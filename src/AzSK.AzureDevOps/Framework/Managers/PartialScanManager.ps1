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
	hidden [string] $scanSource = $null;
    hidden [bool] $isRTFAlreadyAvailable = $false;


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
		$this.scanSource = [AzSKSettings]::GetInstance().GetScanSource();
		#Validating the configuration of storing resource tracker file
        if($null -ne $this.ControlSettings.PartialScan)
		{
			$this.StoreResTrackerLocally = [Bool]::Parse($this.ControlSettings.PartialScan.StoreResourceTrackerLocally);
		}
		If ($this.scanSource -eq "CICD") # use extension storage in case of CICD partial scan
		{
			$this.subId = $subId
            if($null -eq $this.ScanPendingForResources)
		    {
				if(![string]::isnullorwhitespace($this.subId))
				{
					$rmContext = [ContextHelper]::GetCurrentContext();
					$user = "";
					$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
                    $uri= "";

                    if (Test-Path env:partialScanURI)
                    {
						#Uri is created in cicd task based on jobid
                        $uri = $env:partialScanURI
                    }
                    else {
					    $uri = [Constants]::StorageUri -f $this.subId, $this.subId, "ResourceTrackerFile"
                    }

					try {
						$webRequestResult = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
						$this.ScanPendingForResources = $webRequestResult.value | ConvertFrom-Json
                        $this.isRTFAlreadyAvailable = $true;
						write-host "Get request ran successfully"
					}
					catch
					{
						write-host "error in Get request from extension storage :  $uri"
                        $this.ScanPendingForResources = $null
                        $this.isRTFAlreadyAvailable = $false;
					}	
			    }
			}
		}
        #Use local Resource Tracker files for partial scanning
        elseif ($this.StoreResTrackerLocally) 
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
			}
        }
    }

	#Method called from PartialScanManger to update state of last resource scanned
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

                # Post result to RTF for last resource scan. This is required as we are updating RTF only when a resource scan starts and not when it ends
                $IsLastResourceScan = ($this.ResourceScanTrackerObj.ResourceMapTable | Where-Object {$_.State -eq [ScanState]::INIT} |  Measure-Object).Count -eq 0
                if ($IsLastResourceScan -eq $true)
                {
				    $this.WriteToResourceTrackerFile();
                }
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

	# Method to remove obsolete Resource Tracker file
	[void] RemovePartialScanData()
	{
		If ($this.scanSource -eq "CICD")
		{
            if($null -ne $this.ResourceScanTrackerObj)
		    {
				$rmContext = [ContextHelper]::GetCurrentContext();
				$user = "";
				$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
                $uri ="";

                if (Test-Path env:partialScanURI)
                    {
						#Uri is created by cicd task based on jobid
                        $uri = $env:partialScanURI
                    }
                else {
					$uri = [Constants]::StorageUri -f $this.subId, $this.subId, "ResourceTrackerFile"
				}
				
				try {
					if ($this.ResourceScanTrackerObj.ResourceMapTable -ne $null){
						$webRequestResult = Invoke-WebRequest -Uri $uri -Method Delete -ContentType "application/json" -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo) } 
						$this.ResourceScanTrackerObj = $null
						write-host "Resource tracker removed successfully"
					}
				}
				catch {
					write-host "error in delete request from extension storage :  $uri"
				}
			}
		}

        #Use local Resource Tracker files for partial scanning
        elseif ($this.StoreResTrackerLocally) 
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
	}

	#Method to fetch all applicable resources as per input command (including those with "COMP" status in ResourceTracker file)
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

			if ($this.ScanPendingForResources -ne $null){
                $this.ResourceScanTrackerObj = [PartialScanResourceMap]@{
				    Id = $this.ScanPendingForResources.Id;
				    CreatedDate = $this.ScanPendingForResources.CreatedDate;
				    ResourceMapTable = $this.ScanPendingForResources.ResourceMapTable.value;
			    }
            }
            else{
                $this.ResourceScanTrackerObj = $masterControlBlob;
            }

			$this.WriteToResourceTrackerFile();
			$this.ActiveStatus = [ActiveStatus]::Yes;
		}
	}

	[void] WriteToResourceTrackerFile()
	{
		If ($this.scanSource -eq "CICD")
		{
            if($null -ne $this.ResourceScanTrackerObj)
		    {
				if(![string]::isnullorwhitespace($this.subId))
				{
					$rmContext = [ContextHelper]::GetCurrentContext();
					$user = "";
                    $uri = "";
					$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
					$scanObject = $this.ResourceScanTrackerObj | ConvertTo-Json
					$body = "";

                    if (Test-Path env:partialScanURI)
                    {
                        $uri = $env:partialScanURI
                        $JobId ="";
                        $JobId = $uri.Replace('?','/').Split('/')[$JobId.Length -2]
						$body = @{"id" = $Jobid;"__etag"=-1; "value"= $scanObject;} | ConvertTo-Json
                    }
                    else {
					    $uri = [Constants]::StorageUri -f $this.subId, $this.subId, "ResourceTrackerFile"
                        $body = @{"id" = "ResourceTrackerFile";"__etag"=-1; "value"= $scanObject;} | ConvertTo-Json
                    }

					try {
						$webRequestResult = Invoke-WebRequest -Uri $uri -Method Put -ContentType "application/json" -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo) } -Body $body 
						write-host "Resource tracker updated successfully"
                        $this.isRTFAlreadyAvailable = $true;
					}
					catch
					{
						write-host "error in WriteToResourceTrackerFile method : $uri"
					}		
			    }
			}
		}
        elseif ($this.StoreResTrackerLocally) 
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
	}

	#Method to fetch ResourceTrackerFile as an object
	hidden [void] GetResourceScanTrackerObject()
	{
            if($null -eq $this.ScanPendingForResources)
			{
				return;
			}
			If ($this.scanSource -eq "CICD") # use extension storage in case of CICD partial scan
			{
				if(![string]::isnullorwhitespace($this.ScanPendingForResources))
				{
					$this.ResourceScanTrackerObj = [PartialScanResourceMap]@{
				        Id = $this.ScanPendingForResources.Id;
				        CreatedDate = $this.ScanPendingForResources.CreatedDate;
				        ResourceMapTable = $this.ScanPendingForResources.ResourceMapTable.value;
			        }
				}
			}
            elseif ($this.StoreResTrackerLocally) 
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
				$this.ResourceScanTrackerObj = Get-content $masterFilePath | ConvertFrom-Json
            }
	}

	[ActiveStatus] IsPartialScanInProgress($subId)
	{
		$this.GetResourceTrackerFile($subId);
		if($null -ne $this.ControlSettings.PartialScan)
		{
			$resourceTrackerFileValidforDays = [Int32]::Parse($this.ControlSettings.PartialScan.ResourceTrackerValidforDays);
			$this.GetResourceScanTrackerObject();
			if($null -eq $this.ResourceScanTrackerObj)
			{
				return $this.ActiveStatus = [ActiveStatus]::No;
			}
			$shouldStopScanning = ($this.ResourceScanTrackerObj.ResourceMapTable | Where-Object {$_.State -notin ([ScanState]::COMP,[ScanState]::ERR)} |  Measure-Object).Count -eq 0
			if($this.ResourceScanTrackerObj.CreatedDate.AddDays($resourceTrackerFileValidforDays) -lt [DateTime]::UtcNow -or $shouldStopScanning)
			{
				$this.RemovePartialScanData();
				$this.ScanPendingForResources = $null;
				return $this.ActiveStatus = [ActiveStatus]::No;

			}
			return $this.ActiveStatus = [ActiveStatus]::Yes

		}
		else
		{
			$this.ScanPendingForResources = $null;
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
