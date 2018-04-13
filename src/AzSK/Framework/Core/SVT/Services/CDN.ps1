Set-StrictMode -Version Latest
class CDN: SVTBase
{
	hidden [PSObject] $ResourceObject;

	CDN([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName):
        Base($subscriptionId, $resourceGroupName, $resourceName)
    {
        
    }

    CDN([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId, $svtResource)
    {
       
    }

	hidden [ControlResult] CheckCDNHttpsProtocol([ControlResult] $controlResult)
	{
		$cdnEndpoints = Get-AzureRmCdnEndpoint -ProfileName $this.ResourceContext.ResourceName `
							-ResourceGroupName $this.ResourceContext.ResourceGroupName `
							-ErrorAction Stop
		
		if(($cdnEndpoints | Measure-Object).Count -eq 0)
		{
			$controlResult.AddMessage([VerificationResult]::Passed,
										[MessageData]::new("No CDN endpoints are found in the CDN profile.")); 
		}
		else
		{
			$httpAllowedEndpointList =  $cdnEndpoints | Where-Object { $_.IsHttpAllowed -eq $true }

			if(($httpAllowedEndpointList | Measure-Object).Count -eq 0)
			{
				$controlResult.AddMessage([VerificationResult]::Passed,
										[MessageData]::new("All CDN endpoints in the CDN profile [" + $this.ResourceContext.ResourceName + "] are using HTTPS protocol only - ", ($cdnEndpoints | Select-Object -Property Name, HostName, OriginHostHeader, IsHttpAllowed, IsHttpsAllowed))); 
			}
			else
			{
				$httpEndpointObjList=@()
				$httpAllowedEndpointList| Foreach-Object {
					$httpEndpointObj = New-Object -TypeName PSObject
					$httpEndpointObj | Add-Member -NotePropertyName HostName -NotePropertyValue $_.HostName
					$httpEndpointObj | Add-Member -NotePropertyName IsHttpAllowed -NotePropertyValue $_.IsHttpAllowed
					$httpEndpointObj | Add-Member -NotePropertyName IsHttpsAllowed -NotePropertyValue $_.IsHttpsAllowed
					$httpEndpointObjList+=$httpEndpointObj
					}

				$controlResult.SetStateData("Http Enabled Endpoints", $httpEndpointObjList);
				$controlResult.EnableFixControl = $true;
				$controlResult.AddMessage([VerificationResult]::Failed,
										[MessageData]::new("Below CDN endpoints in the CDN profile [" + $this.ResourceContext.ResourceName + "] are using HTTP protocol - ", ($httpAllowedEndpointList | Select-Object -Property Name, HostName, OriginHostHeader, IsHttpAllowed, IsHttpsAllowed))); 
			}
		}
 
		return $controlResult;    
	}
}