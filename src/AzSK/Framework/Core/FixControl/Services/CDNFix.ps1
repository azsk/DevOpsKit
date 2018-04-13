Set-StrictMode -Version Latest 

class CDNFix: FixServicesBase
{
	[PSObject] $ResourceObject = $null;

    CDNFix([string] $subscriptionId, [ResourceConfig] $resourceConfig, [string] $resourceGroupName): 
        Base($subscriptionId, $resourceConfig, $resourceGroupName) 
    { }

	[MessageData[]] EnableHttpsProtocol([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$detailedLogs += [MessageData]::new("Enabling 'HTTPS' protocol for CDN endpoints in CDN Profile [$($this.ResourceName)]...");
	
		$cdnEndpoints = Get-AzureRmCdnEndpoint -ProfileName $this.ResourceName `
							-ResourceGroupName $this.ResourceGroupName `
							-ErrorAction Stop
		$httpAllowedEndpointList =  $cdnEndpoints | Where-Object { $_.IsHttpAllowed -eq $true }


		$httpAllowedEndpointList |	 ForEach-Object{

			$httpEndpoint= Get-AzureRmCdnEndpoint -EndpointName $_.Name -ProfileName $this.ResourceName  -ResourceGroupName $this.ResourceGroupName
			$httpEndpoint.IsHttpAllowed =$false
			$httpEndpoint.IsHttpsAllowed =$true
			Set-AzureRmCdnEndpoint -CdnEndpoint $httpEndpoint
		
		}
		$detailedLogs += [MessageData]::new("'HTTPS' protocol is enabled for all CDN endpoints in CDN Profile [$($this.ResourceName)]");
		return $detailedLogs;
    }

}
