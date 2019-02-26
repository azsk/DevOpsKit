Set-StrictMode -Version Latest

class AttestationOptions
{
	[AttestControls] $AttestControls = [AttestControls]::None
	[bool] $IsBulkClearModeOn = $false;
	[string] $JustificationText;
	[AttestationStatus] $AttestationStatus;
}
