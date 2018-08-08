Set-StrictMode -Version Latest 
class Batch: SVTBase
{       
    Batch([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    {  }

	Batch([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    {  }

	hidden [ControlResult] CheckBatchStorageSSE([ControlResult] $controlResult)
    {
		$batchResource = Get-AzureRmBatchAccount -AccountName $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName
        if($batchResource)
        {
            if($batchResource.AutoStorageProperties -and (-not [string]::IsNullOrEmpty($batchResource.AutoStorageProperties.StorageAccountId)))
            {
                $storageAccount = Get-AzureRmResource -ResourceId $batchResource.AutoStorageProperties.StorageAccountId -ExpandProperties
                if($storageAccount -and $storageAccount.Properties)
                {

					if([Helpers]::CheckMember($storageAccount,"Properties.encryption.services.blob.enabled") -and $storageAccount.Properties.encryption.services.blob.enabled -eq $true)
                    {
                        $controlResult.AddMessage([VerificationResult]::Passed,
                                "Storage Service Encryption is enabled on blob service of Storage Account [$($storageAccount.Name)] associated with Batch account",
                                $storageAccount.Properties.encryption.services); 
                    }
                    else
                    {
                        $controlResult.AddMessage([VerificationResult]::Failed,
								"Storage Service Encryption is not enabled on blob service of Storage Account [$($storageAccount.Name)] associated with Batch account"); 
                    }
                }
                else
                {
                    $controlResult.AddMessage([MessageData]::new("No valid Storage Account found which is associated with Batch account", [MessageType]::Error)); 
                }
            }
            else
            {
                $controlResult.AddMessage([MessageData]::new("No valid Storage Account found which is associated with Batch account", [MessageType]::Error)); 
            }
        }
        else
        {
            $controlResult.AddMessage([MessageData]::new("We are not able to fetch the required data for the resource", [MessageType]::Error)); 
        }
        
		return $controlResult;
    }



	hidden [ControlResult] CheckBatchMetricAlert([ControlResult] $controlResult)
	{
		$this.CheckMetricAlertConfiguration($this.ControlSettings.MetricAlert.Batch, $controlResult, "");
        return $controlResult;
	}
}