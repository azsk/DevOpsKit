Set-StrictMode -Version Latest
class TelemetryKeys {
    static [string] $SubscriptionId = "SubscriptionId";
    static [string] $SubscriptionName = "SubscriptionName";
    static [string] $FeatureGroup = "FeatureGroup";
    static [string] $Feature = "Feature";
    static [string] $ResourceName = "ResourceName";
    static [string] $ResourceGroup = "ResourceGroup";
    static [string] $IsInterrupted = "IsInterrupted";
    static [string] $InterruptedReason = "InterruptedReason";
    static [string] $InterruptedReasonException = "InterruptedReasonException";
    static [string] $TimeTakenInMs = "TimeTakenInMs";
    static [string] $ControlId = "ControlId";
    static [string] $ControlStatus = "ControlStatus";
    static [string] $ControlFailedReason = "ControlFailedReason";
    static [string] $NestedComplaintCount = "NestedComplaintCount";
    static [string] $NestedNonComplaintCount = "NestedNonComplaintCount";
    static [string] $NestedTotalCount = "NestedTotalCount";
    static [string] $NestedResourceName = "NestedResourceName";
    static [string] $IsNestedResourceCheck = "IsNestedResourceCheck";
}

class TelemetryEvents {
    static [string] $OperationInterrupted = "Operation Interrupted";
    static [string] $OperationCompleted = "Operation Completed";
    static [string] $ControlScanned = "Control Scanned";
    static [string] $NestedResourceControlScanned = "Nested Resource Control Scanned";
    static [string] $AutoHealAttempted = "Auto Heal Attempted";
}

class TelemetryMessages {
    static [string] $Yes = "Yes";
    static [string] $InterruptedReasonException = "Exception";
    static [string] $InterruptedReasonControlJSONNotFound = "ControlJSONNotFound";
    static [string] $ControlPassed = "Passed";
    static [string] $ControlFailed = "Failed";
    static [string] $ControlManual = "Manual";
    static [string] $ControlVerify = "Verify";
    static [string] $ControlDisabled = "Disabled";
    static [string] $ControlNotApplicable = "N/A";
}

enum TraceLevel {
    Verbose
    Information
    Warning
    Error
    Fatal
}
