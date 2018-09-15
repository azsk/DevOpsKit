function SetModules
{
    param(
        [System.Collections.IDictionary] $ModuleList,
		[string[]] $SyncModuleList
    )
	$ModuleList.Keys | ForEach-Object{
	$ModuleName = $_
    $ModuleVersion = $ModuleList.Item($_)
    $Module = Get-AzureRmAutomationModule `
        -ResourceGroupName $AutomationAccountRG `
        -AutomationAccountName $AutomationAccountName `
        -Name $ModuleName -ErrorAction SilentlyContinue

    if(($Module | Measure-Object).Count -eq 0)
    {
		PublishEvent -EventName "CA Setup Modules" -Properties @{"ModuleName" = $ModuleName; "ModuleState"= "NotAvailable"; "RequiredModuleVersion"= $ModuleVersion}
		#Download module if it is not available
        DownloadModule -ModuleName $ModuleName -ModuleVersion $ModuleVersion -Sync ($SyncModuleList.Contains($ModuleName))
    }
    else
    {
		PublishEvent -EventName "CA Setup Modules" -Properties @{"ModuleName" = $ModuleName; "ModuleState"= $Module.ProvisioningState; "RequiredModuleVersion"= $ModuleVersion; "AvailableModuleVersion" = $Module.Version}
		#module is in extraction state
		if($Module.ProvisioningState -ne "Failed" -and $Module.ProvisioningState -ne "Succeeded" -and $Module.ProvisioningState -ne "Created")
		{
			Write-Output("CS: Current provisioning state for module: [$ModuleName] is: [$($Module.ProvisioningState)]")
		}
		#Check if module with specified version already exists
        elseif(IsModuleHealthy -ModuleName $ModuleName -ModuleVersion $ModuleVersion)
        {
            return
        }
        else
        {
			#Download required version
            DownloadModule -ModuleName $ModuleName -ModuleVersion $ModuleVersion -Sync ($SyncModuleList.Contains($ModuleName))
        }
    }
  }
}

function DownloadModule
{
    param(
         [string]$ModuleName,
		 [string]$ModuleVersion,
		 [bool] $Sync
    )
	$SearchResult = SearchModule -ModuleName $ModuleName -ModuleVersion $ModuleVersion
    if($SearchResult)
    {
        $ModuleName = $SearchResult.title.'#text' # get correct casing for the Module name
        $PackageDetails = Invoke-RestMethod -Method Get -UseBasicParsing -Uri $SearchResult.id
		$ModuleVersion = $PackageDetails.entry.properties.version

        #Build the content URL for the nuget package
        $ModuleContentUrl = "$PublicPSGalleryUrl/api/v2/package/$ModuleName/$ModuleVersion"

		#$ModuleName/$AzSK... etc. are defined in the core setup (start) code further below
		if($ModuleName -imatch "AzSK*")
		{
	        $ModuleContentUrl = "$AzSKPSGalleryUrl/api/v2/package/$ModuleName/$ModuleVersion"			
		}

        # Find the actual blob storage location of the Module
        do {
            $ActualUrl = $ModuleContentUrl
            $ModuleContentUrl = (Invoke-WebRequest -Uri $ModuleContentUrl -MaximumRedirection 0 -UseBasicParsing -ErrorAction Ignore).Headers.Location
        } while(!$ModuleContentUrl.Contains(".nupkg"))

		$ActualUrl = $ModuleContentUrl

		$retryCount = 0
		do{
			$retryCount++
			$AutomationModule = New-AzureRmAutomationModule `
					-ResourceGroupName $AutomationAccountRG `
					-AutomationAccountName $AutomationAccountName `
					-Name $ModuleName `
					-ContentLink $ActualUrl
		} while($null -eq $AutomationModule -and $retryCount -le 3)

		Write-Output("CS: Importing module: [$ModuleName] Version: [$ModuleVersion] into the CA automation account.")

		if($Sync)
		{
		 while(
                $AutomationModule.ProvisioningState -ne "Created" -and
                $AutomationModule.ProvisioningState -ne "Succeeded" -and
                $AutomationModule.ProvisioningState -ne "Failed"
                )
                {
                    #Module is in extracting state
                    Start-Sleep -Seconds 120
                    $AutomationModule = $AutomationModule | Get-AzureRmAutomationModule
                }
                if($AutomationModule.ProvisioningState -eq "Failed")
                {
					Write-Output ("CS: Failed to import: [$AutomationModule] into the automation account. Will retry in a bit.")
					return;
                }
		}
    }

}

#Checks if the desired module (version) is already present and ready in the automation account so we don't have to download it...
function IsModuleHealthy
{
    param(
        [string] $ModuleName,
		[string] $ModuleVersion
    )
	$SearchResult = SearchModule -ModuleName $ModuleName -ModuleVersion $ModuleVersion
    $Module = Get-AzureRmAutomationModule `
        -ResourceGroupName $AutomationAccountRG `
        -AutomationAccountName $AutomationAccountName `
        -Name $ModuleName -ErrorAction SilentlyContinue

	if(($Module | Measure-Object).Count -eq 0)
	{
		#Module is not available
		return $false
	}
	else
	{
		#added condition to return false if module is not successfully extracted
		return ((($Module.ProvisioningState -eq "Succeeded") -or ($Module.ProvisioningState -eq "Created")) -and ($SearchResult.properties.Version -eq $Module.Version))
	}
}

function SearchModule
{
     param(
            [string] $ModuleName,
			[string] $ModuleVersion
        )
	$url =""
	
	$PSGalleryUrlComputed = $PublicPSGalleryUrl

	#We need to consider AzSK separately because there are various choices/settings that may decide exactly which
	#version of AzSK is used (e.g., prod/staging/preview) and where from (ps gallery/staging gallery, etc.)
	if($ModuleName -imatch "AzSK*")
	{
		#assign environmment specific gallery URL
		$PSGalleryUrlComputed = $AzSKPSGalleryUrl
		$ModuleVersion =""

		#set UpdateToLatestVersion variable's default value as false if it's not defined in caller runbook

		#This code considers the possibility that the outer runbook is an older version and is unaware 
		#of this flag (introduced in recent runbook)
		$isUpdateFlagTrue = $false
		if([bool]::TryParse($UpdateToLatestVersion, [ref]$isUpdateFlagTrue)) 
		{
			$UpdateToLatestVersion = $isUpdateFlagTrue
		} 
		else 
		{
			$UpdateToLatestVersion = $false
		}

		#If org policy owner does not wish to migrate to latest AzSK, we need to check 
		#on their policy endpoint to determine which version... (in AzSKConfig.JSON)
		if((-not [string]::IsNullOrWhiteSpace($azskVersionForOrg)) -and (-not $UpdateToLatestVersion))
		{
			#Download AzSKConfig.JSON to get the desired AzSK module version
			$uri = $global:ExecutionContext.InvokeCommand.ExpandString($azskVersionForOrg)
			Write-Output("CS: Reading specific AzSK version to use in CA from org settings at: [$uri]")

			[System.Uri] $validatedUri = $null;
			if([System.Uri]::TryCreate($uri, [System.UriKind]::Absolute, [ref] $validatedUri))
			{
				try
				{
					$serverFileContent = Invoke-RestMethod `
												-Method GET `
												-Uri $validatedUri `
												-UseBasicParsing

					if($null -ne $serverFileContent)
					{
						if(-not [string]::IsNullOrWhiteSpace($serverFileContent.CurrentVersionForOrg))
						{
							$ModuleVersion = $serverFileContent.CurrentVersionForOrg
							Write-Output("CS: Desired AzSK version: [$ModuleVersion]")
						}
					}
				}
				catch
				{
					# If unable to fetch server config file or module version property then continue and download latest version module.
					Write-Output("CS: Failed in the attempt to fetch the org-specific AzSK version from org policy location: [$validatedUri]")
					Write-Output("CS: Attempting to get the latest version of AzSK from PSGallery as fallback.")
				}
			}
		}
	}

	#######################################################################################################################
	#The code below is common for AzSK or other modules. However, in the case of AzSK, $ModuleVersion may already be set 
	#due to org preference to update to a specific (non-latest) version for their CA environment.

	#Build the query string for our module search.
	if([string]::IsNullOrWhiteSpace($ModuleVersion))
	{
		$queryString = "`$filter=IsLatestVersion&searchTerm=%27$ModuleName%27&includePrerelease=false&`$skip=0&`$top=40&`$orderby=Version%20desc"
	}
	else
	{
		$queryString = "searchTerm=%27$ModuleName%27&includePrerelease=false&`$filter=Version%20eq%20%27$ModuleVersion%27"
	}
	$url = "$PSGalleryUrlComputed/api/v2/Search()?$queryString"
	
    $SearchResult = Invoke-RestMethod -Method Get -Uri $url -UseBasicParsing

    if(!$SearchResult)
    {
            Write-Error "CS: Could not find module: [$ModuleName] in gallery: $PSGalleryUrlComputed"
            return $null
    }
    else
    {
        $SearchResult = $SearchResult | Where-Object -FilterScript {
                return $_.title.'#text' -eq $ModuleName
        }
		#filter for module version
        if(![string]::IsNullOrWhiteSpace($ModuleVersion)) {
                $SearchResult = $SearchResult | Where-Object -FilterScript {
                    return $_.properties.version -eq $ModuleVersion
            }
        }
        return $SearchResult
    }
}

function AddDependentModules
{
     param(
         $InputModuleList
   )
    $InputModuleList.Keys | ForEach-Object{
    $moduleName = $_
	$moduleVersion = $InputModuleList.Item($_)
    $searchResult = SearchModule -ModuleName $moduleName -ModuleVersion $moduleVersion
    if($searchResult)
    {
         $packageDetails = Invoke-RestMethod -Method Get -UseBasicParsing -Uri $searchResult.id
         $dependencies = $packageDetails.entry.properties.dependencies
         if($dependencies)
         {
             $dependencies = $dependencies.Split("|")
             #parse dependencies, which are in the format: Module1name:[Module1version]:|Module2name:[Module2version]
                for($index=0;($index -lt $dependencies.count) -and (![string]::IsNullOrWhiteSpace($dependencies[$index]));$index++)
				{
                    $dependencyModuleDetail = $dependencies[$index].Split(":")
					$dependencyModuleName = $dependencyModuleDetail[0]
					$dependencyModuleVersion = $dependencyModuleDetail[1].Replace('[','').Replace(']','').Split(',')[0]
					
					#Add dependent module to the result list 
                    if(!$ResultModuleList.Contains($dependencyModuleName))
                    {
                        $tempList = [ordered]@{$dependencyModuleName=$dependencyModuleVersion}
                        $tempList+= $ResultModuleList
                        $ResultModuleList.Clear()
                        $tempList.Keys | ForEach-Object{$ResultModuleList.Add($_,$tempList.Item($_))}
                        AddDependentModules -InputModuleList @{$dependencyModuleName=$dependencyModuleVersion} | Out-Null
                    }
                 }
          }

          if(!$ResultModuleList.Contains($moduleName))
          {
             if([string]::IsNullOrWhiteSpace($moduleVersion))
		     {
			    $moduleVersion = $searchResult.properties.Version
		     }
		     $ResultModuleList.Add($moduleName,$moduleVersion)
          }
     }
   }
   return $ResultModuleList
}

function RemoveOnetimeHelperSchedule()
{
	$schedule = Get-AzureRmAutomationSchedule -Name $CAHelperScheduleName `
	-ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName `
	-ErrorAction SilentlyContinue
	
	if(($schedule | Measure-Object).Count -gt 0 -and ($schedule.Frequency -eq [Microsoft.Azure.Commands.Automation.Model.ScheduleFrequency]::Onetime))
	{
		Remove-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $CAHelperScheduleName -ResourceGroupName $AutomationAccountRG -Force -ErrorAction SilentlyContinue | Out-Null		
	}
}
function CreateNewScheduleIfNotExists($scheduleName,$startTime)
{
	$scheduleExists = (Get-AzureRmAutomationSchedule -Name $scheduleName `
	-ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName `
	-ErrorAction SilentlyContinue | Measure-Object).Count -gt 0 
	
	if(!$scheduleExists)
	{
		New-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $scheduleName `
                    -ResourceGroupName $AutomationAccountRG -StartTime $startTime `
					-HourInterval 1 -Description "This schedule ensures that CA activity initiated by the Scan_Schedule actually completes. Do not disable/delete this schedule." `
					-ErrorAction Stop | Out-Null
	}

	$isRegistered = (Get-AzureRmAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -ResourceGroupName $AutomationAccountRG `
						-RunbookName $RunbookName -ScheduleName $scheduleName -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
	if(!$isRegistered)
	{
		Register-AzureRmAutomationScheduledRunbook -RunbookName $RunbookName -ScheduleName $scheduleName `
		-ResourceGroupName $AutomationAccountRG `
		-AutomationAccountName $AutomationAccountName -ErrorAction Stop | Out-Null
	}
	
}
function CreateHelperSchedules()
{
	RemoveOnetimeHelperSchedule
	Write-Output("CS: Creating required helper schedule(s)...")	
	for($i = 1;$i -le 4; $i++)
	{
		$scheduleName = ""
		if($i -eq 1)
		{
			$scheduleName = $CAHelperScheduleName
		}
		else
		{
			$scheduleName = [string]::Concat($CAHelperScheduleName,"_$i")		
		}
		$startTime = $(get-date).AddMinutes(15*$i)
		CreateNewScheduleIfNotExists -scheduleName $scheduleName -startTime $startTime
	}
	DisableHelperSchedules
}

function DisableHelperSchedules()
{
	Get-AzureRmAutomationSchedule -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName | `
	Where-Object {$_.Name -ilike "*$CAHelperScheduleName*"} | `
	Set-AzureRmAutomationSchedule -IsEnabled $false | Out-Null
}
function DisableHelperSchedules($excludeSchedule)
{
	Get-AzureRmAutomationSchedule -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName | `
	Where-Object {$_.Name -ilike "*$CAHelperScheduleName*" -and $_.Name -ne $excludeSchedule} | `
	Set-AzureRmAutomationSchedule -IsEnabled $false | Out-Null
}
function FindNearestSchedule($intervalInMins)
{
	$desiredNextRun = $(get-date).ToUniversalTime().AddMinutes($intervalInMins)
	$finalSchedule = Get-AzureRmAutomationSchedule -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName -ErrorAction SilentlyContinue | `
	Where-Object {$_.Name -ilike "*$CAHelperScheduleName*" -and ($_.ExpiryTime.UtcDateTime -gt $(get-date).ToUniversalTime()) -and ($_.NextRun.UtcDateTime -ge $desiredNextRun)} | `
	Sort-Object -Property NextRun | Select-Object -First 1
    if(($finalSchedule|Measure-Object).Count -eq 0)
    {
        $finalSchedule = Get-AzureRmAutomationSchedule -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName -ErrorAction SilentlyContinue | `
        Where-Object {$_.Name -ilike "*$CAHelperScheduleName*" -and ($_.ExpiryTime.UtcDateTime -gt $(get-date).ToUniversalTime()) -and ($_.NextRun.UtcDateTime -le $desiredNextRun)} | `
        Sort-Object -Property NextRun -Descending | Select-Object -First 1
    }
    return $finalSchedule
}
function EnableHelperSchedule($scheduleName)
{
    if(($scheduleName|Measure-Object).Count -gt 1)
    {
        $scheduleName = $scheduleName[0]
    }
    #Enable only required schedule and disable others
	$enabledSchedule = Set-AzureRmAutomationSchedule -Name $scheduleName -AutomationAccountName $AutomationAccountName -ResourceGroupName $AutomationAccountRG -IsEnabled $true -ErrorAction SilentlyContinue
	if(($enabledSchedule|Measure-Object).Count -gt 0 -and $enabledSchedule.IsEnabled)
	{
		DisableHelperSchedules -excludeSchedule $scheduleName
	}
	Write-Output ("CS: Scheduled CA helper job :[$scheduleName]")
}
function ScheduleNewJob($intervalInMins)
{
	$finalSchedule = FindNearestSchedule -intervalInMins $intervalInMins
	if(($finalSchedule|Measure-Object).Count -gt 0)
	{
		EnableHelperSchedule -scheduleName $finalSchedule.Name
	}
	else
	{
		CreateHelperSchedules 
		$finalSchedule = FindNearestSchedule -intervalInMins $intervalInMins
		EnableHelperSchedule -scheduleName $finalSchedule.Name
	}
	PublishEvent -EventName "CA Job Rescheduled" -Properties @{"IntervalInMinutes" = $intervalInMins}
}

#region: Set of functions to validate and update expiring policy url token 
#Function to get string with RegEx pattern match
function GetSubString($cotentString, $pattern)
{
    return  [regex]::match($cotentString, $pattern).Groups[1].Value
}

#Validate if policy url update required for SAS token
function IsPolicyUrlUpdateRequired($policyUrl)
{
    [System.Uri] $validatedUri = $null;
    $IsSASTokenUpdateRequired = $false
    if([System.Uri]::TryCreate($policyUrl, [System.UriKind]::Absolute, [ref] $validatedUri) -and $validatedUri.Query.Contains("&se="))
    {
        $pattern = '&se=(.*?)T'
        [DateTime] $expiryDate = Get-Date 
        if([DateTime]::TryParse((GetSubString $($validatedUri.Query) $pattern),[ref] $expiryDate))
        {
            if($expiryDate.AddDays(-30) -lt [DateTime]::UtcNow)
            {
                $IsSASTokenUpdateRequired = $true
            }
        }
    }
    return $IsSASTokenUpdateRequired
}

#Get updated policy url 
function GetUpdatedPolicyUrl($policyUrl, $updateUrl)
{
    [System.Uri] $validatedUri = $null;
    $UpdatedUrl = $policyUrl
    if([System.Uri]::TryCreate($policyUrl, [System.UriKind]::Absolute, [ref] $validatedUri) -and $validatedUri.Query.Contains("&se=") -and [System.Uri]::TryCreate($policyUrl, [System.UriKind]::Absolute, [ref] $validatedUri))
    {
        $UpdatedUrl = $policyUrl.Split("?")[0] + "?" + $updateUrl.Split("?")[1]
    }
    return $UpdatedUrl
}

#Function to validate and update Org policy url SAS token 
function CheckAndUpdateExpiringPolicyUrl{
	try{
		#Create local temp directory to copy runbook
		$outputFolderPath = "$Env:LOCALAPPDATA"+"\" + $AzSKModuleName ;
		if(-not (Test-Path -Path $outputFolderPath))
		{
			mkdir -Path $outputFolderPath -Force -ErrorAction Stop | Out-Null
		}
		
		#Export runbook to local directory
		Export-AzureRmAutomationRunbook -Name $RunbookName -OutputFolder $outputFolderPath `
		-ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName `
		-Force -Slot Published | Out-Null

		$runbookFilePath = "$outputFolderPath\$RunbookName.ps1"
		$runbookContent = get-content $runbookFilePath
		
		$pattern = 'onlinePolicyStoreUrl = "(.*?)"'
		$policyStoreUrl = GetSubString $runbookContent $pattern
		$pattern = 'CoreSetupSrcUrl = "(.*?)"'
		$coreSetupUrl = GetSubString $runbookContent $pattern
		$isPolicyUrlUpdatedForSASToken= $false
    
		#Validate if SAS token update required for Org policy url
		if(IsPolicyUrlUpdateRequired $policyStoreUrl)
		{
		   $updatedPolicyUrl= GetUpdatedPolicyUrl $policyStoreUrl $azskVersionForOrg  
		   $runbookContent =  $runbookContent.Replace($policyStoreUrl,$updatedPolicyUrl)
		   $isPolicyUrlUpdatedForSASToken = $true
		}
	
		#Validate if SAS token update required for CoreSetup url
		if(IsPolicyUrlUpdateRequired $coreSetupUrl)
		{
			$updatedCoreSetupUrl= GetUpdatedPolicyUrl $coreSetupUrl $azskVersionForOrg  
			$runbookContent =  $runbookContent.Replace($coreSetupUrl,$updatedCoreSetupUrl)
			$isPolicyUrlUpdatedForSASToken = $true
		}
	
		#If SAS token is updated for policy urls then import latest runbook
		if($isPolicyUrlUpdatedForSASToken)
		{
			Write-Output ("CS: Found that runbook policy setup url SAS token is getting expired. Updating policy url with latest SAS token.")
			$runbookContent | Out-File $runbookFilePath -Encoding utf8 -Force
			#Remove existing runbook
			$existingRunbook = Get-AzureRmAutomationRunbook -AutomationAccountName $AutomationAccountName `
			-ResourceGroupName $AutomationAccountRG -RunbookName $RunbookName
			$existingRunbook | remove-azurermautomationrunbook -Force
		   
			#Import latest runbook
			$Description = "This runbook is responsible for running subscription health scan and resource scans (SVTs). It also keeps all modules up to date."
			
			Import-AzureRmAutomationRunbook -Name $RunbookName -Description $Description -Type 'PowerShell' `
			-Path $runbookFilePath `
			-LogProgress $false -LogVerbose $false `
			-AutomationAccountName $AutomationAccountName `
			-ResourceGroupName $AutomationAccountRG -Published -ErrorAction Stop | Out-Null
			Write-Output ("CS: Updated runbook policy url with latest SAS token.")
		}
	}
	catch
	{
		PublishEvent -EventName "CA Error For Policy Url Expiry Check" -Properties @{ "ErrorRecord" = ($_ | Out-String) } -Metrics @{"TimeTakenInMs" =$setupTimer.ElapsedMilliseconds; "SuccessCount" = 0}
	}
}
#endregion

function IsScanComplete()
{
	$helperScheduleCount = (Get-AzureRmAutomationSchedule -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName -ErrorAction SilentlyContinue | `
	Where-Object {$_.Name -ilike "*$CAHelperScheduleName*"}|Measure-Object).Count
	return ($helperScheduleCount -gt 1 -and $helperScheduleCount -lt 4)
}

try
{
	$setupTimer = [System.Diagnostics.Stopwatch]::StartNew();
	PublishEvent -EventName "CA Setup Started"
	Write-Output("CS: Starting core setup...")

	###Config start--------------------------------------------------
	$AzSKModuleName = "AzSK"
	$RunbookName = "Continuous_Assurance_Runbook"
	
	#These get set as constants during the build process (e.g., AzSKStaging will have a diff URL)
	#PublicPSGalleryUrl is always same.
	$AzSKPSGalleryUrl = "https://www.powershellgallery.com"
	$PublicPSGalleryUrl = "https://www.powershellgallery.com"
	
	#This gets replaced when org-policy is created/updated. This is the org-specific
	#url that helps bootstrap which module version to use within an org setup
	$azskVersionForOrg = "#AzSKConfigURL#"

	#We use this to check if another job is running...
	$Global:FoundExistingJob = $false;
	###Config end----------------------------------------------------


	#initialize variables
	$ResultModuleList = [ordered]@{}
	$retryDownloadIntervalMins = 10
	$monitorjobIntervalMins = 45
	$tempUpdateToLatestVersion = Get-AutomationVariable -Name UpdateToLatestAzSKVersion -ErrorAction SilentlyContinue
    if($null -ne $tempUpdateToLatestVersion)
    {
		$UpdateToLatestVersion = ConvertStringToBoolean($tempUpdateToLatestVersion)
	}
	#We get sub id from RunAsConnection
	$SubscriptionID = $RunAsConnection.SubscriptionID
	
	if(IsScanComplete)
	{
		CreateHelperSchedules
		return
	}

	#Find out how many times has CA runbook run today for this account...
	$jobs = Get-AzureRmAutomationJob -ResourceGroupName $AutomationAccountRG `
		-AutomationAccountName $AutomationAccountName -RunbookName $RunbookName | `
		Where-Object {$_.CreationTime.UtcDateTime.Date -eq $(get-date).ToUniversalTime().Date}
	
	
	#Under normal circumstances, we should not see too many runs on a single day within a CA setup
	#If that is what is happening, let us stop and also disable further retries on the same day.
	if($jobs.Count -gt 25)
	{
		Write-Error("CS: Daily job retry limit exceeded. Will disable retries for today. If this recurs each day, please contact your support team.")
		#The Scan_Schedule will attempt a retry again next day. 
		#We don't disable Scan_Schedule because then we won't have a way to 'auto-recover' CA setups.
		PublishEvent -EventName "CA Setup Fatal Error" -Properties @{"JobsCount"=$jobs.Count} -Metrics @{"TimeTakenInMs" =$setupTimer.ElapsedMilliseconds; "SuccessCount" = 0}
		
		#Disable the helper schedule
		DisableHelperSchedules
		return;
	}
	
	#Check if a scan job is already running. If so, we don't need to duplicate effort!
	$jobs = Get-AzureRmAutomationJob -Name $RunbookName -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName | Where-Object { $_.Status -in ("Queued", "Starting", "Resuming", "Running",  "Activating")}

	ScheduleNewJob -intervalInMins $monitorjobIntervalMins
	if(($jobs|Measure-Object).Count -gt 1)
	{
		$jobs|ForEach-Object{
			#Automation account should have terminated the job after 3hrs (current default behavior). If not, let us stop it.
			if(((GET-DATE).ToUniversalTime() - $_.StartTime.UtcDateTime).TotalMinutes -gt 210)
			{
				Stop-AzureRmAutomationJob -Id $_.JobId `
					-ResourceGroupName $AutomationAccountRG `
					-AutomationAccountName $AutomationAccountName
			}
			else
			{
				$Global:FoundExistingJob = $true;
			}
		}

		#A job is already running. Let it take care of things....
		if($Global:FoundExistingJob)
		{
			return;
		}
	}

	#region: check modules health 
	#Examine the AzSK module(s) currently present in the automation account
	$azskmodules = @()
	$azskModules += Get-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG `
						-AutomationAccountName $AutomationAccountName `
						-ErrorAction SilentlyContinue | Where-Object { $_.Name -ilike "azsk*" }  

	Write-Output ("CS: Looking for module: [$AzSKModuleName] in account: [$AutomationAccountName] in RG: [$AutomationAccountRG]")
	if($azskModules.Count -gt 1)
	{
		#Multiple modules! This anomaly can happen, for e.g., if someone setup AzSKPreview and then switched to AzSK (prod).
		#Clean up all AzSK* modules.
		Write-Output ("CS: Found mulitple AzSK* modules in the automation account. Cleaning them up and importing a fresh one.")
		$azskModules | ForEach-Object { Remove-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName -Name $_.Name -ErrorAction SilentlyContinue -Force }
	}
	elseif($azskModules.Count -eq 1 -and $azskModules[0].Name -ne $AzSKModuleName)
	{
		Write-Output ("CS: Found [$($azskModules[0].Name)] in the automation account when looking for: [$AzSKModuleName]. Cleaning it up and importing a fresh one.")
		Remove-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName -Name $azskModules[0].Name -ErrorAction SilentlyContinue -Force
	}

	#check health of various Azure PS modules (AzSK dependencies)
	$azureModules = Get-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG `
							-AutomationAccountName $AutomationAccountName `
							-ErrorAction SilentlyContinue

	#healthy modules will have 'ProvisioningState' == Succeeded or Created!
	$areAzureModulesUnhealthy= ($azureModules| Where-Object { $_.Name -like 'Azure*' -and -not ($_.ProvisioningState -eq "Succeeded" -or $_.ProvisioningState -eq "Created")} | Measure-Object).Count -gt 0

	$azskModule = Get-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG `
							-AutomationAccountName $AutomationAccountName `
							-Name $AzSKModuleName -ErrorAction SilentlyContinue

	$isAzSKAvailable = ($azskModule | Where-Object {$_.ProvisioningState -eq "Succeeded" -or $_.ProvisioningState -eq "Created"} | Measure-Object).Count -gt 0

	if($isAzSKAvailable)
	{
		Import-Module $AzSKModuleName
	}
	$isAzSKLatest = IsModuleHealthy -ModuleName $AzSKModuleName
	$isSetupComplete = $isAzSKLatest -and -not $areAzureModulesUnhealthy
	$azskSearchResult = SearchModule -ModuleName $AzSKModuleName
    $desiredAzSKVersion = $azskSearchResult.properties.Version  #Note this may not be literally the latest version if org-policy prefers otherwise!
	#endregion
	if($azskModule -and ($azskModule.Version -ne  $desiredAzSKVersion))
	{
		Write-Output ("CS: Installed $AzSKModuleName version: [" + $azskModule.Version + "] in provisioning state: [" + $azskModule.ProvisioningState + "]. Expected version: [$desiredAzSKVersion]")
	}
	#Telemetry
	PublishEvent -EventName "CA Setup Required Modules State" -Properties @{
	"ModuleStateAzSK"= $azskModule.ProvisioningState; `
	"InstalledModuleVersionAzSK"=$azskModule.Version; `
	"RequiredModuleVersionAzSK"=$desiredAzSKVersion; `
	"IsCompleteAzSK"=$isAzSKLatest; `
	"IsComplete"=$isSetupComplete
	}


	#If the automation account does not have all modules in expected state, we have some work to do...
	if(!$isSetupComplete)
	{		
		Write-Output ("CS: Checking and importing missing modules into the automation account...");
		#Module list is in hashtable format : key = modulename , value = version (This is useful to fetch version of specific module by name)
		$finalModuleList = [ordered]@{}

		#Get dependencies of AzSK module
		PublishEvent -EventName "CA Setup Computing Dependencies"
		AddDependentModules -InputModuleList @{$AzSKModuleName=""} | Out-Null

		#Azure modules to be downloaded first should be added first in finalModuleList
		$baseModuleList = [ordered]@{}
		$baseModuleList.Add("AzureRM.Profile",$ResultModuleList.Item("AzureRM.Profile"))
		$baseModuleList.Add("AzureRM.Automation",$ResultModuleList.Item("AzureRM.Automation"))
		$ResultModuleList.Remove("AzureRM.Profile")
		$ResultModuleList.Remove("AzureRM.Automation")
		$finalModuleList += $baseModuleList
		$finalModuleList += $ResultModuleList

		$syncModules = @("AzureRM.Profile", "AzureRM.Automation");
		SetModules -ModuleList $finalModuleList -SyncModuleList $syncModules

		Write-Output("CS: Creating helper schedule for importing modules into the automation account...")
		ScheduleNewJob -intervalInMins $retryDownloadIntervalMins

	}
	#Let us be really sure AzSK is ready to run cmdlets before calling it done!
	elseif((Get-Command -Name "Get-AzSKAzureServicesSecurityStatus" -ErrorAction SilentlyContinue|Measure-Object).Count -eq 0)
	{
		Write-Output ("CS: AzSK not fully ready to run. Creating helper schedule for another retry...")
		ScheduleNewJob -intervalInMins $retryDownloadIntervalMins
	}
	else
	{
		Write-Output ("CS: CA core setup completed.")
		PublishEvent -EventName "CA Setup Succeeded" -Metrics @{"TimeTakenInMs" = $setupTimer.ElapsedMilliseconds;"SuccessCount" = 1}
	}	
	#Validate and update expiring runbook polcy url with latest SAS token 
	CheckAndUpdateExpiringPolicyUrl
	PublishEvent -EventName "CA Setup Completed" -Metrics @{"TimeTakenInMs" = $setupTimer.ElapsedMilliseconds;"SuccessCount" = 1}
}
catch
{
	Write-Error("CS: Error during core setup: " + ($_ | Out-String))
	PublishEvent -EventName "CA Setup Error" -Properties @{ "ErrorRecord" = ($_ | Out-String) } -Metrics @{"TimeTakenInMs" =$setupTimer.ElapsedMilliseconds; "SuccessCount" = 0}
}