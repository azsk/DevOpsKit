Set-StrictMode -Version Latest

class ConfigOverride
{
	hidden [string] $ConfigFileName;
	[PSObject] $ParsedFile;
	hidden [string[]] $ChangedProperties = @();
	
	ConfigOverride([string] $configFileName)
	{
		if([string]::IsNullOrWhiteSpace($configFileName))
		{
			throw [System.ArgumentException] ("The argument 'configFileName' is null or empty")
		}

		$this.ConfigFileName = $configFileName;
		$this.ParsedFile = [ConfigurationHelper]::LoadModuleJsonFile($configFileName);

		if(-not $this.ParsedFile)
		{
			throw [System.ArgumentException] ("The file '$configFileName' is empty")
		}
	}

	ConfigOverride([string] $FolderPath, [string] $fileName)
	{
		if([string]::IsNullOrWhiteSpace($fileName))
		{
			throw [System.ArgumentException] ("The argument 'configFileName' is null or empty")
		}

		$this.ConfigFileName = $fileName;
		#Load file from AzSK App folder
        $rootConfigPath = $FolderPath ;
		$extension = [System.IO.Path]::GetExtension($fileName);

		$filePath = $null
		if(Test-Path -Path $rootConfigPath)
		{
			$filePath = (Get-ChildItem $rootConfigPath -Name -Recurse -Include $fileName) | Select-Object -First 1 
		}

        if ($filePath) {
			if($extension -eq ".json")
			{
				$this.ParsedFile = (Get-Content -Raw -Path ($rootConfigPath + $filePath)) | ConvertFrom-Json
			}
			else
			{
				$this.ParsedFile = (Get-Content -Raw -Path ($rootConfigPath + $filePath)) 
			}
        }
        else {
            throw "Unable to find the specified file '$fileName'"          
        }        
	}

	[bool] UpdatePropertyValue([string] $propertyName, [PSObject] $propertyValue)
	{
		if([string]::IsNullOrWhiteSpace($propertyName))
		{
			throw [System.ArgumentException] ("The argument 'propertyName' is null or empty")
		}

		#if(-not $propertyValue)
		#{
		#	throw [System.ArgumentException] ("The argument 'propertyValue' is null or empty")
		#}

		if([Helpers]::CheckMember($this.ParsedFile, $propertyName, $false))
		{
			$this.ParsedFile.$propertyName = $propertyValue;
			$this.ChangedProperties += $propertyName;
			return $true;
		}
		else
		{
			$this.ParsedFile | Add-Member -Type NoteProperty -Name $propertyName -Value $propertyValue
			$this.ChangedProperties += $propertyName;
			return $true;
		}

		return $false;
	}

	[void] WriteToFolder()
	{
		$this.WriteToFolder([Constants]::AzSKAppFolderPath + "\Temp\PolicySetup");
	}

	[void] WriteToFolder([string] $folderName)
	{
		if([string]::IsNullOrWhiteSpace($folderName))
		{
			throw [System.ArgumentException] ("The argument 'folderName' is null or empty")
		}

		if (-not (Test-Path $folderName)) 
		{
			mkdir -Path $folderName -ErrorAction Stop | Out-Null
		}

		if (-not $folderName.EndsWith("\"))
		{
			$folderName += "\";
		}

		[Helpers]::ConvertToJsonCustom(($this.ParsedFile | Select-Object -Property $this.ChangedProperties)) | Out-File -Force -FilePath ($folderName + $this.ConfigFileName) -Encoding utf8
	}

	[void] static ClearConfigInstance()
	{
		[AzSKSettings]::Instance = $null
		[AzSKConfig]::Instance = $null
		[ConfigurationHelper]::ServerConfigMetadata = $null
		[ConfigurationHelper]::OfflineMode = $false
		[ConfigurationHelper]::ConfigVersion = $null
		[ConfigurationHelper]::IsIssueLogged = $false
		[ConfigurationHelper]::LocalPolicyEnabled = $false
	}
}
