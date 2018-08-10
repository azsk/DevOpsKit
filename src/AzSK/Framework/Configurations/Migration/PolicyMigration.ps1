Set-StrictMode -Version Latest

class PolicyMigrationHelper 
{
	static [string] $PolicyRGName
	static [string] $NewPolicyRGName
	static [void] StartMigration([SubscriptionContext] $subscriptionContext, [PSObject] $PolicyInstance, [PSObject] $OPolicyInstance)
	{
		[PSObject] $MigrationOutput = @{}
		[bool] $ErrorOccurred = $false;
		#Prepar Policy RG Name

		[PolicyMigrationHelper]::PolicyRGName = $OPolicyInstance.ResourceGroupName;
		[PolicyMigrationHelper]::NewPolicyRGName = $PolicyInstance.ResourceGroupName;

		#region Step 1: Validate if Policy Exists
		if(-not [PolicyMigrationHelper]::MigrationPrerequisiteCheck())
		{			    
			return
		}
		#endregion

		#region Step 2: Get meta data for existing policy
		Write-Host ([Constants]::DoubleDashLine + "`r`nUpdating your current Org policy with latest AzSK resources...`r`n" + [Constants]::DoubleDashLine) -ForegroundColor Cyan;

		#region clear any existing locks
		try
		{
			Write-Host ("Checking if there are any resource locks on old Org policy resource group...") -ForegroundColor Yellow;

			$azskRGScope = "/subscriptions/$($subscriptionContext.SubscriptionId)/resourceGroups/$([PolicyMigrationHelper]::PolicyRGName)"
			$resourceLocks = @();
			$resourceLocks += Get-AzureRmResourceLock -Scope $azskRGScope -ErrorAction Stop
			if($resourceLocks.Count -gt 0)
			{
				$resourceLocks | ForEach-Object {
					Remove-AzureRmResourceLock -LockId $_.LockId -Force
				}
				Write-Host ("Successfully removed the locks on old Org policy resource group.") -ForegroundColor Green;
			}
			else
			{
				Write-Host ("No locks found on old Org policy resource group.") -ForegroundColor Green;
			}
			$MigrationOutput.LockRemoval = "Success"
		}
		catch
		{
			Write-Host "An error occurred during removal of locks on old Org policy resource group: [$([PolicyMigrationHelper]::PolicyRGName)]" -ForegroundColor Red
			$MigrationOutput.LockRemoval = "Failed. Message[$_]"
			$ErrorOccurred = $true;
			throw;
		}
		#endregion
		#endregion

		#region capture the existing information
		$oldResourceGroupLocation = [ConfigurationManager]::GetAzSKConfigData().AzSKLocation;
		try
		{
			Write-Host ("Extracting policy files from old Org policy resources...") -ForegroundColor Yellow;

			$oldRg = Get-AzureRmResourceGroup -Name $([PolicyMigrationHelper]::PolicyRGName) -ErrorAction SilentlyContinue
			if($oldRg)
			{
				$oldResourceGroupLocation = $oldRg.Location;					
			}
			
			#region extract storage policies
				$storageAccounts = @();
				$storageAccounts += Get-AzureRmStorageAccount -ResourceGroupName $([PolicyMigrationHelper]::PolicyRGName) -ErrorAction SilentlyContinue;
				$storageAccounts = $storageAccounts | Where-Object { $_.StorageAccountName -like "$([OldConstants]::StorageAccountPreName)*" } ;
				if(($storageAccounts | Measure-Object).Count -ne 1)
				{
					return;
				}
				$context = $storageAccounts[0].Context;		

				$policyBlobs = Get-AzureStorageBlob -Container "policies" -Context $context -ErrorAction SilentlyContinue
				if(($policyBlobs | Measure-Object).Count -gt 0)
				{
					if(-not (Test-Path "$($PolicyInstance.ConfigFolderPath)"))
					{
						mkdir -Path "$($PolicyInstance.ConfigFolderPath)" -ErrorAction Stop | Out-Null
					}
					else
					{
						Remove-Item -Path "$($PolicyInstance.ConfigFolderPath)\*" -Force -Recurse 
					}
					 ForEach($blob in $policyBlobs ) {				
						$splitNames = $blob.Name.Split("/")
						$fileName = $splitNames[($splitNames.Count-1)]
						if($fileName -eq "AzSDK.json")
						{
							$fileName = "AzSK.json"
						}
						if($fileName -eq "RunbookScanAgent.ps1")
						{
							continue
						}
						$filepath = "$($PolicyInstance.ConfigFolderPath)\$fileName"
						Get-AzureStorageBlobContent -Blob $blob.Name -Container "policies" -Destination $filepath -Context $context -Force -ErrorAction SilentlyContinue
					}
				}					
				#endregion

			Write-Host ("Successfully completed extracting policy files from old Org policy resources.") -ForegroundColor Green;
			$MigrationOutput.CurrentDataExtraction = "Success"				
		}
		catch{
			Write-Host "An error while extracting current metadata and copying policy files from old Org policy resources" -ForegroundColor Red				
			$MigrationOutput.CurrentDataExtraction = "Failed. Message[$_]"
			$ErrorOccurred = $true;
			throw;
		}
		#endregion
			
		#region creating new resources
		try
		{
			#region copy subscription migration to policy
			Write-Host ("Copying subscription migration script to policy folder...") -ForegroundColor Yellow;	
			$migrationScriptContent = [ConfigurationHelper]::LoadOfflineConfigFile("Migration.ps1")					 
			Out-File -InputObject $migrationScriptContent -Force -FilePath "$($PolicyInstance.ConfigFolderPath)\Migration.ps1" -Encoding utf8
			Write-Host ("Successfully completed copying subscription migration script to policy folder.") -ForegroundColor Green;
			#endregion
			Write-Host ("Setting up Org policy using the *AzSK* module...`r`n"+[Constants]::GTLine) -ForegroundColor Yellow;	
			
			[PolicyMigrationHelper]::SetupPolicyResources($PolicyInstance)	
			
			Write-Host ([Constants]::GTLine+"`r`nSuccessfully completed setting up Org policy using the *AzSK* module.`r`n"+[Constants]::SingleDashLine) -ForegroundColor Green;
			
			$MigrationOutput.ResourceCreation = "Success"
		}
		catch{
			Write-Host "An error occurred during setting up Org policy with latest AzSK. See migration log for details." -ForegroundColor Red				
			$MigrationOutput.ResourceCreation = "Failed. Message[$_]"
			$ErrorOccurred = $true;
			throw;
		}
		#endregion
		Write-Host ("Performing last couple of steps...") -ForegroundColor Yellow;
		#Override existing IWR
		Write-Host ("Updating old Org-specific installer ('iwr')...") -ForegroundColor Yellow;	
		Set-AzureStorageBlobContent -File $PolicyInstance.InstallerFile -Container $($PolicyInstance.InstallerContainerName) -BlobType Block -Context $context -Force -ErrorAction Stop						
		Write-Host ("Successfully updated installer.") -ForegroundColor Green;
		Write-Host ("Uploading Org policy migration log to storage [$($PolicyInstance.StorageAccountName)]...") -ForegroundColor Yellow;
		[PolicyMigrationHelper]::PersistMigrationOutput($subscriptionContext.SubscriptionId,[PolicyMigrationHelper]::NewPolicyRGName, $MigrationOutput);		
		Write-Host ("Successfully uploaded log.") -ForegroundColor Green;
		#region complete migration
		$MigrationOutput.ErrorOccurred = $ErrorOccurred
		if($MigrationOutput.ErrorOccurred -eq $false)
		{				
			[PolicyMigrationHelper]::CompleteMigration($subscriptionContext.SubscriptionId,[PolicyMigrationHelper]::NewPolicyRGName, $MigrationOutput)
			#endregion									
			write-host ([Constants]::SingleDashLine + "`r`n Org policy migration completed successfully`r`n"+[Constants]::SingleDashLine) -ForegroundColor Green
			write-host ([Constants]::SingleDashLine + "`r`n Follow next steps at: https://aka.ms/devopskit/extmigration#org-policy") -ForegroundColor Green
			
		}
		else
		{
			[PolicyMigrationHelper]::PersistMigrationOutput($subscriptionContext.SubscriptionId, $MigrationOutput)				
			write-host ([Constants]::SingleDashLine + "`r`nAn error during policy migration, please retry again. If issue still continue please reach out to support team.`r`n"+[Constants]::SingleDashLine) -ForegroundColor Red
		}		
	}

	static [bool] MigrationPrerequisiteCheck()
	{
		$PrerequisiteCheckResult = $true
		
		$PolicyRG= Get-AzureRmResourceGroup -Name $([PolicyMigrationHelper]::PolicyRGName) -ErrorAction SilentlyContinue
		if(-not $PolicyRG)
		{
			$PrerequisiteCheckResult = $false
			Write-Host ("WARNING: No policy setup found for Org in the subscription. Migration does not apply. You can use the AzSK module directly to setup new policy.") -ForegroundColor Yellow;
			return $PrerequisiteCheckResult
		}
		$tagName = [Constants]::PolicyMigrationTagName
		$OrgRGName = [PolicyMigrationHelper]::NewPolicyRGName
		$resourceGroupTags = [Helpers]::GetResourceGroupTags($OrgRGName)
		$migrationTag = $resourceGroupTags.GetEnumerator() | Where-Object { $_.Name -eq $tagName }
		if(($migrationTag | Measure-Object).Count -gt 0)
		{
			$PrerequisiteCheckResult = $false
			Write-Host ("WARNING: Policy is already migrated.") -ForegroundColor Yellow;
			return $PrerequisiteCheckResult
		}		
		return $PrerequisiteCheckResult
	}

	static SetupPolicyResources([PSObject] $PolicyInstance)
	{
		# Install Policy
		$PolicyInstance.InstallPolicy([Constants]::NewModuleName)		
	}
	static [void] CompleteMigration([string] $subscriptionId,[string] $OrgRGName, [PSObject] $MigrationOutput)
	{
		#apply tag
		$tagName = [Constants]::PolicyMigrationTagName
		$resourceGroupTags = [Helpers]::GetResourceGroupTags($OrgRGName)
		$resourceGroupTags.Add($tagName,[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"));
		[Helpers]::SetResourceGroupTags($OrgRGName,$resourceGroupTags,$false,$false)		;			
	}

	static [void] PersistMigrationOutput([string] $subscriptionId,[string] $OrgRGName, [PSObject] $MigrationOutput)
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

			try{
				$newStorageRGName = $OrgRGName
				$newStorageAccount = Get-AzureRmResource -ResourceGroupName $newStorageRGName -ResourceType 'Microsoft.Storage/storageAccounts'
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
		}
	}
}

[PolicyMigrationHelper]::StartMigration($subscriptionContext,$PolicyInstance, $OPolicyInstance)
