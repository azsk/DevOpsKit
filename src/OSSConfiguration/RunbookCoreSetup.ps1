#telemetry functions

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
			"Current provisioning state for module $ModuleName is $($Module.ProvisioningState)"
		}
		#Check if module with specified version already exists
        elseif(CheckModuleVersion -ModuleName $ModuleName -ModuleVersion $ModuleVersion)
        {
            #$ModuleName + " is up to date in assets"
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

		"Importing "+ $ModuleName + " Version " + $ModuleVersion

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
                    Write-Error "Importing $AutomationModule Module to Automation failed."
					return;
                }
		}
    }

}

function CheckModuleVersion
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
	if($ModuleName -imatch "AzSK*")
	{
	        $PSGalleryUrlComputed = $AzSKPSGalleryUrl
			$isUpdateFlagTrue = $false
			$ModuleVersion =""
			if ([bool]::TryParse($UpdateToLatestVersion, [ref]$isUpdateFlagTrue)) 
			{
				$UpdateToLatestVersion = $isUpdateFlagTrue
    
			} else 
			{
				$UpdateToLatestVersion = $false
			}

			if((-not [string]::IsNullOrWhiteSpace($AzSKConfigURL)) -and (-not $UpdateToLatestVersion))
			{
				$uri = $global:ExecutionContext.InvokeCommand.ExpandString($AzSKConfigURL)
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
							}
						}
					}
					catch
					{
						# If unable to fetch server config file or module version property then continue and download latest version module.
					}
				}
			}
	}

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
            Write-Error "Could not find Module '$ModuleName'"
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
             # parse dependencies, which are in the format: Module1name:[Module1version]:|Module2name:[Module2version]
                for($index=0;($index -lt $dependencies.count) -and (![string]::IsNullOrWhiteSpace($dependencies[$index]));$index++)
				{
                    $dependencyModuleDetail = $dependencies[$index].Split(":")
					$dependencyModuleName = $dependencyModuleDetail[0]
					$dependencyModuleVersion = $dependencyModuleDetail[1].Replace('[','').Replace(']','')
					#Add dependent module to the result list
                    if(!$ResultModuleList.Contains($dependencyModuleName))
                    {
                        $tempList = [ordered]@{$dependencyModuleName=$dependencyModuleVersion}
                        $tempList+= $ResultModuleList
                        $ResultModuleList.Clear()
                        $tempList.Keys|ForEach-Object{$ResultModuleList.Add($_,$tempList.Item($_))}
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

try
{
	$setupTimer = [System.Diagnostics.Stopwatch]::StartNew();
	PublishEvent -EventName "CA Setup Started"

	#config start
	$AzSKModuleName = "AzSK"
	$RunbookName = "Continuous_Assurance_Runbook"
	$CAHelperScheduleName = "CA_Helper_Schedule"
	$AzSKPSGalleryUrl = "https://www.powershellgallery.com"
	$PublicPSGalleryUrl = "https://www.powershellgallery.com"
	$AzSKConfigURL = "https://azsdkossep.azureedge.net/1.0.0/AzSKConfig.json"
	$Global:FoundExistingJob = $false;
	#config end

	#initialize variables
	$ResultModuleList = [ordered]@{}
	$retryDownloadIntervalMins = 10
	$monitorjobIntervalMins = 45



	#Check for the error jobs count
	$jobs = Get-AzureRmAutomationJob -ResourceGroupName $AutomationAccountRG `
		-AutomationAccountName $AutomationAccountName -RunbookName $RunbookName | `
		Where-Object {$_.CreationTime.UtcDateTime.Date -eq $(get-date).ToUniversalTime().Date}
	if($jobs.Count -gt 25)
	{
		"Something went wrong while loading modules. Please contact AzSK support team."
		PublishEvent -EventName "CA Setup Fatal Error" -Properties @{"JobsCount"=$jobs.Count} -Metrics @{"TimeTakenInMs" =$setupTimer.ElapsedMilliseconds; "SuccessCount" = 0}
		#Disable the schedules 
		$helperSchedule = Get-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName `
		-ResourceGroupName $AutomationAccountRG -Name $CAHelperScheduleName -ErrorAction SilentlyContinue
		if(($helperSchedule|Measure-Object).Count -gt 0)
		{
			Set-AzureRmAutomationSchedule -Name $helperSchedule.Name -IsEnabled $false -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName | Out-Null
		}
		return;
	}
	
	#Check if scan job is already running
	$jobs = Get-AzureRmAutomationJob -Name $RunbookName -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName | Where-Object { $_.Status -in ("Queued", "Starting", "Resuming", "Running",  "Activating")}

	CreateHelperSchedule -nextRetryIntervalInMinutes $monitorjobIntervalMins
	if(($jobs|Measure-Object).Count -gt 1)
	{
		$jobs|ForEach-Object{
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
		if($Global:FoundExistingJob)
		{
			return;
		}
	}

	#region: check modules health 
	#check for the installed AzSK module
	$azskmodules = @()
	$azskModules += Get-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG `
	-AutomationAccountName $AutomationAccountName -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "azsk*" }
	if($azskModules.Count -gt 1)
	{
		#Not the intended state. Cleaning up all the azsk modules
		$azskModules | ForEach-Object { Remove-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName -Name $_.Name -ErrorAction SilentlyContinue -Force }
	}
	elseif($azskModules.Count -eq 1 -and $azskModules[0].Name -ne $AzSKModuleName)
	{
		Remove-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG -AutomationAccountName $AutomationAccountName -Name $azskModules[0].Name -ErrorAction SilentlyContinue -Force
	}

	#check health of existing azure modules
	$azureModules = Get-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG `
	-AutomationAccountName $AutomationAccountName `
	-ErrorAction SilentlyContinue

	$areAzureModulesUnhealthy= ($azureModules| Where-Object { $_.Name -like 'Azure*' -and -not ($_.ProvisioningState -eq "Succeeded" -or $_.ProvisioningState -eq "Created")} | Measure-Object).Count -gt 0

	$azskModule = Get-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG `
	-AutomationAccountName $AutomationAccountName `
	-Name $AzSKModuleName -ErrorAction SilentlyContinue

	$isAzSKAvailable = ($azskModule | Where-Object {$_.ProvisioningState -eq "Succeeded" -or $_.ProvisioningState -eq "Created"} | Measure-Object).Count -gt 0
	if($isAzSKAvailable)
	{
		Import-Module $AzSKModuleName
	}
	$isAzskLatest = CheckModuleVersion -ModuleName $AzSKModuleName
	$isSetupComplete = $isAzskLatest -and -not $areAzureModulesUnhealthy
	$azskSearchResult = SearchModule -ModuleName $AzSKModuleName
    $latestAzskVersion = $azskSearchResult.properties.Version
	#endregion

	#Telemetry
	PublishEvent -EventName "CA Setup Required Modules State" -Properties @{
	"ModuleStateAzSK"= $azskModule.ProvisioningState; `
	"InstalledModuleVersionAzSK"=$azskModule.Version; `
	"RequiredModuleVersionAzSK"=$latestAzskVersion; `
	"IsCompleteAzSK"=$isAzskLatest; `
	"IsComplete"=$isSetupComplete
	}

	Write-Output ("Checking and importing missing modules into the automation account...");

	#check if AzSK module is latest and Azure modules are available
	if(!$isSetupComplete)
	{		
		#Update all modules
		#Module list is in hashtable format : key = modulename , value = version (This is useful to fetch version of specific module by name)
		$finalModuleList = [ordered]@{}

		#Get dependencies of azsk module
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

		"Creating the interim scan schedule..."
		CreateHelperSchedule -nextRetryIntervalInMinutes $retryDownloadIntervalMins

	}
	#check if AzSK command is accessible
	elseif((Get-Command -Name "Get-AzSKAzureServicesSecurityStatus" -ErrorAction SilentlyContinue|Measure-Object).Count -eq 0)
	{
		"Creating the interim scan schedule..."
		CreateHelperSchedule -nextRetryIntervalInMinutes $retryDownloadIntervalMins
	}
	else
	{
		PublishEvent -EventName "CA Setup Succeeded" -Metrics @{"TimeTakenInMs" = $setupTimer.ElapsedMilliseconds;"SuccessCount" = 1}
	}	
	PublishEvent -EventName "CA Setup Completed" -Metrics @{"TimeTakenInMs" = $setupTimer.ElapsedMilliseconds;"SuccessCount" = 1}
}
catch
{
	PublishEvent -EventName "CA Setup Error" -Properties @{ "ErrorRecord" = ($_ | Out-String) } -Metrics @{"TimeTakenInMs" =$setupTimer.ElapsedMilliseconds; "SuccessCount" = 0}
}
