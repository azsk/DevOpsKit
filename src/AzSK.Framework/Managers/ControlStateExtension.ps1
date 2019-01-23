using namespace System.Management.Automation
Set-StrictMode -Version Latest

class ControlStateExtension
{
	hidden [PSObject] $AzSKResourceGroup = $null;
	hidden [PSObject] $AzSKStorageAccount = $null;
	hidden [PSObject] $AzSKStorageContainer = $null;
	hidden [PSObject] $ControlStateIndexer = $null;	
	hidden [int] $HasControlStateReadPermissions = -1;
	hidden [int] $HasControlStateWritePermissions = -1;
	hidden [string]	$IndexerBlobName ="Resource.index.json"
	hidden [int] $retryCount = 3;
	hidden [string] $UniqueRunId;

	hidden [SubscriptionContext] $SubscriptionContext;
    hidden [InvocationInfo] $InvocationContext;

	ControlStateExtension([SubscriptionContext] $subscriptionContext, [InvocationInfo] $invocationContext)
	{
		$this.SubscriptionContext = $subscriptionContext;
		$this.InvocationContext = $invocationContext;		
	}

	hidden [void] Initialize([bool] $CreateResourcesIfNotExists)
	{
		if([string]::IsNullOrWhiteSpace($this.UniqueRunId))
		{
			$this.UniqueRunId = $(Get-Date -format "yyyyMMdd_HHmmss");
		}
		$this.GetAzSKControlStateContainer($CreateResourcesIfNotExists)
	}

	hidden [PSObject] GetAzSKRG([bool] $createIfNotExists)
	{
		$azSKConfigData = [ConfigurationManager]::GetAzSKConfigData()

		$resourceGroup = Get-AzureRmResourceGroup -Name $azSKConfigData.AzSKRGName -ErrorAction SilentlyContinue
		if($createIfNotExists -and ($null -eq $resourceGroup -or ($resourceGroup | Measure-Object).Count -eq 0))
		{
			if([Helpers]::NewAzSKResourceGroup($azSKConfigData.AzSKRGName, $azSKConfigData.AzSKLocation, ""))
			{
				$resourceGroup = Get-AzureRmResourceGroup -Name $azSKConfigData.AzSKRGName -ErrorAction SilentlyContinue
			}
		}
		$this.AzSKResourceGroup = $resourceGroup
		return $resourceGroup;
	}

	hidden [void] GetAzSKStorageAccount($createIfNotExists)
	{
	    $azSKConfigData = [ConfigurationManager]::GetAzSKConfigData()
		if($null -eq $this.AzSKResourceGroup)
		{
			$this.GetAzSKRG($createIfNotExists);
		}
		if($null -ne $this.AzSKResourceGroup)
		{
			$StorageAccount  = $null;
			$loopValue = $this.retryCount;
			while($loopValue -gt 0)
			{
				$loopValue = $loopValue - 1;
				try
				{
					$StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $this.AzSKResourceGroup.ResourceGroupName -ErrorAction Stop | Where-Object {$_.StorageAccountName -like 'azsk*'} -ErrorAction Stop 
					$loopValue = 0;
				}
				catch
				{
					#eat this exception and retry
				}
			}			

			#if no storage account found then it assumes that there is no control state feature is not used and if there are more than one storage account found it assumes the same
			if($createIfNotExists -and ($null -eq $StorageAccount -or ($StorageAccount | Measure-Object).Count -eq 0))
			{
				$storageAccountName = ("azsk" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"));	
				$storageObject = [Helpers]::NewAzskCompliantStorage($storageAccountName, $this.AzSKResourceGroup.ResourceGroupName, $azSKConfigData.AzSKLocation)
				if($null -ne $storageObject -and ($storageObject | Measure-Object).Count -gt 0)
				{
					$loopValue = $this.retryCount;
					while($loopValue -gt 0)
					{
						$loopValue = $loopValue - 1;
						try
						{
							$StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $this.AzSKResourceGroup.ResourceGroupName -ErrorAction Stop | Where-Object {$_.StorageAccountName -like 'azsk*'} -ErrorAction Stop 					
							$loopValue = 0;
						}
						catch
						{
							#eat this exception and retry
						}
					}					
				}					
			}
			$this.AzSKStorageAccount = $StorageAccount;
		}
	}

	hidden [void] GetAzSKControlStateContainer([bool] $createIfNotExists)
	{
		$ContainerName = [Constants]::AttestationDataContainerName;
		if($null -eq $this.AzSKStorageAccount)
		{
			$this.GetAzSKStorageAccount($createIfNotExists)
		}
		if($null -eq $this.AzSKStorageAccount)
		{
			#No storage account => no permissions at all
			$this.HasControlStateReadPermissions = 0
			$this.HasControlStateWritePermissions = 0
			return;
		}

		
		$this.HasControlStateReadPermissions = 0					
		$this.HasControlStateWritePermissions = 0
		$writeTestContainerName = "wt" + $(get-date).ToUniversalTime().ToString("yyyyMMddHHmmss");

		#see if user can create the test container in the storage account. If yes then user have both RW permissions. 
		try
		{
			$containerObject = Get-AzureStorageContainer -Context $this.AzSKStorageAccount.Context -Name $writeTestContainerName -ErrorAction SilentlyContinue
			if($null -ne $containerObject)
			{
				Remove-AzureStorageContainer -Name $writeTestContainerName -Context  $this.AzSKStorageAccount.Context -ErrorAction Stop -Force
				$this.HasControlStateWritePermissions = 1
				$this.HasControlStateReadPermissions = 1
			}
			else
			{
				New-AzureStorageContainer -Context $this.AzSKStorageAccount.Context -Name $writeTestContainerName -ErrorAction Stop
				$this.HasControlStateWritePermissions = 1
				$this.HasControlStateReadPermissions = 1
				Remove-AzureStorageContainer -Name $writeTestContainerName -Context  $this.AzSKStorageAccount.Context -ErrorAction SilentlyContinue -Force
			}				
		}
		catch
		{
			$this.HasControlStateWritePermissions = 0
		}
		if($this.HasControlStateWritePermissions -eq 1)
		{
			try
			{
				if($createIfNotExists)
				{
					New-AzureStorageContainer -Context $this.AzSKStorageAccount.Context -Name $ContainerName -ErrorAction SilentlyContinue
				}
				$containerObject = Get-AzureStorageContainer -Context $this.AzSKStorageAccount.Context -Name $ContainerName -ErrorAction SilentlyContinue
				$this.AzSKStorageContainer = $containerObject;					
			}
			catch
			{
				# Add retry logic, after 3 unsuccessful attempt throw the exception.
			}
		}
		else
		{
			# If user doesn't have write permission, check at least user have read permission
			try
			{
				#Able to read the container then read permissions are good
				$containerObject = Get-AzureStorageContainer -Context $this.AzSKStorageAccount.Context -Name $ContainerName -ErrorAction Stop
				$this.AzSKStorageContainer = $containerObject;
				$this.HasControlStateReadPermissions = 1
			}
			catch
			{
				#Resetting permissions in the case of exception
				$this.HasControlStateReadPermissions = 0			
			}	
		}		
	}
	
	hidden [bool] ComputeControlStateIndexer()
	{
		#check for permission validation
		if($this.HasControlStateReadPermissions -le 0) 
		{
			return $false;
		}
		#return if you don't have the required state attestation configuration during the runtime evaluation
		if( $null -eq $this.AzSKResourceGroup -or $null -eq $this.AzSKStorageAccount -or $null -eq $this.AzSKStorageContainer)
		{
			return $false;
		}
		$StorageAccount = $this.AzSKStorageAccount;
		$containerObject = $this.AzSKStorageContainer;
		$ContainerName = ""
		if($null -ne $this.AzSKStorageContainer)
		{
			$ContainerName = $this.AzSKStorageContainer.Name
		}		
		$indexerBlob = $null;		
		$loopValue = $this.retryCount;
		while($loopValue -gt 0)
		{
			$loopValue = $loopValue - 1;
			try
			{
				$indexerBlob = Get-AzureStorageBlob -Container $ContainerName -Blob $this.IndexerBlobName -Context $StorageAccount.Context -ErrorAction Stop
				$loopValue = 0;
			}
			catch
			{
				#Do Nothing. Below code would create a default indexer.
			}
		}
		[ControlStateIndexer[]] $indexerObjects = @();
		$this.ControlStateIndexer  = $indexerObjects
		if($null -eq $indexerBlob)
		{			
			return $true;
		}
		$AzSKTemp = [Constants]::AzSKAppFolderPath + "\Temp\$($this.UniqueRunId)\ServerControlState";
		if(-not (Test-Path -Path $AzSKTemp))
		{
			mkdir -Path $AzSKTemp -Force
		}

		$indexerObject = @();
		$loopValue = $this.retryCount;
		while($loopValue -gt 0)
		{
			$loopValue = $loopValue - 1;
			try
			{
				Get-AzureStorageBlobContent -CloudBlob $indexerBlob.ICloudBlob -Context $StorageAccount.Context -Destination $AzSKTemp -Force -ErrorAction Stop
				$indexerObject = Get-ChildItem -Path "$AzSKTemp\$($this.IndexerBlobName)" -Force -ErrorAction Stop | Get-Content | ConvertFrom-Json
				$loopValue = 0;
			}
			catch
			{
				#eat this exception and retry
			}
		}
		$this.ControlStateIndexer += $indexerObject;
		return $true;
	}

	hidden [PSObject] GetControlState([string] $id)
	{
		try
		{
			[ControlState[]] $controlStates = @();
			$retVal = $this.ComputeControlStateIndexer();
			if($null -ne $this.ControlStateIndexer -and  $retVal)
			{
				$indexes = @();
				$indexes += $this.ControlStateIndexer 
				$hashId = [Helpers]::ComputeHash($id)
				$selectedIndex = $indexes | Where-Object { $_.HashId -eq $hashId}
				
				if(($selectedIndex | Measure-Object).Count -gt 0)
				{
					$hashId = $selectedIndex.HashId | Select-Object -Unique
					$controlStateBlobName = $hashId + ".json"
					$azSKConfigData = [ConfigurationManager]::GetAzSKConfigData()
					#$azSKConfigData.$AzSKRGName
					#Look of is there is a AzSK RG and AzSK Storage account
					$StorageAccount = $this.AzSKStorageAccount;						
					$containerObject = $this.AzSKStorageContainer
					$ContainerName = ""
					if($null -ne $this.AzSKStorageContainer)
					{
						$ContainerName = $this.AzSKStorageContainer.Name
					}

					$loopValue = $this.retryCount;
					$controlStateBlob = $null;
					while($loopValue -gt 0 -and $null -eq $controlStateBlob)
					{
						$loopValue = $loopValue - 1;
						$controlStateBlob = Get-AzureStorageBlob -Container $ContainerName -Blob $controlStateBlobName -Context $StorageAccount.Context -ErrorAction SilentlyContinue
					}

					if($null -eq $controlStateBlob)
					{
						return $null;
					}
					$AzSKTemp = [Constants]::AzSKAppFolderPath + "\Temp\$($this.UniqueRunId)\ServerControlState";
					if(-not (Test-Path -Path $AzSKTemp))
					{
						mkdir -Path $AzSKTemp -Force
					}

					$loopValue = $this.retryCount;
					while($loopValue -gt 0)
					{
						$loopValue = $loopValue - 1;
						try
						{
							Get-AzureStorageBlobContent -CloudBlob $controlStateBlob.ICloudBlob -Context $StorageAccount.Context -Destination $AzSKTemp -Force -ErrorAction Stop
							$loopValue = 0;
						}
						catch
						{
							#eat this exception and retry
						}
					}
					$ControlStatesJson = Get-ChildItem -Path "$AzSKTemp\$controlStateBlobName" -Force | Get-Content | ConvertFrom-Json 
					if($null -ne $ControlStatesJson)
					{					
						$ControlStatesJson | ForEach-Object {
							try
							{
								$controlState = [ControlState] $_

								#this can be removed after we check there is no value for attestationstatus coming to azsktm database
								if($controlState.AttestationStatus -eq [AttestationStatus]::NotFixed)
								{
									$controlState.AttestationStatus = [AttestationStatus]::WillNotFix
								}

								$controlStates += $controlState;								
							}
							catch 
							{
								[EventBase]::PublishGenericException($_);
							}
						}
					}
				}
			}
			return $controlStates;
		}
		finally{
			[Helpers]::CleanupLocalFolder([Constants]::AzSKAppFolderPath + "\Temp\$($this.UniqueRunId)");
		}
	}

	hidden [void] SetControlState([string] $id, [ControlState[]] $controlStates, [bool] $Override)
	{		
		$AzSKTemp = [Constants]::AzSKAppFolderPath + "\Temp\$($this.UniqueRunId)\ServerControlState";				
		if(-not (Test-Path "$AzSKTemp\ControlState"))
		{
			mkdir -Path "$AzSKTemp\ControlState" -ErrorAction Stop | Out-Null
		}
		else
		{
			Remove-Item -Path "$AzSKTemp\ControlState\*" -Force -Recurse 
		}

		$hash = [Helpers]::ComputeHash($id);
		$indexerPath = "$AzSKTemp\ControlState\$($this.IndexerBlobName)"
		$fileName = "$AzSKTemp\ControlState\$hash.json"	
		
		$StorageAccount = $this.AzSKStorageAccount;						
		$containerObject = $this.AzSKStorageContainer
		$ContainerName = ""
		if($null -ne $this.AzSKStorageContainer)
		{
			$ContainerName = $this.AzSKStorageContainer.Name
		}


		#Filter out the "Passed" controls
		$finalControlStates = $controlStates | Where-Object { $_.ActualVerificationResult -ne [VerificationResult]::Passed};
		if(($finalControlStates | Measure-Object).Count -gt 0)
		{
			if($Override)
			{
				# in the case of override, just persist what is evaluated in the current context. No merging with older data
				$this.UpdateControlIndexer($id, $finalControlStates, $false);
				$finalControlStates = $finalControlStates | Where-Object { $_.State};
			}
			else
			{
				#merge with the exiting if found
				$persistedControlStates = $this.GetPersistedControlStates("$hash.json");
				$finalControlStates = $this.MergeControlStates($persistedControlStates, $finalControlStates);
				$this.UpdateControlIndexer($id, $finalControlStates, $false);
			}
		}
		else
		{
			#purge would remove the entry from the control indexer and also purge the stale state json.
			$this.PurgeControlState($id);
		}
		if(($finalControlStates|Measure-Object).Count -gt 0)
		{
			[Helpers]::ConvertToJsonCustom($finalControlStates) | Out-File $fileName -Force		
		}

		if($null -ne $this.ControlStateIndexer)
		{				
			[Helpers]::ConvertToJsonCustom($this.ControlStateIndexer) | Out-File $indexerPath -Force
			$controlStateArray = Get-ChildItem -Path "$AzSKTemp\ControlState"				
			$controlStateArray | ForEach-Object {
				$state = $_;
				$loopValue = $this.retryCount;
				while($loopValue -gt 0)
				{
					$loopValue = $loopValue - 1;
					try
					{
						Set-AzureStorageBlobContent -File $state.FullName -Container $ContainerName -BlobType Block -Context $StorageAccount.Context -Force -ErrorAction Stop
						$loopValue = 0;
					}
					catch
					{
						#eat this exception and retry
					}
				}
			}
		}
		else
		{
			#clean up the container as there is no indexer
			Get-AzureStorageBlob -Container $ContainerName -Context $StorageAccount.Context | Remove-AzureStorageBlob  
		}
	}

	hidden [void] PurgeControlState([string] $id)
	{		
		$AzSKTemp = [Constants]::AzSKAppFolderPath + "\Temp\$($this.UniqueRunId)\ServerControlState";				
		if(-not (Test-Path "$AzSKTemp\ControlState"))
		{
			mkdir -Path "$AzSKTemp\ControlState" -ErrorAction Stop | Out-Null
		}
		else
		{
			Remove-Item -Path "$AzSKTemp\ControlState\*" -Force 
		}

		$hash = [Helpers]::ComputeHash($id);
		$indexerPath = "$AzSKTemp\ControlState\$($this.IndexerBlobName)"
		$fileName = "$AzSKTemp\ControlState\$hash.json"	
		
		$StorageAccount = $this.AzSKStorageAccount;						
		$containerObject = $this.AzSKStorageContainer
		$ContainerName = ""
		if($null -ne $this.AzSKStorageContainer)
		{
			$ContainerName = $this.AzSKStorageContainer.Name
		}
		
		$this.UpdateControlIndexer($id, $null, $true);
		if($null -ne $this.ControlStateIndexer)
		{				
			[Helpers]::ConvertToJsonCustom($this.ControlStateIndexer) | Out-File $indexerPath -Force
			$controlStateArray = Get-ChildItem -Path "$AzSKTemp\ControlState"				
			$controlStateArray | ForEach-Object {
				$state = $_
				$loopValue = $this.retryCount;
				while($loopValue -gt 0)
				{
					$loopValue = $loopValue - 1;
					try
					{
						Set-AzureStorageBlobContent -File $state.FullName -Container $ContainerName -BlobType Block -Context $StorageAccount.Context -Force -ErrorAction Stop
						$loopValue = 0;
					}
					catch
					{
						#eat this exception and retry
					}
				}
			}
		}
		$loopValue = $this.retryCount;
		while($loopValue -gt 0)
		{
			$loopValue = $loopValue - 1;
			try
			{
				Remove-AzureStorageBlob -Blob "$hash.json" -Context $StorageAccount.Context -Container $ContainerName -Force -ErrorAction Stop
				$loopValue = 0;
			}
			catch
			{
				#eat this exception and retry
			}
		}		
	}

	hidden [ControlState[]] GetPersistedControlStates([string] $controlStateBlobName)
	{
		$AzSKTemp = [Constants]::AzSKAppFolderPath + "\Temp\$($this.UniqueRunId)\ServerControlState";
		if(-not (Test-Path "$AzSKTemp\ExistingControlStates"))
		{
			mkdir -Path "$AzSKTemp\ExistingControlStates" -ErrorAction Stop | Out-Null
		}
		$StorageAccount = $this.AzSKStorageAccount;						
		$containerObject = $this.AzSKStorageContainer
		$ContainerName = ""
		if($null -ne $this.AzSKStorageContainer)
		{
			$ContainerName = $this.AzSKStorageContainer.Name
		}
		[ControlState[]] $ControlStatesJson = @()

		$loopValue = $this.retryCount;
		while($loopValue -gt 0)
		{
			$loopValue = $loopValue - 1;
			try
			{
				$controlStateBlob = Get-AzureStorageBlob -Container $ContainerName -Blob $controlStateBlobName -Context $StorageAccount.Context -ErrorAction Stop
				Get-AzureStorageBlobContent -CloudBlob $controlStateBlob.ICloudBlob -Context $StorageAccount.Context -Destination "$AzSKTemp\ExistingControlStates" -Force -ErrorAction Stop
				$ControlStatesJson = Get-ChildItem -Path "$AzSKTemp\ExistingControlStates\$controlStateBlobName" -Force -ErrorAction Stop | Get-Content | ConvertFrom-Json 
				$loopValue = 0;
			}
			catch
			{
				$ControlStatesJson = @()
				#eat this exception and retry
			}
		}
			
        if(($ControlStatesJson | Measure-Object).Count -gt 0)
        {
		    $ControlStatesJson | ForEach-Object {
			    $ControlState = $_;
			    #this can be removed after we check there is no value for attestationstatus coming to azsktm database
			    if($ControlState.AttestationStatus -eq [AttestationStatus]::NotFixed)
			    {
				    $ControlState.AttestationStatus = [AttestationStatus]::WillNotFix
			    }
		    }
        }

		return $ControlStatesJson
	}

	hidden [ControlState[]] MergeControlStates([ControlState[]] $persistedControlStates,[ControlState[]] $controlStates)
	{
		[ControlState[]] $computedControlStates = $controlStates;
		if(($computedControlStates | Measure-Object).Count -le 0)
		{
			$computedControlStates = @();
		}
		if(($persistedControlStates | Measure-Object).Count -gt 0)
		{
			$persistedControlStates | ForEach-Object {
				$controlState = $_;
				if(($computedControlStates | Where-Object { ($_.InternalId -eq $controlState.InternalId) -and ($_.ChildResourceName -eq $controlState.ChildResourceName) } | Measure-Object).Count -le 0)
				{
					$computedControlStates += $controlState;
				}
			}
		}
		#remove the control states with null state which would be in the case of clear attestation.
		$computedControlStates = $computedControlStates | Where-Object { $_.State}

		return $computedControlStates;
	}

	hidden [void] UpdateControlIndexer([string] $id, [ControlState[]] $controlStates, [bool] $ToBeDeleted)
	{
		$this.ControlStateIndexer = $null;
		$retVal = $this.ComputeControlStateIndexer();
		$StorageAccount = $this.AzSKStorageAccount;						
		$containerObject = $this.AzSKStorageContainer
		$ContainerName = ""
		if($null -ne $this.AzSKStorageContainer)
		{
			$ContainerName = $this.AzSKStorageContainer.Name
		}
		if($retVal)
		{				
			$tempHash = [Helpers]::ComputeHash($id);
			#take the current indexer value
			$filteredIndexerObject = $this.ControlStateIndexer | Where-Object { $_.HashId -eq $tempHash}
			#remove the current index from the list
			$filteredIndexerObject2 = $this.ControlStateIndexer | Where-Object { $_.HashId -ne $tempHash}
			$this.ControlStateIndexer = @();
			$this.ControlStateIndexer += $filteredIndexerObject2
			if(-not $ToBeDeleted)
			{	
				$currentIndexObject = $null;
				#check if there is an existing index and the controlstates are present for that index resource
				if(($filteredIndexerObject | Measure-Object).Count -gt 0 -and ($controlStates | Measure-Object).Count -gt 0)
				{
					$currentIndexObject = $filteredIndexerObject;
					if(($filteredIndexerObject | Measure-Object).Count -gt 1)
					{
						$currentIndexObject = $filteredIndexerObject | Select-Object -Last 1
					}					
					$currentIndexObject.ExpiryTime = [DateTime]::UtcNow.AddMonths(3);
					$currentIndexObject.AttestedBy =  [Helpers]::GetCurrentSessionUser();
					$currentIndexObject.AttestedDate = [DateTime]::UtcNow;
					$currentIndexObject.Version = "1.0";
				}
				elseif(($controlStates | Measure-Object).Count -gt 0)
				{
					$currentIndexObject = [ControlStateIndexer]::new();
					$currentIndexObject.ResourceId = $id
					$currentIndexObject.HashId = $tempHash;
					$currentIndexObject.ExpiryTime = [DateTime]::UtcNow.AddMonths(3);
					$currentIndexObject.AttestedBy = [Helpers]::GetCurrentSessionUser();
					$currentIndexObject.AttestedDate = [DateTime]::UtcNow;
					$currentIndexObject.Version = "1.0";
				}
				if($null -ne $currentIndexObject)
				{
					$this.ControlStateIndexer += $currentIndexObject;			
				}
			}
		}
	}
	
	[bool] HasControlStateReadAccessPermissions()
	{
		if($this.HasControlStateReadPermissions -le 0)
		{
			return $false;
		}
		else
		{
			return $true;
		}
	}

	[void] SetControlStateReadAccessPermissions([int] $value)
	{
		$this.HasControlStateReadPermissions  = $value
	}

	[void] SetControlStateWriteAccessPermissions([int] $value)
	{
		$this.HasControlStateWritePermissions  = $value
	}

	[bool] HasControlStateWriteAccessPermissions()
	{		
		if($this.HasControlStateWritePermissions -le 0)
		{
			return $false;
		}
		else
		{
			return $true;
		}
	}
}