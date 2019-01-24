Set-StrictMode -Version Latest 

class OldConstants
{
	static [string] $AttestationDataContainerName = "azsdk-controls-state"
	static [string] $CAMultiSubScanConfigContainerName = "azsdk-scan-objects"
	static [string] $CAScanProgressSnapshotsContainerName = "azsdk-controls-baseline"
	static [string] $CAScanOutputLogsContainerName= "azsdkexecutionlogs"
	static [string] $V1AlertRGName = "AzSDKAlertsRG";
	static [string] $AzSDKRGName = "AzSDKRG";
	static [string] $StorageAccountPreName = "azsdk";
	static [string] $SettingsFileName = "AzSdkSettings.json"
	static [string] $AutomationAccountName = "AzSDKContinuousAssurance";
	static [string] $AlertActionGroupName = "AzSDKAlertActionGroup"
	static [string] $CriticalAlertActionGroupName = "AzSDKCriticalAlertActionGroup"
	static [string] $AppFolderPath = [Constants]::AzSKAppFolderPath -replace [Constants]::NewModuleName,[Constants]::OldModuleName
	static [string] $AzSDKAlertsVersionTagName = "AzSDKAlertsVersion"
	static [string] $RunbookVersionTagName = "AzSDKCARunbookVersion"
}
