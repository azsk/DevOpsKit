Set-StrictMode -Version Latest
class AzSKRootEvent {
    static [string] $CustomMessage = "AzSK.CustomMessage"; 

    static [string] $GenerateRunIdentifier = "AzSK.GenerateRunIdentifier"; 
    static [string] $UnsupportedResources = "AzSK.UnsupportedResources";
	static [string] $WriteCSV = "AzSK.WriteCSV";
	static [string] $PublishCustomData = "AzSK.PublishCustomData"


    #Command level event
    static [string] $CommandStarted = "AzSK.Command.Started"; 
    static [string] $CommandCompleted = "AzSK.Command.Completed"; 
    static [string] $CommandError = "AzSK.Command.Error"; 
    static [string] $CommandProcessing = "AzSK.Command.Processing";

	static [string] $PolicyMigrationCommandStarted = "AzSK.Command.PolicyMigrationStarted";
	static [string] $PolicyMigrationCommandCompleted = "AzSK.Command.PolicyMigrationCompleted"
}

class SubscriptionContext {
    [string] $SubscriptionId = "";
    [string] $SubscriptionName = "";
    [string] $Scope = "";
    hidden [hashtable] $SubscriptionMetadata = @{}
}

class AzSKRootEventArgument {
    [SubscriptionContext] $SubscriptionContext;
    [MessageData[]] $Messages = @();
    hidden [System.Management.Automation.ErrorRecord] $ExceptionMessage
}
class CustomData {
	[string] $Name
	[PSObject] $Value
}


