<#
.Description
	Base class for all AzSK classes. 
    Provides base functionality to fire events/operations at all inherited class levels like loging context initialization, 
    message publish, load configaration etc.
#>

Set-StrictMode -Version Latest
class AzSKRoot: EventBase
{ 
    #Region: Properties
    [SubscriptionContext] $SubscriptionContext;
	[bool] $RunningLatestPSModule = $true;
    #EndRegion

    #Region: Constructor 
    AzSKRoot([string] $subscriptionId) :Base($subscriptionId)
    {
        #Initialize context 
        $ContextHelper = [ContextHelper]::new()
        $this.SubscriptionContext = $ContextHelper.SetContext($subscriptionId)
    }
    #EndRegion
    
    #Function to load server configuration file
    [PSObject] LoadServerConfigFile([string] $fileName)
    {
        return [ConfigurationManager]::LoadServerConfigFile($fileName);
    }	

	hidden [AzSKRootEventArgument] CreateRootEventArgumentObject() 
	{
		return [AzSKRootEventArgument]@{
            SubscriptionContext = $this.SubscriptionContext;
        };
	}

    hidden [void] PublishAzSKRootEvent([string] $eventType, [MessageData[]] $messages) 
    {
        [AzSKRootEventArgument] $arguments = $this.CreateRootEventArgumentObject();

		if($messages)
		{
		    $arguments.Messages += $messages;
		}

        $this.PublishEvent($eventType, $arguments);
    }

    hidden [void] PublishAzSKRootEvent([string] $eventType, [string] $message, [MessageType] $messageType) 
    {
        if (-not [string]::IsNullOrEmpty($message)) 
		{
            [MessageData] $data = [MessageData]@{
                Message = $message;
                MessageType = $messageType;
            };
            $this.PublishAzSKRootEvent($eventType, $data);
        }
        else 
		{
			[MessageData[]] $blankMessages = @();
            $this.PublishAzSKRootEvent($eventType, $blankMessages);
        }        
    }

	hidden [void] PublishAzSKRootEvent([string] $eventType, [PSObject] $dataObject) 
    {
        if ($dataObject) 
		{
            [MessageData] $data = [MessageData]@{
                DataObject = $dataObject;
            };
            $this.PublishAzSKRootEvent($eventType, $data);
        }
        else 
		{
			[MessageData[]] $blankMessages = @();
            $this.PublishAzSKRootEvent($eventType, $blankMessages);
        }        
    }

    [MessageData[]] PublishCustomMessage([MessageData[]] $messages) 
    {
		if($messages)
		{
			$this.PublishAzSKRootEvent([AzSKRootEvent]::CustomMessage, $messages);
			return $messages;
		}
		return @();
    }

    #Function to publish custom data  
	[CustomData] PublishCustomData([CustomData] $CustomData) 
    {
		if($CustomData)
		{
			$this.PublishAzSKRootEvent([AzSKRootEvent]::PublishCustomData, $CustomData);
			return $CustomData;
		}
		return $null;
    }
	
	[void] CommandProcessing([MessageData[]] $messages) 
    {
		if($messages)
		{
			$this.PublishAzSKRootEvent([AzSKRootEvent]::CommandProcessing, $messages);
		}
    }

    [void] PublishRunIdentifier([System.Management.Automation.InvocationInfo] $invocationContext) 
    {
		if($invocationContext)
		{
			$this.InvocationContext = $invocationContext;
		}
        $this.RunIdentifier = $this.GenerateRunIdentifier();
        $this.PublishAzSKRootEvent([AzSKRootEvent]::GenerateRunIdentifier, [MessageData]::new($this.RunIdentifier, $invocationContext));
    }
}
