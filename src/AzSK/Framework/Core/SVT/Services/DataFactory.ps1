#using namespace Microsoft.Azure.Commands.DataFactory.Models
Set-StrictMode -Version Latest 
class DataFactory: SVTBase
{       
    DataFactory([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
    }

	DataFactory([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
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