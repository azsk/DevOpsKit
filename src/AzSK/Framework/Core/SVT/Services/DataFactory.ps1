#using namespace Microsoft.Azure.Commands.DataFactory.Models
Set-StrictMode -Version Latest 
class DataFactory: SVTBase
{       

    hidden [PSObject] $ResourceObject;

    DataFactory([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
		$this.GetResourceObject();
    }

	DataFactory([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
		 $this.GetResourceObject();
    }

	hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzureRmDataFactory -Name $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName
                                                         
            if(-not $this.ResourceObject)
            {
				$this.ResourceObject = Get-AzureRmDataFactoryV2 -Name $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName
				if(-not $this.ResourceObject)
				{
					throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
				}
            }
        }
        return $this.ResourceObject;
    }
		
	
    hidden [ControlResult] CheckDataFactoryLinkedService([ControlResult] $controlResult)
    {
		# Get all the Linked Service
		$linkedServices = @();
		$linkedServices += Get-AzureRmDataFactoryLinkedService -ResourceGroupName $this.ResourceContext.ResourceGroupName -DataFactoryName $this.ResourceContext.ResourceName

		if($linkedServices.Count -gt 0)
		{           
			$linkedServicesProps = $linkedServices | Select-Object -Property LinkedServiceName, Properties
																	#@{ Label="Type"; Expression= { $_.Properties.Type } }, 
																	#@{ Label="ProvisioningState"; Expression= { $_.Properties.ProvisioningState } }, 
																	#@{ Label="TypeProperties"; Expression= { $_.Properties.TypeProperties } }, 

			$controlResult.SetStateData("Linked Service Details:", $linkedServicesProps);

			$controlResult.AddMessage([VerificationResult]::Verify, 
							"Validate that the following Linked Services are using encryption in transit. Total Linked Services found - $($linkedServices.Count)",
							$linkedServicesProps);
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed, 
										[MessageData]::new("The are no Linked Services configured in Data Factory - ["+ $this.ResourceContext.ResourceName +"]"));
		}                            
        return $controlResult;
    }
}
