Set-StrictMode -Version Latest
class AzSKGenericEvent
{
    static [string] $CustomMessage = "AzSK.Generic.CustomMessage"; #EventArgument: MessageData
    static [string] $Exception = "AzSK.Generic.Exception"; #EventArgument: ErrorRecord
}



class MessageDataBase
{
	[string] $Message = "";
    [PSObject] $DataObject;

	MessageDataBase()
	{ }

	MessageDataBase([string] $message, [PSObject] $dataObject)
	{
		if($dataObject -and ($dataObject | Measure-Object).Count -ne 0)
		{
			$this.DataObject = $dataObject;
			$this.Message = $message;
		}
		else
		{
			# Commented throwing exception
			#throw [System.ArgumentException] ("The argument 'dataObject' is null or empty");
		}		
	}
}

class MessageData: MessageDataBase
{
	[MessageType] $MessageType = [MessageType]::Info;
	
    MessageData()
    { }

    MessageData([string] $message, [MessageType] $messageType)
    {
        $this.Message = $message;
        $this.MessageType = $messageType;
    }

    MessageData([string] $message, [PSObject] $dataObject, [MessageType] $messageType)
    {
        $this.Message = $message;
        $this.DataObject = $dataObject;
        $this.MessageType = $messageType;
    }
	
    MessageData([string] $message, [PSObject] $dataObject)
    {
        $this.Message = $message;
        $this.DataObject = $dataObject;
    }

    MessageData([string] $message)
    {
        $this.Message = $message;
    }

    MessageData([PSObject] $dataObject)
    {
        $this.DataObject = $dataObject;        
    }
	
    MessageData([PSObject] $dataObject, [MessageType] $messageType)
    {
        $this.MessageType = $messageType;
        $this.DataObject = $dataObject;        
    }
}

