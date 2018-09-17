function ConvertStringToBoolean($strToConvert)
{
   if([bool]::TryParse($strToConvert, [ref] $strToConvert))
    {
        return $strToConvert
    }
    else
    {
        return $false
    }
}


function RunAzSKScan() {

	################################ Begin: Configure AzSK for the scan ######################################### 
	#set OMS settings
    if(-not [string]::IsNullOrWhiteSpace($OMSWorkspaceId) -and -not [string]::IsNullOrWhiteSpace($OMSWorkspaceSharedKey))
	{
		Set-AzSKOMSSettings -OMSWorkspaceID $OMSWorkspaceId -OMSSharedKey $OMSWorkspaceSharedKey -Source "CA"
	}
	#set alternate OMS if available
	if(-not [string]::IsNullOrWhiteSpace($AltOMSWorkspaceId) -and -not [string]::IsNullOrWhiteSpace($AltOMSWorkspaceSharedKey))
	{
		Set-AzSKOMSSettings -AltOMSWorkspaceId $AltOMSWorkspaceId -AltOMSSharedKey $AltOMSWorkspaceSharedKey -Source "CA"
	}
    #set webhook settings
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

	#If enableAADAuth... flag is ON, we will attempt to send an AAD token to the online policy store.
	#Else it is assumed that the policy store URL has a (SAS) token built-in.
    $EnableAADAuthForOnlinePolicyStore = ConvertStringToBoolean($EnableAADAuthForOnlinePolicyStore)
    if ($EnableAADAuthForOnlinePolicyStore) {
        Set-AzSKPolicySettings -OnlinePolicyStoreUrl $OnlinePolicyStoreUrl -EnableAADAuthForOnlinePolicyStore
    }
    else {
        Set-AzSKPolicySettings -OnlinePolicyStoreUrl $OnlinePolicyStoreUrl
    }

	# (Auto-)Accepting EULA and privacy as we are running in the background. The privacy consent here is 
	# implied because the end user who sets up CA would need to accept the EULA to run AzSK on their desktop.    
	Set-AzSKPrivacyNoticeResponse -AcceptPrivacyNotice "yes" 

	################################ End: Configure AzSK for the scan ######################################### 
    PublishEvent -EventName "CA Scan Started" -Properties @{
        "ResourceGroupNames"       = $ResourceGroupNames; `
            "OnlinePolicyStoreUrl" = $OnlinePolicyStoreUrl; `
            "OMSWorkspaceId"       = $OMSWorkspaceId;
    }

	#Check if the central scan mode is enabled. Read/prepare artefacts if so.
	#The $Global:IsCentralMode flag is enabled in this...also the target subs list is generated (called subsToScan)
    CheckForSubscriptionsSnapshotData
	
    #Get the current storagecontext
    $existingStorage = Get-AzureRmResource -ResourceGroupName $StorageAccountRG -Name "*azsk*" -ResourceType "Microsoft.Storage/storageAccounts"
	if(($existingStorage|Measure-Object).Count -gt 1)
	{
		$existingStorage = $existingStorage[0]
		Write-Output ("SA: Multiple storage accounts found in resource group. Using Storage Account: [$($existingStorage.Name)] for storing logs")
	}
	$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $StorageAccountRG -Name $existingStorage.Name

	#The 'centralStorageContext' always represents the parent subscription storage. 
	#In multi-sub scan this is the central sub. In single sub scan, this is just the storage in that sub.
	$centralStorageContext = New-AzureStorageContext -StorageAccountName $existingStorage.Name -StorageAccountKey $keys[0].Value -Protocol Https
	
    if($Global:IsCentralMode)
	{
		try
		{
			#This configures AzSK module to maintain separate partial scan data for target subs in Central CA and SDL mode.
			Set-AzSKPolicySettings -EnableCentralScanMode
			
			#Revisit HLD subs only after fresh/in-progress subs are done
			$enableHldRetry = ($Global:subsToScan |Where-Object { $_.Status -in 'NA','INP'} | Measure-Object).Count -le 0
			
			#Scan subs. Pick up only those which are not completed ('COM') or have not gone into error state ('ERR')
			$Global:subsToScan |Where-Object { $_.Status -notin 'ERR','COM'} |ForEach-Object {

				#Candidate sub to eval for scanning.
				$candidateSubToScan = $_;

				#How long have we already spent on this sub?
				$timeNow = [DateTime]::UtcNow
				$scanDuration= ($timeNow-[DateTime]$_.StartedTime).TotalHours

				#Initialize the flags...we determine their actual state further below.
				$isScanAllowed=$false
				$preScanStatus=""
				$postStatus="COM"

				#Possible status flows are [NA --> INP --> COM], [NA --> INP --> HLD --> HLDRETRY --> ERR or COM]
                <#status description:
                    NA = Sub scan not started
                    INP = Sub scan is in progress
                    COM = Sub scan completed
                    HLD = Scan attempted but it's kept on hold because scan taking more time than expected
                    HLDRETRY = Scan will be retried once 
                    ERR = Erroring out scan, retry itself also did not work 
                #>
				#$preScanStatus = potential next status for the current sub
				if($_.Status -eq "NA")
				{
					#Start of scan for this sub
					$preScanStatus="INP"
				}
				elseif($_.Status -eq "INP" -and $scanDuration -ge $MaxScanHours)
				{
					#If scan has been in-progress and maxHours have been consumed, put this sub on a hold ('HLD') list
					$preScanStatus="HLD"
				}
				elseif($_.Status -eq "HLD" -and $enableHldRetry)
				{	
					#If sub was on hold list and a retry is allowed, put this on hold-retry ('HLDRETRY') list
					$preScanStatus="HLDRETRY"
				}
				elseif($_.Status -eq "HLDRETRY")
				{
					#If the retry itself also did not work, we are doomed. We will put this in errored-out ('ERR') list.
					$preScanStatus="ERR"
				}
				else
				{
					$preScanStatus = "RES"
				}

				#We will actually attempt a scan for:
				#	1. HLDRETRY or fresh sub first scan
				#	2. Scan is in progress and max-duration has not been consumed
				if($preScanStatus -in ("HLDRETRY","INP") -or (($_.Status -eq "INP") -and ($scanDuration -le $MaxScanHours)))
				{
					$isScanAllowed = $true
				}

				#Let us switch context to the target subscription.
				$subId = $candidateSubToScan.SubscriptionId;
				Set-AzureRmContext -SubscriptionId $subId | Out-Null
					
				Write-Output ("SA: Scan status details:")
				Write-Output ("SA: Subscription id: [" + $subId + "]")
				
				if($preScanStatus -ne 'RES'){
					Write-Output ("SA: Existing status: ["+ $_.Status + "], New status: [" + $preScanStatus+ "], Scan allowed?: ["+ $isScanAllowed + "], Post scan status: [" + $postStatus + "]")
				}
				else{
					Write-Output ("SA: Existing status: ["+ $_.Status + "], Scan allowed?: ["+ $isScanAllowed + "], Post scan status: [" + $postStatus + "]")
				}

				# $preScanStatus will be 'RES' in case when scan is in progress and max-duration has not been consumed
				# We skip updating scan tracker in this scenario.
				if($preScanStatus -ne 'RES'){
					PersistSubscriptionSnapshot -SubscriptionID $subId -Status $preScanStatus -StorageContext $centralStorageContext 
				}

				if($isScanAllowed){
					Write-Output ("SA: Multi-sub Scan. Started scan for subscription: [$subId]")

					#In case of multi-sub scan logging option applies to all subs
					RunAzSKScanForASub -SubscriptionID $subId -LoggingOption $candidateSubToScan.LoggingOption -StorageContext $centralStorageContext 
					PersistSubscriptionSnapshot -SubscriptionID $subId -Status $postStatus -StorageContext $centralStorageContext 
					Write-Output ("SA: Multi-sub Scan. Completed scan for subscription: [$subId]")
				}		
			}
			
		}			
		finally{
			#Always return back to central subscription context.
			Set-AzureRmContext -SubscriptionId $RunAsConnection.SubscriptionID | Out-Null
		}
	}#IsCentralMode
	else
	{
		#Just the vanilla single-sub CA scan (individual CA setup)
		$subId = $RunAsConnection.SubscriptionID
		Write-Output ("SA: Single sub Scan. Starting scan for subscription: [$subId]")
		RunAzSKScanForASub -SubscriptionID $subId -LoggingOption "CentralSub" -StorageContext $centralStorageContext 
		Write-Output ("SA: Single sub Scan. Completed scan for subscription: [$subId]")
	}   
}

function RunAzSKScanForASub
{
	param
	(
		$SubscriptionID,	#This is the subscription to scan.
		$LoggingOption,		#Whether the scan logs to be stored within the target sub or central sub?
        $StorageContext		#This is the central sub storage context (which is same as target sub in case of individual mode CA)
	)
	$svtResultPath = [string]::Empty
    $gssResultPath = [string]::Empty
    $parentFolderPath = [string]::Empty

	#------------------------------------Clear session state to ensure updated policy settings are used-------------------
	Clear-AzSKSessionState

    #------------------------------------Subscription scan----------------------------------------------------------------
    Write-Output ("SA: Running command 'Get-AzSKSubscriptionSecurityStatus' (GSS) for sub: [$SubscriptionID]")
    $subScanTimer = [System.Diagnostics.Stopwatch]::StartNew();
    PublishEvent -EventName "CA Scan Subscription Started"
    $gssResultPath = Get-AzSKSubscriptionSecurityStatus -SubscriptionId $SubscriptionID -ExcludeTags "OwnerAccess" 

    #---------------------------Check subscription scan status--------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($gssResultPath)) 
    {
        PublishEvent -EventName "CA Scan Subscription Error" -Metrics @{"TimeTakenInMs" = $subScanTimer.ElapsedMilliseconds; "SuccessCount" = 0}
        Write-Output ("SA: Subscription scan failed.")
    }
    else 
    {
        PublishEvent -EventName "CA Scan Subscription Completed" -Metrics @{"TimeTakenInMs" = $subScanTimer.ElapsedMilliseconds; "SuccessCount" = 1}
        Write-Output ("SA: Subscription scan succeeded.")
        $parentFolderPath = (Get-Item $gssResultPath).parent.FullName
    }

    #-------------------------------------Resources Scan------------------------------------------------------------------

	
    $serviceScanTimer = [System.Diagnostics.Stopwatch]::StartNew();
    PublishEvent -EventName "CA Scan Services Started"

	if(-not [string]::IsNullOrWhiteSpace($ResourceGroupNamefromWebhook))
	{
		Write-Output ("SA: Running command 'Get-AzSKAzureServicesSecurityStatus' (GRS) on added resource for sub: [$SubscriptionID], RGs: [$ResourceGroupNamefromWebhook]")
		$rgname = $ResourceGroupNamefromWebhook | Out-string
		$svtResultPath = Get-AzSKAzureServicesSecurityStatus -SubscriptionId $SubscriptionID -ResourceGroupNames $rgname -ExcludeTags "OwnerAccess,RBAC"
	}
	elseif($null -eq $WebHookDataforResourceCreation)
	{
		Write-Output ("SA: Running command 'Get-AzSKAzureServicesSecurityStatus' (GRS) for sub: [$SubscriptionID], RGs: [$ResourceGroupNames]")
		$svtResultPath = Get-AzSKAzureServicesSecurityStatus -SubscriptionId $SubscriptionID -ResourceGroupNames "*" -ExcludeTags "OwnerAccess,RBAC" -UsePartialCommits
	}
   
    #---------------------------Check resources scan status--------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($svtResultPath)) 
    {
        Write-Output ("SA: Azure resources scan failed.")
        PublishEvent -EventName "CA Scan Services Error" -Metrics @{"TimeTakenInMs" = $serviceScanTimer.ElapsedMilliseconds; "SuccessCount" = 0}
    }
    else 
    {
        Write-Output ("SA: Azure resources scan succeeded.")
        $parentFolderPath = (Get-Item $svtResultPath).parent.FullName
        PublishEvent -EventName "CA Scan Services Completed" -Metrics @{"TimeTakenInMs" = $serviceScanTimer.ElapsedMilliseconds; "SuccessCount" = 1}
    }
	#----------------------------------------Export reports to storage---------------------------------------------------
	
	#If either of the scans (GSS/GRS) completed, let us save the results.
    if (![string]::IsNullOrWhiteSpace($gssResultPath) -or ![string]::IsNullOrWhiteSpace($svtResultPath)) 
    {
        if($Global:IsCentralMode)
		{
			if($LoggingOption -ne "CentralSub")
			{
				Write-Output ("SA: Multi-sub Scan. Storing scan results to child (target) subscription...")

				#save scan results in individual subs 
                $existingStorage = Get-AzureRmResource -ResourceGroupName $StorageAccountRG -Name "*azsk*" -ResourceType "Microsoft.Storage/storageAccounts"
				if(($existingStorage|Measure-Object).Count -gt 1)
				{
					$existingStorage = $existingStorage[0]
					Write-Output ("SA: Multiple storage accounts found in resource group. Using Storage Account: [$($existingStorage.Name)] for storing logs")
				}

				$archiveFilePath = "$parentFolderPath\AutomationLogs_" + $(Get-Date -format "yyyyMMdd_HHmmss") + ".zip"
				$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $StorageAccountRG -Name $existingStorage.Name
				$localStorageContext = New-AzureStorageContext -StorageAccountName $existingStorage.Name -StorageAccountKey $keys[0].Value -Protocol Https
				try {
					Get-AzureStorageContainer -Name $CAScanLogsContainerName -Context $localStorageContext -ErrorAction Stop | Out-Null
				}
				catch {
					New-AzureStorageContainer -Name $CAScanLogsContainerName -Context $localStorageContext | Out-Null
				}

				PersistToStorageAccount -StorageContext $localStorageContext -GssResultPath $gssResultPath -SvtResultPath $svtResultPath -SubscriptionId $SubscriptionID

				#remove scan reports older than one month
                PurgeOlderScanReports -StorageContext $localStorageContext
			}
			else
			{
				Write-Output ("SA: Multi-sub Scan. Storing scan results to central subscription...")
				PersistToStorageAccount -StorageContext $StorageContext -GssResultPath $gssResultPath -SvtResultPath $svtResultPath -SubscriptionId $SubscriptionID
				#remove scan reports older than one month
				PurgeOlderScanReports -StorageContext $StorageContext
			}
		}#IsCentralMode
		else
		{
			Write-Output ("SA: Single-sub Scan. Storing scan results to subscription...")
			PersistToStorageAccount -StorageContext $StorageContext -GssResultPath $gssResultPath -SvtResultPath $svtResultPath -SubscriptionId $SubscriptionID
			#remove scan reports older than one month
			PurgeOlderScanReports -StorageContext $StorageContext
		}

        #Clean-up of logs in automation sandbox (the automation VM)
        if (![string]::IsNullOrWhiteSpace($svtResultPath)) {
            Remove-Item -Path $svtResultPath -Recurse -ErrorAction Ignore
        }
        if (![string]::IsNullOrWhiteSpace($gssResultPath)) {
            Remove-Item -Path $gssResultPath -Recurse -ErrorAction Ignore
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
		$GssResultPath,
		$SvtResultPath,
		$SubscriptionId
	)
	if (![string]::IsNullOrWhiteSpace($GssResultPath) -or ![string]::IsNullOrWhiteSpace($SvtResultPath)) {
        
		#Check if the passed storagecontext is null. This would be in the case of default scenario i.e non central mode
		$timeStamp=(Get-Date -format "yyyyMMdd_HHmmss")
		$archiveFilePath = "$parentFolderPath\AutomationLogs_" + $timeStamp + ".zip"
		$storageLocation="$SubContainerName/$SubscriptionId/AutomationLogs_" + $timestamp + ".zip"
            
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
            if (![string]::IsNullOrWhiteSpace($GssResultPath)) {
                Compress-Archive -Path $GssResultPath -CompressionLevel Optimal -DestinationPath $archiveFilePath -Update
            }
            Set-AzureStorageBlobContent -File $archiveFilePath -Container $CAScanLogsContainerName -Context $StorageContext -Blob $storageLocation -ErrorAction Stop | Out-Null
            Write-Output ("SA: Exported reports to storage: [$StorageAccountName]")
            PublishEvent -EventName "CA Scan Reports Persisted" -Properties @{"StorageAccountName" = $StorageAccountName; "ArchiveFilePath" = $archiveFilePath } -Metrics @{"SuccessCount" = 1}
        }
        catch {
            Write-Output ("SA: Could not export reports to storage: [$StorageAccountName]. `r`nError details:" + ($_ | Out-String))
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
		Write-Output ("SA: Removed CA scan logs/reports older than date: [$($NotBefore.ToShortDateString())] from storage account: [$StorageAccountName]")
	}
}

#Used to determine if CA is setup with multi-subscription scanning. 
#If so, appropriate bookkeeping files are created/read.
function CheckForSubscriptionsSnapshotData()
{			
	try {
		$CATargetSubsBlobName = "TargetSubs.json"	
		$CAActiveScanSnapshotBlobName = "ActiveScanTracker.json"
		
		if($StorageAccountRG -ne $SubContainerName)
		{
			$CATargetSubsBlobName = "$SubContainerName\TargetSubs.json"	
			$CAActiveScanSnapshotBlobName = "$SubContainerName\ActiveScanTracker.json"
		}
	
		#Temporary working folder to download JSONs from storage in order to read progress/determine what to scan, etc.
		$destinationFolderPath = $env:temp + "\AzSKTemp\"
		if(-not (Test-Path -Path $destinationFolderPath))
		{
			mkdir -Path $destinationFolderPath -Force | Out-Null
		}

		$CAActiveScanSnapshotBlobPath = "$destinationFolderPath\$CAActiveScanSnapshotBlobName"
		$CATargetSubsBlobPath = "$destinationFolderPath\$CATargetSubsBlobName"

		$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $StorageAccountRG  -Name $StorageAccountName
		$currentContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $keys[0].Value -Protocol Https
		
		#Fetch TargetSubs blob from storage.
		$CAScanSourceDataBlobObject = Get-AzureStorageBlob -Container $CAMultiSubScanConfigContainerName -Blob $CATargetSubsBlobName -Context $currentContext -ErrorAction SilentlyContinue

		#If TargetSubs were NOT found, we are not operating in 'central-scan' mode
		if($null -eq $CAScanSourceDataBlobObject)
		{
			$Global:IsCentralMode = $false;
			return;
		}
		

		#See if some of the target subs have already been scanned or a scan is in progress
		$CAScanDataBlobObject = Get-AzureStorageBlob -Container $CAMultiSubScanConfigContainerName -Blob $CAActiveScanSnapshotBlobName -Context $currentContext -ErrorAction SilentlyContinue 
		if($null -ne $CAScanDataBlobObject)
		{
			Write-Output("SA: Multi-sub scan in progress. Reading progress tracking file...")
			#Found an active scan, download progress-tracker file to our temp location.
			Get-AzureStorageBlobContent -Container $CAMultiSubScanConfigContainerName -Blob $CAActiveScanSnapshotBlobName -Context $currentContext -Destination $destinationFolderPath -Force | Out-Null
			
			#Read the state of various subscriptions in the target list from the progress-tracker file.
			$Global:subsToScan = [array](Get-ChildItem -Path $CAActiveScanSnapshotBlobPath -Force | Get-Content | ConvertFrom-Json)			
		}
		else
		{
			Write-Output("SA: Multi-sub scan starting up. Creating new progress tracking file...")

			#No active scan in progress. This is likely the start of a fresh scan. 
			#We will need to *create* the progress-tracker file before starting the scan.
			$CAScanDataBlobObject = Get-AzureStorageBlob -Container $CAMultiSubScanConfigContainerName -Blob $CATargetSubsBlobName -Context $currentContext -ErrorAction Stop | Out-Null
			Get-AzureStorageBlobContent -Container $CAMultiSubScanConfigContainerName -Blob $CATargetSubsBlobName -Context $currentContext -Destination $destinationFolderPath -Force | Out-Null
	
			$CAScanDataBlobContent = Get-ChildItem -Path "$CATargetSubsBlobPath" -Force | Get-Content | ConvertFrom-Json

			#Create the active snapshot from the ca scan objects
			$Global:subsToScan = @();
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
                        $Global:subsToScan += $out;
				}				
				$Global:subsToScan | ConvertTo-Json -Depth 10 | Out-File $CAActiveScanSnapshotBlobPath
				Set-AzureStorageBlobContent -File $CAActiveScanSnapshotBlobPath -Blob $CAActiveScanSnapshotBlobName -Container $CAMultiSubScanConfigContainerName -BlobType Block -Context $currentContext -Force | Out-Null
			}
			Write-Output("SA: Multi-sub scan. New progress tracking file uploaded to container...")

		}
		if(($Global:subsToScan | Measure-Object).Count -gt 0)
		{
			$Global:IsCentralMode = $true;
		}
	}
	catch {
		Write-Output("SA: Unexpected error while reading multi-sub scan artefacts from storage...`r`nError details: "+ ($_ | Out-String))
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

		if($StorageAccountRG -ne $SubContainerName)
		{
			$CAActiveScanSnapshotBlobName = "$SubContainerName\ActiveScanTracker.json"
		}

		if(-not (Test-Path -Path $destinationFolderPath))
		{
			mkdir -Path $destinationFolderPath -Force | Out-Null
		}
		$CAActiveScanSnapshotBlobPath = "$destinationFolderPath\$CAActiveScanSnapshotBlobName"
		
		#Fetch if there is any existing active scan snapshot
		$CAScanDataBlobObject = Get-AzureStorageBlob -Container $CAMultiSubScanConfigContainerName -Blob $CAActiveScanSnapshotBlobName -Context $StorageContext -ErrorAction SilentlyContinue 
		if($null -ne $CAScanDataBlobObject)
		{
			#We found a blob for active scan... locate the provided subscription in it to update its status.
			Get-AzureStorageBlobContent -Container $CAMultiSubScanConfigContainerName -Blob $CAActiveScanSnapshotBlobName -Context $StorageContext -Destination $destinationFolderPath -Force | Out-Null
			$subsToScan = [array](Get-ChildItem -Path $CAActiveScanSnapshotBlobPath -Force | Get-Content | ConvertFrom-Json)

			$matchedSubId = $subsToScan | Where-Object {$_.SubscriptionId -eq $SubscriptionID}

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
					#This will never get double-called since we call only upon first time transition to 'INP'
					$matchedSubId[0].StartedTime = [DateTime]::UtcNow.ToString('s');
				}
				
				if($Status -eq "ERR")
				{
					Write-Output("SA: Unable to scan subscription: [$SubscriptionID]. Moving on to the next one...")					
				}
			}

			
			#Write the updated status back to the storage blob  
			$subsToScan | ConvertTo-Json -Depth 10 | Out-File $CAActiveScanSnapshotBlobPath
			Set-AzureStorageBlobContent -File $CAActiveScanSnapshotBlobPath -Blob $CAActiveScanSnapshotBlobName -Container $CAMultiSubScanConfigContainerName -BlobType Block -Context $StorageContext -Force | Out-Null

			#This is the last persist status. Archiving it for diagnosys purpose.
			if(($subsToScan | Where-Object { $_.Status -notin ("COM","ERR")} | Measure-Object).Count -eq 0)
			{
				$errSubsCount = ($subsToScan | Where-Object { $_.Status -eq "ERR"} | Measure-Object).Count

				if($errSubsCount -gt 0)
				{
					#We archive *only* if sub(s) went into 'ERR' status 
					Write-Output("SA: Archiving ActiveScanTracker.json as there were some errors...")
					ArchiveBlob -StorageContext $StorageContext
					Write-Output ("SA: Scan could not be completed for a total of [$errSubsCount] subscription(s).`nSee subscriptions with 'ERR' state in:`n`t $StorageAccountRG -> $($StorageContext.StorageAccountName) -> $CAMultiSubScanConfigContainerName -> Archive -> ActiveScanTracker_<timestamp>.ERR.json.")
				}
				Write-Output("SA: Multi-sub scan: Removing ActiveScanTracker.json")
				Remove-AzureStorageBlob -Container $CAMultiSubScanConfigContainerName -Blob $CAActiveScanSnapshotBlobName -Context $StorageContext -Force
			}
		}
	}
	catch {
		Write-Output("SA: Multi-sub Scan: An error occurred during persisting progress snapshot...`nError details:" + ($_ | Out-String) )
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
				mkdir -Path $ArchiveTemp -Force | Out-Null
			}			
		
			$archiveName =  $activeSnapshotBlob + "_" +  (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss") + ".ERR.json";
			$masterFilePath = "$ArchiveTemp\$archiveName"
			$CAActiveScanSnapshotArchiveBlobName = "Archive\$archiveName"
			if($StorageAccountRG -ne $SubContainerName)
			{
				$CAActiveScanSnapshotArchiveBlobName = "$SubContainerName\Archive\$archiveName"
			}
			$activeSnapshotBlob = Get-AzureStorageBlob -Container $CAMultiSubScanConfigContainerName -Context $StorageContext -Blob ($activeSnapshotBlob+".json") -ErrorAction SilentlyContinue
			if($null -ne $activeSnapshotBlob)
			{
				Get-AzureStorageBlobContent -CloudBlob $activeSnapshotBlob.ICloudBlob -Context $StorageContext -Destination $masterFilePath -Force | Out-Null			
				Set-AzureStorageBlobContent -File $masterFilePath -Container $CAMultiSubScanConfigContainerName -Blob $CAActiveScanSnapshotArchiveBlobName -BlobType Block -Context $StorageContext -Force | Out-Null
			}
		}
		catch
		{
			#eat exception as archive should not impact actual flow
			Write-Output("SA: Multi-sub Scan: Not able to archive active scan tracker")
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
	      Set-AzSKAlertMonitoring -SubscriptionId $SubscriptionID -Force | Out-Null
		  PublishEvent -EventName "Alert Monitoring Enabled" -Properties @{ "SubscriptionId" = $SubscriptionID }
	    }
 	    else
		{		  
		  $ExistingWebhook=Get-AzureRmAutomationWebhook -RunbookName $AlertRunbookPresent.Name -ResourceGroup $ResourceGroup -AutomationAccountName $AlertRunbookPresent.AutomationAccountName
          if(($null -ne $ExistingWebhook) -and ((Get-Date).AddHours(24) -gt $ExistingWebhook.ExpiryTime.DateTime))
          {
             #update existing webhook for alert runbook
			 Set-AzSKAlertMonitoring -SubscriptionId $SubscriptionID | Out-Null
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
function DisableHelperSchedules()
{
	Get-AzureRmAutomationSchedule -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName | `
	Where-Object {$_.Name -ilike "*$CAHelperScheduleName*"} | `
	Set-AzureRmAutomationSchedule -IsEnabled $false | Out-Null
	
}

#############################################################################################################
# Main ScanAgent code
#############################################################################################################
try {
    #start timer
    $scanAgentTimer = [System.Diagnostics.Stopwatch]::StartNew();
	Write-Output("SA: Scan agent starting...")

	#config start
	#Setup during Install-CA. These are the RGs that CA will scan. "*" is allowed.
	$ResourceGroupNames = Get-AutomationVariable -Name "AppResourceGroupNames"
	
	#Primary OMS WS info. This is mandatory. CA will send events to this WS.
    $OMSWorkspaceId = Get-AutomationVariable -Name "OMSWorkspaceId"
	$OMSWorkspaceSharedKey = Get-AutomationVariable -Name "OMSSharedKey"
	
	#Secondary/alternate WS info. This is optional. Facilitates federal/state type models.
	$AltOMSWorkspaceId = Get-AutomationVariable -Name "AltOMSWorkspaceId" -ErrorAction SilentlyContinue
	$AltOMSWorkspaceSharedKey = Get-AutomationVariable -Name "AltOMSSharedKey" -ErrorAction SilentlyContinue
	
	#CA can also optionally be configured to send events to a Webhook. 
	$WebhookUrl = Get-AutomationVariable -Name "WebhookUrl" -ErrorAction SilentlyContinue
    $WebhookAuthZHeaderName = Get-AutomationVariable -Name "WebhookAuthZHeaderName" -ErrorAction SilentlyContinue
	$WebhookAuthZHeaderValue = Get-AutomationVariable -Name "WebhookAuthZHeaderValue" -ErrorAction SilentlyContinue
	
	#This is the storage account where scan reports will be stored (in ZIP form)
	$StorageAccountName = Get-AutomationVariable -Name "ReportsStorageAccountName"

	#This is to enable/disable Alerts runbook. (Used if an org wants to collect alerts info from across subs.)
    $DisableAlertRunbook = Get-AutomationVariable -Name "DisableAlertRunbook" -ErrorAction SilentlyContinue
	$AlertRunbookName="Alert_Runbook"

	#Defaults.
    $AzSKModuleName = "AzSK"
	$StorageAccountRG = "AzSKRG"
	#In case of multiple CAs in single sub we use sub-container to host working files for each individual CA 
	#Sub-container has the same name as each CA automation account RG (hence guaranteed to be unique)
	$SubContainerName = $AutomationAccountRG
	
	$CAMultiSubScanConfigContainerName = "ca-multisubscan-config"
	$CAScanLogsContainerName="ca-scan-logs"
	
	#Max time we will spend to scan a single sub
	$MaxScanHours = 8
	
	##config end

	#We get sub id from RunAsConnection

	$SubscriptionID = $RunAsConnection.SubscriptionID
	$Global:IsCentralMode = $false;

	$Global:subsToScan = @();
    Set-AzureRmContext -SubscriptionId $SubscriptionID;
	
	#Another job is already running
	if($Global:FoundExistingJob)
	{
		Write-Output("SA: Found another job running. Returning from the current one...")
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
        
        PublishEvent -EventName "CA Job Skipped" -Properties @{"SubscriptionId" = $RunAsConnection.SubscriptionID} -Metrics @{"TimeTakenInMs" = $timer.ElapsedMilliseconds; "SuccessCount" = 1}
		Write-Output("SA: The module: {$AzSKModuleName} is not available/ready. Skipping AzSK scan. Will retry in the next run.")
		return;
    }
		
	#Scan and save results to storage
    RunAzSKScan
	if($null -eq $WebHookDataforResourceCreation)
	{
		if ($isAzSKAvailable) {
		#Remove helper schedule as AzSK module is available
		Write-Output("SA: Disabling helper schedule...")
		DisableHelperSchedules	
		}

		#Call UpdateAlertMonitoring to setup or Remove Alert Monitoring Runbook
		try
		{	
	 		UpdateAlertMonitoring -DisableAlertRunbook $DisableAlertRunbook -AlertRunBookFullName $AlertRunbookName -SubscriptionID $SubscriptionID -ResourceGroup $StorageAccountRG 
		}
		catch
		{
			  PublishEvent -EventName "Alert Monitoring Error" -Properties @{ "ErrorRecord" = ($_ | Out-String) }
			  Write-Output("SA: (Non-fatal) Error while updating Alert Monitoring setup...")
		}
	}
	
	PublishEvent -EventName "CA Scan Completed" -Metrics @{"TimeTakenInMs" = $scanAgentTimer.ElapsedMilliseconds}
	Write-Output("SA: Scan agent completed...")

}
catch {
	Write-Output("SA: Unexpected error during CA scan agent execution...`r`nError details: " + ($_ | Out-String))
    PublishEvent -EventName "CA Scan Error" -Properties @{ "ErrorRecord" = ($_ | Out-String) } -Metrics @{"TimeTakenInMs" = $scanAgentTimer.ElapsedMilliseconds; "SuccessCount" = 0}
}
