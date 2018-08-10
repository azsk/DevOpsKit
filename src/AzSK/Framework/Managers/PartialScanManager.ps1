Set-StrictMode -Version Latest

class PartialScanManager
{
	hidden [PSObject] $AzSKResourceGroup = $null;
	hidden [PSObject] $AzSKStorageAccount = $null;
	hidden [PSObject] $ScanProgressSnapshotsContainer = $null;
	hidden [int] $HasWritePermissions = -1;
	hidden static [string] $ResourceScanTrackerBlobName="";
	hidden [string] $CAScanProgressSnapshotsContainerName = [Constants]::CAScanProgressSnapshotsContainerName
	hidden [PartialScanResourceMap] $ResourceScanTrackerObj = $null
	[PSObject] $ControlSettings;
	hidden [ActiveStatus] $ActiveStatus = [ActiveStatus]::NotStarted;

	hidden static [PartialScanManager] $Instance = $null;
    static [PartialScanManager] GetInstance()
    {
        if ( $null -eq  [PartialScanManager]::Instance)
        {
            [PartialScanManager]::Instance = [PartialScanManager]::new();
        }
        return [PartialScanManager]::Instance
    }
	static [void] ClearInstance()
    {
       [PartialScanManager]::Instance = $null
    }
	PartialScanManager()
	{
		$this.ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");
		if ([string]::isnullorwhitespace([PartialScanManager]::ResourceScanTrackerBlobName))
        {
           if([ConfigurationManager]::GetAzSKSettings().IsCentralScanModeOn)
		   {
				[PartialScanManager]::ResourceScanTrackerBlobName = [Constants]::ResourceScanTrackerCMBlobName
		   }
		   else
		   {
				[PartialScanManager]::ResourceScanTrackerBlobName = [Constants]::ResourceScanTrackerBlobName
		   }
        }
		$this.GetResourceScanTrackerObject();
	}

	hidden [void] GetAzSKScanProgressSnapshotsContainer()
	{
		if($null -eq $this.AzSKStorageAccount)
		{
			$this.GetAzSKStorageAccount()
		}
		if($null -eq $this.AzSKStorageAccount)
		{
			return;
		}


		try
		{
			#Able to read the container then read permissions are good
			$containerObject = Get-AzureStorageContainer -Context $this.AzSKStorageAccount.Context -Name $this.CAScanProgressSnapshotsContainerName -ErrorAction Stop
			$this.ScanProgressSnapshotsContainer = $containerObject;
		}
		catch
		{
			try
			{
				New-AzureStorageContainer -Context $this.AzSKStorageAccount.Context -Name $this.CAScanProgressSnapshotsContainerName -ErrorAction SilentlyContinue
				$containerObject = Get-AzureStorageContainer -Context $this.AzSKStorageAccount.Context -Name $this.CAScanProgressSnapshotsContainerName -ErrorAction SilentlyContinue
				$this.ScanProgressSnapshotsContainer = $containerObject;
			}
			catch
			{
				#Do nothing
			}
		}
	}

	hidden [void] GetAzSKStorageAccount()
	{
		if($null -eq $this.AzSKResourceGroup)
		{
			$this.GetAzSKRG();
		}
		if($null -ne $this.AzSKResourceGroup)
		{
			$StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $this.AzSKResourceGroup.ResourceGroupName | Where-Object {$_.StorageAccountName -like 'azsk*'} -ErrorAction SilentlyContinue
			#if no storage account found then it assumes that there is no control state feature is not used and if there are more than one storage account found it assumes the same
			$this.AzSKStorageAccount = $StorageAccount;
		}
	}

	hidden [PSObject] GetAzSKRG()
	{
		$azSKConfigData = [ConfigurationManager]::GetAzSKConfigData()
		$resourceGroup = Get-AzureRmResourceGroup -Name $azSKConfigData.AzSKRGName -ErrorAction SilentlyContinue
		$this.AzSKResourceGroup = $resourceGroup
		return $resourceGroup;
	}

	[void] UpdateResourceStatus([string] $resourceId, [ScanState] $state)
	{
		$resourceValues = @();
		$this.GetResourceScanTrackerObject();
		if($this.IsListAvailableAndActive())
		{
			$resourceValue = $this.ResourceScanTrackerObj.ResourceMapTable | Where-Object { $_.Id -eq $resourceId};
			if($null -ne $resourceValue)
			{
				$resourceValue.ModifiedDate = [DateTime]::UtcNow;
				$resourceValue.State = $state;
				#$this.ResourceScanTrackerObj.ResourceMapTable[$idHash] = $resourceValue;
			}
			else
			{
				$resourceValue = [PartialScanResource]@{
					Id = $resourceId;
					State = $state;
					ScanRetryCount = 1;
					CreatedDate = [DateTime]::UtcNow;
					ModifiedDate = [DateTime]::UtcNow;
				}
				$this.ResourceScanTrackerObj.ResourceMapTable +=$resourceValue;
			}
		}
	}

	[void] UpdateResourceScanRetryCount([string] $resourceId)
	{
		$resourceValues = @();
		$this.GetResourceScanTrackerObject();
		if($this.IsListAvailableAndActive())
		{
			$resourceValue = $this.ResourceScanTrackerObj.ResourceMapTable | Where-Object { $_.Id -eq $resourceId};
			if($null -ne $resourceValue)
			{
				$resourceValue.ModifiedDate = [DateTime]::UtcNow;
				$resourceValue.ScanRetryCount = $resourceValue.ScanRetryCount + 1;
				if($resourceValue.ScanRetryCount -ge [Constants]::PartialScanMaxRetryCount)
				{
					$resourceValue.State = [ScanState]::ERR
				}
				#$this.PersistStorageBlob();
			}
			else
			{
				#do nothing
			}
		}
	}

	[void] RemovePartialScanData()
	{
		if($null -ne $this.ResourceScanTrackerObj)
		{
            $AzSKTemp = [Constants]::AzSKAppFolderPath + "\TempState";
			if(-not (Test-Path "$AzSKTemp\PartialScanData"))
			{
				mkdir -Path "$AzSKTemp\PartialScanData" -ErrorAction Stop | Out-Null
			}
			$masterFilePath = "$AzSKTemp\PartialScanData\$([PartialScanManager]::ResourceScanTrackerBlobName)"
			$controlStateBlob = Get-AzureStorageBlob -Container $this.CAScanProgressSnapshotsContainerName -Context $this.AzSKStorageAccount.Context -Blob "$([PartialScanManager]::ResourceScanTrackerBlobName)" -ErrorAction SilentlyContinue

			if($null -ne $controlStateBlob)
			{
				Get-AzureStorageBlobContent -CloudBlob $controlStateBlob.ICloudBlob -Context $this.AzSKStorageAccount.Context -Destination $masterFilePath -Force                
				$partialScanResources  = Get-ChildItem -Path $masterFilePath -Force | Get-Content | ConvertFrom-Json
                if($partialScanResources -ne $null -and ($partialScanResources.ResourceMapTable | Measure-Object).Count -gt 0 -and ($partialScanResources.ResourceMapTable | Where-Object {$_.State -notin ([ScanState]::COMP,[ScanState]::ERR)} | Measure-Object).Count -eq 0)
                {
					$this.ArchiveBlob("_End_");
                    Remove-AzureStorageBlob -CloudBlob $controlStateBlob.ICloudBlob -Force -Context $this.AzSKStorageAccount.Context 
                }
                
			}			
			$this.ResourceScanTrackerObj = $null
		}
	}

	[void] CreateResourceMasterList([PSObject] $resourceIds)
	{

		if(($resourceIds | Measure-Object).Count -gt 0)
		{
			$resourceIdMap = @();
			$resourceIds | ForEach-Object {
				$resourceId = $_;
				$resourceValue = [PartialScanResource]@{
					Id = $resourceId;
					State = [ScanState]::INIT;
					ScanRetryCount = 0;
					CreatedDate = [DateTime]::UtcNow;
					ModifiedDate = [DateTime]::UtcNow;
				}
				#$resourceIdMap.Add($hashId,$resourceValue);
				$resourceIdMap +=$resourceValue
			}
			$masterControlBlob = [PartialScanResourceMap]@{
				Id = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss");
				CreatedDate = [DateTime]::UtcNow;
				ResourceMapTable = $resourceIdMap;
			}
			$this.ResourceScanTrackerObj = $masterControlBlob;
			$this.PersistStorageBlob();
			$this.ActiveStatus = [ActiveStatus]::Yes;
		}
	}

	[void] PersistStorageBlob()
	{
		$this.GetResourceScanTrackerObject();
		if($null -ne $this.ResourceScanTrackerObj)
		{
			$AzSKTemp = [Constants]::AzSKAppFolderPath + "\TempState";
			if(-not (Test-Path "$AzSKTemp\PartialScanData"))
			{
				mkdir -Path "$AzSKTemp\PartialScanData" -ErrorAction Stop | Out-Null
			}
			$masterFilePath = "$AzSKTemp\PartialScanData\$([PartialScanManager]::ResourceScanTrackerBlobName)"

			[Helpers]::ConvertToJsonCustom($this.ResourceScanTrackerObj) | Out-File $masterFilePath -Force
			Set-AzureStorageBlobContent -File $masterFilePath -Container $this.CAScanProgressSnapshotsContainerName -BlobType Block -Context $this.AzSKStorageAccount.Context -Force
		}
	}

	hidden [void] ArchiveBlob()
	{
		$this.ArchiveBlob("_");
	}

	hidden [void] ArchiveBlob([string] $token)
	{
		try
		{
			$AzSKTemp = [Constants]::AzSKAppFolderPath + "\TempState";
			
			if(-not (Test-Path "$AzSKTemp\PartialScanData"))
			{
				mkdir -Path "$AzSKTemp\PartialScanData" -ErrorAction Stop | Out-Null
			}
			$archiveName =  $this.CAScanProgressSnapshotsContainerName + $token +  (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss") + ".json";
			if([ConfigurationManager]::GetAzSKSettings().IsCentralScanModeOn)
			{
				$archiveName =  $this.CAScanProgressSnapshotsContainerName + $token +  (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss") + "_CentralMode" + ".json";
			}
			
			$masterFilePath = "$AzSKTemp\PartialScanData\$archiveName"
			$controlStateBlob = Get-AzureStorageBlob -Container $this.CAScanProgressSnapshotsContainerName -Context $this.AzSKStorageAccount.Context -Blob "$([PartialScanManager]::ResourceScanTrackerBlobName)" -ErrorAction SilentlyContinue
			if($null -ne $controlStateBlob)
			{
				Get-AzureStorageBlobContent -CloudBlob $controlStateBlob.ICloudBlob -Context $this.AzSKStorageAccount.Context -Destination $masterFilePath -Force			
				Set-AzureStorageBlobContent -File $masterFilePath -Container $this.CAScanProgressSnapshotsContainerName -Blob "Archive/$archiveName" -BlobType Block -Context $this.AzSKStorageAccount.Context -Force
			}

			#purge old archives
			$NotBefore = [DateTime]::Now.AddDays(-30);
			$OldLogCount = (Get-AzureStorageBlob -Container $this.CAScanProgressSnapshotsContainerName -Context $this.AzSKStorageAccount.Context | Where-Object { $_.LastModified -lt $NotBefore} | Measure-Object).Count

			Get-AzureStorageBlob -Container $this.CAScanProgressSnapshotsContainerName -Context $this.AzSKStorageAccount.Context | Where-Object { $_.LastModified -lt $NotBefore} | Remove-AzureStorageBlob -Force -ErrorAction SilentlyContinue
		}
		catch
		{
			#eat exception as archive should not impact actual flow
		}
	}

	hidden [void] GetResourceScanTrackerObject()
	{
		if($null -eq $this.ResourceScanTrackerObj)
		{
			if($null -eq $this.AzSKStorageAccount -or $null -eq $this.ScanProgressSnapshotsContainer)
			{
				 $this.GetAzSKScanProgressSnapshotsContainer();
			}
			if($null -eq $this.AzSKStorageAccount -or $null -eq $this.ScanProgressSnapshotsContainer)
			{
				return;
			}
			$AzSKTemp = [Constants]::AzSKAppFolderPath + "\TempState";
			if(-not (Test-Path "$AzSKTemp\PartialScanData"))
			{
				mkdir -Path "$AzSKTemp\PartialScanData" -ErrorAction Stop | Out-Null
			}
			$masterFilePath = "$AzSKTemp\PartialScanData\$([PartialScanManager]::ResourceScanTrackerBlobName)"
			$controlStateBlob = Get-AzureStorageBlob -Container $this.CAScanProgressSnapshotsContainerName -Context $this.AzSKStorageAccount.Context -Blob "$([PartialScanManager]::ResourceScanTrackerBlobName)" -ErrorAction SilentlyContinue

			if($null -ne $controlStateBlob)
			{
				Get-AzureStorageBlobContent -CloudBlob $controlStateBlob.ICloudBlob -Context $this.AzSKStorageAccount.Context -Destination $masterFilePath -Force
				$this.ResourceScanTrackerObj = Get-ChildItem -Path $masterFilePath -Force | Get-Content | ConvertFrom-Json
				$resources = Get-AzureRmResource
				#filter resources which are removed from subscription
				$this.ResourceScanTrackerObj.ResourceMapTable = $this.ResourceScanTrackerObj.ResourceMapTable | Where-Object{$resources.ResourceId -contains $_.Id -or $_.Id -eq "AzSKCfg"}
			}
		}
	}

	[ActiveStatus] IsMasterListActive()
	{
		if($null -eq $this.AzSKStorageAccount -or $null -eq $this.ScanProgressSnapshotsContainer)
		{
		 $this.GetAzSKScanProgressSnapshotsContainer();
		}
		if($null -ne $this.ControlSettings.BaselineControls)
		{
			$this.GetResourceScanTrackerObject();
			$expiryInDays = [Int32]::Parse($this.ControlSettings.BaselineControls.ExpiryInDays);
			if($null -eq $this.ResourceScanTrackerObj)
			{
				return $this.ActiveStatus = [ActiveStatus]::No;
			}
			$shouldStopScanning = ($this.ResourceScanTrackerObj.ResourceMapTable | Where-Object {$_.State -notin ([ScanState]::COMP,[ScanState]::ERR)} |  Measure-Object).Count -eq 0
			if($this.ResourceScanTrackerObj.CreatedDate.AddDays($expiryInDays) -lt [DateTime]::UtcNow -or $shouldStopScanning)
			{
				$this.RemovePartialScanData();
				return $this.ActiveStatus = [ActiveStatus]::No;

			}
			return $this.ActiveStatus = [ActiveStatus]::Yes

		}
		else
		{
			return $this.ActiveStatus = [ActiveStatus]::No;

		}
	}

	[PSObject] GetResourceStatus([string] $resourceId)
	{
		$resourceValues = @();
		$this.GetResourceScanTrackerObject();
		if($this.IsListAvailableAndActive())
		{
			$idHash = [Helpers]::ComputeHash($resourceId)
			$resourceValue = $this.ResourceScanTrackerObj.ResourceMapTable[$idHash];
			$resourceValues += $resourceValue;
			return $resourceValues;
		}
		return $null;
	}

	[PSObject] GetNonScannedResources()
	{
		$nonScannedResources = @();
		$this.GetResourceScanTrackerObject();
		if($this.IsListAvailableAndActive())
		{
			$nonScannedResources +=[PartialScanResource[]] $this.ResourceScanTrackerObj.ResourceMapTable | Where-Object {$_.State -eq [ScanState]::INIT}
			return $nonScannedResources;
		}
		return $null;
	}

	[PSObject] GetAllListedResources()
	{
		$nonScannedResources = @();
		$this.ArchiveBlob()
		$this.GetResourceScanTrackerObject();
		if($this.IsListAvailableAndActive())
		{
			$nonScannedResources += $this.ResourceScanTrackerObj.ResourceMapTable
			return $nonScannedResources;
		}
		return $null;
	}

	[Bool] IsListAvailableAndActive()
	{
		if($null -ne $this.ResourceScanTrackerObj -and $this.ActiveStatus -eq [ActiveStatus]::Yes -and $null -ne $this.ResourceScanTrackerObj.ResourceMapTable)
		{
			return $true
		}
		else
		{
			return $false
		}
	}

	[PSObject] GetBaselineControlDetails()
	{
		return  $this.ControlSettings.BaselineControls
	}
}
