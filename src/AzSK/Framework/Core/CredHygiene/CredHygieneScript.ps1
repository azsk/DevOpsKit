Set-StrictMode -Version Latest

class CredHygiene : CommandBase{
    [string] $credName;
    [string] $credLocation;
    [int] $rotationInt;
    [string] $alertPhoneNumber = "";
	[string] $alertEmail;
    [string] $comment;
    hidden [string] $AzSKTemp = (Join-Path $([Constants]::AzSKAppFolderPath) $([Constants]::RotationMetadataSubPath)); 
    hidden [PSObject] $AzSKResourceGroup = $null;
	hidden [PSObject] $AzSKStorageAccount = $null;
	hidden [PSObject] $RotationMetadataContainer = $null;
	hidden [string] $RotationMetadataContainerName = [Constants]::RotationMetadataContainerName

    CredHygiene([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext)
    { }

    hidden [void] GetAzSKRotationMetadatContainer()
	{
		if($null -eq $this.AzSKStorageAccount)
		{
			$this.GetAzSKStorageAccount()
		}
		if($null -eq $this.AzSKStorageAccount)
		{
			return;
		}


		try
		{
			$containerObject = Get-AzStorageContainer -Context $this.AzSKStorageAccount.Context -Name $this.RotationMetadataContainerName -ErrorAction Stop
			$this.RotationMetadataContainer = $containerObject;
		}
		catch
		{
			try
			{
				New-AzStorageContainer -Context $this.AzSKStorageAccount.Context -Name $this.RotationMetadataContainerName -ErrorAction SilentlyContinue
				$containerObject = Get-AzStorageContainer -Context $this.AzSKStorageAccount.Context -Name $this.RotationMetadataContainerName -ErrorAction SilentlyContinue
				$this.RotationMetadataContainer = $containerObject;
			}
			catch
			{
				#Do nothing
			}
		}
	}

	hidden [void] GetAzSKStorageAccount()
	{
		if($null -eq $this.AzSKResourceGroup)
		{
			$this.GetAzSKRG();
		}
		if($null -ne $this.AzSKResourceGroup)
		{
			$StorageAccount = Get-AzStorageAccount -ResourceGroupName $this.AzSKResourceGroup.ResourceGroupName | Where-Object {$_.StorageAccountName -like 'azsk*'} -ErrorAction SilentlyContinue
			#if no storage account found then it assumes that there is no control state feature is not used and if there are more than one storage account found it assumes the same
			$this.AzSKStorageAccount = $StorageAccount;
		}
	}

	hidden [PSObject] GetAzSKRG()
	{
		$azSKConfigData = [ConfigurationManager]::GetAzSKConfigData()
		$resourceGroup = Get-AzResourceGroup -Name $azSKConfigData.AzSKRGName -ErrorAction SilentlyContinue
		$this.AzSKResourceGroup = $resourceGroup
		return $resourceGroup;
	}

	[void] PrintDetails($credentialInfo){
		$this.PublishCustomMessage("`n")
		$this.PublishCustomMessage("Settings for the AzSK tracked credential [$($credentialInfo.credName)] `n`n", [MessageType]::Info) 
		$this.PublishCustomMessage("`n")

		$this.PublishCustomMessage("Name:`t`t`t`t`t`t`t`t`t$($credentialInfo.credName)", [MessageType]::Default)
		$this.PublishCustomMessage("Location:`t`t`t`t`t`t`t`t$($credentialInfo.credLocation)", [MessageType]::Default)
		$this.PublishCustomMessage("Rotation interval (days):`t`t`t`t$($credentialInfo.rotationInt)", [MessageType]::Default)
		$this.PublishCustomMessage("Alert email:`t`t`t`t`t`t`t$($credentialInfo.emailId)", [MessageType]::Default)
		$this.PublishCustomMessage("Alert phone:`t`t`t`t`t`t`t$($credentialInfo.contactNumber)", [MessageType]::Default)
		$this.PublishCustomMessage("Created on:`t`t`t`t`t`t`t`t$($credentialInfo.firstUpdatedOn)", [MessageType]::Default)
		$this.PublishCustomMessage("Created by:`t`t`t`t`t`t`t`t$($credentialInfo.firstUpdatedBy)", [MessageType]::Default)
		$this.PublishCustomMessage("Last update:`t`t`t`t`t`t`t$($credentialInfo.lastUpdatedOn)", [MessageType]::Default)
		$this.PublishCustomMessage("Updated by:`t`t`t`t`t`t`t`t$($credentialInfo.lastUpdatedBy)", [MessageType]::Default)
		$this.PublishCustomMessage("Comment:`t`t`t`t`t`t`t`t$($credentialInfo.comment)`n", [MessageType]::Default)

		if($credentialInfo.credLocation -eq "AppService"){
			$this.PublishCustomMessage([Constants]::SingleDashLine);
			$this.PublishCustomMessage("AppService name:`t`t`t`t`t`t$($credentialInfo.resourceGroup)", [MessageType]::Default)
			$this.PublishCustomMessage("Resource group:`t`t`t`t`t`t`t$($credentialInfo.resourceName)", [MessageType]::Default)
			$this.PublishCustomMessage("AppService config type:`t`t`t`t`t$($credentialInfo.appConfigType)", [MessageType]::Default)
			$this.PublishCustomMessage("AppService config name:`t`t`t`t`t$($credentialInfo.appConfigName)", [MessageType]::Default)
		}
		if($credentialInfo.credLocation -eq "KeyVault"){
			$this.PublishCustomMessage([Constants]::SingleDashLine);
			$this.PublishCustomMessage("Key vault name:`t`t`t`t`t`t`t$($credentialInfo.kvName)", [MessageType]::Default)
			$this.PublishCustomMessage("Credential type:`t`t`t`t`t`t$($credentialInfo.kvCredType)", [MessageType]::Default)
			$this.PublishCustomMessage("Credential name:`t`t`t`t`t`t$($credentialInfo.kvCredName)", [MessageType]::Default)
			$this.PublishCustomMessage("Expiry time:`t`t`t`t`t`t`t$($credentialInfo.expiryTime)", [MessageType]::Default)
			$this.PublishCustomMessage("Version:`t`t`t`t`t`t`t`t$($credentialInfo.Version)", [MessageType]::Default)
		}

		$this.PublishCustomMessage("`n")		
	}

	[void] PrintInfo ($credentialInfo){
		$this.PublishCustomMessage("`n")
		$this.PublishCustomMessage("Settings for the AzSK tracked credential [$($credentialInfo.credName)] `n`n", [MessageType]::Info) 
		$this.PublishCustomMessage("`n")

		$this.PublishCustomMessage("Name:`t`t`t`t`t`t`t`t`t$($credentialInfo.credName)", [MessageType]::Default)
		$this.PublishCustomMessage("Location:`t`t`t`t`t`t`t`t$($credentialInfo.credLocation)", [MessageType]::Default)
		$this.PublishCustomMessage("Rotation interval (days):`t`t`t`t$($credentialInfo.rotationInt)", [MessageType]::Default)
		$this.PublishCustomMessage("Alert email:`t`t`t`t`t`t`t$($credentialInfo.emailId)", [MessageType]::Default)
		$this.PublishCustomMessage("Alert phone:`t`t`t`t`t`t`t$($credentialInfo.contactNumber)", [MessageType]::Default)
		$this.PublishCustomMessage("Comment:`t`t`t`t`t`t`t`t$($credentialInfo.comment)`n", [MessageType]::Default)

		if($credentialInfo.credLocation -eq "AppService"){
			$this.PublishCustomMessage([Constants]::SingleDashLine);
			$this.PublishCustomMessage("AppService name:`t`t`t`t`t`t$($credentialInfo.resourceGroup)", [MessageType]::Default)
			$this.PublishCustomMessage("Resource group:`t`t`t`t`t`t`t$($credentialInfo.resourceName)", [MessageType]::Default)
			$this.PublishCustomMessage("AppService config type:`t`t`t`t`t$($credentialInfo.appConfigType)", [MessageType]::Default)
			$this.PublishCustomMessage("AppService config name:`t`t`t`t`t$($credentialInfo.appConfigName)", [MessageType]::Default)
		}
		if($credentialInfo.credLocation -eq "KeyVault"){
			$this.PublishCustomMessage([Constants]::SingleDashLine);
			$this.PublishCustomMessage("Key vault name:`t`t`t`t`t`t`t$($credentialInfo.kvName)", [MessageType]::Default)
			$this.PublishCustomMessage("Credential type:`t`t`t`t`t`t$($credentialInfo.kvCredType)", [MessageType]::Default)
			$this.PublishCustomMessage("Credential name:`t`t`t`t`t`t$($credentialInfo.kvCredName)", [MessageType]::Default)
			$this.PublishCustomMessage("Expiry time:`t`t`t`t`t`t`t$($credentialInfo.expiryTime)", [MessageType]::Default)
			$this.PublishCustomMessage("Version:`t`t`t`t`t`t`t`t$($credentialInfo.Version)", [MessageType]::Default)
		}

		$this.PublishCustomMessage("`n")		
	}

    [void] GetAlert($CredentialName)
	{           
        $file = Join-Path $($this.AzSKTemp) -ChildPath $($this.SubscriptionContext.SubscriptionId) | Join-Path -ChildPath $CredentialName
		$file += ".json"
        $this.GetAzSKRotationMetadatContainer()

		$tempSubPath = Join-Path $($this.AzSKTemp) $($this.SubscriptionContext.SubscriptionId)

        if(![string]::isnullorwhitespace($this.SubscriptionContext.SubscriptionId)){
			if(-not (Test-Path $tempSubPath))
			{
				New-Item -ItemType Directory -Path $tempSubPath -ErrorAction Stop | Out-Null
			}	
		}
		else{
			if(-not (Test-Path "$($this.AzSKTemp)"))
			{
				New-Item -ItemType Directory -Path "$($this.AzSKTemp)" -ErrorAction Stop | Out-Null
			}
		}
        
		if($CredentialName){
			$blobName = $CredentialName.ToLower() + ".json"
			$blobContent = Get-AzStorageBlobContent -Blob $blobName -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -Destination $file -Force -ErrorAction Ignore
			if($blobContent){    
				$credentialInfo = Get-ChildItem -Path $file -Force | Get-Content | ConvertFrom-Json

				$this.PrintDetails($credentialInfo);
			}
			else{
				$this.PublishCustomMessage("Could not find an entry for credential [$CredentialName].",[MessageType]::Critical)
				$this.PublishCustomMessage("Please check the name or run Get-AzSKTrackedCredential to list all credentials currently being tracked for rotation/expiry.")
			}
    	}
		else{
			$blob = @();
			$blob = Get-AzStorageBlob -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -ErrorAction Ignore

			if($blob){
				$this.PublishCustomMessage("`n")
				$this.PublishCustomMessage("`nListing settings for all the credentials `n`n",[MessageType]::Update)
				$this.PublishCustomMessage("`n")
				$blob | where {
					$_ | Get-AzStorageBlobContent -Destination $file -Force | Out-Null
					$credentialInfo = Get-ChildItem -Path $file -Force | Get-Content | ConvertFrom-Json

					$this.PrintDetails($credentialInfo);
				}
			}
			else{
				$this.PublishCustomMessage("No credential entries found for rotation/expiry alert.", [MessageType]::Critical)
			}		
		}

		if(Test-Path $file)
		{
			Remove-Item -Path $file
		}
	}

	[void] NewAlert($CredentialLocation, $ResourceGroupName, $ResourceName, $AppConfigType, $AppConfigName, $KVName, $KVCredentialType, $KVCredentialName)
	{           
        $file = Join-Path $($this.AzSKTemp) -ChildPath $($this.SubscriptionContext.SubscriptionId) | Join-Path -ChildPath $($this.credName)
		$file += ".json"
        $this.GetAzSKRotationMetadatContainer()
        $blobName = ($this.credName).ToLower() + ".json"
		[bool] $found = $true;

		$tempSubPath = Join-Path $($this.AzSKTemp) $($this.SubscriptionContext.SubscriptionId)

        if(![string]::isnullorwhitespace($this.SubscriptionContext.SubscriptionId)){
			if(-not (Test-Path $tempSubPath))
			{
				New-Item -ItemType Directory -Path $tempSubPath -ErrorAction Stop | Out-Null
			}	
		}
		else{
			if(-not (Test-Path "$($this.AzSKTemp)"))
			{
				New-Item -ItemType Directory -Path "$($this.AzSKTemp)" -ErrorAction Stop | Out-Null
			}
		}

        $blobContent = Get-AzStorageBlobContent -Blob $blobName -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -Destination $file -Force -ErrorAction Ignore
        if($blobContent){
            $this.PublishCustomMessage("Entry for the credential [$($this.credName)] already exists. Run Update-AzSKTrackedCredential to update alert configurations for the existing credential.", [MessageType]::Error);
        }
        else{
            
            $startTime = [DateTime]::UtcNow
            $user = ([Helpers]::GetCurrentRMContext()).Account.Id
            $this.PublishCustomMessage("Onboarding the credential [$($this.credName)] for rotation/expiry notification", [MessageType]::Default)
            $credentialInfo = New-Object PSObject
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name credLocation -Value $this.credLocation
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name credName -Value $this.credName
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name rotationInt -Value $this.rotationInt
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name emailId -Value $this.alertEmail
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name contactNumber -Value $this.alertPhoneNumber
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name firstUpdatedOn -Value $startTime
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name lastUpdatedOn -Value $startTime
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name comment -Value $this.comment
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name firstUpdatedBy -Value $user
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name lastUpdatedBy -Value $user

            if($CredentialLocation -eq "AppService"){
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name resourceGroup -Value $ResourceGroupName
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name resourceName -Value $ResourceName
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name appConfigType -Value $AppConfigType
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name appConfigName -Value $AppConfigName

				$resource = Get-AzWebApp -ResourceGroupName $credentialInfo.resourceGroup -Name $credentialInfo.resourceName -ErrorAction Ignore
				if(-not $resource){
					$found = $false;
					$this.PublishCustomMessage("Could not find a resource for the given app service name and resource group. Please verify whether the given app service name/resource group is correct.",[MessageType]::Error)
				}
				else{
					if($AppConfigType -eq "Application Settings")
					{
						if(-not ($resource.SiteConfig.AppSettings.Name | where-object{$_ -eq $AppConfigName})){
							$found = $false;
							$this.PublishCustomMessage("Could not find the app setting [$AppConfigName] in the app service. Please verify whether the given app setting name is correct.",[MessageType]::Error)
						}
					}
					elseif($AppConfigType -eq "Connection Strings")
					{
						if(-not ($resource.SiteConfig.ConnectionStrings.Name | where-object{$_ -eq $AppConfigName})){
							$found = $false;
							$this.PublishCustomMessage("Could not find the connection string [$AppConfigName] in the app service. Please verify whether the given connection string name is correct.",[MessageType]::Error)
						}
					}		
							
				}
            }

            if($CredentialLocation -eq "KeyVault"){
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name kvName -Value $KVName
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name kvCredType -Value $KVCredentialType
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name kvCredName -Value $KVCredentialName
                
                if($KVCredentialType -eq "Key")
                {
                    $key = Get-AzKeyVaultKey -VaultName $KVName -Name $KVCredentialName -ErrorAction Ignore
					if($key){
						Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name expiryTime -Value $key.Expires
                    	Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name version -Value $key.Version
					}
                    else{
						$found = $false;
						$this.PublishCustomMessage("Could not find a key for the given key vault credential. Please verify whether the given key vault name/key is correct.",[MessageType]::Error)
					}
                }
                elseif($KVCredentialType -eq "Secret")
                {
                    $secret = Get-AzKeyVaultSecret -VaultName $KVName -Name $KVCredentialName -ErrorAction Ignore
					if($secret){
	                    Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name expiryTime -Value $secret.Expires
    	                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name version -Value $secret.Version
					}
					else{
						$found = $false;
						$this.PublishCustomMessage("Could not find a secret for the given key vault credential. Please verify whether the given key vault name/secret is correct.",[MessageType]::Error)
					}
                }
            }

			if($found){
				$credentialInfo | ConvertTo-Json -Depth 10 | Out-File $file -Force
				Set-AzStorageBlobContent -Blob $blobName -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -File $file -Force | Out-Null
				$this.PublishCustomMessage("Successfully onboarded the credential [$($this.credName)] for rotation/expiry notification", [MessageType]::Update)
				$this.PrintInfo($credentialInfo);
			}
			else{
				$this.PublishCustomMessage("Could not onboard the credential [$($this.credName)] for rotation/expiry notification", [MessageType]::Error)
			}
        }
		if(Test-Path $file)
		{
			Remove-Item -Path $file
		}
        $this.PublishCustomMessage("Run Get-AzSKTrackedCredential to list all the credentials onboarded for rotation/expiry notification.")
	}

	[void] RemoveAlert($CredentialName,$Force)
	{           
        $file = Join-Path $($this.AzSKTemp) -ChildPath $($this.SubscriptionContext.SubscriptionId) | Join-Path -ChildPath $CredentialName
		$file += ".json"
        $this.GetAzSKRotationMetadatContainer()
        $blobName = $CredentialName.ToLower() + ".json"

		$tempSubPath = Join-Path $($this.AzSKTemp) $($this.SubscriptionContext.SubscriptionId)

        if(![string]::isnullorwhitespace($this.SubscriptionContext.SubscriptionId)){
			if(-not (Test-Path $tempSubPath))
			{
				New-Item -ItemType Directory -Path $tempSubPath -ErrorAction Stop | Out-Null
			}	
		}
		else{
			if(-not (Test-Path "$($this.AzSKTemp)"))
			{
				New-Item -ItemType Directory -Path "$($this.AzSKTemp)" -ErrorAction Stop | Out-Null
			}
		}

        $blobContent = Get-AzStorageBlobContent -Blob $blobName -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -Destination $file -Force -ErrorAction Ignore
		if($blobContent){
			
			$title = "Confirm the removal of credential rotation/expiry notification"
			$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "This means Yes"
			$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "This means No"
			$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
			#below is hack for removing error due to strict mode - host variable is not assigned in the method 
			$host = $host
			# Ask for confirmation only if force switch is not present
			$result = 0

			if(!$Force)
			{
				#user confirmation before deleting container
				$storageConfirmMsg = "Are you sure you want to remove expiry alerting on [$CredentialName] credential?"
				$result = $host.ui.PromptForChoice($title, $storageConfirmMsg, $options, 1)
			}
			if($result -eq 0)
			{
				#user selected yes
				$this.PublishCustomMessage("Removing the rotation/expiry notification on the credential [$CredentialName]", [MessageType]::Default) 
				$blobContent | Remove-AzStorageBlob 
				$this.PublishCustomMessage("Successfully removed the rotation/expiry notification on the credential [$CredentialName]", [MessageType]::Update)
			}
			#user selected no in confirmation box
			else
			{
				$this.PublishCustomMessage("You have chosen not to remove rotation/expiry notification on the credential [$CredentialName]", [MessageType]::Default) 
			}        

		}
		else{
			$this.PublishCustomMessage("Entry for the credential [$CredentialName] not found.", [MessageType]::Critical)
		}
		if(Test-Path $file)
		{
			Remove-Item -Path $file
		}
	}
	
	[void] UpdateAlert($CredentialName,$RotationIntervalInDays,$AlertEmail,$AlertSMS,$Comment,$UpdateCredential)
	{           
        $file = Join-Path $($this.AzSKTemp) -ChildPath $($this.SubscriptionContext.SubscriptionId) | Join-Path -ChildPath $CredentialName
		$file += ".json"
        $this.GetAzSKRotationMetadatContainer()
        $blobName = $CredentialName.ToLower() + ".json"

		$tempSubPath = Join-Path $($this.AzSKTemp) $($this.SubscriptionContext.SubscriptionId)

        if(![string]::isnullorwhitespace($this.SubscriptionContext.SubscriptionId)){
			if(-not (Test-Path $tempSubPath))
			{
				New-Item -ItemType Directory -Path $tempSubPath -ErrorAction Stop | Out-Null
			}	
		}
		else{
			if(-not (Test-Path "$($this.AzSKTemp)"))
			{
				New-Item -ItemType Directory -Path "$($this.AzSKTemp)" -ErrorAction Stop | Out-Null
			}
		}

        $blobContent = Get-AzStorageBlobContent -Blob $blobName -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -Destination $file -Force -ErrorAction Ignore
		if($blobContent){
			$this.PublishCustomMessage("Updating settings for AzSK tracked credential [$CredentialName]", [MessageType]::Default) 
			$credentialInfo = Get-ChildItem -Path $file -Force | Get-Content | ConvertFrom-Json
			$user = ([Helpers]::GetCurrentRMContext()).Account.Id;

			if ($RotationIntervalInDays)
			{
				$credentialInfo.rotationInt = $RotationIntervalInDays;
			}

			if ($AlertEmail)
			{
				$credentialInfo.emailId = $AlertEmail;
			}

			if ($AlertSMS)
			{
				$credentialInfo.contactNumber = $AlertSMS;
			}

			if($UpdateCredential){
			
				if($credentialInfo.credLocation -eq "AppService"){
					
					$resource = Get-AzWebApp -ResourceGroupName $credentialInfo.resourceGroup -Name $credentialInfo.resourceName
					
					$hash = @{}

					if($credentialInfo.appConfigType -eq "Application Settings"){
						$this.PublishCustomMessage("Updating the application setting [$($credentialInfo.appConfigName)] in the app service [$($credentialInfo.resourceName)]", [MessageType]::Default)  
						$appConfig = $resource.SiteConfig.AppSettings 
						$appConfigValue = Read-Host "Enter the new secret for the application setting - [$($credentialInfo.appConfigName)]" -AsSecureString 
						$appConfigValue = [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($appConfigValue))

						foreach ($setting in $appConfig) {
							if($setting.Name -eq $credentialInfo.appConfigName){
								$hash[$setting.Name] = $appConfigValue
							}
							else{
								$hash[$setting.Name] = $setting.Value
							}
						}
					}
					elseif($credentialInfo.appConfigType -eq "Connection Strings"){
						$this.PublishCustomMessage("Updating the connection string [$($credentialInfo.appConfigName)] in the app service [$($credentialInfo.resourceName)]", [MessageType]::Default) 
						$appConfig = $resource.SiteConfig.ConnectionStrings
						$appConfigValue = Read-Host "Enter the new secret for the connection string - [$($credentialInfo.appConfigName)]" -AsSecureString
						$appConfigValue = [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($appConfigValue))

						foreach ($setting in $appConfig) {
							if($setting.Name -eq $credentialInfo.appConfigName){
								$hash[$setting.Name] = @{Type=$setting.Type.ToString(); Value=$appConfigValue}
							}
							else{
								$hash[$setting.Name] = @{Type=$setting.Type.ToString(); Value=$setting.ConnectionString}
							}
						}
					}

					if($credentialInfo.appConfigType -eq "Application Settings"){
						Set-AzWebApp -ResourceGroupName $credentialInfo.resourceGroup -Name $credentialInfo.resourceName -AppSettings $hash | Out-Null
						$this.PublishCustomMessage("Successfully updated the application setting [$($credentialInfo.appConfigName)] in the app service [$($credentialInfo.resourceName)]", [MessageType]::Update)
					}
					elseif($credentialInfo.appConfigType -eq "Connection Strings"){
						Set-AzWebApp -ResourceGroupName $credentialInfo.resourceGroup -Name $credentialInfo.resourceName -ConnectionStrings $hash | Out-Null
						$this.PublishCustomMessage("Successfully updated connection string [$($credentialInfo.appConfigName)] in the app service [$($credentialInfo.resourceName)]", [MessageType]::Update)
					}
					
				}			

				if($credentialInfo.credLocation -eq "KeyVault")
				{
					if($credentialInfo.kvCredType -eq "Key")
					{
						$currentKey = Get-AzKeyVaultKey -VaultName $credentialInfo.kvName -Name $credentialInfo.kvCredName -ErrorAction SilentlyContinue
						if(($currentKey | Measure-Object).Count -ne 0)
						{
							$currentTime = [DateTime]::UtcNow
							$expiryTime = $currentTime.AddDays($credentialInfo.rotationInt)

							$this.PublishCustomMessage("Updating the key [$($credentialInfo.kvCredName)] in the key vault [$($credentialInfo.kvName)]", [MessageType]::Default)
							$newKey = Add-AzKeyVaultKey -VaultName $credentialInfo.kvName -Name $credentialInfo.kvCredName -Expires $ExpiryTime -Destination Software
							
							$credentialInfo.expiryTime = $newKey.Expires
							$credentialInfo.version = $newKey.Version

							$this.PublishCustomMessage("Successfully updated the key [$($credentialInfo.kvCredName)] in the key vault [$($credentialInfo.kvName)]", [MessageType]::Update)
						}
					}
					elseif($credentialInfo.kvCredType -eq "Secret")
					{
						$currentSecret = Get-AzKeyVaultSecret -VaultName $credentialInfo.kvName -Name $credentialInfo.kvCredName -ErrorAction SilentlyContinue
						if(($currentSecret | Measure-Object).Count -ne 0)
						{
							$currentTime = [DateTime]::UtcNow
							$expiryTime = $currentTime.AddDays($credentialInfo.rotationInt)

							$this.PublishCustomMessage("Updating the secret [$($credentialInfo.kvCredName)] in the key vault [$($credentialInfo.kvName)]", [MessageType]::Default)
							$secret = Read-Host "Enter the new secret value for the key vault credential - [$($credentialInfo.kvCredName)]" -AsSecureString 
						
							$newSecret = Set-AzKeyVaultSecret -VaultName $credentialInfo.kvName -Name $credentialInfo.kvCredName -SecretValue $secret -Expires $ExpiryTime
							$credentialInfo.expiryTime = $newSecret.Expires
							$credentialInfo.version = $newSecret.Version

							$this.PublishCustomMessage("Successfully updated the secret [$($credentialInfo.kvCredName)] in the key vault [$($credentialInfo.kvName)]", [MessageType]::Update)
						}
					}
					$this.PublishCustomMessage("To avoid impacting availability, the previous version of this $($credentialInfo.kvCredType) has been kept in enabled state.", [MessageType]::Warning)
					$this.PublishCustomMessage("If you are using key/secret URLs with specific version identifier in them, please update to the new version before disabling it.")
				}

				$credentialInfo.lastUpdatedOn = [DateTime]::UtcNow
				$credentialInfo.lastUpdatedBy = $user
			}

			$credentialInfo.comment = $Comment
			$credentialInfo | ConvertTo-Json -Depth 10 | Out-File $file -Force
			Set-AzStorageBlobContent -Blob $blobName -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -File $file -Force | Out-Null
			$this.PublishCustomMessage("Successfully updated settings for AzSK tracked credential [$CredentialName]", [MessageType]::Update) 
			$this.PrintInfo($credentialInfo);
		}
		else{
			$this.PublishCustomMessage("Entry for the credential [$CredentialName] not found.", [MessageType]::Critical)
		}
		if(Test-Path $file)
		{
			Remove-Item -Path $file
		}
	}

}