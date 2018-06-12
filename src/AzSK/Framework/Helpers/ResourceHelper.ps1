using namespace Microsoft.WindowsAzure.Storage.Blob
using namespace Microsoft.Azure.Commands.Management.Storage.Models
using namespace Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel
Set-StrictMode -Version Latest
class ResourceGroupHelper: AzSKRoot
{
	[string] $ResourceGroupName;
	[string] $ResourceGroupLocation = "EastUS2";

	[PSObject] $ResourceGroup;

	ResourceGroupHelper([string] $subscriptionId, [string] $resourceGroupName):
		Base($subscriptionId)
	{
		$this.CreateInstance($resourceGroupName, "EastUS2");
	}

	ResourceGroupHelper([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceGroupLocation):
		Base($subscriptionId)
	{
		$this.CreateInstance($resourceGroupName, $resourceGroupLocation);
	}

	hidden [void] CreateInstance([string] $resourceGroupName, [string] $resourceGroupLocation)
	{
		if([string]::IsNullOrWhiteSpace($resourceGroupName))
		{
			throw [System.ArgumentException] ("The argument 'resourceGroupName' is null or empty");
		}
		$this.ResourceGroupName = $resourceGroupName;
		if(-not [string]::IsNullOrWhiteSpace($resourceGroupLocation))
		{
			$this.ResourceGroupLocation = $resourceGroupLocation;
		}
	}

	[void] CreateResourceGroupIfNotExists()
	{
		if(-not $this.ResourceGroup)
		{
			$rg = Get-AzureRmResourceGroup -Name $this.ResourceGroupName -ErrorAction ignore
			#$rg = Get-AzureRmResourceGroup | Where-Object { $_.ResourceGroupName -eq $this.ResourceGroupName } | Select-Object -First 1
			if(-not $rg)
			{
				$this.PublishCustomMessage("Creating resource group [$($this.ResourceGroupName)]...");
				$result = [Helpers]::NewAzSKResourceGroup($this.ResourceGroupName, $this.ResourceGroupLocation, "");
				if($result)
				{
					$this.ResourceGroup = $result;
					$this.PublishCustomMessage("Successfully created resource group [$($this.ResourceGroupName)]", [MessageType]::Update);
				}
				else
				{
					throw ([SuppressedException]::new("Error occured while creating resource group [$($this.ResourceGroupName)]", [SuppressedExceptionType]::Generic))				
				}
			}
			else
			{
				$this.ResourceGroup = $rg;
			}
		}
	}
}

class StorageHelper: ResourceGroupHelper
{
	hidden [PSStorageAccount] $StorageAccount = $null;
	[string] $StorageAccountName;
	[int] $HaveWritePermissions = 0;
	[int] $retryCount = 3;
	[int] $sleepIntervalInSecs = 10;

	hidden [string] $ResourceType = "Microsoft.Storage/storageAccounts";

	StorageHelper([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceGroupLocation, [string] $storageAccountName):
		Base($subscriptionId, $resourceGroupName, $resourceGroupLocation)
	{
		if([string]::IsNullOrWhiteSpace($storageAccountName))
		{
			throw [System.ArgumentException] ("The argument 'storageAccountName' is null or empty");
		}
		$this.StorageAccountName = $storageAccountName;
	}

	[void] CreateStorageIfNotExists()
	{
		if(-not $this.StorageAccount)
		{
			$this.CreateResourceGroupIfNotExists();

			$existingResources = Find-AzureRmResource -ResourceGroupNameEquals $this.ResourceGroupName -ResourceType $this.ResourceType

			# Assuming 1 storage account is needed on Resource group
			if(($existingResources | Measure-Object).Count -gt 1)
			{
				throw ([SuppressedException]::new(("Multiple storage accounts found in resource group: [$($this.ResourceGroupName)]. This is not expected. Please contact support team."), [SuppressedExceptionType]::InvalidOperation))
			}
			elseif(($existingResources | Measure-Object).Count -eq 0)
			{
				$this.PublishCustomMessage("Creating a storage account: ["+ $this.StorageAccountName +"]...");
				$newStorage = [Helpers]::NewAzskCompliantStorage($this.StorageAccountName, $this.ResourceGroupName, $this.ResourceGroupLocation);
				if($newStorage)
				{
					$this.PublishCustomMessage("Successfully created storage account [$($this.StorageAccountName)]", [MessageType]::Update);
				}
				else
				{
					throw ([SuppressedException]::new("Failed to create storage account [$($this.StorageAccountName)]", [SuppressedExceptionType]::Generic))
				}
			}
			elseif(($existingResources | Measure-Object).Count -eq 1)
			{
				$this.StorageAccountName = $existingResources.Name;
			}

			# Fetch the Storage account context
			$this.StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $this.ResourceGroupName -Name $this.StorageAccountName -ErrorAction Ignore
			if(-not ($this.StorageAccount -and $this.StorageAccount.Context))
			{
				$this.StorageAccount = $null;
				throw ([SuppressedException]::new("Unable to fetch the storage account [$($this.StorageAccountName)]", [SuppressedExceptionType]::InvalidOperation))				
			}

			#precompute storage access permissions for the current scan account
			$this.ComputePermissions();
		}
	}

	[AzureStorageContainer] CreateStorageContainerIfNotExists([string] $containerName)
	{
		return $this.CreateStorageContainerIfNotExists($containerName, [BlobContainerPublicAccessType]::Off);
	}
	
	[AzureStorageContainer] CreateStorageContainerIfNotExists([string] $containerName, [BlobContainerPublicAccessType] $accessType)
	{
		if([string]::IsNullOrWhiteSpace($containerName))
		{
			throw [System.ArgumentException] ("The argument 'containerName' is null or empty");
		}

		$this.CreateStorageIfNotExists();

		$container = Get-AzureStorageContainer -Context $this.StorageAccount.Context -Name $containerName -ErrorAction Ignore
		if(($container| Measure-Object).Count -eq 0)
		{
			$this.PublishCustomMessage("Creating storage container [$containerName]...");
			$container = New-AzureStorageContainer -Context $this.StorageAccount.Context -Name $containerName -Permission $accessType
			if($container)
			{
				$this.PublishCustomMessage("Successfully created storage container [$containerName]", [MessageType]::Update);
			}
		}

		if(($container| Measure-Object).Count -eq 0)
		{
			throw ([SuppressedException]::new("Unable to fetch/create the container [$containerName] under storage account [$($this.StorageAccountName)]", [SuppressedExceptionType]::InvalidOperation))				
		}

		return $container;
	}

	hidden [void] ComputePermissions()
	{		
		if($null -eq $this.StorageAccount)
		{
			#No storage account => no permissions at all
			$this.HaveWritePermissions = 0
			return;
        }
        
		$this.HaveWritePermissions = 0
		#this is local constant with dummy container name to check for storage permissions
		$writeTestContainerName = "writetest";

		#see if user can create the test container in the storage account. If yes then user have both RW permissions. 
		try
		{
			$containerObject = Get-AzureStorageContainer -Context $this.StorageAccount.Context -Name $writeTestContainerName -ErrorAction SilentlyContinue
			if($null -ne $containerObject)
			{
				Remove-AzureStorageContainer -Name $writeTestContainerName -Context  $this.StorageAccount.Context -ErrorAction Stop -Force
				$this.HaveWritePermissions = 1
			}
			else
			{
				New-AzureStorageContainer -Context $this.StorageAccount.Context -Name $writeTestContainerName -ErrorAction Stop
				$this.HaveWritePermissions = 1
				Remove-AzureStorageContainer -Name $writeTestContainerName -Context  $this.StorageAccount.Context -ErrorAction SilentlyContinue -Force
			}				
		}
		catch
		{
			$this.HaveWritePermissions = 0
		}
    }


	[AzureStorageContainer] UploadFilesToBlob([string] $containerName, [string] $blobPath, [System.IO.FileInfo[]] $filesToUpload, [bool] $overwrite)
	{
		return $this.UploadFilesToBlob([string] $containerName, [BlobContainerPublicAccessType]::Off, $blobPath, $filesToUpload, $overwrite);
	}

	[AzureStorageContainer] UploadFilesToBlob([string] $containerName, [string] $blobPath, [System.IO.FileInfo[]] $filesToUpload)
	{
		return $this.UploadFilesToBlob([string] $containerName, [BlobContainerPublicAccessType]::Off, $blobPath, $filesToUpload);
	}

	[AzureStorageContainer] UploadFilesToBlob([string] $containerName, [BlobContainerPublicAccessType] $accessType, [string] $blobPath, [System.IO.FileInfo[]] $filesToUpload)
	{
		return $this.UploadFilesToBlob([string] $containerName, $accessType, $blobPath, $filesToUpload, $true);
	}

	[AzureStorageContainer] UploadFilesToBlob([string] $containerName, [BlobContainerPublicAccessType] $accessType, [string] $blobPath, [System.IO.FileInfo[]] $filesToUpload, [bool] $overwrite)
	{
		$result = $null;
		if($filesToUpload -and $filesToUpload.Count -ne 0)
		{
			$result = $this.CreateStorageContainerIfNotExists($containerName, $accessType);

			$this.PublishCustomMessage("Uploading [$($filesToUpload.Count)] file(s) to container [$containerName]...");
			$filesToUpload |
			ForEach-Object {
				$blobName = $_.Name;
				if(-not [string]::IsNullOrWhiteSpace($blobPath))
				{
					$blobName = $blobPath + "/" + $blobName;
				}

				if($overwrite)
				{
					[Helpers]::RemoveUtf8BOM($_);
					Set-AzureStorageBlobContent -Blob $blobName -Container $containerName -File $_.FullName -Context $this.StorageAccount.Context -Force | Out-Null
				}
				else
				{
					$currentBlob = Get-AzureStorageBlob -Blob $blobName -Container $containerName -Context $this.StorageAccount.Context -ErrorAction Ignore
				
					if(-not $currentBlob)
					{
						[Helpers]::RemoveUtf8BOM($_);
						Set-AzureStorageBlobContent -Blob $blobName -Container $containerName -File $_.FullName -Context $this.StorageAccount.Context | Out-Null
					}
				}

			};
			$this.PublishCustomMessage("All files have been uploaded to container [$containerName]");
		}
		else
		{
			throw [System.ArgumentException] ("The argument 'filesToUpload' is null or empty");
		}
		return $result;
	}

	[void] DownloadFilesFromBlob([string] $containerName, [string] $blobName, [string] $destinationPath, [bool] $overwrite)
	{
		$loopValue = $this.retryCount;
		$sleepValue = $this.sleepIntervalInSecs;
		while($loopValue -gt 0)
		{
			$loopValue = $loopValue - 1;
			try {
				if($overwrite)
				{
					Get-AzureStorageBlobContent -Blob $blobName -Context $this.StorageAccount.Context -Destination $destinationPath -Force -ErrorAction Stop
				}
				else {
					Get-AzureStorageBlobContent -Blob $blobName -Context $this.StorageAccount.Context -Destination $destinationPath -ErrorAction Stop
				}
				$loopValue = 0;
			}
			catch {
				#sleep for incremental 10 seconds before next retry;
				Start-Sleep -Seconds $sleepValue;
				$sleepValue = $sleepValue + 10;
			}
		}
	}

	[string] GenerateSASToken([string] $containerName)
	{
		$this.CreateStorageContainerIfNotExists($containerName);
		$sasToken = New-AzureStorageContainerSASToken -Name $containerName -Context $this.StorageAccount.Context -ExpiryTime (Get-Date).AddMonths(6) -Permission rl -Protocol HttpsOnly -StartTime (Get-Date).AddDays(-1)
		if([string]::IsNullOrWhiteSpace($sasToken))
		{
			throw ([SuppressedException]::new("Unable to create SAS token for storage account [$($this.StorageAccountName)]", [SuppressedExceptionType]::InvalidOperation))
		}
		return $sasToken;
	}
}

class AppInsightHelper: ResourceGroupHelper
{
	[PSObject] $AppInsightInstance = $null;
	[string] $AppInsightName;
	[string] $AppInsightLocation;

	hidden [string] $ResourceType = "Microsoft.Insights/components";

	AppInsightHelper([string] $subscriptionId, [string] $resourceGroupName,[string] $resourceGroupLocation, [string] $appInsightsLocation, [string] $appInsightName):
		Base($subscriptionId, $resourceGroupName, $resourceGroupLocation)
	{
		if([string]::IsNullOrWhiteSpace($appInsightName))
		{
			throw [System.ArgumentException] ("The argument 'appInsightName' is null or empty");
		}
		$this.AppInsightName = $appInsightName;
		$this.AppInsightLocation = $appInsightsLocation;
	}

	[void] CreateAppInsightIfNotExists()
	{
		if(-not $this.AppInsightInstance)
		{
			$this.CreateResourceGroupIfNotExists();
			[Helpers]::RegisterResourceProviderIfNotRegistered("microsoft.insights");
			$existingResources = Find-AzureRmResource -ResourceGroupNameEquals $this.ResourceGroupName -ResourceType $this.ResourceType

			# Assuming 1 storage account is needed on Resource group
			if(($existingResources | Measure-Object).Count -gt 1)
			{
				throw ([SuppressedException]::new(("Multiple application insight resources found in resource group: [$($this.ResourceGroupName)]. This is not expected. Please contact support team."), [SuppressedExceptionType]::InvalidOperation))
			}
			elseif(($existingResources | Measure-Object).Count -eq 0)
			{
				$this.PublishCustomMessage("Creating an application insight resource ["+ $this.AppInsightName +"]...");
				$newResource = New-AzureRmResource -ResourceName $this.AppInsightName -ResourceGroupName $this.ResourceGroupName -ResourceType $this.ResourceType `
									-Location $this.AppInsightLocation -PropertyObject @{"Application_Type"="web"} -Force
				if($newResource)
				{
					$this.PublishCustomMessage("Successfully created application insight resource [$($this.AppInsightName)]", [MessageType]::Update);
				}
				else
				{
					throw ([SuppressedException]::new("Failed to create application insight resource [$($this.AppInsightName)]", [SuppressedExceptionType]::Generic))
				}
			}
			elseif(($existingResources | Measure-Object).Count -eq 1)
			{
				$this.AppInsightName = $existingResources.Name;
			}

			# Fetch the application insight
			$this.AppInsightInstance = Find-AzureRmResource -ResourceNameEquals $this.AppInsightName -ResourceGroupName $this.ResourceGroupName -ResourceType $this.ResourceType -ExpandProperties 
			if(-not ($this.AppInsightInstance -and $this.AppInsightInstance.Properties))
			{
				$this.AppInsightInstance = $null;
				throw ([SuppressedException]::new("Unable to fetch application insight resource [$($this.AppInsightName)]", [SuppressedExceptionType]::InvalidOperation))				
			}
		}
	}
}

