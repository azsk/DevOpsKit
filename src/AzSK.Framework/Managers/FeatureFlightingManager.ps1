Set-StrictMode -Version Latest
#
# FeatureFlightingManager.ps1
#
class FeatureFlightingManager
{
	hidden static [FeatureFlight] $FeatureFlight = $null;
	hidden static $FeatureStatusCache = @{};

	hidden static [bool] GetFeatureStatus([string] $FeatureName, [string] $SubscriptionId)
    {
		#SubscriptionId can either be specific subscription Id or  "*" 
		#Specific Subscription - To check feature status for that particular subscription
		#"*" - To check feature status irrespective of subscription
		#So to check the feature status we will first query the hashtable with subscription specific key
		#If not found then we will query the hashtable with All subscription key
		$SubscriptionSpecificFeatureKey = $FeatureName + "-" + $SubscriptionId
		$AllSubscriptionFeatureKey = $FeatureName + "-" + "*"
		if([FeatureFlightingManager]::FeatureStatusCache.ContainsKey($SubscriptionSpecificFeatureKey))
		{
			return [FeatureFlightingManager]::FeatureStatusCache["$SubscriptionSpecificFeatureKey"]
		}
		elseif([FeatureFlightingManager]::FeatureStatusCache.ContainsKey($AllSubscriptionFeatureKey) -and [FeatureFlightingManager]::FeatureStatusCache["$AllSubscriptionFeatureKey"])
		{
			return $true
		}

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
				#Added the or condition for the scenario where input subscription id is "*" i.e ALL but we have DisabledForSubs count > 0
				elseif(($feature.DisabledForSubs | Measure-Object).Count -gt 0 -and (($feature.DisabledForSubs | Where-Object { $_ -eq $SubscriptionId } | Measure-Object).Count -gt 0 -or $SubscriptionId -eq "*"))
				{
					$featureStatus = $false;	
				}
				#Check if the sub is marked under enabled list or * for this feature
				elseif(($feature.EnabledForSubs | Measure-Object).Count -gt 0 -and ($feature.EnabledForSubs | Where-Object { $_ -eq $SubscriptionId -or $_ -eq "*"} | Measure-Object).Count -eq 0)
				{
					$featureStatus = $false;
				}
			}
			else {
				$featureStatus = $false;
			}
		}
		#Store the feature status in cache
		[FeatureFlightingManager]::FeatureStatusCache["$SubscriptionSpecificFeatureKey"] = $featureStatus
		return $featureStatus;		
	}
	
	hidden static [FeatureFlight] FetchFeatureFlightConfigData()
	{
		[FeatureFlight] $flightingData = [FeatureFlight]::new();
		$flightingData = [FeatureFlight] [ConfigurationManager]::LoadServerConfigFile("FeatureFlighting.json");
		return $flightingData;
	}		
}
