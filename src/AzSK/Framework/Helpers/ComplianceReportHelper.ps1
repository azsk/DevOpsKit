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
    
    hidden [LocalSubscriptionReport] GetLocalSubscriptionScanReport()
	{
		[LocalSubscriptionReport] $storageReport = $null;
		try
		{
			if($this.GetStorageHelperInstance().HaveWritePermissions -eq 0)
			{
				return $null;
			}
            $complianceReportBlobName = [Constants]::ComplianceReportBlobName + ".zip"
            
            $ContainerName = [Constants]::ComplianceReportContainerName           
            $AzSKTemp = [Constants]::AzSKAppFolderPath + [Constants]::ComplianceReportPath;
			
			if(-not (Test-Path -Path $AzSKTemp))
            {
                mkdir -Path $AzSKTemp -Force
            }

			$this.GetStorageHelperInstance().DownloadFilesFromBlob($ContainerName, $complianceReportBlobName, $AzSKTemp, $true);
            $fileName = $AzSKTemp+"\"+$this.SubscriptionContext.SubscriptionId +".json";
			$StorageReportJson = $null;
			try
			{
				# extract file from zip
				$compressedFileName = $AzSKTemp+"\"+[Constants]::ComplianceReportBlobName +".zip"
				if((Test-Path -Path $compressedFileName -PathType Leaf))
				{
					Expand-Archive -Path $compressedFileName -DestinationPath $AzSKTemp -Force
					if((Test-Path -Path $fileName -PathType Leaf))
					{
						$StorageReportJson = (Get-ChildItem -Path $fileName -Force | Get-Content | ConvertFrom-Json)
					}
				}
			}
			catch
			{
				#unable to find zip file. return empty object
				return $null;
			}
			if($null -ne $StorageReportJson)
			{
				$storageReport = [LocalSubscriptionReport] $StorageReportJson;
			}
			return $storageReport;
		}
		finally{
			[Helpers]::CleanupLocalFolder([Constants]::AzSKAppFolderPath + [Constants]::ComplianceReportPath);
		}
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

		$complianceReport = $this.GetLocalSubscriptionScanReport();
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
						$resource.LastEventOn = [DateTime]::UtcNow

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
						$resource.LastEventOn = [DateTime]::UtcNow
						$resource.FirstScannedOn = [DateTime]::UtcNow
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
	
	hidden [LSRControlResultBase[]] ConvertScanResultToSnapshotResult($svtResult, $oldResult, $isSubscriptionScan)
	{
		[LSRControlResultBase[]] $scanResults = @();	

		$svtResult.ControlResults | ForEach-Object {
			$currentResult = $_
			$isLegitimateResult = ($currentResult.CurrentSessionContext.IsLatestPSModule -and $currentResult.CurrentSessionContext.Permissions.HasRequiredAccess -and $currentResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions)
			if($isLegitimateResult)
			{
				$resourceScanResult = [LSRControlResultBase]::new()
				if($isSubscriptionScan) 
				{
					if($null -ne $oldResult)
					{
						$resourceScanResult = $oldResult
					}
					else
					{
						$resourceScanResult = [LSRSubscriptionControlResult]::new()
					}
				}
				else
				{
					if($null -ne $oldResult)
					{
						$resourceScanResult = $oldResult | Where-Object { $_.ChildResourceName -eq $currentResult.ChildResourceName }
					}
					else
					{
						$resourceScanResult = [LSRResourceScanResult]::new()
					}
				}

				if($resourceScanResult.VerificationResult -ne $currentResult.VerificationResult)
				{
					$resourceScanResult.LastResultTransitionOn = [System.DateTime]::UtcNow
				}

				if($resourceScanResult.FirstScannedOn -eq [Constants]::AzSKDefaultDateTime)
				{
					$resourceScanResult.FirstScannedOn = [System.DateTime]::UtcNow
				}

				if($resourceScanResult.FirstFailedOn -eq [Constants]::AzSKDefaultDateTime -and $currentResult.ActualVerificationResult -ne [VerificationResult]::Passed)
				{
					$resourceScanResult.FirstFailedOn = [System.DateTime]::UtcNow
				}

				$resourceScanResult.ScannedBy = [Helpers]::GetCurrentRMContext().Account
				$resourceScanResult.ScanSource = $this.ScanSource
				$resourceScanResult.ScannerVersion = $this.ScannerVersion
				$resourceScanResult.ControlVersion = $this.ScannerVersion
				if(-not $isSubscriptionScan)
				{
					$resourceScanResult.ChildResourceName = $currentResult.ChildResourceName 
				}
				$resourceScanResult.ControlId = $svtResult.ControlItem.ControlId 
				$resourceScanResult.ControlIntId = $svtResult.ControlItem.Id 
				$resourceScanResult.ControlSeverity = $svtResult.ControlItem.ControlSeverity 
				$resourceScanResult.ActualVerificationResult = $currentResult.ActualVerificationResult 
				$resourceScanResult.AttestationStatus = $currentResult.AttestationStatus
				if($resourceScanResult.AttestationStatus -ne [AttestationStatus]::None -and $null -ne $currentResult.StateManagement -and $null -ne $currentResult.StateManagement.AttestedStateData)
				{
					if($resourceScanResult.FirstAttestedOn -eq [Constants]::AzSKDefaultDateTime)
					{
						$resourceScanResult.FirstAttestedOn = $currentResult.StateManagement.AttestedStateData.AttestedDate
					}

					if($currentResult.StateManagement.AttestedStateData.AttestedDate -gt $resourceScanResult.AttestedDate)
					{
						$resourceScanResult.AttestationCounter = $resourceScanResult.AttestationCounter + 1 
					}
					$resourceScanResult.AttestedBy =  $currentResult.StateManagement.AttestedStateData.AttestedBy
					$resourceScanResult.AttestedDate = $currentResult.StateManagement.AttestedStateData.AttestedDate 
					$resourceScanResult.Justification = $currentResult.StateManagement.AttestedStateData.Justification
					# $resourceScanResult.AttestationData = [Helpers]::ConvertToJsonCustomCompressed($currentResult.StateManagement.AttestedStateData.DataObject)	
				}
				else
				{
					$resourceScanResult.AttestedBy = ""
					$resourceScanResult.AttestedDate = [Constants]::AzSKDefaultDateTime 
					$resourceScanResult.Justification = ""
					$resourceScanResult.AttestationData = ""
				}
				
				$resourceScanResult.VerificationResult = $currentResult.VerificationResult
				$resourceScanResult.ScanKind = $this.ScanKind
				$resourceScanResult.ScannerModuleName = [Constants]::AzSKModuleName
				$resourceScanResult.IsLatestPSModule = $currentResult.CurrentSessionContext.IsLatestPSModule
				$resourceScanResult.HasRequiredPermissions = $currentResult.CurrentSessionContext.Permissions.HasRequiredAccess
				$resourceScanResult.HasAttestationWritePermissions = $currentResult.CurrentSessionContext.Permissions.HasAttestationWritePermissions
				$resourceScanResult.HasAttestationReadPermissions = $currentResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions
				$resourceScanResult.UserComments = $currentResult.UserComments
				$resourceScanResult.IsBaselineControl = $svtResult.ControlItem.IsBaselineControl
				
				if($svtResult.ControlItem.Tags.Contains("OwnerAccess") -or $svtResult.ControlItem.Tags.Contains("GraphRead"))
				{
					$resourceScanResult.HasOwnerAccessTag = $true
				}
				$resourceScanResult.LastScannedOn = [DateTime]::UtcNow

				# ToDo: Need to confirm
				#$resourceScanResult.Metadata = $scanResult.Metadata
				$scanResults += $resourceScanResult
			}
		}
		return $scanResults
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
					$newEntity.LastScannedOn = [DateTime]::UtcNow

					# ToDo: Need to confirm
					#$newEntity.Metadata = $scanResult.Metadata
					$convertedEntities += $newEntity
			}
			}
		}
		return $convertedEntities
	}
	hidden [ComplianceStateTableEntity[]] MergeSVTScanResultV2($currentScanData, $resourceInventory)
	{
		if($currentScanData.Count -lt 1) { return $null}

		$existingScanData = $this.GetLocalSubscriptionScanReport();
		[ComplianceStateTableEntity[]] $finalScanData = @()

		#merge subscription scan data
		[ComplianceStateTableEntity[]] $tempSubscriptionScanData = @()
		
		#by default add latest result 
		$tempSubscriptionScanData += $currentScanData | Where-Object{$_.PartitionKey -eq $this.SubscriptionContext.SubscriptionId}
		
		#add missing data from existing compliance
		#$tempSubscriptionScanData += $existingScanData | `
		#Where-Object{$_.PartitionKey -eq $this.SubscriptionContext.SubscriptionId -and $tempSubscriptionScanData.RowKey -inotcontains $_.RowKey}
		$finalScanData += $tempSubscriptionScanData
		# $currentScanData | ForEach-Object {
		# 	$currentScanResult = $_
		# 	try
		# 	{
		# 		if($currentScanResult.FeatureName -ne "AzSKCfg")
		# 		{
		# 			$filteredResource = $resources | Where-Object {$_.ResourceId -eq $currentScanResult.ResourceContext.ResourceId }

		# 			if(($filteredResource | Measure-Object).Count -gt 0)
		# 			{
		# 				$resource = $filteredResource
		# 				$resource.LastEventOn = [DateTime]::UtcNow

		# 				$matchedControlResults = $resource.ResourceScanResult | Where-Object { $_.ControlIntId -eq $currentScanResult.ControlItem.Id }
		# 				if((($matchedControlResults) | Measure-Object).Count -gt 0)
		# 				{
		# 					$_complianceResResult = $matchedControlResults
		# 					$svtResults = $this.ConvertScanResultToSnapshotResult($currentScanResult, $_complianceResResult, $false)
		# 					$resource.ResourceScanResult = $resource.ResourceScanResult | Where-Object { $_.ControlIntId -ne $_complianceResResult[0].ControlIntId }
		# 					$resource.ResourceScanResult += $svtResults
		# 				}
		# 				else
		# 				{
		# 					$resource.ResourceScanResult += $this.ConvertScanResultToSnapshotResult($currentScanResult, $null, $false)
		# 				}

		# 				$tmpResources = $resources | Where-Object {$_.ResourceId -ne $resource.ResourceId } 
		# 				$resources = @()
		# 				$resources += $tmpResources
		# 				$resources += $resource
		# 			}
		# 			else
		# 			{
		# 				$resource = [LSRResources]::New()
		# 				$resource.HashId = [Helpers]::ComputeHash($currentScanResult.ResourceContext.ResourceId)
		# 				$resource.ResourceId = $currentScanResult.ResourceContext.ResourceId
		# 				$resource.LastEventOn = [DateTime]::UtcNow
		# 				$resource.FirstScannedOn = [DateTime]::UtcNow
		# 				$resource.ResourceGroupName = $currentScanResult.ResourceContext.ResourceGroupName
		# 				$resource.ResourceName = $currentScanResult.ResourceContext.ResourceName

		# 				# ToDo: Need to confirm
		# 				# $resource.ResourceMetadata = [Helpers]::ConvertToJsonCustomCompressed($currentScanResult.ResourceContext.ResourceMetadata)
		# 				$resource.FeatureName = $currentScanResult.FeatureName
		# 				$resource.ResourceScanResult += $this.ConvertScanResultToSnapshotResult($currentScanResult, $null, $false)
		# 				$resources += $resource
		# 			}
		# 		}
		# 	}
		# 	catch
		# 	{
		# 		[EventBase]::PublishGenericException($_);
		# 	}
		# }

		
		# if($null -ne $resourceInventory)
		# {
		# 	$deletedResoures = @()
		# 	$resources | ForEach-Object {
		# 		$resource = $_
		# 		if(($resourceInventory | Where-Object { $_.ResourceId -eq $resource.ResourceId } | Measure-Object).Count -eq 0)
		# 		{
		# 			$deletedResoures += $resource.ResourceId
		# 		}
		# 	}
		# 		$resources = $resources | Where-Object { $deletedResoures -notcontains $_.ResourceId }
		# 	}

		# 	$resourceInventory | ForEach-Object {
		# 		$resource = $_
		# 		try {
		# 			if([Helpers]::CheckMember($resource, "ResourceId"))
		# 			{
		# 				if((($resources | Where-Object { $_.ResourceId -eq  $resource.ResourceId }) | Measure-Object).Count -eq 0)
		# 				{
		# 					$newResource = [LSRResources]::new()
		# 					$newResource.HashId = [Helpers]::ComputeHash($resource.ResourceId)
		# 					$newResource.ResourceId = $resource.ResourceId
		# 					$newResource.FeatureName = $supportedResourceTypes[$resource.ResourceType.ToLower()]
		# 					$newResource.ResourceGroupName = $resource.ResourceGroupName
		# 					$newResource.ResourceName = $resource.Name

		# 					$resources += $newResource	
		# 				}
		# 			}
		# 		}
		# 		catch
			# 	{
			# 		[EventBase]::PublishGenericException($_);
			# 	}
			# }
		#}
		
		# # Remove updated objects from existing compliance data
		# $resources | ForEach-Object {
		# 	$resource = $_
		# 	if($null -ne $subscription.ScanDetails.Resources -and $subscription.ScanDetails.Resources.Count -gt 0)
		# 	{
		# 		$subscription.ScanDetails.Resources = $subscription.ScanDetails.Resources | Where-Object { $_.ResourceId -ne $resource.ResourceId }
		# 	}
		# }
		
		# # append new updated objects
		# $subscription.ScanDetails.Resources += $resources
		
		# if($null -ne $complianceReport)
		# {
		# 	$complianceReport.Subscriptions = $complianceReport.Subscriptions | Where-Object { $_.SubscriptionId -ne $subscription.SubscriptionId }
		# }
		# else
		# {
		# 	$complianceReport = [LocalSubscriptionReport]::new()
		# }
		
		# $complianceReport.Subscriptions += $subscription;

		return $finalScanData
	}
	hidden [void] SetLocalSubscriptionScanReportV2([ComplianceStateTableEntity[]] $scanResultForStorage)
	{		
		try
		{
			# if($this.GetStorageHelperInstance().HaveWritePermissions -eq 0)
			# {
			# 	return;
			# }
			# $AzSKTemp = [Constants]::AzSKAppFolderPath + [Constants]::ComplianceReportPath;				
			# if(-not (Test-Path "$AzSKTemp"))
			# {
			# 	mkdir -Path "$AzSKTemp" -ErrorAction Stop | Out-Null
			# }
			# else
			# {
			# 	Remove-Item -Path "$AzSKTemp\*" -Force -Recurse 
			# }

		#	$fileName = "$AzSKTemp\" + $this.SubscriptionContext.SubscriptionId +".json"
			#$compressedFileName = "$AzSKTemp\" + [Constants]::ComplianceReportBlobName +".zip"
		#	$ContainerName = [Constants]::ComplianceReportContainerName;

		#	[Helpers]::ConvertToJsonCustomCompressed($scanResultForStorage) | Out-File $fileName -Force

			#compress file before store to storage

			#Compress-Archive -Path $fileName -CompressionLevel Optimal -DestinationPath $compressedFileName -Update

			#$fileInfos = @();
			#$fileInfos += [System.IO.FileInfo]::new($compressedFileName);
			$storageInstance = $this.GetStorageHelperInstance()
			$TableName = $this.ComplianceTableName
			$AccountName = $storageInstance.StorageAccountName
			$AccessKey = [Helpers]::GetStorageAccountAccessKey($storageInstance.ResourceGroupName,$AccountName) 
			$Uri="https://$AccountName.table.core.windows.net/`$batch"
			$boundary = "batch_$([guid]::NewGuid())"
			$Verb = "POST"
			$ContentMD5 = ""
			$ContentType = "multipart/mixed; boundary=$boundary"
			$Date = get-date -format r
			$CanonicalizedResource = "/$AccountName/`$batch"
			$SigningParts=@($Verb,$ContentMD5,$ContentType,$Date,$CanonicalizedResource)
			$StringToSign = [String]::Join("`n",$SigningParts)

			$KeyBytes = [System.Convert]::FromBase64String($AccessKey)
			$HMAC = New-Object System.Security.Cryptography.HMACSHA256
			$HMAC.Key = $KeyBytes
			$UnsignedBytes = [System.Text.Encoding]::UTF8.GetBytes($StringToSign)
			$KeyHash = $HMAC.ComputeHash($UnsignedBytes)
			$SignedString = [System.Convert]::ToBase64String($KeyHash)
			$sharedKey = $AccountName+":"+$SignedString
			$xmsdate = $Date
			$this.InsertEntitiesToTable($scanResultForStorage,$storageInstance.StorageAccountName,$this.ComplianceTableName,$Uri,$SharedKey,$xmsdate,$Boundary)
		}
		finally
		{
			#[Helpers]::CleanupLocalFolder([Constants]::AzSKAppFolderPath + [Constants]::ComplianceReportPath);
		}
    }
	hidden [void] StoreComplianceDataInUserSubscription([SVTEventContext[]] $currentScanResult)
	{
		$filteredResources = $null
		# ToDo: Resource inventory helper
		 if($this.ScanSource -eq [ScanSource]::Runbook) 
		 { 
			$resources = "" | Select-Object "SubscriptionId", "ResourceGroups"
			$resources.ResourceGroups = [System.Collections.ArrayList]::new()
			# ToDo: cache this properties as AzSKRoot.
			$resourcesFlat = Find-AzureRmResource
			$supportedResourceTypes = [SVTMapping]::GetSupportedResourceMap()
			# Not considering nested resources to reduce complexity
			$filteredResources = $resourcesFlat | Where-Object { $supportedResourceTypes.ContainsKey($_.ResourceType.ToLower()) }			
		 }
		 $convertedCurrentScanResult = $this.ConvertScanResultToSnapshotResultV2($currentScanResult)
		 $finalScanReport = $this.MergeSVTScanResultV2($convertedCurrentScanResult, $filteredResources)
		 $this.SetLocalSubscriptionScanReportV2($finalScanReport)
		 #$finalScanReport = $this.MergeSVTScanResult($svtEventContextResults, $filteredResources)
		 #$this.SetLocalSubscriptionScanReport($finalScanReport)
	}
}