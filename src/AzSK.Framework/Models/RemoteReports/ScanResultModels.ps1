Set-StrictMode -Version Latest

class ScanInfoBase {
    [ScanInfoVersion] $ScanInfoVersion;
    [string] $SubscriptionId;
    [string] $SubscriptionName;
    [ScanSource] $Source;
    [string] $ScannerVersion;
    [string] $ControlVersion;
    [string] $Metadata;
	[bool] $HasAttestationWritePermissions = $false
	[bool] $HasAttestationReadPermissions = $false
	[bool] $IsLatestPSModule

    ScanInfoBase() {
        $this.ScanInfoVersion = [ScanInfoVersion]::V1
    }
}

class ControlResultBase {
    [string] $ControlId;
    [string] $ControlIntId;
    [string] $ControlSeverity;
    [VerificationResult] $ActualVerificationResult;
    [AttestationStatus] $AttestationStatus;
	[DateTime] $AttestedDate = [Constants]::AzSKDefaultDateTime;
    [VerificationResult] $VerificationResult;
	[bool] $HasRequiredAccess = $true;
    [string] $AttestedBy;
    [string] $Justification;
    [string] $AttestedState;
    [string] $CurrentState;
    [DateTime] $AttestationExpiryDate = [Constants]::AzSKDefaultDateTime;
    [bool] $IsBaselineControl;
    # add PreviewBaselineFlag
    [string] $UserComments;
    [bool] $IsPreviewBaselineControl;
	[bool] $HasOwnerAccessTag;
	[int] $MaximumAllowedGraceDays=0;
}

class SubscriptionControlResult : ControlResultBase {
}

class ServiceControlResult : ControlResultBase {
    [bool] $IsNestedResource;
    [string] $NestedResourceName;
}

class SubscriptionScanInfo : ScanInfoBase {
    [SubscriptionScanKind] $ScanKind;
    [SubscriptionControlResult[]] $ControlResults;
}

class ServiceScanInfo : ScanInfoBase {
    [string] $Feature;
    [ServiceScanKind] $ScanKind;
    [string] $ResourceGroup;
    [string] $ResourceName;
    [string] $ResourceId;
    [ServiceControlResult[]] $ControlResults;
}

enum ScanInfoVersion {
    V1
}
