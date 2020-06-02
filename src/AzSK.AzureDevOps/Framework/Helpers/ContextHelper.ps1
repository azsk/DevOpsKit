using namespace Microsoft.IdentityModel.Clients.ActiveDirectory
using namespace System.IO
using namespace System.Security.Cryptography

class MyTokenCache: TokenCache
{


}

class ContextHelper {
    
    static hidden [Context] $currentContext;
    static [bool] $bUseTokenCache = $false;

    hidden static [PSObject] GetCurrentContext()
    {
        if(-not [ContextHelper]::currentContext)
        {
            $clientId = [Constants]::DefaultClientId ;          
            $replyUri = [Constants]::DefaultReplyUri; 
            $azureDevOpsResourceId = [Constants]::DefaultAzureDevOpsResourceId;
            [AuthenticationContext] $ctx = $null;
            
            if ([ContextHelper]::bUseTokenCache)
            { 
                $tokenCache = [AzSKADOTokenCache]::new();  
                $ctx = [AuthenticationContext]::new("https://login.windows.net/common", $tokenCache);
            }
            else 
            {
                $ctx = [AuthenticationContext]::new("https://login.windows.net/common");
            }

            # TODO: what is this code for?
            if ($ctx.TokenCache.Count -gt 0)
            {
                [String] $homeTenant = $ctx.TokenCache.ReadItems().First().TenantId;
                $ctx = [AuthenticationContext]::new("https://login.microsoftonline.com/" + $homeTenant);
            }
        
            [AuthenticationResult] $result = $null;
            try 
            {
               $task = $ctx.AcquireTokenSilentAsync($azureDevOpsResourceId, $clientId).GetAwaiter();
               $result = $task.Wait(100); #100ms
            }
            catch  
            {
                $result = $ctx.AcquireToken($azureDevOpsResourceId, $clientId, [Uri]::new($replyUri), [PromptBehavior]::Auto);
            }

            [ContextHelper]::ConvertToContextObject($result);
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

    static [string] GetCurrentSessionUser() {
        $context = [ContextHelper]::GetCurrentContext()
        if ($null -ne $context) {
            return $context.Account.Id
        }
        else {
            return "NO_ACTIVE_SESSION"
        }
    }
}