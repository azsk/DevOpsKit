Set-StrictMode -Version Latest
class SVTMapping
{

	hidden static [hashtable] $SupportedResourceMap = $null;

	static [string] GetResourceTypeEnumItems()
	{
		return ([SVTMapping]::AzSKDevOpsResourceMapping |
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
            ResourceType = "AzureDevOps.Organization";
            JsonFileName = "AzureDevOps.Organization.json";
            ClassName = "Organization";
            ResourceTypeName = "Organization";            
        }
    );

    static [ResourceTypeMapping[]] $AzSKDevOpsResourceMapping = (
		[ResourceTypeMapping]@{
            ResourceType = "AzureDevOps.Organization";
            JsonFileName = "AzureDevOps.Organization.json";
            ClassName = "Organization";
            ResourceTypeName = "Organization";            
        },
        [ResourceTypeMapping]@{
            ResourceType = "AzureDevOps.Project";
			ClassName = "Project";
			JsonFileName = "AzureDevOps.Project.json";
			ResourceTypeName = "Project";
        },
        [ResourceTypeMapping]@{
            ResourceType = "AzureDevOps.User";
			ClassName = "User";
			JsonFileName = "AzureDevOps.User.json";
			ResourceTypeName = "User";
        },
        [ResourceTypeMapping]@{
            ResourceType = "AzureDevOps.Build";
			ClassName = "Build";
			JsonFileName = "AzureDevOps.Build.json";
			ResourceTypeName = "Build";
        },
        [ResourceTypeMapping]@{
            ResourceType = "AzureDevOps.Release";
			ClassName = "Release";
			JsonFileName = "AzureDevOps.Release.json";
			ResourceTypeName = "Release";
        },
        [ResourceTypeMapping]@{
            ResourceType = "AzureDevOps.ServiceConnection";
			ClassName = "ServiceConnection";
			JsonFileName = "AzureDevOps.ServiceConnection.json";
			ResourceTypeName = "ServiceConnection";
        },
        [ResourceTypeMapping]@{
            ResourceType = "AzureDevOps.AgentPool";
			ClassName = "AgentPool";
			JsonFileName = "AzureDevOps.AgentPool.json";
			ResourceTypeName = "AgentPool";
        }
	)
	
	static [SubscriptionMapping] $SubscriptionMapping =	@{
		ClassName = "SubscriptionCore";
        JsonFileName = "SubscriptionCore.json";
		FixClassName = "SubscriptionCoreFix";
		FixFileName = "SubscriptionCoreFix.ps1";
	};
}

Invoke-Expression "enum ResourceTypeName { `r`n All `r`n $([SVTMapping]::GetResourceTypeEnumItems()) }";
