Set-StrictMode -Version Latest 

class TrafficManagerFix: FixServicesBase
{
	[PSObject] $ResourceObject = $null;

    TrafficManagerFix([string] $subscriptionId, [ResourceConfig] $resourceConfig, [string] $resourceGroupName): 
        Base($subscriptionId, $resourceConfig, $resourceGroupName) 
    { }

	[MessageData[]] EnableHttpsAsMonitorProtocol([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$detailedLogs += [MessageData]::new("Enabling 'HTTPS' protocol for endpoint monitoring on Traffic Manager Profile [$($this.ResourceName)]...");
		$TrafficManagerProfile = Get-AzureRmTrafficManagerProfile -Name  $this.ResourceName -ResourceGroupName $this.ResourceGroupName 
		$TrafficManagerProfile.MonitorProtocol = 'HTTPS'
		if([string]::IsNullOrWhiteSpace($TrafficManagerProfile.MonitorPath))
		{
			$TrafficManagerProfile.MonitorPath='/'
		}
		Set-AzureRmTrafficManagerProfile -TrafficManagerProfile $TrafficManagerProfile
		$detailedLogs += [MessageData]::new("'HTTPS' protocol is enabled for endpoint monitoring on Traffic Manager Profile [$($this.ResourceName)]");
		return $detailedLogs;
    }

}
