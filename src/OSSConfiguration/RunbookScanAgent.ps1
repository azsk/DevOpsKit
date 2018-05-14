function ConvertStringToBoolean($strToConvert) {
    switch ($strToConvert) {
        "true" {return $true}
        "false" {return $false}
    }
    return $false #adding this to prevent error all path doesn't return value"
}


function RunAzSKScan() {

	if(-not [string]::IsNullOrWhiteSpace($OMSWorkspaceId) -and -not [string]::IsNullOrWhiteSpace($OMSWorkspaceSharedKey))
	{
		Set-AzSKOMSSettings -OMSWorkspaceID $OMSWorkspaceId -OMSSharedKey $OMSWorkspaceSharedKey -Source "CA"
	}
	
	if(-not [string]::IsNullOrWhiteSpace($AltOMSWorkspaceId) -and -not [string]::IsNullOrWhiteSpace($AltOMSWorkspaceSharedKey))
	{
		Set-AzSKOMSSettings -AltOMSWorkspaceId $AltOMSWorkspaceId -AltOMSSharedKey $AltOMSWorkspaceSharedKey -Source "CA"
	}
	if(-not [string]::IsNullOrWhiteSpace($WebhookUrl))	
	{
		if(-not [string]::IsNullOrWhiteSpace($WebhookAuthZHeaderName) -and -not [string]::IsNullOrWhiteSpace($WebhookAuthZHeaderValue))
		{
			Set-AzSKWebhookSettings -WebhookUrl $WebhookUrl -AuthZHeaderName $WebhookAuthZHeaderName -AuthZHeaderValue $WebhookAuthZHeaderValue -Source "CA"
		}
		else
		{
			Set-AzSKWebhookSettings -WebhookUrl $WebhookUrl -Source "CA"
		}
	}

    #set values in AzSKSettings.json
    $EnableAADAuthForOnlinePolicyStore = ConvertStringToBoolean($EnableAADAuthForOnlinePolicyStore)
    if ($EnableAADAuthForOnlinePolicyStore) {
        Set-AzSKPolicySettings -OnlinePolicyStoreUrl $OnlinePolicyStoreUrl -EnableAADAuthForOnlinePolicyStore
    }
    else {
        Set-AzSKPolicySettings -OnlinePolicyStoreUrl $OnlinePolicyStoreUrl
    }    
	Set-AzSKPrivacyNoticeResponse -AcceptPrivacyNotice "yes" #Accepting EULA and privacy as CA will be running in non-interactive mode and user has setup the CA with accepted privacy notice

    PublishEvent -EventName "CA Scan Started" -Properties @{
        "ResourceGroupNames"       = $ResourceGroupNames; `
            "OnlinePolicyStoreUrl" = $OnlinePolicyStoreUrl; `
            "OMSWorkspaceId"       = $OMSWorkspaceId;
    }

	CheckForSubscriptionsSnapshotData
	#Check if the central scan mode is enabled

        #Get the current storagecontext
        $existingStorage = Find-AzureRmResource -ResourceGroupNameEquals $StorageAccountRG -ResourceNameContains "azsk" -ResourceType "Microsoft.Storage/storageAccounts"
		if(($existingStorage|Measure-Object).Count -gt 1)
		{
			$existingStorage = $existingStorage[0]
			Write-Output ("Multiple storage accounts found in resource group. Using Storage Account: $($existingStorage.ResourceName) for storing logs")
		}

		#Create output files in storage		
		$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $StorageAccountRG -Name $existingStorage.ResourceName
		$centralStorageContext = New-AzureStorageContext -StorageAccountName $existingStorage.ResourceName -StorageAccountKey $keys[0].Value -Protocol Https
		if($Global:IsCentralMode)
		{
			try
			{
				Set-AzSKPolicySettings -EnableCentralScanMode
				$enableHldRetry = ($Global:activeScanObjects |Where-Object { $_.Status -in 'NA','INP'} | Measure-Object).Count -le 0
				$Global:activeScanObjects |Where-Object { $_.Status -notin 'ERR','COM'} |ForEach-Object {
					$activeScanObject = $_;
					$timeNow = [DateTime]::UtcNow
					$scanDuration= ($timeNow-[DateTime]$_.StartedTime).TotalHours
					$isScanAllowed=$false
					$preStatus="UNDEFINED"
					$postStatus="COM"


					if($_.Status -eq "NA"){$preStatus="INP"}
					elseif($_.Status -eq "INP" -and $scanDuration -ge $MaxScanHours){$preStatus="HLD"}
					elseif($_.Status -eq "HLD" -and $enableHldRetry){$preStatus="HLDRETRY"}
					elseif($_.Status -eq "HLDRETRY"){$preStatus="ERR"}

					if($preStatus -in ("HLDRETRY","INP") -or (($_.Status -eq "INP") -and ($scanDuration -le $MaxScanHours)))
					{
						$isScanAllowed = $true
					}

					 $subId = $activeScanObject.SubscriptionId;
					Select-AzureRmSubscription -SubscriptionId $subId | Out-Null
						
					Write-Output ("Scan status details:")
					Write-Output ("Subscription id - " + $subId)
					Write-Output ("Existing status - "+ $_.Status)
					if($preStatus -ne 'UNDEFINED'){Write-Output ("New status - " + $preStatus)}
					Write-Output ("Scan allowed? - "+ $isScanAllowed) 
					Write-Output ("Post scan status - " + $postStatus)

					if($preStatus -ne 'UNDEFINED'){
						PersistSubscriptionSnapshot -SubscriptionID $subId -Status $preStatus -StorageContext $centralStorageContext 
					}
					if($isScanAllowed){
						"Started scan for the subscription: $subId"
						RunAzSKScanForASub -SubscriptionID $subId -LoggingOption $activeScanObject.LoggingOption -StorageContext $centralStorageContext 
						PersistSubscriptionSnapshot -SubscriptionID $subId -Status $postStatus -StorageContext $centralStorageContext 
						"Completed scan for the subscription: $subId"
					
					}
					
				}
				
			}			
			finally{
				Select-AzureRmSubscription -SubscriptionId $RunAsConnection.SubscriptionID | Out-Null
			}

		}
		else
		{
			RunAzSKScanForASub -SubscriptionID $RunAsConnection.SubscriptionID -LoggingOption "CentralSub" -StorageContext $centralStorageContext 
		}
}

function RunAzSKScanForASub
{
	param
	(
		$SubscriptionID,
		$LoggingOption,
        $StorageContext
	)
	$svtResultPath = [string]::Empty
    $subscriptionResultPath = [string]::Empty
    $parentFolderPath = [string]::Empty

    #------------------------------------Subscription scan----------------------------------------------------------------
    "Running command 'Get-AzSKSubscriptionSecurityStatus'"
    $subScanTimer = [System.Diagnostics.Stopwatch]::StartNew();
    PublishEvent -EventName "CA Scan Subscription Started"
    $subscriptionResultPath = Get-AzSKSubscriptionSecurityStatus -SubscriptionId $SubscriptionID -ExcludeTags "OwnerAccess" 

    #---------------------------Check subscription scan status--------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($subscriptionResultPath)) {
        PublishEvent -EventName "CA Scan Subscription Error" -Metrics @{"TimeTakenInMs" = $subScanTimer.ElapsedMilliseconds; "SuccessCount" = 0}
        "Subscription scan failed."
    }
    else {
        PublishEvent -EventName "CA Scan Subscription Completed" -Metrics @{"TimeTakenInMs" = $subScanTimer.ElapsedMilliseconds; "SuccessCount" = 1}
        "Subscription scan succeeded."
        $parentFolderPath = (Get-Item $subscriptionResultPath).parent.FullName
    }

    #-------------------------------------Resources Scan------------------------------------------------------------------

	"Running command 'Get-AzSKAzureServicesSecurityStatus'"
    $serviceScanTimer = [System.Diagnostics.Stopwatch]::StartNew();
    PublishEvent -EventName "CA Scan Services Started"
   
           $svtResultPath = Get-AzSKAzureServicesSecurityStatus -SubscriptionId $SubscriptionID -ResourceGroupNames $ResourceGroupNames -ExcludeTags "OwnerAccess" -UsePartialCommits
   
    #---------------------------Check resources scan status--------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($svtResultPath)) {
        "Azure resources scan failed."
        PublishEvent -EventName "CA Scan Services Error" -Metrics @{"TimeTakenInMs" = $serviceScanTimer.ElapsedMilliseconds; "SuccessCount" = 0}
    }
    else {
        "Azure resources scan succeeded."
        $parentFolderPath = (Get-Item $svtResultPath).parent.FullName
        PublishEvent -EventName "CA Scan Services Completed" -Metrics @{"TimeTakenInMs" = $serviceScanTimer.ElapsedMilliseconds; "SuccessCount" = 1}
    }
    #----------------------------------------Export reports to storage---------------------------------------------------
    if (![string]::IsNullOrWhiteSpace($subscriptionResultPath) -or ![string]::IsNullOrWhiteSpace($svtResultPath)) {
        #Check if storage account exists
        if($Global:IsCentralMode)
		{
			if($LoggingOption -ne "CentralSub")
			{
				$existingStorage = Find-AzureRmResource -ResourceGroupNameEquals $StorageAccountRG -ResourceNameContains "azsk" -ResourceType "Microsoft.Storage/storageAccounts"
				if(($existingStorage|Measure-Object).Count -gt 1)
				{
					$existingStorage = $existingStorage[0]
					Write-Output ("Multiple storage accounts found in resource group. Using Storage Account: $($existingStorage.ResourceName) for storing logs")
				}

				#Create output files in storage
				$archiveFilePath = "$parentFolderPath\AutomationLogs_" + $(Get-Date -format "yyyyMMdd_HHmmss") + ".zip"
				$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $StorageAccountRG -Name $existingStorage.ResourceName
				$localStorageContext = New-AzureStorageContext -StorageAccountName $existingStorage.ResourceName -StorageAccountKey $keys[0].Value -Protocol Https
				try {
					Get-AzureStorageContainer -Name $CAScanLogsContainerName -Context $localStorageContext -ErrorAction Stop | Out-Null
				}
				catch {
					New-AzureStorageContainer -Name $CAScanLogsContainerName -Context $localStorageContext | Out-Null
				}

				PersistToStorageAccount -StorageContext $localStorageContext -SubscriptionResultPath $subscriptionResultPath -SvtResultPath $svtResultPath -SubscriptionId $SubscriptionID
				PurgeOlderScanReports -StorageContext $localStorageContext
			}
			else
			{
				PersistToStorageAccount -StorageContext $StorageContext -SubscriptionResultPath $subscriptionResultPath -SvtResultPath $svtResultPath -SubscriptionId $SubscriptionID
				PurgeOlderScanReports -StorageContext $StorageContext
			}
		}
		else
		{
			PersistToStorageAccount -StorageContext $StorageContext -SubscriptionResultPath $subscriptionResultPath -SvtResultPath $svtResultPath -SubscriptionId $SubscriptionID
			PurgeOlderScanReports -StorageContext $StorageContext
		}

        #Clean-up of logs in automation sandbox
        if (![string]::IsNullOrWhiteSpace($svtResultPath)) {
            Remove-Item -Path $svtResultPath -Recurse -ErrorAction Ignore
        }
        if (![string]::IsNullOrWhiteSpace($subscriptionResultPath)) {
            Remove-Item -Path $subscriptionResultPath -Recurse -ErrorAction Ignore
        }
        if (![string]::IsNullOrWhiteSpace($archiveFilePath)) {
            Remove-Item -Path $archiveFilePath -Recurse -ErrorAction Ignore
        }
    }
}

function PersistToStorageAccount
{
	param(
		$StorageContext,
		$SubscriptionResultPath,
		$SvtResultPath,
		$SubscriptionId
	)
	if (![string]::IsNullOrWhiteSpace($SubscriptionResultPath) -or ![string]::IsNullOrWhiteSpace($SvtResultPath)) {
        
		#Check if the passed storagecontext is null. This would be in the case of default scenario i.e non preview mode
		$timeStamp=(Get-Date -format "yyyyMMdd_HHmmss")
		$archiveFilePath = "$parentFolderPath\AutomationLogs_" + $timeStamp + ".zip"
		$storageLocation="$AutomationAccountRG/$SubscriptionId/AutomationLogs_" + $timestamp + ".zip"
            
			try {			
				Get-AzureStorageContainer -Name $CAScanLogsContainerName -Context $StorageContext -ErrorAction Stop | Out-Null
			}
			catch {
				New-AzureStorageContainer -Name $CAScanLogsContainerName -Context $StorageContext | Out-Null
		}

		#Persist the files to the storage account using the passed storage context
        try {
            if (![string]::IsNullOrWhiteSpace($SvtResultPath)) {
                Compress-Archive -Path $SvtResultPath -CompressionLevel Optimal -DestinationPath $archiveFilePath -Update
            }
            if (![string]::IsNullOrWhiteSpace($SubscriptionResultPath)) {
                Compress-Archive -Path $SubscriptionResultPath -CompressionLevel Optimal -DestinationPath $archiveFilePath -Update
            }
            Set-AzureStorageBlobContent -File $archiveFilePath -Container $CAScanLogsContainerName -Context $StorageContext -Blob $storageLocation -ErrorAction Stop | Out-Null
            "Exported reports to storage $StorageAccountName"
            PublishEvent -EventName "CA Scan Reports Persisted" -Properties @{"StorageAccountName" = $StorageAccountName; "ArchiveFilePath" = $archiveFilePath } -Metrics @{"SuccessCount" = 1}
        }
        catch {
            "Could not export reports to storage $StorageAccountName"
            PublishEvent -EventName "CA Scan Reports Persist Error" -Properties @{"ErrorRecord" = ($_ | Out-String); "StorageAccountName" = $StorageAccountName; "ArchiveFilePath" = $archiveFilePath } -Metrics @{"SuccessCount" = 0}
            throw $_.Exception
        }        
    }
}

function PurgeOlderScanReports
{
	param(
		$StorageContext
	)
	$NotBefore = [DateTime]::Now.AddDays(-30);
	$OldLogCount = (Get-AzureStorageBlob -Container $CAScanLogsContainerName -Context $StorageContext | Where-Object { $_.LastModified -lt $NotBefore} | Measure-Object).Count

	Get-AzureStorageBlob -Container $CAScanLogsContainerName -Context $StorageContext | Where-Object { $_.LastModified -lt $NotBefore} | Remove-AzureStorageBlob -Force -ErrorAction SilentlyContinue

	if($OldLogCount -gt 0)
	{
		#Deleted successfully all the old reports
		Write-Output ("Removed all the scan logs/reports older than date: $($NotBefore.ToShortDateString()) from storage account: [$StorageAccountName]")
	}
}

function CheckForSubscriptionsSnapshotData()
{			
	try {
		$CAScanDataBlobName = "TargetSubs.json"	
		$CAActiveScanSnapshotBlobName = "ActiveScanTracker.json"
		
		if($StorageAccountRG -ne $AutomationAccountRG)
		{
			$CAScanDataBlobName = "$AutomationAccountRG\TargetSubs.json"	
			$CAActiveScanSnapshotBlobName = "$AutomationAccountRG\ActiveScanTracker.json"
		}
	

		$destinationFolderPath = $env:temp + "\AzSKTemp\"
		if(-not (Test-Path -Path $destinationFolderPath))
		{
			mkdir -Path $destinationFolderPath -Force
		}
		$CAActiveScanSnapshotBlobPath = "$destinationFolderPath\$CAActiveScanSnapshotBlobName"
		$CAScanDataBlobPath = "$destinationFolderPath\$CAScanDataBlobName"
		$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $StorageAccountRG  -Name $StorageAccountName
		$currentContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $keys[0].Value -Protocol Https
		#Fetch if there is any existing active scan snapshot
		$CAScanSourceDataBlobObject = Get-AzureStorageBlob -Container $CAMultiSubScanConfigContainerName -Blob $CAScanDataBlobName -Context $currentContext -ErrorAction SilentlyContinue
		if($null -eq $CAScanSourceDataBlobObject)
		{
			$Global:IsCentralMode = $false;
			return;
		}
		$CAScanDataBlobObject = Get-AzureStorageBlob -Container $CAMultiSubScanConfigContainerName -Blob $CAActiveScanSnapshotBlobName -Context $currentContext -ErrorAction SilentlyContinue 
		if($null -ne $CAScanDataBlobObject)
		{
			Get-AzureStorageBlobContent -Container $CAMultiSubScanConfigContainerName -Blob $CAActiveScanSnapshotBlobName -Context $currentContext -Destination $destinationFolderPath -Force | Out-Null
			$Global:activeScanObjects = [array](Get-ChildItem -Path $CAActiveScanSnapshotBlobPath -Force | Get-Content | ConvertFrom-Json)			
		}
		else
		{
			#Fetch the CA Scan objects
			$CAScanDataBlobObject = Get-AzureStorageBlob -Container $CAMultiSubScanConfigContainerName -Blob $CAScanDataBlobName -Context $currentContext -ErrorAction Stop | Out-Null
			Get-AzureStorageBlobContent -Container $CAMultiSubScanConfigContainerName -Blob $CAScanDataBlobName -Context $currentContext -Destination $destinationFolderPath -Force | Out-Null
			$CAScanDataBlobContent = Get-ChildItem -Path "$CAScanDataBlobPath" -Force | Get-Content | ConvertFrom-Json

			#Create the active snapshot from the ca scan objects
			$Global:activeScanObjects = @();
			if(($CAScanDataBlobContent | Measure-Object).Count -gt 0)
			{
				$CAScanDataBlobContent | ForEach-Object {
					$CAScanDataInstance = $_;
                    $out = "" | Select-Object SubscriptionId, Status, LoggingOption, CreatedTime, StartedTime, CompletedTime
                        $out.SubscriptionId = $CAScanDataInstance.SubscriptionId
                        $out.Status = "NA";
                        $out.LoggingOption = $CAScanDataInstance.LoggingOption;
                        $out.CreatedTime = [DateTime]::UtcNow.ToString('s');
                        $out.StartedTime = [DateTime]::MinValue.ToString('s');
                        $out.CompletedTime = [DateTime]::MinValue.ToString('s');
                        $Global:activeScanObjects += $out;
				}				
				$Global:activeScanObjects | ConvertTo-Json -Depth 10 | Out-File $CAActiveScanSnapshotBlobPath
				Set-AzureStorageBlobContent -File $CAActiveScanSnapshotBlobPath -Blob $CAActiveScanSnapshotBlobName -Container $CAMultiSubScanConfigContainerName -BlobType Block -Context $currentContext -Force
			}
		}
		if(($Global:activeScanObjects | Measure-Object).Count -gt 0)
		{
			$Global:IsCentralMode = $true;
		}
	}
	catch {
		PublishEvent -EventName "CA Scan Error-PreviewSnapshotComputation" -Properties @{ "ErrorRecord" = ($_ | Out-String) } -Metrics @{"TimeTakenInMs" = $scanAgentTimer.ElapsedMilliseconds; "SuccessCount" = 0}
		$Global:IsCentralMode = $false;
	}
}

function PersistSubscriptionSnapshot
{
	param(
		$SubscriptionID,
		$Status,
        $StorageContext
	)
	try {
		$CAActiveScanSnapshotBlobName = "ActiveScanTracker.json"
		$destinationFolderPath = $env:temp + "\AzSKTemp\"
		if($StorageAccountRG -ne $AutomationAccountRG)
		{
			$CAActiveScanSnapshotBlobName = "$AutomationAccountRG\ActiveScanTracker.json"
		}

		if(-not (Test-Path -Path $destinationFolderPath))
		{
			mkdir -Path $destinationFolderPath -Force
		}
		$CAActiveScanSnapshotBlobPath = "$destinationFolderPath\$CAActiveScanSnapshotBlobName"
		
		#Fetch if there is any existing active scan snapshot
		$CAScanDataBlobObject = Get-AzureStorageBlob -Container $CAMultiSubScanConfigContainerName -Blob $CAActiveScanSnapshotBlobName -Context $StorageContext -ErrorAction SilentlyContinue 
		if($null -ne $CAScanDataBlobObject)
		{
			Get-AzureStorageBlobContent -Container $CAMultiSubScanConfigContainerName -Blob $CAActiveScanSnapshotBlobName -Context $StorageContext -Destination $destinationFolderPath -Force | Out-Null
			$activeScanObjects = [array](Get-ChildItem -Path $CAActiveScanSnapshotBlobPath -Force | Get-Content | ConvertFrom-Json)

			$matchedSubId = $activeScanObjects | Where-Object {$_.SubscriptionId -eq $SubscriptionID}
			if(($matchedSubId | Measure-Object).Count -gt 0)
			{
				$matchedSubId[0].SubscriptionId = $SubscriptionID
				$matchedSubId[0].Status = $Status;
				if($Status -eq "COM")
				{
					$matchedSubId[0].CompletedTime = [DateTime]::UtcNow.ToString('s');
				}
				elseif($Status -eq "INP")
				{
					$matchedSubId[0].StartedTime = [DateTime]::UtcNow.ToString('s');
				}
				
			}
			if($Status -eq "ERR")
			{
				"Unable to scan subscription (ID: $SubscriptionID). Continuing job..."
			}
			
			$activeScanObjects | ConvertTo-Json -Depth 10 | Out-File $CAActiveScanSnapshotBlobPath
			Set-AzureStorageBlobContent -File $CAActiveScanSnapshotBlobPath -Blob $CAActiveScanSnapshotBlobName -Container $CAMultiSubScanConfigContainerName -BlobType Block -Context $StorageContext -Force

			if(($activeScanObjects | Where-Object { $_.Status -notin ("COM","ERR")} | Measure-Object).Count -eq 0)
			{
				$errSubsCount = ($activeScanObjects | Where-Object { $_.Status -eq "ERR"} | Measure-Object).Count
				if($errSubsCount -gt 0)
				{
					"Archiving ActiveScanTracker.json"	
					ArchiveBlob -StorageContext $StorageContext
					Write-Output ("Scan is incomplete for $errSubsCount subscription(s). Refer subscriptions with 'ERR' state in $AutomationAccountRG -> $($StorageContext.StorageAccountName) -> $CAMultiSubScanConfigContainerName -> Archive -> ActiveScanTracker_<timestamp>.ERR.json.")
				}
				"Removing ActiveScanTracker.json"
				Remove-AzureStorageBlob -Container $CAMultiSubScanConfigContainerName -Blob $CAActiveScanSnapshotBlobName -Context $StorageContext -Force
			}
		}
	}
	catch {
		PublishEvent -EventName "CA Scan Error-PreviewSnapshotPersist" -Properties @{ "ErrorRecord" = ($_ | Out-String) } -Metrics @{"TimeTakenInMs" = $scanAgentTimer.ElapsedMilliseconds; "SuccessCount" = 0}
		$Global:IsCentralMode = $false;
	}
}

function ArchiveBlob
	{
		param(
        $StorageContext
		)
	
		try
		{
			$activeSnapshotBlob="ActiveScanTracker"
			$ArchiveTemp = $env:temp + "\AzSKTemp\Archive"
			if(-not (Test-Path -Path $ArchiveTemp))
			{
				mkdir -Path $ArchiveTemp -Force
			}			
		
			$archiveName =  $activeSnapshotBlob + "_" +  (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss") + ".ERR.json";
			$masterFilePath = "$ArchiveTemp\$archiveName"
			$CAActiveScanSnapshotArchiveBlobName = "Archive\$archiveName"
			if($StorageAccountRG -ne $AutomationAccountRG)
			{
				$CAActiveScanSnapshotArchiveBlobName = "$AutomationAccountRG\Archive\$archiveName"
			}
			$activeSnapshotBlob = Get-AzureStorageBlob -Container $CAMultiSubScanConfigContainerName -Context $StorageContext -Blob ($activeSnapshotBlob+".json") -ErrorAction SilentlyContinue
			if($null -ne $activeSnapshotBlob)
			{
				Get-AzureStorageBlobContent -CloudBlob $activeSnapshotBlob.ICloudBlob -Context $StorageContext -Destination $masterFilePath -Force | Out-Null			
				Set-AzureStorageBlobContent -File $masterFilePath -Container $CAMultiSubScanConfigContainerName -Blob $CAActiveScanSnapshotArchiveBlobName -BlobType Block -Context $StorageContext -Force
			}
		}
		catch
		{
			#eat exception as archive should not impact actual flow
			"Not able to archive active scan tracker" 
		}
	}

function UpdateAlertMonitoring
{
	param
	(   
	    $SubscriptionID,
		$DisableAlertRunbook,
		$AlertRunBookFullName,
		$ResourceGroup		
	)
	try
	{
	  if($DisableAlertRunbook)
	  {
        Remove-AzSKAlertMonitoring -SubscriptionId $SubscriptionID
		PublishEvent -EventName "Alert Monitoring Disabled" -Properties @{ "SubscriptionId" = $SubscriptionID }
	  }
	  else
	  {
	    $AlertRunbookPresent= Get-AzureRmAutomationRunbook -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroup -Name $AlertRunBookFullName -ErrorAction SilentlyContinue
	    if(-not $AlertRunbookPresent)
	    {
	      Set-AzSKAlertMonitoring -SubscriptionId $SubscriptionID -Force
		  PublishEvent -EventName "Alert Monitoring Enabled" -Properties @{ "SubscriptionId" = $SubscriptionID }
	    }
 	    else
		{		  
		  $ExistingWebhook=Get-AzureRmAutomationWebhook -RunbookName $AlertRunbookPresent.Name -ResourceGroup $ResourceGroup -AutomationAccountName $AlertRunbookPresent.AutomationAccountName
          if(($null -ne $ExistingWebhook) -and ((Get-Date).AddHours(24) -gt $ExistingWebhook.ExpiryTime.DateTime))
          {
             #update existing webhook for alert runbook
			 Set-AzSKAlertMonitoring -SubscriptionId $SubscriptionID
			 PublishEvent -EventName "Alert Monitoring Updated Webhook" -Properties @{ "SubscriptionId" = $SubscriptionID }
          }
		}
	  
	  }
	}
	catch
	{
	 PublishEvent -EventName "Alert Monitoring Error" -Properties @{ "ErrorRecord" = ($_ | Out-String) }
	}
}
try {
    #start timer
    $scanAgentTimer = [System.Diagnostics.Stopwatch]::StartNew();

    #config start
    $ResourceGroupNames = Get-AutomationVariable -Name "AppResourceGroupNames"
    $OMSWorkspaceId = Get-AutomationVariable -Name "OMSWorkspaceId"
    $OMSWorkspaceSharedKey = Get-AutomationVariable -Name "OMSSharedKey"
	$AltOMSWorkspaceId = Get-AutomationVariable -Name "AltOMSWorkspaceId" -ErrorAction SilentlyContinue
    $AltOMSWorkspaceSharedKey = Get-AutomationVariable -Name "AltOMSSharedKey" -ErrorAction SilentlyContinue
	$WebhookUrl = Get-AutomationVariable -Name "WebhookUrl" -ErrorAction SilentlyContinue
    $WebhookAuthZHeaderName = Get-AutomationVariable -Name "WebhookAuthZHeaderName" -ErrorAction SilentlyContinue
	$WebhookAuthZHeaderValue = Get-AutomationVariable -Name "WebhookAuthZHeaderValue" -ErrorAction SilentlyContinue
    $StorageAccountName = Get-AutomationVariable -Name "ReportsStorageAccountName"
    $DisableAlertRunbook = Get-AutomationVariable -Name "DisableAlertRunbook" -ErrorAction SilentlyContinue
	$AlertRunbookName="Alert_Runbook"
    $AzSKModuleName = "AzSK"
    $StorageAccountRG = "AzSKRG"
    $CAHelperScheduleName = "CA_Helper_Schedule"
	$CAMultiSubScanConfigContainerName = "ca-multisubscan-config"
	$CAScanLogsContainerName="ca-scan-logs"
	$MaxScanHours = 8
    ##config end

    #Set subscription id
    $SubscriptionID = $RunAsConnection.SubscriptionID
	$Global:IsCentralMode = $false;
	$Global:activeScanObjects = @();
    Select-AzureRmSubscription -SubscriptionId $SubscriptionID;
		
	if($Global:FoundExistingJob)
	{
		return;
	}

    $isAzSKAvailable = (Get-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG `
            -AutomationAccountName $AutomationAccountName `
            -Name $AzSKModuleName -ErrorAction SilentlyContinue | `
            Where-Object {$_.ProvisioningState -eq "Succeeded" -or $_.ProvisioningState -eq "Created"} | `
            Measure-Object).Count -gt 0
    if ($isAzSKAvailable) {
        Import-Module $AzSKModuleName
    }

    #Return if modules are not ready
    if ((Get-Command -Name "Get-AzSKAzureServicesSecurityStatus" -ErrorAction SilentlyContinue|Measure-Object).Count -eq 0) {
        "$AzSKModuleName module not available. Skipping AzSK scan. Will retry in the next run."
        PublishEvent -EventName "CA Job Skipped" -Properties @{"SubscriptionId" = $RunAsConnection.SubscriptionID} -Metrics @{"TimeTakenInMs" = $timer.ElapsedMilliseconds; "SuccessCount" = 1}
        return;
    }

	
	    #Scan and save results to storage
    RunAzSKScan

	if ($isAzSKAvailable) {
		#Remove helper schedule as AzSK module is available
		Remove-AzureRmAutomationSchedule -Name $CAHelperScheduleName -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName -Force
    }
   
    PublishEvent -EventName "CA Scan Completed" -Metrics @{"TimeTakenInMs" = $scanAgentTimer.ElapsedMilliseconds}

    #Call UpdateAlertMonitoring to setup or Remove Alert Monitoring Runbook
	try
	{	
	 UpdateAlertMonitoring -DisableAlertRunbook $DisableAlertRunbook -AlertRunBookFullName $AlertRunbookName -SubscriptionID $SubscriptionID -ResourceGroup $StorageAccountRG 
	}
	catch
	{
	  PublishEvent -EventName "Alert Monitoring Error" -Properties @{ "ErrorRecord" = ($_ | Out-String) }
	}
}
catch {
    PublishEvent -EventName "CA Scan Error" -Properties @{ "ErrorRecord" = ($_ | Out-String) } -Metrics @{"TimeTakenInMs" = $scanAgentTimer.ElapsedMilliseconds; "SuccessCount" = 0}
}