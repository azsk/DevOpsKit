Set-StrictMode -Version Latest 
class SVTConfig
{
    [string] $FeatureName = ""
    [string] $Reference = ""
    [bool] $IsManintenanceMode 
    [ControlItem[]] $Controls = @();

	static [SVTConfig] LoadServerConfigFile([string] $fileName, [bool] $useOnlinePolicyStore, [string] $onlineStoreUri, [bool] $enableAADAuthForOnlinePolicyStore)
    {
		return [SVTConfig]([ConfigurationHelper]::LoadServerConfigFile($fileName, $useOnlinePolicyStore, $onlineStoreUri, $enableAADAuthForOnlinePolicyStore));
    }
}

class ControlItem
{
    #Fields from JSON
    [string] $ControlID = ""
    [string] $Id = ""
    [ControlSeverity] $ControlSeverity = [ControlSeverity]::High
    [string] $Description = ""
    [string] $Automated = ""
    [string[]] $Tags = @()
    [bool] $Enabled   
    hidden [string] $MethodName = ""   
    [string] $Recommendation = ""   
    [string] $Rationale = ""   
    hidden [string[]] $DataObjectProperties = @()
	hidden [string] $AttestComparisionType = ""
    hidden [FixControl] $FixControl = $null;
	[int] $AttestationExpiryPeriodInDays
	[bool] $IsBaselineControl
}

class FixControl
{
    [string] $FixMethodName = ""
    [FixControlImpact] $FixControlImpact = [FixControlImpact]::High;
    [PSObject] $Parameters = $null;
}

enum FixControlImpact
{
	Critical
	High
	Medium
	Low
}
