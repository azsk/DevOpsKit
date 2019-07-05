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

    hidden [void] dummy()
	{
		Write-Host "1"
	}

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

			Write-Host "Alert details for the credential [$CredentialName] `n" 

			Write-Host "Name:									$($credentialInfo.credName)"
			Write-Host "Location: 								$($credentialInfo.credLocation)"
			Write-Host "Rotation interval in days: 				$($credentialInfo.rotationInt)"
			Write-Host "Alert email: 							$($credentialInfo.emailId)"
			Write-Host "Alert phone: 							$($credentialInfo.contactNumber)"
			Write-Host "Entry created on: 						$($credentialInfo.firstUpdatedOn)"
			Write-Host "Entry created by: 						$($credentialInfo.firstUpdatedBy)"
			Write-Host "Last updated on: 						$($credentialInfo.lastUpdatedOn)"
			Write-Host "Last updated by: 						$($credentialInfo.lastUpdatedBy)"

			if($credentialInfo.credLocation -eq "AppService"){
				Write-Host "Resource group: 						$($credentialInfo.resourceGroup)"
				Write-Host "Resource name: 							$($credentialInfo.resourceName)"
				Write-Host "Application configuration type: 		$($credentialInfo.appConfigType)"
				Write-Host "Application configuration name: 		$($credentialInfo.appConfigName)"
			}
			if($credentialInfo.credLocation -eq "KeyVault"){
				Write-Host "Key vault name: 						$($credentialInfo.kvName)"
				Write-Host "Key vault credential type: 				$($credentialInfo.kvCredType)"
				Write-Host "Key vault credential name: 				$($credentialInfo.kvCredName)"
				Write-Host "Expiry time: 							$($credentialInfo.expiryTime)"
				Write-Host "Version: 								$($credentialInfo.Version)"
			}

			Write-Host "Comment: 								$($credentialInfo.comment)`n"
			}
			else{
				Write-Host "Entry for the credential [$CredentialName] was not found. Run Get-AzSKCredentialAlert to list all the credentials onboarded for rotation/expiry notification. " -ForegroundColor Red
			}
    	}
		else{
			$blob = @();
			$blob = Get-AzStorageBlob -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -ErrorAction Ignore

			if($blob){
				Write-Host "`nListing alert details for all the credentials `n`n"
				$blob | where {
					$_ | Get-AzStorageBlobContent -Destination $file -Force | Out-Null
					$credentialInfo = Get-ChildItem -Path $file -Force | Get-Content | ConvertFrom-Json

					Write-Host "Alert details for the credential [$($credentialInfo.credName)] `n" 

					Write-Host "Name:									$($credentialInfo.credName)"
					Write-Host "Location: 								$($credentialInfo.credLocation)"
					Write-Host "Rotation interval in days: 				$($credentialInfo.rotationInt)"
					Write-Host "Alert email: 							$($credentialInfo.emailId)"
					Write-Host "Alert phone: 							$($credentialInfo.contactNumber)"
					Write-Host "Entry created on: 						$($credentialInfo.firstUpdatedOn)"
					Write-Host "Entry created by: 						$($credentialInfo.firstUpdatedBy)"
					Write-Host "Last updated on: 						$($credentialInfo.lastUpdatedOn)"
					Write-Host "Last updated by: 						$($credentialInfo.lastUpdatedBy)"

					if($credentialInfo.credLocation -eq "AppService"){
						Write-Host "Resource group: 						$($credentialInfo.resourceGroup)"
						Write-Host "Resource name: 							$($credentialInfo.resourceName)"
						Write-Host "Application configuration type: 		$($credentialInfo.appConfigType)"
						Write-Host "Application configuration name: 		$($credentialInfo.appConfigName)"
					}
					if($credentialInfo.credLocation -eq "KeyVault"){
						Write-Host "Key vault name: 						$($credentialInfo.kvName)"
						Write-Host "Key vault credential type: 				$($credentialInfo.kvCredType)"
						Write-Host "Key vault credential name: 				$($credentialInfo.kvCredName)"
						Write-Host "Expiry time: 							$($credentialInfo.expiryTime)"
						Write-Host "Version: 								$($credentialInfo.Version)"
					}

					Write-Host "Comment: 								$($credentialInfo.comment)`n"
				}
			}
			else{
				Write-Host "No credential entries found for rotation/expiry alert." -ForegroundColor Red
			}		
		}

		if(Test-Path $file)
		{
			Remove-Item -Path $file
		}
	}

	[void] SetAlert($CredentialLocation, $ResourceGroupName, $ResourceName, $AppConfigType, $AppConfigName, $KVName, $KVCredentialType, $KVCredentialName)
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
            $this.PublishCustomMessage("Onboarding the credential [$($this.credName)] for rotation/expiry notification")
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
				Write-Host "Removing the rotation/expiry notification on the credential [$CredentialName]" 
				$blobContent | Remove-AzStorageBlob 
				Write-Host "Successfully removed the rotation/expiry notification on the credential [$CredentialName]" -ForegroundColor Green
			}
			#user selected no in confirmation box
			else
			{
				Write-Host "You have chosen not to remove rotation/expiry notification on the credential [$CredentialName]" 
			}        

		}
		else{
			Write-Host "Entry for the credential [$CredentialName] not found." -ForegroundColor Red
		}
		if(Test-Path $file)
		{
			Remove-Item -Path $file
		}
        $this.PublishCustomMessage("Run Get-AzSKCredentialAlert to list all the credentials onboarded for rotation/expiry notification.")
	}
	
	[void] UpdateAlert($CredentialName,$RotationIntervalInDays,$AlertEmail,$AlertSMS,$Comment)
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
			Write-Host "Updating alert details for the credential [$CredentialName]" 
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
			Write-Host "Successfully updated alert details for the credential [$CredentialName]" -ForegroundColor Green
		}
		else{
			Write-Host "Entry for the credential [$CredentialName] not found." -ForegroundColor Red
		}
		if(Test-Path $file)
		{
			Remove-Item -Path $file
		}
        $this.PublishCustomMessage("Run Get-AzSKCredentialAlert to list all the credentials onboarded for rotation/expiry notification.")
	}
}