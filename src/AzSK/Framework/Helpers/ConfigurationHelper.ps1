Set-StrictMode -Version Latest
#
# ConfigurationHelper.ps1
#
class ConfigurationHelper {
	hidden static [bool] $IsIssueLogged = $false
	hidden static [PSObject] $ServerConfigMetadata = $null
	hidden static [bool] $OfflineMode = $false;
	hidden static [string] $ConfigVersion =""
	hidden static [bool] $LocalPolicyEnabled= $false
	hidden static [string] $ConfigPath = [string]::Empty
	hidden static [PSObject] LoadOfflineConfigFile([string] $fileName)
	{
		return [ConfigurationHelper]::LoadOfflineConfigFile($fileName, $true);
	}
	hidden static [PSObject] LoadOfflineConfigFile([string] $fileName, [bool] $parseJson) {
		$rootConfigPath = [Constants]::AzSKAppFolderPath + "\" ;
		return [ConfigurationHelper]::LoadOfflineConfigFile($fileName, $true,$rootConfigPath);
	}
    hidden static [PSObject] LoadOfflineConfigFile([string] $fileName, [bool] $parseJson, $path) {
		#Load file from AzSK App folder
		$rootConfigPath = $path + "\" ;	
        
		$extension = [System.IO.Path]::GetExtension($fileName);

		$filePath = $null
		if(Test-Path -Path $rootConfigPath)
		{
			$filePath = (Get-ChildItem $rootConfigPath -Name -Recurse -Include $fileName) | Select-Object -First 1 
		}
        #If file not present in App folder load settings from Configurations in Module folder 
        if (!$filePath) {
            $rootConfigPath = (Get-Item $PSScriptRoot).Parent.FullName + "\Configurations\";
            $filePath = (Get-ChildItem $rootConfigPath -Name -Recurse -Include $fileName) | Select-Object -First 1 
        }

        if ($filePath)
		{
			if($parseJson)
			{
				if($extension -eq ".json" -or $extension -eq ".omsview")
				{
					$fileContent = (Get-Content -Raw -Path ($rootConfigPath + $filePath)) | ConvertFrom-Json
				}
				else
				{
					$fileContent = (Get-Content -Raw -Path ($rootConfigPath + $filePath)) 
				}
			}
			else
			{
				$fileContent = (Get-Content -Raw -Path ($rootConfigPath + $filePath)) 
			}
        }
        else {
            throw "Unable to find the specified file '$fileName'"          
        }
        if (-not $fileContent) {
            throw "The specified file '$fileName' is empty"                                  
        }

        return $fileContent;
    }	

    hidden static [PSObject] LoadServerConfigFile([string] $policyFileName, [bool] $useOnlinePolicyStore, [string] $onlineStoreUri, [bool] $enableAADAuthForOnlinePolicyStore) {
        [PSObject] $fileContent = "";
        if ([string]::IsNullOrWhiteSpace($policyFileName)) {
            throw [System.ArgumentException] ("The argument 'policyFileName' is null");
        } 

        if ($useOnlinePolicyStore) {
			
            if ([string]::IsNullOrWhiteSpace($onlineStoreUri)) 
			{
                throw [System.ArgumentException] ("The argument 'onlineStoreUri' is null");
			} 
			
			if($policyFileName -eq [Constants]::ServerConfigMetadataFileName -and $null -ne [ConfigurationHelper]::ServerConfigMetadata)
			{
				return [ConfigurationHelper]::ServerConfigMetadata;
			}
			#First load offline OSS Content
			$fileContent = [ConfigurationHelper]::LoadOfflineConfigFile($policyFileName)

			#Check if policy present in server using metadata file
			if(-not [ConfigurationHelper]::OfflineMode -and [ConfigurationHelper]::IsPolicyPresentOnServer($policyFileName,$useOnlinePolicyStore,$onlineStoreUri,$enableAADAuthForOnlinePolicyStore))
			{
				try 
				{
					if([String]::IsNullOrWhiteSpace([ConfigurationHelper]::ConfigVersion) -and -not [ConfigurationHelper]::LocalPolicyEnabled)
					{
						try
						{
							$Version = [System.Version] ($global:ExecutionContext.SessionState.Module.Version);
							$serverFileContent = [ConfigurationHelper]::InvokeControlsAPI($onlineStoreUri, $Version, $policyFileName, $enableAADAuthForOnlinePolicyStore);
							[ConfigurationHelper]::ConfigVersion = $Version;
						}
						catch
						{
							try{
								$Version = ([ConfigurationHelper]::LoadOfflineConfigFile("AzSK.json")).ConfigSchemaBaseVersion;
								$serverFileContent = [ConfigurationHelper]::InvokeControlsAPI($onlineStoreUri, $Version, $policyFileName, $enableAADAuthForOnlinePolicyStore);
								[ConfigurationHelper]::ConfigVersion = $Version;
							}
							catch{
								if(Test-Path $onlineStoreUri)
								{	
									[EventBase]::PublishGenericCustomMessage("Running Org-Policy from local policy store location: [$onlineStoreUri]", [MessageType]::Warning);
									$serverFileContent = [ConfigurationHelper]::LoadOfflineConfigFile($policyFileName, $true, $onlineStoreUri)
									[ConfigurationHelper]::LocalPolicyEnabled = $true
								}
								else {
									throw $_
								}
							}
						}
					}
					elseif([ConfigurationHelper]::LocalPolicyEnabled)
					{
						$serverFileContent = [ConfigurationHelper]::LoadOfflineConfigFile($policyFileName, $true, $onlineStoreUri)
					}
					else
					{
						$Version = [ConfigurationHelper]::ConfigVersion ;
						$serverFileContent = [ConfigurationHelper]::InvokeControlsAPI($onlineStoreUri, $Version, $policyFileName, $enableAADAuthForOnlinePolicyStore);
					}

					#Completely override offline config if Server Override flag is enabled
					if([ConfigurationHelper]::IsOverrideOfflineEnabled($policyFileName))
					{
						$fileContent = $serverFileContent
					}
					else
					{
						$fileContent = [Helpers]::MergeObjects($fileContent,$serverFileContent)	
					}
				}
				catch 
				{
					[ConfigurationHelper]::OfflineMode = $true;

					if(-not [ConfigurationHelper]::IsIssueLogged)
					{
						if([Helpers]::CheckMember($_,"Exception.Response.StatusCode") -and  $_.Exception.Response.StatusCode.ToString().ToLower() -eq "unauthorized")
						{
							[EventBase]::PublishGenericCustomMessage(("Not able to fetch org-specific policy. The current Azure subscription is not linked to your org tenant."), [MessageType]::Warning);
							[ConfigurationHelper]::IsIssueLogged = $true
						}
						elseif($policyFileName -eq [Constants]::ServerConfigMetadataFileName)
						{
							[EventBase]::PublishGenericCustomMessage(("Not able to fetch org-specific policy. Validate if org policy url is correct or policy is migrated with latest AzSK"), [MessageType]::Warning);
							[ConfigurationHelper]::IsIssueLogged = $true
						}
						else
						{
							[EventBase]::PublishGenericCustomMessage(("Error while fetching the policy [$policyFileName] from online store. " + [Constants]::OfflineModeWarning), [MessageType]::Warning);
							[EventBase]::PublishGenericException($_);
							[ConfigurationHelper]::IsIssueLogged = $true
						}
					}            
				}
			}

            if (-not $fileContent) {
                #Fire special event to notify user about switching to offline policy  
                $fileContent = [ConfigurationHelper]::LoadOfflineConfigFile($policyFileName)
            }
            # return $updateResult	
        }
        else {
            [EventBase]::PublishGenericCustomMessage(([Constants]::OfflineModeWarning + " Policy: $policyFileName"), [MessageType]::Warning);
            $fileContent = [ConfigurationHelper]::LoadOfflineConfigFile($policyFileName)
        }        

        if (-not $fileContent) {
            throw "The specified file '$policyFileName' is empty"                                  
        }

        return $fileContent;
    }

	hidden static [PSObject] LoadServerFileRaw([string] $fileName, [bool] $useOnlinePolicyStore, [string] $onlineStoreUri, [bool] $enableAADAuthForOnlinePolicyStore)
	{
		[PSObject] $fileContent = "";
        if ([string]::IsNullOrWhiteSpace($fileName)) {
            throw [System.ArgumentException] ("The argument 'fileName' is null");
        } 

        if ($useOnlinePolicyStore) {
			
            if ([string]::IsNullOrWhiteSpace($onlineStoreUri)) 
			{
                throw [System.ArgumentException] ("The argument 'onlineStoreUri' is null");
            } 

			#Check if policy present in server using metadata file
			if(-not [ConfigurationHelper]::OfflineMode -and [ConfigurationHelper]::IsPolicyPresentOnServer($fileName,$useOnlinePolicyStore,$onlineStoreUri,$enableAADAuthForOnlinePolicyStore))
			{
				try 
				{
					if([String]::IsNullOrWhiteSpace([ConfigurationHelper]::ConfigVersion))
					{							
						try
						{
							$Version = [System.Version] ($global:ExecutionContext.SessionState.Module.Version);
							$serverFileContent = [ConfigurationHelper]::InvokeControlsAPI($onlineStoreUri, $Version, $fileName, $enableAADAuthForOnlinePolicyStore);
							[ConfigurationHelper]::ConfigVersion = $Version;
						}
						catch
						{
							$Version = ([ConfigurationHelper]::LoadOfflineConfigFile("AzSK.json")).ConfigSchemaBaseVersion;
							$serverFileContent = [ConfigurationHelper]::InvokeControlsAPI($onlineStoreUri, $Version, $fileName, $enableAADAuthForOnlinePolicyStore);
							[ConfigurationHelper]::ConfigVersion = $Version;
						}
					}
					else
					{
						$Version = [ConfigurationHelper]::ConfigVersion ;
						$serverFileContent = [ConfigurationHelper]::InvokeControlsAPI($onlineStoreUri, $Version, $fileName, $enableAADAuthForOnlinePolicyStore);
					}
						
					$fileContent = $serverFileContent
				}
				catch 
				{
					[ConfigurationHelper]::OfflineMode = $true;

					if(-not [ConfigurationHelper]::IsIssueLogged)
					{
						if([Helpers]::CheckMember($_,"Exception.Response.StatusCode") -and  $_.Exception.Response.StatusCode.ToString().ToLower() -eq "unauthorized")
						{
							[EventBase]::PublishGenericCustomMessage(("Not able to fetch org-specific policy. The current Azure subscription is not linked to your org tenant."), [MessageType]::Warning);
							[ConfigurationHelper]::IsIssueLogged = $true
						}
						elseif($fileName -eq [Constants]::ServerConfigMetadataFileName)
						{
							[EventBase]::PublishGenericCustomMessage(("Not able to fetch org-specific policy. Validate if org policy url is correct or policy is migrated with latest AzSK"), [MessageType]::Warning);
							[ConfigurationHelper]::IsIssueLogged = $true
						}
						else
						{
							[EventBase]::PublishGenericCustomMessage(("Error while fetching the policy [$fileName] from online store. " + [Constants]::OfflineModeWarning), [MessageType]::Warning);
							[EventBase]::PublishGenericException($_);
							[ConfigurationHelper]::IsIssueLogged = $true
						}
					}            
				}
				
				
			}

        }
        else {
            [EventBase]::PublishGenericCustomMessage(([Constants]::OfflineModeWarning + " Policy: $fileName"), [MessageType]::Warning);            
        }        

        return $fileContent;
	}

	hidden static [PSObject] InvokeControlsAPI([string] $onlineStoreUri,[string] $configVersion, [string] $policyFileName, [bool] $enableAADAuthForOnlinePolicyStore)
	{
		#Evaluate all code block in onlineStoreUri. 
		#Can use '$FileName' in uri to fill dynamic file name.
		#Revisit
		$FileName = $policyFileName;
		$Version = $configVersion;
		$uri = $global:ExecutionContext.InvokeCommand.ExpandString($onlineStoreUri)
		[System.Uri] $validatedUri = $null;
		if([System.Uri]::TryCreate($uri, [System.UriKind]::Absolute, [ref] $validatedUri))
		{
			if($enableAADAuthForOnlinePolicyStore)
			{
				$accessToken = [Helpers]::GetAccessToken("https://management.core.windows.net/")
				$serverFileContent = Invoke-RestMethod `
									-Method GET `
									-Uri $validatedUri `
                					-Headers @{"Authorization" = "Bearer $accessToken"} `
									-UseBasicParsing
				return $serverFileContent
			}
			else 
			{
				$serverFileContent = Invoke-RestMethod `
									-Method GET `
									-Uri $validatedUri `
									-UseBasicParsing
				return $serverFileContent
			}
		}
		else
		{
			[EventBase]::PublishGenericCustomMessage(("'UseOnlinePolicyStore' is enabled but the 'OnlinePolicyStoreUrl' is not valid Uri: [$uri]. `r`n" + [Constants]::OfflineModeWarning), [MessageType]::Warning);
			[ConfigurationHelper]::OfflineMode = $true;
		}
		return $null;
	}

	#Need to rethink on this function logic
	hidden static [PSObject] LoadModuleJsonFile([string] $fileName) {
	
	 $rootConfigPath = (Get-Item $PSScriptRoot).Parent.FullName + "\Configurations\";
     $filePath = (Get-ChildItem $rootConfigPath -Name -Recurse -Include $fileName) | Select-Object -First 1 
	 if ($filePath) {
            $fileContent = (Get-Content -Raw -Path ($rootConfigPath + $filePath)) | ConvertFrom-Json
        }
        else {
            throw "Unable to find the specified file '$fileName'"          
        }
	return $fileContent;
	}

	hidden static [PSObject] LoadModuleRawFile([string] $fileName) {
	
	 $rootConfigPath = (Get-Item $PSScriptRoot).Parent.FullName + "\Configurations\";
     $filePath = (Get-ChildItem $rootConfigPath -Name -Recurse -Include $fileName) | Select-Object -First 1 
	 if ($filePath) {
            $fileContent = (Get-Content -Raw -Path ($rootConfigPath + $filePath)) 
        }
        else {
            throw "Unable to find the specified file '$fileName'"          
        }
	return $fileContent;
	}

	hidden static [bool] IsPolicyPresentOnServer([string] $fileName, [bool] $useOnlinePolicyStore, [string] $onlineStoreUri, [bool] $enableAADAuthForOnlinePolicyStore)
	{
		#Check if Config meta data is null and load the meta data from server
		if($null -eq [ConfigurationHelper]::ServerConfigMetadata)
		{
			#if File is meta data file then return true
			if($fileName -eq [Constants]::ServerConfigMetadataFileName)
			{
				return $true
			}
			else
			{				
				$filecontent = [ConfigurationHelper]::LoadServerConfigFile([Constants]::ServerConfigMetadataFileName, $useOnlinePolicyStore, $onlineStoreUri, $enableAADAuthForOnlinePolicyStore);							
				[ConfigurationHelper]::ServerConfigMetadata = $filecontent;
			}
		}
		
		if($null -ne [ConfigurationHelper]::ServerConfigMetadata)
		{
			if([ConfigurationHelper]::ServerConfigMetadata.OnlinePolicyList | Where-Object { $_.Name -eq $fileName})
			{
				return $true
			}
			else
			{
				return $false
			}
		}
		else
		{
			#If Metadata file is not present on server then set offline default meta data.. 
			[ConfigurationHelper]::ServerConfigMetadata = [ConfigurationHelper]::LoadOfflineConfigFile([Constants]::ServerConfigMetadataFileName);
			return $false			
		}
	}

	#Function to check if Override Offline flag is enabled 
	hidden static [bool] IsOverrideOfflineEnabled([string] $fileName)
	{
		if($fileName -eq [Constants]::ServerConfigMetadataFileName)
		{
			return $true
		}

		$PolicyMetadata = [ConfigurationHelper]::ServerConfigMetadata.OnlinePolicyList | Where-Object { $_.Name -eq $fileName}
		if(($PolicyMetadata -and [Helpers]::CheckMember($PolicyMetadata,"OverrideOffline") -and $PolicyMetadata.OverrideOffline -eq $true) )
		{
			return $true
		}
		else
		{
			return $false
		}
	}
}
