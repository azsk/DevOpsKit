Set-StrictMode -Version Latest
class AzSKDevOpsRoot: EventBase
{ 
    [SubscriptionContext] $SubscriptionContext;
	[bool] $RunningLatestPSModule = $true;

    AzSKDevOpsRoot([string] $organizationName)
    {   
            [Helpers]::AbstractClass($this, [AzSKDevOpsRoot]);
        

			$this.SubscriptionContext = [SubscriptionContext]@{
				SubscriptionId = $organizationName;
				Scope = "/$organizationName";
			};
			[Helpers]::GetCurrentAzureDevOpsContext()
    }    
}