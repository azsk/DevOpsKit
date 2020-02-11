using namespace Microsoft.Azure.Storage.Blob
using namespace Microsoft.Azure.Commands.Management.Storage.Models
using namespace Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel
Set-StrictMode -Version Latest
class ResourceGroupHelper: EventBase
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
			$rg = Get-AzResourceGroup -Name $this.ResourceGroupName -ErrorAction ignore
			#$rg = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -eq $this.ResourceGroupName } | Select-Object -First 1
			if(-not $rg)
			{
				$this.PublishCustomMessage("Creating resource group [$($this.ResourceGroupName)]...");
				$result = [ResourceGroupHelper]::NewAzSKResourceGroup($this.ResourceGroupName, $this.ResourceGroupLocation, "");
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

	static [PSObject] GetResourceGroupTags([string]$RGName)
	{
		$azskResourceGroup = Get-AzResourceGroup -Name $RGName -ErrorAction SilentlyContinue;
		$tags = @{}
		if(($azskResourceGroup | Measure-Object).Count -gt 0)
		{
			$tags = $azskResourceGroup.Tags;
			if($null -eq $tags)
			{
				$tags = @{}
			}
		}
		return $tags 
	}

	static [string] GetResourceGroupTag([string]$RGName, [string] $tagName)
	{
		$azskResourceGroup = Get-AzResourceGroup -Name $RGName -ErrorAction SilentlyContinue;
		$tags = @{}
		if(($azskResourceGroup | Measure-Object).Count -gt 0)
		{
			$tags = $azskResourceGroup.Tags;
			if(($tags | Measure-Object).Count -gt 0)
			{
				return $tags[$tagName];
			}
		}
		return ""; 
	}

	static [bool] NewAzSKResourceGroup([string]$ResourceGroup, [string]$Location, [string] $Version) {
        try {
            [Hashtable] $RGTags = @{};
            if ([string]::IsNullOrWhiteSpace($Version))
			 {
               $version= [Constants]::AzSKCurrentModuleVersion
            }
                $RGTags += @{
                    "AzSKVersion" = $Version;
                    "CreationTime" = $(get-date).ToUniversalTime().ToString("yyyyMMdd_HHmmss");
                }
            
            $newRG = New-AzResourceGroup -Name $ResourceGroup -Location $Location `
                -Tag $RGTags `
                -ErrorAction Stop

            return $true
        }
        catch {
			#return as false in the case of exception. Caller of this function is taking care if the value is false
            return $false
        }

	}
	
	static [void] CreateNewResourceGroupIfNotExists([string]$ResourceGroup, [string]$Location, [string] $Version) 
    {
       if((Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0)
	    {
		    [ResourceGroupHelper]::NewAzSKResourceGroup($ResourceGroup,$Location,$Version)
	    }  
	}
	
	static [void] SetResourceGroupTags([string]$RGName, [PSObject]$TagsHashTable, [bool] $Remove) {
		[ResourceGroupHelper]::SetResourceGroupTags($RGName, $TagsHashTable, $Remove, $true) 
	}

	static [void] SetResourceGroupTags([string]$RGName, [PSObject]$TagsHashTable, [bool] $Remove, [bool] $update) {
		$azskResourceGroup = Get-AzResourceGroup -Name $RGName -ErrorAction SilentlyContinue;
		if(($azskResourceGroup | Measure-Object).Count -gt 0)
		{
			$tags = $azskResourceGroup.Tags;
			if($null -eq $tags)
			{
				$tags = @{}
			}
			if(($TagsHashTable | Measure-Object).Count -gt 0)
			{
				$TagsHashTable.Keys | ForEach-Object {
					$key = $_;
					if($null -ne $tags -and $tags.ContainsKey($key))
					{
						if($update)
						{
							$tags[$key] = $TagsHashTable[$key];
						}
						if($Remove)
						{
							$tags.Remove($key);
						}
					}
					elseif(-not $Remove)
					{
						$tags.Add($key, $TagsHashTable[$key])
					}
				}
			}
			try
			{
				Set-AzResourceGroup -Name $RGName -Tag $tags -ErrorAction Stop
			}
			catch
			{
                #Skipping tag exception. Exception can be raised due to privilege issues.
				#[EventBase]::PublishGenericCustomMessage(" `r`nError occured while adding tag(s) on resource group [$RGName]. $($_.Exception)", [MessageType]::Warning);
			}
		}
    }

	static [bool] IsLatestVersionConfiguredOnSub([String] $ConfigVersion,[string] $TagName,[string] $FeatureName)
	{
		$IsLatestVersionPresent = [ResourceGroupHelper]::IsLatestVersionConfiguredOnSub($ConfigVersion,$TagName)
		if($IsLatestVersionPresent){
			#<TODO Framework: Use Publish Custom Message and use only one function for latest configurations versions>
			Write-Host "$FeatureName configuration in your subscription is already up to date. If you would like to reconfigure, please rerun the command with '-Force' parameter." -ForegroundColor Cyan
		}				
		return $IsLatestVersionPresent		
	}

	static [bool] IsLatestVersionConfiguredOnSub([String] $ConfigVersion,[string] $TagName)
	{
		$IsLatestVersionPresent = $false
		$tagsOnSub =  [ResourceGroupHelper]::GetResourceGroupTags([ConfigurationManager]::GetAzSKConfigData().AzSKRGName) 
		if($tagsOnSub)
		{
			$SubConfigVersion= $tagsOnSub.GetEnumerator() | Where-Object {$_.Name -eq $TagName -and $_.Value -eq $ConfigVersion}
			
			if(($SubConfigVersion | Measure-Object).Count -gt 0)
			{
				$IsLatestVersionPresent = $true				
			}			
		}
		return $IsLatestVersionPresent		
	}

}

class ResourceHelper: EventBase{

	static [void] SetResourceTags([string] $ResourceId, [PSObject] $TagsHashTable, [bool] $Remove, [bool] $update) {
		$azskResource = Get-AzResource -ResourceId $ResourceId -ErrorAction SilentlyContinue;
		if(($azskResource | Measure-Object).Count -gt 0)
		{
			$tags = $azskResource.Tags;
			if($null -eq $tags)
			{
				$tags = @{}
			}
			if(($TagsHashTable | Measure-Object).Count -gt 0)
			{
				$TagsHashTable.Keys | ForEach-Object {
					$key = $_;
					if($null -ne $tags -and $tags.ContainsKey($key))
					{
						if($update)
						{
							$tags[$key] = $TagsHashTable[$key];
						}
						if($Remove)
						{
							$tags.Remove($key);
						}
					}
					elseif(-not $Remove)
					{
						$tags.Add($key, $TagsHashTable[$key])
					}
				}
			}			
			try
			{
				Set-AzResource -ResourceId $ResourceId -Tag $tags -Force -ErrorAction Stop
			}
			catch
			{
				[EventBase]::PublishGenericCustomMessage(" `r`nError occured while adding tag(s) on resource [$ResourceId]. $($_.Exception)", [MessageType]::Warning);
			}
		}
	}
	
	static [bool] IsvNetExpressRouteConnected($resourceName, $resourceGroupName)
	{
		$result = $false;
		$gateways = @();
		$gateways += Get-AzVirtualNetworkGateway -ResourceGroupName $resourceGroupName | Where-Object { $_.GatewayType -eq "ExpressRoute" }
		if($gateways.Count -ne 0)
		{
			$vNet = Get-AzVirtualNetwork -Name $resourceName -ResourceGroupName $resourceGroupName 
			if($vnet)
			{
				$subnetIds = @();
				$vnet | ForEach-Object {
					if($_.Subnets)
					{
						$subnetIds += $_.Subnets | Select-Object -Property Id | Select-Object -ExpandProperty Id
					}
				};
            
				if($subnetIds.Count -ne 0)
				{
					$gateways | ForEach-Object {
						$result = $result -or (($_.IpConfigurations | Where-Object { $subnetIds -contains $_.Subnet.Id } | Measure-Object).Count -ne 0);
					};
				}
			}
		}
		return $result; 
	}

	static [void] RegisterResourceProviderIfNotRegistered([string] $provideNamespace)
	{
		if([string]::IsNullOrWhiteSpace($provideNamespace))
		{
			throw [System.ArgumentException] "The argument '$provideNamespace' is null or empty";
		}

		# Check if provider is registered or not
		if(-not [ResourceHelper]::IsProviderRegistered($provideNamespace))
		{
			[EventBase]::PublishGenericCustomMessage(" `r`nThe resource provider: [$provideNamespace] is not registered on the subscription. `r`nRegistering resource provider, this can take up to a minute...", [MessageType]::Warning);

			Register-AzResourceProvider -ProviderNamespace $provideNamespace

			$retryCount = 10;
			while($retryCount -ne 0 -and (-not [ResourceHelper]::IsProviderRegistered($provideNamespace)))
			{
				$timeout = 10
				Start-Sleep -Seconds $timeout
				$retryCount--;
				#[EventBase]::PublishGenericCustomMessage("Checking resource provider status every $timeout seconds...");
			}

			if(-not [ResourceHelper]::IsProviderRegistered($provideNamespace))
			{
				throw ([SuppressedException]::new(("Resource provider: [$provideNamespace] registration failed. `r`nTry registering the resource provider from Azure Portal --> your Subscription --> Resource Providers --> $provideNamespace --> Register"), [SuppressedExceptionType]::Generic))
			}
			else
			{
				[EventBase]::PublishGenericCustomMessage("Resource provider: [$provideNamespace] registration successful.`r`n ", [MessageType]::Update);
			}
		}
	}

	hidden static [bool] IsProviderRegistered([string] $provideNamespace)
	{
		return ((Get-AzResourceProvider -ProviderNamespace $provideNamespace | Where-Object { $_.RegistrationState -ne "Registered" } | Measure-Object).Count -eq 0);
	}

}


class StorageHelper: ResourceGroupHelper
{
	hidden [PSStorageAccount] $StorageAccount = $null;
	[string] $StorageAccountName;
	[string] $StorageKind; 
	[string] $AccessKey;
	[int] $HaveWritePermissions = 0;
	[int] $retryCount = 3;
	[int] $sleepIntervalInSecs = 10;
	static [StorageHelper] $AzSKStorageHelperInstance = $null
	hidden [string] $ResourceType = "Microsoft.Storage/storageAccounts";

	StorageHelper([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceGroupLocation, [string] $storageAccountName):
		Base($subscriptionId, $resourceGroupName, $resourceGroupLocation)
	{
		if([string]::IsNullOrWhiteSpace($storageAccountName))
		{
			throw [System.ArgumentException] ("The argument 'storageAccountName' is null or empty");
		}
		$this.StorageAccountName = $storageAccountName;
		$this.StorageKind = [Constants]::NewStorageKind;
	}
	StorageHelper([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceGroupLocation, [string] $storageAccountName, [string] $storageKind):
		Base($subscriptionId, $resourceGroupName, $resourceGroupLocation)
	{
		if([string]::IsNullOrWhiteSpace($storageAccountName))
		{
			throw [System.ArgumentException] ("The argument 'storageAccountName' is null or empty");
		}
		$this.StorageAccountName = $storageAccountName;
		$this.StorageKind = $storageKind
	}
	[void] UpdateCurrentInstance([StorageHelper] $AzSKStorageHelperInstance)
	{
		$this.AccessKey = $AzSKStorageHelperInstance.AccessKey
		$this.HaveWritePermissions = $AzSKStorageHelperInstance.HaveWritePermissions
	}

	static [void] UploadStorageBlobContent([string] $fileName, [string] $blobName, [string] $containerName, [object] $stgCtx)
	{
            Set-AzStorageBlobContent -Blob $blobName -Container $containerName -File $fileName -Context $stgCtx -Force | Out-Null
    }

    static [object] GetStorageBlobContent([string] $folderName, [string] $fileName, [string] $blobName, [string] $containerName, [object] $stgCtx)
	{
             $fileName = Join-Path $folderName.TrimEnd([IO.Path]::DirectorySeparatorChar) $fileName
             return [StorageHelper]::GetStorageBlobContent($fileName, $blobName, $containerName, $stgCtx)
    }

    static [object] GetStorageBlobContent([string] $fileName, [string] $blobName, [string] $containerName, [object] $stgCtx)
	{
		$result = Get-AzStorageBlobContent -Blob $blobName -Container $containerName -Destination $fileName -Context $stgCtx -Force 
        return $result
    }


	[void] CreateStorageIfNotExists()
	{
		if(-not $this.StorageAccount)
		{
			$isAzSKStorage = $false;
			$this.CreateResourceGroupIfNotExists();
			if($this.ResourceGroupName -eq [ConfigurationManager]::GetAzSKConfigData().AzSKRGName -and $this.StorageAccountName -like "$([Constants]::StorageAccountPreName)*")           
            {
                if($null -ne [StorageHelper]::AzSKStorageHelperInstance)
                {
                    $this.UpdateCurrentInstance([StorageHelper]::AzSKStorageHelperInstance);
                    return;
                }
                else {
                    $isAzSKStorage = $true
                }               
			}   
            $existingResources = Get-AzResource -ResourceGroupName $this.ResourceGroupName -ResourceType $this.ResourceType
            
            # Assuming 1 storage account is needed on Resource group
			if(($existingResources | Measure-Object).Count -gt 1)
			{
				throw ([SuppressedException]::new(("Multiple storage accounts found in resource group: [$($this.ResourceGroupName)]. This is not expected. Please contact support team."), [SuppressedExceptionType]::InvalidOperation))
			}
			elseif(($existingResources | Measure-Object).Count -eq 0)
			{
				$this.PublishCustomMessage("Creating a storage account: ["+ $this.StorageAccountName +"]...");
				$newStorage = [StorageHelper]::NewAzskCompliantStorage($this.StorageAccountName, $this.StorageKind, $this.ResourceGroupName, $this.ResourceGroupLocation);
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
			$this.StorageAccount = Get-AzStorageAccount -ResourceGroupName $this.ResourceGroupName -Name $this.StorageAccountName -ErrorAction Ignore
			if(-not ($this.StorageAccount -and $this.StorageAccount.Context))
			{
				$this.StorageAccount = $null;
				throw ([SuppressedException]::new("Unable to fetch the storage account [$($this.StorageAccountName)]", [SuppressedExceptionType]::InvalidOperation))				
			}

			#fetch access key
			$keys = Get-AzStorageAccountKey -ResourceGroupName $this.ResourceGroupName -Name $this.StorageAccountName -ErrorAction SilentlyContinue 
			if($keys)
			{
				$this.AccessKey = $keys[0].Value;
			}	
			
			#precompute storage access permissions for the current scan account
			$this.ComputePermissions();
            if($isAzSKStorage)
			{
				[StorageHelper]::AzSKStorageHelperInstance = $this
			}
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

		$container = Get-AzStorageContainer -Context $this.StorageAccount.Context -Name $containerName -ErrorAction Ignore
		if(($container| Measure-Object).Count -eq 0)
		{
			$this.PublishCustomMessage("Creating storage container [$containerName]...");
			$container = New-AzStorageContainer -Context $this.StorageAccount.Context -Name $containerName -Permission $accessType
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

	[AzureStorageTable] CreateTableIfNotExists([string] $tableName)
	{
		if([string]::IsNullOrWhiteSpace($tableName))
		{
			throw [System.ArgumentException] ("The argument 'tableName' is null or empty");
		}

		$this.CreateStorageIfNotExists();

		$table = Get-AzStorageTable -Context $this.StorageAccount.Context -Name $tableName -ErrorAction Ignore
		if(($table| Measure-Object).Count -eq 0)
		{
			$this.PublishCustomMessage("Creating table [$tableName]...");
			$table = New-AzStorageTable -Name $tableName -Context $this.StorageAccount.Context 
			if($table)
			{
				$this.PublishCustomMessage("Successfully created table: [$tableName] in storage: [$($this.StorageAccountName)]", [MessageType]::Update);
			}
		}

		if(($table| Measure-Object).Count -eq 0)
		{
			throw ([SuppressedException]::new("Unable to fetch/create the table [$tableName] under storage account [$($this.StorageAccountName)]", [SuppressedExceptionType]::InvalidOperation))				
		}

		return $table;
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
		$writeTestContainerName = "wt" + $(get-date).ToUniversalTime().ToString("yyyyMMddHHmmss");

		#see if user can create the test container in the storage account. If yes then user have both RW permissions. 
		try
		{
			
			New-AzStorageContainer -Context $this.StorageAccount.Context -Name $writeTestContainerName -ErrorAction Stop
			$this.HaveWritePermissions = 1
			Remove-AzStorageContainer -Name $writeTestContainerName -Context  $this.StorageAccount.Context -ErrorAction SilentlyContinue -Force
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
                if($_.Extension.ToLower() -ne '.zip')
                {
				    [Helpers]::RemoveUtf8BOM($_);
                }

				$loopValue = $this.retryCount;
				$sleepValue = $this.sleepIntervalInSecs;
				while($loopValue -gt 0)
				{
					$loopValue = $loopValue - 1;
					try {
						if($overwrite)
						{
							 [StorageHelper]::UploadStorageBlobContent($_.FullName, $blobName , $containerName ,$this.StorageAccount.Context)
							 #Set-AzStorageBlobContent -Blob $blobName -Container $containerName -File $_.FullName -Context $this.StorageAccount.Context -Force | Out-Null
						}
						else
						{
							$currentBlob = Get-AzStorageBlob -Blob $blobName -Container $containerName -Context $this.StorageAccount.Context -ErrorAction Ignore
						
							if(-not $currentBlob)
							{
								[StorageHelper]::UploadStorageBlobContent($_.FullName, $blobName, $containerName, $this.StorageAccount.Context)
								#Set-AzStorageBlobContent -Blob $blobName -Container $containerName -File $_.FullName -Context $this.StorageAccount.Context | Out-Null
							}
						}
						$loopValue = 0;
					}
					catch {
						#sleep for incremental 10 seconds before next retry;
						Start-Sleep -Seconds $sleepValue;
						$sleepValue = $sleepValue + 10;
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
					[StorageHelper]::GetStorageBlobContent($destinationPath, $blobName , $containerName ,$this.StorageAccount.Context)
					#Get-AzStorageBlobContent -Blob $blobName -Container $containerName -Context $this.StorageAccount.Context -Destination $destinationPath -Force -ErrorAction Stop
				}
				else {
					[StorageHelper]::GetStorageBlobContent($destinationPath, $blobName , $containerName ,$this.StorageAccount.Context)
					#Get-AzStorageBlobContent -Blob $blobName -Container $containerName -Context $this.StorageAccount.Context -Destination $destinationPath -ErrorAction Stop
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

	[psobject] DownloadFilesFromBlob([string] $containerName, [string] $blobName, [string] $destinationPath, [bool] $overwrite,[bool] $WithoutVirtualDirectory)
	{
		$loopValue = $this.retryCount;
		$sleepValue = $this.sleepIntervalInSecs;
		$blobDetails =$null
		if($WithoutVirtualDirectory)
		{
			$copyDestinationPath = Join-Path $([Constants]::AzSKTempFolderPath) "ContainerContent"
			[Helpers]::CreateFolderIfNotExist($copyDestinationPath,$true)
		}
		else
		{
			$copyDestinationPath= $destinationPath
		}

		while($loopValue -gt 0)
		{
			$loopValue = $loopValue - 1;
			try {
				if($overwrite)
				{
					[StorageHelper]::GetStorageBlobContent($copyDestinationPath, $blobName , $containerName ,$this.StorageAccount.Context)
					#$blobDetails= Get-AzStorageBlobContent -Blob $blobName -Container $containerName -Context $this.StorageAccount.Context -Destination $copyDestinationPath -Force -ErrorAction Stop
				}
				else {
					[StorageHelper]::GetStorageBlobContent($copyDestinationPath, $blobName , $containerName ,$this.StorageAccount.Context)
					#$blobDetails= Get-AzStorageBlobContent -Blob $blobName -Container $containerName -Context $this.StorageAccount.Context -Destination $copyDestinationPath -ErrorAction Stop
				}
				$loopValue = 0;
			}
			catch {
				#sleep for incremental 10 seconds before next retry;
				Start-Sleep -Seconds $sleepValue;
				$sleepValue = $sleepValue + 10;
			}
		}
		if($WithoutVirtualDirectory)
		{
			Get-ChildItem -Path $copyDestinationPath -Recurse -File | Copy-Item -Destination $destinationPath -Force
		}
		return $blobDetails
	}

	[string] GenerateSASToken([string] $containerName)
	{
		$this.CreateStorageContainerIfNotExists($containerName);
		$sasToken = New-AzStorageContainerSASToken -Name $containerName -Context $this.StorageAccount.Context -ExpiryTime (Get-Date).AddMonths(6) -Permission rl -Protocol HttpsOnly -StartTime (Get-Date).AddDays(-1)
		if([string]::IsNullOrWhiteSpace($sasToken))
		{
			throw ([SuppressedException]::new("Unable to create SAS token for storage account [$($this.StorageAccountName)]", [SuppressedExceptionType]::InvalidOperation))
		}
		return $sasToken;
	}
	[string] GenerateTableSASToken([string] $tableName)
	{
		$this.CreateTableIfNotExists($tableName);
		$sasToken = New-AzStorageTableSASToken -Context $this.StorageAccount.Context -Name $tableName -Permission rau -Protocol HttpsOnly -StartTime (Get-Date).AddDays(-1) -ExpiryTime (Get-Date).AddHours(6) 
		if([string]::IsNullOrWhiteSpace($sasToken))
		{
			throw ([SuppressedException]::new("Unable to create SAS token for table [$tableName] in storage account [$($this.StorageAccountName)]", [SuppressedExceptionType]::InvalidOperation))
		}
		return $sasToken;
	}

	[void] GetStorageAccountInstance()
	{
		# Fetch the Storage account context
		$this.StorageAccount = Get-AzStorageAccount -ResourceGroupName $this.ResourceGroupName -Name $this.StorageAccountName -ErrorAction Ignore
		if(-not ($this.StorageAccount -and $this.StorageAccount.Context))
		{
			$this.StorageAccount = $null;
			throw ([SuppressedException]::new("Unable to fetch the storage account [$($this.StorageAccountName)] under resource group [$($this.ResourceGroupName)]", [SuppressedExceptionType]::InvalidOperation))				
		}
	}

	#Function to download files from container with or without virtual directory
    [PSObject] DownloadFilesFromContainer([string] $containerName, [string] $folderName, [string] $destinationPath, [bool] $overwrite, [bool] $WithoutVirtualDirectory)
	{
		$loopValue = $this.retryCount;
		$sleepValue = $this.sleepIntervalInSecs;
		$blobList = @()
		[Helpers]::CreateFolderIfNotExist($destinationPath,$false)
		if($WithoutVirtualDirectory)
		{
			$copyDestinationPath = Join-Path $([Constants]::AzSKTempFolderPath) "ContainerContent"
			[Helpers]::CreateFolderIfNotExist($copyDestinationPath,$true)
		}
		else
		{
			$copyDestinationPath= $destinationPath

		}
		while($loopValue -gt 0)
		{
			$loopValue = $loopValue - 1;
			try {
				$blobs = Get-AzStorageBlob -Container $containerName -Context $($this.StorageAccount.Context) | Where-Object {$_.Name -like "*$folderName*"}				 
				foreach ($blob in $blobs)
				{
					$blobName = $blob.Name
					$blobList+= [StorageHelper]::GetStorageBlobContent($copyDestinationPath, $blobName.Split("/")[-1], $blobName , $containerName ,$this.StorageAccount.Context)
				}
				$loopValue = 0;
			}
			catch {
				#sleep for incremental 10 seconds before next retry;
				Start-Sleep -Seconds $sleepValue;
				$sleepValue = $sleepValue + 10;
			}
		}
		if($WithoutVirtualDirectory)
		{
			Get-ChildItem -Path $copyDestinationPath -Recurse -File | Copy-Item -Destination $destinationPath -Force
		}
		return $blobList
	}
	
	static [PSObject] NewAzskCompliantStorage([string]$StorageName, [string]$StorageKind,[string]$ResourceGroup,[string]$Location) {
        $storageSku = [Constants]::NewStorageSku
        $storageObject = $null
        try {
            #register resource providers
            [ResourceHelper]::RegisterResourceProviderIfNotRegistered("Microsoft.Storage");
            [ResourceHelper]::RegisterResourceProviderIfNotRegistered("microsoft.insights");

            #create storage
            $status = Get-AzStorageAccountNameAvailability -Name $StorageName
            if($null -ne $status -and  $status.NameAvailable -eq $true)
            {
                $newStorage = New-AzStorageAccount -ResourceGroupName $ResourceGroup `
                    -Name $StorageName `
                    -Type $storageSku `
                    -Location $Location `
                    -Kind $StorageKind `
                    -AccessTier Cool `
                    -EnableHttpsTrafficOnly $true `
                    -ErrorAction Stop

                $retryAccount = 0
                do {
                    $storageObject = Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageName -ErrorAction SilentlyContinue
                    Start-Sleep -seconds 2
                    $retryAccount++
                }while (!$storageObject -and $retryAccount -ne 6)

                if ($storageObject) {                                       

                    #set diagnostics on
                    $currentContext = $storageObject.Context
                    Set-AzStorageServiceLoggingProperty -ServiceType Blob -LoggingOperations All -Context $currentContext -RetentionDays 365 -PassThru -ErrorAction Stop
                    Set-AzStorageServiceMetricsProperty -MetricsType Hour -ServiceType Blob -Context $currentContext -MetricsLevel ServiceAndApi -RetentionDays 365 -PassThru -ErrorAction Stop
                }
            }
            else
            {
                throw ([SuppressedException]::new(("The specified name for the storage account is not available. Please rerun this command to try a different name."), [SuppressedExceptionType]::Generic));          
            }
        }
        catch {
            [EventBase]::PublishGenericException($_);
            $storageObject = $null
            #clean-up storage if error occurs
            if ((Get-AzResource -ResourceGroupName $ResourceGroup -Name $StorageName|Measure-Object).Count -gt 0) {
            # caused deletion of storage on any exception.
                # Remove-AzureRmStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageName -Force -ErrorAction SilentlyContinue
                
            }
        }
        return $storageObject
	}
	
	static [PSObject] NewAzskCompliantStorage([string]$StorageName, [string]$ResourceGroup, [string]$Location) {
		return [StorageHelper]::NewAzskCompliantStorage($StorageName,[Constants]::NewStorageKind,[string]$ResourceGroup,[string]$Location)
	  }

	static [string] CreateStorageAccountSharedKey([string] $StringToSign,[string] $AccountName,[string] $AccessKey)
	{
        $KeyBytes = [System.Convert]::FromBase64String($AccessKey)
        $HMAC = New-Object System.Security.Cryptography.HMACSHA256
        $HMAC.Key = $KeyBytes
        $UnsignedBytes = [System.Text.Encoding]::UTF8.GetBytes($StringToSign)
        $KeyHash = $HMAC.ComputeHash($UnsignedBytes)
        $SignedString = [System.Convert]::ToBase64String($KeyHash)
        $sharedKey = $AccountName+":"+$SignedString
        return $sharedKey    	
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
			[ResourceHelper]::RegisterResourceProviderIfNotRegistered("microsoft.insights");
			$existingResources = Get-AzResource -ResourceGroupName $this.ResourceGroupName -ResourceType $this.ResourceType

			# Assuming 1 storage account is needed on Resource group
			if(($existingResources | Measure-Object).Count -gt 1)
			{
				throw ([SuppressedException]::new(("Multiple application insight resources found in resource group: [$($this.ResourceGroupName)]. This is not expected. Please contact support team."), [SuppressedExceptionType]::InvalidOperation))
			}
			elseif(($existingResources | Measure-Object).Count -eq 0)
			{
				$this.PublishCustomMessage("Creating an application insight resource ["+ $this.AppInsightName +"]...");
				$newResource = New-AzResource -ResourceName $this.AppInsightName -ResourceGroupName $this.ResourceGroupName -ResourceType $this.ResourceType `
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
			$this.AppInsightInstance = Get-AzResource -Name $this.AppInsightName -ResourceGroupName $this.ResourceGroupName -ResourceType $this.ResourceType -ExpandProperties 
			if(-not ($this.AppInsightInstance -and $this.AppInsightInstance.Properties))
			{
				$this.AppInsightInstance = $null;
				throw ([SuppressedException]::new("Unable to fetch application insight resource [$($this.AppInsightName)]", [SuppressedExceptionType]::InvalidOperation))				
			}
		}
	}
}

