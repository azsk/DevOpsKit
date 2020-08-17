using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class HostInfo: CommandBase
{    
	HostInfo([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext) 
    { 
		$this.DoNotOpenOutputFolder = $true;
	}
	
	[MessageData[]] GetHostInfo()
	{
		$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nFetching configuration details from the host machine...`r`n" + [Constants]::DoubleDashLine);

		$loadedModules = (Get-Module | Select-Object -Property Name, Description, Version, Path);
		$this.PublishCustomMessage("`n`n");
		$this.PublishCustomMessage("Loaded PowerShell modules", [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString($loadedModules, $true), [MessageType]::Default);
		$this.PublishCustomMessage("`r`n" +[Constants]::DoubleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage("`n`n");
		$rmContext = [ContextHelper]::GetCurrentContext();
		$this.PublishCustomMessage("Logged-in user context", [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString(($rmContext.Account | Select-Object -Property Id, Type), $true), [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage("`n`n");
		$this.PublishCustomMessage("`r`nAzSK Settings`r`n" + [Constants]::SingleDashLine, [MessageType]::Default);
		$settingsRaw = [ConfigurationManager]::GetLocalAzSKSettings();
		$settings = $this.MaskSettings($settingsRaw);
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString($settings, $true), [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage("`n`n");
		$this.PublishCustomMessage("`r`nAzSK Configurations`r`n" + [Constants]::SingleDashLine, [MessageType]::Default);
		$configurationsRaw = [ConfigurationManager]::GetAzSKConfigData();
		$configurations = $this.MaskSettings($configurationsRaw);
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString($configurations, $true), [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage("`n`n"); 
		$this.PublishCustomMessage("`r`nAz context`r`n" + [Constants]::SingleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString(($rmContext | Select-Object -Property Subscription, Tenant), $false), [MessageType]::Default);
	
		[MessageData[]] $returnMsgs = @();
		$returnMsgs += [MessageData]::new("Returning ADO Host Info.");
		return $returnMsgs
	}

	GetAzSKVersion()
	{
		$configuredVersion = [System.Version] $this.GetCurrentModuleVersion()
		$serverVersion = [System.Version] ([ConfigurationManager]::GetAzSKConfigData().GetLatestAzSKVersion($this.GetModuleName()));
		$updateAvailable = $false;
		$actionMessage = "No Action Required"
		if($serverVersion -gt $this.GetCurrentModuleVersion()) 
		{
			$updateAvailable = $true;
			$actionMessage = "Use " + [ConfigurationManager]::GetAzSKConfigData().InstallationCommand + " to update AzSK"
        	}
		else
		{
			$actionMessage = [Constants]::NoActionRequiredMessage
		}

		$this.AddConfigurationDetails('DevOpsKit (AzSK)', $configuredVersion, $serverVersion, $serverVersion, $actionMessage)
	}

	[PSObject] MaskSettings($settingsRaw)
	{
		#All secrets/keys in AzSKSettings end with the text "Key", mask those that have values.
		$settingsRaw | Get-Member -Type Property | Where-Object {$_.Name -Match "Key$"} | ForEach-Object {
				$n = $_.Name; 
				$v = $settingsRaw.$n;
				if (-not [string]::IsNullOrEmpty($v))
				{
					$len = $v.Length 
					#Upto 8 chars, let us mask everything
					if ($len -le 8)
					{
						$maskCount = $len
						$showCount = 0
					}
					else #More than 8 chars, show 1/3rd or 8 whichever is smaller
					{
						$showCount =  [Math]::Min( ([Math]::Floor($len/3)), 8)
						$maskCount = $len - $showCount
					}
					$regEx = ".{$maskCount}$" #RegEx for last n chars
					$maskedStr = "*"*$maskCount #Replaced value
					$settingsRaw.$n = $settingsRaw.$n -replace $regEx,$maskedStr #Replace
				}
		}
		return $settingsRaw;
	}
}