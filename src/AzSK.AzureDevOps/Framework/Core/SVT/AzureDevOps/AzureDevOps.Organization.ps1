Set-StrictMode -Version Latest 
class Organization: ADOSVTBase
{    
    [PSObject] $ServiceEndPointsObj = $null
    [PSObject] $PipelineSettingsObj = $null
    [PSObject] $OrgPolicyObj = $null
    #TODO: testing below line
    hidden [string] $SecurityNamespaceId;
    Organization([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    { 
        $this.GetOrgPolicyObject()
        $this.GetPipelineSettingsObj()
    }

    GetOrgPolicyObject()
    {
        $apiURL = "https://{0}.vsaex.visualstudio.com/_apis/Contribution/dataProviders/query?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);

        $orgUrl = "https://{0}.visualstudio.com" -f $($this.SubscriptionContext.SubscriptionName);
        $inputbody =  "{'contributionIds':['ms.vss-org-web.collection-admin-policy-data-provider'],'context':{'properties':{'sourcePage':{'url':'$orgUrl/_settings/policy','routeId':'ms.vss-admin-web.collection-admin-hub-route','routeValues':{'adminPivot':'policy','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
        
        $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);
      
        if([Helpers]::CheckMember($responseObj,"data") -and $responseObj.data.'ms.vss-org-web.collection-admin-policy-data-provider')
        {
            $this.OrgPolicyObj = $responseObj.data.'ms.vss-org-web.collection-admin-policy-data-provider'.policies
        }
    }
    
    GetPipelineSettingsObj()
    {
        $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);

        $orgUrl = "https://{0}.visualstudio.com" -f $($this.SubscriptionContext.SubscriptionName);
        #$inputbody =  "{'contributionIds':['ms.vss-org-web.collection-admin-policy-data-provider'],'context':{'properties':{'sourcePage':{'url':'$orgUrl/_settings/policy','routeId':'ms.vss-admin-web.collection-admin-hub-route','routeValues':{'adminPivot':'policy','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
        $inputbody = "{'contributionIds':['ms.vss-build-web.pipelines-org-settings-data-provider'],'dataProviderContext':{'properties':{'sourcePage':{'url':'$orgUrl/_settings/pipelinessettings','routeId':'ms.vss-admin-web.collection-admin-hub-route','routeValues':{'adminPivot':'pipelinessettings','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
        
        $responseObj = $null 

        try{
            $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);
        }
        catch{
            #Write-Host "Pipeline settings for the organization [$($this.SubscriptionContext.SubscriptionName)] can not be fetched."
        }
        
      
        if([Helpers]::CheckMember($responseObj,"dataProviders"))
        {
            try {
             if($responseObj.dataProviders.'ms.vss-build-web.pipelines-org-settings-data-provider') 
              { 
                  $this.PipelineSettingsObj = $responseObj.dataProviders.'ms.vss-build-web.pipelines-org-settings-data-provider'
              }
            }
            catch {
                #Write-Host "Pipeline settings for the organization [$($this.SubscriptionContext.SubscriptionName)] can not be fetched."
            }
            
        }
    }
    
    hidden [ControlResult] CheckProCollSerAcc([ControlResult] $controlResult)
    {
        try
        {
            $url= "https://vssps.dev.azure.com/{0}/_apis/graph/groups?api-version=5.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($url);
       
            $accname = "Project Collection Service Accounts"; #Enterprise Service Accounts
            $prcollobj = $responseObj | where {$_.displayName -eq $accname}
            
            if(($prcollobj | Measure-Object).Count -gt 0)
            {

                $prmemberurl = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
                $inputbody = '{"contributionIds":["ms.vss-admin-web.org-admin-members-data-provider"],"dataProviderContext":{"properties":{"subjectDescriptor":"{0}","sourcePage":{"url":"https://{1}.visualstudio.com/_settings/groups?subjectDescriptor={0}","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute"}}}}}'
                $inputbody = $inputbody.Replace("{0}",$prcollobj.descriptor)
                $inputbody = $inputbody.Replace("{1}",$this.SubscriptionContext.SubscriptionName) | ConvertFrom-Json
                
                $responsePrCollObj = [WebRequestHelper]::InvokePostWebRequest($prmemberurl,$inputbody);
                $responsePrCollData = $responsePrCollObj.dataProviders.'ms.vss-admin-web.org-admin-members-data-provider'.identities
            
                if(($responsePrCollData | Measure-Object).Count -gt 0){
                    $responsePrCollData = $responsePrCollData | Select-Object displayName,mailAddress,subjectKind
                    $stateData = @();
                    $stateData += $responsePrCollData
                    $controlResult.AddMessage([VerificationResult]::Verify, "Review the members of the group Project Collection Service Accounts : ", $stateData); 
                    $controlResult.SetStateData("Members of the Project Collection Service Accounts group : ", $stateData); 
                }
                else
                { #count is 0 then there is no member in the prj coll ser acc group
                    $controlResult.AddMessage([VerificationResult]::Passed, "Project Collection Service Accounts group does not have any member.");
                }
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Error, "Project Collection Service Accounts group could not be fetched.");
            }
        }
        catch
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the list of groups in the organization.");
        }
       
        return $controlResult
    }

    hidden [ControlResult] CheckAADConfiguration([ControlResult] $controlResult)
    {
        try 
        {
            $apiURL = "https://dev.azure.com/{0}/_settings/organizationAad?__rt=fps&__ver=2" -f $($this.SubscriptionContext.SubscriptionName);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            
            if(([Helpers]::CheckMember($responseObj[0],"fps.dataProviders.data") ) -and  (($responseObj[0].fps.dataProviders.data."ms.vss-admin-web.organization-admin-aad-data-provider") -and $responseObj[0].fps.dataProviders.data."ms.vss-admin-web.organization-admin-aad-data-provider".orgnizationTenantData) -and (-not [string]::IsNullOrWhiteSpace($responseObj[0].fps.dataProviders.data."ms.vss-admin-web.organization-admin-aad-data-provider".orgnizationTenantData.domain)))
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Organization is configured with [$($responseObj.fps.dataProviders.data.'ms.vss-admin-web.organization-admin-aad-data-provider'.orgnizationTenantData.displayName)] directory.");
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Failed, "Organization is not configured with AAD.");
            }
        }
        catch {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch AAD configuration details.");
        }
        return $controlResult
    }


    hidden [ControlResult] CheckAltAuthSettings([ControlResult] $controlResult)
    {
       if([Helpers]::CheckMember($this.OrgPolicyObj,"applicationConnection"))
       {
           try {                       
               #https://devblogs.microsoft.com/devops/azure-devops-will-no-longer-support-alternate-credentials-authentication/
                $altAuthObj = $this.OrgPolicyObj.applicationConnection | Where-Object {$_.Policy.Name -eq "Policy.DisallowBasicAuthentication"}
                 if(($altAuthObj | Measure-Object).Count -gt 0)
                {
                     if($altAuthObj.policy.effectiveValue -eq $false )
                     {
                         $controlResult.AddMessage([VerificationResult]::Passed,
                                                     "Alternate authentication is disabled in organization.");
                     }
                     else {
                         $controlResult.AddMessage([VerificationResult]::Failed,
                                                     "Alternate authentication is enabled in organization.");
                     }
                 }
             }
             catch {
                $controlResult.AddMessage([VerificationResult]::Passed,
                "Alternate authentication is no longer supported in Azure DevOps.");
             }
        }

        return $controlResult
    }

    hidden [ControlResult] CheckExternalUserPolicy([ControlResult] $controlResult)
    {
        if([Helpers]::CheckMember($this.OrgPolicyObj,"user"))
        {
            $userPolicyObj = $this.OrgPolicyObj.user[0]; 
            $guestAuthObj = $userPolicyObj | Where-Object {$_.Policy.Name -eq "Policy.DisallowAadGuestUserAccess"}
            if(($guestAuthObj | Measure-Object).Count -gt 0)
            {
                if($guestAuthObj.policy.effectiveValue -eq $false )
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,"External guest access is disabled in the organization.");
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Failed, "External guest access is enabled in the organization.");
                }
            }
            else 
            {
                #Manual control status because external guest access notion is not applicable when AAD is not configured. Instead invite GitHub user policy is available in non-AAD backed orgs.
                $controlResult.AddMessage([VerificationResult]::Manual, "Could not fetch external guest access policy details of the organization.");    
            }
        }
        else 
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch external guest access policy details of the organization.");
        }
        return $controlResult
    }

    hidden [ControlResult] CheckPublicProjectPolicy([ControlResult] $controlResult)
    {
        if([Helpers]::CheckMember($this.OrgPolicyObj,"security"))
        {
            $guestAuthObj = $this.OrgPolicyObj.security | Where-Object {$_.Policy.Name -eq "Policy.AllowAnonymousAccess"}
            if(($guestAuthObj | Measure-Object).Count -gt 0)
            {
                    if($guestAuthObj.policy.effectiveValue -eq $false )
                    {
                        $controlResult.AddMessage([VerificationResult]::Passed, "Public projects are not allowed in the organization.");
                    }
                    else 
                    {
                        $controlResult.AddMessage([VerificationResult]::Failed, "Public projects are allowed in the organization.");
                    }
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the public project security policies.");
            }  
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the organization security policies.");
        }  
        return $controlResult
    }


    hidden [ControlResult] ValidateInstalledExtensions([ControlResult] $controlResult)
    {
        try 
        {
           
            $apiURL = "https://extmgmt.dev.azure.com/{0}/_apis/extensionmanagement/installedextensions?api-version=4.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            
            if(($responseObj | Measure-Object).Count -gt 0 ) #includes both custom installed and built in extensions.
            {
                $extensionList = $responseObj | Select-Object extensionName,publisherId,publisherName,version,flags # 'flags' is not available in every extension. It is visible only for built in extensions. Hence this appends 'flags' to trimmed objects.
                $extensionList = $extensionList | Where-Object {$_.flags -notlike "*builtin*" } # to filter out extensions that are built in and are not visible on portal.
                $extCount = ($extensionList | Measure-Object ).Count;

                if($extCount -gt 0)
                {               
                    $controlResult.AddMessage("No. of extensions installed : " + $extCount);

                    $whitelistedExtPublishers = $this.ControlSettings.Organization.WhitelistedExtensionPublishers;

                    $whiteListedExtensions = @(); #Publishers trusted by Microsoft
                    $whiteListedExtensions += $extensionList | Where-Object {$_.publisherName -in $whitelistedExtPublishers}
                    
                    $NonwhiteListedExtensions = @(); #Publishers not trusted by Microsoft
                    $NonwhiteListedExtensions += $extensionList | Where-Object {$_.publisherName -notin $whitelistedExtPublishers}
                        
                    $controlResult.AddMessage([VerificationResult]::Verify, "Review the below list of installed extensions : ");  
                    $controlResult.AddMessage("Whitelisted extensions (from trusted publisher) : ", $whiteListedExtensions);
                    $controlResult.AddMessage("Non-Whitelisted extensions : ", $NonwhiteListedExtensions);

                    $stateData = @{
                        Whitelisted_Extensions = @();
                        NonWhitelisted_Extensions = @();
                    };

                    $stateData.Whitelisted_Extensions += $whiteListedExtensions
                    $stateData.NonWhitelisted_Extensions += $NonwhiteListedExtensions

                    $controlResult.SetStateData("List of installed extensions : ", $stateData);
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Passed, "No installed extensions found.");
                }
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "No installed extensions found.");
            }

        }
        catch
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the list of installed extensions.");
        }

        return $controlResult
    }

    hidden [ControlResult] ValidateSharedExtensions([ControlResult] $controlResult)
    {
        $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
        $orgURL="https://{0}.visualstudio.com/_settings/extensions" -f $($this.SubscriptionContext.SubscriptionName);
        $inputbody =  "{'contributionIds':['ms.vss-extmgmt-web.ext-management-hub'],'dataProviderContext':{'properties':{'sourcePage':{'url':'$orgURL','routeId':'ms.vss-admin-web.collection-admin-hub-route','routeValues':{'adminPivot':'extensions','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
        
        try
        {
            $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);

            if([Helpers]::CheckMember($responseObj[0],"dataProviders") -and $responseObj[0].dataProviders.'ms.vss-extmgmt-web.extensionManagmentHub-collection-data-provider')
            {
                $sharedExtensions = $responseObj[0].dataProviders.'ms.vss-extmgmt-web.extensionManagmentHub-collection-data-provider'.sharedExtensions

                if(($sharedExtensions | Measure-Object).Count -gt 0)
                {
                    $controlResult.AddMessage("No. of shared extensions :" + $sharedExtensions.Count)
                    $extensionList = @();
                    $extensionList +=  ($sharedExtensions | Select-Object extensionName,publisherId,publisherName,version) 

                    $controlResult.AddMessage([VerificationResult]::Verify, "Review the below list of shared extensions : ",$extensionList); 
                                                    
                    $controlResult.SetStateData("List of shared extensions : ", $extensionList);                                
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Passed, "No shared extensions found.");
                } 
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the list of shared extensions.");    
            }
        }
        catch
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the list of shared extensions.");
        }
        return $controlResult
    }

    hidden [ControlResult] CheckGuestIdentities([ControlResult] $controlResult)
    {
        try 
        {
            $apiURL = "https://{0}.vsaex.visualstudio.com/_apis/UserEntitlements?top=100&filter=userType+eq+%27guest%27&api-version=5.0-preview.2" -f $($this.SubscriptionContext.SubscriptionName);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        
            if(($responseObj -ne $null) -and ($responseObj[0].totalCount -gt 0) -and ([Helpers]::CheckMember($responseObj[0], 'members')))
            {
                $controlResult.AddMessage("No. of guest identities present:" + ($responseObj[0].totalCount));
                $guestList = @();
                $guestList +=  ($responseObj[0].members | Select-Object @{Name="IdentityType"; Expression = {$_.user.subjectKind}},@{Name="DisplayName"; Expression = {$_.user.displayName}}, @{Name="MailAddress"; Expression = {$_.user.mailAddress}},@{Name="AccessLevel"; Expression = {$_.accessLevel.licenseDisplayName}},@{Name="LastAccessedDate"; Expression = {$_.lastAccessedDate}})
                $controlResult.AddMessage([VerificationResult]::Verify, "Review the below list of guest users : ",$guestList);      
                $controlResult.SetStateData("Guest users list: ", $guestList);    
            }
            else #external guest access notion is not applicable when AAD is not configured. Instead GitHub user notion is available in non-AAD backed orgs.
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "There are no guest users in the organization.");
            }
        }
        catch 
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the list of guest identities.");
        } 

        return $controlResult
    }

    hidden [ControlResult] CheckExtensionManagers([ControlResult] $controlResult)
    {

        $apiURL = "https://{0}.extmgmt.visualstudio.com/_apis/securityroles/scopes/ems.manage.ui/roleassignments/resources/ems-ui" -f $($this.SubscriptionContext.SubscriptionName);
        
        try 
        {
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        
            # If no ext. managers are present, 'count' property is available for $responseObj[0] and its value is 0. 
            # If ext. managers are assigned, 'count' property is not available for $responseObj[0]. 
            #'Count' is a PSObject property and 'count' is response object property. Notice the case sensitivity here.
            
            # TODO: When there are no managers check member in the below condition returns false when checknull flag [third param in CheckMember] is not specified (default value is $true). Assiging it $false. Need to revisit.
            if(([Helpers]::CheckMember($responseObj[0],"count",$false)) -and ($responseObj[0].count -eq 0))
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "No extension managers assigned.");
            }
             # When there are managers - the below condition will be true.
            elseif((-not ([Helpers]::CheckMember($responseObj[0],"count"))) -and ($responseObj.Count -gt 0)) 
            {
                $controlResult.AddMessage("No. of extension managers present : " + $responseObj.Count)
                $extensionManagerList = @();
                $extensionManagerList +=  ($responseObj | Select-Object @{Name="IdentityName"; Expression = {$_.identity.displayName}},@{Name="Role"; Expression = {$_.role.displayName}})
                $controlResult.AddMessage([VerificationResult]::Verify, "Review the below list of extension managers : ",$extensionManagerList);        
                $controlResult.SetStateData("List of extension managers : ", $extensionManagerList);   
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "No extension managers assigned.");
            }
        }
        catch 
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the list of extension managers.");
        }
        return $controlResult
    }

    hidden [ControlResult] CheckInActiveUsers([ControlResult] $controlResult)
    {

        $apiURL = "https://{0}.vsaex.visualstudio.com/_apis/UserEntitlements?top=50&filter=&sortOption=lastAccessDate+ascending" -f $($this.SubscriptionContext.SubscriptionName);
        $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

        if($responseObj.Count -gt 0)
        {
            $inactiveUsers =  @()
            $responseObj[0].items | ForEach-Object { 
                if([datetime]::Parse($_.lastAccessedDate) -lt ((Get-Date).AddDays(-$($this.ControlSettings.Organization.InActiveUserActivityLogsPeriodInDays))))
                {
                    $inactiveUsers+= $_
                }                
            }
            if(($inactiveUsers | Measure-Object).Count -gt 0)
            {
                if($inactiveUsers.Count -gt 50)
                {
                    $controlResult.AddMessage("Displaying top 50 inactive users")
                }
                $inactiveUsersNames = ($inactiveUsers | Select-Object -Property @{Name="Name"; Expression = {$_.User.displayName}},@{Name="mailAddress"; Expression = {$_.User.mailAddress}})
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        "Review inactive users present in the organization",$inactiveUsersNames);
                $controlResult.SetStateData("Inactive users list: ", $inactiveUsersNames);
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                        "No inactive users found")   
            }
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "No inactive users found");
        }
        
        return $controlResult;
    }

    hidden [ControlResult] CheckDisconnectedIdentities([ControlResult] $controlResult)
    {
        $apiURL = "https://{0}.visualstudio.com/_apis/OrganizationSettings/DisconnectedUser" -f $($this.SubscriptionContext.SubscriptionName);
        $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        
        try {
           if ([Helpers]::CheckMember($responseObj,"users")) {
               if(($responseObj.users | Measure-Object).Count -gt 0 )  
               {
        
                    $UsersNames = @();   
                    $UsersNames += ($responseObj.users | Select-Object -Property @{Name="Name"; Expression = {$_.displayName}},@{Name="mailAddress"; Expression = {$_.preferredEmailAddress}})
                    $controlResult.AddMessage([VerificationResult]::Failed, "Remove access from the organization for below disconnected users",$UsersNames);  
                    $controlResult.SetStateData("Disconnected users list: ", $UsersNames);
               }
               else
               {
                   $controlResult.AddMessage([VerificationResult]::Passed, "No disconnected users found.");
               }   
              } 
        }
        catch {
            $controlResult.AddMessage([VerificationResult]::Passed, "No disconnected users found.");
        }
        
       
        return $controlResult;
    }

    hidden [ControlResult] CheckRBACAccess([ControlResult] $controlResult)
    {
        $url= "https://vssps.dev.azure.com/{0}/_apis/graph/groups?api-version=5.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
        $groupsObj = [WebRequestHelper]::InvokeGetWebRequest($url);

        $apiURL = "https://{0}.vsaex.visualstudio.com/_apis/UserEntitlements?top=50&filter=&sortOption=lastAccessDate+ascending" -f $($this.SubscriptionContext.SubscriptionName);
        $usersObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

        $Users =  @()
        $usersObj[0].items | ForEach-Object { 
                $Users+= $_   
        }

        $groups = ($groupsObj | Select-Object -Property @{Name="Name"; Expression = {$_.displayName}},@{Name="mailAddress"; Expression = {$_.mailAddress}});
        
        $UsersNames = ($Users | Select-Object -Property @{Name="Name"; Expression = {$_.User.displayName}},@{Name="mailAddress"; Expression = {$_.User.mailAddress}})

        if ( (($groups | Measure-Object).Count -gt 0) -or (($UsersNames | Measure-Object).Count -gt 0)) {
            $controlResult.AddMessage([VerificationResult]::Verify, "Verify users and groups present on Organization");

            $controlResult.AddMessage("Verify groups present on Organization", $groups); 
            $controlResult.AddMessage("Verify users present on Organization", $UsersNames); 
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
        $url= "https://vssps.dev.azure.com/{0}/_apis/graph/groups?api-version=5.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
        $groupsObj = [WebRequestHelper]::InvokeGetWebRequest($url);
         
        $apiURL = "https://dev.azure.com/{0}/_apis/Contribution/HierarchyQuery?api-version=5.0-preview" -f $($this.SubscriptionContext.SubscriptionName);

        $membercount =0;
        Foreach ($group in $groupsObj){
         $groupmember = @();    
         $descriptor = $group.descriptor;
         $inputbody =  '{"contributionIds":["ms.vss-admin-web.org-admin-members-data-provider"],"dataProviderContext":{"properties":{"subjectDescriptor":"","sourcePage":{"url":"","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute"}}}}}' | ConvertFrom-Json
        
         $inputbody.dataProviderContext.properties.subjectDescriptor = $descriptor;
         $inputbody.dataProviderContext.properties.sourcePage.url = "https://dev.azure.com/$($this.SubscriptionContext.SubscriptionName)/_settings/groups?subjectDescriptor=$($descriptor)";
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
            $controlResult.AddMessage([VerificationResult]::Verify, "Verify members of groups present on Organization");
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,  "No users or groups found");
        }

        return $controlResult
    }

    hidden [ControlResult] CheckOAuthAppAccess([ControlResult] $controlResult)
    {
       if([Helpers]::CheckMember($this.OrgPolicyObj,"applicationConnection"))
       {
            $OAuthObj = $this.OrgPolicyObj.applicationConnection | Where-Object {$_.Policy.Name -eq "Policy.DisallowOAuthAuthentication"}
            if(($OAuthObj | Measure-Object).Count -gt 0)
            {
                if($OAuthObj.policy.effectiveValue -eq $true )
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,
                                                "OAuth is enabled for third-party application access.");
                }
                else {
                    $controlResult.AddMessage([VerificationResult]::Failed,
                                                "OAuth is enabled for third-party application access.");
                }
            }
       }
        return $controlResult
    }

    hidden [ControlResult] CheckSSHAuthn([ControlResult] $controlResult)
    {
       if([Helpers]::CheckMember($this.OrgPolicyObj,"applicationConnection"))
       {
            $SSHAuthObj = $this.OrgPolicyObj.applicationConnection | Where-Object {$_.Policy.Name -eq "Policy.DisallowSecureShell"}
            if(($SSHAuthObj | Measure-Object).Count -gt 0)
            {
                if($SSHAuthObj.policy.effectiveValue -eq $true )
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,
                                                "SSH authentication is enabled for application connection policies.");
                }
                else {
                    $controlResult.AddMessage([VerificationResult]::Failed,
                                                "SSH authentication is disabled for application connection policies");
                }
            }
       }
        return $controlResult
    }

    hidden [ControlResult] CheckEnterpriseAccess([ControlResult] $controlResult)
    {
       if([Helpers]::CheckMember($this.OrgPolicyObj,"security"))
       {
            $CAPObj = $this.OrgPolicyObj.security | Where-Object {$_.Policy.Name -eq "Policy.AllowOrgAccess"}
            if(($CAPObj | Measure-Object).Count -gt 0)
            {
                if($CAPObj.policy.effectiveValue -eq $true )
                {
                    $controlResult.AddMessage([VerificationResult]::Verify,
                                                "Enterprise access to projects is enabled.");
                }
                else {
                    $controlResult.AddMessage([VerificationResult]::Passed,
                                                "Enterprise access to projects is disabled.");
                }
            }
       }
        return $controlResult
    }

    hidden [ControlResult] CheckCAP([ControlResult] $controlResult)
    {
       if([Helpers]::CheckMember($this.OrgPolicyObj,"security"))
       {
            $CAPObj = $this.OrgPolicyObj.security | Where-Object {$_.Policy.Name -eq "Policy.EnforceAADConditionalAccess"}
            if(($CAPObj | Measure-Object).Count -gt 0)
            {
                if($CAPObj.policy.effectiveValue -eq $true )
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,
                                                "AAD conditional access policy validation is enabled.");
                }
                else {
                    $controlResult.AddMessage([VerificationResult]::Failed,
                                                "AAD conditional access policy validation is disabled.");
                }
            }
       }
        return $controlResult
    }

    hidden [ControlResult] CheckBadgeAnonAccess([ControlResult] $controlResult)
    {
       if($this.PipelineSettingsObj)
       {
            
            if($this.PipelineSettingsObj.statusBadgesArePrivate -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Anonymous access to status badge API is disabled.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Failed, "Anonymous access to status badge API is enabled.");
            }       
       }
       else{
            $controlResult.AddMessage([VerificationResult]::Manual, "Pipeline settings could not be fetched due to insufficient permissions at organization scope.");
       }
        return $controlResult
    }

    hidden [ControlResult] CheckSetQueueTime([ControlResult] $controlResult)
    {
       if($this.PipelineSettingsObj)
       {
            
            if($this.PipelineSettingsObj.enforceSettableVar -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Only limited variables can be set at queue time.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Failed, "All variables can be set at queue time.");
            }       
       }
       else{
            $controlResult.AddMessage([VerificationResult]::Manual, "Pipeline settings could not be fetched due to insufficient permissions at organization scope.");
        }
        return $controlResult
    }

    hidden [ControlResult] CheckJobAuthZScope([ControlResult] $controlResult)
    {
       if($this.PipelineSettingsObj)
       {
            $orgLevelScope = $this.PipelineSettingsObj.enforceJobAuthScope
            
            if($orgLevelScope -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Job authorization scope is limited to current project at organization level.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Failed, "Job authorization scope is set to project collection at organization level.");
            }       
       }
       else{
             $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the organization pipeline settings.");
       }       
        return $controlResult
    }
    
    hidden [ControlResult] AutoInjectedExtension([ControlResult] $controlResult)
    {
        try
        {
            $url ="https://extmgmt.dev.azure.com/{0}/_apis/extensionmanagement/installedextensions?api-version=5.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($url);     
            $autoInjExt = @();
            
            foreach($extension in $responseObj)
            {
                foreach($cont in $extension.contributions)
                {
                    if([Helpers]::CheckMember($cont,"type"))
                    {
                        if($cont.type -eq "ms.azure-pipelines.pipeline-decorator")
                        {
                            $autoInjExt +=  ($extension | Select-Object -Property @{Name="Name"; Expression = {$_.extensionName}},@{Name="Publisher"; Expression = {$_.PublisherName}},@{Name="Version"; Expression = {$_.version}})
                            break;
                        }
                    }  
                }     
            }

            if (($autoInjExt | Measure-Object).Count -gt 0)
            {
                $controlResult.AddMessage([VerificationResult]::Verify,"Verify the below auto-injected tasks at organization level:", $autoInjExt);
                $controlResult.SetStateData("Auto-injected tasks list: ", $autoInjExt); 
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Passed,"No auto-injected tasks found at organization level");
            }
        }
        catch 
        {
            $controlResult.AddMessage([VerificationResult]::Error,"Couldn't fetch the list of installed extensions in the organization.");     
        }

        return $controlResult
    }

    hidden [ControlResult] CheckMinPCACount([ControlResult] $controlResult)
    {
        $TotalPCAMembers=0
        $PCAMembers = @()
        $PCAMembers += [AdministratorHelper]::GetTotalPCAMembers($this.SubscriptionContext.SubscriptionName)
        $TotalPCAMembers = ($PCAMembers| Measure-Object).Count
        $PCAMembers = $PCAMembers | Select-Object displayName,mailAddress
        $controlResult.AddMessage("There are a total of $TotalPCAMembers Project Collection Administrators in your organization")
        if($TotalPCAMembers -lt $this.ControlSettings.Organization.MinPCAMembersPermissible){
            $controlResult.AddMessage([VerificationResult]::Failed,"Number of administrators configured are less than the minimum required administrators count : $($this.ControlSettings.Organization.MinPCAMembersPermissible)");
        }
        else{
            $controlResult.AddMessage([VerificationResult]::Passed,"Number of administrators configured are more than the minimum required administrators count : $($this.ControlSettings.Organization.MinPCAMembersPermissible)");
        }
        if($TotalPCAMembers -gt 0){
            $controlResult.AddMessage("Verify the following Project Collection Administrators : ",$PCAMembers)
            $controlResult.SetStateData("List of Project Collection Administrators : ",$PCAMembers)
        }        
        return $controlResult
}

hidden [ControlResult] CheckMaxPCACount([ControlResult] $controlResult)
    {
        
        $TotalPCAMembers=0
        $PCAMembers = @()
        $PCAMembers += [AdministratorHelper]::GetTotalPCAMembers($this.SubscriptionContext.SubscriptionName)
        $TotalPCAMembers = ($PCAMembers| Measure-Object).Count
        $PCAMembers = $PCAMembers | Select-Object displayName,mailAddress
        $controlResult.AddMessage("There are a total of $TotalPCAMembers Project Collection Administrators in your organization")
        if($TotalPCAMembers -gt $this.ControlSettings.Organization.MaxPCAMembersPermissible){
            $controlResult.AddMessage([VerificationResult]::Failed,"Number of administrators configured are more than the approved limit : $($this.ControlSettings.Organization.MaxPCAMembersPermissible)");
        }
        else{
            $controlResult.AddMessage([VerificationResult]::Passed,"Number of administrators configured are within than the approved limit : $($this.ControlSettings.Organization.MaxPCAMembersPermissible)");
        }
        if($TotalPCAMembers -gt 0){
            $controlResult.AddMessage("Verify the following Project Collection Administrators : ",$PCAMembers)
            $controlResult.SetStateData("List of Project Collection Administrators : ",$PCAMembers)
        }
    
        return $controlResult
}

}