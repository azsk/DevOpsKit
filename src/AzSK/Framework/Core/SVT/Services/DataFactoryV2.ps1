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
		 
         try{
            
            $this.AddResourceMetadata($this.adfDetails);
         }
		 catch{
            throw ([SuppressedException]::new(("Error while adding resource metadata!", [SuppressedExceptionType]::Generic)));
         }

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
	    
        # Get pipelines count

        $pipelines = @();
        $pipelines += Get-AzureRmDataFactoryV2Pipeline -ResourceGroupName $this.ResourceContext.ResourceGroupName -DataFactoryName $this.ResourceContext.ResourceName;
		$this.adfDetails.PipelinesCount = ($pipelines | Measure-Object).Count
        
        #Get Dataset count
        $datasets = @();
        $datasets += Get-AzureRmDataFactoryV2Dataset -ResourceGroupName $this.ResourceContext.ResourceGroupName -DataFactoryName $this.ResourceContext.ResourceName;
        $this.adfDetails.DatasetsCount +=  ($datasets | Measure-Object).Count

        #Get Triggers count
        $triggers = @();
        $triggers += Get-AzureRmDataFactoryV2Trigger -ResourceGroupName $this.ResourceContext.ResourceGroupName -DataFactoryName $this.ResourceContext.ResourceName;
        $this.adfDetails.TriggersCount +=  ($triggers | Measure-Object).Count;
    }

}

Class ADFV2Details{

[int]$PipelinesCount;
[PSObject]$LinkedserviceDetails;
[int]$DatasetsCount;
[PSObject]$TriggersCount;

}
