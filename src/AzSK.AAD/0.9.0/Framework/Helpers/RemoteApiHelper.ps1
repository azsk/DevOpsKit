﻿Set-StrictMode -Version Latest

#Helper functions used by RemoteReportListner (for sending events to controls API)
class RemoteApiHelper {
    hidden static [string] $ApiBaseEndpoint = [ConfigurationManager]::GetAzSKConfigData().AzSKApiBaseURL; #"https://localhost:44348/api"

    #TODO: Reconcile this with AccountHelper::GetAccessToken()
    hidden static [string] GetAccessToken() {
        $rmContext = [AccountHelper]::GetCurrentRmContext();
		$ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
        return [AccountHelper]::GetAccessToken($ResourceAppIdURI);
    }

    hidden static [psobject] PostContent($uri, $content, $type) {
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
            return "ERROR"
        }
    }

    hidden static [psobject] PostJsonContent($uri, $obj) {
        $postContent = [Helpers]::ConvertToJsonCustomCompressed($obj)
        return [RemoteApiHelper]::PostContent($uri, $postContent, "application/json")
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
    
    hidden static [psobject] ConvertToSimpleSet([SVTEventContext[]] $contexts) {
        $firstContext = $contexts[0]
        $set = "" | Select-Object "tenantId", "TenantName", "Source", "ScannerVersion", "ControlVersion", "ControlSet"
        $set.tenantId = $firstContext.TenantContext.tenantId
        $set.TenantName = $firstContext.TenantContext.TenantName
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
