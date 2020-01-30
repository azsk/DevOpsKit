<#
.Description
# Context class for indenity details. 
# Provides functionality to login, create context, get token for api calls
#>
using namespace Microsoft.IdentityModel.Clients.ActiveDirectory

class ContextHelper {
    
    #static hidden [Context] $currentContext;
    static hidden [PSObject] $currentPPContext = $null;

    hidden static [PSObject] GetCurrentContext()
    {
        if ([ContextHelper]::currentPPContext -eq $null)
        {
            Set-StrictMode -Off
            if ($Global:currentSession -eq $null)
            {
                Add-PowerAppsAccount
            }
            [ContextHelper]::currentPPContext = $Global:currentSession
            Set-StrictMode -Version Latest
        }

        return [ContextHelper]::currentPPContext;
    }
    
    static [string] GetAccessToken([string] $resourceAppIdUri) {
            return [ContextHelper]::GetAccessToken()   
    }

    static [string] GetAccessToken()
    {
        # TODO: Handlle login
        if([ContextHelper]::currentPPContext)
        {
            #ConvertFrom-SecureString
            return  [ContextHelper]::currentPPContext.idToken
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
        #TODO-PP: fix
        $contextObj = [Context]::new()
        $contextObj.Account.Id = $context.UserInfo.DisplayableId
        $contextObj.Tenant.Id = $context.TenantId 
        $contextObj.AccessToken = $context.AccessToken
        #$contextObj.AccessToken =  ConvertTo-SecureString -String $context.AccessToken -asplaintext -Force
        [ContextHelper]::currentPPContext = $contextObj
    }
}