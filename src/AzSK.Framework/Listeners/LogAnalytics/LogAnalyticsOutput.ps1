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
					[LogAnalyticsHelper]::SetLAWSDetails();
					$settings = [ConfigurationManager]::GetAzSKSettings()
					
					if((-not [string]::IsNullOrEmpty($settings.LAWSId)) -or (-not [string]::IsNullOrEmpty($settings.AltLAWSId)))
					{
						$currentInstance.PublishCustomMessage("Scan events will be sent to the following Log Analytics workspace(s):",[MessageType]::Info);

						if(-not [string]::IsNullOrEmpty($settings.LAWSId))
						{						
							$currentInstance.PublishCustomMessage("WSId: $($settings.LAWSId)`n",[MessageType]::Info);
						}
						
						if(-not [string]::IsNullOrEmpty($settings.AltLAWSId))
						{
							$currentInstance.PublishCustomMessage("AltWSId: $($settings.AltLAWSId)`n",[MessageType]::Info);
							$currentInstance.PublishCustomMessage("`n");
						}
						else
						{
							$currentInstance.PublishCustomMessage("`n");
						}
					}
					else
					{
						$currentInstance.PublishCustomMessage("Scan events are currently not being sent to a Log Analytics workspace. To set one up refer: https://aka.ms/devopskit/setuplaws `n",[MessageType]::Warning);						
					}
					
					$currentInstance.CommandAction($Event,"Command Started");
				}
				catch{
					$currentInstance.PublishException($_);
				}
				
				#TODO: Disabling OMS inventory call. Need to rework on performance part.
				# if(-not ([LogAnalyticsHelper]::IsLAWSSettingValid -eq -1 -and [LogAnalyticsHelper]::IsAltLAWSSettingValid -eq -1))
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

			$this.RegisterEvent([SVTEvent]::PostCredHygiene, {
                $currentInstance = [LogAnalyticsOutput]::GetInstance();
                try
                {
                    $invocationContext = [System.Management.Automation.InvocationInfo] $currentInstance.InvocationContext
                    $credentialInfo = $Event.SourceArgs;
                    [LogAnalyticsHelper]::WriteControlResult( $credentialInfo, "AzSK_CredHygiene");
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
			# 		[LogAnalyticsHelper]::SetLAWSDetails();
			# 		if(-not ([LogAnalyticsHelper]::IsLAWSSettingValid -eq -1 -and [LogAnalyticsHelper]::IsAltLAWSSettingValid -eq -1))
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
                
				if((-not [string]::IsNullOrWhiteSpace($settings.LAWSId)) -or (-not [string]::IsNullOrWhiteSpace($settings.AltLAWSId)))
				{
					$eventContextAll | ForEach-Object{
					$eventContext = $_
						$tempBodyObjects = [LogAnalyticsHelper]::GetLAWSBodyObjects($eventContext,$this.GetAzSKContextDetails())
                    
						$tempBodyObjects | ForEach-Object{
							Set-Variable -Name tempBody -Value $_ -Scope Local
							$tempBodyObjectsAll.Add($tempBody)
						}
					}
					# Send data to Log analytics only if content to post is not null
					# Added if block to avoid exception for cases where ControlResult is null
					if($tempBodyObjectsAll -ne $null)
					{
						$body = $tempBodyObjectsAll | ConvertTo-Json
						$lawBodyByteArray = ([System.Text.Encoding]::UTF8.GetBytes($body))

						#publish to primary workspace
						if(-not [string]::IsNullOrWhiteSpace($settings.LAWSId) -and [LogAnalyticsHelper]::IsLAWSSettingValid -ne -1)
						{
							[LogAnalyticsHelper]::PostLAWSData($settings.LAWSId, $settings.LAWSSharedKey, $lawBodyByteArray, $settings.LAType, 'LAWS')
						}

						#publish to secondary workspace
						if(-not [string]::IsNullOrWhiteSpace($settings.AltLAWSId) -and [LogAnalyticsHelper]::IsAltLAWSSettingValid -ne -1)
						{
							[LogAnalyticsHelper]::PostLAWSData($settings.AltLAWSId, $settings.AltLAWSSharedKey, $lawBodyByteArray, $settings.LAType, 'AltLAWS')
						}
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

			if(-not [string]::IsNullOrWhiteSpace($settings.LASource))
			{
				$AzSKContext.Source = $settings.LASource
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

	



