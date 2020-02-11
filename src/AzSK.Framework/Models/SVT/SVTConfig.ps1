Set-StrictMode -Version Latest 
class SVTConfig
{
    [string] $FeatureName = ""
    [string] $Reference = ""
    [bool] $IsMaintenanceMode 
    [ControlItem[]] $Controls = @();

    static [SVTConfig] LoadServerConfigFile([string] $fileName, [bool] $useOnlinePolicyStore, [string] $onlineStoreUri, [bool] $enableAADAuthForOnlinePolicyStore)
    {
        return [SVTConfig]([ConfigurationHelper]::LoadServerConfigFile($fileName, $useOnlinePolicyStore, $onlineStoreUri, $enableAADAuthForOnlinePolicyStore));
    }

    static [SVTConfig] LoadServerFileRaw([string] $fileName, [bool] $useOnlinePolicyStore, [string] $onlineStoreUri, [bool] $enableAADAuthForOnlinePolicyStore)
    {
        return [SVTConfig]([ConfigurationHelper]::LoadServerFileRaw($fileName, $useOnlinePolicyStore, $onlineStoreUri, $enableAADAuthForOnlinePolicyStore));
    }
}

class ControlItem
{
    #Fields from JSON
    [string] $ControlID = ""
    [string] $Id = ""
    [string] $ControlSeverity = [ControlSeverity]::High
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
    #add PreviewBaselineFlag
    [bool] $IsPreviewBaselineControl;
    [DateTime] $GraceExpiryDate
    [int] $NewControlGracePeriodInDays
    [int] $AttestationPeriodInDays
    [string[]] $ValidAttestationStates
    [string] $PolicyDefinitionGuid 
    [string] $PolicyDefnResourceIdSuffix
    [string] $policyDefinitionId

    # Parameters to prevent attestation drift 
    [bool] $IsAttestationDriftExpected = $false
    [OnAttestationDrift] $OnAttestationDrift = $null
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

class OnAttestationDrift
{
    [string] $ApplyToVersionsUpto;
    [int] $OverrideAttestationExpiryInDays = 90;
    [ActionOnAttestationDrift] $ActionOnAttestationDrift = [ActionOnAttestationDrift]::None;
}

<#
    .Description
    CheckIfSubset - Pass if all the objects in current state data are present in attested state data (retrieved from storage)
    RespectExistingAttestationExpiryPeriod - Pass if attested with older version
    OverrideAttestationExpiryPeriod - Override existing attestation expiry period
    CheckSelectPropertiesInDataObject - Match only a selected set of properties in the state data object. These properties are defined in control json file

#>

enum ActionOnAttestationDrift
{
    CheckIfSubset
    RespectExistingAttestationExpiryPeriod 
    OverrideAttestationExpiryPeriod
    CheckOnlySelectPropertiesInDataObject
    None
}