Set-StrictMode -Version Latest 
class Release: ADOSVTBase
{   

    hidden [PSObject] $ReleaseObj;
    hidden [string] $ProjectId;
    hidden static [string] $securityNamespaceId = $null;
    hidden static [PSObject] $ReleaseVarNames = @{};
    
    Release([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        [system.gc]::Collect();
        # Get release object
        $apiURL = $this.ResourceContext.ResourceId
        $this.ReleaseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        # Get project id
        $pattern = "https://$($this.SubscriptionContext.SubscriptionName).vsrm.visualstudio.com/(.*?)/_apis/Release/definitions/$($this.ReleaseObj.id)"
        $this.ProjectId = [regex]::match($this.ReleaseObj.url.ToLower(), $pattern.ToLower()).Groups[1].Value
        if([string]::IsNullOrEmpty($this.ProjectId))
        {
            $pattern = "https://vsrm.dev.azure.com/$($this.SubscriptionContext.SubscriptionName)/(.*?)/_apis/Release/definitions/$($this.ReleaseObj.id)"
            $this.ProjectId = [regex]::match($this.ReleaseObj.url.ToLower(), $pattern.ToLower()).Groups[1].Value
        }
        # Get security namespace identifier of current release pipeline.
        if ([string]::IsNullOrEmpty([Release]::SecurityNamespaceId)) {
            $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
            $securityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            [Release]::SecurityNamespaceId = ($securityNamespacesObj | Where-Object { ($_.Name -eq "ReleaseManagement") -and ($_.actions.name -contains "ViewReleaseDefinition")}).namespaceId
    
            $securityNamespacesObj = $null;
        }
    }

    hidden [ControlResult] CheckCredInReleaseVariables([ControlResult] $controlResult)
	{
        if([Helpers]::CheckMember([ConfigurationManager]::GetAzSKSettings(),"SecretsScanToolFolder"))
        {
            $ToolFolderPath =  [ConfigurationManager]::GetAzSKSettings().SecretsScanToolFolder
            $SecretsScanToolName = [ConfigurationManager]::GetAzSKSettings().SecretsScanToolName
            if((-not [string]::IsNullOrEmpty($ToolFolderPath)) -and (Test-Path $ToolFolderPath) -and (-not [string]::IsNullOrEmpty($SecretsScanToolName)))
            {
                $ToolPath = Get-ChildItem -Path $ToolFolderPath -File -Filter $SecretsScanToolName -Recurse 
                if($ToolPath)
                { 
                    if($this.ReleaseObj)
                    {
                        try
                        {
                            $releaseDefFileName = $($this.ResourceContext.ResourceName).Replace(" ","")
                            $releaseDefPath = [Constants]::AzSKTempFolderPath + "\Releases\"+ $releaseDefFileName + "\";
                            if(-not (Test-Path -Path $releaseDefPath))
                            {
                                New-Item -ItemType Directory -Path $releaseDefPath -Force | Out-Null
                            }

                            $this.ReleaseObj | ConvertTo-Json -Depth 5 | Out-File "$releaseDefPath\$releaseDefFileName.json"
                            $searcherPath = Get-ChildItem -Path $($ToolPath.Directory.FullName) -Include "buildsearchers.xml" -Recurse
                            ."$($Toolpath.FullName)" -I $releaseDefPath -S "$($searcherPath.FullName)" -f csv -Ve 1 -O "$releaseDefPath\Scan"    
                            
                            $scanResultPath = Get-ChildItem -Path $releaseDefPath -File -Include "*.csv"
                            
                            if($scanResultPath -and (Test-Path $scanResultPath.FullName))
                            {
                                $credList = Get-Content -Path $scanResultPath.FullName | ConvertFrom-Csv 
                                if(($credList | Measure-Object).Count -gt 0)
                                {
                                    $controlResult.AddMessage("No. of credentials found:" + ($credList | Measure-Object).Count )
                                    $controlResult.AddMessage([VerificationResult]::Failed,"Found credentials in variables")
                                }
                                else {
                                    $controlResult.AddMessage([VerificationResult]::Passed,"No credentials found in variables")
                                }
                            }
                        }
                        catch {
                            #Publish Exception
                            $this.PublishException($_);
                        }
                        finally
                        {
                            #Clean temp folders 
                            Remove-ITem -Path $releaseDefPath -Recurse
                        }
                    }
                }
            }

        }
       else
       {
            try {      
                if([Helpers]::CheckMember($this.ReleaseObj,"variables")) 
                {
                    $varList = @();
                    $noOfCredFound = 0;     
                    $patterns = $this.ControlSettings.Patterns | where {$_.RegexCode -eq "SecretsInRelease"} | Select-Object -Property RegexList;
                    $exclusions = $this.ControlSettings.Release.ExcludeFromSecretsCheck;
                    if(($patterns | Measure-Object).Count -gt 0)
                    {        
                        Get-Member -InputObject $this.ReleaseObj.variables -MemberType Properties | ForEach-Object {
                            if([Helpers]::CheckMember($this.ReleaseObj.variables.$($_.Name),"value") -and  (-not [Helpers]::CheckMember($this.ReleaseObj.variables.$($_.Name),"isSecret")))
                            {
                                $releaseVarName = $_.Name
                                $releaseVarValue = $this.ReleaseObj[0].variables.$releaseVarName.value 
                                <# code to collect stats for var names
                                    if ([Release]::ReleaseVarNames.Keys -contains $releaseVarName)
                                    {
                                            [Release]::ReleaseVarNames.$releaseVarName++
                                    }
                                    else 
                                    {
                                        [Release]::ReleaseVarNames.$releaseVarName = 1
                                    }
                                #>
                                if ($exclusions -notcontains $releaseVarName)
                                {
                                    for ($i = 0; $i -lt $patterns.RegexList.Count; $i++) {
                                        #Note: We are using '-cmatch' here. 
                                        #When we compile the regex, we don't specify ignoreCase flag.
                                        #If regex is in text form, the match will be case-sensitive.
                                        if ($releaseVarValue -cmatch $patterns.RegexList[$i]) { 
                                            $noOfCredFound +=1
                                            $varList += " $releaseVarName";   
                                            break;  
                                        }
                                    }
                                }
                            } 
                        }
                        if($noOfCredFound -gt 0)
                        {
                            $varList = $varList | select -Unique
                            $controlResult.AddMessage([VerificationResult]::Failed,
                            "Found credentials in release definition. Variables name: $varList" );
                        }
                        else {
                            $controlResult.AddMessage([VerificationResult]::Passed, "No credentials found in release definition.");
                        }
                        $patterns = $null;
                    }
                    else 
                    {
                        $controlResult.AddMessage([VerificationResult]::Manual, "Regular expressions for detecting credentials in pipeline variables are not defined in your organization.");    
                    }
                }
                else {
                    $controlResult.AddMessage([VerificationResult]::Passed, "No variables found in release definition.");
                }
            }
            catch {
                $controlResult.AddMessage([VerificationResult]::Manual, "Could not evaluate release definition.");
                $controlResult.AddMessage($_);
            }    

         }
     
        return $controlResult;
    }

    hidden [ControlResult] CheckForInactiveReleases([ControlResult] $controlResult)
    {        
        if($this.ReleaseObj)
        {
            $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery/project/{1}?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName),$this.ProjectId;
            $inputbody =  "{
                'contributionIds': [
                    'ms.vss-releaseManagement-web.releases-list-data-provider'
                ],
                'dataProviderContext': {
                    'properties': {
                        'definitionIds': '$($this.ReleaseObj.id)',
                        'definitionId': '$($this.ReleaseObj.id)',
                        'fetchAllReleases': true,
                        'sourcePage': {
                            'url': 'https://$($this.SubscriptionContext.SubscriptionName).visualstudio.com/$($this.ResourceContext.ResourceGroupName)/_release?_a=releases&view=mine&definitionId=$($this.ReleaseObj.id)',
                            'routeId': 'ms.vss-releaseManagement-web.hub-explorer-3-default-route',
                            'routeValues': {
                                'project': '$($this.ResourceContext.ResourceGroupName)',
                                'viewname': 'hub-explorer-3-view',
                                'controller': 'ContributedPage',
                                'action': 'Execute'
                            }
                        }
                    }
                }
            }"  | ConvertFrom-Json 

        $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);

        if([Helpers]::CheckMember($responseObj,"dataProviders") -and $responseObj.dataProviders.'ms.vss-releaseManagement-web.releases-list-data-provider')
        {

            $releases = $responseObj.dataProviders.'ms.vss-releaseManagement-web.releases-list-data-provider'.releases

            if(($releases | Measure-Object).Count -gt 0 )
            {
                $recentReleases = @()
                 $releases | ForEach-Object { 
                    if([datetime]::Parse( $_.createdOn) -gt (Get-Date).AddDays(-$($this.ControlSettings.Release.ReleaseHistoryPeriodInDays)))
                    {
                        $recentReleases+=$_
                    }
                }
                
                if(($recentReleases | Measure-Object).Count -gt 0 )
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,
                    "Found recent releases triggered within $($this.ControlSettings.Release.ReleaseHistoryPeriodInDays) days");
                }
                else
                {
                    $controlResult.AddMessage([VerificationResult]::Failed,
                    "No recent release history found in last $($this.ControlSettings.Release.ReleaseHistoryPeriodInDays) days");
                }
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                "No release history found.");
            }
           
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                                "No release history found. Release is inactive.");
        }
        $responseObj = $null;
    } 
        return $controlResult
    }

    hidden [ControlResult] CheckInheritedPermissions([ControlResult] $controlResult)
    {
        # Here 'permissionSet' = security namespace identifier, 'token' = project id
        $apiURL = "https://{0}.visualstudio.com/{1}/_admin/_security/index?useApiUrl=true&permissionSet={2}&token={3}%2F{4}&style=min" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $([Release]::SecurityNamespaceId), $($this.ProjectId), $($this.ReleaseObj.id);
        $header = [WebRequestHelper]::GetAuthHeaderFromUri($apiURL);
        $responseObj = Invoke-RestMethod -Method Get -Uri $apiURL -Headers $header -UseBasicParsing
        $responseObj = ($responseObj.SelectNodes("//script") | Where-Object { $_.class -eq "permissions-context" }).InnerXML | ConvertFrom-Json; 
        if($responseObj.inheritPermissions -eq $true)
        {
            $controlResult.AddMessage([VerificationResult]::Failed,"Inherited permissions are enabled on release pipeline.");
        }
        else 
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"Inherited permissions are disabled on release pipeline.");
        }
        $header = $null;
        $responseObj = $null;
        return $controlResult
    }

    hidden [ControlResult] CheckPreDeploymentApproval ([ControlResult] $controlResult)
    {
        $releaseStages = $this.ReleaseObj.environments;# | Where-Object { $this.ControlSettings.Release.RequirePreDeployApprovals -contains $_.name.Trim()}
        if($releaseStages)
        {
            $nonComplaintStages = $releaseStages | ForEach-Object { 
                $releaseStage = $_
                if([Helpers]::CheckMember($releaseStage,"preDeployApprovals.approvals.isAutomated") -and $releaseStage.preDeployApprovals.approvals.isAutomated -eq $true) 
                {
                    return $($releaseStage | Select-Object id,name, @{Name = "Owner"; Expression = {$_.owner.displayName}}) 
                }
            }

            if(($nonComplaintStages | Measure-Object).Count -gt 0)
            {
                $controlResult.AddMessage([VerificationResult]::Failed,"Pre-deployment approvals is not enabled for following release stages in [$($this.ReleaseObj.name)] pipeline.", $nonComplaintStages);
            }
            else 
            {
                $complaintStages = $releaseStages | ForEach-Object {
                    $releaseStage = $_
                    return  $($releaseStage | Select-Object id,name, @{Name = "Owner"; Expression = {$_.owner.displayName}})
                }
                $controlResult.AddMessage([VerificationResult]::Passed,"Pre-deployment approvals is enabled for following release stages.", $complaintStages);
                $complaintStages = $null;
            }
            $nonComplaintStages =$null;
        }
        else
        {
            $otherStages = $this.ReleaseObj.environments | ForEach-Object {
                $releaseStage = $_
                if([Helpers]::CheckMember($releaseStage,"preDeployApprovals.approvals.isAutomated") -and $releaseStage.preDeployApprovals.approvals.isAutomated -ne $true) 
                {
                    return $($releaseStage | Select-Object id,name, @{Name = "Owner"; Expression = {$_.owner.displayName}}) 
                }
            }
            
            if ($otherStages) {
                $controlResult.AddMessage([VerificationResult]::Verify,"No release stage found matching to $($this.ControlSettings.Release.RequirePreDeployApprovals -join ", ") in [$($this.ReleaseObj.name)] pipeline.  Verify that pre-deployment approval is enabled for below found environments.");
                $controlResult.AddMessage($otherStages)
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,"No release stage found matching to $($this.ControlSettings.Release.RequirePreDeployApprovals -join ", ") in [$($this.ReleaseObj.name)] pipeline.  Found pre-deployment approval is enabled for present environments.");
            }
            $otherStages =$null;
        }
        $releaseStages = $null;
        return $controlResult
    }

    hidden [ControlResult] CheckPreDeploymentApprovers ([ControlResult] $controlResult)
    {
        $releaseStages = $this.ReleaseObj.environments | Where-Object { $this.ControlSettings.Release.RequirePreDeployApprovals -contains $_.name.Trim()}
        if($releaseStages)
        {
            $approversList = $releaseStages | ForEach-Object { 
                $releaseStage = $_
                if([Helpers]::CheckMember($releaseStage,"preDeployApprovals.approvals.isAutomated") -and $($releaseStage.preDeployApprovals.approvals.isAutomated -eq $false))
                {
                    if([Helpers]::CheckMember($releaseStage,"preDeployApprovals.approvals.approver"))
                    {
                        return @{ ReleaseStageName= $releaseStage.Name; Approvers = $releaseStage.preDeployApprovals.approvals.approver }
                    }
                }
            }
            if(($approversList | Measure-Object).Count -eq 0)
            {
                $controlResult.AddMessage([VerificationResult]::Failed,"No approvers found. Please ensure that pre-deployment approval is enabled for production release stages");
            }
            else
            {
                $stateData = @();
                $stateData += $approversList;
                $controlResult.AddMessage([VerificationResult]::Verify,"Validate users/groups added as approver within release pipeline.",$stateData);
                $controlResult.SetStateData("List of approvers for each release stage: ", $stateData);
            }
            $approversList = $null;
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"No release stage found matching to $($this.ControlSettings.Release.RequirePreDeployApprovals -join ", ") in [$($this.ReleaseObj.name)] pipeline.");
        }
        $releaseStages = $null;
        return $controlResult
    }

    hidden [ControlResult] CheckRBACAccess ([ControlResult] $controlResult)
    {
        $failMsg = $null
        try
        {
            # This functions is to check users permissions on release definition. Groups' permissions check is not added here.
            $releaseDefinitionPath = $this.ReleaseObj.Path.Trim("\").Replace(" ","+").Replace("\","%2F")
            $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/ReadExplicitIdentitiesJson?__v=5&permissionSetId={2}&permissionSetToken={3}%2F{4}%2F{5}" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $([Release]::SecurityNamespaceId), $($this.ProjectId), $($releaseDefinitionPath) ,$($this.ReleaseObj.id);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            $accessList = @()
            $exemptedUserIdentities = @()
            # exclude release owner
            $exemptedUserIdentities += $this.ReleaseObj.createdBy.id
            if([Helpers]::CheckMember($responseObj,"identities") -and ($responseObj.identities|Measure-Object).Count -gt 0)
            {
                $exemptedUserIdentities += $responseObj.identities | Where-Object { $_.IdentityType -eq "user" }| ForEach-Object {
                    $identity = $_
                    $exemptedIdentity = $this.ControlSettings.Release.ExemptedUserIdentities | Where-Object { $_.Domain -eq $identity.Domain -and $_.DisplayName -eq $identity.DisplayName }
                    if(($exemptedIdentity | Measure-Object).Count -gt 0)
                    {
                        return $identity.TeamFoundationId
                    }
                }

                $accessList += $responseObj.identities | Where-Object { $_.IdentityType -eq "user" } | ForEach-Object {
                    $identity = $_ 
                    if($exemptedUserIdentities -notcontains $identity.TeamFoundationId)
                    {
                        $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/DisplayPermissions?__v=5&tfid={2}&permissionSetId={3}&permissionSetToken={4}%2F{5}%2F{6}" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $($identity.TeamFoundationId) ,$([Release]::SecurityNamespaceId), $($this.ProjectId), $($releaseDefinitionPath), $($this.ReleaseObj.id);
                        $identityPermissions = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                        return @{ IdentityName = $identity.DisplayName; IdentityType = $identity.IdentityType; Permissions = ($identityPermissions.Permissions | Select-Object @{Name="Name"; Expression = {$_.displayName}},@{Name="Permission"; Expression = {$_.permissionDisplayString}}) }
                    }
                }

                $accessList += $responseObj.identities | Where-Object { $_.IdentityType -eq "group" } | ForEach-Object {
                    $identity = $_ 
                    $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/DisplayPermissions?__v=5&tfid={2}&permissionSetId={3}&permissionSetToken={4}%2F{5}%2F{6}" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $($identity.TeamFoundationId) ,$([Release]::SecurityNamespaceId), $($this.ProjectId), $($releaseDefinitionPath), $($this.ReleaseObj.id);
                    $identityPermissions = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                    return @{ IdentityName = $identity.DisplayName; IdentityType = $identity.IdentityType; IsAadGroup = $identity.IsAadGroup ;Permissions = ($identityPermissions.Permissions | Select-Object @{Name="Name"; Expression = {$_.displayName}},@{Name="Permission"; Expression = {$_.permissionDisplayString}}) }
                }
            }
            
            if(($accessList | Measure-Object).Count -ne 0)
            {
                $accessList= $accessList | Select-Object -Property @{Name="IdentityName"; Expression = {$_.IdentityName}},@{Name="IdentityType"; Expression = {$_.IdentityType}},@{Name="Permissions"; Expression = {$_.Permissions}}
                $controlResult.AddMessage([VerificationResult]::Verify,"Validate that the following identities have been provided with minimum RBAC access to [$($this.ResourceContext.ResourceName)] pipeline", $accessList);
                $controlResult.SetStateData("Release pipeline access list: ", $accessList);
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Passed,"No identities have been explicitly provided with RBAC access to [$($this.ResourceContext.ResourceName)] pipeline other than release pipeline owner and default groups");
                $controlResult.AddMessage("List of exempted user identities:",$exemptedUserIdentities)
            }

            $accessList = $null;
            $exemptedUserIdentities =$null;
            $responseObj = $null;
        }
        catch
        {
            $failMsg = $_
        }
        if(![string]::IsNullOrEmpty($failMsg))
        {
            $controlResult.AddMessage([VerificationResult]::Manual,"Unable to fetch release pipeline details. $($failMsg)Please verify from portal all teams/groups are granted minimum required permissions on release definition.");
        }       
        return $controlResult
    }

    hidden [ControlResult] CheckExternalSources([ControlResult] $controlResult)
    {
        if(($this.ReleaseObj | Measure-Object).Count -gt 0)
        {
            if( [Helpers]::CheckMember($this.ReleaseObj[0],"artifacts") -and ($this.ReleaseObj[0].artifacts | Measure-Object).Count -gt 0){
               # $sourcetypes = @();
                $sourcetypes = $this.ReleaseObj[0].artifacts;
                $nonadoresource = $sourcetypes | Where-Object { $_.type -ne 'Git'} ;
               
               if( ($nonadoresource | Measure-Object).Count -gt 0){
                   $nonadoresource = $nonadoresource | Select-Object -Property @{Name="alias"; Expression = {$_.alias}},@{Name="Type"; Expression = {$_.type}}
                   $stateData = @();
                   $stateData += $nonadoresource;
                   $controlResult.AddMessage([VerificationResult]::Verify,"Pipeline contains artifacts from below external sources.", $stateData);    
                   $controlResult.SetStateData("Pipeline contains artifacts from below external sources.", $stateData);  
               }
               else {
                $controlResult.AddMessage([VerificationResult]::Passed,"Pipeline does not contain artifacts from external sources");   
               }
               $sourcetypes = $null;
               $nonadoresource = $null;
           }
           else {
            $controlResult.AddMessage([VerificationResult]::Passed,"Pipeline does not contain any source repositories");   
           } 
        }

        return $controlResult;
    }

    hidden [ControlResult] CheckSettableAtReleaseTime([ControlResult] $controlResult)
	{
      try { 
        
        if([Helpers]::CheckMember($this.ReleaseObj[0],"variables")) 
        {
           $setablevar =@();
           $nonsetablevar =@();
          
           Get-Member -InputObject $this.ReleaseObj[0].variables -MemberType Properties | ForEach-Object {
            if([Helpers]::CheckMember($this.ReleaseObj[0].variables.$($_.Name),"allowOverride") )
            {
                $setablevar +=  $_.Name;
            }
            else {
                $nonsetablevar +=$_.Name;  
            }
           } 
           if(($setablevar | Measure-Object).Count -gt 0){
                $controlResult.AddMessage([VerificationResult]::Verify,"The below variables are settable at release time: ",$setablevar);
                $controlResult.SetStateData("Variables settable at release time: ", $setablevar);
                if ($nonsetablevar) {
                    $controlResult.AddMessage("The below variables are not settable at release time: ",$nonsetablevar);      
                } 
           }
           else 
           {
                $controlResult.AddMessage([VerificationResult]::Passed, "No variables were found in the release pipeline that are settable at release time.");   
           }
                 
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Passed,"No variables were found in the release pipeline");   
        }
       }  
       catch {
           $controlResult.AddMessage([VerificationResult]::Manual,"Could not fetch release pipeline variables.");   
       }
     return $controlResult;
    }

    hidden [ControlResult] CheckSettableAtReleaseTimeForURL([ControlResult] $controlResult) 
    {
        try 
        { 
            if ([Helpers]::CheckMember($this.ReleaseObj[0], "variables")) 
            {
                $settableURLVars = @();
                $count = 0;
                $patterns = $this.ControlSettings.Patterns | where {$_.RegexCode -eq "URLs"} | Select-Object -Property RegexList;

                if(($patterns | Measure-Object).Count -gt 0){                
                    Get-Member -InputObject $this.ReleaseObj[0].variables -MemberType Properties | ForEach-Object {
                        if ([Helpers]::CheckMember($this.ReleaseObj[0].variables.$($_.Name), "allowOverride") )
                        {
                            $varName = $_.Name;
                            $varValue = $this.ReleaseObj[0].variables.$($varName).value;
                            for ($i = 0; $i -lt $patterns.RegexList.Count; $i++) {
                                if ($varValue -match $patterns.RegexList[$i]) { 
                                    $count +=1
                                    $settableURLVars += @( [PSCustomObject] @{ Name = $varName; Value = $varValue } )  
                                    break  
                                }
                            }
                        }
                    } 
                    if ($count -gt 0) 
                    {
                        $controlResult.AddMessage([VerificationResult]::Failed, "Found variables that are settable at release time and contain URL value: ", $settableURLVars);
                        $controlResult.SetStateData("List of variables settable at release time and containing URL value: ", $settableURLVars);
                    }
                    else {
                        $controlResult.AddMessage([VerificationResult]::Passed, "No variables were found in the release pipeline that are settable at release time and contain URL value.");   
                    }
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Manual, "Regular expressions for detecting URLs in pipeline variables are not defined in your organization.");    
                }
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "No variables were found in the release pipeline.");   
            }
        }  
        catch 
        {
            $controlResult.AddMessage([VerificationResult]::Manual, "Could not fetch variables of the release pipeline.");   
        }
        return $controlResult;
    }
    hidden [ControlResult] CheckTaskGroupEditPermission([ControlResult] $controlResult)
    {
        $taskGroups = @();

        #fetch all envs of pipeline.
        $releaseEnv = $this.ReleaseObj[0].environments

        #filter task groups in each such env.
        $releaseEnv | ForEach-Object {
            #Task groups have type 'metaTask' whereas individual tasks have type 'task'
            if(([Helpers]::CheckMember($_.deployPhases[0].workflowTasks,"definitiontype")) -and ($_.deployPhases[0].workflowTasks.definitiontype -eq 'metaTask'))
            {
                $taskGroups += $_.deployPhases[0].workflowTasks
            }
        } 

        #Filtering unique task groups used in release pipeline.
        $taskGroups = $taskGroups | Sort-Object -Property taskId -Unique

        $editableTaskGroups = @();
        
        if(($taskGroups | Measure-Object).Count -gt 0)
        {   
            $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName)
            $projectName = $this.ResourceContext.ResourceGroupName
            
            try
            {
                $taskGroups | ForEach-Object {
                    $taskGrpId = $_.taskId
                    $taskGrpURL="https://{0}.visualstudio.com/{1}/_taskgroup/{2}" -f $($this.SubscriptionContext.SubscriptionName), $($projectName), $($taskGrpId)
                    $permissionSetToken = "$($this.projectId)/$taskGrpId"
                    
                    #permissionSetId = 'f6a4de49-dbe2-4704-86dc-f8ec1a294436' is the std. namespaceID. Refer: https://docs.microsoft.com/en-us/azure/devops/organizations/security/manage-tokens-namespaces?view=azure-devops#namespaces-and-their-ids
                    $inputbody = "{
                        'contributionIds': [
                            'ms.vss-admin-web.security-view-members-data-provider'
                        ],
                        'dataProviderContext': {
                            'properties': {
                                'permissionSetId': 'f6a4de49-dbe2-4704-86dc-f8ec1a294436',
                                'permissionSetToken': '$permissionSetToken',
                                'sourcePage': {
                                    'url': '$taskGrpURL',
                                    'routeId':'ms.vss-distributed-task.hub-task-group-edit-route',
                                    'routeValues': {
                                        'project': '$projectName',
                                        'taskGroupId': '$taskGrpId',
                                        'controller':'Apps',
                                        'action':'ContributedHub',
                                        'viewname':'task-groups-edit'
                                    }
                                }
                            }
                        }
                    }" | ConvertFrom-Json

                    # This web request is made to fetch all identities having access to task group - it will contain descriptor for each of them. 
                    # We need contributor's descriptor to fetch its permissions on task group.
                    $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);

                    #Filtering out Contributors group.
                    if([Helpers]::CheckMember($responseObj[0],"dataProviders") -and ($responseObj[0].dataProviders.'ms.vss-admin-web.security-view-members-data-provider') -and ([Helpers]::CheckMember($responseObj[0].dataProviders.'ms.vss-admin-web.security-view-members-data-provider',"identities")))
                    {

                        $contributorObj = $responseObj[0].dataProviders.'ms.vss-admin-web.security-view-members-data-provider'.identities | Where-Object {$_.subjectKind -eq 'group' -and $_.principalName -eq "[$projectName]\Contributors"}
                        # $contributorObj would be null if none of its permissions are set i.e. all perms are 'Not Set'.
                        if($contributorObj)
                        {
                            $contributorInputbody = "{
                                'contributionIds': [
                                    'ms.vss-admin-web.security-view-permissions-data-provider'
                                ],
                                'dataProviderContext': {
                                    'properties': {
                                        'subjectDescriptor': '$($contributorObj.descriptor)',
                                        'permissionSetId': 'f6a4de49-dbe2-4704-86dc-f8ec1a294436',
                                        'permissionSetToken': '$permissionSetToken',
                                        'accountName': '$(($contributorObj.principalName).Replace('\','\\'))',
                                        'sourcePage': {
                                            'url': '$taskGrpURL',
                                            'routeId':'ms.vss-distributed-task.hub-task-group-edit-route',
                                            'routeValues': {
                                                'project': '$projectName',
                                                'taskGroupId': '$taskGrpId',
                                                'controller':'Apps',
                                                'action':'ContributedHub',
                                                'viewname':'task-groups-edit'
                                            }
                                        }
                                    }
                                }
                            }" | ConvertFrom-Json
                        
                            #Web request to fetch RBAC permissions of Contributors group on task group.
                            $contributorResponseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$contributorInputbody);
                            $contributorRBACObj = $contributorResponseObj[0].dataProviders.'ms.vss-admin-web.security-view-permissions-data-provider'.subjectPermissions
                            $editPerms = $contributorRBACObj | Where-Object {$_.displayName -eq 'Edit task group'}
                            #effectivePermissionValue equals to 1 implies edit task group perms is set to 'Allow'. Its value is 3 if it is set to Allow (inherited). This param is not available if it is 'Not Set'.
                            if([Helpers]::CheckMember($editPerms,"effectivePermissionValue") -and (($editPerms.effectivePermissionValue -eq 1) -or ($editPerms.effectivePermissionValue -eq 3)))
                            {
                                $editableTaskGroups += $_.name
                            }
                        }
                    }
                }
                if(($editableTaskGroups | Measure-Object).Count -gt 0)
                {
                    $controlResult.AddMessage([VerificationResult]::Failed,"Contributors have edit permissions on the below task groups used in release definition: ", $editableTaskGroups);
                    $controlResult.SetStateData("List of task groups used in release definition that contributors can edit: ", $editableTaskGroups); 
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,"Contributors do not have edit permissions on any task groups used in release definition.");    
                }
            }
            catch
            {
                $controlResult.AddMessage([VerificationResult]::Error,"Could not fetch the RBAC details of task groups used in the pipeline.");
            }

        }
        else 
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"No task groups found in release definition.");
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckVariableGroupEditPermission([ControlResult] $controlResult)
    {
        
        $varGrps = @();
        $projectName = $this.ResourceContext.ResourceGroupName
        $editableVarGrps = @();

        #add var groups scoped at release scope.
        if((($this.ReleaseObj[0].variableGroups) | Measure-Object).Count -gt 0)
        {
            $varGrps += $this.ReleaseObj[0].variableGroups
        }

        # Each release pipeline has atleast 1 env.
        $envCount = ($this.ReleaseObj[0].environments).Count

        for($i=0; $i -lt $envCount; $i++)
        {
            if((($this.ReleaseObj[0].environments[$i].variableGroups) | Measure-Object).Count -gt 0)
            {
                $varGrps += $this.ReleaseObj[0].environments[$i].variableGroups
            }
        }
        
        if(($varGrps | Measure-Object).Count -gt 0)
        {
            try
            {   
                $varGrps | ForEach-Object{
                    $url = 'https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.variablegroup/roleassignments/resources/{1}%24{2}?api-version=6.1-preview.1' -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $($_);
                    $responseObj = [WebRequestHelper]::InvokeGetWebRequest($url);
                    if(($responseObj | Measure-Object).Count -gt 0)
                    {
                        $contributorsObj = $responseObj | Where-Object {$_.identity.uniqueName -eq "[$projectName]\Contributors"}
                        if((-not [string]::IsNullOrEmpty($contributorsObj)) -and ($contributorsObj.role.name -ne 'Reader')){
                            
                            #Release object doesn't capture variable group name. We need to explicitly look up for its name via a separate web request.
                            $varGrpURL = ("https://{0}.visualstudio.com/{1}/_apis/distributedtask/variablegroups/{2}") -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $($_);
                            $varGrpObj = [WebRequestHelper]::InvokeGetWebRequest($varGrpURL);
                            
                            $editableVarGrps += $varGrpObj[0].name
                        } 
                    }
                }

                if(($editableVarGrps | Measure-Object).Count -gt 0)
                {
                    $controlResult.AddMessage([VerificationResult]::Failed,"Contributors have edit permissions on the below variable groups used in release definition: ", $editableVarGrps);
                    $controlResult.SetStateData("List of variable groups used in release definition that contributors can edit: ", $editableVarGrps); 
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,"Contributors do not have edit permissions on any variable groups used in release definition.");    
                }
            }
            catch
            {
                $controlResult.AddMessage([VerificationResult]::Error,"Could not fetch the RBAC details of variable groups used in the pipeline.");
            }
             
        }
        else 
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"No variable groups found in release definition.");
        }

        return $controlResult
    }
}