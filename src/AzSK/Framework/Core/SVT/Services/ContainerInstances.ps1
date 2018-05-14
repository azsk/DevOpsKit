Set-StrictMode -Version Latest 
class ContainerInstances: SVTBase
{       
    hidden [PSObject] $ResourceObject;

    ContainerInstances([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
        #$this.GetResourceObject();
    }

    ContainerInstances([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        #$this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) 
		{
            $this.ResourceObject = Get-AzureRmContainerGroup -Name $this.ResourceContext.ResourceName `
											-ResourceGroupName $this.ResourceContext.ResourceGroupName -ErrorAction SilentlyContinue

            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }
}
