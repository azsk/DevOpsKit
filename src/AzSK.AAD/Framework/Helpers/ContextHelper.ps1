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

class ContextHelper {
    static hidden [PSObject] $currentAADContext;
    static hidden [PSObject] $currentAzContext;
    static hidden [PSObject] $currentRMContext;
    static hidden [PSObject] $AADAPIAccessToken;

	#TODO: 'static' => most of these will get set for session! (Also statics in [Tenant] class)
	#TODO: May need to consider situations where user runs for 2 diff tenants in same session...
    static hidden [string] $tenantInfoMsg; 

    static hidden [PSObject] $currentAADUserObject;

    static hidden [CommandType] $ScanType;

    static hidden [PrivilegedAADRoles] $UserAADPrivRoles = [PrivilegedAADRoles]::None; 
    static hidden [bool] $rolesLoaded = $false;

    hidden static [PSObject] GetCurrentContext()
	{
		if (-not [ContextHelper]::currentRMContext)
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
            [ContextHelper]::currentRMContext = $rmContext
		}

		return [ContextHelper]::currentRMContext
	}

    hidden static [PSObject] GetCurrentAzContext()
    {
        if ([ContextHelper]::currentAzContext -eq $null)
        {
            throw ([SuppressedException]::new(("Cannot call this method before getting a sign-in context!"), [SuppressedExceptionType]::InvalidOperation))
        }
        return [ContextHelper]::currentAzContext
    }

    hidden static [void] ClearTenantContext()
    {
        [ContextHelper]::currentAADContext = $null;
        [ContextHelper]::currentAzContext = $null;
        [ContextHelper]::currentRMContext = $null;
        [ContextHelper]::AADAPIAccessToken = $null;
        [ContextHelper]::tenantInfoMsg = $null;

        [ContextHelper]::currentAADUserObject = $null;
        
        [ContextHelper]::UserAADPrivRoles = [PrivilegedAADRoles]::None; 
        [ContextHelper]::rolesLoaded = $false;    
    }
    
    # Can be called with $null (when tenantId is not specified by the user)
    hidden static [PSObject] GetCurrentAzContext($desiredTenantId)
    {
        if(-not [ContextHelper]::currentAzContext)
        {
            $azContext = Get-AzContext 

            #If there's no Az ctx, or it is indeterminate (user has no Azure subscription) or the tenantId in the azCtx does not match desired tenantId
            if ($azContext -eq $null -or $azContext.Tenant -eq $null -or (-not [string]::IsNullOrEmpty($desiredTenantId) -and $azContext.Tenant.Id -ne $desiredTenantId))
            {
                #TODO: Consider simplifying this...use AzCtx only if no tenantId or tenantId matches...for all else just do fresh ConnectAzureAD??
                #Better than clearing up existing AzCtx a user may want to keep using otherwise.
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
                    Write-Error "Could not login to Azure environment..." #TODO: PublishCustomMessage equivalent for 'static' classes?
                    throw ([SuppressedException]::new(("Could not login to Azure envmt. Will try direct Connect-AzureAD...."), [SuppressedExceptionType]::AccessDenied))   
                }
            }
            [ContextHelper]::currentAzContext = $azContext
        }
        return [ContextHelper]::currentAzContext
    }

    hidden static [PSObject] GetCurrentAADContext()
    {
        if ([ContextHelper]::currentAADContext -eq $null)
        {
            throw ([SuppressedException]::new(("Cannot call this method before getting a sign-in context!"), [SuppressedExceptionType]::InvalidOperation))
        }
        return [ContextHelper]::currentAADContext
    }

    hidden static [PSObject] GetCurrentAADContext($desiredTenantId) #Can be $null if user did not pass one.
    {
        $currAADCtx = [ContextHelper]::currentAADContext

        # If we don't have a context *or* the context does not match a non-null desired tenant
        if(-not $currAADCtx -or (-not [String]::IsNullOrEmpty($desiredTenantId) -and $desiredTenantId -ne $currAADCtx.TenantID))
        {
            [ContextHelper]::ClearTenantContext()

            $aadContext = $null
            $aadUserObj = $null
            #Try leveraging Azure context if available
            try {
                $tenantId = $null
                $crossTenant = $false
                $accountId = $null

                if (-not [string]::IsNullOrEmpty($desiredTenantId))
                {
                    $tenantId = $desiredTenantId
                }

                $azContext = $null
                try {
                    #Either throws or returns non-null
                    $azContext = [ContextHelper]::GetCurrentAzContext($desiredTenantId)
                    $accountId = $azContext.Account.Id    
                }
                catch {
                    Write-Warning "Could not acquire Azure context. Falling back to Connect-AzureAD..."
                }
                
                if ($azContext -ne $null -and $azContext.Tenant -ne $null) #Can be $null when a user has no Azure subscriptions.
                {
                    $nativeTenantId = $azContext.Tenant.Id
                    if ($tenantId -eq $null) #No 'desired tenant' passed in by user
                    {
                        $tenantId = $nativeTenantId
                    }
                    else
                    {
                        #Check if desiredTenant and native tenant are diff => this user is guest in the desired tenant
                        if ($nativeTenantId -ne $desiredTenantId)
                        {
                            $crossTenant = $true
                        }
                    }
                }

                $aadContext = $null
                if (-not [string]::IsNullOrEmpty($tenantId) -and -not [string]::IsNullOrEmpty($accountId))
                {
                    $aadContext = Connect-AzureAD -TenantId $tenantId -AccountId $accountId -ErrorAction Stop
                }
                elseif (-not [string]::IsNullOrEmpty($accountId)) 
                {
                    $aadContext = Connect-AzureAd -AccountId $accountId -ErrorAction Stop
                    $tenantId = $aadContext.TenantId
                }
                else {
                    $aadContext = Connect-AzureAd -ErrorAction Stop
                    $tenantId = $aadContext.TenantId
                }

                if (-not [String]::IsNullOrEmpty($desiredTenantId) -and $desiredTenantId -ne $aadContext.TenantID)
                {
                    Write-Error "Mismatch between desired tenantId: $desiredTenantId and tenantId from login context: $($aadContext.TenantId).`r`nYou may have mistyped the value of 'tenantId' parameter. Please try again!"
                    throw ([SuppressedException]::new("Mismatch between desired tenantId: $desiredTenantId and tenantId from login context: $($aadContext.TenantId)", [SuppressedExceptionType]::Generic))
                }

                $upn = $aadContext.Account.Id
                if (-not $crossTenant) 
                {
                    #in this case UPN is same as signin name use
                    $aadUserObj = Get-AzureADUser -Filter "UserPrincipalName eq '$upn'"
                }
                else 
                {
                    #Cross-tenant, UPN is the mangled version e.g., joe_contoso.com#desiredtenant.com
                    $upnx = (($upn -replace '@', '_')+'#')
                    $filter = "startswith(UserPrincipalName,'" + $upnx + "')"
                    $aadUserObj = Get-AzureAdUser -Filter $filter
                }
            }
            catch {
                throw ([SuppressedException]::new("Could not acquire an AAD tenant context!`r`n$_", [SuppressedExceptionType]::Generic))
            }

            [ContextHelper]::ScanType = [CommandType]::AAD
            [ContextHelper]::currentAADContext = $aadContext
            [ContextHelper]::currentAADUserObject = $aadUserObj
            [ContextHelper]::tenantInfoMsg = "AAD Tenant Info: `n`tDomain: $($aadContext.TenantDomain)`n`tTenanId: $($aadContext.TenantId)"
        }

        return [ContextHelper]::currentAADContext
    }

    static [string] GetCurrentTenantInfo()
    {
        return [ContextHelper]::tenantInfoMsg
    }

    static [string] GetCurrentSessionUser() 
    {
        $context = [ContextHelper]::GetCurrentAADContext() 
        if ($null -ne $context) {
            return $context.Account.Id
        }
        else {
            return "NO_ACTIVE_SESSION"
        }
    }

    static [string] GetCurrentSessionUserObjectId() 
    {
        return ([ContextHelper]::GetCurrentAADUserObject()).ObjectId;
    }

    hidden static [PSObject] GetCurrentAADUserObject()
    {
        return [ContextHelper]::currentAADUserObject   
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
        if ([ContextHelper]::rolesLoaded -eq $false)
        {
            $upr = [PrivilegedAADRoles]::None
            $apr = [ContextHelper]::GetEnabledPrivRolesInTenant()
            $apr | % {
                $pr = $_
                #Write-Host "$pr.AADPrivRole"
                $roleMembers = [array] (Get-AzureADDirectoryRoleMember -ObjectId $pr.ObjectId)
                #Write-Host "Count: $($roleMembers.Count)"
                if($roleMembers)
                {
                    $roleMembers | % { if ($_.ObjectId -eq $uid) {$upr = $upr -bor $pr.AADPrivRole}}
                }
                
            }    

            [ContextHelper]::UserAADPrivRoles = $upr
            [ContextHelper]::rolesLoaded = $true
        }
        return [ContextHelper]::UserAADPrivRoles
    }

    #Is user a member of any directory role we consider 'admin-equiv.'?
    #Note: #TODO: This does not check for PIM-based role membership yet.
    static [bool] IsUserInAPermanentAdminRole()
    {
        $uid = ([ContextHelper]::GetCurrentAADUserObject()).ObjectId
        $upr = [ContextHelper]::GetUserPrivTenantRoles($uid)
        return ($upr -ne [PrivilegedAADRoles]::None) 
    }


    hidden static [PSObject] GetCurrentAADAPIToken()
    {
        if(-not [ContextHelper]::AADAPIAccessToken)
        {
            $apiToken = $null
            
            $AADAPIGuid = [Constants]::AADAPIGuid

            #Try leveraging Azure context if available
            try {
                #Either throws or returns non-null
                $azContext = [ContextHelper]::GetCurrentAzContext()
                $tenantId = $null
                if ($azContext.Tenant -ne $null) #happens if user does not have any Azure subs.
                {
                    $tenantId = $azContext.Tenant.Id
                }
                else {
                    $tenantId = ([ContextHelper]::GetCurrentAADContext()).TenantId 
                }
                $apiToken = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($azContext.Account, $azContext.Environment, $tenantId, $null, "Never", $null, $AADAPIGuid)
            }
            catch {
                Write-Warning "Could not get AAD API token for: $AADAPIGuid."
                throw ([SuppressedException]::new("Could not get AAD API token for: $AADAPIGuid.", [SuppressedExceptionType]::Generic))
            }

            [ContextHelper]::AADAPIAccessToken = $apiToken
            #TODO move to detailed log: Write-Host("Successfully acquired API access token for $AADAPIGuid")
		}
        return [ContextHelper]::AADAPIAccessToken
    }

    
	hidden static [void] ResetCurrentContext()
	{
		[ContextHelper]::currentRMContext = $null
	}

    #TODO: Review calls to this. Should we have an AAD-version for it? Or just remove...
    static [string] GetAccessToken([string] $resourceAppIdUri, [string] $tenantId) 
    {
        return [ContextHelper]::GetAzureDevOpsAccessToken();
    }

    static [string] GetAzureDevOpsAccessToken()
    {
        # TODO: Handlle login
        if([ContextHelper]::currentAzureDevOpsContext)
        {
            return [ContextHelper]::currentAzureDevOpsContext.AccessToken
        }
        else
        {
            return $null
        }
    }

    static [string] GetAccessToken([string] $resourceAppIdUri) 
    {
        if([ContextHelper]::ScanType -eq [CommandType]::AzureDevOps)
        {
            return [ContextHelper]::GetAzureDevOpsAccessToken()
        }
        else {
            return [ContextHelper]::GetAccessToken($resourceAppIdUri, "");    
        }
        
    }

    static [string] GetAccessToken()
    {
        if([ContextHelper]::ScanType -eq [CommandType]::AzureDevOps)
        {
            return [ContextHelper]::GetAzureDevOpsAccessToken()
        }
        else {
            #TODO : Fix ResourceID
            return [ContextHelper]::GetAccessToken("", "");    
        }
    }

    hidden [SubscriptionContext] SetContext([string] $subscriptionId)
    {
        $aadCtx = [ContextHelper]::GetCurrentAADContext($subscriptionId)	
		#If the user did not specify a tenantId, we determine it from AAD ctx (from the login session)
		if ([string]::IsNullOrEmpty($subscriptionId))
		{
			$subscriptionId = $aadCtx.TenantId
        }
        
        if((-not [string]::IsNullOrEmpty($subscriptionId)))
		{
			$SubscriptionContext = [SubscriptionContext]@{
				SubscriptionId = $subscriptionId;
				Scope = "/Organization/$subscriptionId";
				SubscriptionName = $aadCtx.TenantDomain;
			};
			[ContextHelper]::GetCurrentContext()			
		}
		else
		{
			throw [SuppressedException] ("AAD [$subscriptionId] is either malformed or incorrect.")
        }
        return $SubscriptionContext;
    }
}
