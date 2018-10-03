#using namespace Microsoft.Azure.Commands.ServiceBus.Models
Set-StrictMode -Version Latest 
class ServiceBus: SVTBase
{       
	hidden [PSObject[]] $NameSpacePolicies = @() ;
	hidden [PSObject[]] $Queues = @() ;
	hidden [PSObject[]] $Topics = @() ;
	hidden [HashTable] $QueueAccessPolicies = @{};
	hidden [Hashtable] $TopicAccessPolicies = @{};
	hidden [PSObject] $SBAccessPolicies;

    ServiceBus([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
    }

	ServiceBus([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
		$this.GetServiceBusDetails();
		$this.GetServiceBusAccessPolicies();
    }

	hidden [void] GetServiceBusDetails()
    {
        if (-not $this.NameSpacePolicies) {
            $this.NameSpacePolicies = (Get-AzureRmServiceBusAuthorizationRule -ResourceGroup $this.ResourceContext.ResourceGroupName `
						-NamespaceName $this.ResourceContext.ResourceName | Select-Object Id, Name, Rights)
        }
		
		# Get All Queues
		if (-not $this.Queues) {
            $this.Queues = Get-AzureRmServiceBusQueue -ResourceGroup $this.ResourceContext.ResourceGroupName -NamespaceName $this.ResourceContext.ResourceName
        }

		if (-not $this.Topics) {
            $this.Topics = Get-AzureRmServiceBusTopic -ResourceGroup $this.ResourceContext.ResourceGroupName -NamespaceName $this.ResourceContext.ResourceName
        }
    }

	hidden [void] GetServiceBusAccessPolicies()
	{
		#region "Queue"
		if(($this.Queues|Measure-Object).count -gt 0)
		{
			foreach ($queue in $this.Queues)
			{
				$queuePolicies = Get-AzureRmServiceBusAuthorizationRule -ResourceGroup $this.ResourceContext.ResourceGroupName `
										-NamespaceName $this.ResourceContext.ResourceName -Queue $queue.Name

				$this.QueueAccessPolicies.Add($queue, ($queuePolicies | Select-Object Id, Name, Rights))	
			}
		}
        
		#endregion
           
		#region "Topic"
		
		if(($this.Topics|Measure-Object).count -gt 0)
		{
			foreach ($topic in $this.Topics)
			{
				$topicPolicies = Get-AzureRmServiceBusAuthorizationRule -ResourceGroup $this.ResourceContext.ResourceGroupName `
										-NamespaceName $this.ResourceContext.ResourceName -Topic $topic.Name

				$this.TopicAccessPolicies.Add($topic, $topicPolicies)	
			}
		}

		#endregion

		$this.SBAccessPolicies = New-Object -TypeName PSObject 
		$this.SBAccessPolicies | Add-Member -NotePropertyName NameSpacePolicies -NotePropertyValue $this.NameSpacePolicies 
		$this.SBAccessPolicies | Add-Member -NotePropertyName Queues -NotePropertyValue ($this.QueueAccessPolicies | Select-Object Id, Rights)
		$this.SBAccessPolicies | Add-Member -NotePropertyName Topics -NotePropertyValue ($this.TopicAccessPolicies | Select-Object Id, Rights)
	}

	hidden [ControlResult[]] CheckServiceBusRootPolicy([ControlResult] $controlResult)
	{
		$isControlFailed = $false
		#region "NameSpace"
		
		$controlResult.SetStateData("Authorization rules for Service Bus namespace and child entities", $this.SBAccessPolicies);

		$controlResult.AddMessage([MessageData]::new("Authorization rules for Namespace - ["+ $this.ResourceContext.ResourceName +"]. Validate that these rules must not be used at Queue/Topic level to send and receive messages.", 
				$this.NameSpacePolicies));   
		
		#endregion        

		#region "Queue"
		
		if(($this.Queues|Measure-Object).count -gt 0)
		{
			foreach ($queue in $this.Queues)
			{
				if(($this.QueueAccessPolicies[$queue] |Measure-Object).count -gt 0)
				{
					$controlResult.AddMessage([MessageData]::new("Validate that Queue - ["+ $queue.Name +"] must not use access policies defined at Service Bus Namespace level."));
				}
				else
				{
					$isControlFailed = $true
					$controlResult.AddMessage([MessageData]::new("No Authorization rules defined for Queue - ["+ $queue.Name +"]. Applications (senders/receivers) must not use access policies defined at Service Bus namespace level."));
				}
			}
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("Queue not available in Namespace - ["+ $this.ResourceContext.ResourceName +"]"));
		}
        
		#endregion
           
		#region "Topic"
		
		if(($this.Topics|Measure-Object).count -gt 0)
		{
			foreach ($topic in $this.Topics)
			{
				if(($this.TopicAccessPolicies[$topic] |Measure-Object).count -gt 0)
				{
					$controlResult.AddMessage([MessageData]::new("Validate that Topic - ["+ $topic.Name +"] must not use access policies defined at Service Bus namespace level."));
				}
				else
				{
					$isControlFailed = $true
					$controlResult.AddMessage([MessageData]::new("No Authorization rules defined for Topic - ["+ $topic.Name +"]. Applications (senders/receivers) must not use access policies defined at Service Bus namespace level."));
				}
			}
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("Topics not available in Namespace - ["+ $this.ResourceContext.ResourceName +"]"));
		}

		#endregion

		if($isControlFailed)
		{
			$controlResult.VerificationResult = [VerificationResult]::Failed;
		}
		else
		{
			$controlResult.VerificationResult = [VerificationResult]::Verify;
		}

		return $controlResult;
	}

	hidden [ControlResult[]] CheckServiceBusAuthorizationRule([ControlResult] $controlResult)
	{
		$controlResult.SetStateData("Authorization rules for Namespace and child entities", $this.SBAccessPolicies);

		#region "NameSpace"
		$controlResult.AddMessage([MessageData]::new("Authorization rules for Namespace - ["+ $this.ResourceContext.ResourceName +"]. Validate that these rules are defined at correct entity level and with more limited permissions.", 
				$this.NameSpacePolicies));   
		#endregion        

		#region "Queue"
		
		if(($this.Queues|Measure-Object).count -gt 0)
		{
			foreach ($queue in $this.Queues)
			{
				if(($this.QueueAccessPolicies[$queue] |Measure-Object).count -gt 0)
				{
					$controlResult.AddMessage([MessageData]::new("Authorization rules for Queue - ["+ $queue.Name +"]. Validate that these rules are defined at correct entity level and with more limited permissions.", $this.QueueAccessPolicies[$queue]));
				}
			}
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("Queue not available in Namespace - ["+ $this.ResourceContext.ResourceName +"]"));
		}
        
		#endregion
           
		#region "Topic"
		
		if(($this.Topics|Measure-Object).count -gt 0)
		{
			foreach ($topic in $this.Topics)
			{
				if(($this.TopicAccessPolicies[$topic] |Measure-Object).count -gt 0)
				{
					$controlResult.AddMessage([MessageData]::new("Authorization rules for Topic - ["+ $topic.Name +"]. Validate that these rules are defined at correct entity level and with more limited permissions.", $this.TopicAccessPolicies[$topic]));
				}
				else
				{
					$controlResult.AddMessage([MessageData]::new("No Authorization rules defined for Topic - ["+ $topic.Name +"]."));
				}
			}
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("Topics not available in Namespace - ["+ $this.ResourceContext.ResourceName +"]"));
		}

		#endregion

		$controlResult.VerificationResult = [VerificationResult]::Verify;
		
		return $controlResult;
	}
}