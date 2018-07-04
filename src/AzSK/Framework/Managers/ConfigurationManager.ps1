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
        $IdPropName = "Id"
        $finalObject = [Helpers]::MergeObjects($defaultConfigFile,$extendedConfigFile, $IdPropName);
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

		#check for extension type only if we dont find the type already loaded in to the current session
		if(-not ($extensionSVTClassName -as [type]))
		{
			$extensionSVTClassFileName = $svtClassName + ".ext.ps1";
			try {
                $localExtensionsFolderPath = [Constants]::AzSKExtensionsFolderPath;
                if(-not (Test-Path -Path $localExtensionsFolderPath))
                {
                    mkdir -Path $localExtensionsFolderPath -Force
                }
                $extensionScriptCode = [ConfigurationManager]::LoadServerFileRaw($extensionSVTClassFileName);
                $extensionFilePath = "$([Constants]::AzSKExtensionsFolderPath)\$extensionSVTClassFileName";
                Out-File -InputObject $extensionScriptCode -Force -FilePath $extensionFilePath -Encoding utf8;
                #$extensionScriptCode | Out-File $extensionFilePath -Force
                & $extensionFilePath 
                				
				if(-not ($extensionSVTClassName -as [type]))
				{
					#set extension class name to empty if it is not found
					$extensionSVTClassName = ""
				}
			}
			catch {
				Write-host $_;
			}
        }
        return $extensionSVTClassName
    }	
}
