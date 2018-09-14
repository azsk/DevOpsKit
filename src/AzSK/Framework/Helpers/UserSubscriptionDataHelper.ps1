using namespace Microsoft.Azure.Management.Storage.Models
Set-StrictMode -Version Latest
class UserSubscriptionDataHelper: AzSKRoot
{
	hidden static [string] $ResourceGroupName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
	hidden static [string] $ResourceGroupLocation = [ConfigurationManager]::GetAzSKConfigData().AzSKLocation
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
	static [PSObject] GetUserSubscriptionRGLocation()
	{
		return [UserSubscriptionDataHelper]::ResourceGroupLocation
	}

	static [PSObject] GetUserSubscriptionRG()
	{
		$ResourceGroup = Get-AzureRmResourceGroup -Name $([UserSubscriptionDataHelper]::ResourceGroupName) -ErrorAction Stop
		return $ResourceGroup
	}
	static [PSObject] GetUserSubscriptionStorage()
	{
		$StorageAccountPreName = [Constants]::StorageAccountPreName
		$storageAccount = Get-AzureRmResource -ResourceGroupName $([UserSubscriptionDataHelper]::ResourceGroupName) `
		-Name "*$StorageAccountPreName*" `
		-ResourceType $([UserSubscriptionDataHelper]::StorageResourceType) `
		-ErrorAction Stop
		$storageAccount = $storageAccount | Where-Object{$_.Name -match '^azsk\d{14}$'}

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

	static [PSObject] GetOldStorage()
	{
		$RGName = [OldConstants]::AzSDKRGName
		$StorageAccountPreName = [OldConstants]::StorageAccountPreName
		$existingStorage = Get-AzureRmResource -ResourceGroupName $RGName `
		-Name "*$($StorageAccountPreName)*" `
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
