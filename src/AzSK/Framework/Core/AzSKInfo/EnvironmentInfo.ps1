using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class EnvironmentInfo: CommandBase
{    

	EnvironmentInfo([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext) 
    { 
		$this.DoNotOpenOutputFolder = $true;
	}
	
	GetEnvironmentInfo()
	{
		$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nFetching configuration details from the host machine...`r`n" + [Constants]::DoubleDashLine);

		$loadedModules = (Get-Module | Select-Object -Property Name, Description, Version, Path);
		$this.PublishCustomMessage("Loaded PowerShell modules", [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString($loadedModules, $true), [MessageType]::Default);
		$this.PublishCustomMessage("`r`n" +[Constants]::DoubleDashLine, [MessageType]::Default);

		$rmContext = [Helpers]::GetCurrentRMContext();
		$this.PublishCustomMessage("Logged-in user context", [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString(($rmContext.Account | Select-Object -Property Id, Type), $true), [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		
		$this.PublishCustomMessage("`r`nAzSK Settings`r`n" + [Constants]::SingleDashLine, [MessageType]::Default);
		$settings = [ConfigurationManager]::GetLocalAzSKSettings();
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString($settings, $true), [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);

		$this.PublishCustomMessage("`r`nAzSK Configurations`r`n" + [Constants]::SingleDashLine, [MessageType]::Default);
		$configurations = [ConfigurationManager]::GetAzSKConfigData();
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString($configurations, $true), [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);

		$this.PublishCustomMessage("`r`nAzureRM context`r`n" + [Constants]::SingleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString(($rmContext | Select-Object -Property Subscription, Tenant), $false), [MessageType]::Default);
	}
}