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

	#endregion
}
