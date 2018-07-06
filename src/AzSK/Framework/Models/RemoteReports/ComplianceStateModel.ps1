Set-StrictMode -Version Latest

class ComplianceStateTableEntity
{
	#partition key = resourceid/subscriptionid
	[string] $PartitionKey; 
	#row key = controlid
    [string] $RowKey;
    [string] $HashId = "";
	[string] $ResourceId = "";
	[DateTime] $LastEventOn = [Constants]::AzSKDefaultDateTime;
	[string] $ResourceGroupName = "";
	[string] $ResourceName = "";
	[string] $ResourceMetadata = "";
    [string] $FeatureName = "";
    
    #Default control values
	[string] $ControlId = "";
    [string] $ControlIntId = "";
	[DateTime] $ControlUpdatedOn = [Constants]::AzSKDefaultDateTime;
    [ControlSeverity] $ControlSeverity = [ControlSeverity]::High
    [VerificationResult] $ActualVerificationResult= [VerificationResult]::Manual;
    [AttestationStatus] $AttestationStatus = [AttestationStatus]::None;
    [VerificationResult] $VerificationResult = [VerificationResult]::Manual;
    [string] $AttestedBy = "";
	[DateTime] $AttestedDate = [Constants]::AzSKDefaultDateTime;
    [string] $Justification = "";
    [string] $PreviousVerificationResult = [VerificationResult]::Manual;
	[PSObject] $AttestationData;
	[bool] $IsBaselineControl;
	[bool] $HasOwnerAccessTag;

	#Tracking information
	[DateTime] $LastResultTransitionOn = [Constants]::AzSKDefaultDateTime;
	[DateTime] $LastScannedOn = [Constants]::AzSKDefaultDateTime;
	[DateTime] $FirstScannedOn = [Constants]::AzSKDefaultDateTime;
	[DateTime] $FirstFailedOn = [Constants]::AzSKDefaultDateTime;
	[DateTime] $FirstAttestedOn = [Constants]::AzSKDefaultDateTime;
	[int] $AttestationCounter = 0;

	#Other  information
	[string] $ScannedBy = "";
	[ScanSource] $ScanSource;
	[string] $ScannerModuleName = "";
	[string] $ScannerVersion = "";
	[string] $ControlVersion = "";
	[bool] $IsLatestPSModule;
	[bool] $HasRequiredPermissions;
	[bool] $HasAttestationWritePermissions;
	[bool] $HasAttestationReadPermissions;


	[string] $UserComments = "";
    [string] $Metadata = "";
    
    [ServiceScanKind] $ScanKind = [ServiceScanKind]::Partial;
	[string] $ChildResourceName = "";
}