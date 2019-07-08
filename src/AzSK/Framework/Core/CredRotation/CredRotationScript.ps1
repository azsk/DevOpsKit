Set-StrictMode -Version Latest

class CredRotation : CommandBase{
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

    CredRotation([string] $subscriptionId, [InvocationInfo] $invocationContext): 
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
			$blobName = $CredentialName + ".json"
			$blobContent = Get-AzStorageBlobContent -Blob $blobName -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -Destination $file -Force -ErrorAction Ignore
			if($blobContent){    
			$credentialInfo = Get-ChildItem -Path $file -Force | Get-Content | ConvertFrom-Json

			$this.PublishCustomMessage("`n")
			$this.PublishCustomMessage("Alert details for the credential [$CredentialName] `n`n", [MessageType]::Info) 
			$this.PublishCustomMessage("`n")

			$this.PublishCustomMessage("Name:`t`t`t`t`t`t`t`t`t$($credentialInfo.credName)", [MessageType]::Default)
			$this.PublishCustomMessage("Location:`t`t`t`t`t`t`t`t$($credentialInfo.credLocation)", [MessageType]::Default)
			$this.PublishCustomMessage("Rotation interval in days:`t`t`t`t$($credentialInfo.rotationInt)", [MessageType]::Default)
			$this.PublishCustomMessage("Alert email:`t`t`t`t`t`t`t$($credentialInfo.emailId)", [MessageType]::Default)
			$this.PublishCustomMessage("Alert phone:`t`t`t`t`t`t`t$($credentialInfo.contactNumber)", [MessageType]::Default)
			$this.PublishCustomMessage("Entry created on:`t`t`t`t`t`t$($credentialInfo.firstUpdatedOn)", [MessageType]::Default)
			$this.PublishCustomMessage("Entry created by:`t`t`t`t`t`t$($credentialInfo.firstUpdatedBy)", [MessageType]::Default)
			$this.PublishCustomMessage("Last updated on:`t`t`t`t`t`t$($credentialInfo.lastUpdatedOn)", [MessageType]::Default)
			$this.PublishCustomMessage("Last updated by:`t`t`t`t`t`t$($credentialInfo.lastUpdatedBy)", [MessageType]::Default)

			if($credentialInfo.credLocation -eq "AppService"){
				$this.PublishCustomMessage("Resource group:`t`t`t`t`t`t`t$($credentialInfo.resourceGroup)", [MessageType]::Default)
				$this.PublishCustomMessage("Resource name:`t`t`t`t`t`t`t$($credentialInfo.resourceName)", [MessageType]::Default)
				$this.PublishCustomMessage("Application configuration type:`t`t`t$($credentialInfo.appConfigType)", [MessageType]::Default)
				$this.PublishCustomMessage("Application configuration name:`t`t`t$($credentialInfo.appConfigName)", [MessageType]::Default)
			}
			if($credentialInfo.credLocation -eq "KeyVault"){
				$this.PublishCustomMessage("Key vault name:`t`t`t`t`t`t`t$($credentialInfo.kvName)", [MessageType]::Default)
				$this.PublishCustomMessage("Key vault credential type:`t`t`t`t$($credentialInfo.kvCredType)", [MessageType]::Default)
				$this.PublishCustomMessage("Key vault credential name:`t`t`t`t$($credentialInfo.kvCredName)", [MessageType]::Default)
				$this.PublishCustomMessage("Expiry time:`t`t`t`t`t`t`t$($credentialInfo.expiryTime)", [MessageType]::Default)
				$this.PublishCustomMessage("Version:`t`t`t`t`t`t`t`t$($credentialInfo.Version)", [MessageType]::Default)
			}

			$this.PublishCustomMessage("Comment:`t`t`t`t`t`t`t`t$($credentialInfo.comment)`n", [MessageType]::Default)
			$this.PublishCustomMessage("`n")
			}
			else{
				$this.PublishCustomMessage("Entry for the credential [$CredentialName] was not found. Run Get-AzSKCredentialAlert to list all the credentials onboarded for rotation/expiry notification. ",[MessageType]::Critical)
			}
    	}
		else{
			$blob = @();
			$blob = Get-AzStorageBlob -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -ErrorAction Ignore

			if($blob){
				$this.PublishCustomMessage("`n")
				$this.PublishCustomMessage("`nListing alert details for all the credentials `n`n",[MessageType]::Update)
				$this.PublishCustomMessage("`n")
				$blob | where {
					$_ | Get-AzStorageBlobContent -Destination $file -Force | Out-Null
					$credentialInfo = Get-ChildItem -Path $file -Force | Get-Content | ConvertFrom-Json

					$this.PublishCustomMessage("Alert details for the credential [$($credentialInfo.credName)] `n`n",[MessageType]::Info) 
					$this.PublishCustomMessage("`n")
					$this.PublishCustomMessage("Name:`t`t`t`t`t`t`t`t`t$($credentialInfo.credName)", [MessageType]::Default)
					$this.PublishCustomMessage("Location:`t`t`t`t`t`t`t`t$($credentialInfo.credLocation)", [MessageType]::Default)
					$this.PublishCustomMessage("Rotation interval in days:`t`t`t`t$($credentialInfo.rotationInt)", [MessageType]::Default)
					$this.PublishCustomMessage("Alert email:`t`t`t`t`t`t`t$($credentialInfo.emailId)", [MessageType]::Default)
					$this.PublishCustomMessage("Alert phone:`t`t`t`t`t`t`t$($credentialInfo.contactNumber)", [MessageType]::Default)
					$this.PublishCustomMessage("Entry created on:`t`t`t`t`t`t$($credentialInfo.firstUpdatedOn)", [MessageType]::Default)
					$this.PublishCustomMessage("Entry created by:`t`t`t`t`t`t$($credentialInfo.firstUpdatedBy)", [MessageType]::Default)
					$this.PublishCustomMessage("Last updated on:`t`t`t`t`t`t$($credentialInfo.lastUpdatedOn)", [MessageType]::Default)
					$this.PublishCustomMessage("Last updated by:`t`t`t`t`t`t$($credentialInfo.lastUpdatedBy)", [MessageType]::Default)

					if($credentialInfo.credLocation -eq "AppService"){
						$this.PublishCustomMessage("Resource group:`t`t`t`t`t`t`t$($credentialInfo.resourceGroup)", [MessageType]::Default)
						$this.PublishCustomMessage("Resource name:`t`t`t`t`t`t`t$($credentialInfo.resourceName)", [MessageType]::Default)
						$this.PublishCustomMessage("Application configuration type:`t`t`t$($credentialInfo.appConfigType)", [MessageType]::Default)
						$this.PublishCustomMessage("Application configuration name:`t`t`t$($credentialInfo.appConfigName)", [MessageType]::Default)
					}
					if($credentialInfo.credLocation -eq "KeyVault"){
						$this.PublishCustomMessage("Key vault name:`t`t`t`t`t`t`t$($credentialInfo.kvName)", [MessageType]::Default)
						$this.PublishCustomMessage("Key vault credential type:`t`t`t`t$($credentialInfo.kvCredType)", [MessageType]::Default)
						$this.PublishCustomMessage("Key vault credential name:`t`t`t`t$($credentialInfo.kvCredName)", [MessageType]::Default)
						$this.PublishCustomMessage("Expiry time:`t`t`t`t`t`t`t$($credentialInfo.expiryTime)", [MessageType]::Default)
						$this.PublishCustomMessage("Version:`t`t`t`t`t`t`t`t$($credentialInfo.Version)", [MessageType]::Default)
					}

					$this.PublishCustomMessage("Comment:`t`t`t`t`t`t`t`t$($credentialInfo.comment)`n", [MessageType]::Default)
					$this.PublishCustomMessage("`n")
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
        $blobName = $this.credName + ".json"

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
            $this.PublishCustomMessage("Entry for the credential [$($this.credName)] already exists. Run Update-AzSKCredentialALert to update alert configurations for the existing credential.", [MessageType]::Error);
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
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name moderateTH -Value 30
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name highTH -Value 7

            if($CredentialLocation -eq "AppService"){
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name resourceGroup -Value $ResourceGroupName
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name resourceName -Value $ResourceName
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name appConfigType -Value $AppConfigType
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name appConfigName -Value $AppConfigName
            }

            if($CredentialLocation -eq "KeyVault"){
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name kvName -Value $KVName
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name kvCredType -Value $KVCredentialType
                Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name kvCredName -Value $KVCredentialName
                
                if($KVCredentialType -eq "Key")
                {
                    $key = Get-AzKeyVaultKey -VaultName $KVName -Name $KVCredentialName
                    Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name expiryTime -Value $key.Expires
                    Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name version -Value $key.Version
                }
                elseif($KVCredentialType -eq "Secret")
                {
                    $secret = Get-AzKeyVaultSecret -VaultName $KVName -Name $KVCredentialName
                    Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name expiryTime -Value $secret.Expires
                    Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name version -Value $secret.Version
                }
            }

            $credentialInfo | ConvertTo-Json -Depth 10 | Out-File $file -Force
            Set-AzStorageBlobContent -Blob $blobName -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -File $file -Force | Out-Null
            $this.PublishCustomMessage("Successfully onboarded the credential [$($this.credName)] for rotation/expiry notification", [MessageType]::Update)
        }
		if(Test-Path $file)
		{
			Remove-Item -Path $file
		}
        $this.PublishCustomMessage("Run Get-AzSKCredentialAlert to list all the credentials onboarded for rotation/expiry notification.")
	}

	[void] RemoveAlert($CredentialName,$Force)
	{           
        $file = Join-Path $($this.AzSKTemp) -ChildPath $($this.SubscriptionContext.SubscriptionId) | Join-Path -ChildPath $CredentialName
		$file += ".json"
        $this.GetAzSKRotationMetadatContainer()
        $blobName = $CredentialName + ".json"

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
	
	[void] SetAlert($CredentialName,$RotationIntervalInDays,$AlertEmail,$AlertSMS,$Comment)
	{           
        $file = Join-Path $($this.AzSKTemp) -ChildPath $($this.SubscriptionContext.SubscriptionId) | Join-Path -ChildPath $CredentialName
		$file += ".json"
        $this.GetAzSKRotationMetadatContainer()
        $blobName = $CredentialName + ".json"

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
			$this.PublishCustomMessage("Updating alert details for the credential [$CredentialName]", [MessageType]::Default) 
			$credentialInfo = Get-ChildItem -Path $file -Force | Get-Content | ConvertFrom-Json

			if ($RotationIntervalInDays)
			{
				#Write-Host "Updating rotation interval for the credential [$CredentialName]" -ForegroundColor Yellow
				$credentialInfo.rotationInt = $RotationIntervalInDays;
				#Write-Host "Successfully updated rotation interval for the credential [$CredentialName]" -ForegroundColor Green
			}

			if ($AlertEmail)
			{
				#Write-Host "Updating alert email id for the credential [$CredentialName]" -ForegroundColor Yellow
				$credentialInfo.emailId = $AlertEmail;
				#Write-Host "Successfully updated alert email id for the credential [$CredentialName]" -ForegroundColor Green
			}

			if ($AlertSMS)
			{
				#Write-Host "Updating alert contact number for the credential [$CredentialName]" -ForegroundColor Yellow
				$credentialInfo.contactNumber = $AlertSMS;
				#Write-Host "Successfully updated alert contact number for the credential [$CredentialName]" -ForegroundColor Green
			}

			if ($Comment)
			{
				#Write-Host "Updating comment for the credential [$CredentialName]" -ForegroundColor Yellow
				$credentialInfo.comment = $Comment;
				#Write-Host "Successfully updated comment for the credential [$CredentialName]" -ForegroundColor Green
			}

			$credentialInfo | ConvertTo-Json -Depth 10 | Out-File $file -Force
			Set-AzStorageBlobContent -Blob $blobName -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -File $file -Force | Out-Null
			$this.PublishCustomMessage("Successfully updated alert details for the credential [$CredentialName]", [MessageType]::Update) 
		}
		else{
			$this.PublishCustomMessage("Entry for the credential [$CredentialName] not found.", [MessageType]::Critical)
		}
		if(Test-Path $file)
		{
			Remove-Item -Path $file
		}
	}

	[void] UpdateAlert($CredentialName,$Comment)
	{           
        $file = Join-Path $($this.AzSKTemp) -ChildPath $($this.SubscriptionContext.SubscriptionId) | Join-Path -ChildPath $CredentialName
		$file += ".json"
        $this.GetAzSKRotationMetadatContainer()
        $blobName = $CredentialName + ".json"
		$appConfig =@{};
		$appConfigValue = $null;

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
            $credentialInfo = Get-ChildItem -Path $file -Force | Get-Content | ConvertFrom-Json;
			$user = ([Helpers]::GetCurrentRMContext()).Account.Id;
			$this.PublishCustomMessage("Updating the rotation details for the credential [$CredentialName]", [MessageType]::Default)  
			
			if($credentialInfo.credLocation -eq "AppService"){
				
				$this.PublishCustomMessage("Fetching the app service [$($credentialInfo.resourceName)] details", [MessageType]::Default)
				$resource = Get-AzWebApp -ResourceGroupName $credentialInfo.resourceGroup -Name $credentialInfo.resourceName
				
				$hash = @{}

				if($credentialInfo.appConfigType -eq "Application Settings"){
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

				$this.PublishCustomMessage("Updating the app service configuration" , [MessageType]::Default)
				if($credentialInfo.appConfigType -eq "Application Settings"){
					Set-AzWebApp -ResourceGroupName $credentialInfo.resourceGroup -Name $credentialInfo.resourceName -AppSettings $hash | Out-Null
				}
				elseif($credentialInfo.appConfigType -eq "Connection Strings"){
					Set-AzWebApp -ResourceGroupName $credentialInfo.resourceGroup -Name $credentialInfo.resourceName -ConnectionStrings $hash | Out-Null
				}
				$this.PublishCustomMessage("Successfully updated the app config", [MessageType]::Update)
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
					
						$newKey = Add-AzKeyVaultKey -VaultName $credentialInfo.kvName -Name $credentialInfo.kvCredName -Expires $ExpiryTime -Destination Software
						
						$credentialInfo.expiryTime = $newKey.Expires
						$credentialInfo.version = $newKey.Version
					}
				}
				elseif($credentialInfo.kvCredType -eq "Secret")
				{
					$currentSecret = Get-AzKeyVaultSecret -VaultName $credentialInfo.kvName -Name $credentialInfo.kvCredName -ErrorAction SilentlyContinue
					if(($currentSecret | Measure-Object).Count -ne 0)
					{
						$currentTime = [DateTime]::UtcNow
						$expiryTime = $currentTime.AddDays($credentialInfo.rotationInt)

						$secret = Read-Host "Enter the new secret value for the key vault credential - [$($credentialInfo.kvCredName)]" -AsSecureString 
					
						$newSecret = Set-AzKeyVaultSecret -VaultName $credentialInfo.kvName -Name $credentialInfo.kvCredName -SecretValue $secret -Expires $ExpiryTime
						$credentialInfo.expiryTime = $newSecret.Expires
						$credentialInfo.version = $newSecret.Version
					}
				}
				$this.PublishCustomMessage("Older version of this credential has not been disabled to maintain availability of exisiting applications. Please update the version at the required locations & then disable the older version.", [MessageType]::Warning)
			}

			$credentialInfo.lastUpdatedOn = [DateTime]::UtcNow
			$credentialInfo.lastUpdatedBy = $user
			$credentialInfo.comment = $Comment
			$credentialInfo | ConvertTo-Json -Depth 10 | Out-File $file -Force
			Set-AzStorageBlobContent -Blob $blobName -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -File $file -Force | Out-Null

			$this.PublishCustomMessage("Successfully updated the rotation details for the credential [$CredentialName]", [MessageType]::Update)
        }
        else{
            $this.PublishCustomMessage("Credential [$CredentialName] not found.", [MessageType]::Critical)
        }
		if(Test-Path $file)
		{
			Remove-Item -Path $file
		}
	}	
}