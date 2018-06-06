class LocalSubscriptionReport
{
	[LSRSubscription[]] $Subscriptions = @();
}

class LSRSubscription
{
	[string] $SubscriptionId = "";
	[string] $SubscriptionName = "";
	[LSRScanDetails] $ScanDetails = $null;
	[string] $SubscriptionMetadata = "";
	[string] $SchemaVersion = "";


	LSRSubscription() {
		$this.SchemaVersion = "1.0"
	}
}

class LSRScanDetails
{
	[LSRSubscriptionControlResult[]] $SubscriptionScanResult = @();
	[LSRResources[]] $Resources = @();
}

class LSRResources
{
	[string] $HashId = "";
	[string] $ResourceId = "";
	[DateTime] $LastEventOn = [Constants]::AzSKDefaultDateTime;
	[DateTime] $FirstScannedOn = [Constants]::AzSKDefaultDateTime;
	
	[string] $ResourceGroupName = "";
	[string] $ResourceName = "";
	[string] $ResourceMetadata = "";
	[string] $FeatureName = "";

	[LSRResourceScanResult[]] $ResourceScanResult = @();
}
 
class LSRControlResultBase 
{
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

	#Tracking information
	[DateTime] $LastResultTransitionOn = [Constants]::AzSKDefaultDateTime;
	[DateTime] $LastScannedOn = [Constants]::AzSKDefaultDateTime;
	[DateTime] $FirstScannedOn = [Constants]::AzSKDefaultDateTime;
	[DateTime] $FirstFailedOn = [Constants]::AzSKDefaultDateTime;
	[DateTime] $FirstAttestedOn = [Constants]::AzSKDefaultDateTime;
	[int] $AttestationCounter;

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
}

class LSRSubscriptionControlResult : LSRControlResultBase {
	[SubscriptionScanKind] $ScanKind;
}

class LSRResourceScanResult : LSRControlResultBase {
	[ServiceScanKind] $ScanKind;
	[string] $ChildResourceName = "";
}