#using namespace Microsoft.Azure.Commands.DataFactory.Models
Set-StrictMode -Version Latest 
class DataFactory: SVTBase
{       

    hidden [PSObject] $ResourceObject;
    hidden [ADFDetails] $adfDetails = [ADFDetails]::new()

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
					throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
				}
            $this.GetADFDetails();
            $this.AddResourceMetadata($this.adfDetails);
        }

        return $this.ResourceObject;
    }
		
	
    hidden [ControlResult] CheckDataFactoryLinkedService([ControlResult] $controlResult)
    {

		if(($this.adfDetails.LinkedserviceDetails | Measure-Object).Count -gt 0)
		{           
			$linkedServicesProps = $this.adfDetails.LinkedserviceDetails | Select-Object -Property LinkedServiceName, Properties

			$controlResult.SetStateData("Linked Service Details:", $linkedServicesProps);
			 


			$controlResult.AddMessage([VerificationResult]::Verify, 
							"Validate that the following Linked Services are using encryption in transit. Total Linked Services found - $(($this.adfDetails.linkedservicedetails | Measure-Object).Count)",
							$linkedServicesProps);
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed, 
										[MessageData]::new("The are no Linked Services configured in Data Factory - ["+ $this.ResourceContext.ResourceName +"]"));
		}       
		                  
        return $controlResult;
    }

    hidden GetADFDetails(){
    
        # Get linked services details
		
        $this.adfDetails.LinkedserviceDetails += Get-AzureRmDataFactoryLinkedService -ResourceGroupName $this.ResourceContext.ResourceGroupName -DataFactoryName $this.ResourceContext.ResourceName;
		

        try{
        # Get pipelines count

             $pipelines = @();
             $pipelines += Get-AzureRmDataFactoryPipeline -ResourceGroupName $this.ResourceContext.ResourceGroupName -DataFactoryName $this.ResourceContext.ResourceName;
		     $this.adfDetails.PipelinesCount = ($pipelines | Measure-Object).Count;

       
             #Get Dataset count
             $datasets = @();
             $datasets += Get-AzureRmDataFactoryDataset -ResourceGroupName $this.ResourceContext.ResourceGroupName -DataFactoryName $this.ResourceContext.ResourceName;
             $this.adfDetails.DatasetsCount +=  ($datasets | Measure-Object).Count;
        }
        catch{
            

        }
    
    }
}

Class ADFDetails{

[int]$PipelinesCount;  #default 0
[PSObject]$LinkedserviceDetails;
[int]$DatasetsCount;   # default 0

}
