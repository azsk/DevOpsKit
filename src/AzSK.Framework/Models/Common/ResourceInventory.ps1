Set-StrictMode -Version Latest 
class ResourceInventory
{
    static [PSObject[]] $RawResources;
    static [PSObject[]] $FilteredResources;
    static [PSObject[]] $ResourcesWithTagMapping;

    static [void] FetchResources()
    {
        if($null -eq [ResourceInventory]::RawResources -or $null -eq [ResourceInventory]::FilteredResources)       
        {
            [ResourceInventory]::RawResources = Get-AzResource
            $supportedResourceTypes = [SVTMapping]::GetSupportedResourceMap()
            # Not considering nested resources to reduce complexity
            if(-not [string]::IsNullOrWhiteSpace([ResourceInventory]::RawResources))
            {
                [ResourceInventory]::FilteredResources = [ResourceInventory]::RawResources | Where-Object { $supportedResourceTypes.ContainsKey($_.ResourceType.ToLower()) }        
            }
            else 
            {
                [ResourceInventory]::FilteredResources = $null;
            }
        }                      
    }
    
	# This function is to save the result of resource to rg tag mapping that is done while sending the ResourceInventory telemetry event.
    static [void] SetResourceToTagMapping($resourceDetails)
    {
        if($null -eq [ResourceInventory]::ResourcesWithTagMapping)       
        {
            [ResourceInventory]::ResourcesWithTagMapping = $resourceDetails;
        }
    }

    static [void] Clear()
    {
        [ResourceInventory]::RawResources = $null;
        [ResourceInventory]::FilteredResources = $null;
		[ResourceInventory]::ResourcesWithTagMapping = $null;
    }

}