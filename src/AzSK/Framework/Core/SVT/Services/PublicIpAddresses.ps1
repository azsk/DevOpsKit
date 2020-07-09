Set-StrictMode -Version Latest 
class PublicIpAddresses: AzSVTBase
{       
	hidden [PSObject] $ResourceObject;
	hidden [bool] $LockExists = $false;

    PublicIpAddresses([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        
    }

    

    hidden [ControlResult] VerifyPublicIp([ControlResult] $controlResult)
	{	
		$publicIps = Get-AzPublicIpAddress -ResourceGroupName $this.ResourceContext.ResourceGroupName -Name $this.ResourceContext.ResourceName
        $ipFlatList = [System.Collections.ArrayList]::new()
		
		foreach($publicIp in $publicIps){
			$ip = $publicIp | Select-Object ResourceGroupName, Name, Location, PublicIpAllocationMethod, PublicIpAddressVersion

			$ipFlatList.Add($ip) | Out-Null
        }
        
		if($ipFlatList.Count -gt 0)
        {
		$controlResult.SetStateData("Public IP details", $ipFlatList);
            $controlResult.AddMessage([VerificationResult]::Verify, "Found public IPs.", $ipFlatList)
        }
        else
        {
           $controlResult.VerificationResult = [VerificationResult]::Passed
        }
	return $controlResult
     }

}