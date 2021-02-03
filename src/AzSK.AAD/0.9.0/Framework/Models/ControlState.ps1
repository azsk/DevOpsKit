Set-StrictMode -Version Latest 

class ControlState
{
	ControlState()
	{
		
	}

	ControlState([string] $ControlId, [string] $InternalId, [string] $ChildResourceName, [string] $ActualVerificationResult, [string] $Version)
	{
		$this.ControlId = $ControlId;
		$this.InternalId = $InternalId;
		$this.ChildResourceName = $ChildResourceName;
		$this.ActualVerificationResult = $ActualVerificationResult;
		#setting the effective control result default value actual. It would be reset once it is computed based on user input
		$this.EffectiveVerificationResult = $ActualVerificationResult;
		$this.Version = $Version;		
	}

	[string] $ControlId
	[string] $InternalId
	[string] $ResourceId
    [string] $HashId
	[StateData] $State	
	[string] $ChildResourceName
	[VerificationResult] $ActualVerificationResult
	[VerificationResult] $EffectiveVerificationResult
	[AttestationStatus] $AttestationStatus = [AttestationStatus]::None
	[string] $Version
}

class ControlStateIndexer
{
	[string] $ResourceId
	[string] $HashId
	[DateTime] $ExpiryTime
	[string] $AttestedBy
	[DateTime] $AttestedDate
	[string] $Version
}