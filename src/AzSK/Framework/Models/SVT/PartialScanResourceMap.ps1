Set-StrictMode -Version Latest 
class PartialScanResourceMap
{
    [string] $Id
    [DateTime] $CreatedDate
    [PSObject] $ResourceMapTable    
}

class PartialScanResource
{
	[string] $Id
    [ScanState] $State
	[int] $ScanRetryCount
    [DateTime] $CreatedDate
	[DateTime] $ModifiedDate
}

enum ActiveStatus{
	NotStarted
	Yes
	No
}

enum ScanState{
	INIT
	COMP
	ERR
}