using namespace Newtonsoft.Json
using namespace Microsoft.Azure.Commands.Common.Authentication.Abstractions
using namespace Microsoft.Azure.Commands.Common.Authentication
using namespace Microsoft.Azure.Management.Storage.Models
using namespace Microsoft.IdentityModel.Clients.ActiveDirectory

Set-StrictMode -Version Latest



# Represents subset of directory roles that we check against for 'AAD admin-or-not'
[Flags()]
enum PrivilegedAADRoles
{
    None = 0
    SecurityReader = 1
    UserAccountAdmin = 2
    SecurityAdmin = 4
    CompanyAdmin = 8
}

#Creates an object for our (internal) representation of a privileged role
#The term 'privileged' or 'privRole' here refers to directory roles we consider in 'admin-or-not' check
#It does not refer to AAD-PIM (at least as yet)
function New-PrivRole()
{
  param ($DisplayName, $ObjectId, $AADPrivRole)

  $privRole = new-object PSObject

  $privRole | add-member -type NoteProperty -Name DisplayName -Value $DisplayName
  $privRole | add-member -type NoteProperty -Name ObjectId -Value $ObjectId
  $privRole | add-member -type NoteProperty -Name AADPrivRole -Value $AADPrivRole

  return $privRole
}

class AccountHelper {
    static hidden [PSObject] $currentAADContext;
    static hidden [PSObject] $currentAzContext;
    static hidden [PSObject] $currentRMContext;
    static hidden [PSObject] $AADAPIAccessToken;
    static hidden [string] $tenantInfoMsg;

    static hidden [PSObject] $currentAADUserObject;

    static hidden [CommandType] $ScanType;

    static hidden [PrivilegedAADRoles] $UserAADPrivRoles = [PrivilegedAADRoles]::None; 
    static hidden [bool] $rolesLoaded = $false;

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
    
    # Can be called with $null (when tenantId is not specified by the user)
    hidden static [PSObject] GetCurrentAzContext($desiredTenantId)
    {
        if(-not [AccountHelper]::currentAzContext)
        {
            $azContext = Get-AzContext 

            #If there's no Az ctx, or it is indeterminate (user has no Azure subscription) or the tenantId in the azCtx does not match desired tenantId
            if ($azContext -eq $null -or $azContext.Tenant -eq $null -or (-not [string]::IsNullOrEmpty($desiredTenantId) -and $azContext.Tenant.Id -ne $desiredTenantId))
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

    hidden static [PSObject] GetCurrentAADContext($desiredTenantId) #Can be $null if user did not pass one.
    {
        if(-not [AccountHelper]::currentAADContext)
        {
            $aadContext = $null
            $aadUserObj = $null
            #Try leveraging Azure context if available
            try {
                #Either throws or returns non-null
                $azContext = [AccountHelper]::GetCurrentAzContext($desiredTenantId)

                $accountId = $azContext.Account.Id

                if ($azContext.Tenant -ne $null)
                {
                    $tenantId = $azContext.Tenant.Id
                    $aadContext = Connect-AzureAD -TenantId $tenantId -AccountId $accountId -ErrorAction Stop
                }
                else 
                {
                    $aadContext = Connect-AzureAd -AccountId $accountId -ErrorAction Stop
                    $tenantId = $aadContext.TenantId
                }

                $upn = $aadContext.Account.Id
                $aadUserObj = Get-AzureADUser -Filter "UserPrincipalName eq '$upn'"
            }
            catch {
                Write-Warning("Could not get Az/AzureAD context.")
                throw "TODO: ExceptionType?. Could not get Az/AAD context."
            }

            [AccountHelper]::ScanType = [CommandType]::AAD
            [AccountHelper]::currentAADContext = $aadContext
            [AccountHelper]::currentAADUserObject = $aadUserObj
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

    hidden static [PSObject] GetCurrentAADUserObject()
    {
        return [AccountHelper]::currentAADUserObject   
    }

    hidden static [PSObject] GetEnabledPrivRolesInTenant()
    {
        #Get subset of directory level roles that have been enabled in this tenant. (Not orgs enable all roles.)
        $enabledDirRoles = [array] (Get-AzureADDirectoryRole)

        #$srRole = $activeRoles | ? { $_.DisplayName -eq "Security Reader"}
        
        $apr = @()
        $enabledDirRoles | % {
            $ar = $_
        
            switch ($ar.DisplayName)
            {
                'Security Reader' { 
                    $apr += New-PrivRole -DisplayName 'Security Reader' -ObjectId $ar.ObjectId -AADPrivRole ([PrivilegedAADRoles]::SecurityReader)
                }
        
                'User Account Administrator' { 
                    $apr += New-PrivRole -DisplayName 'User Account Administrator' -ObjectId $ar.ObjectId -AADPrivRole ([PrivilegedAADRoles]::UserAccountAdmin)
                }
                 
                'Security Administrator' {
                    $apr += New-PrivRole -DisplayName 'Security Administrator' -ObjectId $ar.ObjectId -AADPrivRole ([PrivilegedAADRoles]::SecurityAdmin)
                }
        
                'Company Administrator' {
                    $apr += New-PrivRole -DisplayName 'Company Administrator' -ObjectId $ar.ObjectId -AADPrivRole ([PrivilegedAADRoles]::CompanyAdmin)
                }
            }
        }
        return $apr        
    } 

    #Returns a bit flag representing all roles we consider 'admin-like' that the user is currently a member of. 
    #TODO: This only uses 'permanent' membership checks currently. Need to augment for PIM.
    static [PrivilegedAADRoles] GetUserPrivTenantRoles([String] $uid)
    {
        if ([AccountHelper]::rolesLoaded -eq $false)
        {
            $upr = [PrivilegedAADRoles]::None
            $apr = [AccountHelper]::GetEnabledPrivRolesInTenant()
            $apr | % {
                $pr = $_
                #Write-Host "$pr.AADPrivRole"
                $roleMembers = [array] (Get-AzureADDirectoryRoleMember -ObjectId $pr.ObjectId)
                #Write-Host "Count: $($roleMembers.Count)"
                $roleMembers | % { if ($_.ObjectId -eq $uid) {$upr = $upr -bor $pr.AADPrivRole}}
            }    

            [AccountHelper]::UserAADPrivRoles = $upr
            [AccountHelper]::rolesLoaded = $true
        }
        return [AccountHelper]::UserAADPrivRoles
    }

    #Is user a member of any directory role we consider 'admin-equiv.'?
    #Note: #TODO: This does not check for PIM-based role membership yet.
    static [bool] IsUserInAPermanentAdminRole()
    {
        $uid = ([AccountHelper]::GetCurrentAADUserObject()).ObjectId
        $upr = [AccountHelper]::GetUserPrivTenantRoles($uid)
        return ($upr -ne [PrivilegedAADRoles]::None) 
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
                $tenantId = $null
                if ($azContext.Tenant -ne $null) #happens if user does not have any Azure subs.
                {
                    $tenantId = $azContext.Tenant.Id
                }
                else {
                    $tenantId = ([AccountHelper]::GetCurrentAADContext()).TenantId 
                }
                $apiToken = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($azContext.Account, $azContext.Environment, $tenantId, $null, "Never", $null, $AADAPIGuid)
            }
            catch {
                Write-Warning("Could not get AAD API token for $AADAPIGuid.")
                throw "TODO: ExceptionType?. Could not get AAD API token for $AADAPIGuid."
            }

            [AccountHelper]::AADAPIAccessToken = $apiToken
            #TODO move to detailed log: Write-Host("Successfully acquired API access token for $AADAPIGuid")
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
