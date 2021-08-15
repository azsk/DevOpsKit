Set-StrictMode -Version Latest

#This is used to send events to the controls API (to directly save to org DB)
class RemoteReportsListener: ListenerBase {

    hidden RemoteReportsListener() {
    }

    hidden static [RemoteReportsListener] $Instance = $null;

    static [RemoteReportsListener] GetInstance() {
        if ( $null  -eq [RemoteReportsListener]::Instance  ) {
            [RemoteReportsListener]::Instance = [RemoteReportsListener]::new();
        }
        return [RemoteReportsListener]::Instance
    }

    [void] RegisterEvents() {
        $this.UnregisterEvents();

        $this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
            $currentInstance = [RemoteReportsListener]::GetInstance();
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

		$this.RegisterEvent([SVTEvent]::CommandStarted, {
			 $currentInstance = [RemoteReportsListener]::GetInstance();
			try
			{

				$scanSource = [RemoteReportHelper]::GetScanSource();
				if($scanSource -ne [ScanSource]::Runbook) { return; }
				[ResourceInventory]::FetchResources();
				[RemoteReportsListener]::ReportAllResources();				
				$invocationContext = [System.Management.Automation.InvocationInfo] $currentInstance.InvocationContext
				if(!$invocationContext.BoundParameters.ContainsKey("tenantId")) {return;}
				$resources = "" | Select-Object "tenantId", "ResourceGroups"
				$resources.tenantId = $invocationContext.BoundParameters["tenantId"]
				$resources.ResourceGroups = [System.Collections.ArrayList]::new()
				$supportedResourceTypes = [SVTMapping]::GetSupportedResourceMap()
				# # Not considering nested resources to reduce complexity
				$filteredResources = [ResourceInventory]::FilteredResources | Where-Object { $supportedResourceTypes.ContainsKey($_.ResourceType.ToLower()) }
				$grouped = $filteredResources | Group-Object {$_.ResourceGroupName} | Select-Object Name, Group				
				foreach($group in $grouped){
					$resourceGroup = "" | Select-Object Name, Resources
					$resourceGroup.Name = $group.Name
					$resourceGroup.Resources = [System.Collections.ArrayList]::new()
					foreach($item in $group.Group){
						$resource = "" | Select-Object Name, ResourceId, Feature
						if($item.Name.Contains("/")){
							$splitName = $item.Name.Split("/")
							$resource.Name = $splitName[$splitName.Length - 1]
						}
						else{
							$resource.Name = $item.Name;
						}
						$resource.ResourceId = $item.ResourceId
						$resource.Feature = $supportedResourceTypes[$item.ResourceType.ToLower()]
						$resourceGroup.Resources.Add($resource) | Out-Null
					}
					$resources.ResourceGroups.Add($resourceGroup) | Out-Null
				}
				[RemoteApiHelper]::PostResourceInventory($resources)
			}
			catch
			{
				$currentInstance.PublishException($_);
			}
		});

		$this.RegisterEvent([SVTEvent]::EvaluationCompleted, {
			$currentInstance = [RemoteReportsListener]::GetInstance();
			try
			{
				$settings = [ConfigurationManager]::GetAzSKConfigData();
				if(!$settings.PublishVulnDataToApi) {return;}
				$invocationContext = [System.Management.Automation.InvocationInfo] $currentInstance.InvocationContext
				$SVTEventContexts = [SVTEventContext[]] $Event.SourceArgs
				$featureGroup = [RemoteReportHelper]::GetFeatureGroup($SVTEventContexts)
				if($featureGroup -eq [FeatureGroup]::Subscription){
					[RemoteReportsListener]::ReportSubscriptionScan($currentInstance, $invocationContext, $SVTEventContexts)
				}elseif($featureGroup -eq [FeatureGroup]::Service){
					[RemoteReportsListener]::ReportServiceScan($currentInstance, $invocationContext, $SVTEventContexts)
				}else{

				}
			}
			catch
			{
				$currentInstance.PublishException($_);
			}
		});

		$this.RegisterEvent([AzSKRootEvent]::PublishCustomData, {
            $currentInstance = [RemoteReportsListener]::GetInstance();
            try
            {				
				$CustomDataObj =  $Event.SourceArgs
				$CustomObjectData=$CustomDataObj| Select-Object -exp Messages|select -exp DataObject
				if($CustomObjectData.Name -eq "SubSVTObject")
				{
					$subSVTObject = $CustomObjectData.Value;
					$currentInstance.FetchRBACTelemetry($subSVTObject);					
					[RemoteApiHelper]::PostRBACTelemetry(($subSVTObject.CustomObject.Value));
				}
				elseif($CustomObjectData.Name -eq "FeatureControlTelemetry")
				{					 
					 [RemoteApiHelper]::PushFeatureControlsTelemetry($CustomObjectData.Value);
				}
				#| select -exp Value;
				
            }
            catch
            {
                $currentInstance.PublishException($_);
            }
        });

		
    }


	static [void] ReportAllResources()
	{
		$currentInstance = [RemoteReportsListener]::GetInstance();
		$invocationContext = [System.Management.Automation.InvocationInfo] $currentInstance.InvocationContext
		$tenantId = ([AccountHelper]::GetCurrentRmContext()).Subscription.Id;
		$resourceGroups = Get-AzResourceGroup
        $resourcesDetails = @();
		$resourcesFlat = [ResourceInventory]::RawResources
        foreach($res in $resourcesFlat){
            $resourceGroup = ($resourceGroups | where-object {$_.ResourceGroupName -eq $res.ResourceGroupName});
            $resEnv = "";
            $resComponentId = "";
            $rgEnv = "";
            $rgComponentId = "";
            if([Helpers]::CheckMember($resourceGroup, "Tags")) {
                $rgTags = $resourceGroup.Tags;
                if($rgTags.ContainsKey("Env")) 
                {
                   $rgEnv = $rgTags.Env;
                }
                if($rgTags.ContainsKey("ComponentID")) 
                {
                    $rgComponentId = $rgTags.ComponentID;
                }
            }
            if([Helpers]::CheckMember($res, "Tags"))
            {
                $resTags = $res.Tags;
                if($resTags.ContainsKey("Env"))
                {
                    $resEnv = $resTags.Env;
                }
                if($resTags.ContainsKey("ComponentID"))
                {
                    $resComponentId = $resTags.ComponentID;
                }
            }
			$resourceProperties = @{
			    "Name" = $res.Name;
			    "ResourceId" = $res.ResourceId;
			    "ResourceName" = $res.Name;
			    "ResourceType" = $res.ResourceType;
			    "ResourceGroupName" = $res.ResourceGroupName;
			    "Location" = $res.Location;
			    "tenantId" = $tenantId;
                "Sku" = $res.Sku;
			    "Tags" = [Helpers]::FetchTagsString($res.Tags);
				"Env" = $resEnv;
				"ComponentID" = $resComponentId;
				"RGComponentID" = $rgComponentId;
				"RGEnv" = $rgEnv;
                }
                $resourcesDetails += $resourceProperties;
            }
		[RemoteApiHelper]::PostResourceFlatInventory($resourcesDetails)
	}


	static [void] ReportSubscriptionScan(
		[RemoteReportsListener] $publisher, `
		[System.Management.Automation.InvocationInfo]  $invocationContext, `
		[SVTEventContext[]] $SVTEventContexts)
	{
		$SVTEventContext = $SVTEventContexts[0]
		$scanResult = [SubscriptionScanInfo]::new()
		$scanResult.ScanKind = [RemoteReportHelper]::GetSubscriptionScanKind($invocationContext.MyCommand.Name, $invocationContext.BoundParameters)
		$scanResult.tenantId = $SVTEventContext.TenantContext.tenantId
		$scanResult.TenantName = $SVTEventContext.TenantContext.TenantName
		$scanResult.Source = [RemoteReportHelper]::GetScanSource()
		$scanResult.ScannerVersion = $publisher.GetCurrentModuleVersion()
		# Using module version as control version by default
		$scanResult.ControlVersion = $publisher.GetCurrentModuleVersion()
		$scanResult.Metadata = [Helpers]::ConvertToJsonCustomCompressed($SVTEventContext.TenantContext.SubscriptionMetadata)
		if(($SVTEventContexts | Measure-Object).Count -gt 0 -and ($SVTEventContexts[0].ControlResults | Measure-Object).Count -gt 0)
		{
			$TempCtrlResult = $SVTEventContexts[0].ControlResults[0];
			$scanResult.HasAttestationWritePermissions = $TempCtrlResult.CurrentSessionContext.Permissions.HasAttestationWritePermissions
			$scanResult.HasAttestationReadPermissions = $TempCtrlResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions
			$scanResult.IsLatestPSModule = $TempCtrlResult.CurrentSessionContext.IsLatestPSModule
		}
		$results = [System.Collections.ArrayList]::new()
		$SVTEventContexts | ForEach-Object {
			$context = $_
			if ($context.ControlItem.Enabled) {
				$result = [RemoteReportHelper]::BuildSubscriptionControlResult($context.ControlResults[0], $context.ControlItem)
				$results.Add($result)
			}
			else {
				$result = [SubscriptionControlResult]::new()
				$result.ControlId = $context.ControlItem.ControlID
				$result.ControlIntId = $context.ControlItem.Id
				$result.ActualVerificationResult = [VerificationResult]::Disabled
				$result.AttestationStatus = [AttestationStatus]::None
				$result.VerificationResult = [VerificationResult]::Disabled
				$result.MaximumAllowedGraceDays = $context.MaximumAllowedGraceDays
				$results.Add($result)
			}
		}
		$scanResult.ControlResults = [SubscriptionControlResult[]] $results
		[RemoteApiHelper]::PostSubscriptionScanResult($scanResult)
	}

	static [void] ReportServiceScan(
		[RemoteReportsListener] $publisher, `
		[System.Management.Automation.InvocationInfo]  $invocationContext, `
		[SVTEventContext[]] $SVTEventContexts)
	{
		$SVTEventContextFirst = $SVTEventContexts[0]
		$scanResult = [ServiceScanInfo]::new()
		$scanResult.ScanKind = [RemoteReportHelper]::GetServiceScanKind($invocationContext.MyCommand.Name, $invocationContext.BoundParameters)
		$scanResult.tenantId = $SVTEventContextFirst.TenantContext.tenantId
		$scanResult.TenantName = $SVTEventContextFirst.TenantContext.TenantName
		$scanResult.Source = [RemoteReportHelper]::GetScanSource()
		$scanResult.ScannerVersion = $publisher.GetCurrentModuleVersion()
		# Using module version as control version by default
		$scanResult.ControlVersion = $publisher.GetCurrentModuleVersion()
		$scanResult.Feature = $SVTEventContextFirst.FeatureName
		$scanResult.ResourceGroup = $SVTEventContextFirst.ResourceContext.ResourceGroupName
		$scanResult.ResourceName = $SVTEventContextFirst.ResourceContext.ResourceName
		$scanResult.ResourceId = $SVTEventContextFirst.ResourceContext.ResourceId
		$scanResult.Metadata = [Helpers]::ConvertToJsonCustomCompressed($SVTEventContextFirst.ResourceContext.ResourceMetadata)
		
		if(($SVTEventContexts | Measure-Object).Count -gt 0 -and ($SVTEventContexts[0].ControlResults | Measure-Object).Count -gt 0)
		{
			$TempCtrlResult = $SVTEventContexts[0].ControlResults[0];
			$scanResult.HasAttestationWritePermissions = $TempCtrlResult.CurrentSessionContext.Permissions.HasAttestationWritePermissions
			$scanResult.HasAttestationReadPermissions = $TempCtrlResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions
			$scanResult.IsLatestPSModule = $TempCtrlResult.CurrentSessionContext.IsLatestPSModule
		}
		$results = [System.Collections.ArrayList]::new()
		$SVTEventContexts | ForEach-Object {
			$SVTEventContext = $_
			if (!$SVTEventContext.ControlItem.Enabled) {
				$result = [ServiceControlResult]::new()
				$result.ControlId = $SVTEventContext.ControlItem.ControlID
				$result.ControlIntId = $SVTEventContext.ControlItem.Id
				$result.ControlSeverity = $SVTEventContext.ControlItem.ControlSeverity
				$result.ActualVerificationResult = [VerificationResult]::Disabled
				$result.AttestationStatus = [AttestationStatus]::None
				$result.VerificationResult = [VerificationResult]::Disabled				
				$results.Add($result)
			}
			elseif ($SVTEventContext.ControlResults.Count -eq 1 -and `
				($scanResult.ResourceName -eq $SVTEventContext.ControlResults[0].ChildResourceName -or `
					[string]::IsNullOrWhiteSpace($SVTEventContext.ControlResults[0].ChildResourceName)))
			{
				$result = [RemoteReportHelper]::BuildServiceControlResult($SVTEventContext.ControlResults[0], `
					$false, $SVTEventContext.ControlItem)
				$results.Add($result)
			}
			elseif ($SVTEventContext.ControlResults.Count -eq 1 -and `
				$scanResult.ResourceName -ne $SVTEventContext.ControlResults[0].ChildResourceName)
			{
				$result = [RemoteReportHelper]::BuildServiceControlResult($SVTEventContext.ControlResults[0], `
					 $true, $SVTEventContext.ControlItem)
				$results.Add($result)
			}
			elseif ($SVTEventContext.ControlResults.Count -gt 1)
			{
				$SVTEventContext.ControlResults | Foreach-Object {
					$result = [RemoteReportHelper]::BuildServiceControlResult($_ , `
						 $true, $SVTEventContext.ControlItem)
					$results.Add($result)
				}
			}
		}

		$scanResult.ControlResults = [ServiceControlResult[]] $results
		[RemoteApiHelper]::PostServiceScanResult($scanResult)
	}

	hidden [void] FetchRBACTelemetry($svtObject)
	{
		$svtObject.GetRoleAssignments();
		$svtObject.PublishRBACTelemetryData();
		$svtObject.GetPIMRoles();

	}
}
