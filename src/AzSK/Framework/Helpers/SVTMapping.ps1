Set-StrictMode -Version Latest
class SVTMapping
{
	static [string] $VirtualNetworkTypeName = "VirtualNetwork";
	static [string] $ERvNetTypeName = "ERvNet";
	static [string] $LogicAppsTypeName = "LogicApps";
	static [string] $APIConnectionTypeName = "APIConnection";

	hidden static [hashtable] $SupportedResourceMap = $null;

	static [string] GetResourceTypeEnumItems()
	{
		return ([SVTMapping]::Mapping |
					Where-Object { -not [string]::IsNullOrEmpty($_.ResourceTypeName) } |
					ForEach-Object { "$($_.ResourceTypeName.Replace(' ', '')) `r`n" } |
					Sort-Object);
	}

	static [hashtable] GetSupportedResourceMap()
	{
		if($null -eq [SVTMapping]::SupportedResourceMap){
			$supportedMap = @{}
			foreach($map in [SVTMapping]::Mapping){
				if([string]::IsNullOrWhiteSpace($map.ResourceType) -or [string]::IsNullOrWhiteSpace($map.ResourceTypeName)){
					continue;
				}
				if($supportedMap.ContainsKey($map.ResourceType)) {continue;}
				$supportedMap.Add($map.ResourceType.ToLower(), $map.ResourceTypeName)
			}
			[SVTMapping]::SupportedResourceMap = $supportedMap
		}
		return [SVTMapping]::SupportedResourceMap
	}

    static [ResourceTypeMapping[]] $Mapping = (
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.Logic/Workflows";
            JsonFileName = "LogicApps.json";
            ClassName = "LogicApps";
			ResourceTypeName = [SVTMapping]::LogicAppsTypeName;
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.Compute/virtualMachines";
            JsonFileName = "VirtualMachine.json";
            ClassName = "VirtualMachine";
			ResourceTypeName = "VirtualMachine";
        },
        [ResourceTypeMapping]@{
            ResourceType = "Microsoft.DataLakeStore/accounts";
            JsonFileName = "DataLakeStore.json";
            ClassName = "DataLakeStore";
			ResourceTypeName = "DataLakeStore";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.DataLakeAnalytics/accounts";
            JsonFileName = "DataLakeAnalytics.json";
            ClassName = "DataLakeAnalytics";
			ResourceTypeName = "DataLakeAnalytics";
        },
        [ResourceTypeMapping]@{
            ResourceType = "Microsoft.KeyVault/vaults";
            JsonFileName = "KeyVault.json";
            ClassName = "KeyVault";
			ResourceTypeName = "KeyVault";
        },
        [ResourceTypeMapping]@{
            ResourceType = "Microsoft.Sql/servers";
            JsonFileName = "SQLDatabase.json";
            ClassName = "SQLDatabase";
            FixClassName = "SQLDatabaseFix";
			FixFileName = "SQLDatabaseFix.ps1";
			ResourceTypeName = "SQLDatabase";
        },
        [ResourceTypeMapping]@{
            ResourceType = "Microsoft.Web/sites";
            JsonFileName = "AppService.json";
            ClassName = "AppService";
			FixClassName = "AppServiceFix";
			FixFileName = "AppServiceFix.ps1";
			ResourceTypeName = "AppService";
        },
        [ResourceTypeMapping]@{
            ResourceType = "Microsoft.DataFactory/dataFactories";
            JsonFileName = "DataFactory.json";
            ClassName = "DataFactory";
			ResourceTypeName = "DataFactory";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.DataFactory/factories";
            JsonFileName = "DataFactoryV2.json";
            ClassName = "DataFactoryV2";
            ResourceTypeName = "DataFactoryV2";
        }, 
        [ResourceTypeMapping]@{
            ResourceType = "Microsoft.Storage/storageAccounts";
            JsonFileName = "Storage.json";
            ClassName = "Storage";
			ResourceTypeName = "Storage";
			FixClassName = "StorageFix";
			FixFileName = "StorageFix.ps1";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.NotificationHubs/namespaces/notificationHubs";
            JsonFileName = "NotificationHub.json";
            ClassName = "NotificationHub";
			ResourceTypeName = "NotificationHub";
		 },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.Cdn/profiles";
            JsonFileName = "CDN.json";
            ClassName = "CDN";
			ResourceTypeName = "CDN";
			FixClassName = "CDNFix";
			FixFileName = "CDNFix.ps1";
        },
        [ResourceTypeMapping]@{
            ResourceType = "Microsoft.Network/virtualNetworks";
            JsonFileName = "VirtualNetwork.json";
            ClassName = "VirtualNetwork";
			ResourceTypeName = [SVTMapping]::VirtualNetworkTypeName;
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.Network/virtualNetworks";
            JsonFileName = "ERvNet.json";
            ClassName = "ERvNet";
			ResourceTypeName = [SVTMapping]::ERvNetTypeName;
        },
        [ResourceTypeMapping]@{
            ResourceType = "Microsoft.AnalysisServices/servers";
            JsonFileName = "AnalysisServices.json";
            ClassName = "AnalysisServices";
			ResourceTypeName = "AnalysisServices";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.Search/searchServices";
            JsonFileName = "Search.json";
            ClassName = "Search";
			ResourceTypeName = "Search";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.Batch/batchAccounts";
            JsonFileName = "Batch.json";
            ClassName = "Batch";
			ResourceTypeName = "Batch";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.ClassicCompute/domainNames";
            JsonFileName = "CloudService.json";
            ClassName = "CloudService";
			ResourceTypeName = "CloudService";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.ServiceBus/namespaces";
            JsonFileName = "ServiceBus.json";
            ClassName = "ServiceBus";
			ResourceTypeName = "ServiceBus";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.Eventhub/namespaces";
            JsonFileName = "EventHub.json";
            ClassName = "EventHub";
			ResourceTypeName = "EventHub";
        },
       [ResourceTypeMapping]@{
            ResourceType = "Microsoft.Cache/Redis";
            JsonFileName = "RedisCache.json";
            ClassName = "RedisCache";
			ResourceTypeName = "RedisCache";
		    FixClassName = "RedisCacheFix";
			FixFileName = "RedisCacheFix.ps1";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.ServiceFabric/clusters";
            JsonFileName = "ServiceFabric.json";
            ClassName = "ServiceFabric";
			ResourceTypeName = "ServiceFabric";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.Web/connectionGateways";
            JsonFileName = "ODG.json";
            ClassName = "ODG";
			ResourceTypeName = "ODG";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.Network/trafficmanagerprofiles";
            JsonFileName = "TrafficManager.json";
            ClassName = "TrafficManager";
			ResourceTypeName = "TrafficManager";
			FixClassName = "TrafficManagerFix";
			FixFileName = "TrafficManagerFix.ps1";
        
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.StreamAnalytics/streamingjobs";
            JsonFileName = "StreamAnalytics.json";
            ClassName = "StreamAnalytics";
			ResourceTypeName = "StreamAnalytics";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.DocumentDb/databaseAccounts";
            JsonFileName = "CosmosDB.json";
            ClassName = "CosmosDb";
			ResourceTypeName = "CosmosDB";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.Automation/automationAccounts";
            JsonFileName = "Automation.json";
            ClassName = "Automation";
			ResourceTypeName = "Automation";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.Network/loadBalancers";
            JsonFileName = "LoadBalancer.json";
            ClassName = "LoadBalancer";
			ResourceTypeName = "LoadBalancer";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.Web/connections";
            JsonFileName = "APIConnection.json";
            ClassName = "APIConnection";
			ResourceTypeName = [SVTMapping]::APIConnectionTypeName;
        },
        [ResourceTypeMapping]@{
            ResourceType = "Microsoft.BotService/botServices";
            JsonFileName = "BotService.json";
            ClassName = "BotService";
			ResourceTypeName = "BotService";
        },
		[ResourceTypeMapping]@{
            ResourceType = "AzSKCfg";
			ClassName = "AzSKCfg";
			JsonFileName = "AzSKCfg.json";
			ResourceTypeName = "AzSKCfg";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.ContainerInstance/containerGroups";
			ClassName = "ContainerInstances";
			JsonFileName = "ContainerInstances.json";
			ResourceTypeName = "ContainerInstances";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.ContainerRegistry/registries";
			ClassName = "ContainerRegistry";
			JsonFileName = "ContainerRegistry.json";
			ResourceTypeName = "ContainerRegistry";
			FixClassName = "ContainerRegistryFix";
			FixFileName = "ContainerRegistryFix.ps1";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.Databricks/workspaces";
			ClassName = "Databricks";
			JsonFileName = "Databricks.json";
			ResourceTypeName = "Databricks";
        },
        [ResourceTypeMapping]@{
            ResourceType = "Microsoft.HDInsight/clusters";
			ClassName = "HDInsight";
			JsonFileName = "HDInsight.json";
			ResourceTypeName = "HDInsight";
        },
		[ResourceTypeMapping]@{
            ResourceType = "";
			ClassName = "";
			JsonFileName = "ApplicationProxy.json";
			ResourceTypeName = "";
        },
        [ResourceTypeMapping]@{
            ResourceType = "Microsoft.ApiManagement/service";
			ClassName = "APIManagement";
			JsonFileName = "APIManagement.json";
            ResourceTypeName = "APIManagement";
        },
		[ResourceTypeMapping]@{
            ResourceType = "Microsoft.ContainerService/ManagedClusters";
			ClassName = "KubernetesService";
			JsonFileName = "KubernetesService.json";
			ResourceTypeName = "KubernetesService";
        },
     [ResourceTypeMapping]@{
            ResourceType = "Microsoft.DBforPostgreSQL/servers";
			ClassName = "DBForPostgreSQL";
			JsonFileName = "DBForPostgreSQL.json";
            ResourceTypeName = "DBForPostgreSQL";
    },
	 [ResourceTypeMapping]@{
            ResourceType = "Microsoft.DBforMySQL/servers";
			ClassName = "DBForMySql";
			JsonFileName = "DBForMySql.json";
			ResourceTypeName = "DBForMySql";
    },
    [ResourceTypeMapping]@{
        ResourceType = "Microsoft.Compute/virtualMachineScaleSets";
        JsonFileName = "VirtualMachineScaleSet.json";
        ClassName = "VirtualMachineScaleSet";
        ResourceTypeName = "VirtualMachineScaleSet";
    }
    );

	static [SubscriptionMapping] $SubscriptionMapping =	@{
		ClassName = "SubscriptionCore";
        JsonFileName = "SubscriptionCore.json";
		FixClassName = "SubscriptionCoreFix";
		FixFileName = "SubscriptionCoreFix.ps1";
	};
	
}

Invoke-Expression "enum ResourceTypeName { `r`n All `r`n $([SVTMapping]::GetResourceTypeEnumItems()) }";
