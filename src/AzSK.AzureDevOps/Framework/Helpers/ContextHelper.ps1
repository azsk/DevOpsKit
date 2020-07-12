<#
.Description
# Context class for indenity details. 
# Provides functionality to login, create context, get token for api calls
#>
using namespace Microsoft.IdentityModel.Clients.ActiveDirectory

class ContextHelper {
    
    static hidden [Context] $currentContext;
    
    #This will be used to carry current org under current context.
    static hidden [string] $orgName;
    static [int] $TotalPCAMembers=0;
    static [int] $TotalPAMembers=0; 
    static [bool] $isCurrentUserPCA=$false;
    static [bool] $isCurrentUserPA=$false;

    hidden static [PSObject] GetCurrentContext()
    {
        return [ContextHelper]::GetCurrentContext($false);
    }

    hidden static [PSObject] GetCurrentContext([bool]$authNRefresh)
    {
        if( (-not [ContextHelper]::currentContext) -or $authNRefresh)
        {
            $clientId = [Constants]::DefaultClientId ;          
            $replyUri = [Constants]::DefaultReplyUri; 
            $azureDevOpsResourceId = [Constants]::DefaultAzureDevOpsResourceId;
            [AuthenticationContext] $ctx = $null;

            $ctx = [AuthenticationContext]::new("https://login.windows.net/common");

            [AuthenticationResult] $result = $null;

            $azSKUI = $null;
            if ( !$authNRefresh -and ($azSKUI = Get-Variable 'AzSKADOLoginUI' -Scope Global -ErrorAction 'Ignore')) {
                if ($azSKUI.Value -eq 1) {
                    $result = $ctx.AcquireToken($azureDevOpsResourceId, $clientId, [Uri]::new($replyUri),[PromptBehavior]::Always);
                }
                else {
                    $result = $ctx.AcquireToken($azureDevOpsResourceId, $clientId, [Uri]::new($replyUri),[PromptBehavior]::Auto);
                }
            }
            else {
                $result = $ctx.AcquireToken($azureDevOpsResourceId, $clientId, [Uri]::new($replyUri),[PromptBehavior]::Auto);
            }

            [ContextHelper]::ConvertToContextObject($result)
        }
        return [ContextHelper]::currentContext
    }
    
    hidden static [PSObject] GetCurrentContext([System.Security.SecureString] $PATToken)
    {
        if(-not [ContextHelper]::currentContext)
        {
            [ContextHelper]::ConvertToContextObject($PATToken)
        }
        return [ContextHelper]::currentContext
    }

    static [string] GetAccessToken([string] $resourceAppIdUri) {
            return [ContextHelper]::GetAccessToken()   
    }

    static [string] GetAccessToken()
    {
        if([ContextHelper]::currentContext)
        {
            # Validate if token is PAT using lenght (PAT has lengh of 52), if PAT dont go to refresh login session.
            #TODO: Change code to find token type supplied PAT or login session token
            #if token expiry is within 2 min, refresh.
            if (([ContextHelper]::currentContext.AccessToken.length -ne 52) -and ([ContextHelper]::currentContext.TokenExpireTimeLocal -le [DateTime]::Now.AddMinutes(2)))
            {
                [ContextHelper]::GetCurrentContext($true);
            }
            return  [ContextHelper]::currentContext.AccessToken
        }
        else
        {
            return $null
        }
    }

    hidden [SubscriptionContext] SetContext([string] $subscriptionId)
    {
        if((-not [string]::IsNullOrEmpty($subscriptionId)))
              {
                     $SubscriptionContext = [SubscriptionContext]@{
                           SubscriptionId = $subscriptionId;
                           Scope = "/Organization/$subscriptionId";
                           SubscriptionName = $subscriptionId;
                     };
                     # $subscriptionId contains the organization name (due to framework).
                     [ContextHelper]::orgName = $subscriptionId;
                     [ContextHelper]::GetCurrentContext()                  
              }
              else
              {
                     throw [SuppressedException] ("OrganizationName name [$subscriptionId] is either malformed or incorrect.")
        }
        return $SubscriptionContext;
    }

    hidden [SubscriptionContext] SetContext([string] $subscriptionId, [System.Security.SecureString] $PATToken)
    {
        if((-not [string]::IsNullOrEmpty($subscriptionId)))
              {
                     $SubscriptionContext = [SubscriptionContext]@{
                           SubscriptionId = $subscriptionId;
                           Scope = "/Organization/$subscriptionId";
                           SubscriptionName = $subscriptionId;
                     };
                     # $subscriptionId contains the organization name (due to framework).
                     [ContextHelper]::orgName = $subscriptionId;
                     [ContextHelper]::GetCurrentContext($PATToken)         
              }
              else
              {
                     throw [SuppressedException] ("OrganizationName name [$subscriptionId] is either malformed or incorrect.")
        }
        return $SubscriptionContext;
    }

    static [void] ResetCurrentContext()
    {
        
    }

    hidden static ConvertToContextObject([PSObject] $context)
    {
        $contextObj = [Context]::new()
        $contextObj.Account.Id = $context.UserInfo.DisplayableId
        $contextObj.Tenant.Id = $context.TenantId 
        $contextObj.AccessToken = $context.AccessToken
        
        # Here subscription basically means ADO organization (due to framework).
        # We do not get ADO organization Id as part of current context. Hence appending org name to both Id and Name param.
        $contextObj.Subscription = [Subscription]::new()
        $contextObj.Subscription.Id = [ContextHelper]::orgName
        $contextObj.Subscription.Name = [ContextHelper]::orgName 
        
        $contextObj.TokenExpireTimeLocal = $context.ExpiresOn.LocalDateTime
        #$contextObj.AccessToken =  ConvertTo-SecureString -String $context.AccessToken -asplaintext -Force
        [ContextHelper]::currentContext = $contextObj
    }

    hidden static ConvertToContextObject([System.Security.SecureString] $patToken)
    {
        $contextObj = [Context]::new()
        $contextObj.Account.Id = [string]::Empty
        $contextObj.Tenant.Id =  [string]::Empty
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($patToken)
        $contextObj.AccessToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        
        # Here subscription basically means ADO organization (due to framework).
        # We do not get ADO organization Id as part of current context. Hence appending org name to both Id and Name param.
        $contextObj.Subscription = [Subscription]::new()
        $contextObj.Subscription.Id = [ContextHelper]::orgName
        $contextObj.Subscription.Name = [ContextHelper]::orgName 

        #$contextObj.AccessToken = $patToken
        #$contextObj.AccessToken =  ConvertTo-SecureString -String $context.AccessToken -asplaintext -Force
        [ContextHelper]::currentContext = $contextObj
    }

    static [string] GetCurrentSessionUser() {
        $context = [ContextHelper]::GetCurrentContext()
        if ($null -ne $context) {
            return $context.Account.Id
        }
        else {
            return "NO_ACTIVE_SESSION"
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
            [ContextHelper]::FindPCAMembers($prcollobj.descriptor,$OrgName)
        }
    }
    catch {

    }
    }

    static [void] GetPADescriptorAndMembers([string] $OrgName){
        
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

        $accname = "Project Administrators"; 
        $prcollobj = $responseObj.dataProviders.'ms.vss-admin-web.org-admin-groups-data-provider'.identities | where {$_.displayName -eq $accname}
        
        

        if(($prcollobj | Measure-Object).Count -gt 0){
            [ContextHelper]::FindPAMembers($prcollobj.descriptor,$OrgName)
        }
    }
    catch {

    }
    }


    static [void] FindPCAMembers([string]$descriptor,[string] $OrgName){
        $url="https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.1-preview" -f $($OrgName);
        $postbody=@'
        {"contributionIds":["ms.vss-admin-web.org-admin-members-data-provider"],"dataProviderContext":{"properties":{"subjectDescriptor":"{0}","sourcePage":{"url":"https://{2}.visualstudio.com/_settings/groups?subjectDescriptor={1}","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute","serviceHost":"cdcc3dee-d62a-41ee-aded-daf587e1851b (MicrosoftIT)"}}}}}
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
                return [ContextHelper]::FindPCAMembers($_.descriptor,$OrgName)
            }
            else{
                if([ContextHelper]::isCurrentUserPCA -eq $false -and [ContextHelper]::GetCurrentSessionUser() -eq $_.mailAddress){
                    [ContextHelper]::isCurrentUserPCA=$true;
                }
                [ContextHelper]::TotalPCAMembers++
            }
            }
        }
        catch {
            Write-Host $_
        }
		

    }

    static [void] FindPAMembers([string]$descriptor,[string] $OrgName){
        $url="https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.1-preview" -f $($OrgName);
        $postbody=@'
        {"contributionIds":["ms.vss-admin-web.org-admin-members-data-provider"],"dataProviderContext":{"properties":{"subjectDescriptor":"{0}","sourcePage":{"url":"https://{2}.visualstudio.com/_settings/groups?subjectDescriptor={1}","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute","serviceHost":"cdcc3dee-d62a-41ee-aded-daf587e1851b (MicrosoftIT)"}}}}}
'@
        $postbody=$postbody.Replace("{0}",$descriptor)
        $postbody=$postbody.Replace("{1}",$OrgName)
        $post='{"contributionIds":["ms.vss-admin-web.org-admin-members-data-provider"],"dataProviderContext":{"properties":{"subjectDescriptor":"{0}","sourcePage":{"url":"https://{2}.visualstudio.com/_settings/groups?subjectDescriptor={1}","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute","serviceHost":"cdcc3dee-d62a-41ee-aded-daf587e1851b (MicrosoftIT)"}}}}}' | ConvertFrom-Json
		$post.dataProviderContext.properties.subjectDescriptor = $descriptor;
		$post.dataProviderContext.properties.sourcePage.url = "https://$($OrgName).visualstudio.com/_settings/groups?subjectDescriptor=$($descriptor)";
        $rmContext = [ContextHelper]::GetCurrentContext();
		$user = "";
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
        try {
            $response = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $postbody
            $data=$response.dataProviders.'ms.vss-admin-web.org-admin-members-data-provider'.identities
            $data | ForEach-Object{
    
            if($_.subjectKind -eq "group"){
                return [ContextHelper]::FindPCAMembers($_.descriptor,$OrgName)
            }
            else{
                if([ContextHelper]::isCurrentUserPA -eq $false -and [ContextHelper]::GetCurrentSessionUser() -eq $_.mailAddress){
                    [ContextHelper]::isCurrentUserPA=$true;
                }
                [ContextHelper]::TotalPAMembers++
            }
            }
        }
        catch {
            Write-Host $_
        }
		

    }

    static [int] GetTotalPCAMembers([string] $OrgName){
        [ContextHelper]::GetPCADescriptorAndMembers($OrgName)
        return [ContextHelper]::TotalPCAMembers
    }
    static [int] GetTotalPAMembers([string] $OrgName){
        [ContextHelper]::GetPADescriptorAndMembers($OrgName)
        return [ContextHelper]::TotalPAMembers
    }
    static [bool] GetIsCurrentUserPCA([string] $OrgName){
        [ContextHelper]::GetPCADescriptorAndMembers($OrgName)
        return [ContextHelper]::isCurrentUserPCA
    }
    static [bool] GetIsCurrentUserPA([string] $OrgName){
        [ContextHelper]::GetPADescriptorAndMembers($OrgName)
        return [ContextHelper]::isCurrentUserPA
    }
}