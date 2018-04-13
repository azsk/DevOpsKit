Set-StrictMode -Version Latest
class TrafficManager : SVTBase
{
	hidden [PSObject] $ResourceObject;
	
	TrafficManager([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName):
        Base($subscriptionId, $resourceGroupName, $resourceName)
    {
		   $this.GetResourceObject();
    }

    TrafficManager([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId, $svtResource)
    {
		   $this.GetResourceObject();
    }

	 hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject)
		{
		
            $this.ResourceObject = Get-AzureRmTrafficManagerProfile -Name $this.ResourceContext.ResourceName `
								-ResourceGroupName $this.ResourceContext.ResourceGroupName `
								-ErrorAction SilentlyContinue

            if(-not $this.ResourceObject)
            {
				throw ([SuppressedException]::new(("Resource '$($this.ResourceContext.ResourceName)' not found under Resource Group '$($this.ResourceContext.ResourceGroupName)'"), [SuppressedExceptionType]::InvalidOperation))
            }

	    }

        return $this.ResourceObject;
    }
	
	
	[ControlItem[]] ApplyServiceFilters([ControlItem[]] $controls)
	{
		if($controls.Count -eq 0)
		{
			return $controls;
		}

		$result = @();
		
		if([Helpers]::CheckMember($this.ResourceObject, "MonitorProtocol") -and $this.ResourceObject.MonitorProtocol -eq "TCP")
		{
            $result += $controls | Where-Object {$_.ControlID -ne "Azure_TrafficManager_DP_Enable_HTTPS" }
		}
		else{
			$result += $controls
		}

		
				
		return $result;
	}


	hidden [ControlResult] CheckTrafficManagerEndpointMonitorProtocol([ControlResult] $controlResult)
	{
			#Checking if endpoints are there or not in the profile
		if(($this.ResourceObject.Endpoints | Measure-Object).Count -gt 0)
		{
			$EnabledEndpointList =  $this.ResourceObject.Endpoints | Where-Object { $_.EndpointStatus -eq 'Enabled' }
			#check if all endpoints are not disabled
			if(($EnabledEndpointList | Measure-Object).Count -eq 0)
			{
				$controlResult.AddMessage([VerificationResult]::Passed,
										[MessageData]::new("All endpoints are disabled in the Traffic Manager profile ["+ $this.ResourceContext.ResourceName +"].")); 
			}
			else
			{
				if($this.ResourceObject.MonitorProtocol -eq 'HTTPS')
				{
					$controlResult.AddMessage([VerificationResult]::Passed,
										[MessageData]::new("The Traffic Manager profile ["+ $this.ResourceContext.ResourceName +"] is using HTTPS protocol for endpoint monitoring.")); 
				}
				else
				{
					$controlResult.EnableFixControl = $true;
					$controlResult.AddMessage([VerificationResult]::Failed,
										[MessageData]::new("The Traffic Manager profile ["+ $this.ResourceContext.ResourceName +"] is not using HTTPS protocol for endpoint monitoring.",$this.ResourceObject)); 
				}
			}
			
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed,
										[MessageData]::new("No endpoints found in the Traffic Manager profile ["+ $this.ResourceContext.ResourceName +"].")); 
		}
		
 
		return $controlResult;    
	}
}