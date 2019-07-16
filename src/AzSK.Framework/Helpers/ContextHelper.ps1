class ContextHelper : EventBase
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

		$currentContext = [ContextHelper]::GetCurrentRMContext()

        if((-not $currentContext) -or ($currentContext -and ((-not $currentContext.Subscription -and ($SubscriptionContext.SubscriptionId -ne [Constants]::BlankSubscriptionId)) `
				-or -not $currentContext.Account)))
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
				$currentContext = $rmLogin.Context;
			}
        }

		if($currentContext -and $currentContext.Subscription -and $currentContext.Subscription.Id)
		{
		    if(($currentContext.Subscription.Id -ne $SubscriptionContext.SubscriptionId) -and ($SubscriptionContext.SubscriptionId -ne [Constants]::BlankSubscriptionId))
			{
				try 
				{
					$currentContext = Set-AzContext -SubscriptionId $SubscriptionContext.SubscriptionId -ErrorAction Stop   
				}
				catch 
				{
					throw [SuppressedException] ("Please provide a valid tenant or a valid subscription.`nNote: If you are using Privileged Identity Management (PIM), make sure you have activated your access.​") 
				}
				    
				# $currentContext will contain the desired subscription (or $null if id is wrong or no permission)
				if ($null -eq $currentContext)
				{
					throw [SuppressedException] ("Invalid Subscription Id [" + $SubscriptionContext.SubscriptionId + "]") 
				}
				[ContextHelper]::ResetCurrentRMContext()
				[ContextHelper]::GetCurrentRMContext()
			}
			elseif(($currentContext.Subscription.Id -ne $SubscriptionContext.SubscriptionId) -and ($SubscriptionContext.SubscriptionId -eq [Constants]::BlankSubscriptionId))
			{
				$SubscriptionContext.SubscriptionId = $currentContext.Subscription.Id
				$SubscriptionContext.SubscriptionName = $currentContext.Subscription.Name
				$SubscriptionContext.Scope = "/subscriptions/" +$currentContext.Subscription.Id
			}
		}
		elseif($null -ne $currentContext -and ($SubscriptionContext.SubscriptionId -eq [Constants]::BlankSubscriptionId))
		{
			$SubscriptionContext.SubscriptionName = [Constants]::BlankSubscriptionName
		}
		else
		{
            throw [SuppressedException] ("Subscription Id [" + $SubscriptionContext.SubscriptionId + "] is invalid or you may not have permissions.")
		}

        if ($null -ne $currentContext -and [Helpers]::CheckMember($currentContext, "Subscription"))
        {
            $SubscriptionContext.SubscriptionName = $currentContext.Subscription.Name;
		}

		return $SubscriptionContext
    }
}