Set-StrictMode -Version Latest
enum VerificationResult
{
	Passed 
    Failed
    Verify
    Manual
	RiskAck
	Error
	Disabled
	Exception
	Remediate
	Exempted
	NotScanned
}

enum AttestationStatus
{
	None
    NotAnIssue
	NotFixed
	WillNotFix
	WillFixLater
}

enum AttestControls 
{
	None
	All
	AlreadyAttested
	NotAttested
}

enum MessageType
{
    Critical
    Error
    Warning
    Info
    Update
    Deprecated
	Default
}

enum ControlSeverity
{
	Critical
	High
	Medium
	Low
}

enum Environment
{
	SDL
	CICD
	CC
}

enum ScanSource
{
    SpotCheck
    VSO
    Runbook
}

enum FeatureGroup
{
	Unknown
    Subscription
    Service
}

enum ServiceScanKind
{
    Partial
    ResourceGroup
    Subscription
}

enum SubscriptionScanKind
{
    Partial
    Complete
}

enum OMSInstallationOption
{
	All
	Queries
	Alerts
	SampleView
	GenericView
}

enum GeneratePDF
{
	None
	Landscape
	Portrait
}

enum CAReportsLocation
{
	CentralSub
	IndividualSubs	
}

enum InfoType
{
	SubscriptionInfo
	ControlInfo
	HostInfo
	AttestationInfo
}

enum AutoUpdate
{
	On
	Off
	NotSet
}

enum StorageContainerType
{
	AttestationDataContainer
	CAMultiSubScanConfigContainer
	ScanProgressSnapshotsContainer
	CAScanOutputLogsContainer
}

enum TertiaryBool
{	
	False
	True
	NotSet
}

enum ComparisionType
{
	NumLesserOrEqual
}
