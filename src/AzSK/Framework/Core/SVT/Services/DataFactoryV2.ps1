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

    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzureRmDataFactoryV2 -Name $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName                                         
          
				if(-not $this.ResourceObject)
				{
					throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
				}
        $this.GetADFV2Details();
        $this.AddResourceMetadata($this.adfDetails);
        }
        return $this.ResourceObject;
    }

    hidden GetADFV2Details(){
    
        # Get all the Linked Service
        try{

            $resourceAppIdURI =[WebRequestHelper]::AzureManagementUri;
            $accessToken = [Helpers]::GetAccessToken($ResourceAppIdURI)
            $authorisationToken = "Bearer " + $accessToken
            $headers = @{"Authorization"=$authorisationToken;"Content-Type"="application/json"}
            $apiFunctionsUrl = [string]::Format("https://management.azure.com/{0}/linkedservices?api-version=2018-06-01",$this.ResourceContext.ResourceId)
            $linkedServiceDetail = [WebRequestHelper]::InvokeGetWebRequest($apiFunctionsUrl, $headers)
            # Get pipelines count
            $this.adfDetails.LinkedserviceDetails += $linkedServiceDetail
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
        catch{


        }
    }

}

Class ADFV2Details{

[int]$PipelinesCount; #default 0
[PSObject]$LinkedserviceDetails;
[int]$DatasetsCount; #default 0
[PSObject]$TriggersCount; #default 0

}
