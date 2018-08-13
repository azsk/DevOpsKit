Set-StrictMode -Version Latest
#
# ConfigManager.ps1
#
class ConfigurationManager
{
	hidden static [AzSKConfig] GetAzSKConfigData()
    {        
        return [AzSKConfig]::GetInstance([ConfigurationManager]::GetAzSKSettings().UseOnlinePolicyStore, [ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl, [ConfigurationManager]::GetAzSKSettings().EnableAADAuthForOnlinePolicyStore)		
    }	
	
	hidden static [AzSKSettings] GetAzSKSettings()
    {        
        return [AzSKSettings]::GetInstance()
    }

	hidden static [AzSKSettings] GetLocalAzSKSettings()
    {        
        return [AzSKSettings]::GetLocalInstance()
    }

	hidden static [AzSKSettings] UpdateAzSKSettings([AzSKSettings] $localSettings)
    {        
        return [AzSKSettings]::Update($localSettings)
    }
	
	hidden static [SVTConfig] GetSVTConfig([string] $fileName)
    {        
        $defaultConfigFile = [ConfigurationHelper]::LoadServerConfigFile($fileName, [ConfigurationManager]::GetAzSKSettings().UseOnlinePolicyStore, [ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl, [ConfigurationManager]::GetAzSKSettings().EnableAADAuthForOnlinePolicyStore);
        $extendedFileName = $fileName.Replace(".json",".ext.json");
        $extendedConfigFile = [ConfigurationHelper]::LoadServerFileRaw($extendedFileName, [ConfigurationManager]::GetAzSKSettings().UseOnlinePolicyStore, [ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl, [ConfigurationManager]::GetAzSKSettings().EnableAADAuthForOnlinePolicyStore);
        $finalObject = [SVTConfig] $defaultConfigFile;
        if(-not [string]::IsNullOrWhiteSpace($extendedConfigFile))
        {
            $IdPropName = "Id"
            $finalObject = [SVTConfig]([Helpers]::MergeObjects($defaultConfigFile,$extendedConfigFile, $IdPropName));
        }        
        return $finalObject;
    }

	hidden static [PSObject] LoadServerConfigFile([string] $fileName)
    {
        return [ConfigurationHelper]::LoadServerConfigFile($fileName, [ConfigurationManager]::GetAzSKSettings().UseOnlinePolicyStore, [ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl, [ConfigurationManager]::GetAzSKSettings().EnableAADAuthForOnlinePolicyStore);
    }

    hidden static [PSObject] LoadServerFileRaw([string] $fileName)
    {
        return [ConfigurationHelper]::LoadServerFileRaw($fileName, [ConfigurationManager]::GetAzSKSettings().UseOnlinePolicyStore, [ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl, [ConfigurationManager]::GetAzSKSettings().EnableAADAuthForOnlinePolicyStore);
    }

    hidden static [string] LoadExtensionFile([string] $svtClassName)
    {
        $extensionSVTClassName = $svtClassName + "Ext";
        $extensionFilePath = ""
		#check for extension type only if we dont find the type already loaded in to the current session
		if(-not ($extensionSVTClassName -as [type]))
		{
			$extensionSVTClassFileName = $svtClassName + ".ext.ps1";
			try {
				$extensionFilePath = [ConfigurationManager]::DownloadExtFile($extensionSVTClassFileName)
			}
			catch {
				[EventBase]::PublishGenericException($_);
			}
        }
        return $extensionFilePath
    }	

	hidden static [string[]] RegisterExtListenerFiles()
    {
		$ServerConfigMetadata = [ConfigurationManager]::LoadServerConfigFile([Constants]::ServerConfigMetadataFileName)
		$ListenerFilePaths = @();
		if($null -ne [ConfigurationHelper]::ServerConfigMetadata)
		{
			[ConfigurationHelper]::ServerConfigMetadata.OnlinePolicyList | ForEach-Object {
				if([Helpers]::CheckMember($_,"Name"))
				{
					if($_.Name -match "Listener.ext.ps1")
					{
						$listenerFileName = $_.Name
						try {
							$extensionFilePath = [ConfigurationManager]::DownloadExtFile($listenerFileName)
							# file has to be loaded here due to scope constraint
							$ListenerFilePaths += $extensionFilePath
						}
						catch {
							[EventBase]::PublishGenericException($_);
						}
					}
				}
			}
		}
		return $ListenerFilePaths;
    }

	hidden static [string] DownloadExtFile([string] $fileName)
	{
		$localExtensionsFolderPath = [Constants]::AzSKExtensionsFolderPath;
		$extensionFilePath = ""

		if(-not (Test-Path -Path $localExtensionsFolderPath))
		{
			mkdir -Path $localExtensionsFolderPath -Force
		}
		
		$extensionScriptCode = [ConfigurationManager]::LoadServerFileRaw($fileName);
		
		if(-not [string]::IsNullOrWhiteSpace($extensionScriptCode))
        {
			$extensionFilePath = "$([Constants]::AzSKExtensionsFolderPath)\$fileName";
            Out-File -InputObject $extensionScriptCode -Force -FilePath $extensionFilePath -Encoding utf8;       
		}

		return $extensionFilePath
	}
}
