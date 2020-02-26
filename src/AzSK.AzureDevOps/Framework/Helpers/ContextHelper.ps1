<#
.Description
# Context class for indenity details. 
# Provides functionality to login, create context, get token for api calls
#>
using namespace Microsoft.IdentityModel.Clients.ActiveDirectory

class ContextHelper {
    
    static hidden [Context] $currentContext;

    hidden static [PSObject] GetCurrentContext()
    {
        if(-not [ContextHelper]::currentContext)
        {
            $clientId = [Constants]::DefaultClientId ;          
            $replyUri = [Constants]::DefaultReplyUri; 
            $azureDevOpsResourceId = [Constants]::DefaultAzureDevOpsResourceId;
            [AuthenticationContext] $ctx = $null;

            $ctx = [AuthenticationContext]::new("https://login.windows.net/common");
            if ($ctx.TokenCache.Count -gt 0)
            {
                [String] $homeTenant = $ctx.TokenCache.ReadItems().First().TenantId;
                $ctx = [AuthenticationContext]::new("https://login.microsoftonline.com/" + $homeTenant);
            }
            [AuthenticationResult] $result = $null;
            $result = $ctx.AcquireToken($azureDevOpsResourceId, $clientId, [Uri]::new($replyUri),[PromptBehavior]::Always);
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
        # TODO: Handlle login
        if([ContextHelper]::currentContext)
        {
            #ConvertFrom-SecureString
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
        #$contextObj.AccessToken = $patToken
        #$contextObj.AccessToken =  ConvertTo-SecureString -String $context.AccessToken -asplaintext -Force
        [ContextHelper]::currentContext = $contextObj
    }
}