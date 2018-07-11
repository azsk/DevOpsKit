Set-StrictMode -Version Latest 
class ResourceInventory
{
    static [PSObject[]] $RawResources;
    static [PSObject[]] $FilteredResources;    

    static [void] FetchResources([string] $CurrentSubscriptionId)
    {
        if($null -eq [ResourceInventory]::RawResources -or $null -eq [ResourceInventory]::FilteredResources)       
        {
            [ResourceInventory]::RawResources = Find-AzureRmResource
            $supportedResourceTypes = [SVTMapping]::GetSupportedResourceMap()
            # Not considering nested resources to reduce complexity
            [ResourceInventory]::FilteredResources = [ResourceInventory]::RawResources | Where-Object { $supportedResourceTypes.ContainsKey($_.ResourceType.ToLower()) }        
        }                      
    }

    static [void] Clear()
    {
        [ResourceInventory]::RawResources = $null;
        [ResourceInventory]::FilteredResources = $null;
    }

}