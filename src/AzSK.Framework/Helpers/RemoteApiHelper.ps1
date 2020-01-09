Set-StrictMode -Version Latest

class RemoteApiHelper {
    hidden static [string] $ApiBaseEndpoint = [ConfigurationManager]::GetAzSKConfigData().AzSKApiBaseURL; #"https://localhost:44348/api"

    hidden static [string] GetAccessToken() {
        $rmContext = [ContextHelper]::GetCurrentRMContext();
		$ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
        return [ContextHelper]::GetAccessToken($ResourceAppIdURI);
    }

    hidden static [psobject] PostContent($uri, $content, $type) 
    {
            try {
                $accessToken = [RemoteApiHelper]::GetAccessToken()
                $result = Invoke-WebRequest -Uri $([RemoteApiHelper]::ApiBaseEndpoint + $uri) `
                    -Method Post `
                    -Body $content `
                    -ContentType $type `
                    -Headers @{"Authorization" = "Bearer $accessToken"} `
                    -UseBasicParsing
                return $result
            }
            catch {
                #Error while sending events to Database. Encode content to UTF8 and make API call again
                if (($null -ne $content)-and ($content.length -gt 0)) {
                    if ($_.Exception.Response.StatusCode -eq "BadRequest") {
                        [RemoteApiHelper]::PostUTF8Content($uri, $content, "application/json")
                    }
                }
                return "ERROR"
            }
    }  
    hidden static [psobject] PostUTF8Content($uri, $content, $type) 
    {
            try {
                $accessToken = [RemoteApiHelper]::GetAccessToken()
                $result = Invoke-WebRequest -Uri $([RemoteApiHelper]::ApiBaseEndpoint + $uri) `
                    -Method Post `
                    -Body ([System.Text.Encoding]::UTF8.GetBytes($content)) `
                    -ContentType $type `
                    -Headers @{"Authorization" = "Bearer $accessToken"} `
                    -UseBasicParsing
                return $result
            }
            catch {
                return "ERROR"
            }
    }
    
    hidden static [psobject] GetContent($uri, $content, $type) 
    {
        $url = [RemoteApiHelper]::ApiBaseEndpoint + $uri;
        $accessToken = [RemoteApiHelper]::GetAccessToken()
            $result = Invoke-WebRequest -Uri $url `
                -Method POST `
                -Body $content `
                -ContentType $type `
                -Headers @{"Authorization" = "Bearer $accessToken"} `
                -UseBasicParsing
                
            return $result.Content
              
    }


    hidden static [psobject] PostJsonContent($uri, $obj) {
        $postContent = [JsonHelper]::ConvertToJsonCustomCompressed($obj)
        return [RemoteApiHelper]::PostContent($uri, $postContent, "application/json")
    }
    hidden static [psobject] GetJsonContent($uri, $obj) {
        $postContent = [JsonHelper]::ConvertToJsonCustomCompressed($obj)
        return [RemoteApiHelper]::GetContent($uri, $postContent, "application/json")
    }

    static [void] PostSubscriptionScanResult($scanResult) {
        [RemoteApiHelper]::PostJsonContent("/scanresults/subscription", $scanResult) | Out-Null
    }

    static [void] PostServiceScanResult($scanResult) {
        [RemoteApiHelper]::PostJsonContent("/scanresults/service", $scanResult) | Out-Null
    }

    static [void] PostResourceInventory($resources) {
        [RemoteApiHelper]::PostJsonContent("/inventory/resources", $resources) | Out-Null
    }

    static [void] PostResourceControlsInventory($resourceControlData) {
        [RemoteApiHelper]::PostJsonContent("/inventory/resourceControls", $resourceControlData) | Out-Null
    }

	static [void] PostResourceFlatInventory($resourcesFlat) {
		[RemoteApiHelper]::PostJsonContent("/inventory/resourcesflat", $resourcesFlat) | Out-Null
	}

	static [void] PostApplicableControlSet([SVTEventContext[]] $contexts) {
        if (($contexts | Measure-Object).Count -lt 1) { return; }
        $set = [RemoteApiHelper]::ConvertToSimpleSet($contexts);
        [RemoteApiHelper]::PostJsonContent("/scanresults/service/applicable", $set) | Out-Null
    }
	
	static [void] PostRBACTelemetry([TelemetryRBAC[]] $RBACAccess){
		[RemoteApiHelper]::PostJsonContent("/inventory/RBACTelemetry", $RBACAccess) | Out-Null	
	}

    static [void] PostPolicyComplianceTelemetry($PolicyComplianceData){
		[RemoteApiHelper]::PostJsonContent("/policycompliancedata", $PolicyComplianceData) | Out-Null	
    }
    static [PSObject] GetComplianceSnapshot([string] $parameters){
		return([RemoteApiHelper]::GetJsonContent("/compliancedata", $parameters) )	
    }
    
    static [void] PostASCTelemetry($ASCTelemetryData)
    {
        $currentDateTime = [DateTime]::UtcNow
        $ASCDataList = @();
        #will remove $awaitedTelemetryList and consequent condition check once we are ready to use the APIs for the properties in the list
        $awaitedTelemetryList = @("SecureScore", "ThreatDetection", "ASCRecommendations", "SecurityEventsTier")
		$ASCTelemetryData | Get-Member -Type Property | ForEach-Object {
            if($_.Name -ne "SubscriptionId" -and (-not ($null -eq $ASCTelemetryData.($_.Name) -or "" -eq $ASCTelemetryData.($_.Name))) -and $awaitedTelemetryList -notcontains $_.Name)
            {
                $ascProperty = New-Object psobject -Property @{
                    SubscriptionId = $ASCTelemetryData.SubscriptionId;
                    FeatureName = "ASC";
                    SubFeatureName = $_.Name;
                    ResourceId = $null;
                    CustomData = $ASCTelemetryData.($_.Name);
                    UpdatedOn = $currentDateTime;
                }
                $ASCDataList += $ascProperty
            }
        }
        #will uncomment api call once the API for this is up
        [RemoteApiHelper]::PostJsonContent("/inventory/asctelemetrydata", $ASCDataList) | Out-Null
    }

    hidden static [psobject] ConvertToSimpleSet([SVTEventContext[]] $contexts) {
        $firstContext = $contexts[0]
        $set = "" | Select-Object "SubscriptionId", "SubscriptionName", "Source", "ScannerVersion", "ControlVersion", "ControlSet"
        $set.SubscriptionId = $firstContext.SubscriptionContext.SubscriptionId
        $set.SubscriptionName = $firstContext.SubscriptionContext.SubscriptionName
        $set.Source = [RemoteReportHelper]::GetScanSource()
        #RENAME
        $module = Get-Module 'AzSK*' | Select-Object -First 1
        $set.ScannerVersion = $module.Version.ToString()
        $set.ControlVersion = $module.Version.ToString()
        $set.ControlSet = [System.Collections.ArrayList]::new()
        foreach ($item in $contexts) {
            $controlItem = "" | Select-Object "FeatureName", "ResourceGroupName", "ResourceName", "ResourceId", "ControlIntId", "ControlId", "ControlSeverity"
            $controlItem.FeatureName = $item.FeatureName
			if([Helpers]::CheckMember($item,"ResourceContext"))
			{
				$controlItem.ResourceGroupName = $item.ResourceContext.ResourceGroupName
				$controlItem.ResourceName = $item.ResourceContext.ResourceName
				$controlItem.ResourceId = $item.ResourceContext.ResourceId
			}            
            
            $controlItem.ControlIntId = $item.ControlItem.Id
            $controlItem.ControlId = $item.ControlItem.ControlID
            $controlItem.ControlSeverity = $item.ControlItem.ControlSeverity
            $set.ControlSet.Add($controlItem) | Out-Null
        }
        return $set;
    }

    static [void] PushFeatureControlsTelemetry($ResourceControlsData)
    {        
        if($null -ne $ResourceControlsData.ResourceContext -and ($ResourceControlsData.Controls | Measure-Object).Count -gt 0)
        {
            $ResourceControlsDataMini = "" | Select-Object ResourceName, ResourceGroupName, ResourceId, Controls, ChildResourceNames
            $ResourceControlsDataMini.ResourceName = $ResourceControlsData.ResourceContext.ResourceName;
            $ResourceControlsDataMini.ResourceGroupName = $ResourceControlsData.ResourceContext.ResourceGroupName;
            $ResourceControlsDataMini.ResourceId = $ResourceControlsData.ResourceContext.ResourceId;
            $controls = @();
            $ResourceControlsData.Controls | ForEach-Object {
                $control = "" | Select-Object ControlStringId, ControlId;
                $control.ControlStringId = $_.ControlId;
                $control.ControlId = $_.Id;
                $controls += $control;
            }
            $ResourceControlsDataMini.Controls = $controls;        
            $ResourceControlsDataMini.ChildResourceNames = $ResourceControlsData.ChildResourceNames;   

            [RemoteApiHelper]::PostResourceControlsInventory($ResourceControlsDataMini);
        }
    }
}
