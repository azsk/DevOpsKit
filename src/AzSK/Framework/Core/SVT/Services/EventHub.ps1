#using namespace Microsoft.Azure.Commands.EventHub.Models
Set-StrictMode -Version Latest 
class EventHub: SVTBase
{       
	hidden [PSObject[]] $NameSpacePolicies;
	hidden [PSObject[]] $EventHubs;

    EventHub([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
		$this.GetEventHubDetails();
    }

	EventHub([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
		$this.GetEventHubDetails();
    }

	hidden [void] GetEventHubDetails()
    {
        if (-not $this.NameSpacePolicies) {
            $this.NameSpacePolicies = Get-AzureRmEventHubAuthorizationRule -ResourceGroupName $this.ResourceContext.ResourceGroupName `
						-NamespaceName $this.ResourceContext.ResourceName
        }

		if (-not $this.EventHubs) {
            $this.EventHubs = Get-AzureRmEventHub -ResourceGroupName $this.ResourceContext.ResourceGroupName -NamespaceName $this.ResourceContext.ResourceName
        }
    }

	hidden [ControlResult[]] CheckEventHubRootPolicy([ControlResult] $controlResult)
	{
		[ControlResult[]] $resultControlResultList = @()

		#region "NameSpace"
		[ControlResult] $childControlResult = [ControlResult]@{
                            #ChildResourceName = $this.ResourceContext.ResourceName;
                        };

		$childControlResult.SetStateData("Authorization rules for Event Hub Namespace", $this.NameSpacePolicies);

		$childControlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Following are the authorization rules for Namespace - ["+ $this.ResourceContext.ResourceName +"]. Validate that these rules must not be used at Event Hub level to send and receive messages.", 
				$this.NameSpacePolicies));   

		$resultControlResultList += $childControlResult
		#endregion        

		#region "Event Hub"
		
		if(($this.EventHubs|Measure-Object).count -gt 0)
		{
			foreach ($eventHub in $this.EventHubs)
			{
				[ControlResult] $childControlResult = [ControlResult]@{
						ChildResourceName = $eventHub.Name;
					};

				$eventHubPolicies = Get-AzureRmEventHubAuthorizationRule -ResourceGroupName $this.ResourceContext.ResourceGroupName `
										-NamespaceName $this.ResourceContext.ResourceName -EventHubName $eventHub.Name

				if(($eventHubPolicies|Measure-Object).count -gt 0)
				{
					$childControlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Validate that Event Hub - ["+ $eventHub.Name +"] must not use access policies defined at Namespace level."));
				}
				else
				{
					$childControlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("No Authorization rules defined for Event Hub - ["+ $eventHub.Name +"]. Applications (senders/receivers) must not use access policies defined at Event Hub namespace level."));
				}
				$resultControlResultList += $childControlResult
			}
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("Event Hub not available in Namespace - ["+ $this.ResourceContext.ResourceName +"]"));
		}
        
		#endregion
           
		return $resultControlResultList;
	}

	hidden [ControlResult[]] CheckEventHubAuthorizationRule([ControlResult] $controlResult)
	{
		[ControlResult[]] $resultControlResultList = @()

		#region "NameSpace"
		[ControlResult] $childControlResult = [ControlResult]@{
                            #ChildResourceName = $this.ResourceContext.ResourceName;
                        };

		$childControlResult.SetStateData("Authorization rules for Event Hub Namespace", $this.NameSpacePolicies);
		$childControlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Authorization rules for Namespace - ["+ $this.ResourceContext.ResourceName +"]. Validate that these rules are defined at correct entity level and with more limited permissions.", 
				$this.NameSpacePolicies));   

		$resultControlResultList += $childControlResult
		#endregion        

		#region "Event Hub"
		
		if(($this.EventHubs|Measure-Object).count -gt 0)
		{
			foreach ($eventHub in $this.EventHubs)
			{
				[ControlResult] $childControlResult = [ControlResult]@{
						ChildResourceName = $eventHub.Name;
					};

				$eventHubPolicies = Get-AzureRmEventHubAuthorizationRule -ResourceGroupName $this.ResourceContext.ResourceGroupName `
										-NamespaceName $this.ResourceContext.ResourceName -EventHubName $eventHub.Name

				if(($eventHubPolicies|Measure-Object).count -gt 0)
				{
					$childControlResult.SetStateData("Authorization rules for Event Hub:" + $eventHub.Name , $eventHubPolicies);
					$childControlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Authorization rules for Event Hub - ["+ $eventHub.Name +"]. Validate that these rules are defined at correct entity level and with more limited permissions.", $eventHubPolicies));
				}
				else
				{
					$childControlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No Authorization rules defined for Event Hub - ["+ $eventHub.Name +"]."));
				}
				$resultControlResultList += $childControlResult
			}
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("Event Hub not available in Namespace - ["+ $this.ResourceContext.ResourceName +"]"));
		}
        
		#endregion
           
		return $resultControlResultList;
	}
}