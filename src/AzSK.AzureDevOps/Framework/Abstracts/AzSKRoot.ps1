Set-StrictMode -Version Latest
class AzSKRoot: EventBase
{ 
    [SubscriptionContext] $SubscriptionContext;
	[bool] $RunningLatestPSModule = $true;

    AzSKRoot([string] $subscriptionId)
    {   
        [Helpers]::AbstractClass($this, [AzSKRoot]);
        
		if((-not [string]::IsNullOrEmpty($subscriptionId)))
		{
			$this.SubscriptionContext = [SubscriptionContext]@{
				SubscriptionId = $subscriptionId;
				Scope = "/Organization/$subscriptionId";
				SubscriptionName = $subscriptionId;
			};
			[Helpers]::GetCurrentAzureDevOpsContext()			
		}
		else
		{
			throw [SuppressedException] ("OrganizationName name [$subscriptionId] is either malformed or incorrect.")
		}
	}
	
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

	[bool] IsLatestVersionConfiguredOnSub([String] $ConfigVersion,[string] $TagName,[string] $FeatureName)
	{
		$IsLatestVersionPresent = $this.IsLatestVersionConfiguredOnSub($ConfigVersion,$TagName)
		if($IsLatestVersionPresent){
			$this.PublishCustomMessage("$FeatureName configuration in your subscription is already up to date. If you would like to reconfigure, please rerun the command with '-Force' parameter.");
		}				
		return $IsLatestVersionPresent		
	}

	[bool] IsLatestVersionConfiguredOnSub([String] $ConfigVersion,[string] $TagName)
	{
		$IsLatestVersionPresent = $false
		$tagsOnSub =  [Helpers]::GetResourceGroupTags([ConfigurationManager]::GetAzSKConfigData().AzSKRGName) 
		if($tagsOnSub)
		{
			$SubConfigVersion= $tagsOnSub.GetEnumerator() | Where-Object {$_.Name -eq $TagName -and $_.Value -eq $ConfigVersion}
			
			if(($SubConfigVersion | Measure-Object).Count -gt 0)
			{
				$IsLatestVersionPresent = $true				
			}			
		}
		return $IsLatestVersionPresent		
	}


}
