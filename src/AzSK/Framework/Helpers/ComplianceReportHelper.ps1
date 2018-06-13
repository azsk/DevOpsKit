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
            $AzSKTemp = [Constants]::AzSKAppFolderPath + "\Temp\StorageReport";
			
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
    
    hidden [LocalSubscriptionReport] MergeScanReport([LSRSubscription] $scanReport)
    {
        $complianceReport = $this.GetLocalSubscriptionScanReport();

        if([Helpers]::CheckMember($complianceReport,"Subscriptions") -and (($complianceReport.Subscriptions | Where-Object { $_.SubscriptionId -eq $scanReport.SubscriptionId }) | Measure-Object).Count -gt 0)
        {
            $_oldScanRerportSubscription = $complianceReport.Subscriptions | Where-Object { $_.SubscriptionId -eq $scanReport.SubscriptionId }
            if([Helpers]::CheckMember($scanReport,"ScanDetails") -and [Helpers]::CheckMember($scanReport.ScanDetails,"SubscriptionScanResult") `
                    -and ($scanReport.ScanDetails.SubscriptionScanResult | Measure-Object).Count -gt 0)
            {
                if([Helpers]::CheckMember($_oldScanRerportSubscription,"ScanDetails") -and [Helpers]::CheckMember($_oldScanRerportSubscription.ScanDetails,"SubscriptionScanResult") `
                        -and ($_oldScanRerportSubscription.ScanDetails.SubscriptionScanResult | Measure-Object).Count -gt 0)
                {
                    $scanReport.ScanDetails.SubscriptionScanResult | ForEach-Object {
                        $subcriptionScanResult = [LSRSubscriptionControlResult] $_
                        
                        if((($_oldScanRerportSubscription.ScanDetails.SubscriptionScanResult | Where-Object { $subcriptionScanResult.ControlIntId -eq $_.ControlIntId }) | Measure-Object).Count -gt0)
                        {
                            $_complianceSubResult = $_oldScanRerportSubscription.ScanDetails.SubscriptionScanResult | Where-Object { $subcriptionScanResult.ControlIntId -eq $_.ControlIntId }
                            $_complianceSubResult.ScanKind = $subcriptionScanResult.ScanKind
                            $_complianceSubResult.ControlIntId = $subcriptionScanResult.ControlIntId
                            $_complianceSubResult.ControlUpdatedOn = $subcriptionScanResult.ControlUpdatedOn
                            $_complianceSubResult.ControlSeverity = $subcriptionScanResult.ControlSeverity

                            if($subcriptionScanResult.AttestationStatus -ne [AttestationStatus]::None -and ($subcriptionScanResult.AttestationStatus -ne $_complianceSubResult.AttestationStatus -or $subcriptionScanResult.Justification -ne $_complianceSubResult.Justification))
                            {
                                $_complianceSubResult.AttestationCounter = $_complianceSubResult.AttestationCounter + 1
                            }
                            if($_complianceSubResult.VerificationResult -ne $subcriptionScanResult.VerificationResult)
                            {
                                $_complianceSubResult.LastResultTransitionOn = [System.DateTime]::UtcNow
                            }

                            $_complianceSubResult.PreviousVerificationResult = $_complianceSubResult.ActualVerificationResult
                            $_complianceSubResult.ActualVerificationResult = $subcriptionScanResult.ActualVerificationResult
                            $_complianceSubResult.AttestationStatus = $subcriptionScanResult.AttestationStatus
                            $_complianceSubResult.VerificationResult = $subcriptionScanResult.VerificationResult
                            $_complianceSubResult.AttestedBy = $subcriptionScanResult.AttestedBy
                            $_complianceSubResult.AttestedDate = $subcriptionScanResult.AttestedDate
                            $_complianceSubResult.Justification = $subcriptionScanResult.Justification
                            $_complianceSubResult.AttestationData = $subcriptionScanResult.AttestationData
                            $_complianceSubResult.LastScannedOn = [System.DateTime]::UtcNow

                            if($_complianceSubResult.FirstScannedOn -eq [Constants]::AzSKDefaultDateTime)
                            {
                                $_complianceSubResult.FirstScannedOn = [System.DateTime]::UtcNow
                            }
                            
                            if($_complianceSubResult.FirstFailedOn -eq [Constants]::AzSKDefaultDateTime -and $subcriptionScanResult.ActualVerificationResult -eq [VerificationResult]::Failed)
                            {
                                $_complianceSubResult.FirstFailedOn = [System.DateTime]::UtcNow
                            }

                            if($_complianceSubResult.FirstAttestedOn -eq [Constants]::AzSKDefaultDateTime -and $subcriptionScanResult.AttestationStatus -ne [AttestationStatus]::None)
                            {
                                $_complianceSubResult.FirstAttestedOn = [System.DateTime]::UtcNow
                            }

                            $_complianceSubResult.ScannedBy = $subcriptionScanResult.ScannedBy
                            $_complianceSubResult.ScanSource = $subcriptionScanResult.ScanSource
                            $_complianceSubResult.ScannerModuleName = $subcriptionScanResult.ScannerModuleName
                            $_complianceSubResult.ScannerVersion = $subcriptionScanResult.ScannerVersion
                            $_complianceSubResult.ControlVersion = $subcriptionScanResult.ControlVersion
                            $_complianceSubResult.IsLatestPSModule = $subcriptionScanResult.IsLatestPSModule
                            $_complianceSubResult.HasRequiredPermissions = $subcriptionScanResult.HasRequiredPermissions
                            $_complianceSubResult.HasAttestationWritePermissions = $subcriptionScanResult.HasAttestationWritePermissions
                            $_complianceSubResult.HasAttestationReadPermissions = $subcriptionScanResult.HasAttestationReadPermissions
                            $_complianceSubResult.UserComments = $subcriptionScanResult.UserComments
                            $_complianceSubResult.Metadata = $subcriptionScanResult.Metadata
							$_complianceSubResult.IsBaselineControl = $subcriptionScanResult.IsBaselineControl
							$_complianceSubResult.HasOwnerAccessTag = $subcriptionScanResult.HasOwnerAccessTag
                            
							$_oldScanRerportSubscription.ScanDetails.SubscriptionScanResult = $_oldScanRerportSubscription.ScanDetails.SubscriptionScanResult | Where-Object { $subcriptionScanResult.ControlIntId -ne $_.ControlIntId }
                            $_oldScanRerportSubscription.ScanDetails.SubscriptionScanResult += $_complianceSubResult
                        }
                    }
                }
                else
                {
                    $_oldScanRerportSubscription.ScanDetails.SubscriptionScanResult += $scanReport.ScanDetails.SubscriptionScanResult;
                }
            }

            if([Helpers]::CheckMember($scanReport,"ScanDetails")  -and [Helpers]::CheckMember($scanReport.ScanDetails,"Resources") `
                -and ($scanReport.ScanDetails.Resources | Measure-Object).Count -gt 0)
            {
                if([Helpers]::CheckMember($_oldScanRerportSubscription,"ScanDetails") -and [Helpers]::CheckMember($_oldScanRerportSubscription.ScanDetails,"Resources") `
                         -and ($_oldScanRerportSubscription.ScanDetails.Resources | Measure-Object).Count -gt 0)
                {
                    $scanReport.ScanDetails.Resources | Foreach-Object {
                        $resource = [LSRResources] $_

                        if([Helpers]::CheckMember($_oldScanRerportSubscription.ScanDetails,"Resources") -and (($_oldScanRerportSubscription.ScanDetails.Resources | Where-Object { $resource.HashId -contains $_.HashId }) | Measure-Object).Count -gt0)
                        {
                            $_ORresource = $_oldScanRerportSubscription.ScanDetails.Resources | Where-Object { $resource.HashId -contains $_.HashId }
                            $_ORresource.LastEventOn = [DateTime]::UtcNow

                            $resource.ResourceScanResult | ForEach-Object {

                                $newControlResult = [LSRResourceScanResult] $_
                                if([Helpers]::CheckMember($_ORresource,"ResourceScanResult") -and (($_ORresource.ResourceScanResult | Where-Object { $_.ControlIntId -eq $newControlResult.ControlIntId -and $_.ChildResourceName -eq $newControlResult.ChildResourceName }) | Measure-Object).Count -eq 0)
                                {
                                    $_ORresource.ResourceScanResult += $newControlResult
                                }
                                else
                                {
                                    $_complianceResResult = $_ORresource.ResourceScanResult | Where-Object { $_.ControlIntId -eq $newControlResult.ControlIntId -and $_.ChildResourceName -eq $newControlResult.ChildResourceName }

                                    $_complianceResResult.ScanKind = $newControlResult.ScanKind
                                    $_complianceResResult.ControlIntId = $newControlResult.ControlIntId
                                    $_complianceResResult.ControlUpdatedOn = $newControlResult.ControlUpdatedOn
                                    $_complianceResResult.ControlSeverity = $newControlResult.ControlSeverity

                                    if($newControlResult.AttestationStatus -ne [AttestationStatus]::None -and($newControlResult.AttestationStatus -ne $_complianceResResult.AttestationStatus -or $newControlResult.Justification -ne $_complianceResResult.Justification))
                                    {
                                        $_complianceResResult.AttestationCounter = $_complianceResResult.AttestationCounter + 1 
                                    }
                                    if($_complianceResResult.VerificationResult -ne $newControlResult.VerificationResult)
                                    {
                                        $_complianceResResult.LastResultTransitionOn = [System.DateTime]::UtcNow
                                    }

                                    $_complianceResResult.PreviousVerificationResult = $_complianceResResult.VerificationResult
                                    $_complianceResResult.ActualVerificationResult = $newControlResult.ActualVerificationResult
                                    $_complianceResResult.AttestationStatus = $newControlResult.AttestationStatus
                                    $_complianceResResult.VerificationResult = $newControlResult.VerificationResult
                                    $_complianceResResult.AttestedBy = $newControlResult.AttestedBy
                                    $_complianceResResult.AttestedDate = $newControlResult.AttestedDate
                                    $_complianceResResult.Justification = $newControlResult.Justification
                                    $_complianceResResult.AttestationData = $newControlResult.AttestationData
                                    $_complianceResResult.IsBaselineControl = $newControlResult.IsBaselineControl
                                    $_complianceResResult.LastScannedOn = [System.DateTime]::UtcNow

                                    if($_complianceResResult.FirstScannedOn -eq [Constants]::AzSKDefaultDateTime)
                                    {
                                        $_complianceResResult.FirstScannedOn = [System.DateTime]::UtcNow
                                    }
                                    
                                    if($_complianceResResult.FirstFailedOn -eq [Constants]::AzSKDefaultDateTime -and $newControlResult.ActualVerificationResult -eq [VerificationResult]::Failed)
                                    {
                                        $_complianceResResult.FirstFailedOn = [System.DateTime]::UtcNow
                                    }

                                    if($_complianceResResult.FirstAttestedOn -eq [Constants]::AzSKDefaultDateTime -and $newControlResult.AttestationStatus -ne [AttestationStatus]::None)
                                    {
                                        $_complianceResResult.FirstAttestedOn = [System.DateTime]::UtcNow
                                    }
                                    
                                    $_complianceResResult.ScannedBy = $newControlResult.ScannedBy
                                    
                                    $_complianceResResult.ScanSource = $newControlResult.ScanSource
                                    $_complianceResResult.ScannerModuleName = $newControlResult.ScannerModuleName
                                    $_complianceResResult.ScannerVersion = $newControlResult.ScannerVersion
                                    $_complianceResResult.ControlVersion = $newControlResult.ControlVersion
                                    $_complianceResResult.IsLatestPSModule = $newControlResult.IsLatestPSModule
                                    $_complianceResResult.HasRequiredPermissions = $newControlResult.HasRequiredPermissions
                                    $_complianceResResult.HasAttestationWritePermissions = $newControlResult.HasAttestationWritePermissions
                                    $_complianceResResult.HasAttestationReadPermissions = $newControlResult.HasAttestationReadPermissions
                                    $_complianceResResult.UserComments = $newControlResult.UserComments
                                    $_complianceResResult.Metadata = $newControlResult.Metadata
									$_complianceResResult.HasOwnerAccessTag = $newControlResult.HasOwnerAccessTag

                                    $_ORresource.ResourceScanResult = $_ORresource.ResourceScanResult | Where-Object { $_.ControlIntId -ne $_complianceResResult.ControlIntId -or  $_.ChildResourceName -ne  $_complianceResResult.ChildResourceName }
                                    $_ORresource.ResourceScanResult += $_complianceResResult
                                }
                            }
                        }
                        else
                        {
                            $_oldScanRerportSubscription.ScanDetails.Resources += $resource
                        }
                    }
                }
                else
                {
                    $_oldScanRerportSubscription.ScanDetails.Resources += $scanReport.ScanDetails.Resources;
                }
            }

            $complianceReport.Subscriptions = $complianceReport.Subscriptions | Where-Object { $_.SubscriptionId -ne $scanReport.SubscriptionId }
            $complianceReport.Subscriptions += $_oldScanRerportSubscription
        }
        else
        {
            if([Helpers]::CheckMember($complianceReport,"Subscriptions"))
            {
                $complianceReport.Subscriptions += $scanReport;
            }
            else
            {
                $complianceReport = [LocalSubscriptionReport]::new()
                $complianceReport.Subscriptions += $scanReport;
            }
            
        }

        return $complianceReport
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
						if((($subscription.ScanDetails.SubscriptionScanResult | Where-Object { $currentScanResult.ControlItem.Id -eq $_.ControlIntId }) | Measure-Object).Count -gt0)
						{
							$_complianceSubResult = $subscription.ScanDetails.SubscriptionScanResult | Where-Object { $currentScanResult.ControlItem.Id -eq $_.ControlIntId }
							$svtResults = $this.ConvertScanResultToSnapshotResult($currentScanResult, $scanSource, $scannerVersion, $scanKind, $_complianceSubResult, $true)

							$subscription.ScanDetails.SusbscriptionScanResult = $subscription.ScanDetails.SubscriptionScanResult | Where-Object {$_.ControlIntId -ne $currentScanResult.ControlItem.Id }
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
				else
				{

					if((($resources | Where-Object {$_.ResourceId -eq $currentScanResult.ResourceContext.ResourceId }) | Measure-Object).Count -gt 0)
					{
						$resource = $resources | Where-Object {$_.ResourceId -eq $currentScanResult.ResourceContext.ResourceId }
						$resource.LastEventOn = [DateTime]::UtcNow

						if((($resource.ResourceScanResult | Where-Object { $_.ControlIntId -eq $currentScanResult.ControlItem.Id }) | Measure-Object).Count -gt 0)
						{
							$_complianceResResult = $resource.ResourceScanResult | Where-Object { $_.ControlIntId -eq $currentScanResult.ControlItem.Id }
							$svtResults = $this.ConvertScanResultToSnapshotResult($currentScanResult, $scanSource, $scannerVersion, $scanKind, $_complianceResResult, $false)
							$resource.ResourceScanResult = $resource.ResourceScanResult | Where-Object { $_.ControlIntId -ne $_complianceResResult.ControlIntId }
							$resource.ResourceScanResult += $svtResults
						}
						else
						{
							$resource.ResourceScanResult += $this.ConvertScanResultToSnapshotResult($currentScanResult, $scanSource, $scannerVersion, $scanKind, $null, $false)
						}

						$resources = ($resources | Where-Object {$_.ResourceId -ne $resource.ResourceId } | Measure-Object)
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

		# Resources obj consist of compliance snapshot data.
		$deletedResoures = @()
		$resources | ForEach-Object {
			$resource = $_
			if(($resourceInventory | Where-Object { $_.ResourceId -eq $resource.ResourceId } | Measure-Object).Count -eq 0)
			{
				$deletedResoures += $resource.ResourceId
			}
		}

		$resources = $resources | Where-Object {  $deletedResoures -notcontains $_.ResourceId }

		$resourceInventory | ForEach-Object {
			$resource = $_
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
		#if($isSubscriptionScan)
		#{
		#	[LSRSubscriptionControlResult[]] $scanResults = @();	
		#}
		#else
		#{
		#	[LSRResourceScanResult[]] $scanResults = @();	
		#}

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
						$resourceScanResult = $oldResult | Where-Object { $_.ChildResourceName -eq $currentResult.ChildResourceName -or [string]::IsNullOrEmpty($currentResult.ChildResourceName) }
					}
					else
					{
						$resourceScanResult = [LSRResourceScanResult]::new()
					}
					
				}

				if($currentResult.AttestationStatus -ne [AttestationStatus]::None -and($currentResult.AttestationStatus -ne $resourceScanResult.AttestationStatus -or $currentResult.Justification -ne $resourceScanResult.Justification))
				{
					$resourceScanResult.AttestationCounter = $resourceScanResult.AttestationCounter + 1 
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

				if($resourceScanResult.FirstAttestedOn -eq [Constants]::AzSKDefaultDateTime -and $currentResult.AttestationStatus -ne [AttestationStatus]::None)
				{
					$resourceScanResult.FirstAttestedOn = [System.DateTime]::UtcNow
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
				if($resourceScanResult.AttestationStatus -ne [AttestationStatus]::None)
				{
					$resourceScanResult.AttestedBy =  $currentResult.StateManagement.AttestedStateData.AttestedBy
					$resourceScanResult.AttestedDate = $currentResult.StateManagement.AttestedStateData.AttestedDate 
					$resourceScanResult.Justification = $currentResult.StateManagement.AttestedStateData.Justification
					$resourceScanResult.AttestationData = [Helpers]::ConvertToJsonCustomCompressed($currentResult.StateManagement.AttestedStateData.DataObject)	
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