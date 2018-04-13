Set-StrictMode -Version Latest 
class StreamAnalytics: SVTBase
{       
    hidden [PSObject] $ResourceObject;

    StreamAnalytics([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
                 Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
    }

    StreamAnalytics([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
    }

    hidden [ControlResult] CheckStreamAnalyticsMetricAlert([ControlResult] $controlResult)
    {
        $this.CheckMetricAlertConfiguration($this.ControlSettings.MetricAlert.StreamAnalytics, $controlResult, "");
        return $controlResult;
	 }
}
