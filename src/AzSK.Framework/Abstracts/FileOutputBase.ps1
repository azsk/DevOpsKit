Set-StrictMode -Version Latest 
class FileOutputBase: ListenerBase
{
    static [string] $ETCFolderPath = "Etc";

	[string] $FilePath = "";
    [string] $FolderPath = "";
    #[string] $BasePath = "";
    hidden [string[]] $BasePaths = @();
    
    FileOutputBase()
    {   
        [Helpers]::AbstractClass($this, [FileOutputBase]);
    }     

	hidden [void] AddBasePath([string] $path)
    {
		if(-not [string]::IsNullOrWhiteSpace($path))
		{
			$path = $global:ExecutionContext.InvokeCommand.ExpandString($path);
			if(Test-Path -Path $path)
			{
				$this.BasePaths += $path;
			}
		}
	}

	[void] SetRunIdentifier([AzSKRootEventArgument] $arguments)
    {
		([ListenerBase]$this).SetRunIdentifier($arguments);

		$this.AddBasePath([ConfigurationManager]::GetAzSKSettings().OutputFolderPath);
		$this.AddBasePath([ConfigurationManager]::GetAzSKConfigData().OutputFolderPath);
		$this.AddBasePath([Constants]::AzSKLogFolderPath);
	}

	hidden [string] CalculateFolderPath([SubscriptionContext] $context, [string] $subFolderPath, [int] $pathIndex)
    {
		$outputPath = "";
		if($context -and (-not [string]::IsNullOrWhiteSpace($context.SubscriptionName)) -and (-not [string]::IsNullOrWhiteSpace($context.SubscriptionId)))
		{
			$isDefaultPath = $false;
			if($pathIndex -lt $this.BasePaths.Count)
			{
				$basePath = $this.BasePaths.Item($pathIndex);
			}
			else
			{
				$isDefaultPath = $true;
				$basePath = [Constants]::AzSKLogFolderPath;
			}

			if (-not $basePath.EndsWith("\")) {
				$basePath += "\";
			}

			$outputPath = $basePath + [Constants]::AzSKModuleName + "Logs\"

			$sanitizedPath = [Helpers]::SanitizeFolderName($context.SubscriptionName);
			if ([string]::IsNullOrEmpty($sanitizedPath)) {
				$sanitizedPath = $context.SubscriptionId;
			}

			$runPath = $this.RunIdentifier;
			$commandMetadata = $this.GetCommandMetadata();

			if($commandMetadata)
			{
				$runPath += "_" + $commandMetadata.ShortName;
			}

			if ([string]::IsNullOrEmpty($sanitizedPath)) {
				$outputPath += ("Default\{0}\" -f $runPath);            
			}
			else {
				$outputPath += ("Sub_{0}\{1}\" -f $sanitizedPath, $runPath);            
			}

			if (-not [string]::IsNullOrEmpty($subFolderPath)) {
				$sanitizedPath = [Helpers]::SanitizeFolderName($subFolderPath);
				if (-not [string]::IsNullOrEmpty($sanitizedPath)) {
					$outputPath += ("{0}\" -f $sanitizedPath);            
				}   
			}

			if(-not (Test-Path $outputPath))
			{
				try
				{
					mkdir -Path $outputPath -ErrorAction Stop | Out-Null
				}
				catch
				{
					$outputPath = "";
					if(-not $isDefaultPath)
					{
						$outputPath = $this.CalculateFolderPath($context, $subFolderPath, $pathIndex + 1);
					}
				}
			}
		}
		return $outputPath;
	}

	[string] CalculateFolderPath([SubscriptionContext] $context, [string] $subFolderPath)
	{
		return $this.CalculateFolderPath($context, $subFolderPath, 0);
	}

	[string] CalculateFolderPath([SubscriptionContext] $context)
	{
		return $this.CalculateFolderPath($context, "");
	}

	[void] SetFolderPath([SubscriptionContext] $context)
    {
		$this.SetFolderPath($context, "");
	}

    [void] SetFolderPath([SubscriptionContext] $context, [string] $subFolderPath)
    {
        $this.FolderPath = $this.CalculateFolderPath($context, $subFolderPath);
    }

	[string] CalculateFilePath([SubscriptionContext] $context, [string] $fileName)
	{
		return $this.CalculateFilePath($context, "", $fileName);
	}

	[string] CalculateFilePath([SubscriptionContext] $context, [string] $subFolderPath, [string] $fileName)
    {
		$outputPath = "";
		$this.SetFolderPath($context, $subFolderPath); 
        if ([string]::IsNullOrEmpty($this.FolderPath)) {
            return $outputPath;
        }

        $outputPath = $this.FolderPath;
        if (-not $outputPath.EndsWith("\")) {
            $outputPath += "\";
        }
        if ([string]::IsNullOrEmpty($fileName)) {
            $outputPath += $(Get-Date -format "yyyyMMdd_HHmmss") + ".LOG";
        }
        else {
            $outputPath += $fileName;            
        }
		return $outputPath;
	}

    [void] SetFilePath([SubscriptionContext] $context, [string] $fileName)
    {
        $this.SetFilePath($context, "", $fileName);
    }

    [void] SetFilePath([SubscriptionContext] $context, [string] $subFolderPath, [string] $fileName)
    {
		$this.FilePath = $this.CalculateFilePath($context, $subFolderPath, $fileName);
    }
}
