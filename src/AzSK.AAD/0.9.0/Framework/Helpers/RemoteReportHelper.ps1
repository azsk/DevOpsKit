Set-StrictMode -Version Latest

#Helper functions used by various listeners that send events remotely (e.g., OMS, AIOrg/Control-Telemetry, User/Anon-Telemetry, RemoteReportsListener, etc.)
class RemoteReportHelper
{
	hidden static [string[]] $IgnoreScanParamList = "DoNotOpenOutputFolder";
	hidden static [string[]] $AllowedServiceScanParamList = "tenantId", "ResourceGroupNames";
	hidden static [string[]] $AllowedSubscriptionScanParamList = "tenantId";
	hidden static [int] $MaxServiceParamCount = [RemoteReportHelper]::IgnoreScanParamList.Count + [RemoteReportHelper]::AllowedServiceScanParamList.Count;
	hidden static [int] $MaxSubscriptionParamCount = [RemoteReportHelper]::IgnoreScanParamList.Count + [RemoteReportHelper]::AllowedSubscriptionScanParamList.Count;

	static [FeatureGroup] GetFeatureGroup([SVTEventContext[]] $SVTEventContexts)
	{
		if(($SVTEventContexts | Measure-Object).Count -eq 0 -or $null -eq $SVTEventContexts[0].FeatureName) {
			return [FeatureGroup]::Unknown
		}
		$feature = $SVTEventContexts[0].FeatureName.ToLower()
		if($feature.Contains("subscription")){
			return [FeatureGroup]::Subscription
		} else{
			return [FeatureGroup]::Service
		}
	}

	static [ServiceScanKind] GetServiceScanKind([string] $command, [hashtable] $parameters)
	{
		$parameterNames = [array] $parameters.Keys
		if($parameterNames.Count -gt [RemoteReportHelper]::MaxServiceParamCount)
		{
			return [ServiceScanKind]::Partial;
		}
		$validParamCounter = 0;
		foreach($parameterName in $parameterNames)
		{
			if ([RemoteReportHelper]::AllowedServiceScanParamList.Contains($parameterName))
			{
				$validParamCounter += 1
			}
			elseif ([RemoteReportHelper]::IgnoreScanParamList.Contains($parameterName))
			{
				# Ignoring
			}
			else
			{
				return [ServiceScanKind]::Partial;
			}
		}

		if ($validParamCounter -eq 1)
		{
			return [ServiceScanKind]::Subscription;
		}
		elseif ($validParamCounter -eq 2)
		{
			return [ServiceScanKind]::ResourceGroup;
		}
		else
		{
			return [ServiceScanKind]::Partial;
		}
	}

	static [SubscriptionScanKind] GetSubscriptionScanKind([string] $command, [hashtable] $parameters)
	{
		$parameterNames = [array] $parameters.Keys
		if($parameterNames.Count -gt [RemoteReportHelper]::MaxSubscriptionParamCount)
		{
			return [SubscriptionScanKind]::Partial;
		}
		$validParamCounter = 0;
		foreach($parameterName in $parameterNames)
		{
			if ([RemoteReportHelper]::AllowedSubscriptionScanParamList.Contains($parameterName))
			{
				$validParamCounter += 1
			}
			elseif ([RemoteReportHelper]::IgnoreScanParamList.Contains($parameterName))
			{
				# Ignoring
			}
			else
			{
				return [SubscriptionScanKind]::Partial;
			}
		}

		if ($validParamCounter -eq 1)
		{
			return [SubscriptionScanKind]::Complete;
		}
		else
		{
			return [SubscriptionScanKind]::Partial;
		}
	}

	static [SubscriptionControlResult] BuildSubscriptionControlResult([ControlResult] $controlResult, [ControlItem] $control)
	{
		$result = [SubscriptionControlResult]::new()
		$result.ControlId = $control.ControlId
		$result.ControlIntId = $control.Id
		$result.ControlSeverity = $control.ControlSeverity
		$result.ActualVerificationResult = $controlResult.ActualVerificationResult
		$result.AttestationStatus = $controlResult.AttestationStatus
		$result.VerificationResult = $controlResult.VerificationResult
		$result.HasRequiredAccess = $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess
		$result.IsBaselineControl = $control.IsBaselineControl
		$result.MaximumAllowedGraceDays = $controlResult.MaximumAllowedGraceDays
		if($control.Tags.Contains("OwnerAccess")  -or $control.Tags.Contains("GraphRead"))
		{
			$result.HasOwnerAccessTag = $true
		}

		$result.UserComments = $controlResult.UserComments

		if($null -ne $controlResult.StateManagement -and $null -ne $controlResult.StateManagement.AttestedStateData) {
			$result.AttestedBy = $controlResult.StateManagement.AttestedStateData.AttestedBy
			$result.Justification = $controlResult.StateManagement.AttestedStateData.Justification
			$result.AttestedState = [Helpers]::ConvertToJsonCustomCompressed($controlResult.StateManagement.AttestedStateData.DataObject)
			$result.AttestedDate = $controlResult.StateManagement.AttestedStateData.AttestedDate

		}
		if($null -ne $controlResult.StateManagement -and $null -ne $controlResult.StateManagement.CurrentStateData) {
			$result.CurrentState = [Helpers]::ConvertToJsonCustomCompressed($controlResult.StateManagement.CurrentStateData.DataObject)
		}
		return $result;
	}

	static [ServiceControlResult] BuildServiceControlResult([ControlResult] $controlResult, [bool] $isNestedResource, [ControlItem] $control)
	{
		$result = [ServiceControlResult]::new()
		$result.IsNestedResource = $isNestedResource
		if ($isNestedResource)
		{
			$result.NestedResourceName = $controlResult.ChildResourceName
		}
		else
		{
			$result.NestedResourceName = $null
		}
		$result.ControlId = $control.ControlID
		$result.ControlIntId = $control.Id
		$result.ControlSeverity = $control.ControlSeverity
		$result.ActualVerificationResult = $controlResult.ActualVerificationResult
		$result.AttestationStatus = $controlResult.AttestationStatus
		$result.VerificationResult = $controlResult.VerificationResult
		$result.HasRequiredAccess = $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess
		$result.IsBaselineControl = $control.IsBaselineControl
		$result.UserComments = $controlResult.UserComments
		$result.MaximumAllowedGraceDays = $controlResult.MaximumAllowedGraceDays
		if($control.Tags.Contains("OwnerAccess")  -or $control.Tags.Contains("GraphRead"))
		{
			$result.HasOwnerAccessTag = $true
		}

		if($null -ne $controlResult.StateManagement -and $null -ne $controlResult.StateManagement.AttestedStateData) {
			$result.AttestedBy = $controlResult.StateManagement.AttestedStateData.AttestedBy
			$result.Justification = $controlResult.StateManagement.AttestedStateData.Justification
			$result.AttestedState = [Helpers]::ConvertToJsonCustomCompressed($controlResult.StateManagement.AttestedStateData.DataObject)
			$result.AttestedDate = $controlResult.StateManagement.AttestedStateData.AttestedDate
		}
		if($null -ne $controlResult.StateManagement -and $null -ne $controlResult.StateManagement.CurrentStateData) {
			$result.CurrentState = [Helpers]::ConvertToJsonCustomCompressed($controlResult.StateManagement.CurrentStateData.DataObject)
		}
		return $result;
	}

	static [ScanSource] GetScanSource()
	{		
		$settings = [ConfigurationManager]::GetAzSKSettings();
		[string] $omsSource = $settings.OMSSource;
		if([string]::IsNullOrWhiteSpace($omsSource)){
			return [ScanSource]::SpotCheck
		}
		if($omsSource.Equals("CICD", [System.StringComparison]::OrdinalIgnoreCase)){
			return [ScanSource]::VSO
		}
		if($omsSource.Equals("CC", [System.StringComparison]::OrdinalIgnoreCase) -or
			$omsSource.Equals("CA", [System.StringComparison]::OrdinalIgnoreCase)){
			return [ScanSource]::Runbook
		}
		return [ScanSource]::SpotCheck
	}

	static [string] GetAIOrgTelemetryKey()
	{
		$settings = [ConfigurationManager]::GetAzSKConfigData();
		$telemetryKey = $settings.ControlTelemetryKey

		#BUGBUG: Need to address same 'perf' concern as AIOrgTMKey below!
		[guid]$key = [guid]::NewGuid() 
		
		if([guid]::TryParse($telemetryKey, [ref] $key) -and ![guid]::Empty.Equals($key))
		{
			return $telemetryKey;
		}
		#BUGBUG: What is the intent here? 
		#BUGBUG: It appears that if telemetryKey in config is 00000- (and no server setting) this will return 0000--...
		#TODO: This should work smoothly if we support locally forwarded OrgTelemetry in OSS mode... 
		return [ConfigurationManager]::GetAzSKSettings().LocalControlTelemetryKey;
	}

	static [bool] IsAIOrgTelemetryEnabled()
	{
		$settings = [ConfigurationManager]::GetAzSKConfigData();
		$telemetryKey = $settings.ControlTelemetryKey
		#BUGBUG: We should not burn a Guid each time like this. Just check non-null and perhaps length...
		#If we need a mock guid, make one up 01234567-89ab-cdef-0123456789abcdef
		#Also, cache the result and the fact that it has been set/checked (upon first call)
		#TODO: Even otherwise, checking bEnabled first is much more optimal. Most people will have it as $false.
		[guid]$key = [guid]::NewGuid()
		if([guid]::TryParse($telemetryKey, [ref] $key) -and ![guid]::Empty.Equals($key))
		{
			return $settings.EnableControlTelemetry;
		} 
		#BUGBUG: Unclear why this would return LocalEnable...
		return [ConfigurationManager]::GetAzSKSettings().LocalEnableControlTelemetry;
	}

	static [string] Mask([psobject] $toMask)
	{
		$sha384 = [System.Security.Cryptography.SHA384Managed]::new()
		$maskBytes = [System.Text.Encoding]::UTF8.GetBytes($toMask.ToString())
		$maskBytes = $sha384.ComputeHash($maskBytes)
		$sha384.Dispose()
		$take = 16
		$sb = [System.Text.StringBuilder]::new($take)
		for($i = 0; $i -lt ($take/2); $i++){
			$x = $sb.Append($maskBytes[$i].ToString("x2"))
		}
		return $sb.ToString();
	}
}
