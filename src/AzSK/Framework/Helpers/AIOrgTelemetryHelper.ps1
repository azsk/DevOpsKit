Set-StrictMode -Version Latest

class AIOrgTelemetryHelper {
    static hidden [string[]] $ParamsToMask = @("OMSSharedKey");
    static hidden [Microsoft.ApplicationInsights.TelemetryClient] $OrgTelemetryClient;
    static hidden [Microsoft.ApplicationInsights.TelemetryClient] $UsageTelemetryClient;
	static [PSObject] $CommonProperties;
    static AIOrgTelemetryHelper() {
        [AIOrgTelemetryHelper]::OrgTelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new()
    }

    static [void] TrackEvent([string] $Name) {
        [AIOrgTelemetryHelper]::TrackEvent($Name, $null, $null);
    }

    static [void] TrackEventWithOnlyProperties([string] $Name, [hashtable] $Properties) {
        [AIOrgTelemetryHelper]::TrackEvent($Name, $Properties, $null);
    }

    static [void] TrackEventWithOnlyMetrics([string] $Name, [hashtable] $Metrics) {
        [AIOrgTelemetryHelper]::TrackEvent($Name, $null, $Metrics);
    }

    static [void] TrackEvent([string] $Name, [hashtable] $Properties, [hashtable] $Metrics) {
        if (![RemoteReportHelper]::IsAIOrgTelemetryEnabled()) { return; };
        [AIOrgTelemetryHelper]::TrackEventInternal($Name, $Properties, $Metrics);
        [AIOrgTelemetryHelper]::OrgTelemetryClient.Flush();
    }

    static [void] TrackEvents([System.Collections.ArrayList] $events) {
        #if (![RemoteReportHelper]::IsAIOrgTelemetryEnabled()) { return; };
        #foreach ($item in $events) {
        #    [AIOrgTelemetryHelper]::TrackEventInternal($item.Name, $item.Properties, $item.Metrics);
        #}
        [AIOrgTelemetryHelper]::PublishEvent($events,"AIOrg");
        #[AIOrgTelemetryHelper]::OrgTelemetryClient.Flush();
    }

    static [void] TrackCommandExecution([string] $Name, [hashtable] $Properties, [hashtable] $Metrics, [System.Management.Automation.InvocationInfo] $invocationContext) {
        if (![RemoteReportHelper]::IsAIOrgTelemetryEnabled()) { return; };
        $Properties = [AIOrgTelemetryHelper]::AttachInvocationInfo($Properties, $invocationContext);
        [AIOrgTelemetryHelper]::TrackEventInternal($Name, $Properties, $Metrics);
        [AIOrgTelemetryHelper]::OrgTelemetryClient.Flush();
    }

    static [void] TrackException([System.Management.Automation.ErrorRecord] $ErrorRecord, [System.Management.Automation.InvocationInfo] $InvocationContext) {
        [AIOrgTelemetryHelper]::TrackException($ErrorRecord, $null, $null, $InvocationContext);
    }

    static [void] TrackExceptionWithOnlyProperties([System.Management.Automation.ErrorRecord] $ErrorRecord, [hashtable] $Properties, [System.Management.Automation.InvocationInfo] $InvocationContext) {
        [AIOrgTelemetryHelper]::TrackException($ErrorRecord, $Properties, $null, $InvocationContext);
    }

    static [void] TrackExceptionWithOnlyMetrics([System.Management.Automation.ErrorRecord] $ErrorRecord, [hashtable] $Metrics, [System.Management.Automation.InvocationInfo] $InvocationContext) {
        [AIOrgTelemetryHelper]::TrackException($ErrorRecord, $null, $Metrics, $InvocationContext);
    }

    static [void] TrackException([System.Management.Automation.ErrorRecord] $ErrorRecord, [hashtable] $Properties, [hashtable] $Metrics, [System.Management.Automation.InvocationInfo] $InvocationContext) {
		try {
			if (![RemoteReportHelper]::IsAIOrgTelemetryEnabled()) { return; };
			$Properties = [AIOrgTelemetryHelper]::AttachInvocationInfo($Properties, $InvocationContext);
			$Properties = [AIOrgTelemetryHelper]::AttachCommonProperties($Properties);
			$Metrics = [AIOrgTelemetryHelper]::AttachCommonMetrics($Metrics);
			$ex = [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry]::new()
			$ex.Exception = $ErrorRecord.Exception
			try{
				$ex.Properties.Add("ScriptStackTrace", $ErrorRecord.ScriptStackTrace)
			}
			catch{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
			$Properties.Keys | ForEach-Object {
				try{
					$ex.Properties.Add($_, $Properties[$_].ToString());
				}
				catch{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
			}
			$Metrics.Keys | ForEach-Object {
				try{
					$ex.Metrics.Add($_, $Metrics[$_]);
				}
				catch{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
			}
			[AIOrgTelemetryHelper]::OrgTelemetryClient.InstrumentationKey = [RemoteReportHelper]::GetAIOrgTelemetryKey();
			[AIOrgTelemetryHelper]::OrgTelemetryClient.TrackException($ex);
			[AIOrgTelemetryHelper]::OrgTelemetryClient.Flush();
		}
		catch{
				# Eat the current exception which typically happens when network or other API issue while sending telemetry events 
				# No need to break execution
		}
    }


    hidden static [void] TrackEventInternal([string] $Name, [hashtable] $Properties, [hashtable] $Metrics) {
        $Properties = [AIOrgTelemetryHelper]::AttachCommonProperties($Properties);
        $Metrics = [AIOrgTelemetryHelper]::AttachCommonMetrics($Metrics);
        try {
            $event = [Microsoft.ApplicationInsights.DataContracts.EventTelemetry]::new()
            $event.Name = $Name
            $Properties.Keys | ForEach-Object {
                try {
                    $event.Properties.Add($_, ($Properties[$_].ToString()));
                }
                catch
				{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
            }
            $Metrics.Keys | ForEach-Object {
                try {
                    $event.Metrics.Add($_, $Metrics[$_]);
                }
                catch
				{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
            }
            [AIOrgTelemetryHelper]::OrgTelemetryClient.InstrumentationKey = [RemoteReportHelper]::GetAIOrgTelemetryKey();
            [AIOrgTelemetryHelper]::OrgTelemetryClient.TrackEvent($event);
        }
        catch{
				# Eat the current exception which typically happens when network or other API issue while sending telemetry events 
				# No need to break execution
		}
    }

    hidden static [hashtable] AttachCommonProperties([hashtable] $Properties) {
        if ($null -eq $Properties) {
            $Properties = @{}
        }
        else {
            $Properties = $Properties.Clone()
        }
        try {
            $NA = "NA";
            try {
                $Properties.Add("ScanSource", [RemoteReportHelper]::GetScanSource());
            }
            catch
			{
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
            try {
                $module = Get-Module 'AzSK*' | Select-Object -First 1
                $Properties.Add("ScannerModuleName", $module.Name);
                $Properties.Add("ScannerVersion", $module.Version.ToString());
            }
            catch
			{
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
            try 
			{
                $azureContext = [Helpers]::GetCurrentRMContext()
                try 
				{
                    $Properties.Add([TelemetryKeys]::SubscriptionId, $azureContext.Subscription.Id)
                }
                catch
				{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
                try 
				{
                    $Properties.Add([TelemetryKeys]::SubscriptionName, $azureContext.Subscription.Name)
                }
                catch
				{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
                try 
				{
                    $Properties.Add("AzureEnv", $azureContext.Environment.Name)
                }
                catch
				{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
                try 
				{
                    $Properties.Add("TenantId", $azureContext.Tenant.Id)
                }
                catch
				{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
                try 
				{
                    $Properties.Add("AccountId", $azureContext.Account.Id)
                }
                catch
				{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
                try 
				{
                    if ($Properties.ContainsKey("RunIdentifier")) {
                        $actualRunId = $Properties["RunIdentifier"]
                        $Properties["UniqueRunIdentifier"] = [RemoteReportHelper]::Mask($azureContext.Account.Id + '##' + $actualRunId.ToString())
                    }
                }
                catch
				{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
                try 
				{
                    $Properties.Add("AccountType", $azureContext.Account.Type);
                }
                catch
				{
					# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
					# No need to break execution
				}
            }
            catch
			{
				# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
				# No need to break execution
			}
        }
        catch 
		{
			# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
			# No need to break execution
        }
        return $Properties;
    }

    hidden static [hashtable] AttachCommonMetrics([hashtable] $Metrics) {
        if ($null -eq $Metrics) {
            $Metrics = @{}
        }
        else {
            $Metrics = $Metrics.Clone()
        }
        return $Metrics;
    }

    hidden static [hashtable] AttachInvocationInfo([hashtable] $Properties, [System.Management.Automation.InvocationInfo] $invocationContext) {
        if ($null -eq $Properties) {
            $Properties = @{}
        }
        else {
            $Properties = $Properties.Clone()
        }
        if ($null -eq $invocationContext) { return $Properties};
        $Properties.Add("Command", $invocationContext.MyCommand.Name)
        $params = @{}
        $invocationContext.BoundParameters.Keys | ForEach-Object {
            $value = "MASKED"
            if (![AIOrgTelemetryHelper]::ParamsToMask.Contains($_)) {
                $value = $invocationContext.BoundParameters[$_].ToString()
            }
            $Properties.Add("Param" + $_, $value)
            $params.Add("$_", $value)
        }
        $Properties.Add("Params", [Helpers]::ConvertToJsonCustomCompressed($params))
        $loadedModules = Get-Module | ForEach-Object { $_.Name + "=" + $_.Version.ToString()}
        $Properties.Add("LoadedModules" , ($loadedModules -join ';'))
        return $Properties;
    }

	static [void] PublishEvent([string] $EventName, [hashtable] $Properties, [hashtable] $Metrics) {
		try {
			#return if telemetry key is empty
			$telemetryKey= [RemoteReportHelper]::GetAIOrgTelemetryKey()
			if ([string]::IsNullOrWhiteSpace($telemetryKey)) { return; };
			$eventObj = [AIOrgTelemetryHelper]::GetEventBaseObject($EventName)
			$eventObj=[AIOrgTelemetryHelper]::SetCommonProperties($eventObj)

			if ($null -ne $Properties) {
				$Properties.Keys | ForEach-Object {
					try {
						if (!$eventObj.data.baseData.properties.ContainsKey($_)) {
							$eventObj.data.baseData.properties.Add($_ , $Properties[$_].ToString())
						}
					}
					catch
					{
						# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
						# No need to break execution
					}
				}
			}
			if ($null -ne $Metrics) {
				$Metrics.Keys | ForEach-Object {
					try {
						$metric = $Metrics[$_] -as [double]
						if (!$eventObj.data.baseData.measurements.ContainsKey($_) -and $null -ne $metric) {
							$eventObj.data.baseData.measurements.Add($_ , $Metrics[$_])
						}
					}
					catch 
					{
						# Eat the current exception which typically happens when the property already exist in the object and try to add the same property again
						# No need to break execution
					}
				}
			}

			$eventJson = ConvertTo-Json $eventObj -Depth 100 -Compress

			Invoke-WebRequest -Uri "https://dc.services.visualstudio.com/v2/track" `
				-Method Post `
				-ContentType "application/x-json-stream" `
				-Body $eventJson `
				-UseBasicParsing | Out-Null
		}
		catch {
			# Eat the current exception which typically happens when network or other API issue while sending telemetry events 
			# No need to break execution
		}
	}

	static [void] PublishARMCheckerEvent([string] $EventName, [hashtable] $Properties, [hashtable] $Metrics) {
		try {
		   $armcheckerscantelemetryEvents = [System.Collections.ArrayList]::new()
		   $telemetryEvent = "" | Select-Object Name, Properties, Metrics
		   $telemetryEvent.Name =  $EventName
	       $telemetryEvent.Properties = $Properties
		   $telemetryEvent.Metrics = $Metrics
		   $armcheckerscantelemetryEvents.Add($telemetryEvent)
		   [AIOrgTelemetryHelper]::PublishARMCheckerEvent($armcheckerscantelemetryEvents);   
		}
		catch {
	     # Left blank intentionally
		 # Error while sending events to telemetry. No need to break the execution.
		}
	}
	static [void] PublishARMCheckerEvent([System.Collections.ArrayList] $armcheckerscantelemetryEvents) {  
	try
	{
	 #Attach Common Properties to each EventObject
	 $armcheckerscantelemetryEvents | ForEach-Object -Begin{
	 $module = Get-Module 'AzSK*' | Select-Object -First 1
	 } -Process {
	            $_.Properties.Add("ScannerModuleName", $module.Name);
                $_.Properties.Add("ScannerVersion", $module.Version.ToString());
				$_.Properties.Add("Command","Get-AzSKARMChecker")
	 } -End {}

	 [AIOrgTelemetryHelper]::PublishEvent($armcheckerscantelemetryEvents,"Usage");
   }
   catch{
    # Left blank intentionally
    # Error while sending events to telemetry. No need to break the execution.
   }

}

    static [PSObject] GetEventBaseObject([string] $EventName) {
	$telemetryKey= [RemoteReportHelper]::GetAIOrgTelemetryKey()
    $eventObj = "" | Select-Object data, iKey, name, tags, time
    $eventObj.iKey = $telemetryKey
    $eventObj.name = "Microsoft.ApplicationInsights." + $telemetryKey.Replace("-", "") + ".Event"
    $eventObj.time = [datetime]::UtcNow.ToString("o")

    $eventObj.tags = "" | Select-Object ai.internal.sdkVersion
    $eventObj.tags.'ai.internal.sdkVersion' = "dotnet: 2.1.0.26048"

    $eventObj.data = "" | Select-Object baseData, baseType
    $eventObj.data.baseType = "EventData"
    $eventObj.data.baseData = "" | Select-Object ver, name, measurements, properties

    $eventObj.data.baseData.ver = 2
    $eventObj.data.baseData.name = $EventName

    $eventObj.data.baseData.measurements = New-Object 'system.collections.generic.dictionary[string,double]'
    $eventObj.data.baseData.properties = New-Object 'system.collections.generic.dictionary[string,string]'

    return $eventObj;
	}

	#Telemetry functions -- start here
  static [PSObject]  SetCommonProperties([psobject] $EventObj) {
    $notAvailable = "NA"
    if([AIOrgTelemetryHelper]::CommonProperties)
	 {	
		try{
		$EventObj.data.baseData.properties.Add("SubscriptionId",[AIOrgTelemetryHelper]::CommonProperties.SubscriptionId)
		$EventObj.data.baseData.properties.Add("SubscriptionName",[AIOrgTelemetryHelper]::CommonProperties.SubscriptionName)		
		$azureContext = [Helpers]::GetCurrentRMContext()
		$EventObj.data.baseData.properties.Add("TenantId", $azureContext.Tenant.Id)
		$EventObj.data.baseData.properties.Add("AccountId", $azureContext.Account.Id)
		}
		catch{
			# Eat the current exception which typically happens to avoid any break in event push
			# No need to break execution
		}
	 }
	  return $EventObj
}

	static [PSObject] GetUsageEventBaseObject([string] $EventName,[string] $type) {
		$eventObj = "" | Select-Object data, iKey, name, tags, time
        if($type -eq "Usage")
        {
            $eventObj.iKey = [Constants]::UsageTelemetryKey
        }
        else
        {
            $eventObj.iKey = [RemoteReportHelper]::GetAIOrgTelemetryKey()
        }
		$eventObj.name = $EventName
		$eventObj.time = [datetime]::UtcNow.ToString("o")

		$eventObj.tags = "" | Select-Object ai.internal.sdkVersion
		$eventObj.tags.'ai.internal.sdkVersion' = "dotnet: 2.1.0.26048"

		$eventObj.data = "" | Select-Object baseData, baseType
		$eventObj.data.baseType = "EventData"
		$eventObj.data.baseData = "" | Select-Object ver, name, measurements, properties

		$eventObj.data.baseData.ver = 2
		$eventObj.data.baseData.name = $EventName

		$eventObj.data.baseData.measurements = New-Object 'system.collections.generic.dictionary[string,double]'
		$eventObj.data.baseData.properties = New-Object 'system.collections.generic.dictionary[string,string]'

		return $eventObj;
}

	
static [void] PublishEvent([System.Collections.ArrayList] $servicescantelemetryEvents,[string] $type) {
    try {

        $eventlist = [System.Collections.ArrayList]::new()

        $servicescantelemetryEvents | ForEach-Object {
        
        $eventObj = [AIOrgTelemetryHelper]::GetUsageEventBaseObject($_.Name,$type)
        #SetCommonProperties -EventObj $eventObj

        $currenteventobj = $_
        if ($null -ne $currenteventobj.Properties) {
            $currenteventobj.Properties.Keys | ForEach-Object {
                try {
                    if (!$eventObj.data.baseData.properties.ContainsKey($_)) {
                        $eventObj.data.baseData.properties.Add($_ , $currenteventobj.Properties[$_].ToString())
                    }
                }
                catch
				{
					# Left blank intentionally
					# Error while sending CA events to telemetry. No need to break the execution.
				}
            }
        }
        if ($null -ne $currenteventobj.Metrics) {
            $currenteventobj.Metrics.Keys | ForEach-Object {
                try {
                    $metric = $currenteventobj.Metrics[$_] -as [double]
                    if (!$eventObj.data.baseData.measurements.ContainsKey($_) -and $null -ne $metric) {
                        $eventObj.data.baseData.measurements.Add($_ , $currenteventobj.Metrics[$_])
                    }
                }
                catch {
					# Left blank intentionally
					# Error while sending CA events to telemetry. No need to break the execution.
				}
            }
        }
        
        $eventlist.Add($eventObj)
        
        }

        $eventJson = ConvertTo-Json $eventlist -Depth 100 -Compress

        Invoke-WebRequest -Uri "https://dc.services.visualstudio.com/v2/track" `
            -Method Post `
            -ContentType "application/x-json-stream" `
            -Body $eventJson `
            -UseBasicParsing | Out-Null
    }
    catch {
		# Left blank intentionally
		# Error while sending CA events to telemetry. No need to break the execution.
    }
}

}
