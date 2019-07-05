Set-StrictMode -Version Latest

class CredRotation : CommandBase{
    [string] $credName;
    [string] $credLocation;
    [int] $rotationInt;
    [string] $alertPhoneNumber = "";
	[string] $alertEmail;
    [string] $comment;
    hidden [string] $AzSKTemp = [Constants]::AzSKAppFolderPath + [Constants]::RotationMetadataSubPath; 
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

    [void] SetAlert($CredentialLocation, $ResourceGroupName, $ResourceName, $AppConfigType, $AppConfigName, $KVName, $KVCredentialType, $KVCredentialName)
	{           
        $file = $this.AzSKTemp + "\$($this.SubscriptionContext.SubscriptionId)\" + $this.credName + ".json"
        $this.GetAzSKRotationMetadatContainer()
        $blobName = $this.credName + ".json"

        if(![string]::isnullorwhitespace($this.SubscriptionContext.SubscriptionId)){
			if(-not (Test-Path "$($this.AzSKTemp)\$($this.SubscriptionContext.SubscriptionId)"))
			{
				mkdir -Path "$($this.AzSKTemp)\$($this.SubscriptionContext.SubscriptionId)" -ErrorAction Stop | Out-Null
			}	
		}
		else{
			if(-not (Test-Path "$($this.AzSKTemp)"))
			{
				mkdir -Path "$($this.AzSKTemp)" -ErrorAction Stop | Out-Null
			}
		}

        $blobContent = Get-AzStorageBlobContent -Blob $blobName -Container $this.RotationMetadataContainerName -Context $this.AzSKStorageAccount.Context -Destination $file -Force -ErrorAction Ignore
        if($blobContent){
            Write-Host "Entry for the credential [$($this.credName)] already exists. Run Update-AzSKCredentialALert to update alert configurations for the existing credential." -ForegroundColor Yellow
        }
        else{
            
            $startTime = [DateTime]::UtcNow
            $user = ([Helpers]::GetCurrentRMContext()).Account.Id
            Write-Host "Onboarding the credential [$($this.credName)] for rotation/expiry notification" -ForegroundColor White
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
            Write-Host "Successfully onboarded the credential [$($this.credName)] for rotation/expiry notification" -ForegroundColor Green
        }
        Write-Host "Run Get-AzSKCredentialAlert to list all the credentials onboarded for rotation/expiry notification." -ForegroundColor Cyan
            Write-Host "1"
	}
}