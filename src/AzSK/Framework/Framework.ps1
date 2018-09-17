Set-StrictMode -Version Latest

# load AI dlls using context
try {Get-AzureRmContext -ErrorAction SilentlyContinue | Out-Null }
catch 
{ 
	# No need to break execution 
}

. $PSScriptRoot\Models\Enums.ps1

#Constants
. $PSScriptRoot\Helpers\Constants.ps1
. $PSScriptRoot\Helpers\OldConstants.ps1


#Models
. $PSScriptRoot\Models\AzSKGenericEvent.ps1
. $PSScriptRoot\Models\CommandDetails.ps1
. $PSScriptRoot\Models\Exception\SuppressedException.ps1
. $PSScriptRoot\Models\RemoteReports\CsvOutputModel.ps1
. $PSScriptRoot\Helpers\CommandHelper.ps1
. $PSScriptRoot\Abstracts\EventBase.ps1

. $PSScriptRoot\Helpers\Helpers.ps1

#Helpers (independent of models)

. $PSScriptRoot\Helpers\ConfigurationHelper.ps1

. $PSScriptRoot\Models\AzSKConfig.ps1
. $PSScriptRoot\Models\AzSKEvent.ps1
. $PSScriptRoot\Models\AzSKSettings.ps1

. $PSScriptRoot\Models\SVT\SVTConfig.ps1
. $PSScriptRoot\Models\SVT\SVTEvent.ps1
. $PSScriptRoot\Models\SVT\SVTResource.ps1
. $PSScriptRoot\Models\SVT\AttestationOptions.ps1
. $PSScriptRoot\Models\SVT\PSCloudService.ps1
. $PSScriptRoot\Models\SVT\PartialScanResourceMap.ps1
. $PSScriptRoot\Models\RemoteReports\LSRScanResultModel.ps1
. $PSScriptRoot\Models\RemoteReports\ComplianceStateModel.ps1
. $PSScriptRoot\Models\SubscriptionCore\AzureSecurityCenter.ps1
. $PSScriptRoot\Models\SubscriptionCore\ManagementCertificate.ps1
. $PSScriptRoot\Models\SubscriptionSecurity\SubscriptionRBAC.ps1
. $PSScriptRoot\Models\ContinuousAssurance\AutomationAccount.ps1
. $PSScriptRoot\Models\ControlState.ps1
. $PSScriptRoot\Models\FixControl\FixControlModel.ps1
. $PSScriptRoot\Models\RemoteReports\RecommendationReportModel.ps1
. $PSScriptRoot\Models\RemoteReports\ScanResultModels.ps1

#Helpers
. $PSScriptRoot\Helpers\Helpers.ps1

. $PSScriptRoot\Helpers\WebRequestHelper.ps1
. $PSScriptRoot\Helpers\ActiveDirectoryHelper.ps1
. $PSScriptRoot\Helpers\RoleAssignmentHelper.ps1
. $PSScriptRoot\Helpers\SecurityCenterHelper.ps1
. $PSScriptRoot\Helpers\SVTMapping.ps1
. $PSScriptRoot\Helpers\IdentityHelpers.ps1
. $PSScriptRoot\Helpers\ConfigOverride.ps1

. $PSScriptRoot\Models\Common\ResourceInventory.ps1


#Managers
. $PSScriptRoot\Managers\ConfigurationManager.ps1
. $PSScriptRoot\Managers\ControlStateExtension.ps1
. $PSScriptRoot\Managers\AzSKPDFExtension.ps1
. $PSScriptRoot\Managers\PartialScanManager.ps1

. $PSScriptRoot\Helpers\OMSHelper.ps1
. $PSScriptRoot\Helpers\RemoteReportHelper.ps1
. $PSScriptRoot\Helpers\RemoteApiHelper.ps1
. $PSScriptRoot\Core\PrivacyNotice.ps1


#Abstracts
. $PSScriptRoot\Abstracts\AzSKRoot.ps1
. $PSScriptRoot\Abstracts\SVTBase.ps1

. $PSScriptRoot\Abstracts\FixControl\FixControlBase.ps1
. $PSScriptRoot\Abstracts\FixControl\FixServicesBase.ps1
. $PSScriptRoot\Abstracts\FixControl\FixSubscriptionBase.ps1

. $PSScriptRoot\Abstracts\ListenerBase.ps1
. $PSScriptRoot\Abstracts\FileOutputBase.ps1

. $PSScriptRoot\Helpers\ResourceHelper.ps1
. $PSScriptRoot\Helpers\UserSubscriptionDataHelper.ps1
. $PSScriptRoot\Abstracts\ComplianceBase.ps1
. $PSScriptRoot\Helpers\ComplianceReportHelper.ps1

#Listeners
. $PSScriptRoot\Listeners\UserReports\WriteFolderPath.ps1
(Get-ChildItem -Path "$PSScriptRoot\Listeners\UserReports" -Recurse -File -Include "*.ps1" -Exclude "WriteFolderPath.ps1") |
    ForEach-Object {
    . $_.FullName
}
. $PSScriptRoot\Listeners\GenericListener\GenericListenerBase.ps1
. $PSScriptRoot\Listeners\RemoteReports\TelemetryStrings.ps1
. $PSScriptRoot\Helpers\RemoteReportHelper.ps1
. $PSScriptRoot\Helpers\AIOrgTelemetryHelper.ps1
. $PSScriptRoot\Listeners\RemoteReports\RemoteReportsListener.ps1
. $PSScriptRoot\Listeners\RemoteReports\AIOrgTelemetry.ps1
. $PSScriptRoot\Listeners\RemoteReports\UsageTelemetry.ps1
. $PSScriptRoot\Listeners\OMS\OMSOutput.ps1
. $PSScriptRoot\Listeners\FixControl\WriteFixControlFiles.ps1
. $PSScriptRoot\Listeners\EventHub\EventHubOutput.ps1
. $PSScriptRoot\Listeners\Webhook\WebhookOutput.ps1
. $PSScriptRoot\Listeners\CA\WriteCAStatus.ps1
. $PSScriptRoot\Listeners\GenericListener\GenericListener.ps1
. $PSScriptRoot\Listeners\SecurityRecommendationReport.ps1
. $PSScriptRoot\Listeners\ListenerHelper.ps1

#Remaining Abstracts
. $PSScriptRoot\Core\SVT\SVTControlAttestation.ps1
. $PSScriptRoot\Abstracts\CommandBase.ps1

#SubscriptionSecurity
. $PSScriptRoot\Core\SubscriptionSecurity\Alerts.ps1
. $PSScriptRoot\Core\SubscriptionSecurity\ARMPolicies.ps1

#CA
. $PSScriptRoot\Core\ContinuousAssurance\CAAutomation.ps1

#Remaining Abstracts
. $PSScriptRoot\Abstracts\SVTCommandBase.ps1

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
. $PSScriptRoot\Core\AzureMonitoring\OMSMonitoring.ps1
. $PSScriptRoot\Core\SVT\SubscriptionCore\SubscriptionCore.ps1
. $PSScriptRoot\Core\SVT\AzSKCfg\AzSKCfg.ps1
. $PSScriptRoot\Core\SVT\SVTResourceResolver.ps1
. $PSScriptRoot\Core\SVT\ServicesSecurityStatus.ps1
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