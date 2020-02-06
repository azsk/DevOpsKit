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
          Write-Host "Login Code Here......................"
          [ContextHelper]::currentContext = [Context]::new()
          [ContextHelper]::currentContext.Account.Id = "User Id"
          [ContextHelper]::currentContext.Tenant.Id = "Tenant Id" 
          [ContextHelper]::currentContext.AccessToken = "Access Token"
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
}