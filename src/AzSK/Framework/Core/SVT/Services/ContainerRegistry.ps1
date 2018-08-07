Set-StrictMode -Version Latest 
class ContainerRegistry: SVTBase
{       
    hidden [PSObject] $ResourceObject;

    ContainerRegistry([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
        $this.GetResourceObject();
    }

    ContainerRegistry([string] $subscriptionId, [SVTResource] $svtResource): 
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

	hidden [ControlResult] CheckAdminUserStatus([ControlResult] $controlResult)
    {
		$isAdminUserEnabled = $this.ResourceObject.Properties.adminUserEnabled
		
		if($isAdminUserEnabled)
		{
			$controlResult.VerificationResult = [VerificationResult]::Failed
		}
		else
		{
			$controlResult.VerificationResult = [VerificationResult]::Passed
		}
	
		return $controlResult;
    }
}
