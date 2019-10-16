class AzResourceInventoryListener: ListenerBase
{
    [Microsoft.ApplicationInsights.TelemetryClient] $TelemetryClient;
    hidden static [AzResourceInventoryListener] $Instance = $null;
    AzResourceInventoryListener():Base()
    {
        $this.TelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new()
    }
    static [AzResourceInventoryListener] GetInstance() {
        if( $null  -eq [AzResourceInventoryListener]::Instance ) {
             [AzResourceInventoryListener]::Instance = [AzResourceInventoryListener]::new();
         }
         return [AzResourceInventoryListener]::Instance
     }
    [void] RegisterEvents() 
    {
        $this.UnregisterEvents();       

        $this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
            $currentInstance = [SecurityRecommendationReport]::GetInstance();
            try 
            {
                $currentInstance.SetRunIdentifier([AzSKRootEventArgument] ($Event.SourceArgs | Select-Object -First 1));
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

        $this.RegisterEvent([SVTEvent]::CommandStarted, {
            $currentInstance = [AzResourceInventoryListener]::GetInstance();
        try
        {
            $scanSource = [RemoteReportHelper]::GetScanSource();
            if($scanSource -ne [ScanSource]::Runbook) { return; }
            $SubscriptionId = ([ContextHelper]::GetCurrentRMContext()).Subscription.Id;
            [ResourceInventory]::FetchResources();
            [AzResourceInventoryListener]::PostAzResourceInventory();            
            $resources= [ResourceInventory]::RawResources
            $resourceGroups = Get-AzResourceGroup
            $resourceDetails = @();
            $telemetryEvents = [System.Collections.ArrayList]::new()
                    foreach($res in $resources){
                                    $rgTags = ($resourceGroups | where-object {$_.ResourceGroupName  -eq $res.ResourceGroupName}).Tags;
                        $resourceProperties = @{
                        "Name" = $res.Name;
                        "ResourceId" = $res.ResourceId;
                        "ResourceName" = $res.Name;
                        "ResourceType" = $res.ResourceType;
                        "ResourceGroupName" = $res.ResourceGroupName;
                        "Location" = $res.Location;
                        "SubscriptionId" = $SubscriptionId;
                        "Tags" = [Helpers]::FetchTagsString($res.Tags);
                        "Sku" = $res.Sku
                        "Env" = $res.Tags.Env;
                            "ComponentID" = $res.Tags.ComponentID;
                            "RGComponentID" = $rgTags.ComponentID;
                            "RGEnv" = $rgTags.Env;
                    }
                    $telemetryEvent = "" | Select-Object Name, Properties, Metrics
                    $telemetryEvent.Name = "Resource Inventory"
                    $telemetryEvent.Properties = $resourceProperties
                    $telemetryEvents.Add($telemetryEvent) | Out-Null
                    $resourceDetails+=$resourceProperties;		   
                    }
                [AIOrgTelemetryHelper]::TrackEvents($telemetryEvents);
                [RemoteApiHelper]::PostResourceFlatInventory($resourceDetails)
				[ResourceInventory]::SetResourceToTagMapping($resourceDetails)
        }
        catch{
            $currentInstance.PublishException($_);
        }
        });
    }

    
    static [void] PostAzResourceInventory()
    {
        $currentInstance = [AzResourceInventoryListener]::GetInstance();
        try
        {
            $scanSource = [RemoteReportHelper]::GetScanSource();
            if($scanSource -ne [ScanSource]::Runbook) { return; }
            $SubscriptionId = ([ContextHelper]::GetCurrentRMContext()).Subscription.Id;
            if(-not $SubscriptionId) {return;}
            $resources = "" | Select-Object "SubscriptionId", "ResourceGroups"
            $resources.SubscriptionId = $SubscriptionId
            $resources.ResourceGroups = [System.Collections.ArrayList]::new()
            $supportedResourceTypes = [SVTMapping]::GetSupportedResourceMap()
            #  Not considering nested resources to reduce complexity
            $filteredResources = [ResourceInventory]::FilteredResources
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
    }
}