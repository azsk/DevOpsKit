Set-StrictMode -Version Latest 

class OMSOutput: ListenerBase
{		
	hidden static [OMSOutput] $Instance = $null;  
	#Default source is kept as SDL / PowerShell. 
	static [string] $DefaultOMSSource = "SDL"
	#This value must be set in respective environment i.e. CICD,CA   
	hidden static [bool] $IsIssueLogged = $false
	OMSOutput()
	{
		[OMSHelper]::SetOMSDetails()
	}

	static [OMSOutput] GetInstance()
	{
		if($null -eq [OMSOutput]::Instance)
		{
			[OMSOutput]::Instance = [OMSOutput]::new();
		}
		return [OMSOutput]::Instance;
	}

	[void] RegisterEvents()
	{
		if(!([OMSHelper]::isOMSSettingValid -eq -1 -and [OMSHelper]::isAltOMSSettingValid -eq -1))
		{
			$this.UnregisterEvents();

			# Mandatory: Generate Run Identifier Event
			$this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
				$currentInstance = [OMSOutput]::GetInstance();
				try 
				{
				    $currentInstance.SetRunIdentifier([AzSKRootEventArgument] ($Event.SourceArgs | Select-Object -First 1));                         
					[OMSOutput]::IsIssueLogged = $false
				}
				catch 
				{
				    $currentInstance.PublishException($_);
				}
			});	
			
			$this.RegisterEvent([SVTEvent]::CommandStarted, {
				$currentInstance = [OMSOutput]::GetInstance();
				try 
				{
					[OMSHelper]::SetOMSDetails();
					$currentInstance.CommandAction($Event,"Command Started");
				}
				catch{
					$currentInstance.PublishException($_);
				}
				
				#TODO: Disabling OMS inventory call. Need to rework on performance part.
				# if(-not ([OMSHelper]::isOMSSettingValid -eq -1 -and [OMSHelper]::isAltOMSSettingValid -eq -1))
				# {
				# 	try
				# 	{
				# 		$invocationContext = [System.Management.Automation.InvocationInfo] $currentInstance.InvocationContext
				# 		if(!$invocationContext.BoundParameters.ContainsKey("SubscriptionId")) {return;}
				# 		[OMSHelper]::PostResourceInventory($currentInstance.GetAzSKContextDetails())
				# 	}
				# 	catch
				# 	{
				# 		$currentInstance.PublishException($_);
				# 	}
				# }
			});


			$this.RegisterEvent([AzSKRootEvent]::CommandStarted, {
				$currentInstance = [OMSOutput]::GetInstance();
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
				$currentInstance = [OMSOutput]::GetInstance();
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
				$currentInstance = [OMSOutput]::GetInstance();
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
				$currentInstance = [OMSOutput]::GetInstance();
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
			# 	$currentInstance = [OMSOutput]::GetInstance();
			# 	try
			# 	{
			# 		[OMSHelper]::SetOMSDetails();
			# 		if(-not ([OMSHelper]::isOMSSettingValid -eq -1 -and [OMSHelper]::isAltOMSSettingValid -eq -1))
			# 		{
			# 			$invocationContext = [System.Management.Automation.InvocationInfo] $currentInstance.InvocationContext
			# 			$SVTEventContexts = [SVTEventContext[]] $Event.SourceArgs
						
			# 			[OMSHelper]::PostApplicableControlSet($SVTEventContexts,$currentInstance.GetAzSKContextDetails());
			# 		}
			# 	}
			# 	catch
			# 	{
			# 		$currentInstance.PublishException($_);
			# 	}
			# });
		}
	}

	hidden [void] WriteControlResult([SVTEventContext[]] $eventContextAll)
	{
		try
		{
			$settings = [ConfigurationManager]::GetAzSKSettings()
			$tempBodyObjectsAll = [System.Collections.ArrayList]::new()

            try{
                
				if((-not [string]::IsNullOrWhiteSpace($settings.OMSWorkspaceId)) -or (-not [string]::IsNullOrWhiteSpace($settings.AltOMSWorkspaceId)))
				{
					$eventContextAll | ForEach-Object{
					$eventContext = $_
						$tempBodyObjects = [OMSHelper]::GetOMSBodyObjects($eventContext,$this.GetAzSKContextDetails())
                    
						$tempBodyObjects | ForEach-Object{
							Set-Variable -Name tempBody -Value $_ -Scope Local
							$tempBodyObjectsAll.Add($tempBody)
						}
					}
					
					$body = $tempBodyObjectsAll | ConvertTo-Json
					$omsBodyByteArray = ([System.Text.Encoding]::UTF8.GetBytes($body))

					#publish to primary workspace
					if(-not [string]::IsNullOrWhiteSpace($settings.OMSWorkspaceId) -and [OMSHelper]::isOMSSettingValid -ne -1)
					{
						[OMSHelper]::PostOMSData($settings.OMSWorkspaceId, $settings.OMSSharedKey, $omsBodyByteArray, $settings.OMSType, 'OMS')
					}

					#publish to secondary workspace
					if(-not [string]::IsNullOrWhiteSpace($settings.AltOMSWorkspaceId) -and [OMSHelper]::isAltOMSSettingValid -ne -1)
					{
						[OMSHelper]::PostOMSData($settings.AltOMSWorkspaceId, $settings.AltOMSSharedKey, $omsBodyByteArray, $settings.OMSType, 'AltOMS')
					}
				}

                
			}
			catch
			{
				if(-not [OMSOutput]::IsIssueLogged)
				{
					$this.PublishCustomMessage("An error occurred while pushing data to OMS. Please check logs for more details. AzSK control evaluation results will not be sent to the configured OMS workspace from this environment until the error is resolved.", [MessageType]::Warning);
					$this.PublishException($_);
					[OMSOutput]::IsIssueLogged = $true
				}
			}
		}
		catch
		{
			[Exception] $ex = [Exception]::new("Error sending events to OMS. The following exception occurred: `r`n$($_.Exception.Message) `r`nFor more on AzSK OMS setup, refer: https://aka.ms/devopskit/ca", $_.Exception)
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

			if(-not [string]::IsNullOrWhiteSpace($settings.OMSSource))
			{
				$AzSKContext.Source = $settings.OMSSource
			}
			else
			{
				$AzSKContext.Source = [OMSOutput]::DefaultOMSSource
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
		[OMSHelper]::WriteControlResult($commandModel,"AzSK_CommandEvent")
	}
	}

	



