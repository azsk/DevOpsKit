Set-StrictMode -Version Latest

class StorageReportHelper
{
    hidden [PSObject] $AzSKResourceGroup = $null;
	hidden [PSObject] $AzSKStorageAccount = $null;
	hidden [PSObject] $AzSKStorageContainer = $null;
	hidden [PSObject] $ControlStateIndexer = $null;	
	hidden [int] $HasControlStateReadPermissions = -1;
	hidden [int] $HasControlStateWritePermissions = -1;
	hidden [string]	$IndexerBlobName ="Resource.index.json"
    hidden [int] $retryCount = 3;
    
    hidden [InvocationInfo] $InvocationContext;

    StorageReportHelper([InvocationInfo] $invocationContext)
	{
		$this.SubscriptionContext = $subscriptionContext;
		$this.InvocationContext = $invocationContext;
    }
    
    hidden [void] Initialize([bool] $CreateResourcesIfNotExists)
	{
		$this.GetAzSKStorageReportContainer($CreateResourcesIfNotExists)
    }
    
    hidden [void] GetAzSKStorageReportContainer([bool] $createIfNotExists)
	{
		$ContainerName = [Constants]::StorageReportContainerName;
		if($null -eq $this.AzSKStorageAccount)
		{
			$this.GetAzSKStorageAccount($createIfNotExists)
		}
		if($null -eq $this.AzSKStorageAccount)
		{
			#No storage account => no permissions at all
			$this.HasStorageReportReadPermissions = 0
			$this.HasStorageReportWritePermissions = 0
			return;
        }
        
		$this.HasStorageReportReadPermissions = 0					
		$this.HasStorageReportWritePermissions = 0
		$writeTestContainerName = "writetest";

		#see if user can create the test container in the storage account. If yes then user have both RW permissions. 
		try
		{
			$containerObject = Get-AzureStorageContainer -Context $this.AzSKStorageAccount.Context -Name $writeTestContainerName -ErrorAction SilentlyContinue
			if($null -ne $containerObject)
			{
				Remove-AzureStorageContainer -Name $writeTestContainerName -Context  $this.AzSKStorageAccount.Context -ErrorAction Stop -Force
				$this.HasStorageReportWritePermissions = 1
				$this.HasStorageReportReadPermissions = 1
			}
			else
			{
				New-AzureStorageContainer -Context $this.AzSKStorageAccount.Context -Name $writeTestContainerName -ErrorAction Stop
				$this.HasStorageReportWritePermissions = 1
				$this.HasStorageReportReadPermissions = 1
				Remove-AzureStorageContainer -Name $writeTestContainerName -Context  $this.AzSKStorageAccount.Context -ErrorAction SilentlyContinue -Force
			}				
		}
		catch
		{
			$this.HasStorageReportWritePermissions = 0
		}
		if($this.HasStorageReportWritePermissions -eq 1)
		{
			try
			{
				if($createIfNotExists)
				{
					New-AzureStorageContainer -Context $this.AzSKStorageAccount.Context -Name $ContainerName -ErrorAction SilentlyContinue
				}
				$containerObject = Get-AzureStorageContainer -Context $this.AzSKStorageAccount.Context -Name $ContainerName -ErrorAction SilentlyContinue
				$this.AzSKStorageContainer = $containerObject;					
			}
			catch
			{
				# Add retry logic, after 3 unsuccessful attempt throw the exception.
			}
		}
		else
		{
			# If user doesn't have write permission, check at least user have read permission
			try
			{
				#Able to read the container then read permissions are good
				$containerObject = Get-AzureStorageContainer -Context $this.AzSKStorageAccount.Context -Name $ContainerName -ErrorAction Stop
				$this.AzSKStorageContainer = $containerObject;
				$this.HasStorageReportReadPermissions = 1
			}
			catch
			{
				#Resetting permissions in the case of exception
				$this.HasStorageReportReadPermissions = 0			
			}	
		}		
    }
    
    hidden [void] GetAzSKStorageAccount($createIfNotExists)
	{
		if($null -eq $this.AzSKResourceGroup)
		{
			$this.GetAzSKRG($createIfNotExists);
		}
		if($null -ne $this.AzSKResourceGroup)
		{
			$StorageAccount  = $null;
			$loopValue = $this.retryCount;
			while($loopValue -gt 0)
			{
				$loopValue = $loopValue - 1;
				try
				{
					$StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $this.AzSKResourceGroup.ResourceGroupName -ErrorAction Stop | Where-Object {$_.StorageAccountName -like 'azsk*'} -ErrorAction Stop 
					$loopValue = 0;
				}
				catch
				{
					#eat this exception and retry
				}
			}			

			#if no storage account found then it assumes that there is no control state feature is not used and if there are more than one storage account found it assumes the same
			if($createIfNotExists -and ($null -eq $StorageAccount -or ($StorageAccount | Measure-Object).Count -eq 0))
			{
				$storageAccountName = ("azsk" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"));	
				$storageObject = [Helpers]::NewAzskCompliantStorage($storageAccountName, $this.AzSKResourceGroup.ResourceGroupName, [Constants]::AzSKRGLocation)
				if($null -ne $storageObject -and ($storageObject | Measure-Object).Count -gt 0)
				{
					$loopValue = $this.retryCount;
					while($loopValue -gt 0)
					{
						$loopValue = $loopValue - 1;
						try
						{
							$StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $this.AzSKResourceGroup.ResourceGroupName -ErrorAction Stop | Where-Object {$_.StorageAccountName -like 'azsk*'} -ErrorAction Stop 					
							$loopValue = 0;
						}
						catch
						{
							#eat this exception and retry
						}
					}					
				}					
			}
			$this.AzSKStorageAccount = $StorageAccount;
		}
    }
    
    hidden [PSObject] GetAzSKRG([bool] $createIfNotExists)
	{
		$azSKConfigData = [ConfigurationManager]::GetAzSKConfigData()

		$resourceGroup = Get-AzureRmResourceGroup -Name $azSKConfigData.AzSKRGName -ErrorAction SilentlyContinue
		if($createIfNotExists -and ($null -eq $resourceGroup -or ($resourceGroup | Measure-Object).Count -eq 0))
		{
			if([Helpers]::NewAzSKResourceGroup($azSKConfigData.AzSKRGName, [Constants]::AzSKRGLocation, ""))
			{
				$resourceGroup = Get-AzureRmResourceGroup -Name $azSKConfigData.AzSKRGName -ErrorAction SilentlyContinue
			}
		}
		$this.AzSKResourceGroup = $resourceGroup
		return $resourceGroup;
    }
    
    hidden [LocalSubscriptionReport] GetLocalSubscriptionScanReport()
	{
		try
		{
            $storageReportBlobName = [Constants]::StorageReportBlobName + ".json"
            
            #Look of is there is a AzSK RG and AzSK Storage account
            $StorageAccount = $this.AzSKStorageAccount;						
            $containerObject = $this.AzSKStorageContainer
            $ContainerName = ""
            if($null -ne $this.AzSKStorageContainer)
            {
                $ContainerName = $this.AzSKStorageContainer.Name
            }

            $loopValue = $this.retryCount;
            $StorageReportBlob = $null;
            while($loopValue -gt 0 -and $null -eq $StorageReportBlob)
            {
                $loopValue = $loopValue - 1;
                $StorageReportBlob = Get-AzureStorageBlob -Container $ContainerName -Blob $storageReportBlobName -Context $StorageAccount.Context -ErrorAction SilentlyContinue
            }

            if($null -eq $StorageReportBlob)
            {
                return $null;
            }
            $AzSKTemp = [Constants]::AzSKAppFolderPath + "\Temp\StorageReport";
            if(-not (Test-Path -Path $AzSKTemp))
            {
                mkdir -Path $AzSKTemp -Force
            }

            $loopValue = $this.retryCount;
            while($loopValue -gt 0)
            {
                $loopValue = $loopValue - 1;
                try
                {
                    Get-AzureStorageBlobContent -CloudBlob $StorageReportBlob.ICloudBlob -Context $StorageAccount.Context -Destination $AzSKTemp -Force -ErrorAction Stop
                    $loopValue = 0;
                }
                catch
                {
                    #eat this exception and retry
                }
            }
            $StorageReportJson = Get-ChildItem -Path "$AzSKTemp\$StorageReportBlobName" -Force | Get-Content | ConvertFrom-Json 
            
			return $StorageReportJson;
		}
		finally{
		
		}
    }
    
    hidden [void] SetLocalSubscriptionScanReport([LocalSubscriptionReport] $scanResultForStorage)
	{		
		$AzSKTemp = [Constants]::AzSKAppFolderPath + "\Temp\StorageReport";				
		if(-not (Test-Path "$AzSKTemp\StorageReport"))
		{
			mkdir -Path "$AzSKTemp\StorageReport" -ErrorAction Stop | Out-Null
		}
		else
		{
			Remove-Item -Path "$AzSKTemp\StorageReport\*" -Force -Recurse 
		}

		$fileName = "$AzSKTemp\StorageReport\" + [Constants]::StorageReportBlobName.json 
		
		$StorageAccount = $this.AzSKStorageAccount;						
		$containerObject = $this.AzSKStorageContainer
		$ContainerName = ""
		if($null -ne $this.AzSKStorageContainer)
		{
			$ContainerName = $this.AzSKStorageContainer.Name
		}

        [Helpers]::ConvertToJsonCustom($scanResultForStorage) | Out-File $fileName -Force

        $loopValue = $this.retryCount;
        while($loopValue -gt 0)
        {
            $loopValue = $loopValue - 1;
            try
            {
                Set-AzureStorageBlobContent -File $fileName -Container $ContainerName -BlobType Block -Context $StorageAccount.Context -Force -ErrorAction Stop
                $loopValue = 0;
            }
            catch
            {
                #eat this exception and retry
            }
        }
    }
    
    hidden [void] CleanTempFolder()
	{
		$AzSKTemp = [Constants]::AzSKAppFolderPath + "\Temp\StorageReport";				
		if(Test-Path "$AzSKTemp")
		{
			Remove-Item -Path $AzSKTemp -Recurse -Force -ErrorAction Stop | Out-Null
		}

    }
    
    hidden [void] PostServiceScanReport($scanResult)
    {
        $scanReport = $this.SerializeServiceScanReport($scanResult)
        $finalScanReport = $this.MergeScanReport($scanReport)
        $this.SetLocalSubscriptionScanReport($finalScanReport)
    }

    hidden [void] PostSubscriptionScanReport($scanResult)
    {
        $scanReport = $this.SerializeSubscriptionScanReport($scanResult)
        $finalScanReport = $this.MergeScanReport($scanReport)
        $this.SetLocalSubscriptionScanReport($finalScanReport)
    }

    hidden [LSRSubscription] SerializeSubscriptionScanReport($scanResult)
    {
        $storageReport = [LSRSubscription]::new()
        $storageReport.SubscriptionId = $scanResult.SubscriptionId
        $storageReport.SubscriptionName = $scanResult.SubscriptionName 

        $scanDetails = [LSRScanDetails]::new()

        $scanResult.ControlResults | ForEach-Object {
            $serviceControlResult = $_
            $subscriptionScanResult = [LSRSubscriptionControlResult]::new()
            # $subscriptionScanResult.ScannedBy = 
            $subscriptionScanResult.ScanSource = $scanResult.Source
            $subscriptionScanResult.ScannerVersion = $scanResult.ScannerVersion 
            $subscriptionScanResult.ControlVersion = $scanResult.ControlVersion
            $subscriptionScanResult.ChildResourceName = $serviceControlResult.NestedResourceName 
            $subscriptionScanResult.ControlId = $serviceControlResult.ControlId 
            #$subscriptionScanResult.ControlUpdatedOn = $serviceControlResult.
            $subscriptionScanResult.InternalId = $serviceControlResult.ControlIntId 
            $subscriptionScanResult.ControlSeverity = $serviceControlResult.ControlSeverity 
            $subscriptionScanResult.ActualVerificationResult = $serviceControlResult.ActualVerificationResult 
            $subscriptionScanResult.AttestedBy =  $serviceControlResult.AttestedBy 
            #$subscriptionScanResult.AttestedDate = $serviceControlResult.AttestedBy
            $subscriptionScanResult.Justification = $serviceControlResult.Justification
            $subscriptionScanResult.AttestationStatus = $serviceControlResult.AttestationStatus
            $subscriptionScanResult.AttestationData = $serviceControlResult.AttestedState
            $subscriptionScanResult.VerificationResult = $serviceControlResult.VerificationResult
            $subscriptionScanResult.ScanKind = $scanResult.ScanKind
            #$subscriptionScanResult.ScannerModuleName = $scanResult.
            $subscriptionScanResult.IsLatestPSModule = $scanResult.IsLatestPSModule
            $subscriptionScanResult.HasRequiredPermissions = $scanResult.HasRequiredAccess
            $subscriptionScanResult.HasAttestationWritePermissions = $scanResult.HasAttestationWritePermissions
            $subscriptionScanResult.HasAttestationReadPermissions = $scanResult.HasAttestationReadPermissions
            #$subscriptionScanResult.UserComments = $scanResult.

            $scanDetails.SubscriptionScanResult.Add($subscriptionScanResult)
        }
        $storageReport.LSRScanDetails = $scanDetails;

        return $storageReport;
    }

    hidden [LSRSubscription] SerializeServiceScanReport($scanResult)
    {
        $storageReport = [LSRSubscription]::new()
        $storageReport.SubscriptionId = $scanResult.SubscriptionId
        $storageReport.SubscriptionName = $scanResult.SubscriptionName 
        
        $resources = [LSRResources]::new()
        $resources.HashId = [Helpers]::ComputeHash($scanResult.ResourceId)
        $resources.ResourceId = $scanResult.ResourceId
        $resources.LastEventOn = 
        $resources.FirstScannedOn = 
        
        $resources.ResourceGroupName = $scanResult.ResourceGroup
        $resources.ResourceName = $scanResult.ResourceName
        $resources.ResourceMetadata = $scanResult.Metadata

        $scanResult.ControlResults | ForEach-Object {
                $serviceControlResult = $_
                $resourceScanResult = [LSRResourceScanResult]::new()
                # $resourceScanResult.ScannedBy = 
                $resourceScanResult.ScanSource = $scanResult.Source
                $resourceScanResult.ScannerVersion = $scanResult.ScannerVersion 
                $resourceScanResult.ControlVersion = $scanResult.ControlVersion
                $resourceScanResult.ChildResourceName = $serviceControlResult.NestedResourceName 
                $resourceScanResult.ControlId = $serviceControlResult.ControlId 
                #$resourceScanResult.ControlUpdatedOn = $serviceControlResult.
                $resourceScanResult.InternalId = $serviceControlResult.ControlIntId 
                $resourceScanResult.ControlSeverity = $serviceControlResult.ControlSeverity 
                $resourceScanResult.ActualVerificationResult = $serviceControlResult.ActualVerificationResult 
                $resourceScanResult.AttestedBy =  $serviceControlResult.AttestedBy 
                #$resourceScanResult.AttestedDate = $serviceControlResult.AttestedBy
                $resourceScanResult.Justification = $serviceControlResult.Justification
                $resourceScanResult.AttestationStatus = $serviceControlResult.AttestationStatus
                $resourceScanResult.AttestationData = $serviceControlResult.AttestedState
                $resourceScanResult.VerificationResult = $serviceControlResult.VerificationResult
                $resourceScanResult.ScanKind = $scanResult.ScanKind
                #$resourceScanResult.ScannerModuleName = $scanResult.
                $resourceScanResult.IsLatestPSModule = $scanResult.IsLatestPSModule
                $resourceScanResult.HasRequiredPermissions = $scanResult.HasRequiredAccess
                $resourceScanResult.HasAttestationWritePermissions = $scanResult.HasAttestationWritePermissions
                $resourceScanResult.HasAttestationReadPermissions = $scanResult.HasAttestationReadPermissions
                #$resourceScanResult.UserComments = $scanResult.

                $resources.ResourceScanResult.Add($resourceScanResult)
        }

        $scanDetails = [LSRScanDetails]::new()
        $scanDetails.Resources.Add($resources)
        $storageReport.LSRScanDetails = $scanDetails;

        return $storageReport;
    }

    hidden [LocalSubscriptionReport] MergeScanReport([LSRSubscription] $scanReport)
    {
        $_oldScanReport = $this.GetLocalSubscriptionScanReport();

        
        if(($_oldScanReport | Where-Object { $_.SubscriptionId -eq $scanReport.SubscriptionId }).Count -gt 0)
        {

        }
        else
        {
            $_oldScanReport.Subscriptions += $scanReport;
        }

        return $_oldScanReport
    }

}
