﻿Set-StrictMode -Version Latest 
class Constants
{
    #All constant used across all modules Defined Here.
    static [string] $DoubleDashLine    = "================================================================================"
    static [string] $HashLine          = "################################################################################"
	static [string] $GTLine          =   ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    static [string] $SingleDashLine    = "--------------------------------------------------------------------------------"
    static [string] $UnderScoreLineLine= "________________________________________________________________________________"
    static [string] $RemediationMsg = "** Next steps **`r`n" + 
"Look at the individual control evaluation status in the CSV file.`r`n" +
"        a) If the control has passed, no action is necessary.`r`n" +
"        b) If the control has failed, look at the control evaluation detail in the LOG file to understand why.`r`n" +
"        c) If the control status says 'Verify', it means that human judgement is required to determine the final control status. Look at the control evaluation output in the LOG file to make a determination.`r`n" +
"        d) If the control status says 'Manual', it means that AzSK (currently) does not cover the control via automation OR AzSK is not able to fetch the data. You need to manually implement/verify it.`r`n" +
"`r`nNote: The 'Recommendation' column in the CSV file provides basic (generic) guidance that can help you fix a failed control. You can also use standard Azure product documentation. You should carefully consider the implications of making the required change in the context of your application. `r`n"

    static [string] $RemediationMsgForARMChekcer = "** Next steps **`r`n" + 
"Look at the individual control evaluation status in the CSV file.`r`n" +
"        a) If the control has passed, no action is necessary.`r`n" +
"        b) If the control has failed, look at the control evaluation detail in the CSV file (LineNumber, ExpectedValue, CurrentValue, etc.) and fix the issue.`r`n" +
"        c) If the control status says 'Skipped', it means that you have chosen to skip certain controls using the '-SkipControlsFromFile' parameter.`r`n" 


	static [string] $DefaultInfoCmdMsg = "This command provides overall information about different components of the AzSK which includes subscription information, security controls information, attestation information, host information. 'Get-AzSKInfo' command can be used with 'InfoType' parameter to fetch information.`r`n" + 
					"`r`nFollowing InfoType parameter values are currently supported by Get-AzSKInfo cmdlet.`r`n" +
					"`tSubscriptionInfo : To get version details about different component of AzSK configured in Subscription.`r`n" +
					"`tControlInfo      : To get baseline, severity, description, rationale etc information about security controls.`r`n" +
					"`tAttestationInfo  : To get statistics, attestation justification, expiry etc information about controls attestation.`r`n" +
					"`tHostInfo         : To get information about machine details.`r`n" +
					"`r`n`r`nExamples:`r`n" +
					"`tGet-AzSKInfo -InfoType SubscriptionInfo -SubscriptionId <YourSubscriptionId> `r`n" +
					"`tGet-AzSKInfo -InfoType ControlInfo -ResourceTypeName All -UseBaselineControls `r`n" +
					"`tGet-AzSKInfo -InfoType AttestationInfo -SubscriptionId <YourSubscriptionId> -ResourceTypeName All -UseBaselineControls `r`n" +
					"`tGet-AzSKInfo -InfoType HostInfo `r`n";

	static [string] $DefaultControlInfoCmdMsg = "Run 'Get-AzSKInfo' command with below combination of parameter to get information about Azure services security control(s).`r`n`r`n" + 
					"   All controls                          : Get-AzSKInfo -InfoType ControlInfo `r`n" +
					"   Baseline controls information         : Get-AzSKInfo -InfoType ControlInfo -UseBaselineControls `r`n" +
					"   Controls for specific resource type   : Get-AzSKInfo -InfoType ControlInfo -ResourceTypeName AppService `r`n" +
					"   Controls with specific severity       : Get-AzSKInfo -InfoType ControlInfo -ControlSeverity 'High' `r`n" +
					"   Controls with specific tag(s)         : Get-AzSKInfo -InfoType ControlInfo -FilterTags 'Automated, FunctionApp' `r`n" +
					"   Controls with specific keyword        : Get-AzSKInfo -InfoType ControlInfo -ControlIdContains 'AppService_AuthZ_' `r`n" +
					"   Control(s) with specific controlId(s) : Get-AzSKInfo -InfoType ControlInfo -ResourceTypeName AppService -ControlIds 'Azure_AppService_AuthZ_Grant_Min_RBAC_Access, Azure_AppService_DP_Use_CNAME_With_SSL'  `r`n" +
					"   Get information on PS console         : Use any of above command with additional -Verbose argument`r`n";

    static [string] $OfflineModeWarning = "Running in offline policy mode. Commands will run against local JSON files!"
	#Constants for AzSKConfig
	   static [string] $AutomationAccount = "AzSKContinuousAssurance"
       static [string] $RunbookName = "Continuous_Assurance_Runbook"
	   static [string] $ScheduleName = "CA_Scan_Schedule"
	   static [string] $connectionAssetName = "AzureRunAsConnection"
	   #static [string] $AzSKRGName = "AzSKRG"
	   static [string] $SupportDL = "azsksupext@microsoft.com"
	   static [string] $CICDShortLink = "https://aka.ms/devopskit/cicd"

	#Constants for SVTs
    static [string] $ModuleStartHeading = [Constants]::DoubleDashLine +
    "`r`nStarting analysis: [FeatureName: {0}] [ResourceGroupName: {1}] [ResourceName: {2}] `r`n" + [Constants]::SingleDashLine
	 static [string] $ModuleStartHeadingSub = [Constants]::DoubleDashLine +
    "`r`nStarting analysis: [FeatureName: {0}] [SubscriptionName: {1}] [SubscriptionId: {2}] `r`n" + [Constants]::SingleDashLine
    static [string] $AnalysingControlHeading =  "Checking: [{0}]-[{1}]"
	static [string] $AnalysingControlHeadingSub =  "Checking: [{0}]-[{1}]"
    static [string] $CompletedAnalysis = [Constants]::SingleDashLine + "`r`nCompleted analysis: [FeatureName: {0}] [ResourceGroupName: {1}] [ResourceName: {2}] `r`n" + [Constants]::DoubleDashLine
    static [string] $CompletedAnalysisSub = [Constants]::SingleDashLine + "`r`nCompleted analysis: [FeatureName: {0}] [SubscriptionName: {1}] [SubscriptionId: {2}] `r`n" + [Constants]::DoubleDashLine
	static [string] $PIMAPIUri="https://api.azrbac.mspim.azure.com/api/v2/privilegedAccess/azureResources/resources";
	#Constants for Attestation
	static [string] $ModuleAttestStartHeading = [Constants]::DoubleDashLine +
    "`r`nInfo: Starting attestation [{3}/{4}]- [FeatureName: {0}] [ResourceGroupName: {1}] [ResourceName: {2}] `r`n" + [Constants]::SingleDashLine
	 static [string] $ModuleAttestStartHeadingSub = [Constants]::DoubleDashLine +
    "`r`nInfo: Starting attestation - [FeatureName: {0}] [SubscriptionName: {1}] [SubscriptionId: {2}] `r`n" + [Constants]::SingleDashLine
    static [string] $CompletedAttestAnalysis = [Constants]::SingleDashLine + "`r`nCompleted attestation: [FeatureName: {0}] [ResourceGroupName: {1}] [ResourceName: {2}] `r`n" + [Constants]::DoubleDashLine
    static [string] $CompletedAttestAnalysisSub = [Constants]::SingleDashLine + "`r`nCompleted attestation: [FeatureName: {0}] [SubscriptionName: {1}] [SubscriptionId: {2}] `r`n" + [Constants]::DoubleDashLine
	static [System.Version] $AzSKCurrentModuleVersion=[System.Version]::new()
	static [string] $AzSKModuleName = "AzSK";
	static [string] $AttestationDataContainerName = "attestation-data"
	static [string] $CAMultiSubScanConfigContainerName = "ca-multisubscan-config"
	static [string] $CAScanProgressSnapshotsContainerName = "ca-scan-checkpoints"
	static [string] $CAScanOutputLogsContainerName= "ca-scan-logs"
	static [string] $ResourceScanTrackerBlobName = "ResourceScanTracker.json"
	static [string] $ResourceScanTrackerCMBlobName = "ResourceScanTracker_CentralMode.json"
	static [hashtable] $AttestationStatusHashMap = @{
			[AttestationStatus]::NotAnIssue		="1";
			[AttestationStatus]::WillNotFix		="2";
			[AttestationStatus]::WillFixLater	="3";
			[AttestationStatus]::NotApplicable	="4";
			[AttestationStatus]::StateConfirmed ="5";
	}

	static [string] $StorageAccountPreName= "azsk"
	static [string] $AzSKAppFolderPath = $Env:LOCALAPPDATA + "\Microsoft\" + [Constants]::AzSKModuleName
	static [string] $AzSKLogFolderPath = $Env:LOCALAPPDATA + "\Microsoft\"
	static [string] $AzSKTempFolderPath = $env:TEMP + "\" + [Constants]::AzSKModuleName + "\"
	static [string] $AzSKExtensionsFolderPath = $Env:LOCALAPPDATA + "\Microsoft\" + [Constants]::AzSKModuleName + "\Extensions"
	static [string] $ARMManagementUri = "https://management.azure.com/";	
	static [string] $VersionCheckMessage = "A newer version of AzSK is available: Version {0} `r`nTo update, run the command below in a fresh PS window:`r`n" ;
	static [string] $VersionWarningMessage = ("Using the latest version ensures that AzSK security commands you run use the latest, most up-to-date controls. `r`nResults from the current version should not be considered towards compliance requirements.`r`n" + [Constants]::DoubleDashLine);
	static [string] $UsageTelemetryKey = "cf4c5e1a-d68d-4ea1-9901-37b67f58a192";
	static [string] $AzSKRGLocation = "eastus2";
	static [string] $OMSRequestURI = "https://management.azure.com/{0}?api-version=2015-03-20";
	static [string] $NewStorageSku = "Standard_LRS";
	static [string] $NewStorageKind = "BlobStorage";
	static [string] $ARMControlsFileURI = "https://azsdkossep.azureedge.net/1.0.0/ARMControls.json";
	static [string] $RecommendationURI = "https://azsdkossep.azureedge.net/recmnds/r.json ";
	#V1 alert RG name constant is temporary and added for backward compatibility	
	static [string] $AlertActionGroupName = "AzSKAlertActionGroup"
	static [string] $CriticalAlertActionGroupName = "AzSKCriticalAlertActionGroup"
	static [string] $ResourceDeploymentActionGroupName = "ResourceDeploymentActionGroup"

	# Append recommendation when control require elevated permission
	static [string] $RequireOwnerPermMessage = "(The status for this control has been marked as 'Manual' because elevated (Co-Admin/Owner/Contributor) permission is required to check security configuration for this resource. You can re-run the control with the appropriate privilege.) "
	static [string] $OwnerAccessTagName = "OwnerAccess"

	static [string] $BlankSubscriptionId = "00000000-0000-0000-0000-000000000000"
	static [string] $BlankSubscriptionName = "AzSK Empty Subscription"
	static [string] $BlankScope = "/subscriptions/00000000-0000-0000-0000-000000000000";

	static [string] $CentralRBACVersionTagName = "CentralRBACVersion"
	static [string] $DeprecatedRBACVersionTagName = "DeprecatedRBACVersion"
	static [string] $ARMPolicyConfigVersionTagName = "ARMPolicyConfigVersion"
	static [string] $AzSKAlertsVersionTagName = "AzSKAlertsVersion"
	static [string] $SecurityCenterConfigVersionTagName = "SecurityCenterConfigVersion"
	static [string] $NoActionRequiredMessage ="No Action Required"
	static [string] $PolicyMigrationTagName = "PolicyMigratedOn"
	static [string] $AlertRunbookName= "Alert_Runbook"
	static [string] $Alert_ResourceCreation_Runbook= "Continuous_Assurance_ScanOnTrigger_Runbook"
	static [string] $AutomationWebhookName="WebhookForAlertRunbook"
	static [string] $AutomationAccountName="AzSKContinuousAssurance"
	static [int] $AlertWebhookUriExpiryInDays = 60	

	static [int] $DefaultControlExpiryInDays = 90
	static [int] $PartialScanMaxRetryCount = 3
	static [string] $NewModuleName = "AzSK"
	static [string] $OldModuleName = "AzSDK"

	#CA variables names
	static [string] $AppResourceGroupNames = "AppResourceGroupNames"
	static [string] $ReportsStorageAccountName = "ReportsStorageAccountName"
	static [string] $OMSWorkspaceId = "OMSWorkspaceId"
	static [string] $OMSSharedKey = "OMSSharedKey"
	static [string] $AltOMSWorkspaceId = "AltOMSWorkspaceId"
	static [string] $AltOMSSharedKey = "AltOMSSharedKey"
	static [string] $WebhookUrl = "WebhookUrl"
	static [string] $WebhookAuthZHeaderName = "WebhookAuthZHeaderName"
	static [string] $WebhookAuthZHeaderValue = "WebhookAuthZHeaderValue"
	static [string] $DisableAlertRunbook = "DisableAlertRunbook"
	static [string] $CATargetSubsBlobName= "TargetSubs.json"
	static [string] $CoAdminElevatePermissionMsg = "(If you are 'Owner' then please elevate to 'Co-Admin' in the portal and re-run in a *fresh* PS console.)"

	static [string] $CommandNameChangeWarning = "The command {0} shall be renamed to {1} in a future release ('SDK' shall be replaced with 'SK').";
	static [string] $MultipleModulesWarning =  "Found multiple modules ({0} and {1}) loaded in the PS session.`r`n"+
			"Stopping cmdlet execution.`r`n"+
			"Recommendation: Please start a fresh PS session and run 'Import-Module {2}' first to avoid getting into this situation.`r`n"

	#Constants for Org Policy
	static [string] $OrgPolicyTagPrefix = "AzSKOrgName_"
	static [int] $SASTokenExpiryReminderInDays = 30
	# Local Subscription Report Constants
	#static [string] $ComplianceReportContainerName = "compliance-state"
	static [string] $ComplianceReportTableName = "ComplianceState"
	static [DateTime] $AzSKDefaultDateTime = '1900-01-01T00:00:00'
	static [int] $ControlResultComplianceInDays = 3
	static [string] $ComplianceReportPath = [Constants]::AzSKAppFolderPath + "\TempState\ComplianceData"

	static [string] $ServerConfigMetadataFileName = "ServerConfigMetadata.json"

	static [void] SetAzSKModuleName($moduleName)
	{
		if(-not [string]::IsNullOrWhiteSpace($moduleName))
		{
			[Constants]::AzSKModuleName = $moduleName.Replace("azsk","AzSK");
			[Constants]::AzSKAppFolderPath = $Env:LOCALAPPDATA + "\Microsoft\" + [Constants]::AzSKModuleName
			[Constants]::AzSKTempFolderPath = $env:TEMP + "\" + [Constants]::AzSKModuleName + "\"
		}
	}
	static [void] SetAzSKCurrentModuleVersion($moduleVersion)
	{
		if(-not [string]::IsNullOrWhiteSpace($moduleVersion))
		{
			[Constants]::AzSKCurrentModuleVersion = $moduleVersion;
		}
	}
}
