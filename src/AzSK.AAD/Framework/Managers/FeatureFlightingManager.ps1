Set-StrictMode -Version Latest
#
# FeatureFlightingManager.ps1
#
class FeatureFlightingManager
{
	hidden static [FeatureFlight] $FeatureFlight = $null;

	hidden static [bool] GetFeatureStatus([string] $FeatureName, [string] $tenantId)
    {
		$featureStatus = $true;
		if($null -eq [FeatureFlightingManager]::FeatureFlight)
		{
			[FeatureFlightingManager]::FeatureFlight = [FeatureFlightingManager]::FetchFeatureFlightConfigData();
		}
		$feature = [FeatureFlightingManager]::FeatureFlight.Features | Where-Object { $_.Name -eq $FeatureName};
		if(($feature | Measure-Object).Count -eq 1)
		{
			if($feature.IsEnabled -eq $true)
			{
				#Print preview note if the preview flag is enabled for this feature
				if($feature.UnderPreview -eq $true)
				{
					[EventBase]::PublishGenericCustomMessage("Note: $FeatureName Feature is currently under Preview.", [MessageType]::Info);
				}
				$scanSource = [AzSKSettings]::GetInstance().GetScanSource();
				$compatibleScanSource = ($feature.Sources | Where-Object { $_ -eq $scanSource -or $_ -eq "*" } | Measure-Object).Count -gt 0;				
				#Check if the feature scan source is compatible
				if(-not $compatibleScanSource)
				{
					$featureStatus = $false;	
				}
				#Check if the sub is marked under disabled list for this feature
				elseif(($feature.DisabledForSubs | Measure-Object).Count -gt 0 -and ($feature.DisabledForSubs | Where-Object { $_ -eq $tenantId } | Measure-Object).Count -eq 1)
				{
					$featureStatus = $false;	
				}
				#Check if the sub is marked under enabled list or * for this feature
				elseif(($feature.EnabledForSubs | Measure-Object).Count -gt 0 -and ($feature.EnabledForSubs | Where-Object { $_ -eq $tenantId -or $_ -eq "*"} | Measure-Object).Count -eq 0)
				{
					$featureStatus = $false;
				}
			}
			else {
				$featureStatus = $false;
			}
		}
		return $featureStatus;		
	}
	
	hidden static [FeatureFlight] FetchFeatureFlightConfigData()
	{
		[FeatureFlight] $flightingData = [FeatureFlight]::new();
		$flightingData = [FeatureFlight] [ConfigurationManager]::LoadServerConfigFile("FeatureFlighting.json");
		return $flightingData;
	}		
}
