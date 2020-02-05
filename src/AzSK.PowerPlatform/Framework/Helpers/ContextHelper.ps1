<#
.Description
# Context class for indenity details. 
# Provides functionality to login, create context, get token for api calls
#>
using namespace Microsoft.IdentityModel.Clients.ActiveDirectory

class ContextHelper {
    
    static hidden [Context] $currentPPContext;
    #static hidden [PSObject] $currentPPContext = $null;

    hidden static [PSObject] GetCurrentContext()
    {
        if ([ContextHelper]::currentPPContext -eq $null)
        {
            Set-StrictMode -Off
            if ($Global:currentSession -eq $null)
            {
                Add-PowerAppsAccount
            }
            [ContextHelper]::currentPPContext = [ContextHelper]::ConvertToContextObject($Global:currentSession)
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
            return  [ContextHelper]::currentPPContext.AccessToken
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

    hidden static [Context] ConvertToContextObject([PSObject] $ppSession)
    {
        $contextObj = [Context]::new()
        $contextObj.Account.Id = $ppSession.upn 
        $contextObj.Tenant.Id = $ppSession.TenantId 
        $contextObj.AccessToken = $ppSession.idToken  #TODO-PP: there is also refreshToken in the ppSesssion plus resourceTokens.
            #$ppSession.resourceTokens."https://service.powerapps.com/".accessToken #TODO-PP: This starts with Azure-mgmt, but also collects PP-API token.
        return $contextObj
        
    }
}