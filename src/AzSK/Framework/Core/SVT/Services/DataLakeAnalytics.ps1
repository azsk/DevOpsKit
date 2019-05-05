Set-StrictMode -Version Latest 
class DataLakeAnalytics: SVTBase
{       
    hidden [PSObject] $ResourceObject;

    DataLakeAnalytics([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzDataLakeAnalyticsAccount -Name $this.ResourceContext.ResourceName `
                                            -ResourceGroupName $this.ResourceContext.ResourceGroupName
            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }
   
	hidden [ControlResult] CheckEncryptionAtRest([ControlResult] $controlResult)
    {   
		$defaultADLSAccount = Get-AzDataLakeStoreAccount -Name $this.ResourceObject.DefaultDataLakeStoreAccount -ResourceGroupName $this.ResourceContext.ResourceGroupName

		if($defaultADLSAccount)
		{
			$encryptionSettings = $defaultADLSAccount | Select-Object -Property EncryptionConfig, EncryptionState, EncryptionProvisioningState
			if($defaultADLSAccount.EncryptionState -eq [Microsoft.Azure.Management.DataLake.Store.Models.EncryptionState]::Enabled)
			{
				$controlResult.VerificationResult = [VerificationResult]::Passed;
			}
			else
			{
				$controlResult.VerificationResult = [VerificationResult]::Failed;
			}

			$controlResult.AddMessage("Encryption settings of default Data Lake Store account [$($this.ResourceObject.DefaultDataLakeStoreAccount)]", $encryptionSettings);	
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("We are not able to fetch the details of default Data Lake Store account [$($this.ResourceObject.DefaultDataLakeStoreAccount)]", [MessageType]::Error)); 
		
		}
		return $controlResult;
    }
}
