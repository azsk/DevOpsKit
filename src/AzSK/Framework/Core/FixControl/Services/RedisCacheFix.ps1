Set-StrictMode -Version Latest 

class RedisCacheFix: FixServicesBase
{
	[PSObject] $ResourceObject = $null;

    RedisCacheFix([string] $subscriptionId, [ResourceConfig] $resourceConfig, [string] $resourceGroupName): 
        Base($subscriptionId, $resourceConfig, $resourceGroupName) 
    { 
    }

	[MessageData[]] DisableNon_SSLport_RedisCache([PSObject] $parameters)
    {

		[MessageData[]] $detailedLogs = @();
		$detailedLogs += [MessageData]::new("Disabling Non SSL port on RedisCache :  [$($this.ResourceName)]...");
		Set-AzureRmRedisCache -ResourceGroupName $this.ResourceGroupName -Name $this.ResourceName -EnableNonSslPort $false
		$detailedLogs += [MessageData]::new("Disabled Non SSL port on RedisCache : [$($this.ResourceName)]");
		return $detailedLogs;	
		
    }

}
