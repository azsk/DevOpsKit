#using namespace Microsoft.Azure.Commands.ServiceBus.Models
Set-StrictMode -Version Latest 
class ServiceBus: SVTBase
{       
	hidden [PSObject[]] $NameSpacePolicies;
	hidden [PSObject[]] $Queues;
	hidden [PSObject[]] $Topics;

    ServiceBus([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
    }

	ServiceBus([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
		$this.GetServiceBusDetails();
    }

	hidden [void] GetServiceBusDetails()
    {
        if (-not $this.NameSpacePolicies) {
            $this.NameSpacePolicies = Get-AzureRmServiceBusAuthorizationRule -ResourceGroup $this.ResourceContext.ResourceGroupName `
						-NamespaceName $this.ResourceContext.ResourceName
        }
		
		# Get All Queues
		if (-not $this.Queues) {
            $this.Queues = Get-AzureRmServiceBusQueue -ResourceGroup $this.ResourceContext.ResourceGroupName -NamespaceName $this.ResourceContext.ResourceName
        }

		if (-not $this.Topics) {
            $this.Topics = Get-AzureRmServiceBusTopic -ResourceGroup $this.ResourceContext.ResourceGroupName -NamespaceName $this.ResourceContext.ResourceName
        }
    }

	hidden [ControlResult[]] CheckServiceBusRootPolicy([ControlResult] $controlResult)
	{
		[ControlResult[]] $resultControlResultList = @()

		#region "NameSpace"
		[ControlResult] $childControlResult = [ControlResult]@{
                            #ChildResourceName = $this.ResourceContext.ResourceName;
                        };

		$childControlResult.SetStateData("Authorization rules for Namespace", $this.NameSpacePolicies);

		$childControlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Authorization rules for Namespace - ["+ $this.ResourceContext.ResourceName +"]. Validate that these rules must not be used at Queue/Topic level to send and receive messages.", 
				$this.NameSpacePolicies));   
		
		$resultControlResultList += $childControlResult

		#endregion        

		#region "Queue"
		
		if(($this.Queues|Measure-Object).count -gt 0)
		{
			foreach ($queue in $this.Queues)
			{
				[ControlResult] $childControlResult = [ControlResult]@{
						ChildResourceName = $queue.Name;
					};

				$queuePolicies = Get-AzureRmServiceBusAuthorizationRule -ResourceGroup $this.ResourceContext.ResourceGroupName `
										-NamespaceName $this.ResourceContext.ResourceName -Queue $queue.Name

				if(($queuePolicies|Measure-Object).count -gt 0)
				{
					$childControlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Validate that Queue - ["+ $queue.Name +"] must not use access policies defined at Service Bus namespace level."));
				}
				else
				{
					$childControlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("No Authorization rules defined for Queue - ["+ $queue.Name +"]. Applications (senders/receivers) must not use access policies defined at Service Bus namespace level."));
				}
				$resultControlResultList += $childControlResult
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
				[ControlResult] $childControlResult = [ControlResult]@{
						ChildResourceName = $topic.Name;
					};

				$topicPolicies = Get-AzureRmServiceBusAuthorizationRule -ResourceGroup $this.ResourceContext.ResourceGroupName `
										-NamespaceName $this.ResourceContext.ResourceName -Topic $topic.Name

				if(($topicPolicies|Measure-Object).count -gt 0)
				{
					$childControlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Validate that Topic - ["+ $topic.Name +"] must not use access policies defined at Service Bus namespace level."));
				}
				else
				{
					$childControlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("No Authorization rules defined for Topic - ["+ $topic.Name +"]. Applications (senders/receivers) must not use access policies defined at Service Bus namespace level."));
				}
				$resultControlResultList += $childControlResult
			}
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("Topics not available in Namespace - ["+ $this.ResourceContext.ResourceName +"]"));
		}

		#endregion

		return $resultControlResultList;
	}

	hidden [ControlResult[]] CheckServiceBusAuthorizationRule([ControlResult] $controlResult)
	{
		[ControlResult[]] $resultControlResultList = @()

		#region "NameSpace"
		[ControlResult] $childControlResult = [ControlResult]@{
                            #ChildResourceName = $this.ResourceContext.ResourceName;
                        };

		$childControlResult.SetStateData("Authorization rules for Namespace", $this.NameSpacePolicies);
		$childControlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Authorization rules for Namespace - ["+ $this.ResourceContext.ResourceName +"]. Validate that these rules are defined at correct entity level and with more limited permissions.", 
				$this.NameSpacePolicies));   

		$resultControlResultList += $childControlResult
		#endregion        

		#region "Queue"
		
		if(($this.Queues|Measure-Object).count -gt 0)
		{
			foreach ($queue in $this.Queues)
			{
				[ControlResult] $childControlResult = [ControlResult]@{
						ChildResourceName = $queue.Name;
					};

				$queuePolicies = Get-AzureRmServiceBusAuthorizationRule -ResourceGroup $this.ResourceContext.ResourceGroupName `
										-NamespaceName $this.ResourceContext.ResourceName -Queue $queue.Name

				if(($queuePolicies|Measure-Object).count -gt 0)
				{
					$childControlResult.SetStateData("Authorization rules for Queue:" + $queue.Name , $queuePolicies);
					$childControlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Authorization rules for Queue - ["+ $queue.Name +"]. Validate that these rules are defined at correct entity level and with more limited permissions.", $queuePolicies));
				}
				else
				{
					$childControlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No Authorization rules defined for Queue - ["+ $queue.Name +"]."));
				}
				$resultControlResultList += $childControlResult
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
				[ControlResult] $childControlResult = [ControlResult]@{
						ChildResourceName = $topic.Name;
					};

				$topicPolicies = Get-AzureRmServiceBusAuthorizationRule -ResourceGroup $this.ResourceContext.ResourceGroupName `
										-NamespaceName $this.ResourceContext.ResourceName -Topic $topic.Name

				if(($topicPolicies|Measure-Object).count -gt 0)
				{
					$childControlResult.SetStateData("Authorization rules for Topic:" + $topic.Name , $topicPolicies);
					$childControlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Authorization rules for Topic - ["+ $topic.Name +"]. Validate that these rules are defined at correct entity level and with more limited permissions.", $topicPolicies));
				}
				else
				{
					$childControlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No Authorization rules defined for Topic - ["+ $topic.Name +"]."));
				}
				$resultControlResultList += $childControlResult
			}
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("Topics not available in Namespace - ["+ $this.ResourceContext.ResourceName +"]"));
		}

		#endregion

		return $resultControlResultList;
	}
}