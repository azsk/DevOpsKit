Set-StrictMode -Version Latest

class SVTResourceResolver: AzSKRoot
{
    [string[]] $ResourceNames = @();
    [string] $ResourceType = "";
    [ResourceTypeName] $ResourceTypeName = [ResourceTypeName]::All;
	[Hashtable] $Tag = $null;
    [string] $TagName = "";
    [string[]] $TagValue = "";
	hidden [string[]] $ResourceGroups = @();
	[ResourceTypeName] $ExcludeResourceTypeName = [ResourceTypeName]::All;
	[string[]] $ExcludeResourceNames=@();
	[SVTResource[]] $ExcludedResources=@();
	[string] $ExcludeResourceWarningMessage=[string]::Empty
	[string[]] $ExcludeResourceGroupNames=@();
	[string[]] $ExcludedResourceGroupNames=@();
	[string] $ExcludeResourceGroupWarningMessage=[string]::Empty;
	[SVTResource[]] $SVTResources = @();
    [int] $SVTResourcesFoundCount;
    
    [string] $ResourcePath;
    [string] $SampleResourceName
    SVTResourceResolver([string]$sampleResourceName): Base($sampleResourceName)
	{
        $this.SampleResourceName = $sampleResourceName
    }

    [void] LoadResourcesForScan()
	{
        
        #Call APIS for Organization,User/Builds/Releases/ServiceConnections 
        #Select Org/User by default...
        $svtResource = [SVTResource]::new();
        $svtResource.ResourceName = $this.SampleResourceName;
        $svtResource.ResourceType = "X.SampleResource";
        $svtResource.ResourceId = "SampleResource/$($this.SampleResourceName)/"
        $svtResource.ResourceTypeMapping = ([SVTMapping]::XResourceMapping |
                                        Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                        Select-Object -First 1)
        $this.SVTResources +=$svtResource


        
        $this.SVTResourcesFoundCount = $this.SVTResources.Count
    
    }
}