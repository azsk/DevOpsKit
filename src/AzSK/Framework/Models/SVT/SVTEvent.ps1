Set-StrictMode -Version Latest

class SVTEvent
{
    #First level event

    #Command level event
    static [string] $CommandStarted = "AzSK.SVT.Command.Started"; #Initialize listeners #Function execution started
    static [string] $CommandCompleted = "AzSK.SVT.Command.Completed"; #Cleanup listeners #Function execution completed
    static [string] $CommandError = "AzSK.SVT.Command.Error";

    #Second level event for every resource
    static [string] $EvaluationStarted = "AzSK.SVT.Evaluation.Started"; #Individual Resource execution started
    static [string] $EvaluationCompleted = "AzSK.SVT.Evaluation.Completed"; #Individual Resource execution completed
    static [string] $EvaluationError = "AzSK.SVT.Evaluation.Error";

    #Control level events
    static [string] $ControlStarted = "AzSK.SVT.Control.Started"; #Individual control execution started
    static [string] $ControlCompleted = "AzSK.SVT.Control.Completed"; #Individual control execution completed
    static [string] $ControlError = "AzSK.SVT.Control.Error"; #Error while control execution
    static [string] $ControlDisabled = "AzSK.SVT.Control.Disabled"; #Event if control is in disabled mode

	#Resource and Control Level event
	static [string] $WriteInventory = "AzSK.SVT.WriteInventory"; #Custom event to write resource inventory
}

class ResourceContext
{
	[string] $ResourceId =""
    [string] $ResourceGroupName = ""
    [string] $ResourceName = ""
    [string] $ResourceType = ""
	[hashtable] $ResourceMetadata = @{}
    [string] $ResourceTypeName = ""
}

class ControlResult
{
    [string] $ChildResourceName = "";

    [VerificationResult] $VerificationResult = [VerificationResult]::Manual;
    [VerificationResult] $ActualVerificationResult = [VerificationResult]::Manual;
	[SessionContext] $CurrentSessionContext = [SessionContext]::new();
	[AttestationStatus] $AttestationStatus = [AttestationStatus]::None;

	[StateManagement] $StateManagement = [StateManagement]::new();
	hidden [PSObject] $FixControlParameters = $null;
	hidden [bool] $EnableFixControl = $false;
	[bool] $IsControlInGrace=$true;
	[DateTime] $FirstFailedOn = [Constants]::AzSKDefaultDateTime;
	[DateTime] $FirstScannedOn = [Constants]::AzSKDefaultDateTime;
	[int] $MaximumAllowedGraceDays=0;
	[String] $UserComments	
    [MessageData[]] $Messages = @();

    [void] AddMessage([MessageData] $messageData)
    {
        if((-not [string]::IsNullOrEmpty($messageData.Message)) -or ($null -ne $messageData.DataObject))
        {
            $this.Messages += $messageData;
        }
    }

    [void] AddMessage([VerificationResult] $result, [MessageData] $messageData)
    {
        $this.VerificationResult = $result;
        $this.AddMessage($messageData);
    }

    [void] AddMessage([VerificationResult] $result, [string] $message, [PSObject] $dataObject)
    {
        $this.VerificationResult = $result;
        $this.AddMessage([MessageData]::new($message, $dataObject));
    }

	[void] AddMessage([string] $message, [PSObject] $dataObject)
    {
        $this.AddMessage([MessageData]::new($message, $dataObject));
    }

	[void] AddMessage([PSObject] $dataObject)
    {
        $this.AddMessage([MessageData]::new($dataObject));
    }
	[void] AddMessage([string] $message)
    {
        $this.AddMessage([MessageData]::new($message));
    }

    [void] AddError([System.Management.Automation.ErrorRecord] $exception)
    {
        $this.AddMessage([MessageData]::new($exception, [MessageType]::Error));
    }

	[void] SetStateData([string] $message, [PSObject] $dataObject)
	{
		$this.StateManagement.CurrentStateData = [StateData]::new($message, $dataObject);
	}
}

class SessionContext
{
	[UserPermissions] $Permissions = [UserPermissions]::new();
	[bool] $IsLatestPSModule
}

class UserPermissions
{
	[bool] $HasAttestationWritePermissions = $false
	[bool] $HasAttestationReadPermissions = $false
	[bool] $HasRequiredAccess = $true;
}

class StateManagement
{
	[StateData] $AttestedStateData;
	[StateData] $CurrentStateData;
}

class Metadata
{
	[string] $Reference = ""
}

class StateData: MessageDataBase
{
	[string] $Justification = "";
	[string] $AttestedBy =""
	[DateTime] $AttestedDate
	[string] $ExpiryDate =""
	StateData()
	{
	}

	StateData([string] $message, [PSObject] $dataObject) :
		Base($message, $dataObject)
	{
	}
}

class SVTEventContext: AzSKRootEventArgument
{
	[string] $FeatureName = ""
    [Metadata] $Metadata
	[string] $PartialScanIdentifier;
    [ResourceContext] $ResourceContext;
	[ControlItem] $ControlItem;
    [ControlResult[]] $ControlResults = @();

	[bool] IsResource()
	{
		if($this.ResourceContext)
		{
			return $true;
		}
		else
		{
			return $false;
		}
	}

	[string] GetUniqueId()
	{
		$uniqueId = "";
		if($this.IsResource())
		{
			$uniqueId = $this.ResourceContext.ResourceId;
		}
		else
		{
			$uniqueId = $this.SubscriptionContext.Scope;
		}

		# Unique Id validation
		if([string]::IsNullOrWhiteSpace($uniqueId))
		{
			throw "Error while evaluating Unique Id. The parameter 'ResourceContext.ResourceId' OR 'SubscriptionContext.Scope' is null or empty."
		}

		return $uniqueId;
	}
}