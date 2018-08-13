Set-StrictMode -Version Latest 

class GenericListener: ListenerBase
{		
	hidden static [GenericListener] $Instance = $null;  
	
	hidden [GenericListenerBase[]] $ExtendedListeners = @();
	
	
	GenericListener()
	{
		
	}

	static [GenericListener] GetInstance()
	{
		if($null -eq [GenericListener]::Instance)
		{
			[GenericListener]::Instance = [GenericListener]::new();
		}
		return [GenericListener]::Instance;
	}

	[void] RegisterEvents()
	{
		$this.UnregisterEvents();

		# Mandatory: Generate Run Identifier Event
        $this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
            $currentInstance = [GenericListener]::GetInstance();
            try 
            {
				$rootEventArgs = [AzSKRootEventArgument] ($Event.SourceArgs | Select-Object -First 1);
				$currentInstance.SetRunIdentifier($rootEventArgs);                         				
				$currentInstance.LoadExtendedListeners($rootEventArgs);
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });	
		
		$this.RegisterEvent([SVTEvent]::CommandStarted, {
			$currentInstance = [GenericListener]::GetInstance();
            try 
            {
				$params = @{};
				$params.Add("EventArgs", $Event.SourceArgs);
				$currentInstance.CallListenersMethod("SVTCommandStarted",$params);
			}
			catch{
				$currentInstance.PublishException($_);
			}
			
		});


		$this.RegisterEvent([AzSKRootEvent]::CommandStarted, {
            $currentInstance = [GenericListener]::GetInstance();
            try 
            {
				$params = @{};
				$params.Add("EventArgs", $Event.SourceArgs);
				$currentInstance.CallListenersMethod("GenericCommandStarted",$params);
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });


		$this.RegisterEvent([AzSKRootEvent]::CommandCompleted, {
			$currentInstance = [GenericListener]::GetInstance();
			try 
			{
				$params = @{};
				$params.Add("EventArgs", $Event.SourceArgs);
				$currentInstance.CallListenersMethod("GenericCommandCompleted",$params);
			}
			catch 
			{
				$currentInstance.PublishException($_);
			}
		});

		$this.RegisterEvent([SVTEvent]::CommandCompleted, {
            $currentInstance = [GenericListener]::GetInstance();
            try 
            {
				$params = @{};
				$params.Add("EventArgs", $Event.SourceArgs);
				$currentInstance.CallListenersMethod("SVTCommandCompleted",$params);
			}
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

		$this.RegisterEvent([SVTEvent]::EvaluationStarted, {
			$currentInstance = [GenericListener]::GetInstance();
			try
			{
				$params = @{};
				$params.Add("EventArgs", $Event.SourceArgs);
				$currentInstance.CallListenersMethod("FeatureEvaluationStarted",$params);
			}
			catch
			{
				$currentInstance.PublishException($_);
			}
		});

		$this.RegisterEvent([SVTEvent]::EvaluationCompleted, {
			$currentInstance = [GenericListener]::GetInstance();
			try
			{
				$params = @{};
				$params.Add("EventArgs", $Event.SourceArgs);
				$currentInstance.CallListenersMethod("FeatureEvaluationCompleted",$params);
			}
			catch
			{
				$currentInstance.PublishException($_);
			}
		});
	}

	[void] LoadExtendedListeners([AzSKRootEventArgument] $rootEventArgs)
	{
		if(($this.ExtendedListeners | Measure-Object).Count -le 0)
		{
			$ListenerFilePaths = [ConfigurationManager]::RegisterExtListenerFiles();
			if(($ListenerFilePaths | Measure-Object).Count -gt 0)
			{				
				$ListenerFilePaths | ForEach-Object {
					$listenerPath = $_;
					. $listenerPath
					$listenerFileName = [System.IO.Path]::GetFileName($listenerPath);
					$listenerClassName = $listenerFileName.trimend(".ext.ps1") + "Ext"
					$listenerObject = New-Object -TypeName $listenerClassName -ArgumentList $this, $rootEventArgs
					$this.ExtendedListeners += $listenerObject;
				}
			}
		}		
	}

	[void] CallListenersMethod($methodName, $parameters)
	{
		if(($this.ExtendedListeners | Measure-Object).Count -gt 0)
		{
			$this.ExtendedListeners | ForEach-Object {
				$listenerObject = $_
				$listenerObject.$methodName($parameters);
			}
		}
	}
}