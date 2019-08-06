#using namespace Microsoft.Azure.Commands.EventHub.Models
Set-StrictMode -Version Latest 
class EventHub: AzSVTBase
{       
	hidden [PSObject[]] $NamespacePolicies = @();
	hidden [PSObject[]] $EventHubs = @();
	hidden [HashTable] $EHChildAccessPolicies = @{};

	EventHub([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
		$this.GetEventHubDetails();
		$this.GetEHAccessPolicies();
    }

	hidden [void] GetEventHubDetails()
    {
        if (-not $this.NamespacePolicies) {
			try
			{
				$this.NamespacePolicies = (Get-AzEventHubAuthorizationRule -ResourceGroupName $this.ResourceContext.ResourceGroupName `
						-NamespaceName $this.ResourceContext.ResourceName | Select-Object Id, Name, Rights)
			}
			catch
			{
				# This block is intentionally left blank to handle exception while fetching namespace access policy
			}
            
        }

		if (-not $this.EventHubs) {
			try
			{
				$this.EventHubs = Get-AzEventHub -ResourceGroupName $this.ResourceContext.ResourceGroupName -NamespaceName $this.ResourceContext.ResourceName
			}
			catch
			{
				# This block is intentionally left blank to handle exception while fetching eventhub of namespace
			}
        }
    }

	hidden [void] GetEHAccessPolicies()
	{
		#region "Event Hub"
		
		if(($this.EventHubs|Measure-Object).count -gt 0)
		{
			foreach ($eventHub in $this.EventHubs)
			{
				try
				{
					$eventHubPolicies = Get-AzEventHubAuthorizationRule -ResourceGroupName $this.ResourceContext.ResourceGroupName `
										-NamespaceName $this.ResourceContext.ResourceName -EventHubName $eventHub.Name

					$this.EHChildAccessPolicies.Add($eventHub, ($eventHubPolicies | Select-Object Id, Name, Rights))	
				}
				catch
				{
					# This block is intentionally left blank to handle exception while fetching eventhub access policies
				}
			}
		}
        
		#endregion
	}

	hidden [ControlResult[]] CheckEventHubRootPolicy([ControlResult] $controlResult)
	{
		$isControlFailed = $false
		
		#region "NameSpace"

		if(($this.NamespacePolicies | Measure-Object).count -gt 1)
		{
			$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Authorization rules for Event Hub namespace - ["+ $this.ResourceContext.ResourceName +"]. All the authorization rules except 'RootManageSharedAccessKey' must be removed from namespace level. Also validate that 'RootManageSharedAccessKey' authorization rule must not be used at Event Hub level to send and receive messages.", 
				$this.NamespacePolicies));   	
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Authorization rules for namespace - ["+ $this.ResourceContext.ResourceName +"]. Validate that these rules must not be used at Event Hub level to send and receive messages.", 
				$this.NamespacePolicies));   	
		}

		$controlResult.SetStateData("Authorization rules for namespace entities", $this.NamespacePolicies);

		#endregion        

		return $controlResult;
	}

	hidden [ControlResult[]] CheckEventHubAuthorizationRule([ControlResult] $controlResult)
	{
		$isControlFailed = $false
		$fullPermissionEventHubs = @();
		$noPolicyEventHubs = @();

		#region "Event Hub"
		
		if(($this.EventHubs|Measure-Object).count -gt 0)
		{
			foreach ($eventHub in $this.EventHubs)
			{
				if($this.EHChildAccessPolicies.ContainsKey($eventHub) -and ($this.EHChildAccessPolicies[$eventHub] |Measure-Object).count -gt 0)
				{
					foreach ($policy in $this.EHChildAccessPolicies[$eventHub])
					{
						if(($policy.Rights | Measure-Object).count -gt 1)
						{
							$fullPermissionEventHubs += $policy
							$isControlFailed = $true
						}
					}
				}
				else
				{
					$noPolicyEventHubs += $eventHub.Name
					$isControlFailed = $true
				}
			}

			if($isControlFailed)
			{
				$controlResult.VerificationResult = [VerificationResult]::Failed;

				$faliedClients = New-Object -TypeName PSObject 
				if(($fullPermissionEventHubs | Measure-Object).count -gt 0)
				{
					$faliedClients | Add-Member -NotePropertyName FailedEventHub -NotePropertyValue $fullPermissionEventHubs
					$controlResult.AddMessage([MessageData]::new("Validate the authorization rules for the Event Hub are defined with limited permissions.", $fullPermissionEventHubs));
				}
				if(($noPolicyEventHubs | Measure-Object).count -gt 0)
				{
					if([Helpers]::CheckMember($faliedClients,"FailedEventHub"))
					{
						$faliedClients.FailedEventHub += $noPolicyEventHubs
					}
					else
					{
						$faliedClients | Add-Member -NotePropertyName FailedEventHub -NotePropertyValue $noPolicyEventHubs
					}
					
					$controlResult.AddMessage([MessageData]::new("No Authorization rules defined for following Event Hub. Either Event Hub is not in use or namespace level access policy is used. Applications (senders/receivers) must not use access policies defined at Service Bus namespace level.", $noPolicyEventHubs));
				}

				$controlResult.SetStateData("Access policy with minimum required permission must be defined for the Event Hub", $faliedClients);
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("Authorization rules for the Event Hub are defined at correct entity level and with limited permissions."));
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("Event Hub not available in namespace - ["+ $this.ResourceContext.ResourceName +"]"));
		}
        
		#endregion

		return $controlResult;
	}
}