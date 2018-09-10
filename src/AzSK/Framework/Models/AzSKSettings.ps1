Set-StrictMode -Version Latest
class AzSKSettings {
    [string] $OMSWorkspaceId;
    [string] $OMSSharedKey;
	[string] $AltOMSWorkspaceId;
    [string] $AltOMSSharedKey;
    [string] $OMSType;
	[string] $OMSSource;

	[string] $EventHubNamespace;
	[string] $EventHubName;
	[string] $EventHubSendKeyName;
	[string] $EventHubSendKey;
    [string] $EventHubType;
	[string] $EventHubSource;

	[string] $WebhookUrl;
	[string] $WebhookAuthZHeaderName;
	[string] $WebhookAuthZHeaderValue;
	[string] $WebhookType;
	[string] $WebhookSource;
	[string] $AutoUpdateCommand;
	[AutoUpdate] $AutoUpdateSwitch = [AutoUpdate]::NotSet;

	[string] $OutputFolderPath;


	[TertiaryBool] $AllowSelfSignedWebhookCertificate;
	[bool] $EnableAADAuthForOnlinePolicyStore;
    [bool] $UseOnlinePolicyStore;
    [string] $OnlinePolicyStoreUrl;
	[string] $UsageTelemetryLevel;
	[string] $LocalControlTelemetryKey;
	[bool] $LocalEnableControlTelemetry;
	[bool] $PrivacyNoticeAccepted = $false;
	[bool] $IsCentralScanModeOn = $false;
    hidden static [AzSKSettings] $Instance = $null;
	hidden static [string] $FileName = "AzSKSettings.json";
	[bool] $StoreComplianceSummaryInUserSubscriptions;


    static [AzSKSettings] GetInstance() {
        if (-not [AzSKSettings]::Instance)
		{
			[AzSKSettings]::LoadAzSKSettings($false);
        }

        return [AzSKSettings]::Instance
    }

	static [AzSKSettings] GetLocalInstance() {
        return [AzSKSettings]::LoadAzSKSettings($true);
    }

    hidden static [AzSKSettings] LoadAzSKSettings([bool] $loadUserCopy) {
        #Filename will be static.
        #For AzSK Settings, never use online policy store. It's assumed that file will be available offline
		#-------- AzSK rename code change--------#
		$localAppDataSettings = $null

		# TBR : AzSDK cleanup on local machine for Local settings folder
		$AzSDKAppFolderPath = $Env:LOCALAPPDATA + "\Microsoft\" + "AzSDK*"
		if(Test-Path -Path $AzSDKAppFolderPath)
		{
		    Get-ChildItem -Path $AzSDKAppFolderPath -Directory | Remove-Item -Recurse -Force
		}
		
		if(-not $localAppDataSettings)
		{
			$localAppDataSettings = [ConfigurationHelper]::LoadOfflineConfigFile([AzSKSettings]::FileName)
		}
		
		#------------------------------#	
		[AzSKSettings] $parsedSettings = $null;
		[AzSKSettings] $localModuleSettings = $null;
		[AzSKSettings] $serverSettings = $null;
		$migratedPropNames = @();
        #Validate settings content is not null
        if ($localAppDataSettings) {
			try
			{
				#Step1: Try parsing the object from local app data settings. If parse is successful then there is no change to settings schema.
				$parsedSettings = [AzSKSettings] $localAppDataSettings
			}
			catch
			{
				#Step2: Any error occurred while converting local json file indicates change in schema
				#Load latest Settings from modules folder
				$parsedSettings = [ConfigurationHelper]::LoadModuleJsonFile([AzSKSettings]::FileName)
				$parsedSettings | Get-Member -MemberType Properties |
					ForEach-Object {
						$propertyName = $_.Name;
						if([Helpers]::CheckMember($localAppDataSettings, $propertyName))
						{
							$parsedSettings.$propertyName = $localAppDataSettings.$propertyName;
							$migratedPropNames += $propertyName;
						}
					};
				if($migratedPropNames.Count -ne 0)
				{
                    [AzSKSettings]::Update($parsedSettings);
					[EventBase]::PublishGenericCustomMessage("Local AzSK settings file was not compatible with the latest version. `r`nMigrated the existing values for properties: [$([string]::Join(", ", $migratedPropNames))] ", [MessageType]::Warning);
				}
			}

			#Step 3: Get the latest server settings and merge with that

			if(-not $loadUserCopy)
			{
				[bool] $_useOnlinePolicyStore = $parsedSettings.UseOnlinePolicyStore;
				[string] $_onlineStoreUri = $parsedSettings.OnlinePolicyStoreUrl;
				[bool] $_enableAADAuthForOnlinePolicyStore = $parsedSettings.EnableAADAuthForOnlinePolicyStore;
				$serverSettings = [ConfigurationHelper]::LoadServerConfigFile([AzSKSettings]::FileName, $_useOnlinePolicyStore, $_onlineStoreUri, $_enableAADAuthForOnlinePolicyStore);

				$mergedServerPropNames = @();
				$serverSettings | Get-Member -MemberType Properties |
					ForEach-Object {
						$propertyName = $_.Name;
						if([string]::IsNullOrWhiteSpace($parsedSettings.$propertyName) -and -not [string]::IsNullOrWhiteSpace($serverSettings.$propertyName))
						{
							$parsedSettings.$propertyName = $serverSettings.$propertyName;
							$mergedServerPropNames += $propertyName;
						}
					};				
				[AzSKSettings]::Instance = $parsedSettings;				
			}
            #Sever merged settings should not be persisted, as it should always take latest from the server
			return $parsedSettings;
        }
		else
		{
			return $null;
		}
    }

    [void] Update()
	{
		if (-not (Test-Path $([Constants]::AzSKAppFolderPath)))
		{
			mkdir -Path $([Constants]::AzSKAppFolderPath) -ErrorAction Stop | Out-Null
		}

		#persisting back to file
		[AzSKSettings]::Instance | ConvertTo-Json | Out-File -Force -FilePath ([Constants]::AzSKAppFolderPath + "\" + [AzSKSettings]::FileName)
	}

    static [void] Update([AzSKSettings] $localSettings)
	{
		if (-not (Test-Path $([Constants]::AzSKAppFolderPath)))
		{
			mkdir -Path $([Constants]::AzSKAppFolderPath) -ErrorAction Stop | Out-Null
		}

		#persisting back to file
		$localSettings | ConvertTo-Json | Out-File -Force -FilePath ([Constants]::AzSKAppFolderPath + "\" + [AzSKSettings]::FileName)
	}
	
	hidden [string] GetScanSource()
	{
		return $this.OMSSource
	}
}
