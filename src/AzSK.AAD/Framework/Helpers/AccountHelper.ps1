using namespace Newtonsoft.Json
using namespace Microsoft.Azure.Commands.Common.Authentication.Abstractions
using namespace Microsoft.Azure.Commands.Common.Authentication
using namespace Microsoft.Azure.Management.Storage.Models
using namespace Microsoft.IdentityModel.Clients.ActiveDirectory

Set-StrictMode -Version Latest

class AccountHelper {
    static hidden [PSObject] $currentAADContext;
    static hidden [PSObject] $currentAzContext;
    static hidden [PSObject] $currentRMContext;
    static hidden [PSObject] $AADAPIAccessToken;
    static hidden [string] $tenantInfoMsg;
    static hidden [CommandType] $ScanType;

    hidden static [PSObject] GetCurrentRMContext()
	{
		if (-not [AccountHelper]::currentRMContext)
		{
			$rmContext = Get-AzContext -ErrorAction Stop

			if ((-not $rmContext) -or ($rmContext -and (-not $rmContext.Subscription -or -not $rmContext.Account))) {
				[EventBase]::PublishGenericCustomMessage("No active Azure login session found. Initiating login flow...", [MessageType]::Warning);
                [PSObject]$rmLogin = $null
                $AzureEnvironment = [Constants]::DefaultAzureEnvironment
                $AzskSettings = [Helpers]::LoadOfflineConfigFile("AzSK.AzureDevOps.Settings.json", $true)          
                if([Helpers]::CheckMember($AzskSettings,"AzureEnvironment"))
                {
                   $AzureEnvironment = $AzskSettings.AzureEnvironment
                }
                if(-not [string]::IsNullOrWhiteSpace($AzureEnvironment) -and $AzureEnvironment -ne [Constants]::DefaultAzureEnvironment) 
                {
                    try{
                        $rmLogin = Connect-AzAccount -EnvironmentName $AzureEnvironment
                    }
                    catch{
                        [EventBase]::PublishGenericException($_);
                    }         
                }
                else
                {
                $rmLogin = Connect-AzAccount
                }
				if ($rmLogin) {
                    $rmContext = $rmLogin.Context;	
				}
            }
            [AccountHelper]::currentRMContext = $rmContext
		}

		return [AccountHelper]::currentRMContext
	}

    hidden static [PSObject] GetCurrentAzContext()
    {
        if ([AccountHelper]::currentAzContext -eq $null)
        {
            throw "Cannot call this method before getting a sign-in context"
        }
        return [AccountHelper]::currentAzContext
    }
    
    hidden static [PSObject] GetCurrentAzContext($desiredTenantId)
    {
        if(-not [AccountHelper]::currentAzContext)
        {
            $azContext = Get-AzContext 

            if ($azContext -eq $null -or ($desiredTenantId -ne $null -and $azContext.Tenant.Id -ne $desiredTenantId))
            {
                if ($azContext) #If we have a context for another tenant, disconnect.
                {
                    Disconnect-AzAccount -ErrorAction Stop
                }
                #Now try to fetch a fresh context.
                try {
                        $azureContext = Connect-AzAccount -ErrorAction Stop
                        #On a fresh login, the 'cached' context object we care about is inside the AzureContext
                        $azContext = $azureContext.Context 
                }
                catch {
                    Write-Error("Could not login to Azure environment...")
                    throw ("TODO: SuppressedException? Could not login to Azure envmt.")   
                }
            }
            [AccountHelper]::currentAzContext = $azContext
        }
        return [AccountHelper]::currentAzContext
    }

    hidden static [PSObject] GetCurrentAADContext()
    {
        if ([AccountHelper]::currentAADContext -eq $null)
        {
            throw "Cannot call this method before getting a sign-in context"
        }
        return [AccountHelper]::currentAADContext
    }

    hidden static [PSObject] GetCurrentAADContext($desiredTenantId)
    {
        if(-not [AccountHelper]::currentAADContext)
        {
            $aadContext = $null
            #Try leveraging Azure context if available
            try {
                #Either throws or returns non-null
                $azContext = [AccountHelper]::GetCurrentAzContext($desiredTenantId)

                $tenantId = $azContext.Tenant.Id
                $accountId = $azContext.Account.Id
                $aadContext = Connect-AzureAD -TenantId $tenantId -AccountId $accountId -ErrorAction Stop
            }
            catch {
                Write-Warning("Could not get Az/AzureAD context.")
                throw "TODO: ExceptionType?. Could not get Az/AAD context."
            }

            [AccountHelper]::ScanType = [CommandType]::AAD
            [AccountHelper]::currentAADContext = $aadContext
            
            [AccountHelper]::tenantInfoMsg = "Current AAD Domain: $($aadContext.TenantDomain)`nTenanId: $($aadContext.TenantId)"
        }

        return [AccountHelper]::currentAADContext
    }

    static [string] GetCurrentTenantInfo()
    {
        return [AccountHelper]::tenantInfoMsg
    }

    static [string] GetCurrentSessionUser() 
    {
        $context = [AccountHelper]::GetCurrentAADContext() 
        if ($null -ne $context) {
            return $context.Account.Id
        }
        else {
            return "NO_ACTIVE_SESSION"
        }
    }
    
    hidden static [PSObject] GetCurrentAADAPIToken()
    {
        if(-not [AccountHelper]::AADAPIAccessToken)
        {
            $apiToken = $null
            
            $AADAPIGuid = "74658136-14ec-4630-ad9b-26e160ff0fc6" #BUGBUG: Resolve loading order issue if we use [WebRequestHelper]::GetAADAPIGuid();

            #Try leveraging Azure context if available
            try {
                #Either throws or returns non-null
                $azContext = [AccountHelper]::GetCurrentAzContext()
                $apiToken = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($azContext.Account, $azContext.Environment, $azContext.Tenant.Id, $null, "Never", $null, $AADAPIGuid)
            }
            catch {
                Write-Warning("Could not get AAD API token for $AADAPIGuid.")
                throw "TODO: ExceptionType?. Could not get AAD API token for $AADAPIGuid."
            }

            [AccountHelper]::AADAPIAccessToken = $apiToken
            Write-Host("Successfully acquired API access token for $AADAPIGuid")
		}
        return [AccountHelper]::AADAPIAccessToken
    }

    
	hidden static [void] ResetCurrentRMContext()
	{
		[AccountHelper]::currentRMContext = $null
	}

    static [string] GetAccessToken([string] $resourceAppIdUri, [string] $tenantId) 
    {
        return [AccountHelper]::GetAzureDevOpsAccessToken();
    }

    static [string] GetAzureDevOpsAccessToken()
    {
        # TODO: Handlle login
        if([AccountHelper]::currentAzureDevOpsContext)
        {
            return [AccountHelper]::currentAzureDevOpsContext.AccessToken
        }
        else
        {
            return $null
        }
    }

    static [string] GetAccessToken([string] $resourceAppIdUri) 
    {
        if([AccountHelper]::ScanType -eq [CommandType]::AzureDevOps)
        {
            return [AccountHelper]::GetAzureDevOpsAccessToken()
        }
        else {
            return [AccountHelper]::GetAccessToken($resourceAppIdUri, "");    
        }
        
    }

    static [string] GetAccessToken()
    {
        if([AccountHelper]::ScanType -eq [CommandType]::AzureDevOps)
        {
            return [AccountHelper]::GetAzureDevOpsAccessToken()
        }
        else {
            #TODO : Fix ResourceID
            return [AccountHelper]::GetAccessToken("", "");    
        }
    }
}

