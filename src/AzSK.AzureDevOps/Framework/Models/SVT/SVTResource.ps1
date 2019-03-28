Set-StrictMode -Version Latest 

class SubscriptionMapping
{    
	[string] $JsonFileName
    [string] $ClassName
    [string] $FixClassName = "";
    [string] $FixFileName = "";
}

class ResourceTypeMapping: SubscriptionMapping
{
    [string] $ResourceTypeName
    [string] $ResourceType
}

class SVTResource
{
	[string] $ResourceId = "";
	[string] $ResourceGroupName = "";
    [string] $ResourceName = ""; 
    [string] $Location = "";
    [string] $ResourceType = "";
	hidden [ResourceTypeMapping] $ResourceTypeMapping = $null;
}
