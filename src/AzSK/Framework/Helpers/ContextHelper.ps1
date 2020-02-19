class ContextHelper : EventBase
{
    static hidden [PSObject] $currentContext;
    

    hidden static [PSObject] GetCurrentContext()
	{
		if (-not [ContextHelper]::currentContext)
		{
			$rmContext = Get-AzContext -ErrorAction Stop

			if ((-not $rmContext) -or ($rmContext -and (-not $rmContext.Subscription -or -not $rmContext.Account))) {
				[EventBase]::PublishGenericCustomMessage("No active Azure login session found. Initiating login flow...", [MessageType]::Warning);
                [PSObject]$rmLogin = $null
                $AzureEnvironment = [Constants]::DefaultAzureEnvironment
                $AzskSettings = [Helpers]::LoadOfflineConfigFile("AzSKSettings.json", $true)          
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
            [ContextHelper]::currentContext = $rmContext
		}

		return [ContextHelper]::currentContext
	}

	hidden static [void] ResetCurrentContext()
	{
		[ContextHelper]::currentContext = $null
    }
    
    
    static [string] GetAccessToken([string] $resourceAppIdUri, [string] $tenantId) 
    {
        $rmContext = [ContextHelper]::GetCurrentContext()
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
        $context = [ContextHelper]::GetCurrentContext()
        if ($null -ne $context) {
            return $context.Account.Id
        }
        else {
            return "NO_ACTIVE_SESSION"
        }
    }

    hidden [SubscriptionContext] SetContext([string] $subscriptionId)
    {

		#Validate SubId
		[Guid] $validatedId = [Guid]::Empty;
		[SubscriptionContext] $SubscriptionContext = $null;
		if([Guid]::TryParse($subscriptionId, [ref] $validatedId))
		{
			#Set up subscription
			$SubscriptionContext = [SubscriptionContext]@{
				SubscriptionId = $validatedId.Guid;
				Scope = "/subscriptions/$($validatedId.Guid)";
			};
		}
		else
		{
			throw [SuppressedException] ("Subscription Id [$subscriptionId] is malformed. Subscription Id should contain 32 digits with 4 dashes (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).")
		}

		$currentAzContext = [ContextHelper]::GetCurrentContext()

        if((-not $currentAzContext) -or ($currentAzContext -and ((-not $currentAzContext.Subscription -and ($SubscriptionContext.SubscriptionId -ne [Constants]::BlankSubscriptionId)) `
				-or -not $currentAzContext.Account)))
        {
            $this.PublishCustomMessage("No active Azure login session found. Initiating login flow...", [MessageType]::Warning);

			if($SubscriptionContext.SubscriptionId -ne [Constants]::BlankSubscriptionId)
			{
				$rmLogin = Connect-AzAccount -SubscriptionId $SubscriptionContext.SubscriptionId
			}
			else
			{
				$rmLogin = Connect-AzAccount
			}
            
			if($rmLogin)
			{
				$currentAzContext = $rmLogin.Context;
			}
        }

		if($currentAzContext -and $currentAzContext.Subscription -and $currentAzContext.Subscription.Id)
		{
		    if(($currentAzContext.Subscription.Id -ne $SubscriptionContext.SubscriptionId) -and ($SubscriptionContext.SubscriptionId -ne [Constants]::BlankSubscriptionId))
			{
				try 
				{
					$currentAzContext = Set-AzContext -SubscriptionId $SubscriptionContext.SubscriptionId -ErrorAction Stop   
				}
				catch 
				{
					throw [SuppressedException] ("Please provide a valid tenant or a valid subscription.`nNote: If you are using Privileged Identity Management (PIM), make sure you have activated your access.") 
				}
				    
				# $currentAzContext will contain the desired subscription (or $null if id is wrong or no permission)
				if ($null -eq $currentAzContext)
				{
					throw [SuppressedException] ("Invalid Subscription Id [" + $SubscriptionContext.SubscriptionId + "]") 
				}
				[ContextHelper]::ResetCurrentContext()
				[ContextHelper]::GetCurrentContext()
			}
			elseif(($currentAzContext.Subscription.Id -ne $SubscriptionContext.SubscriptionId) -and ($SubscriptionContext.SubscriptionId -eq [Constants]::BlankSubscriptionId))
			{
				$SubscriptionContext.SubscriptionId = $currentAzContext.Subscription.Id
				$SubscriptionContext.SubscriptionName = $currentAzContext.Subscription.Name
				$SubscriptionContext.Scope = "/subscriptions/" +$currentAzContext.Subscription.Id
			}
		}
		elseif($null -ne $currentAzContext -and ($SubscriptionContext.SubscriptionId -eq [Constants]::BlankSubscriptionId))
		{
			$SubscriptionContext.SubscriptionName = [Constants]::BlankSubscriptionName
		}
		else
		{
            throw [SuppressedException] ("Subscription Id [" + $SubscriptionContext.SubscriptionId + "] is invalid or you may not have permissions.")
		}

        if ($null -ne $currentAzContext -and [Helpers]::CheckMember($currentAzContext, "Subscription"))
        {
            $SubscriptionContext.SubscriptionName = $currentAzContext.Subscription.Name;
		}

		return $SubscriptionContext
    }
}