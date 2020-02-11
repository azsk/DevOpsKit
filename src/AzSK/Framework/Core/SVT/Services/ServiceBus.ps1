#using namespace Microsoft.Azure.Commands.ServiceBus.Models
Set-StrictMode -Version Latest 
class ServiceBus: AzSVTBase
{       
	hidden [PSObject[]] $NamespacePolicies = @() ;
	hidden [PSObject[]] $Queues = @() ;
	hidden [PSObject[]] $Topics = @() ;
	hidden [HashTable] $QueueAccessPolicies = @{};
	hidden [Hashtable] $TopicAccessPolicies = @{};

	ServiceBus([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
		$this.GetServiceBusDetails();
		$this.GetServiceBusAccessPolicies();
    }

	hidden [void] GetServiceBusDetails()
    {
        if (-not $this.NamespacePolicies) {
			try
			{
				$this.NamespacePolicies = (Get-AzServiceBusAuthorizationRule -ResourceGroup $this.ResourceContext.ResourceGroupName `
							-NamespaceName $this.ResourceContext.ResourceName | Select-Object Id, Name, Rights)
			}
			catch
			{
				# This block is intentionally left blank to handle exception while fetching namespace access policy
			}
            
        }
		
		# Get All Queues
		if (-not $this.Queues) {
			try
			{
				$this.Queues = Get-AzServiceBusQueue -ResourceGroup $this.ResourceContext.ResourceGroupName -NamespaceName $this.ResourceContext.ResourceName
			}
			catch
			{
				# This block is intentionally left blank to handle exception while fetching queue in service bus
			}
            
        }

		# Get All Topics
		if (-not $this.Topics) {
			try
			{
				$this.Topics = Get-AzServiceBusTopic -ResourceGroup $this.ResourceContext.ResourceGroupName -NamespaceName $this.ResourceContext.ResourceName
			}
			catch
			{
				# This block is intentionally left blank to handle exception while fetching topic in service bus
			}
        }
    }

	hidden [void] GetServiceBusAccessPolicies()
	{
		#region "Queue"

		if(($this.Queues|Measure-Object).count -gt 0)
		{
			foreach ($queue in $this.Queues)
			{
				try
				{
					$queuePolicies = Get-AzServiceBusAuthorizationRule -ResourceGroup $this.ResourceContext.ResourceGroupName `
										-NamespaceName $this.ResourceContext.ResourceName -Queue $queue.Name

					$this.QueueAccessPolicies.Add($queue, ($queuePolicies | Select-Object Id, Name, Rights))	
				}
				catch
				{
					# This block is intentionally left blank to handle exception while fetching queue access policies
				}
			}
		}
        
		#endregion
        
		#region "Topic"
		
		if(($this.Topics|Measure-Object).count -gt 0)
		{
			foreach ($topic in $this.Topics)
			{
				try
				{
					$topicPolicies = Get-AzServiceBusAuthorizationRule -ResourceGroup $this.ResourceContext.ResourceGroupName `
										-NamespaceName $this.ResourceContext.ResourceName -Topic $topic.Name

					$this.TopicAccessPolicies.Add($topic, ($topicPolicies| Select-Object Id, Name, Rights))	
				}
				catch
				{
					# This block is intentionally left blank to handle exception while fetching topic access policies
				}
				
			}
		}

		#endregion
	}

	hidden [ControlResult[]] CheckServiceBusRootPolicy([ControlResult] $controlResult)
	{
		$isControlFailed = $false
		#region "NameSpace"

		if((($this.NamespacePolicies | Measure-Object).count -eq 1) -and (($this.NamespacePolicies.Id.substring($this.NamespacePolicies.Id.Length-25, 25) -eq "RootManageSharedAccessKey"))) {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("Only default authorization rule present for namespace - ["+ $this.ResourceContext.ResourceName +"].", 
			$this.NamespacePolicies)); 
		}
		else {
			$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Authorization rules for namespace - ["+ $this.ResourceContext.ResourceName +"]. All the authorization rules except 'RootManageSharedAccessKey' must be removed from namespace level. Also validate that 'RootManageSharedAccessKey' authorization rule must not be used at Queue/Topic level to send and receive messages.", 
			$this.NamespacePolicies)); 
		}

		$controlResult.SetStateData("Authorization rules for namespace entities", $this.NamespacePolicies);
		
		#endregion        

		return $controlResult;
	}

	hidden [ControlResult[]] CheckServiceBusAuthorizationRule([ControlResult] $controlResult)
	{
		$isControlFailed = $false
		$fullPermissionQueues = @();
		$noPolicyQueues = @();
		$fullPermissionTopics = @();
		$noPolicyTopics = @();
		
		#region "Queue"
		
		if(($this.Queues|Measure-Object).count -gt 0)
		{
			foreach ($queue in $this.Queues)
			{
				if($this.QueueAccessPolicies.ContainsKey($queue) -and ($this.QueueAccessPolicies[$queue] |Measure-Object).count -gt 0)
				{
					foreach ($policy in $this.QueueAccessPolicies[$queue])
					{
						if(($policy.Rights | Measure-Object).count -gt 2)
						{
							$fullPermissionQueues += $policy
							$isControlFailed = $true
						}
					}
				}
				else
				{
					$noPolicyQueues += $queue.Name
					$isControlFailed = $true
				}
			}
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("Queue not available in namespace - ["+ $this.ResourceContext.ResourceName +"]"));
		}
        
		#endregion
           
		#region "Topic"
		
		if(($this.Topics|Measure-Object).count -gt 0)
		{
			foreach ($topic in $this.Topics)
			{
				if($this.TopicAccessPolicies.ContainsKey($topic) -and ($this.TopicAccessPolicies[$topic] |Measure-Object).count -gt 0)
				{
					foreach ($policy in $this.TopicAccessPolicies[$topic])
					{
						if(($policy.Rights | Measure-Object).count -gt 2)
						{
							$fullPermissionTopics += $policy
							$isControlFailed = $true
						}
					}
				}
				else
				{
					$noPolicyTopics += $topic.Name
					$isControlFailed = $true
				}
			}
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("Topics not available in namespace - ["+ $this.ResourceContext.ResourceName +"]"));
		}

		#endregion

		if($isControlFailed)
		{
			$controlResult.VerificationResult = [VerificationResult]::Failed;

			$failedClients = New-Object -TypeName PSObject 
			if(($fullPermissionQueues | Measure-Object).count -gt 0)
			{
				$failedClients | Add-Member -NotePropertyName FailedQueuesWithFullPermission -NotePropertyValue $fullPermissionQueues
				$controlResult.AddMessage([MessageData]::new("Validate the authorization rules for the Queue are defined with limited permissions.", $fullPermissionQueues));
			}
			if(($noPolicyQueues | Measure-Object).count -gt 0)
			{
				$failedClients | Add-Member -NotePropertyName FailedQueuesWithNoAccessPolicy -NotePropertyValue $noPolicyQueues
				$controlResult.AddMessage([MessageData]::new("No Authorization rules defined for following Queue. Either Queue is not in use or namespace level access policy is used. Applications (senders/receivers) must not use access policies defined at Service Bus namespace level.", $noPolicyQueues));
			}
			if(($fullPermissionTopics | Measure-Object).count -gt 0)
			{
				$failedClients | Add-Member -NotePropertyName FailedTopicsWithFullPermission -NotePropertyValue $fullPermissionTopics
				$controlResult.AddMessage([MessageData]::new("Validate the authorization rules for the Topic are defined with limited permissions.", $fullPermissionTopics));
			}
			if(($noPolicyTopics | Measure-Object).count -gt 0)
			{
				$failedClients | Add-Member -NotePropertyName FailedTopicsWithNoAccessPolicy -NotePropertyValue $noPolicyTopics
				$controlResult.AddMessage([MessageData]::new("No Authorization rules defined for following Topic. Either Topic is not in use or namespace level access policy is used. Applications (senders/receivers) must not use access policies defined at Service Bus namespace level.", $noPolicyTopics));
			}

			$controlResult.SetStateData("Access policy with minimum required permission must be defined for the Queue/Topic", $failedClients);
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("Authorization rules for the Queue/Topic are defined at correct entity level and with limited permissions."));
		}

		return $controlResult;
	}
}