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
    [string] $ControlSeverity = ([ControlSeverity]::High).ToString();
    [string] $ActualVerificationResult= ([VerificationResult]::Manual).ToString();
    [string] $AttestationStatus = ([AttestationStatus]::None).ToString();
    [string] $VerificationResult = ([VerificationResult]::Manual).ToString();
    [string] $AttestedBy = "";
	[string] $AttestedDate = [Constants]::AzSKDefaultDateTime;
    [string] $Justification = "";
    [string] $PreviousVerificationResult = ([VerificationResult]::Manual).ToString();
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
	[string] $ScanSource;
	[string] $ScannerModuleName = "";
	[string] $ScannerVersion = "";
	[bool] $IsLatestPSModule;
	[bool] $HasRequiredPermissions;
	[bool] $HasAttestationWritePermissions;
	[bool] $HasAttestationReadPermissions;
	[string] $UserComments = "";    
	[string] $ChildResourceName = "";
	[bool] $IsActive = $true;

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