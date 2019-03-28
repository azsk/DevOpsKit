Set-StrictMode -Version Latest 
class FixSubscriptionBase: FixControlBase
{ 
    [string] $ResourceGroupName = "";
    [string] $ResourceName = "";

    hidden [ResourceConfig] $ResourceConfig = $null;

    FixSubscriptionBase([string] $subscriptionId, [ArrayWrapper] $controls): 
        Base($subscriptionId)
    {
		if($controls)
		{
			$this.CreateInstance($controls.Values);
		}
		else
		{
			$this.CreateInstance(@());
		}
    }

	hidden [void] CreateInstance([ControlParam[]] $controls)
	{
		[Helpers]::AbstractClass($this, [FixSubscriptionBase]); 

		$typeMapping = [SVTMapping]::SubscriptionMapping;
        if (-not $typeMapping)
		{
            throw [System.ArgumentException] ("No subscription type mapping found");    
        }

        $this.LoadSvtConfig($typeMapping.JsonFileName);

		if(-not $controls)
		{
            throw [System.ArgumentException] ("No controls found to fix");    
		}

		$this.Controls += $controls;
	}

	[MessageData[]] FixStarted()
	{ 
		return $this.PublishCustomMessage([Constants]::DoubleDashLine +
				"`r`nStarting control fixes: [FeatureName: $($this.SVTConfig.FeatureName)] [SubscriptionName: $($this.SubscriptionContext.SubscriptionName)] [SubscriptionId: $($this.SubscriptionContext.SubscriptionId)] `r`n" + 
				[Constants]::SingleDashLine);
	}

	[MessageData[]] FixCompleted()
	{ 
		return $this.PublishCustomMessage([Constants]::SingleDashLine +
				"`r`nCompleted control fixes: [FeatureName: $($this.SVTConfig.FeatureName)] [SubscriptionName: $($this.SubscriptionContext.SubscriptionName)] [SubscriptionId: $($this.SubscriptionContext.SubscriptionId)] `r`n" + 
				[Constants]::DoubleDashLine, [MessageType]::Update);	
	}

}
