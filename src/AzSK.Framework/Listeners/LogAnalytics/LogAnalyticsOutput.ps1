Set-StrictMode -Version Latest 

class LogAnalyticsOutput: ListenerBase
{		
	hidden static [LogAnalyticsOutput] $Instance = $null;  
	#Default source is kept as SDL / PowerShell. 
	static [string] $DefaultLAWSource = "SDL"
	#This value must be set in respective environment i.e. CICD,CA   
	hidden static [bool] $IsIssueLogged = $false
	LogAnalyticsOutput()
	{
		
	}

	static [LogAnalyticsOutput] GetInstance()
	{
		if($null -eq [LogAnalyticsOutput]::Instance)
		{
			[LogAnalyticsOutput]::Instance = [LogAnalyticsOutput]::new();
		}
		return [LogAnalyticsOutput]::Instance;
	}

	[void] RegisterEvents()
	{
			$this.UnregisterEvents();

			# Mandatory: Generate Run Identifier Event
			$this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
				$currentInstance = [LogAnalyticsOutput]::GetInstance();
				try 
				{
				    $currentInstance.SetRunIdentifier([AzSKRootEventArgument] ($Event.SourceArgs | Select-Object -First 1));                         
					
					[LogAnalyticsOutput]::IsIssueLogged = $false
				}
				catch 
				{
				    $currentInstance.PublishException($_);
				}
			});	
			
			$this.RegisterEvent([SVTEvent]::CommandStarted, {
				$currentInstance = [LogAnalyticsOutput]::GetInstance();
				try 
				{
					[LogAnalyticsHelper]::SetLAWDetails();
					$settings = [ConfigurationManager]::GetAzSKSettings()
					$currentInstance.PublishCustomMessage("Scan events will be sent to the following Log Analytics workspace(s):",[MessageType]::Info);
					if(-not [string]::IsNullOrEmpty($settings.LAWorkspaceId))
					{
						$currentInstance.PublishCustomMessage("WSId: $($settings.LAWorkspaceId)`n",[MessageType]::Info);
					}

					if(-not [string]::IsNullOrEmpty($settings.AltLAWorkspaceId))
					{
						$currentInstance.PublishCustomMessage("AltWsId: $($settings.AltLAWorkspaceId)`n",[MessageType]::Info);
						$currentInstance.PublishCustomMessage("`n");
					}
					else
					{
						$currentInstance.PublishCustomMessage("`n");
					}
					
					$currentInstance.CommandAction($Event,"Command Started");
				}
				catch{
					$currentInstance.PublishException($_);
				}
				
				#TODO: Disabling OMS inventory call. Need to rework on performance part.
				# if(-not ([LogAnalyticsHelper]::IsLAWSettingValid -eq -1 -and [LogAnalyticsHelper]::IsAltLAWSettingValid -eq -1))
				# {
				# 	try
				# 	{
				# 		$invocationContext = [System.Management.Automation.InvocationInfo] $currentInstance.InvocationContext
				# 		if(!$invocationContext.BoundParameters.ContainsKey("SubscriptionId")) {return;}
				# 		[LogAnalyticsHelper]::PostResourceInventory($currentInstance.GetAzSKContextDetails())
				# 	}
				# 	catch
				# 	{
				# 		$currentInstance.PublishException($_);
				# 	}
				# }
			});


			$this.RegisterEvent([AzSKRootEvent]::CommandStarted, {
				$currentInstance = [LogAnalyticsOutput]::GetInstance();
				try 
				{
					$currentInstance.CommandAction($Event,"Command Started");

				}
				catch 
				{
				    $currentInstance.PublishException($_);
				}
			});


			$this.RegisterEvent([AzSKRootEvent]::CommandCompleted, {
				$currentInstance = [LogAnalyticsOutput]::GetInstance();
				try 
				{
					$currentInstance.CommandAction($Event,"Command Completed");					
				}
				catch 
				{
					$currentInstance.PublishException($_);
				}
			});

			$this.RegisterEvent([SVTEvent]::CommandCompleted, {
				$currentInstance = [LogAnalyticsOutput]::GetInstance();
				try 
				{
					$currentInstance.CommandAction($Event,"Command Completed");				
				}
				catch 
				{
				    $currentInstance.PublishException($_);
				}
			});


			$this.RegisterEvent([SVTEvent]::EvaluationCompleted, {
				$currentInstance = [LogAnalyticsOutput]::GetInstance();
				try
				{
					$invocationContext = [System.Management.Automation.InvocationInfo] $currentInstance.InvocationContext
					$SVTEventContexts = [SVTEventContext[]] $Event.SourceArgs
					#foreach($svtEventContext in $SVTEventContexts)
					#{
					#	$currentInstance.WriteControlResult($svtEventContext);
					#}
					$currentInstance.WriteControlResult($SVTEventContexts);
				}
				catch
				{
					$currentInstance.PublishException($_);
				}
			});


			# $this.RegisterEvent([SVTEvent]::WriteInventory, {
			# 	$currentInstance = [LogAnalyticsOutput]::GetInstance();
			# 	try
			# 	{
			# 		[LogAnalyticsHelper]::SetLAWDetails();
			# 		if(-not ([LogAnalyticsHelper]::IsLAWSettingValid -eq -1 -and [LogAnalyticsHelper]::IsAltLAWSettingValid -eq -1))
			# 		{
			# 			$invocationContext = [System.Management.Automation.InvocationInfo] $currentInstance.InvocationContext
			# 			$SVTEventContexts = [SVTEventContext[]] $Event.SourceArgs
						
			# 			[LogAnalyticsHelper]::PostApplicableControlSet($SVTEventContexts,$currentInstance.GetAzSKContextDetails());
			# 		}
			# 	}
			# 	catch
			# 	{
			# 		$currentInstance.PublishException($_);
			# 	}
			# });
		
	}

	hidden [void] WriteControlResult([SVTEventContext[]] $eventContextAll)
	{
		try
		{
			$settings = [ConfigurationManager]::GetAzSKSettings()
			$tempBodyObjectsAll = [System.Collections.ArrayList]::new()

            try{
                
				if((-not [string]::IsNullOrWhiteSpace($settings.LAWorkspaceId)) -or (-not [string]::IsNullOrWhiteSpace($settings.AltLAWorkspaceId)))
				{
					$eventContextAll | ForEach-Object{
					$eventContext = $_
						$tempBodyObjects = [LogAnalyticsHelper]::GetLAWBodyObjects($eventContext,$this.GetAzSKContextDetails())
                    
						$tempBodyObjects | ForEach-Object{
							Set-Variable -Name tempBody -Value $_ -Scope Local
							$tempBodyObjectsAll.Add($tempBody)
						}
					}
					
					$body = $tempBodyObjectsAll | ConvertTo-Json
					$lawBodyByteArray = ([System.Text.Encoding]::UTF8.GetBytes($body))

					#publish to primary workspace
					if(-not [string]::IsNullOrWhiteSpace($settings.LAWorkspaceId) -and [LogAnalyticsHelper]::IsLAWSettingValid -ne -1)
					{
						[LogAnalyticsHelper]::PostLAWData($settings.LAWorkspaceId, $settings.LAWSharedKey, $lawBodyByteArray, $settings.LAWType, 'LAW')
					}

					#publish to secondary workspace
					if(-not [string]::IsNullOrWhiteSpace($settings.AltLAWorkspaceId) -and [LogAnalyticsHelper]::IsAltLAWSettingValid -ne -1)
					{
						[LogAnalyticsHelper]::PostLAWData($settings.AltLAWorkspaceId, $settings.AltLAWSharedKey, $lawBodyByteArray, $settings.LAWType, 'AltLAW')
					}
				}

                
			}
			catch
			{
				if(-not [LogAnalyticsOutput]::IsIssueLogged)
				{
					$this.PublishCustomMessage("An error occurred while pushing data to Log Analytics. Please check logs for more details. AzSK control evaluation results will not be sent to the configured Log Analytics workspace from this environment until the error is resolved.", [MessageType]::Warning);
					$this.PublishException($_);
					[LogAnalyticsOutput]::IsIssueLogged = $true
				}
			}
		}
		catch
		{
			[Exception] $ex = [Exception]::new("Error sending events to Log Analytics. The following exception occurred: `r`n$($_.Exception.Message) `r`nFor more on AzSK Log Analytics workspace setup, refer: https://aka.ms/devopskit/ca", $_.Exception)
			throw [SuppressedException] $ex
		}

		}

		hidden [AzSKContextDetails] GetAzSKContextDetails()
		{

			$AzSKContext = [AzSKContextDetails]::new();
			$AzSKContext.RunIdentifier= $this.RunIdentifier;
			$commandMetadata = $this.GetCommandMetadata();
			if($commandMetadata)
			{
				$AzSKContext.RunIdentifier += "_" + $commandMetadata.ShortName;
			}			
			$AzSKContext.Version = $scannerVersion = $this.GetCurrentModuleVersion()
			$settings = [ConfigurationManager]::GetAzSKSettings()

			if(-not [string]::IsNullOrWhiteSpace($settings.LAWSource))
			{
				$AzSKContext.Source = $settings.LAWSource
			}
			else
			{
				$AzSKContext.Source = [LogAnalyticsOutput]::DefaultLAWSource
			}
			$AzSKContext.PolicyOrgName =  [ConfigurationManager]::GetAzSKConfigData().PolicyOrgName

				return $AzSKContext
		}

	hidden [void] CommandAction($event,$eventName)
	{
		$arg = $event.SourceArgs | Select-Object -First 1;	
		
		$commandModel = [CommandModel]::new() 
		$commandModel.EventName = $eventName
		$commandModel.RunIdentifier = $this.RunIdentifier
		$commandModel.ModuleVersion= $this.GetCurrentModuleVersion();
		$commandModel.ModuleName = $this.GetModuleName();
		$commandModel.MethodName = $this.InvocationContext.InvocationName;
		$commandModel.Parameters	=$(($this.InvocationContext.BoundParameters | Out-String).TrimEnd())
		
		if([Helpers]::CheckMember($arg,"SubscriptionContext"))
		{
			$commandModel.SubscriptionId = $arg.SubscriptionContext.SubscriptionId
			$commandModel.SubscriptionName =  $arg.SubscriptionContext.SubscriptionName
		}
		if([Helpers]::CheckMember($arg,"PartialScanIdentifier"))
		{
			$commandModel.PartialScanIdentifier = $arg.PartialScanIdentifier
		}
		[LogAnalyticsHelper]::WriteControlResult($commandModel,"AzSK_CommandEvent")
	}
	}

	



