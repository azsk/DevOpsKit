Set-StrictMode -Version Latest
class AzSKRoot: EventBase
{ 
    [SubscriptionContext] $SubscriptionContext;
	[bool] $RunningLatestPSModule = $true;

    AzSKRoot([string] $subscriptionId)
    {   
        [Helpers]::AbstractClass($this, [AzSKRoot]);
        
		#Validate SubId
		[Guid] $validatedId = [Guid]::Empty;
		if([Guid]::TryParse($subscriptionId, [ref] $validatedId))
		{
			#Set up subscription
			$this.SubscriptionContext = [SubscriptionContext]@{
				SubscriptionId = $validatedId.Guid;
				Scope = "/subscriptions/$($validatedId.Guid)";
			};

			$this.SetAzureContext();
		}
		else
		{
			throw [SuppressedException] ("Subscription Id [$subscriptionId] is malformed. Subscription Id should contain 32 digits with 4 dashes (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).")
		}
    }    
    
    hidden [void] SetAzureContext()
    {
		$currentContext = [Helpers]::GetCurrentRMContext()

        if((-not $currentContext) -or ($currentContext -and ((-not $currentContext.Subscription -and ($this.SubscriptionContext.SubscriptionId -ne [Constants]::BlankSubscriptionId)) `
				-or -not $currentContext.Account)))
        {
            $this.PublishCustomMessage("No active Azure login session found. Initiating login flow...", [MessageType]::Warning);

			if($this.SubscriptionContext.SubscriptionId -ne [Constants]::BlankSubscriptionId)
			{
				$rmLogin = Connect-AzureRmAccount -SubscriptionId $this.SubscriptionContext.SubscriptionId
			}
			else
			{
				$rmLogin = Connect-AzureRmAccount
			}
            
			if($rmLogin)
			{
				$currentContext = $rmLogin.Context;
			}
        }

		if($currentContext -and $currentContext.Subscription -and $currentContext.Subscription.Id)
		{
		    if(($currentContext.Subscription.Id -ne $this.SubscriptionContext.SubscriptionId) -and ($this.SubscriptionContext.SubscriptionId -ne [Constants]::BlankSubscriptionId))
			{
				$currentContext = Set-AzureRmContext -SubscriptionId $this.SubscriptionContext.SubscriptionId -ErrorAction Stop   
        
				    
				# $currentContext will contain the desired subscription (or $null if id is wrong or no permission)
				if ($null -eq $currentContext)
				{
					throw [SuppressedException] ("Invalid Subscription Id [" + $this.SubscriptionContext.SubscriptionId + "]") 
				}
				[Helpers]::ResetCurrentRMContext()
				[Helpers]::GetCurrentRMContext()
			}
			elseif(($currentContext.Subscription.Id -ne $this.SubscriptionContext.SubscriptionId) -and ($this.SubscriptionContext.SubscriptionId -eq [Constants]::BlankSubscriptionId))
			{
				$this.SubscriptionContext.SubscriptionId = $currentContext.Subscription.Id
				$this.SubscriptionContext.SubscriptionName = $currentContext.Subscription.Name
				$this.SubscriptionContext.Scope = "/subscriptions/" +$currentContext.Subscription.Id
			}
		}
		elseif($null -ne $currentContext -and ($this.SubscriptionContext.SubscriptionId -eq [Constants]::BlankSubscriptionId))
		{
			$this.SubscriptionContext.SubscriptionName = [Constants]::BlankSubscriptionName
		}
		else
		{
            throw [SuppressedException] ("Subscription Id [" + $this.SubscriptionContext.SubscriptionId + "] is invalid or you may not have permissions.")
		}

        if ($null -ne $currentContext -and [Helpers]::CheckMember($currentContext, "Subscription"))
        {
            $this.SubscriptionContext.SubscriptionName = $currentContext.Subscription.Name;
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
