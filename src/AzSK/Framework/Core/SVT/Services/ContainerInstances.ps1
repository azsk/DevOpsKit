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

            $this.ResourceObject = Get-AzureRmResource -Name $this.ResourceContext.ResourceName `
											-ResourceGroupName $this.ResourceContext.ResourceGroupName -ExpandProperties

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

	hidden [ControlResult] CheckContainerImage([ControlResult] $controlResult)
    {
		$controlResult.VerificationResult = [VerificationResult]::Verify; 
		if([Helpers]::CheckMember($this.ResourceObject, "properties.containers"))
		{
			$containerImages = @();
			$containerImages += $this.ResourceObject.properties.containers | Select-Object name, @{ Label="image"; Expression={ $_.properties.image } };
			if($containerImages.Count -ne 0)
			{
				$controlResult.SetStateData("Containers and their images", $containerImages);
				$controlResult.AddMessage([MessageData]::new("Review following images utilized by containers. Make sure their source is trustworthy.",
									$containerImages));
			}
			else
			{
				$controlResult.AddMessage([MessageData]::new("No containers are found under container group - ["+ $this.ResourceContext.ResourceName +"]"));
			}	
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("No containers are found under container group - ["+ $this.ResourceContext.ResourceName +"]"));
		}
  
        return $controlResult;
    }	

	hidden [ControlResult] CheckRegistry([ControlResult] $controlResult)
    {
		$controlResult.VerificationResult = [VerificationResult]::Verify; 
		if([Helpers]::CheckMember($this.ResourceObject, "Properties.imageRegistryCredentials"))
		{
			$registry = @();
			$registry += $this.ResourceObject.Properties.imageRegistryCredentials | Select-Object server | Select-Object -ExpandProperty server -Unique;
			if($registry.Count -ne 0)
			{
				$controlResult.SetStateData("Container registry", $registry);
				$controlResult.AddMessage([MessageData]::new("Make sure the following registry is trustworthy.",
									$registry));
			}
			else
			{
				$controlResult.AddMessage([MessageData]::new("Containers are utilizing default public registry for container group - ["+ $this.ResourceContext.ResourceName +"]"));
			}	
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("Containers are utilizing default public registry for container group - ["+ $this.ResourceContext.ResourceName +"]"));
		}
  
        return $controlResult;
    }
	
	hidden [ControlResult] CheckContainerTrust([ControlResult] $controlResult)
    {
		if([Helpers]::CheckMember($this.ResourceObject, "properties.containers"))
		{
			$containers = @();
			$containers += $this.ResourceObject.properties.containers | Select-Object name | Select-Object -ExpandProperty name;

			if($containers.Count -gt 1)
			{
				$controlResult.SetStateData("Containers", $containers);
				$controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Make sure that following containers trust each other.",
									$containers));
			}
			elseif($containers.Count -eq 1)
			{
				$controlResult.AddMessage([VerificationResult]::Passed, 
											[MessageData]::new("Only 1 container is found under container group - ["+ $this.ResourceContext.ResourceName +"]", $containers));
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No containers are found under container group - ["+ $this.ResourceContext.ResourceName +"]"));
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No containers are found under container group - ["+ $this.ResourceContext.ResourceName +"]"));
		}
  
        return $controlResult;
    }
}
