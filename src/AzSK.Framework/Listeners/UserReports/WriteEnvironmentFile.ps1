Set-StrictMode -Version Latest 
class WriteEnvironmentFile: FileOutputBase
{
    hidden static [WriteEnvironmentFile] $Instance = $null;
    static [WriteEnvironmentFile] GetInstance()
    {
        if ($null -eq  [WriteEnvironmentFile]::Instance)
        {
            [WriteEnvironmentFile]::Instance = [WriteEnvironmentFile]::new();
        }

        return [WriteEnvironmentFile]::Instance
    }

    [void] RegisterEvents()
    {        
        $this.UnregisterEvents();

        $this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
            $currentInstance = [WriteEnvironmentFile]::GetInstance();
            try 
            {
                $currentInstance.SetRunIdentifier([AzSKRootEventArgument] ($Event.SourceArgs | Select-Object -First 1));                         
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

		$this.RegisterEvent([SVTEvent]::CommandStarted, {
            $currentInstance = [WriteEnvironmentFile]::GetInstance();
            try 
            {
				$currentInstance.CommandStartedAction($Event.SourceArgs.SubscriptionContext);
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

		$this.RegisterEvent([AzSKRootEvent]::CommandStarted, {
            $currentInstance = [WriteEnvironmentFile]::GetInstance();
            try 
            {
				$currentInstance.CommandStartedAction($Event.SourceArgs.SubscriptionContext);
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });
    }
	
	hidden [void] AddOutputLog([string] $message, [bool] $includeTimeStamp)   
    {
        if([string]::IsNullOrEmpty($message) -or [string]::IsNullOrEmpty($this.FilePath))
        {
            return;
        }
             
        if($includeTimeStamp)
        {
            $message = (Get-Date -format "MM\/dd\/yyyy HH:mm:ss") + "-" + $message
        }

        Add-Content -Value $message -Path $this.FilePath
    } 

    hidden [void] AddOutputLog([string] $message)   
    {
       $this.AddOutputLog($message, $false);  
    } 

	[void] CommandStartedAction([SubscriptionContext] $context)
	{     
		$this.SetFilePath($context, [FileOutputBase]::ETCFolderPath, "EnvironmentDetails.LOG");  	
		$this.AddOutputLog([Constants]::DoubleDashLine);

		$currentVersion = $this.GetCurrentModuleVersion();
		$moduleName = $this.GetModuleName();
		$this.AddOutputLog("Environment log");
		$this.AddOutputLog("$moduleName Version: $currentVersion");
		$this.AddOutputLog([Constants]::DoubleDashLine);

		$this.AddOutputLog("Method Name: $($this.InvocationContext.MyCommand.Name) `r`nInput Parameters: ");
		$this.AddOutputLog([Helpers]::ConvertObjectToString($this.InvocationContext.BoundParameters, $false));
		$this.AddOutputLog([Constants]::DoubleDashLine);

		$loadedModules = (Get-Module | Select-Object -Property Name, Version, Path | Format-Table -AutoSize -Wrap | Out-String);
		$this.AddOutputLog("Loaded PowerShell modules");
        $this.AddOutputLog([Helpers]::ConvertObjectToString($loadedModules, $false));      
		$this.AddOutputLog([Constants]::DoubleDashLine);

		$rmContext = [ContextHelper]::GetCurrentRMContext()

        $this.AddOutputLog("Logged-in user context");
        $loggedInUserContext = ($rmContext.Account | Select-Object -Property Id, Type, ExtendedProperties)
        if([Helpers]::CheckMember($loggedInUserContext, "ExtendedProperties") -and $loggedInUserContext.ExtendedProperties.ContainsKey("ServicePrincipalSecret")){
            $loggedInUserContext.ExtendedProperties["ServicePrincipalSecret"] = "MASKED"
        }
		$this.AddOutputLog([Helpers]::ConvertObjectToString($loggedInUserContext, $false));
		$this.AddOutputLog([Constants]::DoubleDashLine);

		$this.AddOutputLog("Az context");
		$this.AddOutputLog([Helpers]::ConvertObjectToString(($rmContext | Select-Object -Property Environment, Subscription, Tenant), $false));
		$this.AddOutputLog([Constants]::DoubleDashLine);
	}

}
