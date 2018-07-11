using namespace Microsoft.Azure.Management.Storage.Models
Set-StrictMode -Version Latest
class UserSubscriptionDataHelper: AzSKRoot
{
	hidden static [string] $ResourceGroupName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
	hidden static [string] $AutomationAccountName = [Constants]::AutomationAccountName
	hidden static [string] $StorageResourceType = "Microsoft.Storage/storageAccounts";


	UserSubscriptionDataHelper([string] $subscriptionId):
		Base($subscriptionId)
	{
	}
	#region: Get operations 
	static [PSObject] GetUserSubscriptionRGName()
	{
		return [UserSubscriptionDataHelper]::ResourceGroupName
	}
	static [PSObject] GetUserSubscriptionRG()
	{
		$ResourceGroup = Get-AzureRmResourceGroup -Name $([UserSubscriptionDataHelper]::ResourceGroupName) -ErrorAction Stop
		return $ResourceGroup
	}
	static [PSObject] GetUserSubscriptionStorage()
	{
		$StorageAccountPreName = [Constants]::StorageAccountPreName
		$storageAccount = Find-AzureRmResource -ResourceGroupNameEquals $([UserSubscriptionDataHelper]::ResourceGroupName) `
		-ResourceNameContains $StorageAccountPreName `
		-ResourceType $([UserSubscriptionDataHelper]::StorageResourceType) `
		-ErrorAction Stop
		$storageAccount = $storageAccount | Where-Object{$_.ResourceName -match '^azsk\d{14}$'}

		if(($storageAccount|Measure-Object).Count -gt 1)
		{
			throw [SuppressedException]::new("Multiple storage accounts found in resource group: [$([UserSubscriptionDataHelper]::ResourceGroupName)]. This is not expected. Please contact support team.");
		}
		return $storageAccount
	}
	[PSObject] GetUserSubscriptionStorageContainer([string] $StorageContainerType)
	{
		return "<containerobject>"
	}
	[string] GetUserSubscriptionStorageContainerName([string] $StorageContainerType)
	{
		return "<containername>"
	}	
	[PSObject] GetUserSubscriptionStorageContainerData([string] $StorageContainerType)
	{
		return "<containerdata>"
	}	
	static [PSObject] GetStorageContainer($ContainerName)
	{
		$storage = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
		$container = $null
		if($storage)
		{
			$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $([UserSubscriptionDataHelper]::ResourceGroupName) -Name $storage.Name
			$currentContext = New-AzureStorageContext -StorageAccountName $storage.Name -StorageAccountKey $keys[0].Value -Protocol Https
			$container = Get-AzureStorageContainer -Name $ContainerName -Context $currentContext -ErrorAction SilentlyContinue | Out-Null
		}
		return $container
	}
	static [string] GetCAName()
	{
		return [UserSubscriptionDataHelper]::AutomationAccountName
	}

	static [bool] IsMigrationRequired()
	{
		$isMigrationRequired = $true;
		try
		{
			$storage = [UserSubscriptionDataHelper]::GetOldStorage()
			$container = $null
			if($storage)
			{
				$temp = ($env:temp + "\AzSKTemp\");
				if(-not (Test-Path -Path $temp))
				{
					mkdir -Path $temp -Force
				}
				$filePath = "$temp\MigrationOutputFromServer.json"
				Remove-Item -Path $filePath -Force -ErrorAction Ignore
				$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $storage.ResourceGroupName -Name $storage.Name
				$currentContext = New-AzureStorageContext -StorageAccountName $storage.Name -StorageAccountKey $keys[0].Value -Protocol Https
				Get-AzureStorageBlobContent -Blob "MigrationOutput.json" -Container "migration" -Context $currentContext -Force -Destination $filepath -ErrorAction SilentlyContinue
				if((Test-Path $filePath))
				{
					$MigrationOutput = Get-Content -Path $filePath | ConvertFrom-Json
					if($MigrationOutput -and [Helpers]::CheckMember($MigrationOutput,"ErrorOccurred") -and $MigrationOutput.ErrorOccurred)
					{
							$isMigrationRequired = $true;
					}
					else
					{
						$isMigrationRequired = $false;
					}
					
				}
				else
				{
					#if the migration blob is not found then we need to migrate
					$isMigrationRequired = $true;
				}
			}
			else
			{
				#if no storage found, there is no need to migrate as there are no old resources present on the subscription
				$isMigrationRequired = $false;				
			}
		}
		catch
		{
			$isMigrationRequired = $false
			throw;
			
		}
		return $isMigrationRequired
	}

	static [string] IsMigrationCompleted([string] $subscriptionId)
	{
		$MigrationCompleted = "NOTSET"
		$resources = Find-AzureRmResource -TagName $([Constants]::MigrationTagName) | Measure-Object
		$OldRGResource =  Get-AzureRmResourceGroup -Name $([OldConstants]::AzSDKRGName) -ErrorAction SilentlyContinue	
		if(($resources.Count -gt 0) -or (($OldRGResource | Measure-Object).Count -eq  0))
		{
			$MigrationCompleted = "COMP"
		}
		else
		{
			$MigrationCompleted = "INIT"
		}
		return $MigrationCompleted;
	}

	static [PSObject] GetOldStorage()
	{
		$RGName = [OldConstants]::AzSDKRGName
		$StorageAccountPreName = [OldConstants]::StorageAccountPreName
		$existingStorage = Find-AzureRmResource -ResourceGroupNameEquals $RGName `
		-ResourceNameContains $StorageAccountPreName `
		-ResourceType $([UserSubscriptionDataHelper]::StorageResourceType) `
		-ErrorAction Stop
		if(($existingStorage|Measure-Object).Count -gt 1)
		{
			throw [SuppressedException]::new("Multiple storage accounts found in resource group: [$RGName]. This is not expected. Please contact support team.");
		}
		return $existingStorage
	}

	static [PSObject] GetOldRG()
	{
		$RGName = [OldConstants]::AzSDKRGName
		$ResourceGroup = Get-AzureRmResourceGroup -Name $RGName -ErrorAction SilentlyContinue
		return $ResourceGroup
	}
	
	static [PSObject] UpgradeBlobToV2Storage() 
    {
        #TODO: Check contributor permisison on azskrg
		$RGName = [UserSubscriptionDataHelper]::ResourceGroupName
		$StorageName = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage().Name
        try 
        {
            Set-AzureRmStorageAccount -ResourceGroupName $RGName -Name $StorageName -UpgradeToStorageV2 -ErrorAction Stop 
        }
        catch
        {
			[EventBase]::PublishCustomMessage("Failed to upgrade storage [$StorageName].");
			[EventBase]::PublishException($_)
        }
        #Storage compliance
        $retryAccount = 0
		$storageAccount = $null
        do 
        {
            $storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $RGName -Name $StorageName -ErrorAction SilentlyContinue
            Start-Sleep -seconds 2
            $retryAccount++
        } while (!$storageAccount -and $retryAccount -ne 6)
        if($storageAccount)
        {
            $storageContext = $storageAccount.Context 
            Set-AzureStorageServiceLoggingProperty -ServiceType Blob -LoggingOperations 'All' -Context $storageContext -RetentionDays '365' -PassThru
            Set-AzureStorageServiceLoggingProperty -ServiceType Queue -LoggingOperations 'All' -Context $storageContext -RetentionDays '365' -PassThru
            Set-AzureStorageServiceLoggingProperty -ServiceType Table -LoggingOperations 'All' -Context $storageContext -RetentionDays '365' -PassThru
            Set-AzureStorageServiceLoggingProperty -ServiceType File -LoggingOperations 'All' -Context $storageContext -RetentionDays '365' -PassThru
			return $storageAccount
        }
		else
		{
			return $Null
		}
    }
	#endregion
}
