
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
			Write-Output("CS.o: Current provisioning state for module: [$ModuleName] is: [$($Module.ProvisioningState)]")
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
			Write-Output("CS.o: Downloading $ModuleName from $ModuleContentUrl")		
		}

        # Find the actual blob storage location of the Module
        do {
            $ActualUrl = $ModuleContentUrl
            $ModuleContentUrl = (Invoke-WebRequest -Uri $ModuleContentUrl -MaximumRedirection 0 -UseBasicParsing -ErrorAction Ignore).Headers.Location
        } while(!$ModuleContentUrl.Contains(".nupkg"))

		$ActualUrl = $ModuleContentUrl

		$retryCount = 0
		do{
            $AutomationModule = $null
            $retryCount++
            $AutomationModule = New-AzureRmAutomationModule `
            -ResourceGroupName $AutomationAccountRG `
            -AutomationAccountName $AutomationAccountName `
            -Name $ModuleName `
            -ContentLink $ActualUrl
		} while($null -eq $AutomationModule -and $retryCount -le 3)

		Write-Output("CS.o: Importing module: [$ModuleName] Version: [$ModuleVersion] into the CA automation account.")

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
					Write-Output ("CS.o: Failed to import: [$AutomationModule] into the automation account. Will retry in a bit.")
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
	if($ModuleName -imatch "AzSK*" )
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
			$ModuleVersion = "3.10.0"
		}
	}

	#######################################################################################################################
	#The code below is common for AzSK or other modules. However, in the case of AzSK, $ModuleVersion may already be set 
	#due to org preference to update to a specific (non-latest) version for their CA environment.

    #Build the query string for our module search.
    Write-Output ($ModuleVersion)
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
            Write-Error "CS.o: Could not find module: [$ModuleName] in gallery: $PSGalleryUrlComputed"
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
	Write-Output("CS.o: Creating required helper schedule(s)...")	
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
	Write-Output ("CS.o: Scheduled CA helper job :[$scheduleName]")
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

function IsScanComplete()
{
    $helperScheduleCount = (Get-AzureRmAutomationSchedule -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName -ErrorAction SilentlyContinue | `
    Where-Object {$_.Name -ilike "*$CAHelperScheduleName*"}|Measure-Object).Count
	return ($helperScheduleCount -gt 1 -and $helperScheduleCount -lt 4)
}

try
{
	#Check if this is fresh ICA (Profile version )
	$azskVersionForOrg = "#AzSKConfigURL#"
	#These get set as constants during the build process (e.g., AzSKStaging will have a diff URL)
	#PublicPSGalleryUrl is always same.
	$AzSKPSGalleryUrl = "https://www.powershellgallery.com"
	$PublicPSGalleryUrl = "https://www.powershellgallery.com"
	$isBaseProfileModule =  (Get-Module -Name AzureRm.Profile).Version.Major -lt 5
	$tags=@{};
	$RunbookVersion="";
	$RmRunbookVersion="3.1803.0";
	if($isBaseProfileModule)
	{
		try
		{
			$azskResourceGroup = Get-AzureRmResourceGroup -Name $AutomationAccountRG -ErrorAction SilentlyContinue;
			if(($azskResourceGroup | Measure-Object).Count -gt 0)
			{
				$tags = $azskResourceGroup.Tags;
                if($null -ne $tags)
                {
                    $RunbookVersionTag = $tags| Where-Object{ $_.Name -eq 'AzSKCARunbookVersion'}
                    $RunbookVersion = $RunbookVersionTag.Value
                }
				
			}
		}
		catch
		{
			Write-Output("Unable to fetch tags")
		}
		$retryDownloadIntervalMins = 15
		Write-Output ("CS.o: AzSK not fully ready to run. Creating helper schedule for another retry...")
		ScheduleNewJob -intervalInMins $retryDownloadIntervalMins
	}
	if(-not $isBaseProfileModule -or ($RunbookVersion -eq $RmRunbookVersion) )
	{
		$setupTimer = [System.Diagnostics.Stopwatch]::StartNew();
		PublishEvent -EventName "CA Setup Started"
		Write-Output("CS.o: Starting core setup...")
        Write-Output ("CS.o: Downloading AzureRm dependencies...")
		###Config start--------------------------------------------------
		$AzSKModuleName = "AzSK"
		$RunbookName = "Continuous_Assurance_Runbook"
		
		#These get set as constants during the build process (e.g., AzSKStaging will have a diff URL)
		#PublicPSGalleryUrl is always same.

		#This gets replaced when org-policy is created/updated. This is the org-specific
		#url that helps bootstrap which module version to use within an org setup

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
		$jobs = Get-AzureRmAutomationJob -Name $RunbookName -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName
		
		#Find out how many times has CA runbook run today for this account...
		$TodaysJobs = $jobs | Where-Object {$_.CreationTime.UtcDateTime.Date -eq $(get-date).ToUniversalTime().Date}
		
		#Under normal circumstances, we should not see too many runs on a single day within a CA setup
		#If that is what is happening, let us stop and also disable further retries on the same day.
		if($TodaysJobs.Count -gt 25)
		{
			Write-Error("CS.o: Daily job retry limit exceeded. Will disable retries for today. If this recurs each day, please contact your support team.")
			#The Scan_Schedule will attempt a retry again next day. 
			#We don't disable Scan_Schedule because then we won't have a way to 'auto-recover' CA setups.
			PublishEvent -EventName "CA Setup Fatal Error" -Properties @{"JobsCount"=$TodaysJobs.Count} -Metrics @{"TimeTakenInMs" =$setupTimer.ElapsedMilliseconds; "SuccessCount" = 0}
			
			#Disable the helper schedule
			DisableHelperSchedules
			return;
		}
		#Check if a scan job is already running. If so, we don't need to duplicate effort!
		$TotalJobsRunning = $jobs | Where-Object { $_.Status -in ("Queued", "Starting", "Resuming", "Running",  "Activating")}

		ScheduleNewJob -intervalInMins $monitorjobIntervalMins 
		$NoOfRecentActiveRunningJobs = 0    
		if(($TotalJobsRunning|Measure-Object).Count -gt 1)
		{
			$TotalJobsRunning|ForEach-Object{
				#Automation account should have terminated the job after 3hrs (current default behavior). If not, let us stop it.
				if(((GET-DATE).ToUniversalTime() - $_.StartTime.UtcDateTime).TotalMinutes -gt 210)
				{
					$jobId = $_.JobId
					try
					{           
						Stop-AzureRmAutomationJob -Id $jobId -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName                  
					}
					catch
					{
						#Eat exception as not able to stop the existing running job
						Write-Output ("CS.o: Error while stopping job [" + $jobId + "]")
					}
				}
				else
				{               
					$NoOfRecentActiveRunningJobs = $NoOfRecentActiveRunningJobs + 1             
				}
			}       
			
			#A job is already running. Let it take care of things....       
			if($NoOfRecentActiveRunningJobs -gt 1)
			{
				$Global:FoundExistingJob = $true;   
				return;
			}
		}

		#region: check modules health 
		#Examine the AzSK module(s) currently present in the automation account
		$azskmodules = @()
		$azskModules += Get-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG `
					-AutomationAccountName $AutomationAccountName `
					-ErrorAction SilentlyContinue | Where-Object { $_.Name -ilike "azsk*" }
		Write-Output ("CS.o: Looking for module: [$AzSKModuleName] in account: [$AutomationAccountName] in RG: [$AutomationAccountRG]")
		if($azskModules.Count -gt 1)
		{
			#Multiple modules! This anomaly can happen, for e.g., if someone setup AzSKPreview and then switched to AzSK (prod).
			#Clean up all AzSK* modules.
			Write-Output ("CS.o: Found mulitple AzSK* modules in the automation account. Cleaning them up and importing a fresh one.")
			$azskModules | ForEach-Object { Remove-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName -Name $_.Name -ErrorAction SilentlyContinue -Force }
		}
		elseif($azskModules.Count -eq 1 -and $azskModules[0].Name -ne $AzSKModuleName)
		{
			Write-Output ("CS.o: Found [$($azskModules[0].Name)] in the automation account when looking for: [$AzSKModuleName]. Cleaning it up and importing a fresh one.")
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
			Write-Output ("CS.o: Installed $AzSKModuleName version: [" + $azskModule.Version + "] in provisioning state: [" + $azskModule.ProvisioningState + "]. Expected version: [$desiredAzSKVersion]")
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
			Write-Output ("CS.o: Checking and importing missing modules into the automation account...");
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
			$syncModules = @("AzureRM.Profile", "AzureRM.Automation");
			$finalModuleList += $baseModuleList
			$finalModuleList += $ResultModuleList
			SetModules -ModuleList $finalModuleList -SyncModuleList $syncModules

			Write-Output("CS.o: Creating helper schedule for importing modules into the automation account...")
			ScheduleNewJob -intervalInMins $retryDownloadIntervalMins
		}
		#Let us be really sure AzSK is ready to run cmdlets before calling it done!
		elseif((Get-Command -Name "Get-AzSKAzureServicesSecurityStatus" -ErrorAction SilentlyContinue|Measure-Object).Count -eq 0)
		{
			Write-Output ("CS.o: AzSK not fully ready to run. Creating helper schedule for another retry...")
			ScheduleNewJob -intervalInMins $retryDownloadIntervalMins
		}
		else
		{
			Write-Output ("CS.o: CA core setup completed.")
			PublishEvent -EventName "CA Setup Succeeded" -Metrics @{"TimeTakenInMs" = $setupTimer.ElapsedMilliseconds;"SuccessCount" = 1}
		}	
	}	
	Write-Output ("CS.o: Checking if Az.Accounts and Az.Automation present in automation account.")
	PublishEvent -EventName "CA Az Stage1" -Properties @{"Description" = "Checking if Az.Accounts and Az.Automation present in automation account."  }
	$AzModule = Get-AzureRmAutomationModule `
    -ResourceGroupName $AutomationAccountRG `
    -AutomationAccountName $AutomationAccountName `
	-Name "Az.Accounts" -ErrorAction SilentlyContinue
	if(-not $AzModule)
	{
	DownloadModule -ModuleName Az.Accounts -ModuleVersion 1.2.1 -Sync $true
	}
	$AzModule = Get-AzureRmAutomationModule `
    -ResourceGroupName $AutomationAccountRG `
    -AutomationAccountName $AutomationAccountName `
	-Name "Az.Automation" -ErrorAction SilentlyContinue
	if(-not $AzModule)
	{
	DownloadModule -ModuleName Az.Automation -ModuleVersion 1.0.0 -Sync $true
	}
	PublishEvent -EventName "CA Setup Completed" -Metrics @{"TimeTakenInMs" = $setupTimer.ElapsedMilliseconds;"SuccessCount" = 1}
}
catch
{
	Write-Error("CS.o: Error during core setup: " + ($_ | Out-String))
	PublishEvent -EventName "CA Setup Error" -Properties @{ "ErrorRecord" = ($_ | Out-String) } -Metrics @{"TimeTakenInMs" =$setupTimer.ElapsedMilliseconds; "SuccessCount" = 0}
}
