Set-StrictMode -Version Latest

class PartialScanManager
{
	hidden [string] $subId = $null;
	hidden [PSObject] $ScanPendingForResources = $null;
	hidden [string] $ResourceScanTrackerFileName=$null;
	hidden [PartialScanResourceMap] $ResourceScanTrackerObj = $null
	[PSObject] $ControlSettings;
	hidden [ActiveStatus] $ActiveStatus = [ActiveStatus]::NotStarted;
    hidden [string] $AzSKTempStatePath = (Join-Path $([Constants]::AzSKAppFolderPath) "TempState" | Join-Path -ChildPath "PartialScanData");
    hidden [bool] $StoreResTrackerLocally = $false;


	hidden static [PartialScanManager] $Instance = $null;
	
	static [PartialScanManager] GetInstance([PSObject] $StorageAccount, [string] $SubscriptionId)
    {
        if ( $null -eq  [PartialScanManager]::Instance)
        {
			[PartialScanManager]::Instance = [PartialScanManager]::new($SubscriptionId);
		}
		[PartialScanManager]::Instance.subId = $SubscriptionId;
        return [PartialScanManager]::Instance
    }

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
	PartialScanManager([string] $SubscriptionId)
	{
		$this.ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");
		$this.subId = $SubscriptionId;
		if ([string]::isnullorwhitespace($this.ResourceScanTrackerFileName))
        {
           if([ConfigurationManager]::GetAzSKSettings().IsCentralScanModeOn)
		   {
				$this.ResourceScanTrackerFileName = Join-Path $SubscriptionId $([Constants]::ResourceScanTrackerCMBlobName)
		   }
		   else
		   {
				$this.ResourceScanTrackerFileName = Join-Path $SubscriptionId $([Constants]::ResourceScanTrackerBlobName)
		   }
        }
		$this.GetResourceScanTrackerObject();
	}

	PartialScanManager()
	{
		$this.ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");
		if ([string]::isnullorwhitespace($this.ResourceScanTrackerFileName))
        {
			$this.ResourceScanTrackerFileName =  [Constants]::ResourceScanTrackerBlobName
        }
		$this.GetResourceScanTrackerObject();
	}

     hidden [void] GetResourceTrackerFile($subId)
    {
        if($null -ne $this.ControlSettings.PartialScan)
		{
			$this.StoreResTrackerLocally = [Bool]::Parse($this.ControlSettings.PartialScan.StoreResourceTrackerLocally);
        }
        #Use local Resource Tracker files for partial scanning
        if ($this.StoreResTrackerLocally) 
        {
            $this.subId = $subId
            if($null -eq $this.ScanPendingForResources)
		    {
			    if(![string]::isnullorwhitespace($this.subId)){
				    if(Test-Path (Join-Path (Join-Path $this.AzSKTempStatePath $this.subId) $this.ResourceScanTrackerFileName))	
			        {
                        $this.ScanPendingForResources = Get-Content (Join-Path (Join-Path $this.AzSKTempStatePath $this.subId) $this.ResourceScanTrackerFileName) -Raw
				    }
			    }
                else{
                    if(Test-Path (Join-Path $this.AzSKTempStatePath $this.ResourceScanTrackerFileName))	
			            {
                            $this.ScanPendingForResources = Get-Content (Join-Path $this.AzSKTempStatePath $this.ResourceScanTrackerFileName) -Raw
				        }
                }
			}
        }
        #Use Durable Resource Tracker files for partial scanning
        else
        {
             Write-Host ("Durable resource tracker files are not supported by partial scan currently.") -ForegroundColor red
        }
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
				$this.WriteToResourceTrackerFile();
			}
			else
			{
				#do nothing
			}
		}
	}

	[void] RemovePartialScanData()
	{
        #Use local Resource Tracker files for partial scanning
        if ($this.StoreResTrackerLocally) 
            {
		    if($null -ne $this.ResourceScanTrackerObj)
		    {
			    if(![string]::isnullorwhitespace($this.subId)){
				    if(-not (Test-Path (Join-Path $this.AzSKTempStatePath $this.subId)))
				    {
					    New-Item -ItemType Directory -Path (Join-Path $this.AzSKTempStatePath $this.subId) -ErrorAction Stop | Out-Null
				    }
			    }
			    else{
				    if(-not (Test-Path "$this.AzSKTempStatePath"))
				    {
					    New-Item -ItemType Directory -Path "$this.AzSKTempStatePath" -ErrorAction Stop | Out-Null
				    }
			    }

			    $masterFilePath = Join-Path $this.AzSKTempStatePath $($this.ResourceScanTrackerFileName)	
			    $this.ResourceScanTrackerObj = $null
		    }
        }
        #Use Durable Resource Tracker files for partial scanning
        else
        {
             Write-Host ("Durable resource tracker files are not supported by partial scan currently.");
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
			$this.WriteToResourceTrackerFile();
			$this.ActiveStatus = [ActiveStatus]::Yes;
		}
	}

	[void] WriteToResourceTrackerFile()
	{
        if ($this.StoreResTrackerLocally) 
        {
		        if($null -ne $this.ResourceScanTrackerObj)
		        {
			        if(![string]::isnullorwhitespace($this.subId)){
				        if(-not (Test-Path (Join-Path $this.AzSKTempStatePath $this.subId)))
				        {
					        New-Item -ItemType Directory -Path (Join-Path $this.AzSKTempStatePath $this.subId) -ErrorAction Stop | Out-Null
				        }	
			        }
			        else{
				        if(-not (Test-Path "$this.AzSKTempStatePath"))
				        {
					        New-Item -ItemType Directory -Path "$this.AzSKTempStatePath" -ErrorAction Stop | Out-Null
				        }
			        }

			        $masterFilePath =Join-Path (Join-Path $this.AzSKTempStatePath $this.subId) $($this.ResourceScanTrackerFileName)
			        [JsonHelper]::ConvertToJsonCustom($this.ResourceScanTrackerObj) | Out-File $masterFilePath -Force
		        }
        }
        #Use Durable Resource Tracker files for partial scanning
        else
        {
            #Do Nothing
            # Write-Host ("Durable resource tracker files are not supported by partial scan currently.3");
        }
	}

	hidden [void] GetResourceScanTrackerObject()
	{
		if($null -eq $this.ResourceScanTrackerObj)
		{
            if ($null -eq $this.ScanPendingForResources -and ![string]::isnullorwhitespace($this.subId))
			{
				 $this.GetResourceTrackerFile($this.subId);
			}
            if($null -eq $this.ScanPendingForResources)
			{
				return;
			}
			
            if ($this.StoreResTrackerLocally) 
            {
			    if(![string]::isnullorwhitespace($this.subId)){
				    if(-not (Test-Path (Join-Path $this.AzSKTempStatePath $this.subId)))
				    {
					    New-Item -ItemType Directory -Path (Join-Path $this.AzSKTempStatePath $this.subId) -ErrorAction Stop | Out-Null
				    }
			    }
			    else{
				    if(-not (Test-Path "$this.AzSKTempStatePath"))
				    {
					    New-Item -ItemType Directory -Path "$this.AzSKTempStatePath" -ErrorAction Stop | Out-Null
				    }
			    }

			    $masterFilePath = Join-Path (Join-Path $this.AzSKTempStatePath $this.subId) $($this.ResourceScanTrackerFileName)
            }
            #Use Durable Resource Tracker files for partial scanning
            else
            {
                Write-Host ("Durable resource tracker files are not supported by partial scan currently.") -ForegroundColor red
            }
		}
	}

	[ActiveStatus] IsPartialScanInProgress($subId)
	{
		if($null -eq $this.ScanPendingForResources)
		{
		 $this.GetResourceTrackerFile($subId);
		}
		if($null -ne $this.ControlSettings.PartialScan)
		{
			$resourceTrackerFileValidforDays = [Int32]::Parse($this.ControlSettings.PartialScan.ResourceTrackerValidforDays);
			if($null -eq $this.ResourceScanTrackerObj)
			{
				return $this.ActiveStatus = [ActiveStatus]::No;
			}
			$shouldStopScanning = ($this.ResourceScanTrackerObj.ResourceMapTable | Where-Object {$_.State -notin ([ScanState]::COMP,[ScanState]::ERR)} |  Measure-Object).Count -eq 0
			if($this.ResourceScanTrackerObj.CreatedDate.AddDays($resourceTrackerFileValidforDays) -lt [DateTime]::UtcNow -or $shouldStopScanning)
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
}
