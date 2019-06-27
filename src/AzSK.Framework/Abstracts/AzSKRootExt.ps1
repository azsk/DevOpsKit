Set-StrictMode -Version Latest
class AzSKRootExt: EventBase
{ 
    [SubscriptionContext] $SubscriptionContext;

    AzSKRootExt([string] $subscriptionId)
    {   
        
		#Validate SubId
		[Guid] $validatedId = [Guid]::Empty;
		if([Guid]::TryParse($subscriptionId, [ref] $validatedId))
		{
			#Set up subscription
			$this.SubscriptionContext = [SubscriptionContext]@{
				SubscriptionId = $validatedId.Guid;
				Scope = "/subscriptions/$($validatedId.Guid)";
			};

			$this.SetAzureContext();
		}
		else
		{
			throw [SuppressedException] ("Subscription Id [$subscriptionId] is malformed. Subscription Id should contain 32 digits with 4 dashes (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).")
		}
    }    
    
    hidden [void] SetAzureContext()
    {
		$currentContext = [ContextHelper]::GetCurrentRMContext()

        if((-not $currentContext) -or ($currentContext -and ((-not $currentContext.Subscription -and ($this.SubscriptionContext.SubscriptionId -ne [Constants]::BlankSubscriptionId)) `
				-or -not $currentContext.Account)))
        {
            $this.PublishCustomMessage("No active Azure login session found. Initiating login flow...", [MessageType]::Warning);

			if($this.SubscriptionContext.SubscriptionId -ne [Constants]::BlankSubscriptionId)
			{
				$rmLogin = Connect-AzAccount -SubscriptionId $this.SubscriptionContext.SubscriptionId
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
		    if(($currentContext.Subscription.Id -ne $this.SubscriptionContext.SubscriptionId) -and ($this.SubscriptionContext.SubscriptionId -ne [Constants]::BlankSubscriptionId))
			{
				try 
				{
					$currentContext = Set-AzContext -SubscriptionId $this.SubscriptionContext.SubscriptionId -ErrorAction Stop   
				}
				catch 
				{
					throw [SuppressedException] ("Please provide a valid tenant or a valid subscription.​") 
				}
				    
				# $currentContext will contain the desired subscription (or $null if id is wrong or no permission)
				if ($null -eq $currentContext)
				{
					throw [SuppressedException] ("Invalid Subscription Id [" + $this.SubscriptionContext.SubscriptionId + "]") 
				}
				[ContextHelper]::ResetCurrentRMContext()
				[ContextHelper]::GetCurrentRMContext()
			}
			elseif(($currentContext.Subscription.Id -ne $this.SubscriptionContext.SubscriptionId) -and ($this.SubscriptionContext.SubscriptionId -eq [Constants]::BlankSubscriptionId))
			{
				$this.SubscriptionContext.SubscriptionId = $currentContext.Subscription.Id
				$this.SubscriptionContext.SubscriptionName = $currentContext.Subscription.Name
				$this.SubscriptionContext.Scope = "/subscriptions/" +$currentContext.Subscription.Id
			}
		}
		elseif($null -ne $currentContext -and ($this.SubscriptionContext.SubscriptionId -eq [Constants]::BlankSubscriptionId))
		{
			$this.SubscriptionContext.SubscriptionName = [Constants]::BlankSubscriptionName
		}
		else
		{
            throw [SuppressedException] ("Subscription Id [" + $this.SubscriptionContext.SubscriptionId + "] is invalid or you may not have permissions.")
		}

        if ($null -ne $currentContext -and [Helpers]::CheckMember($currentContext, "Subscription"))
        {
            $this.SubscriptionContext.SubscriptionName = $currentContext.Subscription.Name;
		}
    }

	[bool] IsLatestVersionConfiguredOnSub([String] $ConfigVersion,[string] $TagName,[string] $FeatureName)
	{
		$IsLatestVersionPresent = $this.IsLatestVersionConfiguredOnSub($ConfigVersion,$TagName)
		if($IsLatestVersionPresent){
			$this.PublishCustomMessage("$FeatureName configuration in your subscription is already up to date. If you would like to reconfigure, please rerun the command with '-Force' parameter.");
		}				
		return $IsLatestVersionPresent		
	}

	[bool] IsLatestVersionConfiguredOnSub([String] $ConfigVersion,[string] $TagName)
	{
		$IsLatestVersionPresent = $false
		$tagsOnSub =  [ResourceGroupHelper]::GetResourceGroupTags([ConfigurationManager]::GetAzSKConfigData().AzSKRGName) 
		if($tagsOnSub)
		{
			$SubConfigVersion= $tagsOnSub.GetEnumerator() | Where-Object {$_.Name -eq $TagName -and $_.Value -eq $ConfigVersion}
			
			if(($SubConfigVersion | Measure-Object).Count -gt 0)
			{
				$IsLatestVersionPresent = $true				
			}			
		}
		return $IsLatestVersionPresent		
	}
}
