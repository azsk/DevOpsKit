Set-StrictMode -Version Latest
class SVTMapping
{

	hidden static [hashtable] $SupportedResourceMap = $null;

	static [string] GetResourceTypeEnumItems()
	{
		return ([SVTMapping]::AzSKPowerPlatformResourceMappping |
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

    static [ResourceTypeMapping[]] $AzSKPowerPlatformResourceMappping = (
	[ResourceTypeMapping]@{
            ResourceType = "PowerPlatform.Tenant";
            JsonFileName = "PowerPlatform.Tenant.json";
            ClassName = "Tenant";
            ResourceTypeName = "Tenant";            
        },
        [ResourceTypeMapping]@{
            ResourceType = "PowerPlatform.Environment";
	    ClassName = "Environment";
	    JsonFileName = "PowerPlatform.Environment.json";
	    ResourceTypeName = "Environment";
        }
	)
}

Invoke-Expression "enum ResourceTypeName { `r`n All `r`n $([SVTMapping]::GetResourceTypeEnumItems()) }";
