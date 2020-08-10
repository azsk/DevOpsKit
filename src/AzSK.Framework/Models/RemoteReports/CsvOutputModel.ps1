Set-StrictMode -Version Latest

class CsvOutputItem
{
    #Fields from JSON
    [string] $ControlID = ""
    [string] $Status = ""
    [string] $FeatureName = ""
    [string] $ResourceGroupName = ""
    [string] $ResourceName = ""
    [string] $ChildResourceName = ""
    [string] $ControlSeverity = ""
    [string] $IsBaselineControl = ""
    [string] $IsPreviewBaselineControl = ""
    #Changes for compliance table dependency removal
    #removing IsControlInGrace from csv output
	#[string] $IsControlInGrace=""
    [string] $SupportsAutoFix = ""    
    [string] $Description = ""
	[string] $ActualStatus = ""
    [string] $AttestedSubStatus = ""
    [string] $AttestedOn=""
    [string] $AttestationExpiryDate = "" 
	[string] $AttestedBy = ""
	[string] $AttesterJustification = ""
    [string] $Recommendation = ""
	[string] $ResourceId = ""
    [string] $DetailedLogFile = ""
	[string] $UserComments = ""
}