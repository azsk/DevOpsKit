Set-StrictMode -Version Latest
class FeatureFlight
{
    [string] $Version
	[Feature[]] $Features
}

class Feature
{
	[string] $Name;
	[string] $Description;
	[string[]] $Sources;
	[string[]] $EnabledForSubs;
	[string[]] $DisabledForSubs;
	[bool] $UnderPreview;
	[bool] $IsEnabled;
}
