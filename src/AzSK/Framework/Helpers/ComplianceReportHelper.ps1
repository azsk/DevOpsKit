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
				$this.azskStorageInstance.CreateStorageContainerIfNotExists([Constants]::StorageReportContainerName);		
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
            $storageReportBlobName = [Constants]::StorageReportBlobName + ".zip"
            
            $ContainerName = [Constants]::StorageReportContainerName
            $loopValue = $this.retryCount;
            $AzSKTemp = [Constants]::AzSKAppFolderPath + "\Temp\StorageReport";
			
			if(-not (Test-Path -Path $AzSKTemp))
            {
                mkdir -Path $AzSKTemp -Force
            }

			$this.azskStorageInstance.DownloadFilesFromBlob($ContainerName, $storageReportBlobName, $AzSKTemp, $true);
            $fileName = $AzSKTemp+"\"+$this.subscriptionId +".json";
			$StorageReportJson = $null;
			try
			{
				# ToDo: check for the file found Test-File zip + json
				# ToDo: Also add check to to turn off based on flag
				# extract file from zip
				$compressedFileName = $AzSKTemp+"\"+[Constants]::StorageReportBlobName +".zip"
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
			$this.CleanTempFolder()
		}
    }

	# ToDo: Save the file name as subid.json
    hidden [LSRSubscription] GetLocalSubscriptionScanReport([string] $subscriptionId)
    {
		if($this.azskStorageInstance.HaveWritePermissions -eq 0)
		{
			return $null;
		}
        $fullScanResult = $this.GetLocalSubscriptionScanReport();
        if($null -ne $fullScanResult -and ($fullScanResult.Subscriptions | Measure-Object ).Count -gt 0)
        {
            return $fullScanResult.Subscriptions | Where-Object { $_.SubscriptionId -eq $subscriptionId }
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
			$AzSKTemp = [Constants]::AzSKAppFolderPath + "\Temp\StorageReport";				
			if(-not (Test-Path "$AzSKTemp"))
			{
				mkdir -Path "$AzSKTemp" -ErrorAction Stop | Out-Null
			}
			else
			{
				Remove-Item -Path "$AzSKTemp\*" -Force -Recurse 
			}

			$fileName = "$AzSKTemp\" + [Constants]::StorageReportBlobName +".json"
			$compressedFileName = "$AzSKTemp\" + [Constants]::StorageReportBlobName +".zip"

			$StorageAccount = $this.AzSKStorageAccount;						
			$containerObject = $this.AzSKStorageContainer
			$ContainerName = ""
			if($null -ne $this.AzSKStorageContainer)
			{
				$ContainerName = $this.AzSKStorageContainer.Name
			}

			[Helpers]::ConvertToJsonCustomCompressed($scanResultForStorage) | Out-File $fileName -Force

			#compress file before store to storage
			Compress-Archive -Path $fileName -CompressionLevel Optimal -DestinationPath $compressedFileName -Update

			$loopValue = $this.retryCount;
			while($loopValue -gt 0)
			{
				$loopValue = $loopValue - 1;
				try
				{
					Set-AzureStorageBlobContent -File $compressedFileName -Container $ContainerName -BlobType Block -Context $StorageAccount.Context -Force -ErrorAction Stop
					$loopValue = 0;
				}
				catch
				{
					#eat this exception and retry
				}
			}
		}
		finally
		{
			$this.CleanTempFolder();
		}
    }
    
    hidden [void] CleanTempFolder()
	{
		# ToDo: handle error, try catch + Error action continue
		# ToDo: Temp/Storage constants
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
            
			if($scanResult.IsLatestPSModule -and $serviceControlResult.HasRequiredAccess -and $scanResult.HasAttestationReadPermissions)
			{
				$subscriptionScanResult = [LSRSubscriptionControlResult]::new()
				$subscriptionScanResult.ScannedBy = [Helpers]::GetCurrentRMContext().Account
				$subscriptionScanResult.ScanSource = $scanResult.Source
				$subscriptionScanResult.ScannerVersion = $scanResult.ScannerVersion 
				$subscriptionScanResult.ControlVersion = $scanResult.ControlVersion
				$subscriptionScanResult.ControlId = $serviceControlResult.ControlId 
				$subscriptionScanResult.ControlIntId = $serviceControlResult.ControlIntId 
				$subscriptionScanResult.ControlSeverity = $serviceControlResult.ControlSeverity 
				$subscriptionScanResult.ActualVerificationResult = $serviceControlResult.ActualVerificationResult 
				$subscriptionScanResult.AttestedBy =  $serviceControlResult.AttestedBy 
				$subscriptionScanResult.AttestedDate = $serviceControlResult.AttestedDate
				$subscriptionScanResult.Justification = $serviceControlResult.Justification
				$subscriptionScanResult.AttestationStatus = $serviceControlResult.AttestationStatus
				$subscriptionScanResult.AttestationData = $serviceControlResult.AttestedState
				$subscriptionScanResult.VerificationResult = $serviceControlResult.VerificationResult
				$subscriptionScanResult.ScanKind = $scanResult.ScanKind
				$subscriptionScanResult.ScannerModuleName = [Constants]::AzSKModuleName
				$subscriptionScanResult.IsLatestPSModule = $scanResult.IsLatestPSModule
				$subscriptionScanResult.HasRequiredPermissions = $serviceControlResult.HasRequiredAccess
				$subscriptionScanResult.HasAttestationWritePermissions = $scanResult.HasAttestationWritePermissions
				$subscriptionScanResult.HasAttestationReadPermissions = $scanResult.HasAttestationReadPermissions
				$subscriptionScanResult.UserComments = $serviceControlResult.UserComments
				$subscriptionScanResult.IsBaselineControl = $serviceControlResult.IsBaselineControl
				$subscriptionScanResult.HasOwnerAccessTag = $serviceControlResult.HasOwnerAccessTag

				if($subscriptionScanResult.ActualVerificationResult -ne [VerificationResult]::Passed)
				{
					$subscriptionScanResult.FirstFailedOn = [DateTime]::UtcNow
				}
				if($subscriptionScanResult.AttestationStatus -ne [AttestationStatus]::None)
				{
					$subscriptionScanResult.FirstAttestedOn = [DateTime]::UtcNow
					$subscriptionScanResult.AttestationCounter = 1
				}
				$subscriptionScanResult.FirstScannedOn = [DateTime]::UtcNow
				$subscriptionScanResult.LastResultTransitionOn = [DateTime]::UtcNow
				$subscriptionScanResult.LastScannedOn = [DateTime]::UtcNow
				$scanDetails.SubscriptionScanResult += $subscriptionScanResult
			}
        }
        $storageReport.ScanDetails = $scanDetails;

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
        $resources.FeatureName = $scanResult.Feature
        $resources.ResourceGroupName = $scanResult.ResourceGroup
        $resources.ResourceName = $scanResult.ResourceName
        $resources.FirstScannedOn = [DateTime]::UtcNow
        $resources.LastEventOn = [DateTime]::UtcNow

		# ToDo: Need to confirm
        #$resources.ResourceMetadata = $scanResult.Metadata

        $scanResult.ControlResults | ForEach-Object {
                $serviceControlResult = $_
				if($scanResult.IsLatestPSModule -and $serviceControlResult.HasRequiredAccess -and $scanResult.HasAttestationReadPermissions)
				{
					$resourceScanResult = [LSRResourceScanResult]::new()
					$resourceScanResult.ScannedBy = [Helpers]::GetCurrentRMContext().Account
					$resourceScanResult.ScanSource = $scanResult.Source
					$resourceScanResult.ScannerVersion = $scanResult.ScannerVersion 
					$resourceScanResult.ControlVersion = $scanResult.ControlVersion
					$resourceScanResult.ChildResourceName = $serviceControlResult.NestedResourceName 
					$resourceScanResult.ControlId = $serviceControlResult.ControlId 
					$resourceScanResult.ControlIntId = $serviceControlResult.ControlIntId 
					$resourceScanResult.ControlSeverity = $serviceControlResult.ControlSeverity 
					$resourceScanResult.ActualVerificationResult = $serviceControlResult.ActualVerificationResult 
					$resourceScanResult.AttestedBy =  $serviceControlResult.AttestedBy 
					$resourceScanResult.AttestedDate = $serviceControlResult.AttestedDate
					$resourceScanResult.Justification = $serviceControlResult.Justification
					$resourceScanResult.AttestationStatus = $serviceControlResult.AttestationStatus
					$resourceScanResult.AttestationData = $serviceControlResult.AttestedState
					$resourceScanResult.VerificationResult = $serviceControlResult.VerificationResult
					$resourceScanResult.ScanKind = $scanResult.ScanKind
					$resourceScanResult.ScannerModuleName = [Constants]::AzSKModuleName
					$resourceScanResult.IsLatestPSModule = $scanResult.IsLatestPSModule
					$resourceScanResult.HasRequiredPermissions = $serviceControlResult.HasRequiredAccess
					$resourceScanResult.HasAttestationWritePermissions = $scanResult.HasAttestationWritePermissions
					$resourceScanResult.HasAttestationReadPermissions = $scanResult.HasAttestationReadPermissions
					$resourceScanResult.UserComments = $serviceControlResult.UserComments
					$resourceScanResult.IsBaselineControl = $serviceControlResult.IsBaselineControl
					$resourceScanResult.HasOwnerAccessTag = $serviceControlResult.HasOwnerAccessTag

					if($resourceScanResult.ActualVerificationResult -ne [VerificationResult]::Passed)
					{
						$resourceScanResult.FirstFailedOn = [DateTime]::UtcNow
					}
					if($resourceScanResult.AttestationStatus -ne [AttestationStatus]::None)
					{
						$resourceScanResult.FirstAttestedOn = [DateTime]::UtcNow
						$resourceScanResult.AttestationCounter = 1
					}

					$resourceScanResult.FirstScannedOn = [DateTime]::UtcNow
					$resourceScanResult.LastResultTransitionOn = [DateTime]::UtcNow
					$resourceScanResult.LastScannedOn = [DateTime]::UtcNow

					# ToDo: Need to confirm
					#$resourceScanResult.Metadata = $scanResult.Metadata

					$resources.ResourceScanResult += $resourceScanResult
				}

                
        }

        $scanDetails = [LSRScanDetails]::new()
        $scanDetails.Resources += $resources
        $storageReport.ScanDetails = $scanDetails;

        return $storageReport;
    }

    hidden [LocalSubscriptionReport] MergeScanReport([LSRSubscription] $scanReport)
    {
        $_oldScanReport = $this.GetLocalSubscriptionScanReport();

        if([Helpers]::CheckMember($_oldScanReport,"Subscriptions") -and (($_oldScanReport.Subscriptions | Where-Object { $_.SubscriptionId -eq $scanReport.SubscriptionId }) | Measure-Object).Count -gt 0)
        {
            $_oldScanRerportSubscription = $_oldScanReport.Subscriptions | Where-Object { $_.SubscriptionId -eq $scanReport.SubscriptionId }
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
                            $_ORsubcriptionScanResult = $_oldScanRerportSubscription.ScanDetails.SubscriptionScanResult | Where-Object { $subcriptionScanResult.ControlIntId -eq $_.ControlIntId }
                            $_ORsubcriptionScanResult.ScanKind = $subcriptionScanResult.ScanKind
                            $_ORsubcriptionScanResult.ControlIntId = $subcriptionScanResult.ControlIntId
                            $_ORsubcriptionScanResult.ControlUpdatedOn = $subcriptionScanResult.ControlUpdatedOn
                            $_ORsubcriptionScanResult.ControlSeverity = $subcriptionScanResult.ControlSeverity

                            if($subcriptionScanResult.AttestationStatus -ne [AttestationStatus]::None -and ($subcriptionScanResult.AttestationStatus -ne $_ORsubcriptionScanResult.AttestationStatus -or $subcriptionScanResult.Justification -ne $_ORsubcriptionScanResult.Justification))
                            {
                                $_ORsubcriptionScanResult.AttestationCounter = $_ORsubcriptionScanResult.AttestationCounter + 1
                            }
                            if($_ORsubcriptionScanResult.VerificationResult -ne $subcriptionScanResult.VerificationResult)
                            {
                                $_ORsubcriptionScanResult.LastResultTransitionOn = [System.DateTime]::UtcNow
                            }

                            $_ORsubcriptionScanResult.PreviousVerificationResult = $_ORsubcriptionScanResult.ActualVerificationResult
                            $_ORsubcriptionScanResult.ActualVerificationResult = $subcriptionScanResult.ActualVerificationResult
                            $_ORsubcriptionScanResult.AttestationStatus = $subcriptionScanResult.AttestationStatus
                            $_ORsubcriptionScanResult.VerificationResult = $subcriptionScanResult.VerificationResult
                            $_ORsubcriptionScanResult.AttestedBy = $subcriptionScanResult.AttestedBy
                            $_ORsubcriptionScanResult.AttestedDate = $subcriptionScanResult.AttestedDate
                            $_ORsubcriptionScanResult.Justification = $subcriptionScanResult.Justification
                            $_ORsubcriptionScanResult.AttestationData = $subcriptionScanResult.AttestationData
                            $_ORsubcriptionScanResult.LastScannedOn = [System.DateTime]::UtcNow

                            if($_ORsubcriptionScanResult.FirstScannedOn -eq [Constants]::AzSKDefaultDateTime)
                            {
                                $_ORsubcriptionScanResult.FirstScannedOn = [System.DateTime]::UtcNow
                            }
                            
                            if($_ORsubcriptionScanResult.FirstFailedOn -eq [Constants]::AzSKDefaultDateTime -and $subcriptionScanResult.ActualVerificationResult -eq [VerificationResult]::Failed)
                            {
                                $_ORsubcriptionScanResult.FirstFailedOn = [System.DateTime]::UtcNow
                            }

                            if($_ORsubcriptionScanResult.FirstAttestedOn -eq [Constants]::AzSKDefaultDateTime -and $subcriptionScanResult.AttestationStatus -ne [AttestationStatus]::None)
                            {
                                $_ORsubcriptionScanResult.FirstAttestedOn = [System.DateTime]::UtcNow
                            }

                            $_ORsubcriptionScanResult.ScannedBy = $subcriptionScanResult.ScannedBy
                            $_ORsubcriptionScanResult.ScanSource = $subcriptionScanResult.ScanSource
                            $_ORsubcriptionScanResult.ScannerModuleName = $subcriptionScanResult.ScannerModuleName
                            $_ORsubcriptionScanResult.ScannerVersion = $subcriptionScanResult.ScannerVersion
                            $_ORsubcriptionScanResult.ControlVersion = $subcriptionScanResult.ControlVersion
                            $_ORsubcriptionScanResult.IsLatestPSModule = $subcriptionScanResult.IsLatestPSModule
                            $_ORsubcriptionScanResult.HasRequiredPermissions = $subcriptionScanResult.HasRequiredPermissions
                            $_ORsubcriptionScanResult.HasAttestationWritePermissions = $subcriptionScanResult.HasAttestationWritePermissions
                            $_ORsubcriptionScanResult.HasAttestationReadPermissions = $subcriptionScanResult.HasAttestationReadPermissions
                            $_ORsubcriptionScanResult.UserComments = $subcriptionScanResult.UserComments
                            $_ORsubcriptionScanResult.Metadata = $subcriptionScanResult.Metadata
							$_ORsubcriptionScanResult.IsBaselineControl = $subcriptionScanResult.IsBaselineControl
							$_ORsubcriptionScanResult.HasOwnerAccessTag = $subcriptionScanResult.HasOwnerAccessTag
                            
							$_oldScanRerportSubscription.ScanDetails.SubscriptionScanResult = $_oldScanRerportSubscription.ScanDetails.SubscriptionScanResult | Where-Object { $subcriptionScanResult.ControlIntId -ne $_.ControlIntId }
                            $_oldScanRerportSubscription.ScanDetails.SubscriptionScanResult += $_ORsubcriptionScanResult
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
                                    $_oldControlResult = $_ORresource.ResourceScanResult | Where-Object { $_.ControlIntId -eq $newControlResult.ControlIntId -and $_.ChildResourceName -eq $newControlResult.ChildResourceName }

                                    $_oldControlResult.ScanKind = $newControlResult.ScanKind
                                    $_oldControlResult.ControlIntId = $newControlResult.ControlIntId
                                    $_oldControlResult.ControlUpdatedOn = $newControlResult.ControlUpdatedOn
                                    $_oldControlResult.ControlSeverity = $newControlResult.ControlSeverity

                                    if($newControlResult.AttestationStatus -ne [AttestationStatus]::None -and($newControlResult.AttestationStatus -ne $_oldControlResult.AttestationStatus -or $newControlResult.Justification -ne $_oldControlResult.Justification))
                                    {
                                        $_oldControlResult.AttestationCounter = $_oldControlResult.AttestationCounter + 1 
                                    }
                                    if($_oldControlResult.VerificationResult -ne $newControlResult.VerificationResult)
                                    {
                                        $_oldControlResult.LastResultTransitionOn = [System.DateTime]::UtcNow
                                    }

                                    $_oldControlResult.PreviousVerificationResult = $_oldControlResult.VerificationResult
                                    $_oldControlResult.ActualVerificationResult = $newControlResult.ActualVerificationResult
                                    $_oldControlResult.AttestationStatus = $newControlResult.AttestationStatus
                                    $_oldControlResult.VerificationResult = $newControlResult.VerificationResult
                                    $_oldControlResult.AttestedBy = $newControlResult.AttestedBy
                                    $_oldControlResult.AttestedDate = $newControlResult.AttestedDate
                                    $_oldControlResult.Justification = $newControlResult.Justification
                                    $_oldControlResult.AttestationData = $newControlResult.AttestationData
                                    $_oldControlResult.IsBaselineControl = $newControlResult.IsBaselineControl
                                    $_oldControlResult.LastScannedOn = [System.DateTime]::UtcNow

                                    if($_oldControlResult.FirstScannedOn -eq [Constants]::AzSKDefaultDateTime)
                                    {
                                        $_oldControlResult.FirstScannedOn = [System.DateTime]::UtcNow
                                    }
                                    
                                    if($_oldControlResult.FirstFailedOn -eq [Constants]::AzSKDefaultDateTime -and $newControlResult.ActualVerificationResult -eq [VerificationResult]::Failed)
                                    {
                                        $_oldControlResult.FirstFailedOn = [System.DateTime]::UtcNow
                                    }

                                    if($_oldControlResult.FirstAttestedOn -eq [Constants]::AzSKDefaultDateTime -and $newControlResult.AttestationStatus -ne [AttestationStatus]::None)
                                    {
                                        $_oldControlResult.FirstAttestedOn = [System.DateTime]::UtcNow
                                    }
                                    
                                    $_oldControlResult.ScannedBy = $newControlResult.ScannedBy
                                    
                                    $_oldControlResult.ScanSource = $newControlResult.ScanSource
                                    $_oldControlResult.ScannerModuleName = $newControlResult.ScannerModuleName
                                    $_oldControlResult.ScannerVersion = $newControlResult.ScannerVersion
                                    $_oldControlResult.ControlVersion = $newControlResult.ControlVersion
                                    $_oldControlResult.IsLatestPSModule = $newControlResult.IsLatestPSModule
                                    $_oldControlResult.HasRequiredPermissions = $newControlResult.HasRequiredPermissions
                                    $_oldControlResult.HasAttestationWritePermissions = $newControlResult.HasAttestationWritePermissions
                                    $_oldControlResult.HasAttestationReadPermissions = $newControlResult.HasAttestationReadPermissions
                                    $_oldControlResult.UserComments = $newControlResult.UserComments
                                    $_oldControlResult.Metadata = $newControlResult.Metadata
									$_oldControlResult.HasOwnerAccessTag = $newControlResult.HasOwnerAccessTag

                                    $_ORresource.ResourceScanResult = $_ORresource.ResourceScanResult | Where-Object { $_.ControlIntId -ne $_oldControlResult.ControlIntId -or  $_.ChildResourceName -ne  $_oldControlResult.ChildResourceName }
                                    $_ORresource.ResourceScanResult += $_oldControlResult
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

            $_oldScanReport.Subscriptions = $_oldScanReport.Subscriptions | Where-Object { $_.SubscriptionId -ne $scanReport.SubscriptionId }
            $_oldScanReport.Subscriptions += $_oldScanRerportSubscription
        }
        else
        {
            if([Helpers]::CheckMember($_oldScanReport,"Subscriptions"))
            {
                $_oldScanReport.Subscriptions += $scanReport;
            }
            else
            {
                $_oldScanReport = [LocalSubscriptionReport]::new()
                $_oldScanReport.Subscriptions += $scanReport;
            }
            
        }

        return $_oldScanReport
    }

    [bool] HasStorageReportReadAccessPermissions()
	{
		if($this.HasStorageReportReadPermissions -le 0)
		{
			return $false;
		}
		else
		{
			return $true;
		}
	}

	[bool] HasStorageReportWriteAccessPermissions()
	{		
		if($this.HasStorageReportWritePermissions -le 0)
		{
			return $false;
		}
		else
		{
			return $true;
		}
	}

	hidden [LSRSubscription] SerializeResourceInventory($resourceInventory)
    {
        $storageReport = [LSRSubscription]::new()
        $storageReport.SubscriptionId = $resourceInventory.SubscriptionId
		if([Helpers]::CheckMember($resourceInventory,"ResourceGroups") -and ($resourceInventory.ResourceGroups | Measure-Object ).Count -gt 0)
		{
			$scanDetails = [LSRScanDetails]::new()
			$resourceInventory.ResourceGroups | ForEach-Object {
				$resourcegroups = $_
				if([Helpers]::CheckMember($resourcegroups,"Resources") -and ($resourcegroups.Resources | Measure-Object ).Count -gt 0)
				{
					$resourcegroups.Resources | ForEach-Object {
						$resource = $_
						$newResource = [LSRResources]::new()
						$newResource.HashId = [Helpers]::ComputeHash($resource.ResourceId)
						$newResource.ResourceId = $resource.ResourceId
						$newResource.FeatureName = $resource.Feature
						$newResource.ResourceGroupName = $resourcegroups.Name
						$newResource.ResourceName = $resource.Name

						$scanDetails.Resources += $newResource
					}
				}
			}
			$storageReport.ScanDetails = $scanDetails;
		}
        return $storageReport;
    }

	hidden [LocalSubscriptionReport] MergeSVTScanResult($currentScanResults, $resourceInventory, $scanSource, $scannerVersion, $scanKind)
	{
		if($currentScanResults.Count -lt 1) { return $null}

		$SVTEventContextFirst = $currentScanResults[0]
		$subscriptionId = $SVTEventContextFirst.SubscriptionContext.SubscriptionId

		$_oldScanReport = $this.GetLocalSubscriptionScanReport();
		$subscription = [LSRSubscription]::new()
		[LSRResources[]] $resources = @()

		if((($_oldScanReport.Subscriptions | Where-Object { $_.SubscriptionId -eq $subscriptionId }) | Measure-Object).Count -gt 0)
		{
			$subscription = $_oldScanReport.Subscriptions | Where-Object { $_.SubscriptionId -eq $subscriptionId }
		}
		else
		{
			$subscription.SubscriptionId = $subscriptionId
			$subscription.SubscriptionName = $SVTEventContextFirst.SubscriptionContext.SubscriptionName
		}

		# ToDo: Check for null
		if($null -ne $subscription.ScanDetails)
		{
			$subscription.ScanDetails = [LSRScanDetails]::new()
		}
		else
		{
			$resources = $subscription.ScanDetails.Resources
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
								
							# ToDo: Change _OR to snapshot
							$_ORsubcriptionScanResult = $subscription.ScanDetails.SubscriptionScanResult | Where-Object { $currentScanResult.ControlItem.Id -eq $_.ControlIntId }
							$svtResults = $this.ConvertScanResultToSnapshotResult($currentScanResult, $scanSource, $scannerVersion, $scanKind, $_ORsubcriptionScanResult, $true)
							#$_ORsubcriptionScanResult.ScanKind = $svtResult.ScanKind
							#$_ORsubcriptionScanResult.ControlId = $svtResult.ControlId
							#$_ORsubcriptionScanResult.ControlUpdatedOn = $svtResult.ControlUpdatedOn
							#$_ORsubcriptionScanResult.ControlSeverity = $svtResult.ControlSeverity

							#if($svtResult.AttestationStatus -ne [AttestationStatus]::None -and ($svtResult.AttestationStatus -ne $_ORsubcriptionScanResult.AttestationStatus -or $svtResult.Justification -ne $_ORsubcriptionScanResult.Justification))
							#{
							#	$_ORsubcriptionScanResult.AttestationCounter = $_ORsubcriptionScanResult.AttestationCounter + 1
							#}
							#if($_ORsubcriptionScanResult.VerificationResult -ne $svtResult.VerificationResult)
							#{
							#	$_ORsubcriptionScanResult.LastResultTransitionOn = [System.DateTime]::UtcNow
							#}

							#$_ORsubcriptionScanResult.PreviousVerificationResult = $_ORsubcriptionScanResult.ActualVerificationResult
							#$_ORsubcriptionScanResult.ActualVerificationResult = $svtResult.ActualVerificationResult
							#$_ORsubcriptionScanResult.AttestationStatus = $svtResult.AttestationStatus
							#$_ORsubcriptionScanResult.VerificationResult = $svtResult.VerificationResult
							#$_ORsubcriptionScanResult.AttestedBy = $svtResult.AttestedBy
							#$_ORsubcriptionScanResult.AttestedDate = $svtResult.AttestedDate
							#$_ORsubcriptionScanResult.Justification = $svtResult.Justification
							#$_ORsubcriptionScanResult.AttestationData = $svtResult.AttestationData
							#$_ORsubcriptionScanResult.LastScannedOn = [System.DateTime]::UtcNow

							#if($_ORsubcriptionScanResult.FirstScannedOn -eq [Constants]::AzSKDefaultDateTime)
							#{
							#	$_ORsubcriptionScanResult.FirstScannedOn = [System.DateTime]::UtcNow
							#}
                            
							#if($_ORsubcriptionScanResult.FirstFailedOn -eq [Constants]::AzSKDefaultDateTime -and $svtResult.ActualVerificationResult -eq [VerificationResult]::Failed)
							#{
							#	$_ORsubcriptionScanResult.FirstFailedOn = [System.DateTime]::UtcNow
							#}

							#if($_ORsubcriptionScanResult.FirstAttestedOn -eq [Constants]::AzSKDefaultDateTime -and $svtResult.AttestationStatus -ne [AttestationStatus]::None)
							#{
							#	$_ORsubcriptionScanResult.FirstAttestedOn = [System.DateTime]::UtcNow
							#}

							#$_ORsubcriptionScanResult.ScannedBy = $svtResult.ScannedBy
							#$_ORsubcriptionScanResult.ScanSource = $svtResult.ScanSource
							#$_ORsubcriptionScanResult.ScannerModuleName = $svtResult.ScannerModuleName
							#$_ORsubcriptionScanResult.ScannerVersion = $svtResult.ScannerVersion
							#$_ORsubcriptionScanResult.ControlVersion = $svtResult.ControlVersion
							#$_ORsubcriptionScanResult.IsLatestPSModule = $svtResult.IsLatestPSModule
							#$_ORsubcriptionScanResult.HasRequiredPermissions = $svtResult.HasRequiredPermissions
							#$_ORsubcriptionScanResult.HasAttestationWritePermissions = $svtResult.HasAttestationWritePermissions
							#$_ORsubcriptionScanResult.HasAttestationReadPermissions = $svtResult.HasAttestationReadPermissions
							#$_ORsubcriptionScanResult.UserComments = $svtResult.UserComments
							#$_ORsubcriptionScanResult.Metadata = $svtResult.Metadata
							#$_ORsubcriptionScanResult.IsBaselineControl = $svtResult.IsBaselineControl
							#$_ORsubcriptionScanResult.HasOwnerAccessTag = $svtResult.HasOwnerAccessTag

							# ToDo: Pass old obj to serilize fun
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
				else
				{

					if((($resources | Where-Object {$_.ResourceId -eq $currentScanResult.ResourceContext.ResourceId }) | Measure-Object).Count -gt 0)
					{
						$resource = $resources | Where-Object {$_.ResourceId -eq $currentScanResult.ResourceContext.ResourceId }
						$resource.LastEventOn = [DateTime]::UtcNow

						if((($resource.ResourceScanResult | Where-Object { $_.ControlIntId -eq $currentScanResult.ControlItem.Id }) | Measure-Object).Count -gt 0)
						{
							$_oldControlResult = $resource.ResourceScanResult | Where-Object { $_.ControlIntId -eq $currentScanResult.ControlItem.Id }
							$svtResults = $this.ConvertScanResultToSnapshotResult($currentScanResult, $scanSource, $scannerVersion, $scanKind, $_oldControlResult, $false)
							#$_oldControlResult.ControlId = $_resourceSVTResult.ControlId
							#$_oldControlResult.ScanKind = $_resourceSVTResult.ScanKind
							#$_oldControlResult.ControlUpdatedOn = $_resourceSVTResult.ControlUpdatedOn
							#$_oldControlResult.ControlSeverity = $_resourceSVTResult.ControlSeverity

							#if($_resourceSVTResult.AttestationStatus -ne [AttestationStatus]::None -and($_resourceSVTResult.AttestationStatus -ne $_oldControlResult.AttestationStatus -or $_resourceSVTResult.Justification -ne $_oldControlResult.Justification))
							#{
							#	$_oldControlResult.AttestationCounter = $_oldControlResult.AttestationCounter + 1 
							#}
							#if($_oldControlResult.VerificationResult -ne $_resourceSVTResult.VerificationResult)
							#{
							#	$_oldControlResult.LastResultTransitionOn = [System.DateTime]::UtcNow
							#}

							#$_oldControlResult.PreviousVerificationResult = $_oldControlResult.VerificationResult
							#$_oldControlResult.ActualVerificationResult = $_resourceSVTResult.ActualVerificationResult
							#$_oldControlResult.AttestationStatus = $_resourceSVTResult.AttestationStatus
							#$_oldControlResult.VerificationResult = $_resourceSVTResult.VerificationResult
							#$_oldControlResult.AttestedBy = $_resourceSVTResult.AttestedBy
							#$_oldControlResult.AttestedDate = $_resourceSVTResult.AttestedDate
							#$_oldControlResult.Justification = $_resourceSVTResult.Justification
							#$_oldControlResult.AttestationData = $_resourceSVTResult.AttestationData
							#$_oldControlResult.IsBaselineControl = $_resourceSVTResult.IsBaselineControl
							#$_oldControlResult.LastScannedOn = [System.DateTime]::UtcNow

							#if($_oldControlResult.FirstScannedOn -eq [Constants]::AzSKDefaultDateTime)
							#{
							#	$_oldControlResult.FirstScannedOn = [System.DateTime]::UtcNow
							#}
                                    
							#if($_oldControlResult.FirstFailedOn -eq [Constants]::AzSKDefaultDateTime -and $_resourceSVTResult.ActualVerificationResult -eq [VerificationResult]::Failed)
							#{
							#	$_oldControlResult.FirstFailedOn = [System.DateTime]::UtcNow
							#}

							#if($_oldControlResult.FirstAttestedOn -eq [Constants]::AzSKDefaultDateTime -and $_resourceSVTResult.AttestationStatus -ne [AttestationStatus]::None)
							#{
							#	$_oldControlResult.FirstAttestedOn = [System.DateTime]::UtcNow
							#}
                                    
							#$_oldControlResult.ScannedBy = $_resourceSVTResult.ScannedBy
                                    
							#$_oldControlResult.ScanSource = $_resourceSVTResult.ScanSource
							#$_oldControlResult.ScannerModuleName = $_resourceSVTResult.ScannerModuleName
							#$_oldControlResult.ScannerVersion = $_resourceSVTResult.ScannerVersion
							#$_oldControlResult.ControlVersion = $_resourceSVTResult.ControlVersion
							#$_oldControlResult.IsLatestPSModule = $_resourceSVTResult.IsLatestPSModule
							#$_oldControlResult.HasRequiredPermissions = $_resourceSVTResult.HasRequiredPermissions
							#$_oldControlResult.HasAttestationWritePermissions = $_resourceSVTResult.HasAttestationWritePermissions
							#$_oldControlResult.HasAttestationReadPermissions = $_resourceSVTResult.HasAttestationReadPermissions
							#$_oldControlResult.UserComments = $_resourceSVTResult.UserComments
							#$_oldControlResult.Metadata = $_resourceSVTResult.Metadata
							#$_oldControlResult.HasOwnerAccessTag = $_resourceSVTResult.HasOwnerAccessTag

							$resource.ResourceScanResult = $resource.ResourceScanResult | Where-Object { $_.ControlIntId -ne $_oldControlResult.ControlIntId }
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

		# ToDo: Check for previously delete resources


		#Resource Inventory
		if([Helpers]::CheckMember($resourceInventory,"ResourceGroups") -and ($resourceInventory.ResourceGroups | Measure-Object ).Count -gt 0)
		{
			$resourceInventory.ResourceGroups | ForEach-Object {
				$resourcegroups = $_
				if([Helpers]::CheckMember($resourcegroups,"Resources") -and ($resourcegroups.Resources | Measure-Object ).Count -gt 0)
				{
					$resourcegroups.Resources | ForEach-Object {
						$resource = $_
						if((($resources | Where-Object { $_.ResourceId -eq  $resource.ResourceId }) | Measure-Object).Count -eq 0)
						{
							$newResource = [LSRResources]::new()
							$newResource.HashId = [Helpers]::ComputeHash($resource.ResourceId)
							$newResource.ResourceId = $resource.ResourceId
							$newResource.FeatureName = $resource.Feature
							$newResource.ResourceGroupName = $resourcegroups.Name
							$newResource.ResourceName = $resource.Name

							$resources += $newResource	
						}
					}
				}
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

		$_oldScanReport.Subscriptions = $_oldScanReport.Subscriptions | Where-Object { $_.SubscriptionId -ne $subscription.SubscriptionId }
		$_oldScanReport.Subscriptions += $subscription;

		return $_oldScanReport

	}

	hidden [LSRSubscriptionControlResult] SerializeSubscriptionSVTResult($svtResult, $scanSource, $scannerVersion, $scanKind)
	{
		$subscriptionScanResult = [LSRSubscriptionControlResult]::new()
		if(($svtResult.ControlResults | Measure-Object).Count -gt 0)
		{
			# ToDo: 0th index to var
			$subscriptionScanResult.ScannedBy = [Helpers]::GetCurrentRMContext().Account
			$subscriptionScanResult.ScanSource = $scanSource
			$subscriptionScanResult.ScannerVersion = $scannerVersion
			$subscriptionScanResult.ControlVersion = $scannerVersion
			$subscriptionScanResult.ControlId = $svtResult.ControlItem.ControlId 
			$subscriptionScanResult.ControlIntId = $svtResult.ControlItem.Id 
			$subscriptionScanResult.ControlSeverity = $svtResult.ControlItem.ControlSeverity 
			$subscriptionScanResult.ActualVerificationResult = $svtResult.ControlResults[0].ActualVerificationResult 
			$subscriptionScanResult.AttestationStatus = $svtResult.ControlResults[0].AttestationStatus
			if($subscriptionScanResult.AttestationStatus -ne [AttestationStatus]::None)
			{
				$subscriptionScanResult.AttestedBy =  $svtResult.ControlResults[0].StateManagement.AttestedStateData.AttestedBy
				$subscriptionScanResult.AttestedDate = $svtResult.ControlResults[0].StateManagement.AttestedStateData.AttestedDate
				$subscriptionScanResult.Justification = $svtResult.ControlResults[0].StateManagement.AttestedStateData.Justification
				$subscriptionScanResult.AttestationData = [Helpers]::ConvertToJsonCustomCompressed($svtResult.ControlResults[0].StateManagement.AttestedStateData.DataObject)
			}

			$subscriptionScanResult.VerificationResult = $svtResult.ControlResults[0].VerificationResult
			$subscriptionScanResult.ScanKind = $scanKind
			$subscriptionScanResult.ScannerModuleName = [Constants]::AzSKModuleName
			$subscriptionScanResult.IsLatestPSModule = $svtResult.ControlResults[0].CurrentSessionContext.IsLatestPSModule
			$subscriptionScanResult.HasRequiredPermissions = $svtResult.ControlResults[0].CurrentSessionContext.Permissions.HasRequiredAccess
			$subscriptionScanResult.HasAttestationWritePermissions = $svtResult.ControlResults[0].CurrentSessionContext.Permissions.HasAttestationWritePermissions
			$subscriptionScanResult.HasAttestationReadPermissions = $svtResult.ControlResults[0].CurrentSessionContext.Permissions.HasAttestationReadPermissions
			$subscriptionScanResult.UserComments = $svtResult.ControlResults[0].UserComments
			$subscriptionScanResult.IsBaselineControl = $svtResult.ControlItem.IsBaselineControl
			if($svtResult.ControlItem.Tags.Contains("OwnerAccess")  -or $svtResult.ControlItem.Tags.Contains("GraphRead"))
			{
				$subscriptionScanResult.HasOwnerAccessTag = $true
			}

			if($subscriptionScanResult.ActualVerificationResult -ne [VerificationResult]::Passed)
			{
				$subscriptionScanResult.FirstFailedOn = [DateTime]::UtcNow
			}
			if($subscriptionScanResult.AttestationStatus -ne [AttestationStatus]::None)
			{
				$subscriptionScanResult.FirstAttestedOn = [DateTime]::UtcNow
				$subscriptionScanResult.AttestationCounter = 1
			}
			$subscriptionScanResult.FirstScannedOn = [DateTime]::UtcNow
			$subscriptionScanResult.LastResultTransitionOn = [DateTime]::UtcNow
			$subscriptionScanResult.LastScannedOn = [DateTime]::UtcNow
		}
		
		return $subscriptionScanResult
	}

	hidden [LSRResourceScanResult[]] SerializeResourceSVTResult($svtResult, $scanSource, $scannerVersion, $scanKind)
	{
		[LSRResourceScanResult[]] $resourceScanResults = @();
		$svtResult.ControlResults | ForEach-Object {
			$currentResult = $_
			if($currentResult.CurrentSessionContext.IsLatestPSModule -and $currentResult.CurrentSessionContext.Permissions.HasRequiredAccess -and $currentResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions)
			{
				$resourceScanResult = [LSRResourceScanResult]::new()
				$resourceScanResult.ScannedBy = [Helpers]::GetCurrentRMContext().Account
				$resourceScanResult.ScanSource = $scanSource
				$resourceScanResult.ScannerVersion = $scannerVersion
				$resourceScanResult.ControlVersion = $scannerVersion
				$resourceScanResult.ChildResourceName = $currentResult.ChildResourceName 
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

				if($resourceScanResult.ActualVerificationResult -ne [VerificationResult]::Passed)
				{
					$resourceScanResult.FirstFailedOn = [DateTime]::UtcNow
				}
				if($resourceScanResult.AttestationStatus -ne [AttestationStatus]::None)
				{
					$resourceScanResult.FirstAttestedOn = [DateTime]::UtcNow
					$resourceScanResult.AttestationCounter = 1
				}

				$resourceScanResult.FirstScannedOn = [DateTime]::UtcNow
				$resourceScanResult.LastResultTransitionOn = [DateTime]::UtcNow
				$resourceScanResult.LastScannedOn = [DateTime]::UtcNow

				# ToDo: Need to confirm
				#$resourceScanResult.Metadata = $scanResult.Metadata
				$resourceScanResults += $resourceScanResult
			}
		}
		return $resourceScanResults
	} 

	hidden [LSRControlResultBase[]] ConvertScanResultToSnapshotResult($svtResult, $scanSource, $scannerVersion, $scanKind, $oldResult, $isSubscriptionScan)
	{
		if($isSubscriptionScan)
		{
			[LSRSubscriptionControlResult[]] $scanResult = @();	
		}
		else
		{
			[LSRResourceScanResult[]] $scanResult = @();	
		}

		$svtResult.ControlResults | ForEach-Object {
			$currentResult = $_
			$isLegitimateResult = ($currentResult.CurrentSessionContext.IsLatestPSModule -and $currentResult.CurrentSessionContext.Permissions.HasRequiredAccess -and $currentResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions)
			if($isLegitimateResult)
			{
				$resourceScanResult = [LSRResourceScanResult]::new()
				if($null -ne $oldResult)
				{
					if($isSubscriptionScan) 
					{
						$resourceScanResult = $oldResult
					}
					else
					{
						$resourceScanResult = $oldResult | Where-Object { $_.ChildResourceName -eq $currentResult.ChildResourceName -or [string]::IsNullOrEmpty($currentResult.ChildResourceName) }
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
				$resourceScanResults += $resourceScanResult
			}
		}
		return $resourceScanResults
	}
}