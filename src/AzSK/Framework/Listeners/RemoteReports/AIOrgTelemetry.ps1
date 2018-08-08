Set-StrictMode -Version Latest

class AIOrgTelemetry: ListenerBase {
	[Microsoft.ApplicationInsights.TelemetryClient] $TelemetryClient;

    hidden AIOrgTelemetry() {
		$this.TelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new()
    }

    hidden static [AIOrgTelemetry] $Instance = $null;

    static [AIOrgTelemetry] GetInstance() {
        if ( $null  -eq [AIOrgTelemetry]::Instance -or  $null  -eq [AIOrgTelemetry]::Instance.TelemetryClient) {
            [AIOrgTelemetry]::Instance = [AIOrgTelemetry]::new();
        }
        return [AIOrgTelemetry]::Instance
    }

    [void] RegisterEvents() {
        $this.UnregisterEvents();

        $this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
            $currentInstance = [AIOrgTelemetry]::GetInstance();
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
			$currentInstance = [AIOrgTelemetry]::GetInstance();
			try
			{
				$invocationContext = [System.Management.Automation.InvocationInfo] $currentInstance.InvocationContext
				$SVTEventContexts = [SVTEventContext[]] $Event.SourceArgs
				$featureGroup = [RemoteReportHelper]::GetFeatureGroup($SVTEventContexts)
				if($featureGroup -eq [FeatureGroup]::Subscription){
					$currentInstance.PushSubscriptionScanResults($SVTEventContexts)
				}elseif($featureGroup -eq [FeatureGroup]::Service){
					$currentInstance.PushServiceScanResults($SVTEventContexts)
				}else{
				}
			}
			catch
			{
				$currentInstance.PublishException($_);
			}
		});

		$this.RegisterEvent([AzSKGenericEvent]::Exception, {
            $currentInstance = [AIOrgTelemetry]::GetInstance();
            try
            {
				[System.Management.Automation.ErrorRecord] $er = ($Event.SourceArgs | Select-Object -First 1)
				[AIOrgTelemetryHelper]::TrackException($er, $currentInstance.InvocationContext)
            }
            catch
            {
				# Handling error while registration of Exception event.
				# No need to break execution
            }
        });

		$this.RegisterEvent([AzSKRootEvent]::CommandError, {
            $currentInstance = [AIOrgTelemetry]::GetInstance();
            try
            {
				[System.Management.Automation.ErrorRecord] $er = $Event.SourceArgs.ExceptionMessage
				[AIOrgTelemetryHelper]::TrackException($er, $currentInstance.InvocationContext)
            }
            catch
            {
				# Handling error while registration of CommandError event at AzSKRoot.
				# No need to break execution
            }
        });

		$this.RegisterEvent([SVTEvent]::CommandError, {
            $currentInstance = [AIOrgTelemetry]::GetInstance();
            try
            {
				[System.Management.Automation.ErrorRecord] $er = $Event.SourceArgs.ExceptionMessage
				[AIOrgTelemetryHelper]::TrackException($er, $currentInstance.InvocationContext)
            }
            catch
            {
				# Handling error while registration of CommandError event at SVT.
				# No need to break execution
            }
        });

		$this.RegisterEvent([SVTEvent]::EvaluationError, {
            $currentInstance = [AIOrgTelemetry]::GetInstance();
            try
            {
				[System.Management.Automation.ErrorRecord] $er = $Event.SourceArgs.ExceptionMessage
				[AIOrgTelemetryHelper]::TrackException($er, $currentInstance.InvocationContext)
            }
            catch
            {
				# Handling error while registration of EvaluationError event at SVT.
				# No need to break execution
            }
        });

		$this.RegisterEvent([SVTEvent]::ControlError, {
            $currentInstance = [AIOrgTelemetry]::GetInstance();
            try
            {
				[System.Management.Automation.ErrorRecord] $er = $Event.SourceArgs.ExceptionMessage
				[AIOrgTelemetryHelper]::TrackException($er, $currentInstance.InvocationContext)
            }
            catch
            {
				# Handling error while registration of ControlError event at SVT.
				# No need to break execution
            }
		});
		
		$this.RegisterEvent([SVTEvent]::CommandStarted, {
			$currentInstance = [RemoteReportsListener]::GetInstance();
		   try
		   {
			   $scanSource = [RemoteReportHelper]::GetScanSource();
			   if($scanSource -ne [ScanSource]::Runbook) { return; }
               $SubscriptionId = ([Helpers]::GetCurrentRMContext()).Subscription.Id;
			   $resources= Get-AzureRmResource
			   $telemetryEvents = [System.Collections.ArrayList]::new()
					   foreach($res in $resources){
						   $resourceProperties = @{
						   "Name" = $res.Name;
						   "ResourceId" = $res.ResourceId;
						   "ResourceName" = $res.Name;
						   "ResourceType" = $res.ResourceType;
						   "ResourceGroupName" = $res.ResourceGroupName;
						   "Location" = $res.Location;
						   "SubscriptionId" = $SubscriptionId;
						   "Tags" = [Helpers]::FetchTagsString($res.Tags)
					   }
					   $telemetryEvent = "" | Select-Object Name, Properties, Metrics
					   $telemetryEvent.Name = "Resource Inventory"
					   $telemetryEvent.Properties = $resourceProperties
					   $telemetryEvents.Add($telemetryEvent) | Out-Null			   
					   }
				[AIOrgTelemetryHelper]::TrackEvents($telemetryEvents);

		   }
		   catch{
			$currentInstance.PublishException($_);
		   }
		});
    }

	hidden [void] PushSubscriptionScanResults([SVTEventContext[]] $SVTEventContexts)
	{
		$SVTEventContextFirst = $SVTEventContexts[0]
		$baseProperties = @{
			"RunIdentifier" = $this.RunIdentifier;
			[TelemetryKeys]::FeatureGroup = [FeatureGroup]::Subscription;
			"ScanKind" = [RemoteReportHelper]::GetSubscriptionScanKind(
				$this.InvocationContext.MyCommand.Name,
				$this.InvocationContext.BoundParameters);
			"SubscriptionMetadata" = [Helpers]::ConvertToJsonCustomCompressed($SVTEventContextFirst.SubscriptionContext.SubscriptionMetadata);
		}
		$this.PushControlResults($SVTEventContexts, $baseProperties)
	}

	hidden [void] PushServiceScanResults([SVTEventContext[]] $SVTEventContexts)
	{
		$SVTEventContextFirst = $SVTEventContexts[0]
		$baseProperties = @{
			"RunIdentifier" = $this.RunIdentifier;
			[TelemetryKeys]::FeatureGroup = [FeatureGroup]::Service;
			"ScanKind" = [RemoteReportHelper]::GetServiceScanKind(
				$this.InvocationContext.MyCommand.Name,
				$this.InvocationContext.BoundParameters);
			"Feature" = $SVTEventContextFirst.FeatureName;
			"ResourceGroup" = $SVTEventContextFirst.ResourceContext.ResourceGroupName;
			"ResourceName" = $SVTEventContextFirst.ResourceContext.ResourceName;
			"ResourceId" = $SVTEventContextFirst.ResourceContext.ResourceId;
			"ResourceMetadata" = [Helpers]::ConvertToJsonCustomCompressed($SVTEventContextFirst.ResourceContext.ResourceMetadata);
		}
		$this.PushControlResults($SVTEventContexts, $baseProperties)
	}

	hidden [void] PushControlResults([SVTEventContext[]] $SVTEventContexts, [hashtable] $BaseProperties){
		$telemetryEvents = [System.Collections.ArrayList]::new()
		foreach($context in $SVTEventContexts){
			$propertiesCollection = $this.AttachControlProperties($BaseProperties, $context)
			foreach($properties in $propertiesCollection){
				$telemetryEvent = "" | Select-Object Name, Properties, Metrics
				$telemetryEvent.Name = "Control Scanned"
				$telemetryEvent.Properties = $properties
				$telemetryEvent = [AIOrgTelemetry]::SetCommonProperties($telemetryEvent);
				$telemetryEvents.Add($telemetryEvent) | Out-Null
			}
		}
		[AIOrgTelemetryHelper]::TrackEvents($telemetryEvents);
	}


	hidden [hashtable[]] AttachControlProperties([hashtable] $BaseProperties, [SVTEventContext] $context){
		if($null -eq $context) {return  ([hashtable[]]([System.Collections.ArrayList]::new()))}
		$properties = @{}
		if ($null -ne $BaseProperties) {
            $properties = $BaseProperties.Clone()
        }
		$propertiesArray = [System.Collections.ArrayList]::new()
		$properties.Add("ControlIntId", $context.ControlItem.Id);
		$properties.Add("ControlId", $context.ControlItem.ControlID);
		$properties.Add("ControlSeverity", $context.ControlItem.ControlSeverity);
		$properties.Add("IsBaselineControl", $context.ControlItem.IsBaselineControl)
		if (!$context.ControlItem.Enabled) {
			$properties.Add("VerificationResult", [VerificationResult]::Disabled)
			$properties.Add("AttestationStatus", [AttestationStatus]::None)
			$propertiesArray.Add($properties) | Out-Null
		}else{
			$results = $context.ControlResults			
			if($results.Count -eq 1){
				$properties.Add("HasAttestationWritePermissions", $results[0].CurrentSessionContext.Permissions.HasAttestationWritePermissions)
				$properties.Add("HasAttestationReadPermissions", $results[0].CurrentSessionContext.Permissions.HasAttestationReadPermissions)
				$properties.Add("ActualVerificationResult", $results[0].ActualVerificationResult)
				$properties.Add("AttestationStatus", $results[0].AttestationStatus)
				$properties.Add("VerificationResult", $results[0].VerificationResult)
				$properties.Add("HasRequiredAccess", $results[0].CurrentSessionContext.Permissions.HasRequiredAccess)
				if($null -ne $context.ResourceContext){
					if($context.ResourceContext.ResourceName -eq $results[0].ChildResourceName -or [string]::IsNullOrWhiteSpace($results[0].ChildResourceName)){
						$properties.Add("IsNestedResource", 'No')
						$properties.Add("NestedResourceName", "NA")
					}else{
						$properties.Add("IsNestedResource", 'Yes')
						$properties.Add("NestedResourceName", $results[0].ChildResourceName)
					}
				}
				if(($null -ne $results[0].StateManagement) -and ($null -ne $results[0].StateManagement.AttestedStateData)) {
					$properties.Add("AttestedBy", $results[0].StateManagement.AttestedStateData.AttestedBy)
					$properties.Add("Justification", $results[0].StateManagement.AttestedStateData.Justification)
					$properties.Add("AttestedState", [Helpers]::ConvertToJsonCustomCompressed($results[0].StateManagement.AttestedStateData.DataObject))
					$properties.Add("AttestedDate", ($results[0].StateManagement.AttestedStateData.AttestedDate).Tostring("yyyy_MM_dd_hh_mm"))
					$properties.Add("ExpiryDate",  ([DateTime]$results[0].StateManagement.AttestedStateData.ExpiryDate).Tostring("yyyy_MM_dd_hh_mm"))
				}
				if(($null -ne $results[0].StateManagement) -and ($null -ne $results[0].StateManagement.CurrentStateData)) {
					$properties.Add("CurrentState", [Helpers]::ConvertToJsonCustomCompressed($results[0].StateManagement.CurrentStateData.DataObject))
				}
				$propertiesArray.Add($properties) | Out-Null
			}elseif($results.Count -gt 1){
				$properties.Add("IsNestedResource", 'Yes')
				foreach($result in $results){
					$propertiesIn = $properties.Clone()
					$propertiesIn.Add("ActualVerificationResult", $result.ActualVerificationResult)
					$propertiesIn.Add("AttestationStatus", $result.AttestationStatus)
					$propertiesIn.Add("VerificationResult", $result.VerificationResult)
					$propertiesIn.Add("NestedResourceName", $result.ChildResourceName)
					$propertiesIn.Add("HasRequiredAccess", $result.CurrentSessionContext.Permissions.HasRequiredAccess)
					if(($null -ne $result.StateManagement) -and ($null -ne $result.StateManagement.AttestedStateData)) {
						$propertiesIn.Add("AttestedBy", $result.StateManagement.AttestedStateData.AttestedBy)
						$propertiesIn.Add("Justification", $result.StateManagement.AttestedStateData.Justification)
						$propertiesIn.Add("AttestedState", [Helpers]::ConvertToJsonCustomCompressed($result.StateManagement.AttestedStateData.DataObject))
						$propertiesIn.Add("AttestedDate", ($result.StateManagement.AttestedStateData.AttestedDate).Tostring("yyyy_MM_dd_hh_mm"))
					    $propertiesIn.Add("ExpiryDate", ([DateTime]$result.StateManagement.AttestedStateData.ExpiryDate).Tostring("yyyy_MM_dd_hh_mm"))
					}
					if(($null -ne $result.StateManagement) -and ($null -ne $result.StateManagement.CurrentStateData)) {
						$propertiesIn.Add("CurrentState", [Helpers]::ConvertToJsonCustomCompressed($result.StateManagement.CurrentStateData.DataObject))
					}
					$propertiesArray.Add($propertiesIn) | Out-Null
				}
			}
		}
		$returnObj = [hashtable[]] $propertiesArray
		return $returnObj;
	}

	static [psobject] SetCommonProperties([psobject] $telemetryEvent) 
	{
		try
		{
            $NA = "NA";
            try {
                $telemetryEvent.properties.Add("ScanSource", [RemoteReportHelper]::GetScanSource());
            }
            catch {
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
            try {
                $module = Get-Module 'AzSK*' | Select-Object -First 1
                $telemetryEvent.properties.Add("ScannerModuleName", $module.Name);
				$telemetryEvent.properties.Add("ScannerVersion", $module.Version.ToString());
				$telemetryEvent.properties.Add("OrgVersion", [ConfigurationManager]::GetAzSKConfigData().GetLatestAzSKVersion($module.Name).ToString());	
				$telemetryEvent.properties.Add("PolicyOrgName", [ConfigurationManager]::GetAzSKConfigData().PolicyOrgName)
				$AzSKLatestVersion= [ConfigurationManager]::GetAzSKConfigData().GetAzSKLatestPSGalleryVersion($module.Name)		
				$telemetryEvent.properties.Add("LatestVersion", $AzSKLatestVersion);				
				
            }
            catch {
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
            try {
                $azureContext = [Helpers]::GetCurrentRMContext()
                try {
                    $telemetryEvent.properties.Add([TelemetryKeys]::SubscriptionId, $azureContext.Subscription.Id)
                }
                catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
                try {
                    $telemetryEvent.properties.Add([TelemetryKeys]::SubscriptionName, $azureContext.Subscription.Name)
                }
                catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
                try {
                    $telemetryEvent.properties.Add("AzureEnv", $azureContext.Environment.Name)
                }
                catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
                try {
                    $telemetryEvent.properties.Add("TenantId", $azureContext.Tenant.Id)
                }
                catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
                try {
                    $telemetryEvent.properties.Add("AccountId", $azureContext.Account.Id)
                }
                catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
                try {
                    if ($telemetryEvent.Properties.ContainsKey("RunIdentifier")) {
                        $actualRunId = $telemetryEvent.Properties["RunIdentifier"]
						if ($telemetryEvent.Properties.ContainsKey("UniqueRunIdentifier")) {
							$telemetryEvent.Properties["UniqueRunIdentifier"] = [RemoteReportHelper]::Mask($azureContext.Account.Id + '##' + $actualRunId.ToString())
						}
						else
						{
							$telemetryEvent.properties.Add("UniqueRunIdentifier", [RemoteReportHelper]::Mask($azureContext.Account.Id + '##' + $actualRunId.ToString()))
						}
                    }
                }
                catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
                try {
                    $telemetryEvent.properties.Add("AccountType", $azureContext.Account.Type);
                }
                catch {
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
            }
            catch {
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
            }
        }
        catch {
			# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
			# No need to break execution
        }
        return $telemetryEvent;
	}
}
