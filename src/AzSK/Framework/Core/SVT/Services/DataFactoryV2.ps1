#using namespace Microsoft.Azure.Commands.DataFactory.Models
Set-StrictMode -Version Latest 
class DataFactoryV2: SVTBase
{       
    hidden [PSObject] $ResourceObject;
    hidden [ADFV2Details] $adfDetails = [ADFV2Details]::new()

    DataFactoryV2([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
    }

	DataFactoryV2([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
         $this.GetResourceObject();
		 $this.GetADFV2Details();
		 $this.AddResourceMetadata($this.adfDetails);

    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzureRmDataFactoryV2 -Name $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName
                                                         
            if(-not $this.ResourceObject)
            {
				$this.ResourceObject = Get-AzureRmDataFactory -Name $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName
				if(-not $this.ResourceObject)
				{
					throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
				}
            }
        }
        return $this.ResourceObject;
    }

    hidden GetADFV2Details(){
    
        # Get all the Linked Service
		
        $this.adfDetails.LinkedserviceDetails += Get-AzureRmDataFactoryV2LinkedService -ResourceGroupName $this.ResourceContext.ResourceGroupName -DataFactoryName $this.ResourceContext.ResourceName
		
        # Get all the pipelines

		$this.adfDetails.Pipelinedetails += Get-AzureRmDataFactoryV2Pipeline -ResourceGroupName $this.ResourceContext.ResourceGroupName -DataFactoryName $this.ResourceContext.ResourceName
        
        #Get Dataset details

        $this.adfDetails.DatasetDetails +=  Get-AzureRmDataFactoryDataset -ResourceGroupName $this.ResourceContext.ResourceGroupName -DataFactoryName $this.ResourceContext.ResourceName

        #Get Trigger details
        $this.adfDetails.TriggerDetails +=  Get-AzureRmDataFactoryV2Trigger -ResourceGroupName $this.ResourceContext.ResourceGroupName -DataFactoryName $this.ResourceContext.ResourceName
    }

}

Class ADFV2Details{

[PSObject]$Pipelinedetails;
[PSObject]$LinkedserviceDetails;
[PSObject]$DatasetDetails;
[PSObject]$TriggerDetails;

}