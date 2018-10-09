#using namespace Microsoft.Azure.Commands.EventHub.Models
Set-StrictMode -Version Latest 
class EventHub: SVTBase
{       
	hidden [PSObject[]] $NamespacePolicies = @();
	hidden [PSObject[]] $EventHubs = @();
	hidden [HashTable] $EHChildAccessPolicies = @{};
	hidden [PSObject] $EHAccessPolicies;

    EventHub([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
		$this.GetEventHubDetails();
		$this.GetEHAccessPolicies();
    }

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
				$this.NamespacePolicies = (Get-AzureRmEventHubAuthorizationRule -ResourceGroupName $this.ResourceContext.ResourceGroupName `
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
				$this.EventHubs = Get-AzureRmEventHub -ResourceGroupName $this.ResourceContext.ResourceGroupName -NamespaceName $this.ResourceContext.ResourceName
			}
			catch
			{
				# This block is intentionally left blank to handle exception while fetching eventhub of namespace
			}
            
        }
		
		$this.EHAccessPolicies = New-Object -TypeName PSObject 
		$this.EHAccessPolicies | Add-Member -NotePropertyName NameSpacePolicies -NotePropertyValue $this.NamespacePolicies 
		$this.EHAccessPolicies | Add-Member -NotePropertyName EHChildAccessPolicies -NotePropertyValue $this.EHChildAccessPolicies
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
					$eventHubPolicies = Get-AzureRmEventHubAuthorizationRule -ResourceGroupName $this.ResourceContext.ResourceGroupName `
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

		$this.EHAccessPolicies.EHChildAccessPolicies = $this.EHChildAccessPolicies
		
	}

	hidden [ControlResult[]] CheckEventHubRootPolicy([ControlResult] $controlResult)
	{
		$isControlFailed = $false
		
		#region "NameSpace"

		$controlResult.SetStateData("Authorization rules for Eventhub namespace and child entities", $this.EHAccessPolicies);
		$controlResult.AddMessage([MessageData]::new("Following are the authorization rules for namespace - ["+ $this.ResourceContext.ResourceName +"]. Validate that these rules must not be used at Event Hub level to send and receive messages.", 
				$this.NamespacePolicies))

		#endregion        

		#region "Event Hub"
		
		if(($this.EventHubs|Measure-Object).count -gt 0)
		{
			foreach ($eventHub in $this.EventHubs)
			{
				
				if($this.EHChildAccessPolicies.ContainsKey($eventHub) -and ($this.EHChildAccessPolicies[$eventHub] |Measure-Object).count -gt 0)
				{
					$controlResult.AddMessage([MessageData]::new("Validate that Event Hub - ["+ $eventHub.Name +"] must not use access policies defined at Event Hub namespace level."));
				}
				else
				{
					$isControlFailed = $true
					$controlResult.AddMessage([MessageData]::new("No Authorization rules defined for Event Hub - ["+ $eventHub.Name +"]. Applications (senders/receivers) must not use access policies defined at Event Hub namespace level."));
					$controlResult.AddMessage([MessageData]::new("Either Event Hub is not in use or namespace level access policy is used by the Event Hub"));
				}
			}
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("Event Hub not available in namespace - ["+ $this.ResourceContext.ResourceName +"]"));
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

	hidden [ControlResult[]] CheckEventHubAuthorizationRule([ControlResult] $controlResult)
	{
		#region "NameSpace"
		
		$controlResult.SetStateData("Authorization rules for Eventhub namespace and child entities", $this.EHAccessPolicies);
		$controlResult.AddMessage([MessageData]::new("Authorization rules for Eventhub namespace - ["+ $this.ResourceContext.ResourceName +"]. Validate that these rules are defined at correct entity level and with limited permissions.", 
				$this.NamespacePolicies));   

		#endregion        

		#region "Event Hub"
		
		if(($this.EventHubs|Measure-Object).count -gt 0)
		{
			foreach ($eventHub in $this.EventHubs)
			{

				if($this.EHChildAccessPolicies.ContainsKey($eventHub) -and ($this.EHChildAccessPolicies[$eventHub] |Measure-Object).count -gt 0)
				{
					$controlResult.AddMessage([MessageData]::new("Authorization rules for Event Hub - ["+ $eventHub.Name +"]. Validate that these rules are defined at correct entity level and with limited permissions.", $this.EHChildAccessPolicies[$eventHub]));
				}
			}
		}
		else
		{
			$controlResult.AddMessage([MessageData]::new("Event Hub not available in namespace - ["+ $this.ResourceContext.ResourceName +"]"));
		}
        
		#endregion
           
		$controlResult.VerificationResult = [VerificationResult]::Verify;

		return $controlResult;
	}
}