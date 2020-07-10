Set-StrictMode -Version Latest 
class PublicIpAddress: AzSVTBase
{       
	hidden [PSObject] $ResourceObject;
	hidden [bool] $LockExists = $false;

    PublicIpAddress([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzPublicIpAddress -Name $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName -ErrorAction Stop
                                                         
            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }

    hidden [ControlResult] VerifyPublicIp([ControlResult] $controlResult)
	{	
		
			$ip = $this.ResourceObject | Select-Object ResourceGroupName, Name, Location, PublicIpAllocationMethod, PublicIpAddressVersion

		if($ip)
        {
			$controlResult.SetStateData("Public IP details", $ip);
            $controlResult.AddMessage([VerificationResult]::Verify, "Found public IP:", $ip)
        }
        else
        {
            $controlResult.VerificationResult = [VerificationResult]::Passed
        }
		return $controlResult
     }
}