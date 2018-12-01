Set-StrictMode -Version Latest

class AzureDevOpsResourceResolver: Resolver
{
    [SVTResource[]] $SVTResources = @();
    [string] $ResourcePath;
    
    AzureDevOpsResourceResolver([string]$subscriptionId): Base($subscriptionId)
	{
   
    }

    [void] LoadAzureResources()
	{
        
        $resources= "SafetiVSO"
        $resources | ForEach-Object {
            $resource = $_
            $svtResource = [SVTResource]::new();
            $svtResource.ResourceName = "";
            $svtResource.ResourceType = "ServiceEndpoint";
            $svtResource.ResourceId = "Organization/ServiceEndpoint/"
            $svtResource.ResourceTypeMapping = ([SVTMapping]::Mapping |
											Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
											Select-Object -First 1)
            $this.SVTResources +=$svtResource
        }
    }
}