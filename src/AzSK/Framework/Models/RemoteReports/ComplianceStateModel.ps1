Set-StrictMode -Version Latest

class ComplianceStateTableEntity
{
	#partition key = resourceid/subscriptionid
	[string] $PartitionKey; 
	#row key = controlid
    [string] $RowKey;
    [string] $HashId = "";
	[string] $ResourceId = "";
	[string] $LastEventOn = [Constants]::AzSKDefaultDateTime;
	[string] $ResourceGroupName = "";
	[string] $ResourceName = "";
	[string] $ResourceMetadata = "";
    [string] $FeatureName = "";
    
    #Default control values
	[string] $ControlId = "";
    [string] $ControlIntId = "";
	[string] $ControlUpdatedOn = [Constants]::AzSKDefaultDateTime;
    [ControlSeverity] $ControlSeverity = [ControlSeverity]::High
    [VerificationResult] $ActualVerificationResult= [VerificationResult]::Manual;
    [AttestationStatus] $AttestationStatus = [AttestationStatus]::None;
    [VerificationResult] $VerificationResult = [VerificationResult]::Manual;
    [string] $AttestedBy = "";
	[string] $AttestedDate = [Constants]::AzSKDefaultDateTime;
    [string] $Justification = "";
    [string] $PreviousVerificationResult = [VerificationResult]::Manual;
	[PSObject] $AttestationData;
	[bool] $IsBaselineControl;
	[bool] $HasOwnerAccessTag;

	#Tracking information
	[string] $LastResultTransitionOn = [Constants]::AzSKDefaultDateTime;
	[string] $LastScannedOn = [Constants]::AzSKDefaultDateTime;
	[string] $FirstScannedOn = [Constants]::AzSKDefaultDateTime;
	[string] $FirstFailedOn = [Constants]::AzSKDefaultDateTime;
	[string] $FirstAttestedOn = [Constants]::AzSKDefaultDateTime;
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

	[string] GetPartitionKey()
	{
		if([string]::IsNullOrWhiteSpace($this.HashId))
		{
			$partsToHash = $this.ResourceId;
			if(-not [string]::IsNullOrWhiteSpace($this.ChildResourceName))
			{
				$partsToHash = $partsToHash + ":" + $this.ChildResourceName;
			}
			$this.HashId = [Helpers]::ComputeHash($partsToHash.ToLower());
		}
		return $this.HashId;
	}
}