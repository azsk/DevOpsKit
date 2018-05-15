Set-StrictMode -Version Latest 
class ContainerInstances: SVTBase
{       
    hidden [PSObject] $ResourceObject;

    ContainerInstances([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
        $this.GetResourceObject();
    }

    ContainerInstances([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) 
		{
           # $this.ResourceObject = Get-AzureRmContainerGroup -Name $this.ResourceContext.ResourceName `
											#-ResourceGroupName $this.ResourceContext.ResourceGroupName -ErrorAction SilentlyContinue

            $this.ResourceObject = Find-AzureRmResource -ResourceNameEquals $this.ResourceContext.ResourceName `
											-ResourceGroupNameEquals $this.ResourceContext.ResourceGroupName -ExpandProperties

            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }

	hidden [ControlResult] CheckPublicIPAndPorts([ControlResult] $controlResult)
    {
		if([Helpers]::CheckMember($this.ResourceObject, "properties.ipAddress"))
		{
			$controlResult.VerificationResult = [VerificationResult]::Verify; 
			$controlResult.SetStateData("Public IP address and ports assigned to the container", $this.ResourceObject.properties.ipAddress);
			$controlResult.AddMessage([MessageData]::new("Review following public IP address and ports assignment to the container - ["+ $this.ResourceContext.ResourceName +"]",
								$this.ResourceObject.properties.ipAddress));
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed, 
                            [MessageData]::new("No public IP address has been assigned to the container - ["+ $this.ResourceContext.ResourceName +"]"));
		}
  
        return $controlResult;
    }

	
}
