Set-StrictMode -Version Latest

class CredHygiene : CommandBase{
    [string] $credName;
    [string] $credLocation;
	[int] $rotationInt;
	[int] $nextExpiry;
    [string] $comment;
    hidden [string] $AzSKTemp = (Join-Path $([Constants]::AzSKAppFolderPath) $([Constants]::RotationMetadataSubPath)); 
    hidden [PSObject] $AzSKResourceGroup = $null;
	hidden [PSObject] $AzSKStorageAccount = $null;
	hidden [PSObject] $RotationMetadataContainer = $null;
	hidden [string] $RotationMetadataContainerName = [Constants]::RotationMetadataContainerName

    CredHygiene([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext)
		{
			$this.DoNotOpenOutputFolder = $true;
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

	[void] PrintDetails($credentialInfo,$messageType){
		$this.PublishCustomMessage("`n")
		$this.PublishCustomMessage("Settings for the AzSK tracked credential [$($credentialInfo.credName)] `n`n", [MessageType]::Info) 
		$this.PublishCustomMessage("`n")

		$table = $credentialInfo | Format-List @{Label = "Name"; Expression = { $_.credName }} , @{Label = "Location"; Expression = { $_.credLocation }}, @{Label = "Rotation interval (days)"; Expression = { $_.rotationInt }}, @{Label = "Credential Group"; Expression = { $_.credGroup }}, @{Label = "Created on"; Expression = { $_.firstUpdatedOn }}, @{Label = "Created by"; Expression = { $_.firstUpdatedBy }}, @{Label = "Last update"; Expression = { $_.lastUpdatedOn }}, @{Label = "Updated by"; Expression = { $_.lastUpdatedBy }}, @{Label = "Comment"; Expression = { $_.comment }} | Out-String
		$this.PublishCustomMessage($table, $messageType)

		if($credentialInfo.credLocation -eq "AppService"){
			$this.PublishCustomMessage([Constants]::SingleDashLine);
			$this.PublishCustomMessage("Additional Details:");
			$table = $credentialInfo | Format-List @{Label = "AppService Name"; Expression = { $_.resourceName }} , @{Label = "AppService config type"; Expression = { $_.appConfigType }}, @{Label = "AppService config name"; Expression = { $_.appConfigName }} | Out-String
			$this.PublishCustomMessage($table, $messageType)
		}
		if($credentialInfo.credLocation -eq "KeyVault"){
			$this.PublishCustomMessage([Constants]::SingleDashLine);
			$this.PublishCustomMessage("Additional Details:");
			$table = $credentialInfo | Format-List @{Label = "Key vault Name"; Expression = { $_.kvName }} , @{Label = "Credential type"; Expression = { $_.kvCredType }}, @{Label = "Credential name"; Expression = { $_.kvCredName }}, @{Label = "Expiry time"; Expression = { $_.expiryTime }}, @{Label = "Version"; Expression = { $_.version }} | Out-String
			$this.PublishCustomMessage($table, $messageType)
		}

		$this.PublishCustomMessage("`n")		
	}

	[void] PrintInfo ($credentialInfo){
		$this.PublishCustomMessage("`n")
		$this.PublishCustomMessage("Settings for the AzSK tracked credential [$($credentialInfo.credName)] `n`n", [MessageType]::Info) 
		$this.PublishCustomMessage("`n")
		$table = $credentialInfo | Format-List @{Label = "Name"; Expression = { $_.credName }} , @{Label = "Location"; Expression = { $_.credLocation }}, @{Label = "Rotation interval (days)"; Expression = { $_.rotationInt }}, @{Label = "Credential Group"; Expression = { $_.credGroup }}, @{Label = "Comment"; Expression = { $_.comment }} | Out-String
		$this.PublishCustomMessage($table, [MessageType]::Default)

		if($credentialInfo.credLocation -eq "AppService"){
			$this.PublishCustomMessage([Constants]::SingleDashLine);
			$this.PublishCustomMessage("Additional Details:");
			$table = $credentialInfo | Format-List @{Label = "AppService Name"; Expression = { $_.resourceName }} , @{Label = "AppService config type"; Expression = { $_.appConfigType }}, @{Label = "AppService config name"; Expression = { $_.appConfigName }} | Out-String
			$this.PublishCustomMessage($table, [MessageType]::Default)
		}
		if($credentialInfo.credLocation -eq "KeyVault"){
			$this.PublishCustomMessage([Constants]::SingleDashLine);
			$this.PublishCustomMessage("Additional Details:");
			$table = $credentialInfo | Format-List @{Label = "Key vault Name"; Expression = { $_.kvName }} , @{Label = "Credential type"; Expression = { $_.kvCredType }}, @{Label = "Credential name"; Expression = { $_.kvCredName }}, @{Label = "Expiry time"; Expression = { $_.expiryTime }}, @{Label = "Version"; Expression = { $_.version }} | Out-String
			$this.PublishCustomMessage($table, [MessageType]::Default)
		}

		$this.PublishCustomMessage("`n")		
	}

    [void] GetAlert($CredentialName,$DetailedView)
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

        $controlSettings = $this.LoadServerConfigFile("ControlSettings.json");

		if($CredentialName){
			$blobName = $CredentialName.ToLower() + ".json"
			$blobContent = Get-AzStorageBlobContent -Blob $blobName -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -Destination $file -Force -ErrorAction Ignore
			if($blobContent){    
				$credentialInfo = Get-ChildItem -Path $file -Force | Get-Content | ConvertFrom-Json

				$messageType = [MessageType]::Default
				
				$currentTime = [DateTime]::UtcNow;
				$lastRotatedTime = $credentialInfo.lastUpdatedOn;
				$expiryTime = $lastRotatedTime.AddDays($credentialInfo.rotationInt);
				
				if($expiryTime -le $currentTime.AddDays($controlSettings.SubscriptionCore.credHighTH)){ #Checking for expired/about to expire credentials
					$messageType = [MessageType]::Critical
				}
				elseif(($expiryTime -gt $currentTime.AddDays($controlSettings.SubscriptionCore.credHighTH)) -and ($expiryTime -le $currentTime.AddDays($controlSettings.SubscriptionCore.credModerateTH))){ #Checking for credentials nearing expiry.
					$messageType = [MessageType]::Warning
				}
				$this.PrintDetails($credentialInfo,$messageType);
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
				$this.PublishCustomMessage("`nListing settings for all the credentials `n",[MessageType]::Update)
				
				# array to store cred info in ascending order of expiry time.

				$sortedBlob = @();
				
				$blob | where {
					$_ | Get-AzStorageBlobContent -Destination $file -Force | Out-Null
					$credentialInfo = Get-ChildItem -Path $file -Force | Get-Content | ConvertFrom-Json
					$sortedBlob += $credentialInfo;
				}

				$sortedBlob = $sortedBlob | Sort-Object -Property @{Expression = {($_.lastUpdatedOn).AddDays($_.rotationInt)}; Descending = $False} 
				
				$currentTime = [DateTime]::UtcNow;

				if($DetailedView){
					$sortedBlob | where{
						$lastRotatedTime = $_.lastUpdatedOn;
						$expiryTime = $lastRotatedTime.AddDays($_.rotationInt);
						$messageType = [MessageType]::Default
						if($expiryTime -le $currentTime.AddDays($controlSettings.SubscriptionCore.credHighTH)){ #Checking for expired/about to expire credentials
							$messageType = [MessageType]::Critical
						}
						elseif(($expiryTime -gt $currentTime.AddDays($controlSettings.SubscriptionCore.credHighTH)) -and ($expiryTime -le $currentTime.AddDays($controlSettings.SubscriptionCore.credModerateTH))){ #Checking for credentials nearing expiry.
							$messageType = [MessageType]::Warning
						}

						$this.PrintDetails($_,$messageType);
					}
				}
				else{
					$table = $sortedBlob | Format-Table -AutoSize -Wrap @{Label = "Name"; Expression = { $_.credName }} , @{Label = "Location"; Expression = { $_.credLocation }}, @{Label = "Rotation interval (days)"; Expression = { $_.rotationInt }; align='left'}, @{Label = "Credential Group"; Expression = { $_.credGroup }}, @{Label = "Created on"; Expression = { $_.firstUpdatedOn }}, @{Label = "Created by"; Expression = { $_.firstUpdatedBy }}, @{Label = "Last update"; Expression = { $_.lastUpdatedOn }}, @{Label = "Updated by"; Expression = { $_.lastUpdatedBy }}, @{Label = "Comment"; Expression = { $_.comment }} | Out-String
					$this.PublishCustomMessage($table, [MessageType]::Default)
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

	[void] NewAlert($CredentialLocation,$CredentialGroup)
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
            $this.PublishCustomMessage("Entry for the credential [$($this.credName)] already exists.", [MessageType]::Error);
			$this.PublishCustomMessage("Run Update-AzSKTrackedCredential to update alert configurations for the existing credential.", [MessageType]::Default)
        }
        else{
            
            $startTime = [DateTime]::UtcNow
            $user = ([ContextHelper]::GetCurrentRMContext()).Account.Id
            $this.PublishCustomMessage("Onboarding the credential [$($this.credName)] for rotation/expiry notification", [MessageType]::Default)
            $credentialInfo = New-Object PSObject
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name credLocation -Value $this.credLocation
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name credName -Value $this.credName
			Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name rotationInt -Value $this.rotationInt
			Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name nextExpiry -Value $this.nextExpiry
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name firstUpdatedOn -Value $startTime
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name lastUpdatedOn -Value $startTime
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name comment -Value $this.comment
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name firstUpdatedBy -Value $user
            Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name lastUpdatedBy -Value $user

			if($credentialInfo.rotationInt -gt $credentialInfo.nextExpiry){
				$credentialInfo.lastUpdatedOn = ($credentialInfo.lastUpdatedOn).AddDays($credentialInfo.nextExpiry - $credentialInfo.rotationInt) 
			}

            if($CredentialLocation -eq "AppService"){

				$appsvc = Get-AzWebApp -ErrorAction Ignore

				if(($appsvc|Measure-Object).Count -gt 0){

					Write-Host "`nPlease select app service name from below:" -ForegroundColor Cyan

					$i=0;
					$appsvc | where{Write-Host "[$i] $($_.Name)" -ForegroundColor Cyan; $i++}
					
					$choice = Read-Host "App service name choice"
					while($choice -notin 0..($i-1)){
						Write-Host "`nIncorrect value supplied." -ForegroundColor Red
						Write-Host "Please select app service name from below:" -ForegroundColor Cyan

						$i=0;
						$appsvc | where{Write-Host "[$i] $($_.Name)" -ForegroundColor Cyan; $i++}
						$choice = Read-Host "App service name choice"
					}

					$ResourceName = $appsvc[$choice].Name
					$rsc = Get-AzWebApp -Name $ResourceName
					
					$appConfig = $null
					$AppConfigType = $null
					Write-Host "`nPlease select app config type from below: `n[1]: Application Settings`n[2]: Connection Strings" -ForegroundColor Cyan

					$input = Read-Host "App config type"
					
					while(($input -ne 1) -and ($input -ne 2)){
						Write-Host "`nIncorrect value supplied." -ForegroundColor Red
						Write-Host "Please select app config type from below: `n[1]: Application Settings`n[2]: Connection Strings" -ForegroundColor Cyan
						$input = Read-Host "App config type"
					}
					
					if($input -eq 1)
					{
						$AppConfigType = "Application Settings"
						$appConfig = $rsc.SiteConfig.AppSettings
					}
					elseif($input -eq 2)
					{
						$AppConfigType = "Connection Strings"
						$appConfig = $rsc.SiteConfig.ConnectionStrings
					}
					
					if(($appConfig|Measure-Object).Count -gt 0){
						Write-Host "`nPlease select app config name from below:" -ForegroundColor Cyan
						$i=0;
						$appConfig | where{Write-Host "[$i] $($_.Name)" -ForegroundColor Cyan; $i++}
						$choice = Read-Host "App config name"
						while($choice -notin 0..($i-1)){
							Write-Host "`nIncorrect value supplied." -ForegroundColor Red
							Write-Host "Please select app config name from below:" -ForegroundColor Cyan
							$i=0;
							$appConfig | where{Write-Host "[$i] $($_.Name)" -ForegroundColor Cyan; $i++}
							$choice = Read-Host "App config name"
						}
						$AppConfigName = $appConfig[$choice].Name       

						Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name resourceName -Value $ResourceName
						Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name appConfigType -Value $AppConfigType
						Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name appConfigName -Value $AppConfigName
					}	
					else{
						$found = $false
						$this.PublishCustomMessage("There are no $AppConfigType in the app service [$ResourceName].", [MessageType]::Error)
					}
				}
				else{
					$found = $false
					$this.PublishCustomMessage("There are no app services in your subscription.", [MessageType]::Error)
				}

            }

            if($CredentialLocation -eq "KeyVault"){

				$keyVault = Get-AzKeyVault -ErrorAction Ignore

				if(($keyVault|Measure-Object).Count -gt 0){
					Write-Host "`nPlease select key vault name from below:" -ForegroundColor Cyan

					$i=0;
					$keyVault | where{Write-Host "[$i] $($_.VaultName)" -ForegroundColor Cyan; $i++}
					
					$choice = Read-Host "Key vault name choice"
					while($choice -notin 0..($i-1)){
						Write-Host "`nIncorrect value supplied." -ForegroundColor Red
						Write-Host "Please select key vault name from below:" -ForegroundColor Cyan

						$i=0;
						$keyVault | where{Write-Host "[$i] $($_.VaultName)" -ForegroundColor Cyan; $i++}
						$choice = Read-Host "Key vault name choice"
					}
					$KVName = $keyVault[$choice].VaultName
					Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name kvName -Value $KVName
					
					$KVCredentialType = $null
					$KVCredentialName = $null

					Write-Host "`nPlease select key vault credential type from below: `n[1]: Key`n[2]: Secret" -ForegroundColor Cyan
					$input = Read-Host "`Key Vault credential type"
					
					while(($input -ne 1) -and ($input -ne 2)){
						Write-Host "`nIncorrect value supplied." -ForegroundColor Red
						Write-Host "Please select key vault credential type from below: `n[1]: Key`n[2]: Secret" -ForegroundColor Cyan
						$input = Read-Host "Key Vault credential type"
					}

					if($input -eq 1)
					{
						$KVCredentialType = "Key"
						Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name kvCredType -Value $KVCredentialType
						$keys = Get-AzKeyVaultKey -VaultName $KVName -ErrorAction Ignore
						if($keys){
							Write-Host "`nPlease select key name from below:" -ForegroundColor Cyan
							$i=0;
							$keys | where{Write-Host "[$i] $($_.Name)" -ForegroundColor Cyan; $i++}
							$choice = Read-Host "Key name choice"
							while($choice -notin 0..($i-1)){
								Write-Host "`nIncorrect value supplied." -ForegroundColor Red
								Write-Host "Please select key name from below:" -ForegroundColor Cyan
			
								$i=0;
								$keys | where{Write-Host "[$i] $($_.Name)" -ForegroundColor Cyan; $i++}
								$choice = Read-Host "Key name choice"
							}
							$KVCredentialName = $keys[$choice].Name
							Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name kvCredName -Value $KVCredentialName
							$key = Get-AzKeyVaultKey -VaultName $KVName -Name $KVCredentialName -ErrorAction Ignore
							Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name expiryTime -Value $key.Expires
							if($key.Expires){
								if($startTime.AddDays($credentialInfo.rotationInt) -gt $key.Expires){
									$credentialInfo.lastUpdatedOn = ($key.Expires).AddDays(-($credentialInfo.rotationInt))
								}
								else{
									$credentialInfo.lastUpdatedOn = $startTime
								}
							}
							Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name version -Value $key.Version

						}
						else{
							$found = $false;
							$this.PublishCustomMessage("Either there are no keys in the key vault [$KVName] or you do not have sufficient permissions to access them.",[MessageType]::Error)
						}
					}
					elseif($input -eq 2)
					{
						$KVCredentialType = "Secret"
						Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name kvCredType -Value $KVCredentialType
						$secrets = Get-AzKeyVaultSecret -VaultName $KVName -ErrorAction Ignore
						if($secrets){
							Write-Host "`nPlease select secret name from below:" -ForegroundColor Cyan
							$i=0;
							$secrets | where{Write-Host "[$i] $($_.Name)" -ForegroundColor Cyan; $i++}
							$choice = Read-Host "Secret name choice"
							while($choice -notin 0..($i-1)){
								Write-Host "`nIncorrect value supplied." -ForegroundColor Red
								Write-Host "Please select secret name from below:" -ForegroundColor Cyan
			
								$i=0;
								$secrets | where{Write-Host "[$i] $($_.Name)" -ForegroundColor Cyan; $i++}
								$choice = Read-Host "Secret name choice"
							}
							$KVCredentialName = $secrets[$choice].Name
							Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name kvCredName -Value $KVCredentialName
							$secret = Get-AzKeyVaultSecret -VaultName $KVName -Name $KVCredentialName -ErrorAction Ignore
							Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name expiryTime -Value $secret.Expires
							if($secret.Expires){
								if($startTime.AddDays($credentialInfo.rotationInt) -gt $secret.Expires){
									$credentialInfo.lastUpdatedOn = ($secret.Expires).AddDays(-($credentialInfo.rotationInt))
								}
								else{
									$credentialInfo.lastUpdatedOn = $startTime
								}
							}
							Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name version -Value $secret.Version

						}
						else{
							$found = $false;
							$this.PublishCustomMessage("Either there are no secrets in the key vault [$KVName] or you do not have sufficient permissions to access them.",[MessageType]::Error)
						}
					}
				}		
				else{
					$found = $false
					$this.PublishCustomMessage("There are no key vaults in your subscription.", [MessageType]::Error)
				}
			}

			$ag = $null;
			if($found -and $CredentialGroup){
				$actionGroups = Get-AzActionGroup -ErrorAction Ignore -WarningAction Ignore

				if(($actionGroups|Measure-Object).Count -gt 0){
					$ag = $actionGroups | where{$_.Name -eq $CredentialGroup}
					
					if(-not $ag){
						$this.PublishCustomMessage("The action group [$CredentialGroup] does not exist in the subscription.",[MessageType]::Error)
						Write-Host "`nPlease select action group name from below:" -ForegroundColor Cyan
						Write-Host "[0] Create new credential group" -ForegroundColor Cyan
						$i=1;
						$actionGroups | where{Write-Host "[$i] $($_.Name)" -ForegroundColor Cyan; $i++}
						$choice = Read-Host "Credential group choice"
						while($choice -notin 0..$i){
							Write-Host "`nIncorrect value supplied." -ForegroundColor Red
							Write-Host "Please select action group name from below:" -ForegroundColor Cyan
							Write-Host "[0] Create new credential group" -ForegroundColor Cyan
							$i=1;
							$actionGroups | where{Write-Host "[$i] $($_.Name)" -ForegroundColor Cyan; $i++}
							$choice = Read-Host "Credential group choice"
						}
						if($choice -ne 0){
							$ag = $actionGroups[$choice-1]
							$CredentialGroup = $ag.Name
						}
						elseif($choice -eq 0){
							$emailR = $null;
							$phoneR = $null;
							$rgName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName

							Write-Host "`nInitiating flow for creating a new credential group..." -ForegroundColor Yellow
							$name = Read-Host "Please enter the name of the credential group"
							$shortName = Read-Host "Please enter the short name (less than 12 characters) of the credential group"
							
							Write-Host "`nPlease enter: `n[0]: to skip email configuration `n[1]: to configure email for the credential group" -ForegroundColor Cyan
							$choice = Read-Host "User choice"
							while($choice -notin 0..1){
								Write-Host "`nIncorrect value supplied." -ForegroundColor Red
								Write-Host "`nPlease enter: `n[0]: to skip email configuration `n[1]: to configure email for the credential group" -ForegroundColor Cyan
								$choice = Read-Host "User choice"
							}
							if($choice -eq 1){
								$email = Read-Host "Enter a valid email address"
								$emailR = New-AzActionGroupReceiver -Name 'email' -EmailReceiver -EmailAddress $email -ErrorAction Ignore
							}

							Write-Host "`nPlease enter: `n[0]: to skip SMS configuration `n[1]: to configure SMS for the credential group" -ForegroundColor Cyan
							$choice = Read-Host "User choice"
							while($choice -notin 0..1){
								Write-Host "`nIncorrect value supplied." -ForegroundColor Red
								Write-Host "`nPlease enter: `n[0]: to skip SMS configuration `n[1]: to configure SMS for the credential group" -ForegroundColor Cyan
								$choice = Read-Host "User choice"
							}
							if($choice -eq 1){
								$countryCode = Read-Host "Enter a valid country code"
								$phone = Read-Host "Enter a valid contact number"
								$phoneR = New-AzActionGroupReceiver -Name 'SMS' -SmsReceiver -CountryCode $countryCode -PhoneNumber $phone -ErrorAction Ignore
							}

							if($emailR -and $phoneR){
								$ag = Set-AzActionGroup -Name $name -ResourceGroupName $rgName -ShortName $shortName -Receiver $emailR,$phoneR -ErrorAction Ignore -WarningAction Ignore
							}
							elseif($emailR){
								$ag = Set-AzActionGroup -Name $name -ResourceGroupName $rgName -ShortName $shortName -Receiver $emailR -ErrorAction Ignore -WarningAction Ignore
							}
							elseif($phoneR) {
								$ag = Set-AzActionGroup -Name $name -ResourceGroupName $rgName -ShortName $shortName -Receiver $phoneR -ErrorAction Ignore -WarningAction Ignore
							}
						}
						
					}

					if($ag){
						$CredentialGroup = $ag.Name
						$this.InstallCredentialGroupAlert($ag);
						Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name credGroup -Value $CredentialGroup
					}
					else{
						$this.PublishCustomMessage("Error occured while creating the new credential group.", [MessageType]::Error)
					}
					
				}	
				else{
					Write-Host "`nPlease enter [0] to create a new credential group" -ForegroundColor Cyan
					$choice = Read-Host "User choice"

					if($choice -eq 0){
						$emailR = $null;
						$phoneR = $null;
						$rgName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName

						Write-Host "`nInitiating flow for creating a new credential group..." -ForegroundColor Yellow
						$name = Read-Host "Please enter the name of the credential group"
						$shortName = Read-Host "Please enter the short name (less than 12 characters) of the credential group"
							
						Write-Host "`nPlease enter: `n[0]: to skip email configuration `n[1]: to configure email for the credential group" -ForegroundColor Cyan
						$choice = Read-Host "User choice"
						while($choice -notin 0..1){
							Write-Host "`nIncorrect value supplied." -ForegroundColor Red
							Write-Host "`nPlease enter: `n[0]: to skip email configuration `n[1]: to configure email for the credential group" -ForegroundColor Cyan
							$choice = Read-Host "User choice"
						}
						if($choice -eq 1){
							$email = Read-Host "Enter a valid email address"
							$emailR = New-AzActionGroupReceiver -Name 'email' -EmailReceiver -EmailAddress $email -ErrorAction Ignore
						}
						Write-Host "`nPlease enter: `n[0]: to skip SMS configuration `n[1]: to configure SMS for the credential group" -ForegroundColor Cyan
						$choice = Read-Host "User choice"
						while($choice -notin 0..1){
							Write-Host "`nIncorrect value supplied." -ForegroundColor Red
							Write-Host "`nPlease enter: `n[0]: to skip SMS configuration `n[1]: to configure SMS for the credential group" -ForegroundColor Cyan
							$choice = Read-Host "User choice"
						}
						if($choice -eq 1){
							$countryCode = Read-Host "Enter a valid country code"
							$phone = Read-Host "Enter a valid contact number"
							$phoneR = New-AzActionGroupReceiver -Name 'SMS' -SmsReceiver -CountryCode $countryCode -PhoneNumber $phone -ErrorAction Ignore
						}

						if($emailR -and $phoneR){
							$ag = Set-AzActionGroup -Name $name -ResourceGroupName $rgName -ShortName $shortName -Receiver $emailR,$phoneR -ErrorAction Ignore -WarningAction Ignore
						}
						elseif($emailR){
							$ag = Set-AzActionGroup -Name $name -ResourceGroupName $rgName -ShortName $shortName -Receiver $emailR -ErrorAction Ignore -WarningAction Ignore
						}
						elseif($phoneR) {
							$ag = Set-AzActionGroup -Name $name -ResourceGroupName $rgName -ShortName $shortName -Receiver $phoneR -ErrorAction Ignore -WarningAction Ignore
						}

						if($ag){
							$CredentialGroup = $ag.Name
							$this.InstallCredentialGroupAlert($ag);
							Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name credGroup -Value $CredentialGroup
						}
						else{
							$this.PublishCustomMessage("Error occured while creating the new credential group.", [MessageType]::Error)
						}
					}
					else{
						$this.PublishCustomMessage("There are no action groups in your subscription.", [MessageType]::Error)
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
			$this.PublishCustomMessage("Could not find an entry for credential [$CredentialName].", [MessageType]::Critical)
		}
		if(Test-Path $file)
		{
			Remove-Item -Path $file
		}
	}
	
	[void] UpdateAlert($CredentialName,$RotationIntervalInDays,$CredentialGroup,$UpdateCredential,$ResetLastUpdate,$Comment)
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
			$user = ([ContextHelper]::GetCurrentRMContext()).Account.Id;
			$currentTime = [DateTime]::UtcNow

			if ($RotationIntervalInDays)
			{
				$credentialInfo.rotationInt = $RotationIntervalInDays;
			}

			$ag = $null;
			if($CredentialGroup){
				$actionGroups = Get-AzActionGroup -ErrorAction Ignore -WarningAction Ignore
				if(($actionGroups|Measure-Object).Count -gt 0){
					$ag = $actionGroups | where{$_.Name -eq $CredentialGroup}
					
					if(-not $ag){
						$this.PublishCustomMessage("The action group [$CredentialGroup] does not exist in the subscription.",[MessageType]::Error)
						Write-Host "`nPlease select action group name from below:" -ForegroundColor Cyan
						$i=0;
						$actionGroups | where{Write-Host "[$i] $($_.Name)" -ForegroundColor Cyan; $i++}
						$choice = Read-Host "Credential group choice"
						while($choice -notin 0..($i-1)){
							Write-Host "`nIncorrect value supplied." -ForegroundColor Red
							Write-Host "Please select action group name from below:" -ForegroundColor Cyan
							$i=0;
							$actionGroups | where{Write-Host "[$i] $($_.Name)" -ForegroundColor Cyan; $i++}
							$choice = Read-Host "Credential group choice"
						}
						$ag = $actionGroups[$choice]
						$CredentialGroup = $ag.Name
					}

					$this.InstallCredentialGroupAlert($ag);
					if([Helpers]::CheckMember($credentialInfo,"credGroup")){
						$credentialInfo.credGroup = $CredentialGroup
					}
					else{
						Add-Member -InputObject $credentialInfo -MemberType NoteProperty -Name credGroup -Value $CredentialGroup
					}
				}
				else{
					$this.PublishCustomMessage("Could not update the credential group for the credential [$CredentialName] as there are no action groups in your subscription.", [MessageType]::Error)
				}
				
			}

			if($UpdateCredential){
			
				if($credentialInfo.credLocation -eq "AppService"){
					
					$resource = Get-AzWebApp -Name $credentialInfo.resourceName
					
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
						Set-AzWebApp -Name $credentialInfo.resourceName -ResourceGroupName $resource.ResourceGroup -AppSettings $hash | Out-Null
						$this.PublishCustomMessage("Successfully updated the application setting [$($credentialInfo.appConfigName)] in the app service [$($credentialInfo.resourceName)]", [MessageType]::Update)
					}
					elseif($credentialInfo.appConfigType -eq "Connection Strings"){
						Set-AzWebApp -Name $credentialInfo.resourceName -ResourceGroupName $resource.ResourceGroup -ConnectionStrings $hash | Out-Null
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

				$credentialInfo.lastUpdatedOn = $currentTime
				$credentialInfo.lastUpdatedBy = $user
			}
			else{
				if($ResetLastUpdate){
					$credentialInfo.lastUpdatedOn = $currentTime
					$credentialInfo.lastUpdatedBy = $user
				}
				if([Helpers]::CheckMember($credentialInfo,'expiryTime')){
					if($credentialInfo.expiryTime){
						$credentialInfo.lastUpdatedOn = ($credentialInfo.expiryTime).AddDays(-$credentialInfo.rotationInt)
					}
				}
			}

			$credentialInfo.comment = $Comment
			$credentialInfo | ConvertTo-Json -Depth 10 | Out-File $file -Force
			Set-AzStorageBlobContent -Blob $blobName -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -File $file -Force | Out-Null
			$this.PublishCustomMessage("Successfully updated settings for AzSK tracked credential [$CredentialName]", [MessageType]::Update) 
			$this.PrintInfo($credentialInfo);
		}
		else{
			$this.PublishCustomMessage("Could not find an entry for credential [$CredentialName].", [MessageType]::Critical)
		}
		if(Test-Path $file)
		{
			Remove-Item -Path $file
		}
	}

	[void] InstallAlert($AlertEmail)
	{
		$rgName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
		$credHygieneAGName = [Constants]::CredHygieneActionGroupName
		$credHygieneAGShortName = [Constants]::CredHygieneActionGroupShortName
		
		$email = New-AzActionGroupReceiver -Name $AlertEmail -EmailReceiver -EmailAddress $AlertEmail
		$actionGroup = Set-AzActionGroup -Name $credHygieneAGName -ResourceGroupName $rgName -ShortName $credHygieneAGShortName -Receiver $email -ErrorAction Ignore -WarningAction SilentlyContinue
		
		if($actionGroup){
			# We are using LAWS from the same sub for Alert REST API call.
			$automationAccDetails= Get-AzAutomationAccount -ResourceGroupName $rgName -ErrorAction SilentlyContinue 
			if($automationAccDetails)
			{
				#Fetch LAWS Id from CA variables
				$laWSId = Get-AzAutomationVariable -ResourceGroupName $automationAccDetails.ResourceGroupName -AutomationAccountName $automationAccDetails.AutomationAccountName -Name "LAWSId" -ErrorAction SilentlyContinue

				if($laWSId){
					$laWS = Get-AzOperationalInsightsWorkspace | where{$_.CustomerId -eq $laWSId.Value} # Verify whether the LA resource ith the WS id exists.
					if($laWS){
						$body = [ConfigurationManager]::LoadServerConfigFile("CredentialHygieneAlert.json");
						$dataSourceId = $body.properties.source.dataSourceId | ConvertTo-Json -Depth 10
						$dataSourceId = $dataSourceId.Replace("{0}",$this.SubscriptionContext.SubscriptionId).Replace("{1}",$laWS.ResourceGroupName).Replace("{2}",$laWS.CustomerId) | ConvertFrom-Json
						$body.properties.source.dataSourceId = $dataSourceId

						$ag = $body.properties.action.aznsAction.actionGroup[0] | ConvertTo-Json -Depth 10
						$ag = $ag.Replace("{3}",$actionGroup.Id) | ConvertFrom-Json
						$body.properties.action.aznsAction.actionGroup[0] = $ag
							
						$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()	
						$uri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/resourcegroups/$($laWS.ResourceGroupName)/providers/microsoft.insights/scheduledQueryRules/AzSK_CredHygiene_Alert?api-version=2018-04-16"
								
						[WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $uri, $body);
						$this.PublishCustomMessage("Alert for the credential group [$credHygieneAGName] is successfully configured.");
					}
					else{ # LA resource not found.
						$this.PublishCustomMessage("Log Analytics resource with workspace Id [$($laWSId.Value)] provided in the CA automation account variables doesn't exist. Please verify the value of Log Analytics workspace Id.", [MessageType]::Error)
						$this.PublishCustomMessage("Couldn't create credential hygiene alert for the current subscription.", [MessageType]::Error)
						$this.PublishCustomMessage("Run Update-AzSKContinuousAssurance to update the Log Analytics workspace Id with the correct value in the CA automation account.")
					}
				}
				else{ # LAWS id variable not found.
					$this.PublishCustomMessage("Log Analytics workspace Id not found in the CA automation account variables.", [MessageType]::Error)
					$this.PublishCustomMessage("Couldn't create credential hygiene alert for the current subscription.", [MessageType]::Error)
					$this.PublishCustomMessage("Run Update-AzSKContinuousAssurance to update the Log Analytics workspace Id with the correct value in the CA automation account.")
				}
			}
			else{ # CA setup not found.
				$this.PublishCustomMessage("Continuous Assurance setup was not found in the current subscription.", [MessageType]::Error)
				$this.PublishCustomMessage("Couldn't create credential hygiene alert for the current subscription.", [MessageType]::Error)
			}
		}
		else{ # Action group not found/created.
			$this.PublishCustomMessage("Couldn't create action group [$credHygieneAGName] for credential hygiene alerts.", [MessageType]::Error)
			$this.PublishCustomMessage("Couldn't create credential hygiene alert for the current subscription.", [MessageType]::Error)
		}
	}	 

	[void] InstallCredentialGroupAlert($actionGroup)
	{	
		$rgName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName

		# We are using LAWS from the same sub for Alert REST API call.
		$automationAccDetails= Get-AzAutomationAccount -ResourceGroupName $rgName -ErrorAction SilentlyContinue 
		if($automationAccDetails)
		{
			#Fetch LAWS Id from CA variables
			$laWSId = Get-AzAutomationVariable -ResourceGroupName $automationAccDetails.ResourceGroupName -AutomationAccountName $automationAccDetails.AutomationAccountName -Name "LAWSId" -ErrorAction SilentlyContinue
			if($laWSId){
				$laWS = Get-AzOperationalInsightsWorkspace | where{$_.CustomerId -eq $laWSId.Value} # Verify whether the LA resource ith the WS id exists.
				if($laWS){
					
					$body = [ConfigurationManager]::LoadServerConfigFile("CredentialHygieneAlert_CredentialGroup.json");
					$dataSourceId = $body.properties.source.dataSourceId | ConvertTo-Json -Depth 10
					$dataSourceId = $dataSourceId.Replace("{0}",$this.SubscriptionContext.SubscriptionId).Replace("{1}",$laWS.ResourceGroupName).Replace("{2}",$laWS.CustomerId) | ConvertFrom-Json
					$body.properties.source.dataSourceId = $dataSourceId
					
					$ag = $body.properties.action.aznsAction.actionGroup[0] | ConvertTo-Json -Depth 10
					$ag = $ag.Replace("{3}",$actionGroup.Id) | ConvertFrom-Json
					$body.properties.action.aznsAction.actionGroup[0] = $ag
					
					$cg = $body.properties.source.query | ConvertTo-Json -Depth 10
					$cg = $cg.Replace("{4}",$actionGroup.Name) | ConvertFrom-Json
					$body.properties.source.query = $cg
						
					$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()	
					$uri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/resourcegroups/$($laWS.ResourceGroupName)/providers/microsoft.insights/scheduledQueryRules/AzSK_CredHygiene_Alert_$($actionGroup.GroupShortName)?api-version=2018-04-16"
								
					[WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $uri, $body);
					$this.PublishCustomMessage("Alert for the credential group [$($actionGroup.Name)] is successfully configured.");
				}
				else{ # LA resource not found.
					$this.PublishCustomMessage("Log Analytics resource with workspace Id [$($laWSId.Value)] provided in the CA automation account variables doesn't exist. Please verify the value of Log Analytics workspace Id.", [MessageType]::Error)
					$this.PublishCustomMessage("Couldn't create credential hygiene alert for the current subscription.", [MessageType]::Error)
					$this.PublishCustomMessage("Run Update-AzSKContinuousAssurance to update the Log Analytics workspace Id with the correct value in the CA automation account.")
				}
			}
			else{ # LAWS id variable not found.
				$this.PublishCustomMessage("Log Analytics workspace Id not found in the CA automation account variables.", [MessageType]::Error)
				$this.PublishCustomMessage("Couldn't create credential hygiene alert for the current subscription.", [MessageType]::Error)
				$this.PublishCustomMessage("Run Update-AzSKContinuousAssurance to update the Log Analytics workspace Id with the correct value in the CA automation account.")
			}
		}
		else{ # CA setup not found.
			$this.PublishCustomMessage("Continuous Assurance setup was not found in the current subscription.", [MessageType]::Error)
			$this.PublishCustomMessage("Couldn't create credential hygiene alert for the current subscription.", [MessageType]::Error)
		}	
	}	 
}