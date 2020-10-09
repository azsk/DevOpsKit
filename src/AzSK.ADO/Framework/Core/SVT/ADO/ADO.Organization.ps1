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
        try
        {   
            $uri ="https://{0}.visualstudio.com/_settings/organizationPolicy?__rt=fps&__ver=2" -f $($this.SubscriptionContext.SubscriptionName);
            $response = [WebRequestHelper]::InvokeGetWebRequest($uri);
            
            if($response -and [Helpers]::CheckMember($response.fps.dataProviders,"data") -and $response.fps.dataProviders.data.'ms.vss-admin-web.organization-policies-data-provider')
            {
                $this.OrgPolicyObj = $response.fps.dataProviders.data.'ms.vss-admin-web.organization-policies-data-provider'.policies
            }
        }
        catch # Added above new api to get User policy settings, old api is not returning. Fallback to old API in catch
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
            #api call to get PCSA descriptor which used to get PCSA members api call.
            $url = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
            $body = '{"contributionIds":["ms.vss-admin-web.org-admin-groups-data-provider"],"dataProviderContext":{"properties":{"sourcePage":{"url":"https://{0}.visualstudio.com/_settings/groups","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute"}}}}}' 
            $body = ($body.Replace("{0}", $this.SubscriptionContext.SubscriptionName)) | ConvertFrom-Json
            $response = [WebRequestHelper]::InvokePostWebRequest($url,$body);    
       
            $accname = "Project Collection Service Accounts"; #Enterprise Service Accounts
            if ($response -and [Helpers]::CheckMember($response[0],"dataProviders") -and $response[0].dataProviders."ms.vss-admin-web.org-admin-groups-data-provider") {
                
                $prcollobj = $response.dataProviders."ms.vss-admin-web.org-admin-groups-data-provider".identities | where {$_.displayName -eq $accname}
                #$prcollobj = $responseObj | where {$_.displayName -eq $accname}
                
                if(($prcollobj | Measure-Object).Count -gt 0)
                {
                    #pai call to get PCSA members
                    $prmemberurl = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
                    $inputbody = '{"contributionIds":["ms.vss-admin-web.org-admin-members-data-provider"],"dataProviderContext":{"properties":{"subjectDescriptor":"{0}","sourcePage":{"url":"https://{1}.visualstudio.com/_settings/groups?subjectDescriptor={0}","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute"}}}}}'
                    $inputbody = $inputbody.Replace("{0}",$prcollobj.descriptor)
                    $inputbody = $inputbody.Replace("{1}",$this.SubscriptionContext.SubscriptionName) | ConvertFrom-Json
                    
                    $responsePrCollObj = [WebRequestHelper]::InvokePostWebRequest($prmemberurl,$inputbody);
                    $responsePrCollData = $responsePrCollObj.dataProviders.'ms.vss-admin-web.org-admin-members-data-provider'.identities
                    $memberCount = ($responsePrCollData | Measure-Object).Count                
                    if($memberCount -gt 0){
                        $responsePrCollData = $responsePrCollData | Select-Object displayName,mailAddress,subjectKind
                        $stateData = @();
                        $stateData += $responsePrCollData
                        $controlResult.AddMessage("Total number of Project Collection Service Accounts: $($memberCount)"); 
                        $controlResult.AddMessage([VerificationResult]::Verify, "Review the members of the group Project Collection Service Accounts: ", $stateData); 
                        $controlResult.SetStateData("Members of the Project Collection Service Accounts group: ", $stateData); 
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

    hidden [ControlResult] CheckSCALTForAdminMembers([ControlResult] $controlResult)
    {
        try
        {
            if(($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings, "Organization.GroupsToCheckForSCAltMembers"))
            {

                $adminGroupNames = $this.ControlSettings.Organization.GroupsToCheckForSCAltMembers;
                if (($adminGroupNames | Measure-Object).Count -gt 0) 
                {
                    #api call to get descriptor for organization groups. This will be used to fetch membership of individual groups later.
                    $url = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
                    $body = '{"contributionIds":["ms.vss-admin-web.org-admin-groups-data-provider"],"dataProviderContext":{"properties":{"sourcePage":{"url":"https://{0}.visualstudio.com/_settings/groups","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute"}}}}}' 
                    $body = ($body.Replace("{0}", $this.SubscriptionContext.SubscriptionName)) | ConvertFrom-Json
                    $response = [WebRequestHelper]::InvokePostWebRequest($url,$body);    
                    
                    if ($response -and [Helpers]::CheckMember($response[0],"dataProviders") -and $response[0].dataProviders."ms.vss-admin-web.org-admin-groups-data-provider") 
                    {
                        $adminGroups = @();
                        $adminGroups += $response.dataProviders."ms.vss-admin-web.org-admin-groups-data-provider".identities | where { $_.displayName -in $adminGroupNames }
                        $PCSAGroup = $response.dataProviders."ms.vss-admin-web.org-admin-groups-data-provider".identities | where { $_.displayName -eq "Project Collection Service Accounts"}
                            
                        if(($adminGroups | Measure-Object).Count -gt 0)
                        {
                            #global variable to track admin members across all admin groups
                            $allAdminMembers = @();
                            
                            for ($i = 0; $i -lt $adminGroups.Count; $i++) 
                            {
                                # [AdministratorHelper]::AllPCAMembers is a static variable. Always needs to be initialized. At the end of each iteration, it will be populated with members of that particular admin group.
                                [AdministratorHelper]::AllPCAMembers = @();
                                # Helper function to fetch flattened out list of group members.
                                [AdministratorHelper]::FindPCAMembers($adminGroups[$i].descriptor, $this.SubscriptionContext.SubscriptionName)
                                
                                $groupMembers = @();
                                # Add the members of current group to this temp variable.
                                $groupMembers += [AdministratorHelper]::AllPCAMembers
                                # Create a custom object to append members of current group with the group name. Each of these custom object is added to the global variable $allAdminMembers for further analysis of SC-Alt detection.
                                $groupMembers | ForEach-Object {$allAdminMembers += @( [PSCustomObject] @{ name = $_.displayName; mailAddress = $_.mailAddress; id = $_.identityId; groupName = $adminGroups[$i].displayName } )} 
                            }
                            
                            if(($PCSAGroup | Measure-Object).Count -gt 0)
                            {
                                $allPCSAMembers = @();

                                # [AdministratorHelper]::AllPCAMembers is a static variable. Needs to be reinitialized as it might contain group info from the previous for loop.
                                [AdministratorHelper]::AllPCAMembers = @();
                                # Helper function to fetch flattened out list of group members.
                                [AdministratorHelper]::FindPCAMembers($PCSAGroup.descriptor, $this.SubscriptionContext.SubscriptionName)

                                $groupMembers = @();
                                # Add the members of current group to this temp variable.
                                $groupMembers += [AdministratorHelper]::AllPCAMembers

                                # Preparing the list of members of PCSA which needs to be subtracted from $allAdminMembers
                                #USE IDENTITY ID
                                $groupMembers | ForEach-Object {$allPCSAMembers += @( [PSCustomObject] @{ name = $_.displayName; mailAddress = $_.mailAddress; id = $_.identityId; groupName = "Project Collection Administrators" } )} 

                            }

                            #Removing PCSA members from PCA members using id.
                            #TODO: HAVE ANOTHER CONTROL TO CHECK FOR PCA because some service accounts might be added directly as PCA and as well as part of PCSA. This new control will serve as a hygiene control.
                            $allAdminMembers = $allAdminMembers | ? {$_.id -notin $allPCSAMembers.id}

                            # clearing cached value in [AdministratorHelper]::AllPCAMembers as it can be used in attestation later and might have incorrect group loaded.
                            [AdministratorHelper]::AllPCAMembers = @();
                            
                            # Filtering out distinct entries. A user might be added directly to the admin group or might be a member of a child group of the admin group.
                            $allAdminMembers = $allAdminMembers| Sort-Object -Property id -Unique

                            if(($allAdminMembers | Measure-Object).Count -gt 0)
                            {
                                if([Helpers]::CheckMember($this.ControlSettings, "AlernateAccountRegularExpressionForOrg")){
                                    $matchToSCAlt = $this.ControlSettings.AlernateAccountRegularExpressionForOrg
                                    #currently SC-ALT regex is a singleton expression. In case we have multiple regex - we need to make the controlsetting entry as an array and accordingly loop the regex here.
                                    if (-not [string]::IsNullOrEmpty($matchToSCAlt)) 
                                    {
                                        $nonSCMembers = @();
                                        $nonSCMembers += $allAdminMembers | Where-Object { $_.mailAddress -notmatch $matchToSCAlt }  
                                        $nonSCCount = ($nonSCMembers | Measure-Object).Count

                                        $SCMembers = @();
                                        $SCMembers += $allAdminMembers | Where-Object { $_.mailAddress -match $matchToSCAlt }
                                        $SCCount = ($SCMembers | Measure-Object).Count

                                        if ($nonSCCount -gt 0) 
                                        {
                                            $nonSCMembers = $nonSCMembers | Select-Object name,mailAddress,groupName
                                            $stateData = @();
                                            $stateData += $nonSCMembers
                                            $controlResult.AddMessage([VerificationResult]::Failed, "`nTotal number of non SC-ALT accounts with admin privileges:  $nonSCCount"); 
                                            $controlResult.AddMessage("Review the non SC-ALT accounts with admin privileges: ", $stateData);  
                                            $controlResult.SetStateData("List of non SC-ALT accounts with admin privileges: ", $stateData); 
                                        }
                                        else 
                                        {
                                            $controlResult.AddMessage([VerificationResult]::Passed, "No users have admin privileges with non SC-ALT accounts.");
                                        }
                                        if ($SCCount -gt 0) 
                                        {
                                            $SCMembers = $SCMembers | Select-Object name,mailAddress,groupName
                                            $SCData = @();
                                            $SCData += $SCMembers
                                            $controlResult.AddMessage("`nTotal number of SC-ALT accounts with admin privileges: $SCCount");  
                                            $controlResult.AddMessage("SC-ALT accounts with admin privileges: ", $SCData);  
                                        }
                                    }
                                    else {
                                        $controlResult.AddMessage([VerificationResult]::Manual, "Regular expressions for detecting SC-ALT account is not defined in the organization.");
                                    }
                                }
                                else{
                                    $controlResult.AddMessage([VerificationResult]::Error, "Regular expressions for detecting SC-ALT account is not defined in the organization. Please update your ControlSettings.json as per the latest AzSK.ADO PowerShell module.");
                                }   
                            }
                            else
                            { #count is 0 then there is no members added in the admin groups
                                $controlResult.AddMessage([VerificationResult]::Passed, "Admin groups does not have any members.");
                            }
                        }
                        else
                        {
                            $controlResult.AddMessage([VerificationResult]::Error, "Could not find the list of administrator groups in the organization.");
                        }
                    }
                    else
                    {
                        $controlResult.AddMessage([VerificationResult]::Error, "Could not find the list of groups in the organization.");
                    }
                }
                else
                {
                    $controlResult.AddMessage([VerificationResult]::Manual, "List of administrator groups for detecting non SC-Alt accounts is not defined in your organization.");    
                }
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Error, "List of administrator groups for detecting non SC-Alt accounts is not defined in your organization. Please update your ControlSettings.json as per the latest AzSK.ADO PowerShell module.");
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
            $userPolicyObj = $this.OrgPolicyObj.user; 
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
                $controlResult.AddMessage([VerificationResult]::Manual, "Could not fetch external guest access policy details of the organization. This policy is available only when the organization is connected to AAD.");    
            }
        }
        else 
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch user policy details of the organization.");
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
                    $controlResult.AddMessage("No. of installed extensions: " + $extCount);

                    $trustedExtPublishers = $this.ControlSettings.Organization.TrustedExtensionPublishers;

                    $trustedExtensions = @(); #Publishers trusted by Microsoft
                    $trustedExtensions += $extensionList | Where-Object {$_.publisherName -in $trustedExtPublishers}
                    $trustedCount = ($trustedExtensions | Measure-Object).Count
                    
                    $unTrustedExtensions = @(); #Publishers not trusted by Microsoft
                    $unTrustedExtensions += $extensionList | Where-Object {$_.publisherName -notin $trustedExtPublishers}
                    $unTrustedCount = ($unTrustedExtensions | Measure-Object).Count
                    
                    $controlResult.AddMessage("`nList of trusted publishers: ", $trustedExtPublishers);
                    $controlResult.AddMessage([VerificationResult]::Verify, "`nReview the below list of installed extensions: ");  

                    if($unTrustedCount -gt 0){
                        $controlResult.AddMessage("`nNo. of installed extensions (from untrusted publishers): $unTrustedCount");
                        $controlResult.AddMessage("Installed extensions (from untrusted publishers): ", $unTrustedExtensions);
                    }

                    if($trustedCount -gt 0){
                        $controlResult.AddMessage("`nNo. of installed extensions (from trusted publishers): $trustedCount");
                        $controlResult.AddMessage("Installed extensions (from trusted publishers): ", $trustedExtensions);
                    }

                    $stateData = @{
                        Trusted_Extensions = @();
                        Untrusted_Extensions = @();
                    };

                    $stateData.Trusted_Extensions += $trustedExtensions
                    $stateData.Untrusted_Extensions += $unTrustedExtensions

                    $controlResult.SetStateData("List of installed extensions: ", $stateData);
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
                    $controlResult.AddMessage("No. of shared extensions: " + $sharedExtensions.Count)
                    $extensionList = @();
                    $extensionList +=  ($sharedExtensions | Select-Object extensionName,publisherId,publisherName,version) 

                    $controlResult.AddMessage([VerificationResult]::Verify, "Review the below list of shared extensions: ",$extensionList); 
                                                    
                    $controlResult.SetStateData("List of shared extensions: ", $extensionList);                                
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
            $apiURL = "https://{0}.vsaex.visualstudio.com/_apis/UserEntitlements?%24filter=userType%20eq%20%27guest%27&%24orderBy=name%20Ascending&api-version=5.1-preview.3" -f $($this.SubscriptionContext.SubscriptionName);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL); # returns a maximum of 100 guest users
            $guestUsers = @()
            if(($responseObj -ne $null) -and $responseObj.Count -gt 0 -and ([Helpers]::CheckMember($responseObj[0], 'members')))
            {
                $guestUsers += $responseObj[0].members
                $continuationToken =  $responseObj[0].continuationToken # Use the continuationToken for pagination
                while ($continuationToken -ne $null){
                    $urlEncodedToken = [System.Web.HttpUtility]::UrlEncode($continuationToken)
                    $apiURL = "https://{0}.vsaex.visualstudio.com/_apis/UserEntitlements?continuationToken=$urlEncodedToken&%24filter=userType%20eq%20%27guest%27&%24orderBy=name%20Ascending&api-version=5.1-preview.3" -f $($this.SubscriptionContext.SubscriptionName);
                    try{
                        $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                        $guestUsers += $responseObj[0].members
                        $continuationToken =  $responseObj[0].continuationToken
                    }
                    catch
                    {
                        # Eating the exception here as we could not fetch the further guest users
                        $continuationToken = $null
                    }
                }
                $guestList = @();
                $guestList +=  ($guestUsers | Select-Object @{Name="Id"; Expression = {$_.id}},@{Name="IdentityType"; Expression = {$_.user.subjectKind}},@{Name="DisplayName"; Expression = {$_.user.displayName}}, @{Name="MailAddress"; Expression = {$_.user.mailAddress}},@{Name="AccessLevel"; Expression = {$_.accessLevel.licenseDisplayName}},@{Name="LastAccessedDate"; Expression = {$_.lastAccessedDate}},@{Name="InactiveFromDays"; Expression = { if (((Get-Date) -[datetime]::Parse($_.lastAccessedDate)).Days -gt 10000){return "User was never active."} else {return ((Get-Date) -[datetime]::Parse($_.lastAccessedDate)).Days} }})
                $stateData = @();
                $stateData += ($guestUsers | Select-Object @{Name="Id"; Expression = {$_.id}},@{Name="IdentityType"; Expression = {$_.user.subjectKind}},@{Name="DisplayName"; Expression = {$_.user.displayName}}, @{Name="MailAddress"; Expression = {$_.user.mailAddress}})                
                # $guestListDetailed would be same if DetailedScan is not enabled.
                $guestListDetailed = $guestList 

                if([AzSKRoot]::IsDetailedScanRequired -eq $true)
                {
                    # If DetailedScan is enabled. fetch the project entitlements for the guest user
                    $guestListDetailed = $guestList | ForEach-Object {
                        try{
                            $guestUser = $_ 
                            $apiURL = "https://vsaex.dev.azure.com/{0}/_apis/userentitlements/{1}?api-version=6.0-preview.3" -f $($this.SubscriptionContext.SubscriptionName), $($guestUser.Id);
                            $projectEntitlements = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                            $userProjectEntitlements = $projectEntitlements[0].projectEntitlements
                        }
                        catch {
                            $userProjectEntitlements = "Could not fetch project entitlement details of the user."
                        }
                        return @{Id = $guestUser.Id; IdentityType = $guestUser.IdentityType; DisplayName = $guestUser.IdentityType; MailAddress = $guestUser.MailAddress; AccessLevel = $guestUser.AccessLevel; LastAccessedDate = $guestUser.LastAccessedDate; InactiveFromDays = $guestUser.InactiveFromDays; ProjectEntitlements = $userProjectEntitlements} 
                    }
                }
                
                $totalGuestCount = ($guestListDetailed | Measure-Object).Count
                $controlResult.AddMessage("Displaying all guest users in the organization...");
                $controlResult.AddMessage([VerificationResult]::Verify,"Total number of guest users in the organization: $($totalGuestCount)"); 
                
                $inactiveGuestUsers = $guestListDetailed | Where-Object { $_.InactiveFromDays -eq "User was never active." }
                $inactiveCount = ($inactiveGuestUsers | Measure-Object).Count
                if($inactiveCount) {
                    $controlResult.AddMessage("`nTotal number of guest users who were never active: $($inactiveCount)"); 
                    $controlResult.AddMessage("List of guest users who were never active: ",$inactiveGuestUsers);
                }
                
                $activeGuestUsers = $guestListDetailed | Where-Object { $_.InactiveFromDays -ne "User was never active." }    
                $activeCount = ($activeGuestUsers | Measure-Object).Count
                if($activeCount) {
                    $controlResult.AddMessage("`nTotal number of guest users who are active: $($activeCount)"); 
                    $controlResult.AddMessage("List of guest users who are active: ",$activeGuestUsers);
                }  
                $controlResult.SetStateData("Guest users list: ", $stateData);    
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
                $controlResult.AddMessage("No. of extension managers present: " + $responseObj.Count)
                $extensionManagerList = @();
                $extensionManagerList +=  ($responseObj | Select-Object @{Name="IdentityName"; Expression = {$_.identity.displayName}},@{Name="Role"; Expression = {$_.role.displayName}})
                $controlResult.AddMessage([VerificationResult]::Verify, "Review the below list of extension managers: ",$extensionManagerList);        
                $controlResult.SetStateData("List of extension managers: ", $extensionManagerList);   
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

        $topInActiveUsers = $this.ControlSettings.Organization.TopInActiveUserCount 
        $apiURL = "https://{0}.vsaex.visualstudio.com/_apis/UserEntitlements?top={1}&filter=&sortOption=lastAccessDate+ascending" -f $($this.SubscriptionContext.SubscriptionName), $topInActiveUsers;
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
                if($inactiveUsers.Count -ge $topInActiveUsers)
                {
                    $controlResult.AddMessage("Displaying top $($topInActiveUsers) inactive users")
                }
                #inactive user with days from how many days user is inactive, if user account created and was never active, in this case lastaccessdate is default 01-01-0001
                $inactiveUsers = ($inactiveUsers | Select-Object -Property @{Name="Name"; Expression = {$_.User.displayName}},@{Name="mailAddress"; Expression = {$_.User.mailAddress}},@{Name="InactiveFromDays"; Expression = { if (((Get-Date) -[datetime]::Parse($_.lastAccessedDate)).Days -gt 10000){return "User was never active."} else {return ((Get-Date) -[datetime]::Parse($_.lastAccessedDate)).Days} }})
                #set data for attestation
                $inactiveUsersStateData = ($inactiveUsers | Select-Object -Property @{Name="Name"; Expression = {$_.Name}},@{Name="mailAddress"; Expression = {$_.mailAddress}})
                
                $inactiveUsersCount = ($inactiveUsers | Measure-Object).Count
                $controlResult.AddMessage([VerificationResult]::Failed,"Total number of inactive users present in the organization: $($inactiveUsersCount)");
                $controlResult.SetStateData("Inactive users list: ", $inactiveUsersStateData);

                # segregate never active users from the list
                $neverActiveUsers = $inactiveUsers | Where-Object {$_.InactiveFromDays -eq "User was never active."}
                $inactiveUsersWithDays = $inactiveUsers | Where-Object {$_.InactiveFromDays -ne "User was never active."} 

                $neverActiveUsersCount = ($neverActiveUsers | Measure-Object).Count
                if ($neverActiveUsersCount -gt 0) {
                    $controlResult.AddMessage("`nTotal number of users who were never active: $($neverActiveUsersCount)");
                    $controlResult.AddMessage("Review users present in the organization who were never active: ",$neverActiveUsers);
                } 
                
                $inactiveUsersWithDaysCount = ($inactiveUsersWithDays | Measure-Object).Count
                if($inactiveUsersWithDaysCount -gt 0) {
                    $controlResult.AddMessage("`nTotal number of users who are inactive from last $($this.ControlSettings.Organization.InActiveUserActivityLogsPeriodInDays) days: $($inactiveUsersWithDaysCount)");                
                    $controlResult.AddMessage("Review users present in the organization who are inactive from last $($this.ControlSettings.Organization.InActiveUserActivityLogsPeriodInDays) days: ",$inactiveUsersWithDays);
                }
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed, "No inactive users found")   
            }
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed, "No inactive users found");
        }
        
        return $controlResult;
    }

    hidden [ControlResult] CheckDisconnectedIdentities([ControlResult] $controlResult)
    {
        try 
        {
            $apiURL = "https://{0}.visualstudio.com/_apis/OrganizationSettings/DisconnectedUser" -f $($this.SubscriptionContext.SubscriptionName);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            
            #disabling null check to CheckMember because if there are no disconnected users - it will return null.
            if ([Helpers]::CheckMember($responseObj[0], "users",$false)) 
            {
                if (($responseObj[0].users | Measure-Object).Count -gt 0 ) 
                {
        
                    $userNames = @();   
                    $userNames += ($responseObj[0].users | Select-Object -Property @{Name = "Name"; Expression = { $_.displayName } }, @{Name = "mailAddress"; Expression = { $_.preferredEmailAddress } })
                    $controlResult.AddMessage([VerificationResult]::Failed, "Remove access for below disconnected users: ", $userNames);  
                    $controlResult.SetStateData("Disconnected users list: ", $userNames);
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Passed, "No disconnected users found.");
                }   
            } 
        }
        catch 
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the list of disconnected users.");
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
        <# This control has been currently removed from control JSON file.
        {
            "ControlID": "ADO_Organization_AuthN_Enable_App_Access_OAuth",
            "Description": "OAuth should be enabled for third party application access",
            "Id": "Organization260",
            "ControlSeverity": "Medium",
            "Automated": "Yes",
            "MethodName": "CheckOAuthAppAccess",
            "Rationale": "TBD",
            "Recommendation": "Go to Organization Settings --> Security --> Policies --> Application connection policies --> Enable Third-party application access via OAuth",
            "Tags": [
                "SDL",
                "TCP",
                "Automated",
                "AuthN"
            ],
            "Enabled": true
        },
        #>
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
        <#This control has been currently removed from control JSON file.
        {
            "ControlID": "ADO_Organization_AuthN_Enable_SSH_Auth",
            "Description": "SSH authentication should be enabled for Application connection policies",
            "Id": "Organization280",
            "ControlSeverity": "Medium",
            "Automated": "Yes",
            "MethodName": "CheckSSHAuthn",
            "Rationale": "TBD",
            "Recommendation": "Go to Organization Settings --> Security --> Policies --> Application connection policies --> Enable SSH Authentication",
            "Tags": [
                "SDL",
                "TCP",
                "Automated",
                "AuthN"
            ],
            "Enabled": true
        },
        #>
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

    hidden [ControlResult] CheckSettableQueueTime([ControlResult] $controlResult)
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
                $controlResult.AddMessage([VerificationResult]::Passed, "Job authorization scope is limited to current project for non-release pipelines at organization level.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Failed, "Job authorization scope is set to project collection for non-release pipelines at organization level.");
            }       
       }
       else{
             $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the organization pipeline settings.");
       }       
        return $controlResult
    }

    hidden [ControlResult] CheckJobAuthZReleaseScope([ControlResult] $controlResult)
    {
       if($this.PipelineSettingsObj)
       {
            $orgLevelScope = $this.PipelineSettingsObj.enforceJobAuthScopeForReleases
            
            if($orgLevelScope -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Job authorization scope is limited to current project for release pipelines at organization level.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Failed, "Job authorization scope is set to project collection for release pipelines at organization level.");
            }       
       }
       else{
             $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the organization pipeline settings.");
       }       
        return $controlResult
    }

    hidden [ControlResult] CheckAuthZRepoScope([ControlResult] $controlResult)
    {
       if($this.PipelineSettingsObj)
       {
            $orgLevelScope = $this.PipelineSettingsObj.enforceReferencedRepoScopedToken
            
            if($orgLevelScope -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Job authorization scope of pipelines is limited to explicitly referenced Azure DevOps repositories at organization level.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Failed, "Job authorization scope of pipelines is set to all Azure DevOps repositories in the authorized projects at organization level.");
            }       
       }
       else{
             $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the organization pipeline settings.");
       }       
        return $controlResult
    }

    hidden [ControlResult] CheckBuiltInTask([ControlResult] $controlResult)
    {
       <# This control has been currently removed from control JSON file.
         {
            "ControlID": "ADO_Organization_SI_Review_BuiltIn_Tasks_Setting",
            "Description": "Review built-in tasks from being used in pipelines.",
            "Id": "Organization334",
            "ControlSeverity": "Medium",
            "Automated": "Yes",
            "MethodName": "CheckBuiltInTask",
            "Rationale": "Running built-in tasks from untrusted source can lead to all type of attacks and loss of sensitive enterprise data.",
            "Recommendation": "Go to Organization settings --> Pipelines --> Settings --> Task restrictions --> Turn on 'Disable built-in tasks' flag.",
            "Tags": [
                "SDL",
                "TCP",
                "Automated",
                "SI"
            ],
            "Enabled": true
         },
       #>
       if($this.PipelineSettingsObj)
       {
            $orgLevelScope = $this.PipelineSettingsObj.disableInBoxTasksVar
            
            if($orgLevelScope -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Built-in tasks are disabled at organization level.");
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Failed, "Built-in tasks are not disabled at organization level.");
            }       
       }
       else
       {
             $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the organization pipeline settings.");
       }       
        return $controlResult
    }

    hidden [ControlResult] CheckMarketplaceTask([ControlResult] $controlResult)
    {
        <# This control has been currently removed from control JSON file.
         {
            "ControlID": "ADO_Organization_SI_Review_Marketplace_Tasks_Setting",
            "Description": "Review Marketplace tasks from being used in pipelines.",
            "Id": "Organization336",
            "ControlSeverity": "Medium",
            "Automated": "Yes",
            "MethodName": "CheckMarketplaceTask",
            "Rationale": "Running Marketplace tasks from untrusted source can lead to all type of attacks and loss of sensitive enterprise data.",
            "Recommendation": "Go to Organization settings --> Pipelines --> Settings --> Task restrictions --> Turn on 'Disable Marketplace tasks'.",
            "Tags": [
                "SDL",
                "TCP",
                "Automated",
                "SI"
            ],
            "Enabled": true
         },
       #>
       if($this.PipelineSettingsObj)
       {
            $orgLevelScope = $this.PipelineSettingsObj.disableMarketplaceTasksVar
            
            if($orgLevelScope -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Market place tasks are disabled at organization level.");
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Failed, "Market place tasks are not disabled at organization level.");
            }       
       }
       else
       {
             $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the organization pipeline settings.");
       }       
        return $controlResult
    }

    hidden [ControlResult] CheckPolicyProjectTeamAdminUserInvitation([ControlResult] $controlResult)
    {
        if([Helpers]::CheckMember($this.OrgPolicyObj,"user"))
        {
            $userPolicyObj = $this.OrgPolicyObj.user
            $userInviteObj = $userPolicyObj | Where-Object {$_.Policy.Name -eq "Policy.AllowTeamAdminsInvitationsAccessToken"}
            if(($userInviteObj | Measure-Object).Count -gt 0)
            {
            
                if($userInviteObj.policy.effectiveValue -eq $false )
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,"Team and project administrators are not allowed to invite new users.");
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Failed, "Team and project administrators are allowed to invite new users.");
                }
            }
            else 
            {
                #Manual control status because the notion of team and project admins inviting new users is not applicable when AAD is not configured.
                $controlResult.AddMessage([VerificationResult]::Manual, "Could not fetch invite new user policy details of the organization. This policy is available only when the organization is connected to AAD.");    
            }
        }
        else 
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch user policy details of the organization.");
        }
        return $controlResult
    }

    hidden [ControlResult] CheckRequestAccessPolicy([ControlResult] $controlResult)
    {
        <# This control has been currently removed from control JSON file.
        {
            "ControlID": "ADO_Organization_AuthZ_Disable_Request_Access",
            "Description": "Stop your users from requesting access to your organization or project within your organization, by disabling the request access policy.",
            "Id": "Organization339",
            "ControlSeverity": "Medium",
            "Automated": "Yes",
            "MethodName": "CheckRequestAccessPolicy",
            "Rationale": "When request access policy is enabled, users can request access to a resource. Disabling this policy will prevent users from requesting access to organization or project within the organization.",
            "Recommendation": "Go to Organization Settings --> Policy --> User Policy --> Disable 'Request Access'.",
            "Tags": [
                "SDL",
                "TCP",
                "Automated",
                "AuthZ"
            ],
            "Enabled": true
        },
        #>
        if([Helpers]::CheckMember($this.OrgPolicyObj,"user"))
        {
            $userPolicyObj = $this.OrgPolicyObj.user
            $requestAccessObj = $userPolicyObj | Where-Object {$_.Policy.Name -eq "Policy.AllowRequestAccessToken"}
            if(($requestAccessObj | Measure-Object).Count -gt 0)
            {
            
                if($requestAccessObj.policy.effectiveValue -eq $false )
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,"Users can not request access to organization or projects within the organization.");
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Failed, "Users can request access to organization or projects within the organization.");
                }
            }
            else 
            {
                #Manual control status because the notion of request access is not applicable when AAD is not configured.
                $controlResult.AddMessage([VerificationResult]::Manual, "Could not fetch request access policy details of the organization. This policy is available only when the organization is connected to AAD.");    
            }
        }
        else 
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch user policy details of the organization.");
        }
        return $controlResult
    }
    
    hidden [ControlResult] CheckAutoInjectedExtensions([ControlResult] $controlResult)
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
                $controlResult.AddMessage([VerificationResult]::Verify,"Verify the below auto-injected tasks at organization level: ", $autoInjExt);
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
            $controlResult.AddMessage([VerificationResult]::Failed,"Number of administrators configured are less than the minimum required administrators count: $($this.ControlSettings.Organization.MinPCAMembersPermissible)");
        }
        else{
            $controlResult.AddMessage([VerificationResult]::Passed,"Number of administrators configured are more than the minimum required administrators count: $($this.ControlSettings.Organization.MinPCAMembersPermissible)");
        }
        if($TotalPCAMembers -gt 0){
            $controlResult.AddMessage("Verify the following Project Collection Administrators: ",$PCAMembers)
            $controlResult.SetStateData("List of Project Collection Administrators: ",$PCAMembers)
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
            $controlResult.AddMessage([VerificationResult]::Failed,"Number of administrators configured are more than the approved limit: $($this.ControlSettings.Organization.MaxPCAMembersPermissible)");
        }
        else{
            $controlResult.AddMessage([VerificationResult]::Passed,"Number of administrators configured are within than the approved limit: $($this.ControlSettings.Organization.MaxPCAMembersPermissible)");
        }
        if($TotalPCAMembers -gt 0){
            $controlResult.AddMessage("Verify the following Project Collection Administrators: ",$PCAMembers)
            $controlResult.SetStateData("List of Project Collection Administrators: ",$PCAMembers)
        }
    
        return $controlResult
    }

    hidden [ControlResult] CheckAuditStream([ControlResult] $controlResult)
    {
        
        try
        {
            $url ="https://auditservice.dev.azure.com/{0}/_apis/audit/streams?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($url);  
            
            # If no audit streams are configured, 'count' property is available for $responseObj[0] and its value is 0. 
            # If audit streams are configured, 'count' property is not available for $responseObj[0]. 
            #'Count' is a PSObject property and 'count' is response object property. Notice the case sensitivity here.
            
            # TODO: When there are no audit streams configured, CheckMember in the below condition returns false when checknull flag [third param in CheckMember] is not specified (default value is $true). Assiging it $false. Need to revisit.
            if(([Helpers]::CheckMember($responseObj[0],"count",$false)) -and ($responseObj[0].count -eq 0))
            {
                $controlResult.AddMessage([VerificationResult]::Failed, "No audit stream has been configured on the organization.");
            }
             # When audit streams are configured - the below condition will be true.
            elseif((-not ([Helpers]::CheckMember($responseObj[0],"count"))) -and ($responseObj.Count -gt 0)) 
            {
                $enabledStreams = $responseObj | Where-Object {$_.status -eq 'enabled'}
                if(($enabledStreams | Measure-Object).Count -gt 0)
                {
                    $controlResult.AddMessage([VerificationResult]::Passed, "One or more audit streams configured on the organization are currently enabled.");
                }
                else
                {
                    $controlResult.AddMessage([VerificationResult]::Failed, "None of the audit streams that have been configured are currently enabled.");
                }  
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Failed, "No audit stream has been configured on the organization.");
            }   
        }
        catch
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the list of audit streams enabled on the organization.");
        }
        return $controlResult
    }

}