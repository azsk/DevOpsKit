Set-StrictMode -Version Latest

class ComplianceReportHelper: ComplianceBase
{
    hidden [string] $ScanSource
	hidden [System.Version] $ScannerVersion
	hidden [string] $ScanKind 

    ComplianceReportHelper([SubscriptionContext] $subscriptionContext,[System.Version] $ScannerVersion):
    Base([SubscriptionContext] $subscriptionContext) 
	{
		$this.ScanSource = [RemoteReportHelper]::GetScanSource();
		$this.ScannerVersion = $ScannerVersion
		$this.ScanKind = [ServiceScanKind]::Partial;
	} 
	
	hidden [ComplianceStateTableEntity[]] GetSubscriptionComplianceReport()
	{
		return $this.GetSubscriptionComplianceReport($null);
	}

    hidden [ComplianceStateTableEntity[]] GetSubscriptionComplianceReport($currentScanResults)
	{
		[ComplianceStateTableEntity[]] $complianceData = @()
		try
		{
			$queryStringParams = "";
			$partitionKeys = @();
			if(($currentScanResults | Measure-Object).Count -gt 0)
			{
				$currentScanResults | ForEach-Object {
					$currentScanResult = $_;
					$resourceId = $currentScanResult.SubscriptionContext.Scope;
					if($currentScanResult.IsResource())
					{
						$resourceId = $currentScanResult.ResourceContext.ResourceId;
					}
					$controlsToProcess = @();
					if(($currentScanResult.ControlResults | Measure-Object).Count -gt 0)
					{	
						$controlsToProcess += $currentScanResult.ControlResults;
					}
					$controlsToProcess | ForEach-Object {
						$cScanResult = $_;
						$partsToHash = $resourceId;
						if(-not [string]::IsNullOrWhiteSpace($cScanResult.ChildResourceName))
						{
							$partsToHash = $partsToHash + ":" + $cScanResult.ChildResourceName;
						}
						$currentResultHashId = [Helpers]::ComputeHash($partsToHash.ToLower());
						$partitionKeys += $currentResultHashId;
					}
				}
				$partitionKeys = $partitionKeys | Select -Unique

				$template = "PartitionKey%20eq%20'{0}'";
				$tempQS = "?`$filter="
				$haveParitionKeys = $false;
				$partitionKeys | ForEach-Object {
					$pKey = $_
					$tempQS = $tempQS + ($template -f $pKey) + "%20or%20";
					$haveParitionKeys = $true;
				 }
				 if($haveParitionKeys)
				 {
					 $tempQS = $tempQS.Substring(0,$tempQS.Length - 8);
					 $queryStringParams = $tempQS
				 }
			}

			$storageInstance = $this.GetStorageHelperInstance()
			$TableName = $this.ComplianceTableName
			$AccountName = $storageInstance.StorageAccountName
			$AccessKey = [Helpers]::GetStorageAccountAccessKey($storageInstance.ResourceGroupName,$AccountName) 
			$Uri="https://$AccountName.table.core.windows.net/$TableName()$queryStringParams"
			$Verb = "GET"
			$ContentMD5 = ""
			$ContentType = ""
			$Date = [DateTime]::UtcNow.ToString('r')
			$CanonicalizedResource = "/$AccountName/$TableName()"
			$SigningParts=@($Verb,$ContentMD5,$ContentType,$Date,$CanonicalizedResource)
			$StringToSign = [String]::Join("`n",$SigningParts)
			$sharedKey = [Helpers]::CreateStorageAccountSharedKey($StringToSign,$AccountName,$AccessKey)

			$xmsdate = $Date
			$headers = @{"Accept"="application/json";"x-ms-date"=$xmsdate;"Authorization"="SharedKey $sharedKey";"x-ms-version"="2018-03-28"}
			$tempComplianceData  = ([WebRequestHelper]::InvokeGetWebRequest($Uri,$headers)) 
			foreach($item in $tempComplianceData)
			{
				$newEntity = [ComplianceStateTableEntity]::new()
				foreach($Property in $newEntity | Get-Member -type NoteProperty, Property){
					$newEntity.$($Property.Name) = $item.$($Property.Name)
				}
				$complianceData+=$newEntity
			}	
		}
		catch
		{
			return $null;
		}
		return $complianceData;		
    }

    hidden [LSRSubscription] GetLocalSubscriptionScanReport([string] $subId)
    {
		if($this.GetStorageHelperInstance().HaveWritePermissions -eq 0)
		{
			return $null;
		}
        $fullScanResult = $this.GetLocalSubscriptionScanReport();
        if($null -ne $fullScanResult -and ($fullScanResult.Subscriptions | Measure-Object ).Count -gt 0)
        {
            return $fullScanResult.Subscriptions | Where-Object { $_.SubscriptionId -eq $subId }
        }
        else
        {
            return $null;
        }
    }

    hidden [void] SetLocalSubscriptionScanReport([LocalSubscriptionReport] $scanResultForStorage)
	{		
		try
		{
			if($this.GetStorageHelperInstance().HaveWritePermissions -eq 0)
			{
				return;
			}
			$AzSKTemp = [Constants]::AzSKAppFolderPath + [Constants]::ComplianceReportPath;				
			if(-not (Test-Path "$AzSKTemp"))
			{
				mkdir -Path "$AzSKTemp" -ErrorAction Stop | Out-Null
			}
			else
			{
				Remove-Item -Path "$AzSKTemp\*" -Force -Recurse 
			}

			$fileName = "$AzSKTemp\" + $this.SubscriptionContext.SubscriptionId +".json"
			$compressedFileName = "$AzSKTemp\" + [Constants]::ComplianceReportBlobName +".zip"
			$ContainerName = [Constants]::ComplianceReportContainerName;

			[Helpers]::ConvertToJsonCustomCompressed($scanResultForStorage) | Out-File $fileName -Force

			#compress file before store to storage

			Compress-Archive -Path $fileName -CompressionLevel Optimal -DestinationPath $compressedFileName -Update

			$fileInfos = @();
			$fileInfos += [System.IO.FileInfo]::new($compressedFileName);
			$this.GetStorageHelperInstance().UploadFilesToBlob($ContainerName, "", $fileInfos, $true);
		}
		finally
		{
			[Helpers]::CleanupLocalFolder([Constants]::AzSKAppFolderPath + [Constants]::ComplianceReportPath);
		}
    }		
		
	hidden [ComplianceStateTableEntity] ConvertScanResultToSnapshotResult($currentSVTResult, $persistedSVTResult, $controlItem, $partitionKey)
	{
		[ComplianceStateTableEntity] $scanResult = [ComplianceStateTableEntity]::new();
		$scanResult.PartitionKey = $partitionKey;
		$scanResult.RowKey = $controlItem.Id
		$scanResult.HashId = $partitionKey;
		if($null -ne $persistedSVTResult)
		{
			$scanResult = $persistedSVTResult;
		}
		$isLegitimateResult = ($currentSVTResult.CurrentSessionContext.IsLatestPSModule -and $currentSVTResult.CurrentSessionContext.Permissions.HasRequiredAccess -and $currentSVTResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions)
		if($isLegitimateResult)
		{
			if($scanResult.VerificationResult -ne $currentSVTResult.VerificationResult.ToString())
			{
				$scanResult.LastResultTransitionOn = [System.DateTime]::UtcNow.ToString("s");
				$scanResult.PreviousVerificationResult = $scanResult.VerificationResult;
			}

			if($scanResult.FirstScannedOn -eq [Constants]::AzSKDefaultDateTime)
			{
				$scanResult.FirstScannedOn = [System.DateTime]::UtcNow.ToString("s");
			}

			if($scanResult.FirstFailedOn -eq [Constants]::AzSKDefaultDateTime -and $currentSVTResult.ActualVerificationResult -ne [VerificationResult]::Passed)
			{
				$scanResult.FirstFailedOn = [System.DateTime]::UtcNow.ToString("s");
			}

			$scanResult.ScannedBy = [Helpers]::GetCurrentRMContext().Account
			$scanResult.ScanSource = $this.ScanSource
			$scanResult.ScannerVersion = $this.ScannerVersion
			#TODO check in the case sub control					
			$scanResult.ChildResourceName = $currentSVTResult.ChildResourceName 			
			$scanResult.ControlId = $controlItem.ControlId 			
			$scanResult.ControlIntId = $controlItem.Id 
			$scanResult.ControlSeverity = $controlItem.ControlSeverity.ToString()
			$scanResult.ActualVerificationResult = $currentSVTResult.ActualVerificationResult.ToString(); 
			$scanResult.AttestationStatus = $currentSVTResult.AttestationStatus.ToString();
			if($scanResult.AttestationStatus.ToString() -ne [AttestationStatus]::None -and $null -ne $currentSVTResult.StateManagement -and $null -ne $currentSVTResult.StateManagement.AttestedStateData)
			{
				if($scanResult.FirstAttestedOn -eq [Constants]::AzSKDefaultDateTime)
				{
					$scanResult.FirstAttestedOn = $currentSVTResult.StateManagement.AttestedStateData.AttestedDate.ToString("s");
				}

				if($scanResult.StateManagement.AttestedStateData.AttestedDate -gt $scanResult.AttestedDate)
				{
					$scanResult.AttestationCounter = $scanResult.AttestationCounter + 1 
				}
				$scanResult.AttestedBy =  $currentSVTResult.StateManagement.AttestedStateData.AttestedBy
				$scanResult.AttestedDate = $currentSVTResult.StateManagement.AttestedStateData.AttestedDate.ToString("s");
				$scanResult.Justification = $currentSVTResult.StateManagement.AttestedStateData.Justification
			}
			else
			{
				$scanResult.AttestedBy = ""
				$scanResult.AttestedDate = [Constants]::AzSKDefaultDateTime.ToString("s") ;
				$scanResult.Justification = ""
				$scanResult.AttestationData = ""
			}
			if($currentSVTResult.VerificationResult -ne [VerificationResult]::Manual)
			{
				$scanResult.VerificationResult = $currentSVTResult.VerificationResult
			}
			else {
				$scanResult.VerificationResult = $currentSVTResult.ActualVerificationResult.ToString();
			}
			$scanResult.ScannerModuleName = [Constants]::AzSKModuleName
			$scanResult.IsLatestPSModule = $currentSVTResult.CurrentSessionContext.IsLatestPSModule
			$scanResult.HasRequiredPermissions = $currentSVTResult.CurrentSessionContext.Permissions.HasRequiredAccess
			$scanResult.HasAttestationWritePermissions = $currentSVTResult.CurrentSessionContext.Permissions.HasAttestationWritePermissions
			$scanResult.HasAttestationReadPermissions = $currentSVTResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions
			$scanResult.UserComments = $currentSVTResult.UserComments
			$scanResult.IsBaselineControl = $controlItem.IsBaselineControl
			
			if($controlItem.Tags.Contains("OwnerAccess") -or $controlItem.Tags.Contains("GraphRead"))
			{
				$scanResult.HasOwnerAccessTag = $true
			}
			$scanResult.LastScannedOn = [DateTime]::UtcNow.ToString('s')
		}
						
		return $scanResult
	}

	#new functions	
	
	hidden [ComplianceStateTableEntity[]] MergeSVTScanResult($currentScanResults)
	{
		if($currentScanResults.Count -lt 1) { return $null}
		[ComplianceStateTableEntity[]] $finalScanData = @()
		#TODO
		$SVTEventContextFirst = $currentScanResults[0]

		#TODO get specific data
		$complianceReport = $this.GetSubscriptionComplianceReport($currentScanResults);
		
		$foundPersistedData = ($complianceReport | Measure-Object).Count -gt 0
		$currentScanResults | ForEach-Object {
			$currentScanResult = $_
			$resourceId = $currentScanResult.SubscriptionContext.Scope;
			if($currentScanResult.IsResource())
			{
				$resourceId = $currentScanResult.ResourceContext.ResourceId;
			}
			if($currentScanResult.FeatureName -ne "AzSKCfg")
			{
				$controlsToProcess = @();

				if(($currentScanResult.ControlResults | Measure-Object).Count -gt 0)
				{	
					$controlsToProcess += $currentScanResult.ControlResults;
				}
				
				$controlsToProcess | ForEach-Object {
					$cScanResult = $_;
					$partsToHash = $resourceId;
					if(-not [string]::IsNullOrWhiteSpace($cScanResult.ChildResourceName))
					{
						$partsToHash = $partsToHash + ":" + $cScanResult.ChildResourceName;
					}
					$currentResultHashId = [Helpers]::ComputeHash($partsToHash.ToLower());
					$persistedScanResult = $null;
					if($foundPersistedData)
					{
						$persistedScanResult = $complianceReport | Where-Object { $_.PartitionKey -eq $currentResultHashId -and $_.RowKey -eq $currentScanResult.ControlItem.Id }
						# if(($persistedScanResult | Measure-Object).Count -le 0)
						# {
						# 	$foundPersistedData = $false;
						# }				
					}
					$mergedScanResult = $this.ConvertScanResultToSnapshotResult($cScanResult, $persistedScanResult, $currentScanResult.ControlItem, $currentResultHashId)
					$finalScanData += $mergedScanResult;
				}
			}
		}

		return $finalScanData
	}
	hidden [void] SetLocalSubscriptionScanReport([ComplianceStateTableEntity[]] $scanResultForStorage)
	{		
		$storageInstance = $this.GetStorageHelperInstance()

		$groupedScanResultForStorage = $scanResultForStorage | Group-Object { $_.PartitionKey}
		$groupedScanResultForStorage | ForEach-Object {
			$group = $_;
			$results = $_.Group;
			#MERGE batch req sample
			[WebRequestHelper]::InvokeTableStorageBatchWebRequest($storageInstance.ResourceGroupName,$storageInstance.StorageAccountName,$this.ComplianceTableName,$results,$true)
			#POST batch req sample
			#[WebRequestHelper]::InvokeTableStorageBatchWebRequest($storageInstance.ResourceGroupName,$storageInstance.StorageAccountName,$this.ComplianceTableName,$results,$false)
		}		
    }
	hidden [void] StoreComplianceDataInUserSubscription([SVTEventContext[]] $currentScanResult)
	{
		$filteredResources = $null
		#TODO need to figure out on how to delete the old records for deleted resources
		$finalScanReport = $this.MergeSVTScanResult($currentScanResult)
		$this.SetLocalSubscriptionScanReport($finalScanReport)
	}
}