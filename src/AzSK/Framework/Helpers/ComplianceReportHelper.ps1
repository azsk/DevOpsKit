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
			#unable to find zip file. return empty object
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
	hidden [LocalSubscriptionReport] MergeSVTScanResult($currentScanResults, $resourceInventory)
	{
		if($currentScanResults.Count -lt 1) { return $null}

		$SVTEventContextFirst = $currentScanResults[0]

		$complianceReport = $this.GetSubscriptionComplianceReport($currentScanResults);
		$subscription = [LSRSubscription]::new()
		[LSRResources[]] $resources = @()

		if($null -ne $complianceReport -and (($complianceReport.Subscriptions | Where-Object { $_.SubscriptionId -eq $this.SubscriptionContext.SubscriptionId }) | Measure-Object).Count -gt 0)
		{
			$subscription = $complianceReport.Subscriptions | Where-Object { $_.SubscriptionId -eq $this.SubscriptionContext.SubscriptionId }
		}
		else
		{
			$subscription.SubscriptionId = $this.SubscriptionContext.SubscriptionId
			$subscription.SubscriptionName = $SVTEventContextFirst.SubscriptionContext.SubscriptionName
		}

		if($null -ne $subscription.ScanDetails)
		{
			$resources = $subscription.ScanDetails.Resources
		}
		else
		{
			$subscription.ScanDetails = [LSRScanDetails]::new()
		}

		$currentScanResults | ForEach-Object {
			$currentScanResult = $_
			try
			{
				if($currentScanResult.FeatureName -eq "SubscriptionCore")
				{
					if(($subscription.ScanDetails.SubscriptionScanResult | Measure-Object).Count -gt 0)
					{
						$matchedControlResults = $subscription.ScanDetails.SubscriptionScanResult | Where-Object { $currentScanResult.ControlItem.Id -eq $_.ControlIntId }
						if((($matchedControlResults) | Measure-Object).Count -gt 0)
						{
							$_complianceSubResult = $matchedControlResults
							$svtResults = $this.ConvertScanResultToSnapshotResult($currentScanResult, $_complianceSubResult, $true)

							$subscription.ScanDetails.SubscriptionScanResult = $subscription.ScanDetails.SubscriptionScanResult | Where-Object {$_.ControlIntId -ne $currentScanResult.ControlItem.Id }
							$subscription.ScanDetails.SubscriptionScanResult += $svtResults
						}
						else
						{
							$subscription.ScanDetails.SubscriptionScanResult += $this.ConvertScanResultToSnapshotResult($currentScanResult, $null, $true)
						}
					}
					else
					{
						$subscription.ScanDetails.SubscriptionScanResult += $this.ConvertScanResultToSnapshotResult($currentScanResult, $null, $true)
					}
				}
				elseif($currentScanResult.FeatureName -ne "AzSKCfg")
				{
					$filteredResource = $resources | Where-Object {$_.ResourceId -eq $currentScanResult.ResourceContext.ResourceId }

					if(($filteredResource | Measure-Object).Count -gt 0)
					{
						$resource = $filteredResource
						$resource.LastEventOn = [DateTime]::UtcNow.ToString('s')

						$matchedControlResults = $resource.ResourceScanResult | Where-Object { $_.ControlIntId -eq $currentScanResult.ControlItem.Id }
						if((($matchedControlResults) | Measure-Object).Count -gt 0)
						{
							$_complianceResResult = $matchedControlResults
							$svtResults = $this.ConvertScanResultToSnapshotResult($currentScanResult, $_complianceResResult, $false)
							$resource.ResourceScanResult = $resource.ResourceScanResult | Where-Object { $_.ControlIntId -ne $_complianceResResult[0].ControlIntId }
							$resource.ResourceScanResult += $svtResults
						}
						else
						{
							$resource.ResourceScanResult += $this.ConvertScanResultToSnapshotResult($currentScanResult, $null, $false)
						}

						$tmpResources = $resources | Where-Object {$_.ResourceId -ne $resource.ResourceId } 
						$resources = @()
						$resources += $tmpResources
						$resources += $resource
					}
					else
					{
						$resource = [LSRResources]::New()
						$resource.HashId = [Helpers]::ComputeHash($currentScanResult.ResourceContext.ResourceId)
						$resource.ResourceId = $currentScanResult.ResourceContext.ResourceId
						$resource.LastEventOn = [DateTime]::UtcNow.ToString('s')
						$resource.FirstScannedOn = [DateTime]::UtcNow.ToString('s')
						$resource.ResourceGroupName = $currentScanResult.ResourceContext.ResourceGroupName
						$resource.ResourceName = $currentScanResult.ResourceContext.ResourceName

						# ToDo: Need to confirm
						# $resource.ResourceMetadata = [Helpers]::ConvertToJsonCustomCompressed($currentScanResult.ResourceContext.ResourceMetadata)
						$resource.FeatureName = $currentScanResult.FeatureName
						$resource.ResourceScanResult += $this.ConvertScanResultToSnapshotResult($currentScanResult, $null, $false)
						$resources += $resource
					}
				}
			}
			catch
			{
				[EventBase]::PublishGenericException($_);
			}
		}

		if($null -ne $resourceInventory)
		{
			if($resources.Count -gt 0)
			{
				$deletedResoures = @()
				$resources | ForEach-Object {
					$resource = $_
					if(($resourceInventory | Where-Object { $_.ResourceId -eq $resource.ResourceId } | Measure-Object).Count -eq 0)
					{
						$deletedResoures += $resource.ResourceId
					}
				}
				$resources = $resources | Where-Object { $deletedResoures -notcontains $_.ResourceId }
			}

			$resourceInventory | ForEach-Object {
				$resource = $_
				try {
					if([Helpers]::CheckMember($resource, "ResourceId"))
					{
						if((($resources | Where-Object { $_.ResourceId -eq  $resource.ResourceId }) | Measure-Object).Count -eq 0)
						{
							$newResource = [LSRResources]::new()
							$newResource.HashId = [Helpers]::ComputeHash($resource.ResourceId)
							$newResource.ResourceId = $resource.ResourceId
							$newResource.FeatureName = $supportedResourceTypes[$resource.ResourceType.ToLower()]
							$newResource.ResourceGroupName = $resource.ResourceGroupName
							$newResource.ResourceName = $resource.Name

							$resources += $newResource	
						}
					}
				}
				catch
				{
					[EventBase]::PublishGenericException($_);
				}
			}
		}
		
		# Remove updated objects from existing compliance data
		$resources | ForEach-Object {
			$resource = $_
			if($null -ne $subscription.ScanDetails.Resources -and $subscription.ScanDetails.Resources.Count -gt 0)
			{
				$subscription.ScanDetails.Resources = $subscription.ScanDetails.Resources | Where-Object { $_.ResourceId -ne $resource.ResourceId }
			}
		}
		
		# append new updated objects
		$subscription.ScanDetails.Resources += $resources
		
		if($null -ne $complianceReport)
		{
			$complianceReport.Subscriptions = $complianceReport.Subscriptions | Where-Object { $_.SubscriptionId -ne $subscription.SubscriptionId }
		}
		else
		{
			$complianceReport = [LocalSubscriptionReport]::new()
		}
		
		$complianceReport.Subscriptions += $subscription;

		return $complianceReport
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
			if($scanResult.VerificationResult -ne $currentSVTResult.VerificationResult)
			{
				$scanResult.LastResultTransitionOn = [System.DateTime]::UtcNow.ToString("s");
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
			$scanResult.ControlVersion = $this.ScannerVersion	
			#TODO check in the case sub control					
			$scanResult.ChildResourceName = $currentSVTResult.ChildResourceName 			
			$scanResult.ControlId = $controlItem.ControlId 			
			$scanResult.ControlIntId = $controlItem.Id 
			$scanResult.ControlSeverity = $controlItem.ControlSeverity 
			$scanResult.ActualVerificationResult = $currentSVTResult.ActualVerificationResult 
			$scanResult.AttestationStatus = $currentSVTResult.AttestationStatus
			if($scanResult.AttestationStatus -ne [AttestationStatus]::None -and $null -ne $currentSVTResult.StateManagement -and $null -ne $currentSVTResult.StateManagement.AttestedStateData)
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
				# $resourceScanResult.AttestationData = [Helpers]::ConvertToJsonCustomCompressed($currentResult.StateManagement.AttestedStateData.DataObject)	
			}
			else
			{
				$scanResult.AttestedBy = ""
				$scanResult.AttestedDate = [Constants]::AzSKDefaultDateTime.ToString("s") ;
				$scanResult.Justification = ""
				$scanResult.AttestationData = ""
			}
			
			$scanResult.VerificationResult = $currentSVTResult.VerificationResult
			$scanResult.ScanKind = $this.ScanKind
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

			# ToDo: Need to confirm
			#$resourceScanResult.Metadata = $scanResult.Metadata			
		}
						
		return $scanResult
	}

	#new functions	
	hidden [ComplianceStateTableEntity[]] ConvertScanResultToSnapshotResultV2([SVTEventContext[]] $inputResult)
	{
		[ComplianceStateTableEntity[]] $convertedEntities = @();	

		$inputResult | ForEach-Object {
			$oldEntity = $_
			$oldEntity.ControlResults | ForEach-Object{
				$currentResult = $_
				$newEntity = [ComplianceStateTableEntity]::new()
				$isLegitimateResult = ($currentResult.CurrentSessionContext.IsLatestPSModule -and $currentResult.CurrentSessionContext.Permissions.HasRequiredAccess -and $currentResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions)
                #TODO: change below to $isLegitimateResult after dev done
				if($true)
				{
	
					#if($resourceScanResult.VerificationResult -ne $currentResult.VerificationResult)
					#{
					#		$resourceScanResult.LastResultTransitionOn = [System.DateTime]::UtcNow
					#}
	
					#if($resourceScanResult.FirstScannedOn -eq [Constants]::AzSKDefaultDateTime)
					#{
					#	$resourceScanResult.FirstScannedOn = [System.DateTime]::UtcNow
					#}
	
					#if($resourceScanResult.FirstFailedOn -eq [Constants]::AzSKDefaultDateTime -and $currentResult.ActualVerificationResult -ne [VerificationResult]::Passed)
					#{
					#		$resourceScanResult.FirstFailedOn = [System.DateTime]::UtcNow
					#	}
	
					$newEntity.ScannedBy = [Helpers]::GetCurrentRMContext().Account
					$newEntity.ScanSource = $this.ScanSource
					$newEntity.ScannerVersion = $this.ScannerVersion
					$newEntity.ControlVersion = $this.ScannerVersion
					if($oldEntity.FeatureName -ne "SubscriptionCore")
					{
						$newEntity.ChildResourceName = $currentResult.ChildResourceName 
                        #compute hash
						$newEntity.PartitionKey = $currentResult.ResourceContext.ResourceId                         
					}
                    else
                    {
						$newEntity.PartitionKey = $this.SubscriptionCOntext.SubscriptionId                         
                    }
                    $newEntity.RowKey = $oldEntity.ControlItem.Id 
					$newEntity.ControlId = $oldEntity.ControlItem.ControlId 
					$newEntity.ControlIntId = $oldEntity.ControlItem.Id 
					$newEntity.ControlSeverity = $oldEntity.ControlItem.ControlSeverity 
					$newEntity.ActualVerificationResult = $currentResult.ActualVerificationResult 
					$newEntity.AttestationStatus = $currentResult.AttestationStatus
					if($newEntity.AttestationStatus -ne [AttestationStatus]::None -and $null -ne $currentResult.StateManagement -and $null -ne $currentResult.StateManagement.AttestedStateData)
					{
						if($newEntity.FirstAttestedOn -eq [Constants]::AzSKDefaultDateTime)
						{
							$newEntity.FirstAttestedOn = $currentResult.StateManagement.AttestedStateData.AttestedDate
						}
	
						if($currentResult.StateManagement.AttestedStateData.AttestedDate -gt $newEntity.AttestedDate)
						{
							$newEntity.AttestationCounter = $newEntity.AttestationCounter + 1 
						}
						$newEntity.AttestedBy =  $currentResult.StateManagement.AttestedStateData.AttestedBy
						$newEntity.AttestedDate = $currentResult.StateManagement.AttestedStateData.AttestedDate 
						$newEntity.Justification = $currentResult.StateManagement.AttestedStateData.Justification
						# $newEntity.AttestationData = [Helpers]::ConvertToJsonCustomCompressed($currentResult.StateManagement.AttestedStateData.DataObject)	
					}
					else
					{
						$newEntity.AttestedBy = ""
						$newEntity.AttestedDate = [Constants]::AzSKDefaultDateTime 
						$newEntity.Justification = ""
						$newEntity.AttestationData = ""
					}
					$newEntity.VerificationResult = $currentResult.VerificationResult
					$newEntity.ScanKind = $this.ScanKind
					$newEntity.ScannerModuleName = [Constants]::AzSKModuleName
					$newEntity.IsLatestPSModule = $currentResult.CurrentSessionContext.IsLatestPSModule
					$newEntity.HasRequiredPermissions = $currentResult.CurrentSessionContext.Permissions.HasRequiredAccess
					$newEntity.HasAttestationWritePermissions = $currentResult.CurrentSessionContext.Permissions.HasAttestationWritePermissions
					$newEntity.HasAttestationReadPermissions = $currentResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions
					$newEntity.UserComments = $currentResult.UserComments
					$newEntity.IsBaselineControl = $oldEntity.ControlItem.IsBaselineControl
					
					if($oldEntity.ControlItem.Tags.Contains("OwnerAccess") -or $oldEntity.ControlItem.Tags.Contains("GraphRead"))
					{
						$newEntity.HasOwnerAccessTag = $true
					}
					$newEntity.LastScannedOn = [DateTime]::UtcNow.ToString('s')

					# ToDo: Need to confirm
					#$newEntity.Metadata = $scanResult.Metadata
					$convertedEntities += $newEntity
			}
			}
		}
		return $convertedEntities
	}
	hidden [ComplianceStateTableEntity[]] MergeSVTScanResultV2($currentScanResults, $resourceInventory)
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
	hidden [void] SetLocalSubscriptionScanReportV2([ComplianceStateTableEntity[]] $scanResultForStorage)
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
		# ToDo: Resource inventory helper
		#if($this.ScanSource -eq [ScanSource]::Runbook) 
		#{
		# if($updateResourceInventory) 
		# {
		# 	$resources = "" | Select-Object "SubscriptionId", "ResourceGroups"
		# 	$resources.ResourceGroups = [System.Collections.ArrayList]::new()
		# 	# ToDo: cache this properties as AzSKRoot.
		# 	$resourcesFlat = Find-AzureRmResource
		# 	$supportedResourceTypes = [SVTMapping]::GetSupportedResourceMap()
		# 	# Not considering nested resources to reduce complexity
		# 	$filteredResources = $resourcesFlat | Where-Object { $supportedResourceTypes.ContainsKey($_.ResourceType.ToLower()) }			
		# }
		#}
		#$convertedCurrentScanResult = $this.ConvertScanResultToSnapshotResultV2($currentScanResult)
		$finalScanReport = $this.MergeSVTScanResultV2($currentScanResult, $filteredResources)
		$this.SetLocalSubscriptionScanReportV2($finalScanReport)
	}
}