class AdministratorHelper{
    static [bool] $isCurrentUserPCA=$false;
    static [bool] $isCurrentUserPA=$false;
    static $AllPCAMembers = @()
    static $AllPAMembers = @()


    #Check whether uesr is PCA and subgroups member
    static [bool] isUserOrgAdminMember($organizationName, [PSObject] $allowedAdminGrp)
    {
        try 
        {
            $rmContext = [ContextHelper]::GetCurrentContext();
		    $user = "";
            $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))

            $url = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.1-preview.1" -f $($organizationName);
            $body=@'
            {"contributionIds":["ms.vss-admin-web.org-admin-groups-data-provider"],"dataProviderContext":{"properties":{"sourcePage":{"url":"https://{0}.visualstudio.com/_settings/groups","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute"}}}}}
'@ 
            $body = $body.Replace("{0}",$organizationName)
            $groupsOrgObj = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $body

            if ($allowedAdminGrp) {
                $groupsOrgObj = $groupsOrgObj.dataProviders.'ms.vss-admin-web.org-admin-groups-data-provider'.identities | where { $allowedAdminGrp.GroupNames -contains $_.displayName }
            }
            #else condition if 'AllowAdminControlScanForGroups' propertry not foud in orgpolicy. Then check using default group PA 
            else {
                $groupsOrgObj = $groupsOrgObj.dataProviders.'ms.vss-admin-web.org-admin-groups-data-provider'.identities | where { "Project Collection Administrators" -eq $_.displayName }
            }
            foreach ($group in $groupsOrgObj)
	        {
                #if user found in group return true
                if ([AdministratorHelper]::GetIsCurrentUserPCA($group.descriptor, $organizationName)) {
                    return $true;
                }
            }
            return $false;
        }
        catch
        {
            return $false;
        }
    }

    static [bool] isUserProjectAdminMember($organizationName, $project, [PSObject] $allowedAdminGrp)
    {
        try 
        {
            $rmContext = [ContextHelper]::GetCurrentContext();
		    $user = "";
            $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
            
            $url= "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.1-preview.1" -f $($organizationName);
            $body=@'
            {"contributionIds":["ms.vss-admin-web.org-admin-groups-data-provider"],"dataProviderContext":{"properties":{"sourcePage":{"url":"https://{0}.visualstudio.com/{1}/_settings/permissions","routeId":"ms.vss-admin-web.project-admin-hub-route","routeValues":{"project":"{1}","adminPivot":"permissions","controller":"ContributedPage","action":"Execute"}}}}}
'@     
            $body=$body.Replace("{0}",$organizationName)
            $body=$body.Replace("{1}",$project)
            $groupsObj = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $body
            
            if ($allowedAdminGrp) {
                $groupsObj = $groupsObj.dataProviders."ms.vss-admin-web.org-admin-groups-data-provider".identities | where { $allowedAdminGrp.GroupNames -contains $_.displayName }
            }
            #else condition if 'AllowAdminControlScanForGroups' propertry not foud in orgpolicy. Then check using default group PA 
            else {
                $groupsObj = $groupsObj.dataProviders."ms.vss-admin-web.org-admin-groups-data-provider".identities | where { "Project Administrators" -eq $_.displayName }
            }
		    
            foreach ($group in $groupsObj)
	        { 
                #if user found in group return true
                if([AdministratorHelper]::GetIsCurrentUserPA($groupsObj.descriptor,$organizationName, $project))
                {
		    	    return $true;
		        }	
		    }
            return $false;
        }
        catch
        {
            return $false;
        }
    }

    static [void] GetPCADescriptorAndMembers([string] $OrgName){
        
        $url= "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.1-preview.1" -f $($OrgName);
        $body=@'
        {"contributionIds":["ms.vss-admin-web.org-admin-groups-data-provider"],"dataProviderContext":{"properties":{"sourcePage":{"url":"https://{0}.visualstudio.com/_settings/groups","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute"}}}}}
'@ 
        $body=$body.Replace("{0}",$OrgName)
        $rmContext = [ContextHelper]::GetCurrentContext();
		$user = "";
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
        try{
        $responseObj = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $body

        $accname = "Project Collection Administrators"; 
        $prcollobj = $responseObj.dataProviders.'ms.vss-admin-web.org-admin-groups-data-provider'.identities | where {$_.displayName -eq $accname}
        
        

        if(($prcollobj | Measure-Object).Count -gt 0){
            [AdministratorHelper]::FindPCAMembers($prcollobj.descriptor,$OrgName)
        }
    }
    catch {

    }
    }

    static [void] GetPADescriptorAndMembers([string] $OrgName,[string] $projName){
        
        $url= "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.1-preview.1" -f $($OrgName);
        $body=@'
        {"contributionIds":["ms.vss-admin-web.org-admin-groups-data-provider"],"dataProviderContext":{"properties":{"sourcePage":{"url":"https://{0}.visualstudio.com/{1}/_settings/permissions","routeId":"ms.vss-admin-web.project-admin-hub-route","routeValues":{"project":"{1}","adminPivot":"permissions","controller":"ContributedPage","action":"Execute"}}}}}
'@ 
        $body=$body.Replace("{0}",$OrgName)
        $body=$body.Replace("{1}",$projName)
        $rmContext = [ContextHelper]::GetCurrentContext();
		$user = "";
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
        try{
        $responseObj = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $body

        $accname = "Project Administrators"; 
        $prcollobj = $responseObj.dataProviders.'ms.vss-admin-web.org-admin-groups-data-provider'.identities | where {$_.displayName -eq $accname}
        
        

        if(($prcollobj | Measure-Object).Count -gt 0){
            [AdministratorHelper]::FindPAMembers($prcollobj.descriptor,$OrgName,$projName)
        }
    }
    catch {
        Write-Host $_
    }
    }


    static [void] FindPCAMembers([string]$descriptor,[string] $OrgName){
        $url="https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.1-preview" -f $($OrgName);
        $postbody=@'
        {"contributionIds":["ms.vss-admin-web.org-admin-members-data-provider"],"dataProviderContext":{"properties":{"subjectDescriptor":"{0}","sourcePage":{"url":"https://{2}.visualstudio.com/_settings/groups?subjectDescriptor={1}","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute"}}}}}
'@
        $postbody=$postbody.Replace("{0}",$descriptor)
        $postbody=$postbody.Replace("{1}",$OrgName)
        $rmContext = [ContextHelper]::GetCurrentContext();
		$user = "";
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
        try {
            $response = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $postbody
            $data=$response.dataProviders.'ms.vss-admin-web.org-admin-members-data-provider'.identities
            $data | ForEach-Object{
    
            if($_.subjectKind -eq "group"){
                return [AdministratorHelper]::FindPCAMembers($_.descriptor,$OrgName)
            }
            else{
                if([AdministratorHelper]::isCurrentUserPCA -eq $false -and [ContextHelper]::GetCurrentSessionUser() -eq $_.mailAddress){
                    [AdministratorHelper]::isCurrentUserPCA=$true;
                }
                [AdministratorHelper]::AllPCAMembers += $_
            }
            }
        }
        catch {
            Write-Host $_
        }
		

    }

    static [void] FindPAMembers([string]$descriptor,[string] $OrgName,[string] $projName){
        $url="https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.1-preview" -f $($OrgName);
        $postbody=@'
        {"contributionIds":["ms.vss-admin-web.org-admin-members-data-provider"],"dataProviderContext":{"properties":{"subjectDescriptor":"{0}","sourcePage":{"url":"https://{2}.visualstudio.com/{1}/_settings/permissions?subjectDescriptor={0}","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute"}}}}}
'@
        $postbody=$postbody.Replace("{0}",$descriptor)
        $postbody=$postbody.Replace("{2}",$OrgName)
        $postbody=$postbody.Replace("{1}",$projName)
        $rmContext = [ContextHelper]::GetCurrentContext();
		$user = "";
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
        try {
            $response = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $postbody
            $data=$response.dataProviders.'ms.vss-admin-web.org-admin-members-data-provider'.identities
            $data | ForEach-Object{
    
            if($_.subjectKind -eq "group"){
                return [AdministratorHelper]::FindPAMembers($_.descriptor,$OrgName,$projName)
            }
            else{
                if([AdministratorHelper]::isCurrentUserPA -eq $false -and [ContextHelper]::GetCurrentSessionUser() -eq $_.mailAddress){
                    [AdministratorHelper]::isCurrentUserPA=$true;
                }
                [AdministratorHelper]::AllPAMembers += $_
            }
            }
        }
        catch {
            Write-Host $_
        }
		

    }

    static [object] GetTotalPCAMembers([string] $OrgName){

        #TODO: Need to reinitialize as PS ISE caches this list. It will be inappropriate if you switch org names from one scan to another in the same session.
        [AdministratorHelper]::AllPCAMembers = @();
        [AdministratorHelper]::isCurrentUserPCA = $false;
        
        [AdministratorHelper]::GetPCADescriptorAndMembers($OrgName)

        #get unique pca based on display name and mail address
        [AdministratorHelper]::AllPCAMembers = [AdministratorHelper]::AllPCAMembers | Sort-Object 'displayName','mailAddress' | Get-Unique -AsString
        return [AdministratorHelper]::AllPCAMembers
    }
    static [object] GetTotalPAMembers([string] $OrgName,[string] $projName){
        #Always reinitialize PA member list. Needed when trying to scan multiple projects
        
        [AdministratorHelper]::AllPAMembers = @();
        [AdministratorHelper]::GetPADescriptorAndMembers($OrgName,$projName)

        #get unique pa based on display name and mail address
        [AdministratorHelper]::AllPAMembers = [AdministratorHelper]::AllPAMembers | Sort-Object 'displayName','mailAddress' | Get-Unique -AsString
        return [AdministratorHelper]::AllPAMembers
    }
    static [bool] GetIsCurrentUserPCA([string] $descriptor,[string] $OrgName){
        #TODO: Need to reinitialize as PS ISE caches this list. It will be inappropriate if you switch org names from one scan to another in the same session.
        [AdministratorHelper]::AllPCAMembers = @();
        [AdministratorHelper]::isCurrentUserPCA = $false;

        [AdministratorHelper]::FindPCAMembers($descriptor,$OrgName)
        return [AdministratorHelper]::isCurrentUserPCA
    }
    static [bool] GetIsCurrentUserPA([string] $descriptor,[string] $OrgName,[string] $projName){
        #Always reinitialize PA member list and its count. Needed when trying to scan multiple projects
        [AdministratorHelper]::AllPAMembers = @();
        [AdministratorHelper]::isCurrentUserPA = $false;
        [AdministratorHelper]::FindPAMembers($descriptor,$OrgName,$projName)
        return [AdministratorHelper]::isCurrentUserPA
    }
}