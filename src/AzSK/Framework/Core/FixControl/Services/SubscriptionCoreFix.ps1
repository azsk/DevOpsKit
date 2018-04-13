Set-StrictMode -Version Latest 

class SubscriptionCoreFix: FixSubscriptionBase
{       
    SubscriptionCoreFix([string] $subscriptionId, [ArrayWrapper] $controls): 
        Base($subscriptionId, $controls) 
    { }

	[MessageData[]] AddRequiredCentralAccounts([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$detailedLogs += [MessageData]::new("Adding required central accounts to the subscription using AzSK command...");
		Set-AzSKSubscriptionRBAC `
			-SubscriptionId $this.SubscriptionContext.SubscriptionId `
			-Tags ([String]::Join(",", $parameters.Tags)) `
			-DoNotOpenOutputFolder
		$detailedLogs += [MessageData]::new("All required central accounts have been added to the subscription", [MessageType]::Update);
		return $detailedLogs;
    }
	
	[MessageData[]] RemoveDeprecatedAccounts([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$detailedLogs += [MessageData]::new("Removing deprecated accounts from the subscription using AzSK command...");
		Remove-AzSKSubscriptionRBAC -SubscriptionId $this.SubscriptionContext.SubscriptionId -DoNotOpenOutputFolder
		$detailedLogs += [MessageData]::new("All deprecated accounts have been removed from the subscription", [MessageType]::Update);
		return $detailedLogs;
    }

	[MessageData[]] ConfigureSecurityCenter([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$detailedLogs += [MessageData]::new("Configuring Security Center using AzSK command...");
		
		Set-AzSKAzureSecurityCenterPolicies `
			-SubscriptionId $this.SubscriptionContext.SubscriptionId `
			-SecurityContactEmails $parameters.SecurityContactEmails `
			-SecurityPhoneNumber $parameters.SecurityPhoneNumber `
			-DoNotOpenOutputFolder
		
		$detailedLogs += [MessageData]::new("Security Center has been configured", [MessageType]::Update);
		return $detailedLogs;
    }

	[MessageData[]] ConfigureARMPolicies([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$detailedLogs += [MessageData]::new("Configuring ARM policies using AzSK command...");
		
		Set-AzSKARMPolicies `
			-SubscriptionId $this.SubscriptionContext.SubscriptionId `
			-Tags ([String]::Join(",", $parameters.Tags)) `
			-DoNotOpenOutputFolder
		
		$detailedLogs += [MessageData]::new("ARM policies have been configured", [MessageType]::Update);
		return $detailedLogs;
    }
	
	[MessageData[]] ConfigureAlerts([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$detailedLogs += [MessageData]::new("Configuring alerts using AzSK command...");
		
		Set-AzSKAlerts `
			-SubscriptionId $this.SubscriptionContext.SubscriptionId `
			-SecurityContactEmails $parameters.SecurityContactEmails `
			-Tags ([String]::Join(",", $parameters.Tags)) `
			-DoNotOpenOutputFolder
		
		$detailedLogs += [MessageData]::new("Alerts have been configured", [MessageType]::Update);
		return $detailedLogs;
    }
}