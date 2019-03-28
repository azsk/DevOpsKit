Set-StrictMode -Version Latest 
class FixServicesBase: FixControlBase
{
    [string] $ResourceGroupName = "";
    [string] $ResourceName = "";

    hidden [ResourceConfig] $ResourceConfig = $null;

    FixServicesBase([string] $subscriptionId, [ResourceConfig] $resourceConfig, [string] $resourceGroupName): 
        Base($subscriptionId)
    {
		$this.CreateInstance($resourceConfig, $resourceGroupName);
    }

	hidden [void] CreateInstance([ResourceConfig] $resourceConfig, [string] $resourceGroupName)
	{
		[Helpers]::AbstractClass($this, [FixServicesBase]); 

		if(-not $resourceConfig)
		{
			throw [System.ArgumentException] ("The argument 'resourceConfig' is null");
		}
		$this.ResourceConfig = $resourceConfig;

		if([string]::IsNullOrEmpty($resourceGroupName))
		{
			throw [System.ArgumentException] ("The argument 'resourceGroupName' is null or empty");
		}
		$this.ResourceGroupName = $resourceGroupName;

		if([string]::IsNullOrEmpty($resourceConfig.ResourceName))
		{
			throw [System.ArgumentException] ("The argument 'ResourceName' is null or empty");
		}
		$this.ResourceName = $resourceConfig.ResourceName;

        if (-not $resourceConfig.ResourceTypeMapping) 
		{
            throw [System.ArgumentException] ("No ResourceTypeMapping found");    
        }

        $this.LoadSvtConfig($resourceConfig.ResourceTypeMapping.JsonFileName);

		if(-not $this.ResourceConfig.Controls)
		{
            throw [System.ArgumentException] ("No controls found to fix");    
		}

		$this.Controls += $this.ResourceConfig.Controls;
	}

	[MessageData[]] FixStarted()
	{ 
		return $this.PublishCustomMessage([Constants]::DoubleDashLine +
				"`r`nStarting control fixes: [FeatureName: $($this.SVTConfig.FeatureName)] [ResourceGroupName: $($this.ResourceGroupName)] [ResourceName: $($this.ResourceName)] `r`n" + 
				[Constants]::SingleDashLine);
	}

	[MessageData[]] FixCompleted()
	{ 
		return $this.PublishCustomMessage([Constants]::SingleDashLine +
				"`r`nCompleted control fixes: [FeatureName: $($this.SVTConfig.FeatureName)] [ResourceGroupName: $($this.ResourceGroupName)] [ResourceName: $($this.ResourceName)] `r`n" + 
				[Constants]::DoubleDashLine, [MessageType]::Update);	
	}
}
