Set-StrictMode -Version Latest

class MigrationHelper 
{
	static [StorageHelper] $StorageAccountInstance;
	
	static [void] StartMigration([SubscriptionContext] $subscriptionContext, [PSObject] $InvocationContext, [string] $AzureADAppName)
	{
		[bool] $MigrateASC = $false;	
		[AIOrgTelemetryHelper]::CommonProperties= $subscriptionContext
		[PSObject] $MigrationOutput = @{}
		[bool] $ErrorOccurred = $false;
		try
		{
			[AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Started",$null, $null)
			if(-not [MigrationHelper]::MigrationPrerequisiteCheck($subscriptionContext.SubscriptionId))
			{
			    [AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Prerequisite Failed",$null, $null)
				return
			}

			Write-Host ([Constants]::DoubleDashLine + "`r`nUpdating your current subscription with latest policies along with migration of existing resources...`r`n" + [Constants]::DoubleDashLine) -ForegroundColor Cyan;

			#region clear any existing locks
			try
			{
				Write-Host ("Checking if there are any resource locks on old RG...") -ForegroundColor Yellow;

				$azsdkRGScope = "/subscriptions/$($subscriptionContext.SubscriptionId)/resourceGroups/$([OldConstants]::AzSDKRGName)"
				$resourceLocks = @();
				$resourceLocks += Get-AzureRmResourceLock -Scope $azsdkRGScope -ErrorAction Stop
				if($resourceLocks.Count -gt 0)
				{
					$resourceLocks | ForEach-Object {
						Remove-AzureRmResourceLock -LockId $_.LockId -Force
					}
					Write-Host ("Successfully removed the locks on old resource group.") -ForegroundColor Green;
				}
				else
				{
					Write-Host ("No locks found on old resource group.") -ForegroundColor Green;
				}
				$MigrationOutput.LockRemoval = "Success"
			}
			catch
			{
				Write-Host "An error occurred during removal of locks on old resource group: [$([OldConstants]::AzSDKRGName)]" -ForegroundColor Red
				[AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Error",@{ "StageName"= "Resource Group Lock"; "ErrorRecord" = ($_ | Out-String); "MigrationStatus"= ($MigrationOutput | Out-String) }, $null)
				$MigrationOutput.LockRemoval = "Failed. Message[$_]"
				$ErrorOccurred = $true;
				throw;
			}
			#endregion 

			#region capture the existing information
			$vars = $null
			$oldResourceGroupLocation = [ConfigurationManager]::GetAzSKConfigData().AzSKLocation;
			$scanIntervalInHours = 24;
			try
			{
				Write-Host ("Extracting current data from old resources...") -ForegroundColor Yellow;

				$oldRg = Get-AzureRmResourceGroup -Name $([OldConstants]::AzSDKRGName) -ErrorAction SilentlyContinue
				if($oldRg)
				{
					$oldResourceGroupLocation = $oldRg.Location;
				}
				$vars = Get-AzureRmAutomationVariable -ResourceGroupName $([OldConstants]::AzSDKRGName) -AutomationAccountName $([OldConstants]::AutomationAccountName) -ErrorAction SilentlyContinue
				$migrateCA = $true;
				if(($vars | Measure-Object).Count -eq 0)
				{
					$migrateCA = $false;
				}
				$newRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
				if($migrateCA)
				{
					$schedule = Get-AzureRmAutomationSchedule -Name $([Constants]::ScheduleName) -ResourceGroupName $newRGName -AutomationAccountName $([Constants]::AutomationAccountName) -ErrorAction SilentlyContinue
					if($null -ne $schedule -and $schedule.Frequency -eq 'Hour')
					{
						$scanIntervalInHours = $schedule.Interval
					}

					#extract CA scaling configuration data
					$caSubs = @();
					$storageAccounts = @();
					$storageAccounts += Get-AzureRmStorageAccount -ResourceGroupName $([OldConstants]::AzSDKRGName) -ErrorAction SilentlyContinue;
					if(($storageAccounts | Measure-Object).Count -gt 0)
					{
						$storageAccounts = $storageAccounts | Where-Object { $_.StorageAccountName -like "$([OldConstants]::StorageAccountPreName)*" } ;
						[CAScanModel[]] $scanobjects = @();
						$TargetSubscriptionIds = ""
						if(($storageAccounts | Measure-Object).Count -eq 1)
						{
							$AzSKTemp = [Constants]::AzSKAppFolderPath + "\Migration\CAScalingConfig";				
							if(-not (Test-Path "$AzSKTemp"))
							{
								mkdir -Path "$AzSKTemp" -ErrorAction Stop | Out-Null
							}
							else
							{
								Remove-Item -Path "$AzSKTemp\*" -Force -Recurse 
							}
							$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $([OldConstants]::AzSDKRGName) -Name $storageAccounts[0].StorageAccountName
							$currentContext = New-AzureStorageContext -StorageAccountName $storageAccounts[0].StorageAccountName -StorageAccountKey $keys[0].Value -Protocol Https
							$CAScanDataBlobObject = Get-AzureStorageBlob -Container $([OldConstants]::CAMultiSubScanConfigContainerName) -Blob $([Constants]::CATargetSubsBlobName) -Context $currentContext -ErrorAction SilentlyContinue 
							if($null -ne $CAScanDataBlobObject)
							{						
								$CAScanDataBlobContentObject = Get-AzureStorageBlobContent -Container $([OldConstants]::CAMultiSubScanConfigContainerName) -Blob $([Constants]::CATargetSubsBlobName) -Context $currentContext -Destination $AzSKTemp -Force
								$CAScanDataBlobContent = Get-ChildItem -Path "$AzSKTemp\$([Constants]::CATargetSubsBlobName)" -Force | Get-Content | ConvertFrom-Json

								#create the active snapshot from the ca scan objects					
								if(($CAScanDataBlobContent | Measure-Object).Count -gt 0)
								{

									$CAScanDataBlobContent | ForEach-Object {
										$CAScanDataInstance = $_;
										$scanobject = [CAScanModel]::new($CAScanDataInstance.SubscriptionId, $CAScanDataInstance.LoggingOption);
										$scanobjects += $scanobject;
										$caSubs += $CAScanDataInstance.SubscriptionId 
										$TargetSubscriptionIds = $TargetSubscriptionIds + "," + $CAScanDataInstance.SubscriptionId 							
									}
									$TargetSubscriptionIds = $TargetSubscriptionIds.SubString(1)
								}
							}
						}
					}

				}				
				Write-Host ("Successfully completed extracting current data from old resources.") -ForegroundColor Green;
				$MigrationOutput.CurrentDataExtraction = "Success"				
			}
			catch{
				Write-Host "An error while fetching the current data" -ForegroundColor Red
				[AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Error",@{ "StageName"= "Capture Existing Metadata"; "ErrorRecord" = ($_ | Out-String); "MigrationStatus"= ($MigrationOutput | Out-String) }, $null)
				$MigrationOutput.CurrentDataExtraction = "Failed. Message[$_]"
				$ErrorOccurred = $true;
				throw;
			}
			#endregion 

			#region attestation migration
			try
			{
				Write-Host ("Migrating the attestation data to new storage account...") -ForegroundColor Yellow;
				[MigrationHelper]::MigrateStorageToLatest($subscriptionContext.SubscriptionId, $oldResourceGroupLocation)
				Write-Host ("Successfully completed migrating the attestation data.") -ForegroundColor Green;
				$MigrationOutput.StorageDataMigration = "Success"
			}
			catch
			{
				Write-Host "An error occurred either during migration of attestation data to new storage account. See migration log for details." -ForegroundColor Red
				[AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Error",@{ "StageName"= "Attestation Migration"; "ErrorRecord" = ($_ | Out-String); "MigrationStatus"= ($MigrationOutput | Out-String) }, $null)
				$MigrationOutput.StorageDataMigration = "Failed. Message[$_]"
				$ErrorOccurred = $true;
				#eat the exception and continue with other migration
			}
			#endregion			

			#region alerts migration
			try
			{
				Write-Host ("Creating new alerts and cleaning up old ones...") -ForegroundColor Yellow;
				[MigrationHelper]::MigrateAlerts($subscriptionContext.SubscriptionId, $InvocationContext);
				Write-Host ("Successfully completed creating new alerts.") -ForegroundColor Green;
				$MigrationOutput.AlertsMigration = "Success"
			}
			catch
			{
				Write-Host "An error occurred either during creation of new alerts or removal of old ones. See migration log for details." -ForegroundColor Red
				[AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Error",@{ "StageName"= "Alert Setup"; "ErrorRecord" = ($_ | Out-String) }, $null)
				$MigrationOutput.AlertsMigration = "Failed. Message[$_]"
				$ErrorOccurred = $true;
				#eat the exception and continue with other migration
			}
			#endregion

			#region arm policies migration
			try
			{
				Write-Host ("Creating new policies and cleaning up olde ones...") -ForegroundColor Yellow;
				[MigrationHelper]::MigrateARMPolicies($subscriptionContext.SubscriptionId, $subscriptionContext.Scope, $InvocationContext);
				Write-Host ("Successfully completed creating new ARM policies.") -ForegroundColor Green;
				$MigrationOutput.ARMPoliciesMigration = "Success"
			}
			catch
			{
				Write-Host "An error occurred either during creation of new policies or removal of old ones. See migration log for details." -ForegroundColor Red
				[AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Error",@{ "StageName"= "ARM Policy Setup"; "ErrorRecord" = ($_ | Out-String); "MigrationStatus"= ($MigrationOutput | Out-String) }, $null)
				$MigrationOutput.ARMPoliciesMigration = "Failed. Message[$_]"
				$ErrorOccurred = $true;
				#eat the exception and continue with other migration
			}
			#endregion			

			#region update security center policies
			if($MigrateASC)
			{
				try
				{
					Write-Host ("Updating Security Center policies as per latest configuration...") -ForegroundColor Yellow;
					[MigrationHelper]::UpdateASC($subscriptionContext.SubscriptionId)
					Write-Host ("Successfully updated Security Center policies.") -ForegroundColor Green;
					$MigrationOutput.ASCUpdate = "Success"
				}
				catch
				{
					Write-Host "An error occurred during updation of Security Center policies as per latest configuration. See migration log for details." -ForegroundColor Red
					[AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Error",@{ "StageName"= "ASC Update"; "ErrorRecord" = ($_ | Out-String); "MigrationStatus"= ($MigrationOutput | Out-String) }, $null)
					$MigrationOutput.ASCUpdate = "Failed. Message[$_]"
					$ErrorOccurred = $true;
					#eat the exception and continue with other migration
				}
			}
			#endregion

			#region CA migration
			try
			{
				if($migrateCA)
				{
					Write-Host ("Installing CA using the latest module...") -ForegroundColor Yellow;
					[MigrationHelper]::MigrateAutomationAccountToLatest($subscriptionContext.SubscriptionId, $InvocationContext, $vars, $AzureADAppName, $scanIntervalInHours)					
					Remove-AzureRmAutomationAccount -ResourceGroupName $([OldConstants]::AzSDKRGName) -Name $([OldConstants]::AutomationAccountName) -Force
					[Helpers]::SetResourceGroupTags([OldConstants]::AzSDKRGName ,@{[OldConstants]::RunbookVersionTagName=""}, $true)
					Write-Host ("Successfully completed re-configuring CA.") -ForegroundColor Green;
				}
				else
				{
					$caresources = Find-AzureRmResource -ResourceNameEquals $([Constants]::AutomationAccountName)
					if(($caresources | Measure-Object).Count -eq 0)
					{						
						Write-Host ("The current subscription is not configured with CA.") -ForegroundColor Yellow;
					}
					else
					{
						Write-Host ("CA has been already migrated for this subscription.") -ForegroundColor Green;
					}
				}
				$MigrationOutput.CAMigration = "Success"
			}
			catch
			{
				Write-Host "An error occurred during CA migration. See migration log for details." -ForegroundColor Red
				[AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Error",@{ "StageName"= "CA Setup"; "ErrorRecord" = ($_ | Out-String); "MigrationStatus"= ($MigrationOutput | Out-String) }, $null)
				$MigrationOutput.CAMigration = "Failed. Message[$_]"
				$ErrorOccurred = $true;
				#eat the exception and continue with other migration
			}
			#endregion

			#region cleanup of old CA SPN			

			$subscriptionScope = "/subscriptions/{0}" -f $subscriptionContext.SubscriptionId

			$azskspnformatstring = "AzSDK_CA_SPN";
			$azskRoleAssignments = Get-AzureRmRoleAssignment -Scope $subscriptionScope -RoleDefinitionName Reader | Where-Object { $_.DisplayName -like "$($azskspnformatstring)*" }

			$azskRoleAssignments | ForEach-Object{
				$roleAssignment = $_
				#If you want to remove the role assignment then uncomment the following code.
				#Remove-AzureRmRoleAssignment -ObjectId $roleAssignment.ObjectId  -RoleDefinitionName "Reader"
				#Remove-AzureRmRoleAssignment -ObjectId $roleAssignment.ObjectId  -RoleDefinitionName "Contributor"
			}

			#endregion

			#region to warn about other resources
			$resources = Find-AzureRmResource -ResourceGroupNameEquals $([OldConstants]::AzSDKRGName) | Where-Object { -not ($_.Name -like "$([OldConstants]::StorageAccountPreName)*")}
			#filterout our resources
			if(($resources | Measure-Object).Count -gt 0)
			{
				$resourceString = [Helpers]::ConvertToPson($resources);
				Write-Host "We found resources which are not owned by AzSK. You need to migrate them to appropriate resource groups." -ForegroundColor Yellow
				Write-Host $resourceString
				$MigrationOutput.ResourcesToBeMigrated = "Failed. $resourceString"
			}
			else
			{
				$MigrationOutput.ResourcesToBeMigrated = "Success"
			}
			#endregion

			#region complete migration
			$MigrationOutput.ErrorOccurred = $ErrorOccurred
			if($MigrationOutput.ErrorOccurred -eq $false)
			{
				[MigrationHelper]::CompleteMigration($subscriptionContext.SubscriptionId, $MigrationOutput)
				#endregion					
				[AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Completed",@{ "MigrationStatus"= ($MigrationOutput | Out-String) }, $null)	
				write-host ([Constants]::SingleDashLine + "`r`nMigration completed successfully`r`n"+[Constants]::SingleDashLine) -ForegroundColor Green
			}
			else
			{
				[MigrationHelper]::PersistMigrationOutput($subscriptionContext.SubscriptionId, $MigrationOutput)
				[AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Not Completed",@{ "MigrationStatus"= ($MigrationOutput | Out-String) }, $null)	
				write-host ([Constants]::SingleDashLine + "`r`nAn error during migration, please retry again. If issue still continue please reach out to support team.`r`n"+[Constants]::SingleDashLine) -ForegroundColor Red
			}			
			
		}
		catch
		{
			$MigrationOutput.ErrorOccurred = $ErrorOccurred
			[AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Error",@{ "StageName"= "Migration Block"; "ErrorRecord" = ($_ | Out-String); "MigrationStatus"= ($MigrationOutput | Out-String) }, $null)
			[MigrationHelper]::RollBackMigration($subscriptionContext.SubscriptionId, $MigrationOutput)
			throw "Error occurred during migration. $($_.Exception)"
		}
	}

	static [void] UpdateASC([string] $SubscriptionId)
	{
		$secCenter = [SecurityCenter]::new($SubscriptionId);
		if ($secCenter) 
		{
			#calling the ASC policy method with default params i.e. without ASC security poc email and phone number
			$secCenter.SetPolicies();
		} 
	}

	static [void] SetupAzSKResources([string] $subscriptionId, [string] $location)
	{		
		$RGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		$storageAccountName = ([Constants]::StorageAccountPreName + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"))
		[MigrationHelper]::StorageAccountInstance = [StorageHelper]::new($subscriptionId, $RGName, $location, $storageAccountName);
		[MigrationHelper]::StorageAccountInstance.CreateStorageContainerIfNotExists([Constants]::AttestationDataContainerName)
		[MigrationHelper]::StorageAccountInstance.CreateStorageContainerIfNotExists([Constants]::CAScanOutputLogsContainerName)
		[MigrationHelper]::StorageAccountInstance.CreateStorageContainerIfNotExists([Constants]::CAScanProgressSnapshotsContainerName)		
	}
	static [void] RollBackMigration([string] $subscriptionId, [PSObject] $MigrationOutput)
	{
		try
		{
		#delete partially created resources
		[MigrationHelper]::PersistMigrationOutput($subscriptionId, $MigrationOutput);
		}
		catch
		{
			[AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Error",@{ "StageName"= "Rollback"; "ErrorRecord" = ($_ | Out-String) }, $null)
		}
	}
	static [void] MigrateStorageToLatest($SubscriptionId, $oldResourceGroupLocation)
	{
		$OldRgName = [OldConstants]::AzSDKRGName
		$storageAccounts = @();
		$storageAccounts += Get-AzureRmStorageAccount -ResourceGroupName $OldRgName -ErrorAction SilentlyContinue;
		$storageAccounts = $storageAccounts | Where-Object { $_.StorageAccountName -like "$([OldConstants]::StorageAccountPreName)*" } ;
		if(($storageAccounts | Measure-Object).Count -ne 1)
		{
			return;
		}
		#region creating new resources
		try
		{
			Write-Host ("Creating new resources...") -ForegroundColor Yellow;			
			[MigrationHelper]::SetupAzSKResources($SubscriptionId, $oldResourceGroupLocation)
			Write-Host ("Successfully completed creating new resources.") -ForegroundColor Green;
		}
		catch{
			Write-Host "An error occurred during creation of new resources. See migration log for details." -ForegroundColor Red
			[AIOrgTelemetryHelper]::PublishEvent("AzSK Migration Error",@{ "StageName"= "Resource Setup"; "ErrorRecord" = ($_ | Out-String); "MigrationStatus"= "SetupResourcesFailed"}, $null)
			$ErrorOccurred = $true;
			throw;
		}
		#endregion


		#region Step1: Migrate  Storage		
		$context = $storageAccounts[0].Context;

		$newRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		$newStorageAccounts = @();
		$newStorageAccounts  += Get-AzureRmStorageAccount -ResourceGroupName $newRGName -ErrorAction SilentlyContinue;
		$newStorageAccounts = $newStorageAccounts | Where-Object { $_.StorageAccountName -like "$([Constants]::StorageAccountPreName)*" } ;
		if(($newStorageAccounts | Measure-Object).Count -ne 1)
		{
			return;
		}
		$newContext = $newStorageAccounts[0].Context;

		#region Migrate Attestation Data
		$AzSKTemp = [Constants]::AzSKAppFolderPath + "\Migration\Attestation";				
		if(-not (Test-Path "$AzSKTemp"))
		{
			mkdir -Path "$AzSKTemp" -ErrorAction Stop | Out-Null
		}
		else
		{
			Remove-Item -Path "$AzSKTemp\*" -Force -Recurse 
		}

		$attestationBlobs = Get-AzureStorageBlob -Container $([OldConstants]::AttestationDataContainerName) -Context $context -ErrorAction SilentlyContinue
		if(($attestationBlobs | Measure-Object).Count -gt 0)
		{
			$attestationBlobs | ForEach-Object {
				$blob = $_;
				$filename = "$AzSKTemp\$($blob.Name)"
				Get-AzureStorageBlobContent -Blob $_.Name -Container $([OldConstants]::AttestationDataContainerName) -Destination $filename -Context $context -Force -ErrorAction SilentlyContinue
			}
		}

		#move the stuff to new storage account
		
		#region to check if there are existing blobs in the new attestation container
		$attestationBlobs = Get-AzureStorageBlob -Container $([Constants]::AttestationDataContainerName) -Context $newContext
		if(($attestationBlobs | Measure-Object).Count -gt 0)
		{
			Write-Host "Skipping migration of attestation data. Found attestation data in new container. Migrating again can corrupt your latest attestation data." -ForegroundColor Yellow
		}
		else
		{
			$controlStateArray = Get-ChildItem -Path "$AzSKTemp"				
			$controlStateArray | ForEach-Object {
				$state = $_;
				$loopValue = 3;
				while($loopValue -gt 0)
				{
					$loopValue = $loopValue - 1;
					try
					{
						Set-AzureStorageBlobContent -File $state.FullName -Container $([Constants]::AttestationDataContainerName) -BlobType Block -Context $newContext -Force -ErrorAction Stop
						$loopValue = 0;
					}
					catch
					{
						#eat this exception and retry
					}
				}
			}
		}
		#endregion

		#region Migrate Central Scanning Config Data
		$AzSKTemp = [Constants]::AzSKAppFolderPath + "\Migration\CentralScanConfig";				
		if(-not (Test-Path "$AzSKTemp"))
		{
			mkdir -Path "$AzSKTemp" -ErrorAction Stop | Out-Null
		}
		else
		{
			Remove-Item -Path "$AzSKTemp\*" -Force -Recurse 
		}

		$centalScanningConfiguration = Get-AzureStorageBlob -Container $([OldConstants]::CAMultiSubScanConfigContainerName) -Context $context -ErrorAction SilentlyContinue
		#if($null -eq $centalScanningConfiguration)
		#{
		#	return;
		#}

		if(($centalScanningConfiguration | Measure-Object).Count -gt 0)
		{
			$centalScanningConfiguration | ForEach-Object {
				$blob = $_;
				$filename = "$AzSKTemp\$($blob.Name)"
				Get-AzureStorageBlobContent -Blob $_.Name -Container $([OldConstants]::CAMultiSubScanConfigContainerName) -Destination $filename -Context $context -Force -ErrorAction SilentlyContinue
			}
		}

		#move the stuff to new storage account

		$configDataFiles = Get-ChildItem -Path "$AzSKTemp"				
			$configDataFiles | ForEach-Object {
				$file = $_;
				$loopValue = 3;
				while($loopValue -gt 0)
				{
					$loopValue = $loopValue - 1;
					try
					{
						Set-AzureStorageBlobContent -File $file.FullName -Container $([Constants]::CAMultiSubScanConfigContainerName) -BlobType Block -Context $newContext -Force -ErrorAction Stop
						$loopValue = 0;
					}
					catch
					{
						#eat this exception and retry
					}
				}
			}


		#endregion

		#region add migration tag to old storage account
		$oldStorageResource = Get-AzureRmResource -ResourceId $storageAccounts[0].Id
		$resourceTags = $oldStorageResource.Tags
		if($null -eq $resourceTags)
		{
			$resourceTags = @{}
		}
		if($resourceTags.ContainsKey("Migration"))
		{
			$resourceTags["Migration"] = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss");
		}
		else
		{
			$resourceTags.Add("Migration",[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"));
		}
		Set-AzureRmResource -Tag  $resourceTags -ResourceId $storageAccounts[0].Id -Force
		#endregion
		#endregion
	}

	static [void] PersistMigrationOutput([string] $subscriptionId, [PSObject] $MigrationOutput)
	{
		if($null -ne $MigrationOutput)
		{
			$temp = ($env:temp + "\AzSKTemp\");
			$fileName =  "MigrationOutput_"+ (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")+ ".json"
			if(-not (Test-Path -Path $temp))
			{
				mkdir -Path $temp -Force
			}
			[Helpers]::ConvertToJsonCustom($MigrationOutput) | Out-File "$temp\$fileName" -Force;
			$oldStorageAccount = Find-AzureRmResource -ResourceNameContains $([OldConstants]::StorageAccountPreName) -ResourceGroupNameEquals $([OldConstants]::AzSDKRGName) -ResourceType 'Microsoft.Storage/storageAccounts'
			if($oldStorageAccount)
			{
				$storageHelper = [StorageHelper]::new($subscriptionId,[OldConstants]::AzSDKRGName,$oldStorageAccount.Location, $oldStorageAccount.Name);
				$fileInfos = @();
				$fileInfos += [System.IO.FileInfo]::new("$temp\$fileName");
				$storageHelper.UploadFilesToBlob("migration", "", $fileInfos, $true);
			}
			#Store logs to new storage
			try{
				$newStorageRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
				$newStorageAccount = Find-AzureRmResource -ResourceNameContains $([Constants]::StorageAccountPreName) -ResourceGroupNameEquals $newStorageRGName -ResourceType 'Microsoft.Storage/storageAccounts'
				if($newStorageAccount)
				{
					$storageHelper = [StorageHelper]::new($subscriptionId,$newStorageRGName,$newStorageAccount.Location, $newStorageAccount.Name);
					$fileInfos = @();
					$fileInfos += [System.IO.FileInfo]::new("$temp\$fileName");
					$storageHelper.UploadFilesToBlob("migration", "", $fileInfos, $true);
				}
			}
			catch
			{
				#Kept blank to avoid issue with posting migration logs to new storage
			}
			

			#put a lock once the migration is started 
			$azsdkRGScope = "/subscriptions/$subscriptionId/resourceGroups/$([OldConstants]::AzSDKRGName)"
			New-AzureRmResourceLock -LockName "AzSKMigrationLock" -LockLevel ReadOnly -Scope $azsdkRGScope -LockNotes "Migration lock by AzSK to avoid any future edits" -Force
		}
	}
	static [void] MigrateAutomationAccountToLatest([string] $subscriptionId, [PSObject] $invocationContext, [PSObject] $vars, [string] $AzureADAppName, [int] $scanIntervalInHours)
	{
		$azskRG = "*";
		$omsWSId = "";
		$omsWSKey = "";
		$altOMSWSId = "";
		$altOMSWSKey = "";
		$wUrl = "";
		$wHeaderName = "";
		$wHeaderValue = "";
		$disableAlertRunbook ="";
		$vars | ForEach-Object{
			if($_.Name -eq [Constants]::AppResourceGroupNames)
			{
				$azskRG = $_.Value
			}
			elseif($_.Name -eq [Constants]::OMSWorkspaceId)
			{
				$omsWSId = $_.Value
			}
			elseif($_.Name -eq [Constants]::OMSSharedKey)
			{
				$omsWSKey = $_.Value
			}
			elseif($_.Name -eq [Constants]::AltOMSWorkspaceId)
			{
				$altOMSWSId = $_.Value
			}
			elseif($_.Name -eq [Constants]::AltOMSSharedKey)
			{
				$altOMSWSKey = $_.Value
			}
			elseif($_.Name -eq [Constants]::WebhookUrl)
			{
				$wUrl = $_.Value
			}
			elseif($_.Name -eq [Constants]::WebhookAuthZHeaderName)
			{
				$wHeaderName = $_.Value
			}
			elseif($_.Name -eq [Constants]::WebhookAuthZHeaderValue)
			{
				$wHeaderValue = $_.Value
			}
			elseif($_.Name -eq [Constants]::DisableAlertRunbook)
			{
				$disableAlertRunbook = $_.Value
			}						
		}			

		$ccAccount = [CCAutomation]::new($subscriptionId, $invocationContext,`
				[ConfigurationManager]::GetAzSKConfigData().AzSKLocation, $null, $null, $azskRG,`
				$AzureADAppName, $scanIntervalInHours);
		#set the OMS settings
		$ccAccount.SetOMSSettings($omsWSId, $omsWSKey, $altOMSWSId, $altOMSWSKey);

		#set the Webhook settings
		$ccAccount.SetWebhookSettings($wUrl, $wHeaderName, $wHeaderValue);
		$ccAccount.InstallAzSKContinuousAssurance();

		#region to install the disable alertrunbook variable
		$RGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		if(-not [string]::IsNullOrWhiteSpace($disableAlertRunbook))
		{
			New-AzureRmAutomationVariable -Name $([Constants]::DisableAlertRunbook) -Value $disableAlertRunbook -Encrypted $false -ResourceGroupName $RGName -AutomationAccountName $([Constants]::AutomationAccountName) -ErrorAction Ignore
		}			
		[MigrationHelper]::SetCASPNPermissions($ccAccount);

		#endregion

	}
	static [void] MigrateAlerts([string] $subscriptionId, [PSObject] $invocationContext)
	{
		$mandatoryTags = [string]::Join(",", [ConfigurationManager]::GetAzSKConfigData().SubscriptionMandatoryTags);
		$alert = [Alerts]::new($subscriptionId, $invocationContext, $mandatoryTags);
		if ($alert) 
		{
			#calling alert method with default params i.e. without security contanct email and phone number
			$smsReceivers = $null;
			$emailReceivers = $null;
			$webhookUri = "";
			$curActionGroupResource = $alert.GetAlertActionGroup([OldConstants]::AzSDKRGName, [OldConstants]::AlertActionGroupName);
			if($curActionGroupResource)
			{
				$curActionGroupResourceData= Get-AzureRmResource -ResourceId $curActionGroupResource.ResourceId
				$emailReceivers = $curActionGroupResourceData.properties.emailReceivers
			}
			$curCriticalActionGroupResource = $alert.GetAlertActionGroup([OldConstants]::AzSDKRGName, [OldConstants]::CriticalAlertActionGroupName);
			if($curCriticalActionGroupResource)
			{
				$curCriticalActionGroupResourceData= Get-AzureRmResource -ResourceId $curCriticalActionGroupResource.ResourceId
				$smsReceivers = $curCriticalActionGroupResourceData.properties.smsReceivers
			}
			if($null -ne $emailReceivers)
			{
				$alert.SetAlerts($emailReceivers,$smsReceivers,$null);
				Find-AzureRmResource -ResourceGroupNameEquals $([OldConstants]::AzSDKRGName) -ResourceType "Microsoft.Insights/activityLogAlerts" -ErrorAction SilentlyContinue | Remove-AzureRmResource -Force -ErrorAction SilentlyContinue
				Find-AzureRmResource -ResourceGroupName $([OldConstants]::AzSDKRGName) -ResourceType "Microsoft.Insights/actiongroups" -ErrorAction SilentlyContinue | Remove-AzureRmResource -Force -ErrorAction SilentlyContinue				
				[Helpers]::SetResourceGroupTags([OldConstants]::AzSDKRGName ,@{[OldConstants]::AzSDKAlertsVersionTagName=""}, $true)
			}			
		}
		else{
			#No current alerts found
		}	
	}

	static [void] MigrateARMPolicies([string] $subscriptionId,[string] $scope, [PSObject] $invocationContext)
	{
		$oldPoliciesCount = (Get-AzureRmPolicyAssignment | Where-Object { $_.Name -like 'AzSDK*'} | Measure-Object).Count
		if($oldPoliciesCount -gt 0)
		{
			$mandatoryTags = [string]::Join(",", [ConfigurationManager]::GetAzSKConfigData().SubscriptionMandatoryTags);
			$armPolicy = [ARMPolicy]::new($subscriptionId, $invocationContext, $mandatoryTags);
			if ($armPolicy) 
			{
				#region AzSK TBR migration
				Write-Host "Checking for the presence of old policies..." -ForegroundColor Yellow
				$armPolicy.RemoveARMPolicies("AzSDK", $scope)				

				#endregion 

				$armPolicy.SetARMPolicies();
			}
		}
	}

	static [void] CompleteMigration([string] $subscriptionId, [PSObject] $MigrationOutput)
	{
		#apply tag
		$tagName = [Constants]::MigrationTagName
		$resourceGroupTags = [Helpers]::GetResourceGroupTags([OldConstants]::AzSDKRGName)
		if($null -eq $resourceGroupTags)
		{
			$resourceTags = @{}
		}
		if($resourceGroupTags.ContainsKey($tagName))
		{
			$resourceGroupTags[$tagName] = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss");
		}
		else
		{
			$resourceGroupTags.Add($tagName,[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"));
		}
		$RGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		[Helpers]::SetResourceGroupTags($RGName,$resourceGroupTags,$false,$false)

		#set the tag on the storage account
		$resources = @();
		$resources += Find-AzureRmResource -ResourceNameContains $([Constants]::StorageAccountPreName) -ResourceGroupNameEquals $RGName -ResourceType "Microsoft.Storage/storageAccounts"
		if(($resources | Measure-Object).Count -gt 0)
		{
			[MigrationHelper]::SetMigrationTag($resources[0].ResourceId);
		}

		#set tag on automation account
		$resources = @();
		$resources += Find-AzureRmResource -ResourceNameEquals $([Constants]::AutomationAccountName) -ResourceGroupNameEquals $RGName -ResourceType "Microsoft.Automation/automationAccounts"
		if(($resources | Measure-Object).Count -gt 0)
		{
			[MigrationHelper]::SetMigrationTag($resources[0].ResourceId);						
		}

		[MigrationHelper]::PersistMigrationOutput($subscriptionId, $MigrationOutput);			
	}

	static [void] SetMigrationTag([string] $ResourceId)
	{
		$tagName = [Constants]::MigrationTagName;
		$tagValue = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss");
		$resourceTags = @{};
		$resourceTags.Add($tagName,$tagValue);
		[Helpers]::SetResourceTags($ResourceId, $resourceTags, $false, $true);
	}


	static [void] SetCASPNPermissions([CCAutomation] $ccAutomation)
	{
		$runAsConnection = $ccAutomation.GetRunAsConnection();
		if($runAsConnection)
		{
			$existingAppId = $runAsConnection.FieldDefinitionValues.ApplicationId				
			$ADApp = Get-AzureRmADApplication -ApplicationId $existingAppId -ErrorAction SilentlyContinue				
			if($ADApp)
			{
				#check SP permissions
				$haveRGAccess = $ccAutomation.CheckServicePrincipalRGAccess($existingAppId, [OldConstants]::AzSDKRGName, "Owner")
				#assign SP $ccAutomation
				if(!$haveRGAccess)
				{
					$ccAutomation.SetServicePrincipalRGAccess($existingAppId, [OldConstants]::AzSDKRGName, "Owner")
				}
			}
		}
	}

	static [bool] MigrationPrerequisiteCheck($SubscriptionId)
	{		
		$IsMigrationPossible = $true
		#1. Check if Old RG present
		$OldRGResource =  Get-AzureRmResourceGroup -Name $([OldConstants]::AzSDKRGName) -ErrorAction SilentlyContinue
		if($OldRGResource)
		{
			#2. Check Permission using delete lock on old RG
			try
			{
				$azsdkRGScope = "/subscriptions/$subscriptionId/resourceGroups/AzSDKRG"
				$lock =New-AzureRmResourceLock -LockName "AzSKMigrationDeleteLock" -LockLevel CanNotDelete -Scope $azsdkRGScope -LockNotes "Migration lock by AzSK to validate permission" -Force 				
				Remove-AzureRmResourceLock -LockId $lock.LockId -Force
			}
			catch
			{
				$IsMigrationPossible = $false
				Write-Host "Please validate you have Owner permission. Try re-running command after permission confirmation. If issue still continue please reach out to support team." -ForegroundColor Red
				return $IsMigrationPossible			
			}
			# 3. Check if migration completed
			$isMigrationCompleted = [UserSubscriptionDataHelper]::IsMigrationCompleted($SubscriptionId)
			if($isMigrationCompleted -ne "COMP")
			{
				$IsMigrationPossible = $true
			}
			else
			{
				Write-Host ("WARNING: Your subscription has already been migrated from `"AzSDK`" to `"AzSK`". If you'd like to update any other aspect of subscription security (policies, alerts, ASC, CA, etc.), you can rerun this command without the '-Migrate' switch.") -ForegroundColor Yellow;				
				$IsMigrationPossible= $false
			}
		}
		else
		{
			Write-Host ("WARNING: No AzSDK-based assets found in the subscription. Migration does not apply. You can use the AzSK module directly.") -ForegroundColor Yellow;
			$IsMigrationPossible = $false
		}		
		return $IsMigrationPossible
	}
}

[MigrationHelper]::StartMigration($SubscriptionContext, $InvocationContext, $AzureADAppName)
