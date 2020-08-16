Set-StrictMode -Version Latest 
class Project: ADOSVTBase
{    
    [PSObject] $PipelineSettingsObj = $null

    Project([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        $this.GetPipelineSettingsObj()
    }

    GetPipelineSettingsObj()
    {
        $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
        #TODO: testing adding below line commenting above line
        #$apiURL = "https://dev.azure.com/{0}/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);

        $orgUrl = "https://{0}.visualstudio.com" -f $($this.SubscriptionContext.SubscriptionName);
        $projectName = $this.ResourceContext.ResourceName;
        #$inputbody =  "{'contributionIds':['ms.vss-org-web.collection-admin-policy-data-provider'],'context':{'properties':{'sourcePage':{'url':'$orgUrl/_settings/policy','routeId':'ms.vss-admin-web.collection-admin-hub-route','routeValues':{'adminPivot':'policy','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
        $inputbody = "{'contributionIds':['ms.vss-build-web.pipelines-general-settings-data-provider'],'dataProviderContext':{'properties':{'sourcePage':{'url':'$orgUrl/$projectName/_settings/settings','routeId':'ms.vss-admin-web.project-admin-hub-route','routeValues':{'project':'$projectName','adminPivot':'settings','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
    
        $responseObj = $null
        try{
            $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);
        }
        catch{
            #Write-Host "Pipeline settings for the project [$projectName] can not be fetched."
        }
    
        if($responseObj){
            if([Helpers]::CheckMember($responseObj,"dataProviders"))
            {
                try {
                    if($responseObj.dataProviders.'ms.vss-build-web.pipelines-general-settings-data-provider'){
                        $this.PipelineSettingsObj = $responseObj.dataProviders.'ms.vss-build-web.pipelines-general-settings-data-provider'
                    } 
                }
                catch {
                    #Write-Host "Pipeline settings for the project [$projectName] can not be fetched."
                }   
            }
        }
    }

    hidden [ControlResult] CheckPublicProjects([ControlResult] $controlResult)
	{
        $apiURL = $this.ResourceContext.ResourceId;
        try 
        {
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            if([Helpers]::CheckMember($responseObj,"visibility"))
            {
                $visibility = $responseObj.visibility;
                if(($visibility -eq "private") -or ($visibility -eq "organization"))
                {
                    $controlResult.AddMessage([VerificationResult]::Passed, "Project visibility is set to '$visibility'."); 

                }
                else # For orgs with public projects allowed, this control needs to be attested by the project admins. 
                {
                    $controlResult.AddMessage([VerificationResult]::Failed, "Project visibility is set to '$visibility'.");
                }
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Error,"Project visibility details could not be fetched.");
            }
        }
        catch 
        {
            $controlResult.AddMessage([VerificationResult]::Error,"Project visibility details could not be fetched.");
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckBadgeAnonAccess([ControlResult] $controlResult)
    {
       if($this.PipelineSettingsObj)
       {
            
            if($this.PipelineSettingsObj.statusBadgesArePrivate.enabled -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Anonymous access to status badge API is disabled. It is set as '$($this.PipelineSettingsObj.statusBadgesArePrivate.orgEnabled)' at organization scope.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Failed, "Anonymous access to status badge API is enabled. It is set as '$($this.PipelineSettingsObj.statusBadgesArePrivate.orgEnabled)' at organization scope.");
            }       
       }
       else{
            $controlResult.AddMessage([VerificationResult]::Manual, "Pipeline settings could not be fetched due to insufficient permissions at project scope.");
       }
        return $controlResult
    }

    hidden [ControlResult] CheckSetQueueTime([ControlResult] $controlResult)
    {
       if($this.PipelineSettingsObj)
       {
            
            if($this.PipelineSettingsObj.enforceSettableVar.enabled -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Only limited variables can be set at queue time. It is set as '$($this.PipelineSettingsObj.enforceSettableVar.orgEnabled)' at organization scope.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Failed, "All variables can be set at queue time. It is set as '$($this.PipelineSettingsObj.enforceSettableVar.orgEnabled)' at organization scope.");
            }       
       }
       else{
            $controlResult.AddMessage([VerificationResult]::Manual, "Pipeline settings could not be fetched due to insufficient permissions at project scope.");
       }
        return $controlResult
    }

    hidden [ControlResult] CheckJobAuthZScope([ControlResult] $controlResult)
    {
        if($this.PipelineSettingsObj)
        {
            $orgLevelScope = $this.PipelineSettingsObj.enforceJobAuthScope.orgEnabled;
            $prjLevelScope = $this.PipelineSettingsObj.enforceJobAuthScope.enabled;

            if($prjLevelScope -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Job authorization scope is limited to current project for non-release pipelines.");
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Failed, "Job authorization scope is set to project collection for non-release pipelines.");
            }     
            
            if($orgLevelScope -eq $true )
            {
                $controlResult.AddMessage("This setting is enabled (limited to current project) at organization level.");
            }
            else
            {
                $controlResult.AddMessage("This setting is disabled (set to project collection) at organization level.");
            }     
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch project pipeline settings.");
        }       
        return $controlResult
    }

    hidden [ControlResult] CheckJobAuthZReleaseScope([ControlResult] $controlResult)
    {
        if($this.PipelineSettingsObj)
        {
            $orgLevelScope = $this.PipelineSettingsObj.enforceJobAuthScopeForReleases.orgEnabled;
            $prjLevelScope = $this.PipelineSettingsObj.enforceJobAuthScopeForReleases.enabled;

            if($prjLevelScope -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Job authorization scope is limited to current project for release pipelines.");
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Failed, "Job authorization scope is set to project collection for release pipelines.");
            }     
            
            if($orgLevelScope -eq $true )
            {
                $controlResult.AddMessage("This setting is enabled (limited to current project) at organization level.");
            }
            else
            {
                $controlResult.AddMessage("This setting is disabled (set to project collection) at organization level.");
            }     
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch project pipeline settings.");
        }       
        return $controlResult
    }

    hidden [ControlResult] CheckAuthZRepoScope([ControlResult] $controlResult)
    {
        if($this.PipelineSettingsObj)
        {
            $orgLevelScope = $this.PipelineSettingsObj.enforceReferencedRepoScopedToken.orgEnabled;
            $prjLevelScope = $this.PipelineSettingsObj.enforceReferencedRepoScopedToken.enabled;

            if($prjLevelScope -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Job authorization scope of pipelines is limited to explicitly referenced Azure DevOps repositories.");
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Failed, "Job authorization scope of pipelines is set to all Azure DevOps repositories in the authorized projects.");
            }     
            
            if($orgLevelScope -eq $true )
            {
                $controlResult.AddMessage("This setting is enabled (limited to explicitly referenced Azure DevOps repositories) at organization level.");
            }
            else
            {
                $controlResult.AddMessage("This setting is disabled (set to all Azure DevOps repositories in authorized projects) at organization level.");
            }     
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch project pipeline settings.");
        }       
        return $controlResult
    }

    hidden [ControlResult] CheckPublishMetadata([ControlResult] $controlResult)
    {
       if($this.PipelineSettingsObj)
       {
            
            if($this.PipelineSettingsObj.publishPipelineMetadata.enabled -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Publishing metadata from pipeline is enabled. It is set as '$($this.PipelineSettingsObj.publishPipelineMetadata.orgEnabled)' at organization scope.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Failed, "Publishing metadata from pipeline is disabled. It is set as '$($this.PipelineSettingsObj.publishPipelineMetadata.orgEnabled)' at organization scope.");
            }       
       }
       else{
            $controlResult.AddMessage([VerificationResult]::Manual, "Pipeline settings could not be fetched due to insufficient permissions at project scope.");
       }
        return $controlResult
    }

    hidden [ControlResult] CheckRBACAccess([ControlResult] $controlResult)
    {
        $url = 'https://dev.azure.com/{0}/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1' -f $($this.SubscriptionContext.SubscriptionName);
        $inputbody = '{"contributionIds":["ms.vss-admin-web.org-admin-groups-data-provider"],"dataProviderContext":{"properties":{"sourcePage":{"url":"","routeId":"ms.vss-admin-web.project-admin-hub-route","routeValues":{"project":"","adminPivot":"permissions","controller":"ContributedPage","action":"Execute"}}}}}' | ConvertFrom-Json
        $inputbody.dataProviderContext.properties.sourcePage.url = "https://dev.azure.com/$($this.SubscriptionContext.SubscriptionName)/$($this.ResourceContext.ResourceName)/_settings/permissions";
        $inputbody.dataProviderContext.properties.sourcePage.routeValues.Project =$this.ResourceContext.ResourceName;

        $groupsObj = [WebRequestHelper]::InvokePostWebRequest($url,$inputbody); 

        $Allgroups =  @()
         $groupsObj.dataProviders."ms.vss-admin-web.org-admin-groups-data-provider".identities  | ForEach-Object {
            $Allgroups += $_;
        }  

        $descrurl ='https://vssps.dev.azure.com/{0}/_apis/graph/descriptors/{1}?api-version=5.0-preview.1' -f $($this.SubscriptionContext.SubscriptionName), $this.ResourceContext.ResourceId.split('/')[-1];
        $descr = [WebRequestHelper]::InvokeGetWebRequest($descrurl);

        $apiURL = "https://vssps.dev.azure.com/{0}/_apis/Graph/Users?scopeDescriptor={1}" -f $($this.SubscriptionContext.SubscriptionName), $descr[0];
        $usersObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

        <# $Users =  @()
        $usersObj[0].items | ForEach-Object { 
                $Users+= $_   
        } #>

        $groups = ($Allgroups | Select-Object -Property @{Name="Name"; Expression = {$_.displayName}},@{Name="Description"; Expression = {$_.description}});
        
        $UsersNames = ($usersObj | Select-Object -Property @{Name="Name"; Expression = {$_.displayName}},@{Name="mailAddress"; Expression = {$_.mailAddress}})

        if ( (($groups | Measure-Object).Count -gt 0) -or (($UsersNames | Measure-Object).Count -gt 0)) {
            $controlResult.AddMessage([VerificationResult]::Verify, "Verify users and groups present on project");

            $controlResult.AddMessage("Verify groups has access on project", $groups); 
            $controlResult.AddMessage("Verify users has access on project", $UsersNames); 
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,  "No users or groups found");
        }

        return $controlResult
    }

    hidden [ControlResult] JustifyGroupMember([ControlResult] $controlResult)
    {   
        $grpmember = @();   
        $url = 'https://dev.azure.com/{0}/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1' -f $($this.SubscriptionContext.SubscriptionName);
        $inputbody = '{"contributionIds":["ms.vss-admin-web.org-admin-groups-data-provider"],"dataProviderContext":{"properties":{"sourcePage":{"url":"","routeId":"ms.vss-admin-web.project-admin-hub-route","routeValues":{"project":"","adminPivot":"permissions","controller":"ContributedPage","action":"Execute"}}}}}' | ConvertFrom-Json
        $inputbody.dataProviderContext.properties.sourcePage.url = "https://dev.azure.com/$($this.SubscriptionContext.SubscriptionName)/$($this.ResourceContext.ResourceName)/_settings/permissions";
        $inputbody.dataProviderContext.properties.sourcePage.routeValues.Project =$this.ResourceContext.ResourceName;

        $groupsObj = [WebRequestHelper]::InvokePostWebRequest($url,$inputbody); 

        $groups =  @()
         $groupsObj.dataProviders."ms.vss-admin-web.org-admin-groups-data-provider".identities  | ForEach-Object {
            $groups += $_;
        } 
         
        $apiURL = "https://dev.azure.com/{0}/_apis/Contribution/HierarchyQuery?api-version=5.0-preview" -f $($this.SubscriptionContext.SubscriptionName);

        $membercount =0;
        Foreach ($group in $groups){
            $groupmember = @();
         $descriptor = $group.descriptor;
         $inputbody =  '{"contributionIds":["ms.vss-admin-web.org-admin-members-data-provider"],"dataProviderContext":{"properties":{"subjectDescriptor":"","sourcePage":{"url":"","routeId":"ms.vss-admin-web.project-admin-hub-route","routeValues":{"project":"","adminPivot":"permissions","controller":"ContributedPage","action":"Execute"}}}}}' | ConvertFrom-Json
                       
         $inputbody.dataProviderContext.properties.subjectDescriptor = $descriptor;
         $inputbody.dataProviderContext.properties.sourcePage.url = "https://dev.azure.com/$($this.SubscriptionContext.SubscriptionName)/$($this.ResourceContext.ResourceName)/_settings/permissions?subjectDescriptor=$($descriptor)";
         $inputbody.dataProviderContext.properties.sourcePage.routeValues.Project =$this.ResourceContext.ResourceName;

         $usersObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);

         $usersObj.dataProviders."ms.vss-admin-web.org-admin-members-data-provider".identities  | ForEach-Object {
            $groupmember += $_;
        }  

        $grpmember = ($groupmember | Select-Object -Property @{Name="Name"; Expression = {$_.displayName}},@{Name="mailAddress"; Expression = {$_.mailAddress}});
        if ($grpmember -ne $null) {
            $membercount= $membercount + 1
            $controlResult.AddMessage("Verify below members of the group: '$($group.principalname)', Description: $($group.description)", $grpmember); 
        }

        }

        if ( $membercount  -gt 0)  {
            $controlResult.AddMessage([VerificationResult]::Verify, "Verify members of groups present on project");
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,  "No users or groups found");
        }

        return $controlResult
    }

    hidden [ControlResult] CheckMinPACount([ControlResult] $controlResult)
    {
        $TotalPAMembers=0
        $PAMembers = @()
        $PAMembers += [AdministratorHelper]::GetTotalPAMembers($this.SubscriptionContext.SubscriptionName,$this.ResourceContext.ResourceName)
        $TotalPAMembers = ($PAMembers | Measure-Object).Count
        $PAMembers = $PAMembers | Select-Object displayName,mailAddress
        $controlResult.AddMessage("There are a total of $TotalPAMembers Project Administrators in your project.")
        if($TotalPAMembers -lt $this.ControlSettings.Project.MinPAMembersPermissible){
            $controlResult.AddMessage([VerificationResult]::Failed,"Number of administrators configured are less than the minimum required administrators count : $($this.ControlSettings.Project.MinPAMembersPermissible).");
        }
        else{
            $controlResult.AddMessage([VerificationResult]::Passed,"Number of administrators configured are more than the minimum required administrators count : $($this.ControlSettings.Project.MinPAMembersPermissible).");
        }
        if($TotalPAMembers -gt 0){
            $controlResult.AddMessage("Verify the following Project Administrators : ",$PAMembers)
            $controlResult.SetStateData("List of Project Administrators : ",$PAMembers)
        }    
        return $controlResult
    }

    hidden [ControlResult] CheckMaxPACount([ControlResult] $controlResult)
    {
        
        $TotalPAMembers=0
        $PAMembers = @()
        $PAMembers += [AdministratorHelper]::GetTotalPAMembers($this.SubscriptionContext.SubscriptionName,$this.ResourceContext.ResourceName)
        $TotalPAMembers = ($PAMembers | Measure-Object).Count
        $PAMembers = $PAMembers | Select-Object displayName,mailAddress
        $controlResult.AddMessage("There are a total of $TotalPAMembers Project Administrators in your project.")
        if($TotalPAMembers -gt $this.ControlSettings.Project.MaxPAMembersPermissible){
            $controlResult.AddMessage([VerificationResult]::Failed,"Number of administrators configured are more than the approved limit : $($this.ControlSettings.Project.MaxPAMembersPermissible).");
        }
        else{
            $controlResult.AddMessage([VerificationResult]::Passed,"Number of administrators configured are within than the approved limit : $($this.ControlSettings.Project.MaxPAMembersPermissible).");
        }
        if($TotalPAMembers -gt 0){
            $controlResult.AddMessage("Verify the following Project Administrators : ",$PAMembers)
            $controlResult.SetStateData("List of Project Administrators : ",$PAMembers)
        }         
        return $controlResult
    }

    hidden [ControlResult] CheckSCALTForAdminMembers([ControlResult] $controlResult)
    {
        try
        {
            if(($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings, "Project.GroupsToCheckForSCAltMembers"))
            {

                $adminGroupNames = $this.ControlSettings.Project.GroupsToCheckForSCAltMembers;
                if (($adminGroupNames | Measure-Object).Count -gt 0) 
                {
                    #api call to get descriptor for organization groups. This will be used to fetch membership of individual groups later.
                    $url = 'https://dev.azure.com/{0}/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1' -f $($this.SubscriptionContext.SubscriptionName);
                    $inputbody = '{"contributionIds":["ms.vss-admin-web.org-admin-groups-data-provider"],"dataProviderContext":{"properties":{"sourcePage":{"url":"","routeId":"ms.vss-admin-web.project-admin-hub-route","routeValues":{"project":"","adminPivot":"permissions","controller":"ContributedPage","action":"Execute"}}}}}' | ConvertFrom-Json
                    $inputbody.dataProviderContext.properties.sourcePage.url = "https://dev.azure.com/$($this.SubscriptionContext.SubscriptionName)/$($this.ResourceContext.ResourceName)/_settings/permissions";
                    $inputbody.dataProviderContext.properties.sourcePage.routeValues.Project = $this.ResourceContext.ResourceName;
        
                    $response = [WebRequestHelper]::InvokePostWebRequest($url, $inputbody);    
                    
                    if ($response -and [Helpers]::CheckMember($response[0], "dataProviders") -and $response[0].dataProviders."ms.vss-admin-web.org-admin-groups-data-provider") 
                    {
                        $adminGroups = @();
                        $adminGroups += $response.dataProviders."ms.vss-admin-web.org-admin-groups-data-provider".identities | where { $_.displayName -in $adminGroupNames }
                        
                        if(($adminGroups | Measure-Object).Count -gt 0)
                        {
                            #global variable to track admin members across all admin groups
                            $allAdminMembers = @();
                            
                            for ($i = 0; $i -lt $adminGroups.Count; $i++) 
                            {
                                # [AdministratorHelper]::AllPAMembers is a static variable. Always needs ro be initialized. At the end of each iteration, it will be populated with members of that particular admin group.
                                [AdministratorHelper]::AllPAMembers = @();
                                # Helper function to fetch flattened out list of group members.
                                [AdministratorHelper]::FindPAMembers($adminGroups[$i].descriptor,  $this.SubscriptionContext.SubscriptionName, $this.ResourceContext.ResourceName)
                                
                                $groupMembers = @();
                                # Add the members of current group to this temp variable.
                                $groupMembers += [AdministratorHelper]::AllPAMembers
                                # Create a custom object to append members of current group with the group name. Each of these custom object is added to the global variable $allAdminMembers for further analysis of SC-Alt detection.
                                $groupMembers | ForEach-Object {$allAdminMembers += @( [PSCustomObject] @{ name = $_.displayName; mailAddress = $_.mailAddress; groupName = $adminGroups[$i].displayName } )} 
                            }
                            
                            # clearing cached value in [AdministratorHelper]::AllPAMembers as it can be used in attestation later and might have incorrect group loaded.
                            [AdministratorHelper]::AllPAMembers = @();

                            if(($allAdminMembers | Measure-Object).Count -gt 0)
                            {
                                if([Helpers]::CheckMember($this.ControlSettings, "AlernateAccountRegularExpressionForOrg")){
                                    $matchToSCAlt = $this.ControlSettings.AlernateAccountRegularExpressionForOrg
                                    #currently SC-ALT regex is a singleton expression. In case we have multiple regex - we need to make the controlsetting entry as an array and accordingly loop the regex here.
                                    if (-not [string]::IsNullOrEmpty($matchToSCAlt)) 
                                    {
                                        $nonSCMembers = @();
                                        $nonSCMembers += $allAdminMembers | Where-Object { $_.mailAddress -notmatch $matchToSCAlt }  
                                        if (($nonSCMembers | Measure-Object).Count -gt 0) 
                                        {
                                            $nonSCMembers = $nonSCMembers | Select-Object name,mailAddress,groupName
                                            $stateData = @();
                                            $stateData += $nonSCMembers
                                            $controlResult.AddMessage([VerificationResult]::Verify, "Review the users having admin privileges with non SC-Alt accounts : ", $stateData); 
                                            $controlResult.SetStateData("List of users having admin privileges with non SC-Alt accounts : ", $stateData); 
                                        }
                                        else 
                                        {
                                            $controlResult.AddMessage([VerificationResult]::Passed, "No users have admin privileges with non SC-Alt accounts.");
                                        }
                                    }
                                    else {
                                        $controlResult.AddMessage([VerificationResult]::Manual, "Regular expressions for detecting SC-Alt account is not defined in the organization.");
                                    }
                                }
                                else{
                                    $controlResult.AddMessage([VerificationResult]::Error, "Regular expressions for detecting SC-Alt account is not defined in the organization. Please update your ControlSettings.json as per the latest AzSK.AzureDevOps PowerShell module.");
                                }   
                            }
                            else
                            { #count is 0 then there is no members added in the admin groups
                                $controlResult.AddMessage([VerificationResult]::Passed, "Admin groups does not have any members.");
                            }
                        }
                        else
                        {
                            $controlResult.AddMessage([VerificationResult]::Error, "Could not find the list of administrator groups in the project.");
                        }
                    }
                    else
                    {
                        $controlResult.AddMessage([VerificationResult]::Error, "Could not find the list of groups in the project.");
                    }
                }
                else
                {
                    $controlResult.AddMessage([VerificationResult]::Manual, "List of administrator groups for detecting non SC-Alt accounts is not defined in your project.");    
                }
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Error, "List of administrator groups for detecting non SC-Alt accounts is not defined in your project. Please update your ControlSettings.json as per the latest AzSK.AzureDevOps PowerShell module.");
            }
        }
        catch
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the list of groups in the project.");
        }
       
        return $controlResult
    }
}