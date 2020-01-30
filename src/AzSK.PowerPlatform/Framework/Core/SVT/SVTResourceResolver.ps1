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
	[string] $ExcludeResourceGroupWarningMessage=[string]::Empty
	[SVTResource[]] $SVTResources = @();
    [int] $SVTResourcesFoundCount=0;
    
    [string] $ResourcePath;
    [string] $environmentName;
    hidden [string[]] $ProjectNames = @();
    hidden [string[]] $BuildNames = @();
    hidden [string[]] $ReleaseNames = @();
    hidden [string[]] $AgentPools = @();
    SVTResourceResolver([string]$environmentName,$ScanAllArtifacts): Base($environmentName)
	{
        $this.environmentName = $environmentName

        if($ScanAllArtifacts)
        {
        <#           
            $this.ProjectNames = "*"
            $this.BuildNames = "*"
            $this.ReleaseNames = "*"
            $this.AgentPools = "*"
        #>
        }        
    }

    [void] LoadAzureResources()
	{
        $svtResource = [SVTResource]::new();
        $svtResource.ResourceName = $this.environmentName;
        $svtResource.ResourceType = "PowerPlatform.Environment";
        $svtResource.ResourceId = "Organization/$($this.environmentName)/Environment"
        $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKPowerPlatformResourceMappping |
                                        Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                        Select-Object -First 1)
        $this.SVTResources +=$svtResource
           
        $this.SVTResourcesFoundCount = $this.SVTResources.Count
    }
}