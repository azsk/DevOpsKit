Set-StrictMode -Version Latest

# load AI dlls using context
try {Get-AzContext -ErrorAction SilentlyContinue | Out-Null }
catch 
{ 
	# No need to break execution 
}
$FrameworkPath =  ((Get-Item $PSScriptRoot).Parent.Parent).FullName +"\AzSK.Framework"

. $FrameworkPath\Models\Enums.ps1

#Constants
. $FrameworkPath\Helpers\Constants.ps1

#Models
. $FrameworkPath\Models\AzSKGenericEvent.ps1
. $FrameworkPath\Models\CommandDetails.ps1
. $FrameworkPath\Models\Exception\SuppressedException.ps1
. $FrameworkPath\Models\RemoteReports\CsvOutputModel.ps1
. $FrameworkPath\Models\FeatureFlight.ps1
. $FrameworkPath\Models\AzSKEvent.ps1
. $FrameworkPath\Helpers\CommandHelper.ps1
. $FrameworkPath\Abstracts\EventBase.ps1
. $FrameworkPath\Helpers\JsonHelper.ps1
. $FrameworkPath\Helpers\Helpers.ps1
. $FrameworkPath\Helpers\ContextHelper.ps1  
#Helpers (independent of models)

. $FrameworkPath\Helpers\ConfigurationHelper.ps1


. $FrameworkPath\Models\AzSKConfig.ps1

. $FrameworkPath\Models\AzSKSettings.ps1

. $FrameworkPath\Models\SVT\SVTConfig.ps1
. $FrameworkPath\Models\SVT\SVTEvent.ps1
. $FrameworkPath\Models\SVT\SVTResource.ps1
. $FrameworkPath\Models\SVT\AttestationOptions.ps1
. $FrameworkPath\Models\SVT\PSCloudService.ps1
. $FrameworkPath\Models\SVT\PartialScanResourceMap.ps1
. $FrameworkPath\Models\RemoteReports\LSRScanResultModel.ps1
. $FrameworkPath\Models\RemoteReports\ComplianceStateModel.ps1
. $FrameworkPath\Models\SubscriptionCore\AzureSecurityCenter.ps1
. $FrameworkPath\Models\SubscriptionCore\ManagementCertificate.ps1
. $FrameworkPath\Models\SubscriptionSecurity\SubscriptionRBAC.ps1
. $FrameworkPath\Models\ContinuousAssurance\AutomationAccount.ps1
. $FrameworkPath\Models\ControlState.ps1
. $FrameworkPath\Models\FixControl\FixControlModel.ps1
. $FrameworkPath\Models\RemoteReports\RecommendationReportModel.ps1
. $FrameworkPath\Models\RemoteReports\ScanResultModels.ps1

#Helpers
. $FrameworkPath\Helpers\Helpers.ps1
. $FrameworkPath\Managers\ConfigurationManager.ps1
. $PSScriptRoot\Helpers\ResourceHelper.ps1
. $FrameworkPath\Helpers\WebRequestHelper.ps1
. $FrameworkPath\Helpers\ActiveDirectoryHelper.ps1
. $FrameworkPath\Managers\FeatureFlightingManager.ps1
. $PSScriptRoot\Helpers\RoleAssignmentHelper.ps1
. $PSScriptRoot\Helpers\SecurityCenterHelper.ps1
. $FrameworkPath\Helpers\SVTMapping.ps1
. $FrameworkPath\Helpers\IdentityHelpers.ps1
. $FrameworkPath\Helpers\ConfigOverride.ps1
. $FrameworkPath\Helpers\ControlHelper.ps1

. $FrameworkPath\Models\Common\ResourceInventory.ps1


#Managers


. $PSScriptRoot\Helpers\AzHelper.ps1
. $FrameworkPath\Managers\ControlStateExtension.ps1
. $FrameworkPath\Managers\AzSKPDFExtension.ps1
. $FrameworkPath\Managers\PartialScanManager.ps1

. $FrameworkPath\Helpers\LogAnalyticsHelper.ps1
. $FrameworkPath\Helpers\RemoteReportHelper.ps1
. $FrameworkPath\Helpers\RemoteApiHelper.ps1
. $FrameworkPath\Abstracts\PrivacyNotice.ps1


#Abstracts
. $FrameworkPath\Abstracts\AzSKRoot.ps1
. $FrameworkPath\Abstracts\SVTBase.ps1
. $PSScriptRoot\Abstracts\AzSVTBase.ps1

. $FrameworkPath\Abstracts\FixControl\FixControlBase.ps1
. $FrameworkPath\Abstracts\FixControl\FixServicesBase.ps1
. $PSScriptRoot\Abstracts\FixControl\FixSubscriptionBase.ps1

. $FrameworkPath\Abstracts\ListenerBase.ps1
. $FrameworkPath\Abstracts\FileOutputBase.ps1


. $PSScriptRoot\Helpers\UserSubscriptionDataHelper.ps1
. $PSScriptRoot\Abstracts\ComplianceBase.ps1
. $PSScriptRoot\Helpers\ComplianceReportHelper.ps1

#Listeners
. $FrameworkPath\Listeners\UserReports\WriteFolderPath.ps1
(Get-ChildItem -Path "$FrameworkPath\Listeners\UserReports" -Recurse -File -Include "*.ps1" -Exclude "WriteFolderPath.ps1") |
    ForEach-Object {
    . $_.FullName
}
. $FrameworkPath\Listeners\GenericListener\GenericListenerBase.ps1
. $FrameworkPath\Listeners\RemoteReports\TelemetryStrings.ps1
. $FrameworkPath\Helpers\RemoteReportHelper.ps1
. $FrameworkPath\Helpers\AIOrgTelemetryHelper.ps1
. $FrameworkPath\Listeners\RemoteReports\RemoteReportsListener.ps1
. $FrameworkPath\Listeners\RemoteReports\AIOrgTelemetry.ps1
. $FrameworkPath\Listeners\RemoteReports\UsageTelemetry.ps1
. $FrameworkPath\Listeners\LogAnalytics\LogAnalyticsOutput.ps1
. $FrameworkPath\Listeners\FixControl\WriteFixControlFiles.ps1
. $FrameworkPath\Listeners\EventHub\EventHubOutput.ps1
. $FrameworkPath\Listeners\Webhook\WebhookOutput.ps1
. $PSScriptRoot\Listeners\CA\WriteCAStatus.ps1
. $FrameworkPath\Listeners\GenericListener\GenericListener.ps1
. $PSScriptRoot\Listeners\SecurityRecommendationReport.ps1
. $PSScriptRoot\Listeners\AzResourceInventoryListener.ps1
. $FrameworkPath\Listeners\ListenerHelper.ps1
. $PSScriptRoot\Listeners\AzListenerHelper.ps1

#Remaining Abstracts
. $PSScriptRoot\Core\SVT\SVTControlAttestation.ps1
. $FrameworkPath\Abstracts\CommandBase.ps1
. $PSScriptRoot\Abstracts\AzCommandBase.ps1


#SubscriptionSecurity
. $PSScriptRoot\Core\SubscriptionSecurity\Alerts.ps1
. $PSScriptRoot\Core\SubscriptionSecurity\ARMPolicies.ps1

#CA
. $PSScriptRoot\Core\ContinuousAssurance\CAAutomation.ps1

#Remaining Abstracts
. $FrameworkPath\Abstracts\SVTCommandBase.ps1
. $PSScriptRoot\Abstracts\AzSVTCommandBase.ps1
#Core

. $PSScriptRoot\Core\SVT\SVTIaasBase.ps1
(Get-ChildItem -Path "$PSScriptRoot\Core\SVT\Services\" -Recurse -File) |
    ForEach-Object {
    . $_.FullName
}
(Get-ChildItem -Path "$PSScriptRoot\Core\SubscriptionSecurity\" -Recurse -File -Exclude 'SubscriptionSecurity.ps1') |
    ForEach-Object {
    . $_.FullName
}

. $PSScriptRoot\Core\SubscriptionSecurity\SubscriptionSecurity.ps1

. $PSScriptRoot\Core\FixControl\FixControlConfigResolver.ps1
. $PSScriptRoot\Core\FixControl\ControlSecurityFixes.ps1
. $PSScriptRoot\Core\AzureMonitoring\LogAnalyticsMonitoring.ps1
. $PSScriptRoot\Core\SVT\SubscriptionCore\SubscriptionCore.ps1
. $PSScriptRoot\Core\SVT\AzSKCfg\AzSKCfg.ps1
. $PSScriptRoot\Core\SVT\SVTResourceResolver.ps1
. $FrameworkPath\Abstracts\ServicesSecurityStatus.ps1
. $PSScriptRoot\Core\SVT\SubscriptionSecurityStatus.ps1
. $PSScriptRoot\Core\SVT\SVTStatusReport.ps1
. $PSScriptRoot\Core\AzSKInfo\SecurityRecommendationsReport.ps1
. $PSScriptRoot\Core\AzSKInfo\BasicInfo.ps1
. $PSScriptRoot\Core\AzSKInfo\ControlsInfo.ps1
. $PSScriptRoot\Core\AzSKInfo\EnvironmentInfo.ps1
. $PSScriptRoot\Core\AzSKInfo\ComplianceInfo.ps1
. $PSScriptRoot\Core\AzSKInfo\PersistedStateInfo.ps1
. $PSScriptRoot\Core\ARMChecker\ARMCheckerStatus.ps1
. $PSScriptRoot\Core\PolicySetup\PolicySetup.ps1
. $PSScriptRoot\Core\PIM\PIMScript.ps1
. $PSScriptRoot\Core\CredHygiene\CredHygieneScript.ps1
. $PSScriptRoot\Core\InClusterCA\ContinuousAssuranceForDatabricks.ps1
. $PSScriptRoot\Core\InClusterCA\ContinuousAssuranceForHDInsight.ps1
. $PSScriptRoot\Core\InClusterCA\ContinuousAssuranceForKubernetes.ps1