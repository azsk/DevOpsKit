Set-StrictMode -Version Latest

class UsageTelemetry: ListenerBase {
	[Microsoft.ApplicationInsights.TelemetryClient] $TelemetryClient;

    hidden UsageTelemetry() {
		$this.TelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new()
		$this.TelemetryClient.InstrumentationKey = [Constants]::UsageTelemetryKey
    }

    hidden static [UsageTelemetry] $Instance = $null;

    static [UsageTelemetry] GetInstance() {
        if ( $null  -eq [UsageTelemetry]::Instance -or  $null  -eq [UsageTelemetry]::Instance.TelemetryClient) {
            [UsageTelemetry]::Instance = [UsageTelemetry]::new();
        }
        return [UsageTelemetry]::Instance
    }

    [void] RegisterEvents() {
        $this.UnregisterEvents();		
        $this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
            $currentInstance = [UsageTelemetry]::GetInstance();
            try
            {
				$runIdentifier = [AzSKRootEventArgument] ($Event.SourceArgs | Select-Object -First 1)
                $currentInstance.SetRunIdentifier($runIdentifier);
            }
            catch
            {
                $currentInstance.PublishException($_);
            }
        });

		$this.RegisterEvent([SVTEvent]::EvaluationCompleted, {
			if(-not [UsageTelemetry]::IsAnonymousTelemetryActive()) { return; }
			$currentInstance = [UsageTelemetry]::GetInstance();
			try
			{
				$invocationContext = [System.Management.Automation.InvocationInfo] $currentInstance.InvocationContext
				$SVTEventContexts = [SVTEventContext[]] $Event.SourceArgs
				$featureGroup = [RemoteReportHelper]::GetFeatureGroup($SVTEventContexts)
				if($featureGroup -eq [FeatureGroup]::Subscription){
					[UsageTelemetry]::PushSubscriptionScanResults($currentInstance, $SVTEventContexts)
				}elseif($featureGroup -eq [FeatureGroup]::Service){
					[UsageTelemetry]::PushServiceScanResults($currentInstance, $SVTEventContexts)
				}else{

				}
			}
			catch
			{
				$currentInstance.PublishException($_);
			}
			$currentInstance.TelemetryClient.Flush()
		});

		$this.RegisterEvent([AzSKGenericEvent]::Exception, {
			if(-not [UsageTelemetry]::IsAnonymousTelemetryActive()) { return; }
            $currentInstance = [UsageTelemetry]::GetInstance();
            try
            {
				[System.Management.Automation.ErrorRecord] $er = ($Event.SourceArgs | Select-Object -First 1)	

				[UsageTelemetry]::PushException($currentInstance, @{}, @{}, $er);
            }
            catch
            {
				# Handling error while registration of Exception event.
				# No need to break execution
            }
        });

		$this.RegisterEvent([AzSKRootEvent]::CommandError, {
			if(-not [UsageTelemetry]::IsAnonymousTelemetryActive()) { return; }
            $currentInstance = [UsageTelemetry]::GetInstance();
            try
            {
				[System.Management.Automation.ErrorRecord] $er = [RemoteReportHelper]::Mask($Event.SourceArgs.ExceptionMessage)
				[UsageTelemetry]::PushException($currentInstance, @{}, @{}, $er);
            }
            catch
            {
				# Handling error while registration of CommandError event at AzSKRoot.
				# No need to break execution
            }
        });

		$this.RegisterEvent([SVTEvent]::CommandError, {
			if(-not [UsageTelemetry]::IsAnonymousTelemetryActive()) { return; }
            $currentInstance = [UsageTelemetry]::GetInstance();
            try
            {
				[System.Management.Automation.ErrorRecord] $er = [RemoteReportHelper]::Mask($Event.SourceArgs.ExceptionMessage)
				[UsageTelemetry]::PushException($currentInstance, @{}, @{}, $er);
            }
            catch
            {
				# Handling error while registration of CommandError event at SVT.
				# No need to break execution
            }
        });

		$this.RegisterEvent([SVTEvent]::EvaluationError, {
			if(-not [UsageTelemetry]::IsAnonymousTelemetryActive()) { return; }
            $currentInstance = [UsageTelemetry]::GetInstance();
            try
            {
				[System.Management.Automation.ErrorRecord] $er = [RemoteReportHelper]::Mask($Event.SourceArgs.ExceptionMessage)
				[UsageTelemetry]::PushException($currentInstance, @{}, @{}, $er);
            }
            catch
            {
				# Handling error while registration of EvaluationError event at SVT.
				# No need to break execution
            }
        });

		$this.RegisterEvent([SVTEvent]::ControlError, {
			if(-not [UsageTelemetry]::IsAnonymousTelemetryActive()) { return; }
            $currentInstance = [UsageTelemetry]::GetInstance();
            try
            {
				[System.Management.Automation.ErrorRecord] $er = [RemoteReportHelper]::Mask($Event.SourceArgs.ExceptionMessage)
				[UsageTelemetry]::PushException($currentInstance, @{}, @{}, $er);
            }
            catch
            {
				# Handling error while registration of ControlError event at SVT.
				# No need to break execution
            }
        });

		$this.RegisterEvent([AzSKRootEvent]::PolicyMigrationCommandStarted, {
			if(-not [UsageTelemetry]::IsAnonymousTelemetryActive()) { return; }
            $currentInstance = [UsageTelemetry]::GetInstance();
           	try{
			$Properties = @{			
			"OrgName" = [RemoteReportHelper]::Mask($Event.SourceArgs[0]);			
		}
			[UsageTelemetry]::SetCommonProperties($currentInstance, $Properties);
			$event = [Microsoft.ApplicationInsights.DataContracts.EventTelemetry]::new()
			$event.Name = "Policy Migration Started"
			$Properties.Keys | ForEach-Object {
				try{
					$event.Properties.Add($_, $Properties[$_].ToString());
				}
				catch{
					#Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					#No need to break execution
				}
			}			
			$currentInstance.TelemetryClient.TrackEvent($event);
		}
		catch{
		}
        });

		$this.RegisterEvent([AzSKRootEvent]::PolicyMigrationCommandCompleted, {
			if(-not [UsageTelemetry]::IsAnonymousTelemetryActive()) { return; }
            $currentInstance = [UsageTelemetry]::GetInstance();
           	try{
			$Properties = @{			
			"OrgName" = [RemoteReportHelper]::Mask($Event.SourceArgs[0]);			
			}
			[UsageTelemetry]::SetCommonProperties($currentInstance, $Properties);
			$event = [Microsoft.ApplicationInsights.DataContracts.EventTelemetry]::new()
			$event.Name = "Policy Migration Completed"
			$Properties.Keys | ForEach-Object {
				try{
					$event.Properties.Add($_, $Properties[$_].ToString());
				}
				catch{
				}
			}			
			$currentInstance.TelemetryClient.TrackEvent($event);
		}
		catch{
		}
        });
    }

	static [bool] IsAnonymousTelemetryActive()
	{
		$azskSettings = [ConfigurationManager]::GetAzSKSettings();
		if($azskSettings.UsageTelemetryLevel -eq "anonymous") { return $true; }
		else
		{
			return $false;
		}
	}

	static [void] PushSubscriptionScanResults(
		[UsageTelemetry] $Publisher, `
		[SVTEventContext[]] $SVTEventContexts)
	{
		$eventData = @{
			[TelemetryKeys]::FeatureGroup = [FeatureGroup]::Subscription;
			"ScanKind" = [RemoteReportHelper]::GetSubscriptionScanKind(
				$Publisher.InvocationContext.MyCommand.Name,
				$Publisher.InvocationContext.BoundParameters);
		}
        $subscriptionscantelemetryEvents = [System.Collections.ArrayList]::new()

		$SVTEventContexts | ForEach-Object {
			$context = $_
			[hashtable] $eventDataClone = $eventData.Clone();
			$eventDataClone.Add("ControlIntId", $context.ControlItem.Id);
			$eventDataClone.Add("ControlId", $context.ControlItem.ControlID);
			$eventDataClone.Add("ControlSeverity", $context.ControlItem.ControlSeverity);
			if ($context.ControlItem.Enabled) {
				$eventDataClone.Add("ActualVerificationResult", $context.ControlResults[0].ActualVerificationResult)
				$eventDataClone.Add("AttestationStatus", $context.ControlResults[0].AttestationStatus)
				$eventDataClone.Add("VerificationResult", $context.ControlResults[0].VerificationResult)
			}
			else {
				$eventDataClone.Add("ActualVerificationResult", [VerificationResult]::Disabled)
				$eventDataClone.Add("AttestationStatus", [AttestationStatus]::None)
				$eventDataClone.Add("VerificationResult", [VerificationResult]::Disabled)
			}
			#[UsageTelemetry]::PushEvent($Publisher, $eventDataClone, @{})
                $telemetryEvent = "" | Select-Object Name, Properties, Metrics
				$telemetryEvent.Name = "Control Scanned"
				$telemetryEvent.Properties = $eventDataClone
				$telemetryEvent = [UsageTelemetry]::SetCommonProperties($telemetryEvent,$Publisher);
				$subscriptionscantelemetryEvents.Add($telemetryEvent)
		}
            [AIOrgTelemetryHelper]::PublishEvent($subscriptionscantelemetryEvents,"Usage")
	}

	static [void] PushServiceScanResults(
		[UsageTelemetry] $Publisher, `
		[SVTEventContext[]] $SVTEventContexts)
	{
		$NA = "NA"
		$SVTEventContextFirst = $SVTEventContexts[0]
		$eventData = @{
			[TelemetryKeys]::FeatureGroup = [FeatureGroup]::Service;
			"ScanKind" = [RemoteReportHelper]::GetServiceScanKind(
				$Publisher.InvocationContext.MyCommand.Name,
				$Publisher.InvocationContext.BoundParameters);
			"Feature" = $SVTEventContextFirst.FeatureName;
			"ResourceGroup" = [RemoteReportHelper]::Mask($SVTEventContextFirst.ResourceContext.ResourceGroupName);
			"ResourceName" = [RemoteReportHelper]::Mask($SVTEventContextFirst.ResourceContext.ResourceName);
			"ResourceId" = [RemoteReportHelper]::Mask($SVTEventContextFirst.ResourceContext.ResourceId);
		}
        $servicescantelemetryEvents = [System.Collections.ArrayList]::new()

		$SVTEventContexts | ForEach-Object {
			$SVTEventContext = $_
			[hashtable] $eventDataClone = $eventData.Clone()
			$eventDataClone.Add("ControlIntId", $SVTEventContext.ControlItem.Id);
			$eventDataClone.Add("ControlId", $SVTEventContext.ControlItem.ControlID);
			$eventDataClone.Add("ControlSeverity", $SVTEventContext.ControlItem.ControlSeverity);
			if (!$SVTEventContext.ControlItem.Enabled) {
				$eventDataClone.Add("ActualVerificationResult", [VerificationResult]::Disabled)
				$eventDataClone.Add("AttestationStatus", [AttestationStatus]::None)
				$eventDataClone.Add("VerificationResult", [VerificationResult]::Disabled)
				#[UsageTelemetry]::PushEvent($Publisher, $eventDataClone, @{})

                $telemetryEvent = "" | Select-Object Name, Properties, Metrics
				$telemetryEvent.Name = "Control Scanned"
				$telemetryEvent.Properties = $eventDataClone
				$telemetryEvent = [UsageTelemetry]::SetCommonProperties($telemetryEvent,$Publisher);
				$servicescantelemetryEvents.Add($telemetryEvent) 

			}
			elseif ($SVTEventContext.ControlResults.Count -eq 1 -and `
				($SVTEventContextFirst.ResourceContext.ResourceName -eq $SVTEventContext.ControlResults[0].ChildResourceName -or `
					[string]::IsNullOrWhiteSpace($SVTEventContext.ControlResults[0].ChildResourceName)))
			{
				$eventDataClone.Add("ActualVerificationResult", $SVTEventContext.ControlResults[0].ActualVerificationResult)
				$eventDataClone.Add("AttestationStatus", $SVTEventContext.ControlResults[0].AttestationStatus)
				$eventDataClone.Add("VerificationResult", $SVTEventContext.ControlResults[0].VerificationResult)
				$eventDataClone.Add("IsNestedResource", 'No')
				$eventDataClone.Add("NestedResourceName", $NA)
				#[UsageTelemetry]::PushEvent($Publisher, $eventDataClone, @{})

                $telemetryEvent = "" | Select-Object Name, Properties, Metrics
				$telemetryEvent.Name = "Control Scanned"
				$telemetryEvent.Properties = $eventDataClone
				$telemetryEvent = [UsageTelemetry]::SetCommonProperties($telemetryEvent,$Publisher);
				$servicescantelemetryEvents.Add($telemetryEvent) 
			}
			elseif ($SVTEventContext.ControlResults.Count -eq 1 -and `
				$SVTEventContextFirst.ResourceContext.ResourceName -ne $SVTEventContext.ControlResults[0].ChildResourceName)
			{
				$eventDataClone.Add("ActualVerificationResult", $SVTEventContext.ControlResults[0].ActualVerificationResult)
				$eventDataClone.Add("AttestationStatus", $SVTEventContext.ControlResults[0].AttestationStatus)
				$eventDataClone.Add("VerificationResult", $SVTEventContext.ControlResults[0].VerificationResult)
				$eventDataClone.Add("IsNestedResource", 'Yes')
				$eventDataClone.Add("NestedResourceName", [RemoteReportHelper]::Mask($SVTEventContext.ControlResults[0].ChildResourceName))
				#[UsageTelemetry]::PushEvent($Publisher, $eventDataClone, @{})

                $telemetryEvent = "" | Select-Object Name, Properties, Metrics
				$telemetryEvent.Name = "Control Scanned"
				$telemetryEvent.Properties = $eventDataClone
				$telemetryEvent = [UsageTelemetry]::SetCommonProperties($telemetryEvent,$Publisher);
				$servicescantelemetryEvents.Add($telemetryEvent) 
			}
			elseif ($SVTEventContext.ControlResults.Count -gt 1)
			{
				$eventDataClone.Add("IsNestedResource", 'Yes')
				$SVTEventContext.ControlResults | Foreach-Object {
					[hashtable] $eventDataCloneL2 = $eventDataClone.Clone()
					$eventDataCloneL2.Add("ActualVerificationResult", $_.ActualVerificationResult)
					$eventDataCloneL2.Add("AttestationStatus", $_.AttestationStatus)
					$eventDataCloneL2.Add("VerificationResult", $_.VerificationResult)
					$eventDataCloneL2.Add("NestedResourceName", [RemoteReportHelper]::Mask($_.ChildResourceName))
					#[UsageTelemetry]::PushEvent($Publisher, $eventDataCloneL2, @{})

                    $telemetryEvent = "" | Select-Object Name, Properties, Metrics
				    $telemetryEvent.Name = "Control Scanned"
				    $telemetryEvent.Properties = $eventDataCloneL2
					$telemetryEvent = [UsageTelemetry]::SetCommonProperties($telemetryEvent,$Publisher);
                    $servicescantelemetryEvents.Add($telemetryEvent) 
				}
			}
		}
        [AIOrgTelemetryHelper]::PublishEvent($servicescantelemetryEvents,"Usage")
	}

	static [void] PushEvent([UsageTelemetry] $Publisher, `
							[hashtable] $Properties, [hashtable] $Metrics)
	{
		try{
			[UsageTelemetry]::SetCommonProperties($Publisher, $Properties);
			$event = [Microsoft.ApplicationInsights.DataContracts.EventTelemetry]::new()
			$event.Name = "Control Scanned"
			$Properties.Keys | ForEach-Object {
				try{
					$event.Properties.Add($_, $Properties[$_].ToString());
				}
				catch{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
			}
			$Metrics.Keys | ForEach-Object {
				try{
					$event.Metrics.Add($_, $Metrics[$_]);
				}
				catch{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
			}
			$Publisher.TelemetryClient.TrackEvent($event);
		}
		catch{
				# Eat the current exception which typically happens when network or other API issue while sending telemetry events 
				# No need to break execution
		}
	}

	static [void] PushException([UsageTelemetry] $Publisher, `
							[hashtable] $Properties, [hashtable] $Metrics, `
							[System.Management.Automation.ErrorRecord] $ErrorRecord)
	{
		try{
			[UsageTelemetry]::SetCommonProperties($Publisher, $Properties);
			$ex = [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry]::new()
			$ex.Exception = [System.Exception]::new( [RemoteReportHelper]::Mask($ErrorRecord.Exception.ToString()))
			try{
				$ex.Properties.Add("ScriptStackTrace", [UsageTelemetry]::AnonScriptStackTrace($ErrorRecord.ScriptStackTrace))
			}
			catch
			{
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
			$Properties.Keys | ForEach-Object {
				try{
					$ex.Properties.Add($_, $Properties[$_].ToString());
				}
				catch
				{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
			}
			$Metrics.Keys | ForEach-Object {
				try{
					$ex.Metrics.Add($_, $Metrics[$_]);
				}
				catch
				{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
			}
			$Publisher.TelemetryClient.TrackException($ex)
			$Publisher.TelemetryClient.Flush()
		}
		catch{
			# Handled exception occurred while publishing exception
			# No need to break execution
		}
	}

	hidden static [void] SetCommonProperties([UsageTelemetry] $Publisher, [hashtable] $Properties)
	{
		try{
			$NA = "NA";
			$Properties.Add("InfoVersion", "V1");
			try{
				$Properties.Add("ScanSource", [RemoteReportHelper]::GetScanSource());
			}
			catch
			{
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
			try{
				$Properties.Add("ScannerVersion", $Publisher.GetCurrentModuleVersion());
			}
			catch
			{
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
			try{
				$Properties.Add("ControlVersion", $Publisher.GetCurrentModuleVersion());
			}
			catch
			{
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
			try{
				$azureContext = [Helpers]::GetCurrentRMContext()
				try{
					$Properties.Add([TelemetryKeys]::SubscriptionId, [RemoteReportHelper]::Mask($azureContext.Subscription.Id))
				}
				catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
				try{
					$Properties.Add([TelemetryKeys]::SubscriptionName, [RemoteReportHelper]::Mask($azureContext.Subscription.Name))
				}
				catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
				try{
					$Properties.Add("AzureEnv", $azureContext.Environment.Name)
				} 
				catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
				try{
					$Properties.Add("TenantId", [RemoteReportHelper]::Mask($azureContext.Tenant.Id))
				}
				catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
				try{
					$Properties.Add("AccountId", [RemoteReportHelper]::Mask($azureContext.Account.Id))
				}
				catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
				try{
					$Properties.Add("RunIdentifier",  [RemoteReportHelper]::Mask($azureContext.Account.Id + '##' + $Publisher.RunIdentifier));
				}
				catch
				{
					$Properties.Add("RunIdentifier",  $Publisher.RunIdentifier);
				}
				try{
					$Properties.Add("AccountType", $azureContext.Account.Type)
				}
				catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
				try{
					$OrgName = [ConfigurationManager]::GetAzSKConfigData().PolicyOrgName
					$Properties.Add("OrgName", [RemoteReportHelper]::Mask($OrgName))
				}
				catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
			}
			catch{
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
		}
		catch{
			# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
			# No need to break execution
		}
	}

	hidden static [string] AnonScriptStackTrace([string] $ScriptStackTrace)
	{
		try{
			$ScriptStackTrace = $ScriptStackTrace.Replace($env:USERNAME, "USERNAME")
			$lines = $ScriptStackTrace.Split([System.Environment]::NewLine, [System.StringSplitOptions]::RemoveEmptyEntries)
			$newLines = $lines | ForEach-Object {
				$line = $_
				$lineSplit = $line.Split(@(", "), [System.StringSplitOptions]::RemoveEmptyEntries);
				if($lineSplit.Count -eq 2){
					$filePath = $lineSplit[1];
					$startMarker = $filePath.IndexOf("AzSK")
					if($startMarker -gt 0){
						$anonFilePath = $filePath.Substring($startMarker, $filePath.Length - $startMarker)
						$newLine = $lineSplit[0] + ", " + $anonFilePath
						$newLine
					}
					else{
						$line
					}
				}
				else{
					$line
				}
			}
			return ($newLines | Out-String)
		}
		catch{
			return $ScriptStackTrace
		}
	}

	static [psobject] SetCommonProperties([psobject] $EventObj,[UsageTelemetry] $Publisher)
	{
		try{
			$NA = "NA";
			$eventObj.properties.Add("InfoVersion", "V1");
			try{
				$eventObj.properties.Add("ScanSource", [RemoteReportHelper]::GetScanSource());
			}
			catch{
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
			try{
				$eventObj.properties.Add("ScannerModuleName", $Publisher.GetModuleName());
			}
			catch{
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
			try{
				$eventObj.properties.Add("ScannerVersion", $Publisher.GetCurrentModuleVersion());
			}
			catch{
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
			try{
				$eventObj.properties.Add("ControlVersion", $Publisher.GetCurrentModuleVersion());
			}
			catch{
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
			try{
				$azureContext = [Helpers]::GetCurrentRMContext()
				try{
					$eventObj.properties.Add([TelemetryKeys]::SubscriptionId, [RemoteReportHelper]::Mask($azureContext.Subscription.Id))
				}
				catch{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
				try{
					$eventObj.properties.Add([TelemetryKeys]::SubscriptionName, [RemoteReportHelper]::Mask($azureContext.Subscription.Name))
				}
				catch{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
				try{
					$eventObj.properties.Add("AzureEnv", $azureContext.Environment.Name)
				}
				catch{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
				try{
					$eventObj.properties.Add("TenantId", [RemoteReportHelper]::Mask($azureContext.Tenant.Id))
				}
				catch{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
				try{
					$eventObj.properties.Add("AccountId", [RemoteReportHelper]::Mask($azureContext.Account.Id))
				}
				catch{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
				try{
					$eventObj.properties.Add("RunIdentifier",  [RemoteReportHelper]::Mask($azureContext.Account.Id + '##' + $Publisher.RunIdentifier));
				}
				catch{
					$eventObj.properties.Add("RunIdentifier",  $Publisher.RunIdentifier);
				}
				try{
					$eventObj.properties.Add("AccountType", $azureContext.Account.Type)
				}
				catch{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
				try{
					$OrgName = [ConfigurationManager]::GetAzSKConfigData().PolicyOrgName
					$eventObj.properties.Add("OrgName", [RemoteReportHelper]::Mask($OrgName))
				}
				catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
			}
			catch{
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
		}
		catch{
			# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
			# No need to break execution
		}

		return $eventObj;
	}

}

