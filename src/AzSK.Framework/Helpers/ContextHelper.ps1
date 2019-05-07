class ContextHelper 
{
    static hidden [PSObject] $currentRMContext;
    hidden static [PSObject] GetCurrentRMContext()
	{
		if (-not [ContextHelper]::currentRMContext)
		{
			$rmContext = Get-AzContext -ErrorAction Stop

			if ((-not $rmContext) -or ($rmContext -and (-not $rmContext.Subscription -or -not $rmContext.Account))) {
				[EventBase]::PublishGenericCustomMessage("No active Azure login session found. Initiating login flow...", [MessageType]::Warning);
                [PSObject]$rmLogin = $null
                $AzureEnvironment = [Constants]::DefaultAzureEnvironment
                $AzskSettings = [ContextHelper]::LoadOfflineConfigFile("AzSKSettings.json", $true)          
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

	hidden static [void] ResetCurrentRMContext()
	{
		[ContextHelper]::currentRMContext = $null
    }
    
    
    static [string] GetAccessToken([string] $resourceAppIdUri, [string] $tenantId) 
    {
        $rmContext = [ContextHelper]::GetCurrentRMContext()
        if (-not $rmContext) {
        throw ([SuppressedException]::new(("No Azure login found"), [SuppressedExceptionType]::InvalidOperation))
        }
        
        if ([string]::IsNullOrEmpty($tenantId) -and [Helpers]::CheckMember($rmContext,"Tenant")) {
        $tenantId = $rmContext.Tenant.Id
        }
        
        $authResult = [AzureSession]::Instance.AuthenticationFactory.Authenticate(
        $rmContext.Account,
        $rmContext.Environment,
        $tenantId,
        [System.Security.SecureString] $null,
        "Never",
        $null,
        $resourceAppIdUri);
        
        if (-not ($authResult -and (-not [string]::IsNullOrWhiteSpace($authResult.AccessToken)))) {
          throw ([SuppressedException]::new(("Unable to get access token. Authentication Failed."), [SuppressedExceptionType]::Generic))
        }
        return $authResult.AccessToken;
    }

    static [string] GetAccessToken([string] $resourceAppIdUri) {
        return [ContextHelper]::GetAccessToken($resourceAppIdUri, "");
    }

    static [string] GetCurrentSessionUser() {
        $context = [ContextHelper]::GetCurrentRMContext()
        if ($null -ne $context) {
            return $context.Account.Id
        }
        else {
            return "NO_ACTIVE_SESSION"
        }
    }

}