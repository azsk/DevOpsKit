class LocalSubscriptionReport
{
	[LSRSubscription[]] $Subscriptions;
}

class LSRSubscription
{
	[string] $SubscriptionId;
	[string] $SubscriptionName;
	[LSRScanDetails] $LSRScanDetails;
	[string] $SubscriptionMetadata;
	[string] $SchemaVersion;


	LSRSubscription() {
		$this.SchemaVersion = "1.0"
	}
}

class LSRScanDetails
{
	[LSRSubscriptionControlResult[]] $SubscriptionScanResult;
	[LSRResources[]] $Resources;
}

class LSRResources
{
	[string] $HashId;
	[string] $ResourceId;
	[DateTime] $LastEventOn;
	[DateTime] $FirstScannedOn;
	
	[string] $ResourceGroupName;
	[string] $ResourceName;
	[string] $ResourceMetadata;

	[LSRResourceScanResult[]] $ResourceScanResult;
}
 
class LSRControlResultBase 
{
    #Default control values
	[string] $ControlId;
    [string] $ControlIntId;
	[DateTime] $ControlUpdatedOn;
    [ControlSeverity] $ControlSeverity;
    [VerificationResult] $ActualVerificationResult;
    [AttestationStatus] $AttestationStatus;
    [VerificationResult] $VerificationResult;
    [string] $AttestedBy;
	[DateTime] $AttestedDate;
    [string] $Justification;
    [string] $PreviousVerificationResult;
	[PSObject] $AttestationData;

	#Tracking information
	[DateTime] $LastResultTransitionOn;
	[DateTime] $LastScannedOn;
	[DateTime] $FirstScannedOn;
	[DateTime] $FirstFailedOn;
	[DateTime] $FirstAttestedOn;
	[int] $AttestCounterInDays;

	#Other  information
	[string] $ScannedBy;
	[ScanSource] $ScanSource;
	[string] $ScannerModuleName;
	[string] $ScannerVersion;
	[string] $ControlVersion;
	[bool] $IsLatestPSModule;
	[bool] $HasRequiredPermissions;
	[bool] $HasAttestationWritePermissions;
	[bool] $HasAttestationReadPermissions;


	[string] $UserComments;
	[string] $Metadata;
}

class LSRSubscriptionControlResult : LSRControlResultBase {
	[SubscriptionScanKind] $ScanKind;
}

class LSRResourceScanResult : LSRControlResultBase {
	[ServiceScanKind] $ScanKind;
	[string] $ChildResourceName;    
}