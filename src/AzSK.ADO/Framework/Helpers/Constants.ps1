Set-StrictMode -Version Latest 
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
"        d) If the control status says 'Manual', it means that AzSK.ADO (currently) does not cover the control via automation OR AzSK.ADO is not able to fetch the data. You need to manually implement/verify it.`r`n" +
"`r`nNote: The 'Recommendation' column in the CSV file provides basic (generic) guidance that can help you fix a failed control. You can also use standard ADO product documentation. You should carefully consider the implications of making the required change in the context of your application. `r`n"

	static [string] $BugLogMsg="** Bugs have been logged as per below: ** `r`n"+
"	a) New bugs have been logged for fresh control failures.`r`n"+
"	b) For control failures for which bugs were already present, the respective bugs have been marked 'Active' `r`n"



    static [string] $RemediationMsgForARMChekcer = "** Next steps **`r`n" + 
"Look at the individual control evaluation status in the CSV file.`r`n" +
"        a) If the control has passed, no action is necessary.`r`n" +
"        b) If the control has failed, look at the control evaluation detail in the CSV file (LineNumber, ExpectedValue, CurrentValue, etc.) and fix the issue.`r`n" +
"        c) If the control status says 'Skipped', it means that you have chosen to skip certain controls using the '-SkipControlsFromFile' parameter.`r`n" 


	static [string] $DefaultInfoCmdMsg = "This command provides overall information about different components of the AzSK.ADO which includes subscription information, security controls information, attestation information, host information. 'Get-AzSKADOInfo' command can be used with 'InfoType' parameter to fetch information.`r`n" + 
					"`r`nFollowing InfoType parameter values are currently supported by Get-AzSKADOInfo cmdlet.`r`n" +
					"`tSubscriptionInfo : To get version details about different component of AzSK.ADO configured in Subscription.`r`n" +
					"`tControlInfo      : To get baseline, severity, description, rationale etc information about security controls.`r`n" +
					"`tAttestationInfo  : To get statistics, attestation justification, expiry etc information about controls attestation.`r`n" +
					"`tHostInfo         : To get information about machine details.`r`n" +
					"`r`n`r`nExamples:`r`n" +
					"`tGet-AzSKADOInfo -InfoType SubscriptionInfo -SubscriptionId <YourSubscriptionId> `r`n" +
					"`tGet-AzSKADOInfo -InfoType ControlInfo -ResourceTypeName All -UseBaselineControls `r`n" +
					"`tGet-AzSKADOInfo -InfoType AttestationInfo -SubscriptionId <YourSubscriptionId> -ResourceTypeName All -UseBaselineControls `r`n" +
					"`tGet-AzSKADOInfo -InfoType HostInfo `r`n";

	static [string] $DefaultControlInfoCmdMsg = "Run 'Get-AzSKADOInfo' command with below combination of parameter to get information about Azure services security control(s).`r`n`r`n" + 
					"   All controls                          : Get-AzSKADOInfo -InfoType ControlInfo `r`n" +
					"   Baseline controls information         : Get-AzSKADOInfo -InfoType ControlInfo -UseBaselineControls `r`n" +
					"   Controls for specific resource type   : Get-AzSKADOInfo -InfoType ControlInfo -ResourceTypeName AppService `r`n" +
					"   Controls with specific severity       : Get-AzSKADOInfo -InfoType ControlInfo -ControlSeverity 'High' `r`n" +
					"   Controls with specific tag(s)         : Get-AzSKADOInfo -InfoType ControlInfo -FilterTags 'Automated, FunctionApp' `r`n" +
					"   Controls with specific keyword        : Get-AzSKADOInfo -InfoType ControlInfo -ControlIdContains 'AppService_AuthZ_' `r`n" +
					"   Control(s) with specific controlId(s) : Get-AzSKADOInfo -InfoType ControlInfo -ResourceTypeName AppService -ControlIds 'Azure_AppService_AuthZ_Grant_Min_RBAC_Access, Azure_AppService_DP_Use_CNAME_With_SSL'  `r`n" +
					"   Get information on PS console         : Use any of above command with additional -Verbose argument`r`n";

    static [string] $OfflineModeWarning = "Running in offline policy mode. Commands will run against local JSON files!"
	#Constants for AzSKConfig
	static [string] $AzSKADORGName = "ADOScannerRG"
	static [string] $AzSKADORGLocation = "eastus2"

	static [string] $SupportDL = "AzSKADOSup@microsoft.com"

	
	#Constants for SVTs
	static [string] $ParentFolder = "Org_"
    static [string] $ModuleStartHeading = [Constants]::DoubleDashLine +
    "`r`nStarting analysis: [FeatureName: {0}] [ParentGroupName: {1}] [ResourceName: {2}] `r`n" + [Constants]::SingleDashLine
	 static [string] $ModuleStartHeadingSub = [Constants]::DoubleDashLine +
    "`r`nStarting analysis: [FeatureName: {0}] [OrgName: {1}] [OrgId: {2}] `r`n" + [Constants]::SingleDashLine
    static [string] $AnalysingControlHeading =  "Checking: [{0}]-[{1}]"
	static [string] $AnalysingControlHeadingSub =  "Checking: [{0}]-[{1}]"
    static [string] $CompletedAnalysis = [Constants]::SingleDashLine + "`r`nCompleted analysis: [FeatureName: {0}] [ParentGroupName: {1}] [ResourceName: {2}] `r`n" + [Constants]::DoubleDashLine
    static [string] $CompletedAnalysisSub = [Constants]::SingleDashLine + "`r`nCompleted analysis: [FeatureName: {0}] [OrgName: {1}] [OrgId: {2}] `r`n" + [Constants]::DoubleDashLine
	static [string] $PIMAPIUri="https://api.azrbac.mspim.azure.com/api/v2/privilegedAccess/azureResources/resources";
	#Constants for Attestation
	static [string] $ModuleAttestStartHeading = [Constants]::DoubleDashLine +
    "`r`nInfo: Starting attestation [{3}/{4}]- [FeatureName: {0}] [ParentGroupName: {1}] [ResourceName: {2}] `r`n" + [Constants]::SingleDashLine
	 static [string] $ModuleAttestStartHeadingSub = [Constants]::DoubleDashLine +
    "`r`nInfo: Starting attestation - [FeatureName: {0}] [OrgName: {1}] [OrgId: {2}] `r`n" + [Constants]::SingleDashLine
    static [string] $CompletedAttestAnalysis = [Constants]::SingleDashLine + "`r`nCompleted attestation: [FeatureName: {0}] [ParentGroupName: {1}] [ResourceName: {2}] `r`n" + [Constants]::DoubleDashLine
    static [string] $CompletedAttestAnalysisSub = [Constants]::SingleDashLine + "`r`nCompleted attestation: [FeatureName: {0}] [OrgName: {1}] [OrgId: {2}] `r`n" + [Constants]::DoubleDashLine
	static [System.Version] $AzSKCurrentModuleVersion=[System.Version]::new()
	static [string] $AzSKModuleName = "AzSK.ADO";
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
			[AttestationStatus]::ApprovedException ="4";
			[AttestationStatus]::NotApplicable	="5";
			[AttestationStatus]::StateConfirmed ="6";
			
	}

	#Ext Storage
	static [string] $StorageUri = "https://extmgmt.dev.azure.com/{0}/_apis/extensionmanagement/installedextensions/azsdktm/ADOSecurityScanner/Data/Scopes/Default/Current/Collections/{1}/Documents/{2}?api-version=5.1-preview.1" 

	static [string] $AttRepoStorageUri = "https://dev.azure.com/{0}/{1}/_apis/git/repositories/{2}/pushes?api-version=5.0" 
	static [string] $GetAttRepoStorageUri = "https://{0}.visualstudio.com/{1}/_apis/git/repositories/{2}/Items?path=%2F{3}&recursionLevel=0&includeContentMetadata=true&versionDescriptor.version={4}&versionDescriptor.versionOptions=0&versionDescriptor.versionType=0&includeContent=true&resolveLfs=true?api-version=4.1-preview.1" 
	static [string] $AutoUpdateMessage = "Auto-update for AzSK.ADO is currently not enabled for your machine."
	static [string] $AttestationRepo = "ADOScanner_Attestation"; 
	static [string] $AttestationBranch = "master"; 
	static [string] $OrgPolicyRepo = "ADOScanner_Policy_"; 
	static [string] $OrgAttPrjExtFile = "Org_Config";
	static [string] $ModuleAutoUpdateAvailableMsg = "A new version of AzSK.ADO is available. Starting the auto-update workflow...`nTo prepare for auto-update, please:`n`t a) Save your work from all active PS sessions including the current one and`n`t b) Close all PS sessions other than the current one. "; 

	static [string] $AttestedControlsScanMsg = "You are almost done...we will perform a quick scan of controls attested within the last 24 hrs so that the backend will get the latest control status."
	static [string] $LongRunningScanStopMsg = "`nThe set of parameters provided would result in scanning a large number of objects (> {0}). `nIf this is not what you intended, use a parameter set that would narrow down your target set. `nIf you would still like to scan all objects, rerun this command with the '-AllowLongRunningScan' switch.";
	static [string] $LongRunningScanStopByPolicyMsg = "`nScans involving larger number of project components is prohibited in your project by project administrator. `nContact project administrator to allow long running scan by setting flag 'IsAllowLongRunningScan' true.";
	static [string] $StorageAccountPreName= "azsk"
	static [string] $AzSKAppFolderPath = [Environment]::GetFolderPath('LocalApplicationData') + "/Microsoft/" + [Constants]::AzSKModuleName
	static [string] $AzSKLogFolderPath = [Environment]::GetFolderPath('LocalApplicationData') + "/Microsoft/"
	static [string] $AzSKTempFolderPath = [Environment]::GetFolderPath('LocalApplicationData') + "/Temp" + "/" + [Constants]::AzSKModuleName + "/"
	static [string] $AzSKExtensionsFolderPath = [Environment]::GetFolderPath('LocalApplicationData') + "/Microsoft/" + [Constants]::AzSKModuleName + "/Extensions"
	static [string] $ARMManagementUri = "https://management.azure.com/";	
	static [string] $VersionCheckMessage = "A newer version of AzSK.ADO is available: Version {0} `r`nTo update, run the command below in a fresh PS window:`r`n" ;
	static [string] $VersionWarningMessage = ("Using the latest version ensures that AzSK.ADO security commands you run use the latest, most up-to-date controls. `r`nResults from the current version should not be considered towards compliance requirements.`r`n" + [Constants]::DoubleDashLine);
	static [string] $UsageTelemetryKey = "59545085-0620-4106-a7bb-13ee2f5eb7a0";

	static [string] $LAWSRequestURI = "https://management.azure.com/{0}?api-version=2015-03-20";
	static [string] $NewStorageSku = "Standard_LRS";
	static [string] $NewStorageKind = "BlobStorage";
	static [string] $ARMControlsFileURI = "https://azsdkossepstaging.azureedge.net/1.0.0/ARMControls.json";
	static [string] $RecommendationURI = "https://azsdkossep.azureedge.net/recmnds/r.json ";
	static [string] $AttestationReadMsg = "`r`nControl results may not reflect attestation if you do not have permissions to read attestation data from "
	#V1 alert RG name constant is temporary and added for backward compatibility	
	static [string] $AlertActionGroupName = "AzSKAlertActionGroup"
	static [string] $CriticalAlertActionGroupName = "AzSKCriticalAlertActionGroup"
	static [string] $ResourceDeploymentActionGroupName = "ResourceDeploymentActionGroup"

	# Append recommendation when control require elevated permission
	static [string] $RequireOwnerPermMessage = "(The status for this control has been marked as 'Manual' because elevated (Co-Admin/Owner/Contributor) permission is required to check security configuration for this resource. You can re-run the control with the appropriate privilege.) "
	static [string] $OwnerAccessTagName = "OwnerAccess"

	static [string] $BlankSubscriptionId = "00000000-0000-0000-0000-000000000000"
	static [string] $BlankSubscriptionName = "DevOpsKitForX"
	static [string] $BlankScope = "/subscriptions/00000000-0000-0000-0000-000000000000";
	static [string] $DefaultAzureEnvironment = "AzureCloud";

	static [string] $NoActionRequiredMessage ="No Action Required"

	static [int] $DefaultControlExpiryInDays = 90
	static [int] $PartialScanMaxRetryCount = 3

	static [string] $CommandNameChangeWarning = "The command {0} shall be renamed to {1} in a future release ('SDK' shall be replaced with 'SK').";
	static [string] $MultipleModulesWarning =  "Found multiple modules ({0} and {1}) loaded in the PS session.`r`n"+
			"Stopping cmdlet execution.`r`n"+
			"Recommendation: Please start a fresh PS session and run 'Import-Module {2}' first to avoid getting into this situation.`r`n"

	#Constants for Org Policy
	static [string] $OrgPolicyTagPrefix = "AzSKOrgName_"
	static [int] $SASTokenExpiryReminderInDays = 30

	static [string] $InstallOrgPolicyInstructionMsg = "This command will perform 4 important operations. It will:`r`n" + 
					"   [1] Create resources needed to support org policy `r`n" +
					"   [2] Upload (default/base) policies to the policy server `r`n" +
					"   [3] Generate an org-specific installer ('iwr' command) for your org `r`n" +
					"   [4] Create a monitoring dashboard for AzSK.ADO setup/operational health across your org `r`n"
	static [string] $UpdateOrgPolicyInstructionMsg = "This command will perform 2 important operations. It will:`r`n" + 
	"   [1] Upload policies to the policy server `r`n" +
	"   [2] Generate an org-specific installer ('iwr' command) for your org `r`n"
	# Local Subscription Report Constants
	#static [string] $ComplianceReportContainerName = "compliance-state"
	static [string] $ComplianceReportTableName = "ComplianceState"
	static [DateTime] $AzSKDefaultDateTime = '1900-01-01T00:00:00'
	static [int] $ControlResultComplianceInDays = 3
	static [string] $ComplianceReportPath = [Constants]::AzSKAppFolderPath + "\TempState\ComplianceData"

	static [string] $ServerConfigMetadataFileName = "ServerConfigMetadata.json"


	#Constants for ADO
	static [string] $DefaultClientId = "872cd9fa-d31f-45e0-9eab-6e460a02d1f1"
	static [string] $DefaultReplyUri = "urn:ietf:wg:oauth:2.0:oob"
	static [string] $DefaultADOResourceId = "499b84ac-1321-427f-aa17-267ca6975798"

	#Constants for Debug mode
	static [bool] $AzSKDebugModeOn = $false

	static [void] SetAzSKModuleName($moduleName)
	{
		if(-not [string]::IsNullOrWhiteSpace($moduleName))
		{
			[Constants]::AzSKModuleName = $moduleName.Replace("azsk","AzSK");
			[Constants]::AzSKAppFolderPath = Join-Path $([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath "Microsoft" |Join-Path -ChildPath $([Constants]::AzSKModuleName)
			[Constants]::AzSKLogFolderPath = Join-Path $([Environment]::GetFolderPath('LocalApplicationData')) "Microsoft"
			[Constants]::AzSKTempFolderPath = Join-Path $([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath "Temp" |Join-Path -ChildPath $([Constants]::AzSKModuleName)
			[Constants]::AzSKExtensionsFolderPath = Join-Path $([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath "Microsoft" |Join-Path -ChildPath $([Constants]::AzSKModuleName) |Join-Path -ChildPath "Extensions"	
		}
	}
	static [void] SetAzSKCurrentModuleVersion($moduleVersion)
	{
		if(-not [string]::IsNullOrWhiteSpace($moduleVersion))
		{
			[Constants]::AzSKCurrentModuleVersion = $moduleVersion;
		}
	}

	static [void] SetAzSKCurrentEnvironmentMode($moduleVersion)
	{
		#1.0.0.0 is hard-coded version for Dev-Test , which means kit is running in Debug mode 
		if(-not [string]::IsNullOrWhiteSpace($moduleVersion) -and ($moduleVersion -eq "1.0.0.0"))
		{
			[Constants]::AzSKDebugModeOn = $true;
		}
	}
	
	# LogAnalytics view file name
	static [string] $LogAnalyticsGenericView = "AZSK.AM.LogAnalytics.GenericView.V6.lawsview"
	static [string] $LogAnalyticsGenericViewWorkbook = "ADOScannerLAWorkbook.json"
	static [string] $WorkbookData = "WorkbookSerializedData.json"
}
