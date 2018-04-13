Set-StrictMode -Version Latest 
class LoadBalancer: SVTBase
{       
    hidden [PSObject] $ResourceObject;

    LoadBalancer([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
                 Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
    }

    LoadBalancer([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
    }

	hidden [ControlResult] CheckPublicIP([ControlResult] $controlResult)
	{	
		$publicIps = @();
		$loadBalancer = Get-AzureRmLoadBalancer -ResourceGroupName $this.ResourceContext.ResourceGroupName -Name $this.ResourceContext.ResourceName
        $loadBalancer.FrontendIpConfigurations | 
			ForEach-Object {
                Set-Variable -Name feIpConfigurations -Scope Local -Value $_
                if(($feIpConfigurations | Get-Member -Name "PublicIpAddress") -and $feIpConfigurations.PublicIpAddress)
                {
				    $ipResource = Get-AzureRmResource -ResourceId $feIpConfigurations.PublicIpAddress.Id 
				    if($ipResource)
				    {
					   $publicIpObject = Get-AzureRmPublicIpAddress -Name $ipResource.Name -ResourceGroupName $ipResource.ResourceGroupName
					   if($publicIpObject)
					   {
						    $_.PublicIpAddress = $publicIpObject;
						    $publicIps += $publicIpObject;
					    }
				    }
                }
			}
		 
		if($publicIps.Count -gt 0)
		{              
			$controlResult.AddMessage([VerificationResult]::Verify, "Validate Public IP(s) associated with Load Balancer. Total - $($publicIps.Count)", $publicIps);  
			$controlResult.SetStateData("Public IP(s) associated with Load Balancer", $publicIps);
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed, "No Public IP is associated with Load Balancer");
		}
		return $controlResult;
	}
}
