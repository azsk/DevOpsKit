Set-StrictMode -Version Latest

class ComplianceReportHelper
{
	
	hidden [StorageHelper] $azskStorageInstance;
	hidden [int] $retryCount = 3;
	hidden [string] $subscriptionId;
    
    ComplianceReportHelper([string] $subId)
	{
		$this.subscriptionId = $subId;
		$this.CreateComplianceReportContainer();
	} 
	
	hidden [void] CreateComplianceReportContainer()
	{
		try {
			$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
			$azskStorageAccount = Find-AzureRmResource -ResourceNameContains $([Constants]::StorageAccountPreName) -ResourceGroupNameEquals $azskRGName -ResourceType 'Microsoft.Storage/storageAccounts'
			if($azskStorageAccount)
			{
				$this.azskStorageInstance = [StorageHelper]::new($this.subscriptionId, $azskRGName,$azskStorageAccount.Location, $azskStorageAccount.Name);
				$this.azskStorageInstance.CreateStorageContainerIfNotExists([Constants]::ComplianceReportContainerName);		
			}	
		}
		catch {
			#exception will be thrown if it fails to access or create the snapshot container
		}		
	}
    
    hidden [LocalSubscriptionReport] GetLocalSubscriptionScanReport()
	{
		[LocalSubscriptionReport] $storageReport = $null;
		try
		{
			if($this.azskStorageInstance.HaveWritePermissions -eq 0)
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

			$this.azskStorageInstance.DownloadFilesFromBlob($ContainerName, $complianceReportBlobName, $AzSKTemp, $true);
            $fileName = $AzSKTemp+"\"+$this.subscriptionId +".json";
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
		if($this.azskStorageInstance.HaveWritePermissions -eq 0)
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
			if($this.azskStorageInstance.HaveWritePermissions -eq 0)
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

			$fileName = "$AzSKTemp\" + $this.subscriptionId +".json"
			$compressedFileName = "$AzSKTemp\" + [Constants]::ComplianceReportBlobName +".zip"
			$ContainerName = [Constants]::ComplianceReportContainerName;

			[Helpers]::ConvertToJsonCustomCompressed($scanResultForStorage) | Out-File $fileName -Force

			#compress file before store to storage

			Compress-Archive -Path $fileName -CompressionLevel Optimal -DestinationPath $compressedFileName -Update

			$fileInfos = @();
			$fileInfos += [System.IO.FileInfo]::new($compressedFileName);
			$this.azskStorageInstance.UploadFilesToBlob($ContainerName, "", $fileInfos, $true);
		}
		finally
		{
			[Helpers]::CleanupLocalFolder([Constants]::AzSKAppFolderPath + [Constants]::ComplianceReportPath);
		}
    }		

	hidden [LocalSubscriptionReport] MergeSVTScanResult($currentScanResults, $resourceInventory, $scanSource, $scannerVersion, $scanKind)
	{
		if($currentScanResults.Count -lt 1) { return $null}

		$SVTEventContextFirst = $currentScanResults[0]

		$complianceReport = $this.GetLocalSubscriptionScanReport();
		$subscription = [LSRSubscription]::new()
		[LSRResources[]] $resources = @()

		if($null -ne $complianceReport -and (($complianceReport.Subscriptions | Where-Object { $_.SubscriptionId -eq $this.subscriptionId }) | Measure-Object).Count -gt 0)
		{
			$subscription = $complianceReport.Subscriptions | Where-Object { $_.SubscriptionId -eq $this.subscriptionId }
		}
		else
		{
			$subscription.SubscriptionId = $this.subscriptionId
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
						if((($matchedControlResults) | Measure-Object).Count -gt0)
						{
							$_complianceSubResult = $matchedControlResults
							$svtResults = $this.ConvertScanResultToSnapshotResult($currentScanResult, $scanSource, $scannerVersion, $scanKind, $_complianceSubResult, $true)

							$subscription.ScanDetails.SubscriptionScanResult = $subscription.ScanDetails.SubscriptionScanResult | Where-Object {$_.ControlIntId -ne $currentScanResult.ControlItem.Id }
							$subscription.ScanDetails.SubscriptionScanResult += $svtResults
						}
						else
						{
							$subscription.ScanDetails.SubscriptionScanResult += $this.ConvertScanResultToSnapshotResult($currentScanResult, $scanSource, $scannerVersion, $scanKind, $null, $true)
						}
					}
					else
					{
						$subscription.ScanDetails.SubscriptionScanResult += $this.ConvertScanResultToSnapshotResult($currentScanResult, $scanSource, $scannerVersion, $scanKind, $null, $true)
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
							$svtResults = $this.ConvertScanResultToSnapshotResult($currentScanResult, $scanSource, $scannerVersion, $scanKind, $_complianceResResult, $false)
							$resource.ResourceScanResult = $resource.ResourceScanResult | Where-Object { $_.ControlIntId -ne $_complianceResResult[0].ControlIntId }
							$resource.ResourceScanResult += $svtResults
						}
						else
						{
							$resource.ResourceScanResult += $this.ConvertScanResultToSnapshotResult($currentScanResult, $scanSource, $scannerVersion, $scanKind, $null, $false)
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
						$resource.ResourceScanResult += $this.ConvertScanResultToSnapshotResult($currentScanResult, $scanSource, $scannerVersion, $scanKind, $null, $false)
						$resources += $resource
					}
				}
			}
			catch
			{
				[EventBase]::PublishGenericCustomMessage(($currentScanResult | Format-List | Out-String), [MessageType]::Default)
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
		# Resources obj consist of compliance snapshot data.
		

		if($subscription.ScanDetails.Resources.Count -gt 0)
		{
			$resources | ForEach-Object {
				$resource = $_
				$subscription.ScanDetails.Resources = $subscription.ScanDetails.Resources | Where-Object { $_.ResourceId -ne $resource.ResourceId }
			}
		}
		
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
	
	hidden [LSRControlResultBase[]] ConvertScanResultToSnapshotResult($svtResult, $scanSource, $scannerVersion, $scanKind, $oldResult, $isSubscriptionScan)
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
				$resourceScanResult.ScanSource = $scanSource
				$resourceScanResult.ScannerVersion = $scannerVersion
				$resourceScanResult.ControlVersion = $scannerVersion
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
				$resourceScanResult.ScanKind = $scanKind
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
}