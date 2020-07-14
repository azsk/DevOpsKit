Set-StrictMode -Version Latest
class AutoBugLog {
    hidden [ControlStateExtension] $ControlStateExt;
    hidden [SubscriptionContext] $SubscriptionContext;
    hidden [InvocationInfo] $InvocationContext;
    hidden [PSObject] $ControlSettings; 
    hidden [SVTEventContext[]] $ControlResults;
    
    
    AutoBugLog([SubscriptionContext] $subscriptionContext, [InvocationInfo] $invocationContext, [SVTEventContext[]] $ControlResults, [ControlStateExtension] $ControlStateExt) {
        $this.SubscriptionContext = $subscriptionContext;
        $this.InvocationContext = $invocationContext;	
        $this.ControlResults = $ControlResults;		
        $this.ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");
        $this.ControlStateExt = $ControlStateExt               
    }  

    #main function where bug logging takes place 
    hidden [void] LogBugInADO([SVTEventContext[]] $ControlResults, [string] $BugLogParameterValue) {
        #check if user has permissions to log bug for the current resource
        if ($this.CheckPermsForBugLog($ControlResults[0])) {
            #retrieve the project name for the current resource
            $ProjectName = $this.GetProjectForBugLog($ControlResults[0])

            #check if the area and iteration path are valid
            if ([BugLogPathManager]::CheckIfPathIsValid($this.SubscriptionContext.SubscriptionName,$ProjectName,$this.InvocationContext,  $this.ControlSettings.BugLogging.BugLogAreaPath, $this.ControlSettings.BugLogging.BugLogIterationPath)) {
                #Obtain the assignee for the current resource, will be same for all the control failures for this particular resource
                $AssignedTo = $this.GetAssignee($ControlResults[0])
                #Obtain area and iteration paths
                $AreaPath = [BugLogPathManager]::GetAreaPath()
                $IterationPath = [BugLogPathManager]::GetIterationPath()       
	
                #Loop through all the control results for the current resource
                $ControlResults | ForEach-Object {			
					
                    $control = $_;                   

                    #filter controls on basis of whether they are baseline or not depending on the value given in autobuglog flag
                    $LogControlFlag=$false
                    if ($BugLogParameterValue -eq "All") {
                        $LogControlFlag = $true
                    }
                    elseif ($BugLogParameterValue -eq "BaselineControls") {
                        $LogControlFlag = $this.CheckBaselineControl($control.ControlItem.ControlID)				
                    }
                    else {
                        $LogControlFlag = $this.CheckPreviewBaselineControl($control.ControlItem.ControlID)
                    }
			
			
                    if ($LogControlFlag -and ($control.ControlResults[0].VerificationResult -eq "Failed" -or $control.ControlResults[0].VerificationResult -eq "Verify") ) {
				
                        #compute hash of control Id and resource Id	
                        $hash = $this.GetHashedTag($control.ControlItem.Id, $control.ResourceContext.ResourceId)
                        #check if a bug with the computed hash exists
                        $workItem = $this.GetWorkItemByHash($hash, $ProjectName)
                        if ($workItem[0].results.count -gt 0) {
                            #a work item with the hash exists, find if it's state and reactivate if resolved bug
                            $this.ManageActiveAndResolvedBugs($ProjectName, $control, $workItem, $AssignedTo)
                        }
                        else {
                            Write-Host "Determining bugs to log..." -ForegroundColor Cyan

                            #filling the bug template
                            $Title = "[ADOScanner] Control failure - {0} for resource {1} {2}"
                            $Description = "Control failure - {3} for resource {4} {5} </br></br> <b>Control Description: </b> {0} </br></br> <b> Control Result: </b> {6} </br> </br> <b> Rationale:</b> {1} </br></br> <b> Recommendation:</b> {2}"
			
                            $Title = $Title.Replace("{0}", $control.ControlItem.ControlID)
                            $Title = $Title.Replace("{1}", $control.ResourceContext.ResourceTypeName)
                            $Title = $Title.Replace("{2}", $control.ResourceContext.ResourceName)
				
                            $Description = $Description.Replace("{0}", $control.ControlItem.Description)
                            $Description = $Description.Replace("{1}", $control.ControlItem.Rationale)
                            $Description = $Description.Replace("{2}", $control.ControlItem.Recommendation)
                            $Description = $Description.Replace("{3}", $control.ControlItem.ControlID)
                            $Description = $Description.Replace("{4}", $control.ResourceContext.ResourceTypeName)
                            $Description = $Description.Replace("{5}", $control.ResourceContext.ResourceName)
                            $Description = $Description.Replace("{6}", $control.ControlResults[0].VerificationResult)
                            $RunStepsForControl = " </br></br> <b>Control Scan Command:</b> Run:  {0}"
                            $RunStepsForControl = $RunStepsForControl.Replace("{0}", $this.GetControlReproStep($control))
                            $Description+=$RunStepsForControl
				
				
                            #check and append any detailed log and state data for the control failure
                            if ($this.GetDetailedLogForControl($control)) {
                                $Description += "<hr></br><b>Some other details for your reference</b> </br><hr> {7} "
                                $log = $this.GetDetailedLogForControl($control).Replace("\", "\\")
                                $Description = $Description.Replace("{7}", $log)
					
                            }				
                            $Description = $Description.Replace("`"", "'")
                            $Severity = $this.GetSeverity($control.ControlItem.ControlSeverity)		
					
				
                            #function to attempt bug logging
                            $this.AddWorkItem($Title, $Description, $AssignedTo, $AreaPath, $IterationPath, $Severity, $ProjectName, $control, $hash)

                        }
                    }
                }
            }
        }

    }

    #function to get the security command for repro of this bug 
    hidden [string] GetControlReproStep([SVTEventContext []] $ControlResult){
        $StepsForRepro=""
        if ($ControlResult.FeatureName -eq "Organization") {
            $StepsForRepro="Get-AzSKAzureDevOpsSecurityStatus -OrganizationName '{0}' -ControlIds '{1}'"
            $StepsForRepro=$StepsForRepro.Replace("{0}",$ControlResult.ResourceContext.ResourceName)
            $StepsForRepro=$StepsForRepro.Replace("{1}",$ControlResult.ControlItem.ControlID)
        }
        elseif ($ControlResult.ResourceContext.ResourceTypeName -eq "Project") {
            $StepsForRepro="Get-AzSKAzureDevOpsSecurityStatus -OrganizationName '{0}' -ProjectNames '{1}' -ControlIds '{2}'"
            $StepsForRepro=$StepsForRepro.Replace("{0}",$ControlResult.ResourceContext.ResourceGroupName)
            $StepsForRepro=$StepsForRepro.Replace("{1}",$ControlResult.ResourceContext.ResourceName)
            $StepsForRepro=$StepsForRepro.Replace("{2}",$ControlResult.ControlItem.ControlID)
        }
        else {
            $StepsForRepro="Get-AzSKAzureDevOpsSecurityStatus -OrganizationName '{0}' -ProjectNames '{1}' -{2}Names '{3}' -ControlIds '{4}'"
            $StepsForRepro=$StepsForRepro.Replace("{0}",$this.SubscriptionContext.SubscriptionName)
            $StepsForRepro=$StepsForRepro.Replace("{1}",$ControlResult.ResourceContext.ResourceGroupName)
            $StepsForRepro=$StepsForRepro.Replace("{2}",$ControlResult.FeatureName)
            $StepsForRepro=$StepsForRepro.Replace("{3}",$ControlResult.ResourceContext.ResourceName)
            $StepsForRepro=$StepsForRepro.Replace("{4}",$ControlResult.ControlItem.ControlID)
        }
        return $StepsForRepro
    }
    
    #function to retrieve project name according to the resource
    hidden [string] GetProjectForBugLog([SVTEventContext[]] $ControlResult) {
        $ProjectName = ""
        #if resource is the organization, call control state extension to retreive attestation host project
        if ($ControlResult.FeatureName -eq "Organization") {
            $ProjectName = $this.ControlStateExt.GetProject()
        }
        #for all the other resource types, retrieve the project name from the control itself
        elseif ($ControlResult.ResourceContext.ResourceTypeName -eq "Project") {
            $ProjectName = $ControlResult.ResourceContext.ResourceName
        }
        else {
            $ProjectName = $ControlResult.ResourceContext.ResourceGroupName
        }
        return $ProjectName
    }
    
    #function to check if the bug can be logged for the current resource type
    hidden [bool] CheckPermsForBugLog([SVTEventContext[]] $ControlResult) {
        switch -regex ($ControlResult.FeatureName) {
            'Organization' {
                #check if any host project can be retrieved, if not use getHostProject to return the correct behaviour output
                if (!($this.GetHostProject($ControlResult))) {
                    return $false
                }				
            }
            'Project' {
                #check if user is member of PA/PCA
                if (!$this.ControlStateExt.GetControlStatePermission($ControlResult.FeatureName, $ControlResult.ResourceContext.ResourceName)) {
                    Write-Host "`nAuto bug logging denied due to insufficient permissions. Make sure you are a Project Administrator. " -ForegroundColor Red
                    return $false
                }
            }
            'User' {
                #TODO: User controls dont have a project associated with them, can be rectified in future versions
                Write-Host "`nAuto bug logging for user control failures is currently unavailable" -ForegroundColor Red
                return $false
            }
        }
        return $true
    }
    
    #function to retrive the attestation host project for organization level control failures
    hidden [string] GetHostProject([SVTEventContext[]] $ControlResult) {
        $Project = $null
        
        #check if attestationhost project has been specified along with the command
        if ($this.InvocationContext.BoundParameters["AttestationHostProjectName"]) {
            #check if the user has permission to log bug at org level
            if ($this.ControlStateExt.GetControlStatePermission("Organization", "")) { 
                #user is PCA member, set the host project and return the project name
                $this.ControlStateExt.SetProjectInExtForOrg()	
                $Project = $this.ControlStateExt.GetProject()
                return $Project
            }
            #user is not a member of PCA, invalidate the bug log
            else {
                Write-Host "Error: Could not configure host project to log bugs for organization-specific control failures.`nThis may be because: `n  (a) You may not have correct privilege (requires 'Project Collection Administrator').`n  (b) You are logged in using PAT (which is not supported for this currently)." -ForegroundColor Red
                return $null
            }
        }
        
        else {
            #check if the user is a member of PCA after validating that the host project name was not provided 
            if (!$this.ControlStateExt.GetControlStatePermission("Organization", "") ) {
                Write-Host "Error: Auto bug logging denied.`nThis may be because: `n  (a) You are attempting to log bugs for areas you do not have RBAC permission to.`n  (b) You are logged in using PAT (currently not supported for organization and project control's bug logging)." -ForegroundColor Red
                return $null
					  
            }
            else{
                $Project = $this.ControlStateExt.GetProject()
                #user is a PCA member but the project has not been set for org control failures
                if (!$Project) { 
                    Write-Host "`nNo project defined to log bugs for organization-specific controls." -ForegroundColor Red
                    Write-Host "Use the '-AttestationHostProjectName' parameter with this command to configure the project that will host bug logging details for organization level controls.`nRun 'Get-Help -Name Get-AzSKAzureDevOpsSecurityStatus -Full' for more info." -ForegroundColor Yellow
                    return $null
                }
            }
        }
        return $Project

    }

    #function to check any detailed log and state data for the control failure
    hidden [string] GetDetailedLogForControl([SVTEventContext[]] $ControlResult) {
        $log = ""
        #retrieve the message data for control result
        $Messages = $ControlResult.ControlResults[0].Messages

        $Messages | ForEach-Object {
            if ($_.Message) {
                $log += "<b>$($_.Message)</b> </br></br>"
            }
            #check for state data
            if ($_.DataObject) {
                $log += "<hr>"

                #beautify state data for bug template
                $stateData = [Helpers]::ConvertObjectToString($_, $false)
                $stateData=$stateData.Replace("`"","'")
                $stateData = $stateData.Replace("@{", "@{</br>")
                $stateData = $stateData.Replace("@(", "@(</br>")
                $stateData = $stateData.Replace(";", ";</br>")
                $stateData = $stateData.Replace("},", "</br>},</br>")
                $stateData = $stateData.Replace(");", "</br>});</br>")
					
                $log += "$($stateData) </br></br>"	
					
				
            }
        }
        
        #sanitizing input for JSON
        $log = $log.Replace("\", "\\")	

        return $log
    }
    
    #function to retrieve the person to whom the bug will be assigned
    hidden [string] GetAssignee([SVTEventContext[]] $ControlResult) {

        $Assignee = "";
        $ResourceType = $ControlResult.ResourceContext.ResourceTypeName
        $ResourceName = $ControlResult.ResourceContext.ResourceName
        switch -regex ($ResourceType) {
            #assign to the creator of service connection
            'ServiceConnection' {
                $Assignee = $ControlResult.ResourceContext.ResourceDetails.createdBy.uniqueName
            }
            #assign to the creator of agent pool
            'AgentPool' {
                $apiurl = "https://dev.azure.com/{0}/_apis/distributedtask/pools?poolName={1}&api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $ResourceName
                try {
                    $response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
                    $Assignee = $response.createdBy.uniqueName
	
                }
                catch {
                    $Assignee = "";
                }

            }
            #assign to the person who recently triggered the build pipeline, or if the pipeline is empty assign it to the creator
            'Build' {
                $definitionId = ($ControlResult.ResourceContext.ResourceDetails.ResourceLink -split "=")[1]

                try {
                    $apiurl = "https://dev.azure.com/{0}/{1}/_apis/build/builds?definitions={2}&api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $ControlResult.ResourceContext.ResourceGroupName , $definitionId;
				
                    $response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
                    #check for recent trigger
                    if ([Helpers]::CheckMember($response, "requestedBy")) {
                        $Assignee = $response[0].requestedBy.uniqueName
                    }
                    #if no triggers found assign to the creator
                    else {
                        $apiurl = "https://dev.azure.com/{0}/{1}/_apis/build/definitions/{2}?api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $ControlResult.ResourceContext.ResourceGroupName , $definitionId;
                        $response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
                        $Assignee = $response.authoredBy.uniqueName
                    }
                }
                catch {
                    $Assignee = "";
                }	
				
            }
            #assign to the person who recently triggered the release pipeline, or if the pipeline is empty assign it to the creator
            'Release' {
                $definitionId = ($ControlResult.ResourceContext.ResourceId -split "definitions/")[1]
                try {
                    $apiurl = "https://vsrm.dev.azure.com/{0}/{1}/_apis/release/releases?definitionId={2}&api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $ControlResult.ResourceContext.ResourceGroupName , $definitionId;
                    $response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
                    #check for recent trigger
                    if ([Helpers]::CheckMember($response, "modifiedBy")) {
                        $Assignee = $response[0].modifiedBy.uniqueName
                    }
                    #if no triggers found assign to the creator
                    else {
                        $apiurl = "https://vsrm.dev.azure.com/{0}/{1}/_apis/release/definitions/{2}?&api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $ControlResult.ResourceContext.ResourceGroupName , $definitionId;
                        $response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
                        $Assignee = $response.createdBy.uniqueName
                    }
                }
                catch {
                    $Assignee = "";
                }
				


            }
            #assign to the person running the scan, as to reach at this point of code, it is ensured the user is PCA/PA and only they or other PCA
            #PA members can fix the control
            'Organization' {
                $Assignee = [ContextHelper]::GetCurrentSessionUser();
            }
            'Project' {
                $Assignee = [ContextHelper]::GetCurrentSessionUser();

            }
        }
        return $Assignee;

    }

    #function to map severity of the control item
    hidden [string] GetSeverity([string] $ControlSeverity) {
        $Severity = ""
        switch -regex ($ControlSeverity) {
            'Critical' {
                $Severity = "1 - Critical"
            }
            'High' {
                $Severity = "2 - High"
            }
            'Medium' {
                $Severity = "3 - Medium"
            }
            'Low' {
                $Severity = "4 - Low"
            }

        }

        return $Severity
    }
    
    #function to find active bugs and reactivate resolved bugs
    hidden [void] ManageActiveAndResolvedBugs([string]$ProjectName, [SVTEventContext[]] $control, [object] $workItem, [string] $AssignedTo) {
		
		
        $state = ($workItem[0].results.values[0].fields | where { $_.name -eq "State" })
        $id = ($workItem[0].results.values[0].fields | where { $_.name -eq "ID" }).value

        #bug url that redirects user to bug logged in ADO, this is not available via the API response and thus has to be created via the ID of bug
        $bugUrl = "https://{0}.visualstudio.com/{1}/_workitems/edit/{2}" -f $($this.SubscriptionContext.SubscriptionName), $ProjectName , $id

        #TODO : whether the bug is active or resolved, we have to ensure the state of the bug remains active after this function  
        #if a PCA assigns this to a non PCA, the control can never be fixed for org/project controls. to tackle this, reassign it to the original owner PCA
        #do this for both active and resolved bugs, as we need it to be assigned to the actual person who can fix this control
        #for other control results, we need not changed the assignee
        <#    $url = "https://dev.azure.com/{0}/{1}/_apis/wit/workitems/{2}?api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $ProjectName, $id
            $BugTemplate = [ConfigurationManager]::LoadServerConfigFile("TemplateForResolvedBug.json")
            $BugTemplate = $BugTemplate | ConvertTo-Json -Depth 10 
            $BugTemplate=$BugTemplate.Replace("{0}",$AssignedTo)           
            $header = [WebRequestHelper]::GetAuthHeaderFromUriPatch($url)                
            try {
                #TODO: shift all this as a patch request in webrequesthelper class and manage accented characters as well
                $responseObj = Invoke-RestMethod -Uri $url -Method Patch  -ContentType "application/json-patch+json ; charset=utf-8" -Headers $header -Body $BugTemplate
            }
            catch {
                #if the user to whom the bug has been assigneed is not a member of org any more
                if ($_.ErrorDetails.Message -like '*System.AssignedTo*') {
                    $body = $BugTemplate | ConvertFrom-Json
                    #let it remain assigned
                    $body[2].value = "";
                    $body = $body | ConvertTo-Json
                    try {
                        $responseObj = Invoke-RestMethod -Uri $url -Method Patch -ContentType "application/json-patch+json ; charset=utf-8" -Headers $header -Body $body
                        $bugUrl = "https://{0}.visualstudio.com/_workitems/edit/{1}" -f $($this.SubscriptionContext.SubscriptionName), $responseObj.id
                    }
                    catch {
                        Write-Host "Could not reactivate the bug" -ForegroundColor Red
                    }
                }
                else {
                    Write-Host "Could not reactivate the bug" -ForegroundColor Red

                }
            }

        #if the bug state was intially resolved, add in the state data to be referenced later
        if ($state.value -eq "Resolved") {
            $control.ControlResults.AddMessage("Resolved Bug", $bugUrl)
        }
        #if the bug state was initially active
        else {
            $control.ControlResults.AddMessage("Active Bug", $bugUrl)
        }#>


        #change the assignee for resolved bugs only
        if ($state.value -eq "Resolved") {
            $url = "https://dev.azure.com/{0}/{1}/_apis/wit/workitems/{2}?api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $ProjectName, $id
            $BugTemplate = [ConfigurationManager]::LoadServerConfigFile("TemplateForResolvedBug.json")
            $BugTemplate = $BugTemplate | ConvertTo-Json -Depth 10 
            $BugTemplate=$BugTemplate.Replace("{0}",$AssignedTo)           
            $header = [WebRequestHelper]::GetAuthHeaderFromUriPatch($url)                
            try {
                #TODO: shift all this as a patch request in webrequesthelper class and manage accented characters as well
                $responseObj = Invoke-RestMethod -Uri $url -Method Patch  -ContentType "application/json-patch+json ; charset=utf-8" -Headers $header -Body $BugTemplate
                $control.ControlResults.AddMessage("Resolved Bug", $bugUrl)
            }
            catch {
                #if the user to whom the bug has been assigneed is not a member of org any more
                if ($_.ErrorDetails.Message -like '*System.AssignedTo*') {
                    $body = $BugTemplate | ConvertFrom-Json
                    #let it remain assigned
                    $body[2].value = "";
                    $body = $body | ConvertTo-Json
                    try {
                        $responseObj = Invoke-RestMethod -Uri $url -Method Patch -ContentType "application/json-patch+json ; charset=utf-8" -Headers $header -Body $body
                        $control.ControlResults.AddMessage("Resolved Bug", $bugUrl)
                    }
                    catch {
                        Write-Host "Could not reactivate the bug" -ForegroundColor Red
                    }
                }
                else {
                    Write-Host "Could not reactivate the bug" -ForegroundColor Red

                }
            }
        }
        else{
            $control.ControlResults.AddMessage("Active Bug", $bugUrl)
        }
    
    }

    #function to search for existing bugs based on the hash
    hidden [object] GetWorkItemByHash([string] $hash, [string] $ProjectName) {
		
        $url = "https://{0}.almsearch.visualstudio.com/{1}/_apis/search/workItemQueryResults?api-version=5.1-preview" -f $($this.SubscriptionContext.SubscriptionName), $ProjectName;

        #TODO: validate set to allow only two values : ReactiveOldBug and CreateNewBug
        #check for ResolvedBugBehaviour in control settings
        if ($this.ControlSettings.BugLogging.ResolvedBugLogBehaviour -ne "ReactiveOldBug") {
            #new bug is to be logged for every resolved bug, hence search for only new/active bug
            $body = '{"searchText":"{0}","skipResults":0,"takeResults":25,"sortOptions":[],"summarizedHitCountsNeeded":true,"searchFilters":{"Projects":["{1}"],"Work Item Types":["Bug"],"States":["Active","New"]},"filters":[],"includeSuggestions":false}' | ConvertFrom-Json
        }
        else {
            #resolved bug needs to be reactivated, hence search for new/active/resolved bugs
            $body = '{"searchText":"{0}","skipResults":0,"takeResults":25,"sortOptions":[],"summarizedHitCountsNeeded":true,"searchFilters":{"Projects":["{1}"],"Work Item Types":["Bug"],"States":["Active","New","Resolved"]},"filters":[],"includeSuggestions":false}' | ConvertFrom-Json
        }

        #tag to be searched
        $body.searchText = "Tags: " + $hash
        $body.searchFilters.Projects = $ProjectName

        $response = [WebRequestHelper]:: InvokePostWebRequest($url, $body)
    
        return  $response

    }

    #function to compute hash and return the tag
    hidden [string] GetHashedTag([string] $ControlId, [string] $ResourceId) {
        $hashedTag = $null
        $stringToHash = "{0}#{1}"
        #create a hash of resource id and control id
        $stringToHash = $stringToHash.Replace("{0}", $ResourceId)
        $stringToHash = $stringToHash.Replace("{1}", $ControlId)
        #return the bug tag
        $hashedTag = [Helpers]::ComputeHash($stringToHash)
        $hashedTag="ADOScanID: " + $hashedTag.Substring(0, 12)
        return $hashedTag
    }

    hidden [void] AddWorkItem([string] $Title, [string] $Description, [string] $AssignedTo, [string] $AreaPath, [string] $IterationPath, [string]$Severity, [string]$ProjectName, [SVTEventContext[]] $control, [string] $hash) {
		
		
        #logging new bugs
		
        $apiurl = 'https://dev.azure.com/{0}/{1}/_apis/wit/workitems/$bug?api-version=5.1' -f $($this.SubscriptionContext.SubscriptionName), $ProjectName;

        

        $BugTemplate = [ConfigurationManager]::LoadServerConfigFile("TemplateForNewBug.json")
        $BugTemplate = $BugTemplate | ConvertTo-Json -Depth 10 

        $BugTemplate=$BugTemplate.Replace("{0}",$Title)
        $BugTemplate=$BugTemplate.Replace("{1}",$Description)
        $BugTemplate=$BugTemplate.Replace("{2}",$Severity)
        $BugTemplate=$BugTemplate.Replace("{3}",$AreaPath)
        $BugTemplate=$BugTemplate.Replace("{4}",$IterationPath)
        $BugTemplate=$BugTemplate.Replace("{5}",$hash)
        $BugTemplate=$BugTemplate.Replace("{6}",$AssignedTo)

        $responseObj = $null
        $header = [WebRequestHelper]::GetAuthHeaderFromUriPatch($apiurl)

        try {
            $responseObj = Invoke-RestMethod -Uri $apiurl -Method Post -ContentType "application/json-patch+json ; charset=utf-8" -Headers $header -Body $BugTemplate
            $bugUrl = "https://{0}.visualstudio.com/_workitems/edit/{1}" -f $($this.SubscriptionContext.SubscriptionName), $responseObj.id
            $control.ControlResults.AddMessage("New Bug", $bugUrl)
        }
        catch {
            #handle assignee users who are not part of org any more
            if ($_.ErrorDetails.Message -like '*System.AssignedTo*') {
                $BugTemplate = $BugTemplate | ConvertFrom-Json
                $BugTemplate[6].value = "";
                $BugTemplate = $BugTemplate | ConvertTo-Json
                try {
                    $responseObj = Invoke-RestMethod -Uri $apiurl -Method Post -ContentType "application/json-patch+json ; charset=utf-8" -Headers $header -Body $BugTemplate
                    $bugUrl = "https://{0}.visualstudio.com/_workitems/edit/{1}" -f $($this.SubscriptionContext.SubscriptionName), $responseObj.id
                    $control.ControlResults.AddMessage("New Bug", $bugUrl)
                }
                catch {
                    Write-Host "Could not log the bug" -ForegroundColor Red
                }


            }
            #handle the case wherein due to global search area/ iteration paths from different projects passed the checkvalidpath function
            elseif ($_.ErrorDetails.Message -like '*Invalid Area/Iteration id*') {
                Write-Host "Please verify the area and iteration path. They should belong under the same project area." -ForegroundColor Red
            }
            else {
                Write-Host "Could not log the bug" -ForegroundColor Red
            }
        }
		
		
    }

    #the next two functions to check baseline and preview baseline, are duplicate controls that are present in ADOSVTBase as well.
    #they have been added again, due to behaviour of framework, where the file that needs to called in a certain file has to be mentioned
    #above the other file as it is dumped in the memory before the second file. This behaviour will effectively create a deadlock
    #in this case, as we have to create autobuglog object in adosvtbase, making it be declared first in framework and hence the following controls
    #cant be accessed here from adosvtbase.

    #function to check if the current control is a baseline control or not
    hidden [bool] CheckBaselineControl($controlId) {
		if (($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings, "BaselineControls.ResourceTypeControlIdMappingList")) {
			$baselineControl = $this.ControlSettings.BaselineControls.ResourceTypeControlIdMappingList | Where-Object { $_.ControlIds -contains $controlId }
			if (($baselineControl | Measure-Object).Count -gt 0 ) {
				return $true
			}
		}

		if (($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings, "BaselineControls.SubscriptionControlIdList")) {
			$baselineControl = $this.ControlSettings.BaselineControls.SubscriptionControlIdList | Where-Object { $_ -eq $controlId }
			if (($baselineControl | Measure-Object).Count -gt 0 ) {
				return $true
			}
		}
		return $false
    }
    
    #function to check if the current control is a preview baseline control or not
	hidden [bool] CheckPreviewBaselineControl($controlId) {
		if (($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings, "PreviewBaselineControls.ResourceTypeControlIdMappingList")) {
			$PreviewBaselineControls = $this.ControlSettings.PreviewBaselineControls.ResourceTypeControlIdMappingList | Where-Object { $_.ControlIds -contains $controlId }
			if (($PreviewBaselineControls | Measure-Object).Count -gt 0 ) {
				return $true
			}
		}

		if (($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings, "PreviewBaselineControls.SubscriptionControlIdList")) {
			$PreviewBaselineControls = $this.ControlSettings.PreviewBaselineControls.SubscriptionControlIdList | Where-Object { $_ -eq $controlId }
			if (($PreviewBaselineControls | Measure-Object).Count -gt 0 ) {
				return $true
			}
		}
		return $false
	}

    
    
}