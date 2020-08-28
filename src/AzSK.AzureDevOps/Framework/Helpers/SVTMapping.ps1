Set-StrictMode -Version Latest
class SVTMapping
{

	hidden static [hashtable] $SupportedResourceMap = $null;

	static [string] GetResourceTypeEnumItems()
	{
		return ([SVTMapping]::AzSKADOResourceMapping |
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
            ResourceType = "ADO.Organization";
            JsonFileName = "ADO.Organization.json";
            ClassName = "Organization";
            ResourceTypeName = "Organization";            
        }
    );

    static [ResourceTypeMapping[]] $AzSKADOResourceMapping = (
		[ResourceTypeMapping]@{
            ResourceType = "ADO.Organization";
            JsonFileName = "ADO.Organization.json";
            ClassName = "Organization";
            ResourceTypeName = "Organization";            
        },
        [ResourceTypeMapping]@{
            ResourceType = "ADO.Project";
			ClassName = "Project";
			JsonFileName = "ADO.Project.json";
			ResourceTypeName = "Project";
        },
        [ResourceTypeMapping]@{
            ResourceType = "ADO.User";
			ClassName = "User";
			JsonFileName = "ADO.User.json";
			ResourceTypeName = "User";
        },
        [ResourceTypeMapping]@{
            ResourceType = "ADO.Build";
			ClassName = "Build";
			JsonFileName = "ADO.Build.json";
			ResourceTypeName = "Build";
        },
        [ResourceTypeMapping]@{
            ResourceType = "ADO.Release";
			ClassName = "Release";
			JsonFileName = "ADO.Release.json";
			ResourceTypeName = "Release";
        },
        [ResourceTypeMapping]@{
            ResourceType = "ADO.ServiceConnection";
			ClassName = "ServiceConnection";
			JsonFileName = "ADO.ServiceConnection.json";
			ResourceTypeName = "ServiceConnection";
        },
        [ResourceTypeMapping]@{
            ResourceType = "ADO.AgentPool";
			ClassName = "AgentPool";
			JsonFileName = "ADO.AgentPool.json";
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

Invoke-Expression "enum ResourceTypeName { `r`n All `r`n $([SVTMapping]::GetResourceTypeEnumItems())`r`n Org_Project_User `r`n Build_Release `r`n Build_Release_SvcConn_AgentPool_User `r`n}";
