Set-StrictMode -Version Latest

class CosmosDb : SVTBase
{
	hidden [PSObject] $Resource;

	CosmosDb([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
	{
		$this.LoadResource();
	}

	hidden [void] LoadResource()
	{
		if(-not $this.Resource)
		{
			$this.Resource = Get-AzureRmResource -Name $this.ResourceContext.ResourceName `
											-ResourceGroupName $this.ResourceContext.ResourceGroupName `
											-ResourceType $this.ResourceContext.ResourceType
            if(-not $this.Resource)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
		}
	}
	
	[ControlResult] CheckCosmosDbFirewallState([ControlResult] $controlResult)
	{
		return $this.EvalBoolean($controlResult, -not [string]::IsNullOrWhiteSpace($this.Resource.Properties.ipRangeFilter))
	}

	[ControlResult] CheckCosmosDbFirewallIpRange([ControlResult] $controlResult)
	{
		if([string]::IsNullOrWhiteSpace($this.Resource.Properties.ipRangeFilter))
		{
			$controlResult.AddMessage([VerificationResult]::Failed, "Control cannot be validated. Firewall is not enabled for - ["+ $this.ResourceContext.ResourceName +"]");
			return $controlResult
		}
		$controlResult.VerificationResult = [VerificationResult]::Verify
		$totalIpLimit = $this.ControlSettings.CosmosDb.Firewall.IpLimitPerDb
		$limit = $this.ControlSettings.CosmosDb.Firewall.IpLimitPerRange
		$isPassed = 1
		$rangeFilter = $this.Resource.Properties.ipRangeFilter
		$ranges = $rangeFilter.Split(',')
		$controlResult.AddMessage([MessageData]::new(
			"Current firewall IP range(s) for - ["+ $this.ResourceContext.ResourceName +"]", $ranges));
		$totalIps = 0
		foreach($range in $ranges)
		{
			if($range.Contains('/'))
			{
				$mask = [int]($range.Split('/')[1])
				$ipCount = [Math]::Pow(2, 32 - $mask)
				$totalIps += $ipCount
				if($ipCount -gt $limit)
				{
					$isPassed = $isPassed -band 0
					$controlResult.AddMessage("Range - $range has $ipCount IPs which is more than $limit IP limit per range.")
				}
			}
			else
			{
				$totalIps += 1
			}
		}
		if($totalIps -gt $totalIpLimit)
		{
			$isPassed = $isPassed -band 0
			$controlResult.AddMessage("Total IPs allowed is $totalIps which is more than $totalIpLimit IP total limit per db.")
		}
		if($isPassed -eq 0)
		{
			$controlResult.VerificationResult = [VerificationResult]::Failed
		}
		$controlResult.SetStateData("Firewall IP ranges/addresses:", $ranges)
		return $controlResult
	}

	[ControlResult] CheckCosmosDbConsistency([ControlResult] $controlResult)
	{
		return $this.EvalBoolean($controlResult, 
			-not $this.Resource.Properties.consistencyPolicy.defaultConsistencyLevel.Equals(
				"Eventual", [System.StringComparison]::OrdinalIgnoreCase));
	}

	[ControlResult] CheckCosmosDbReplication([ControlResult] $controlResult)
	{
		return $this.EvalBoolean($controlResult, $this.Resource.Properties.readLocations.Count -gt 1);
	}

	[ControlResult] CheckCosmosDbAutomaticFailover([ControlResult] $controlResult)
	{
		return $this.EvalBoolean($controlResult, $this.Resource.Properties.enableAutomaticFailover);
	}

	hidden [ControlResult] EvalBoolean([ControlResult] $controlResult, [Boolean] $IsPassed)
	{
		if($IsPassed)
		{
			$controlResult.VerificationResult = [VerificationResult]::Passed
			return $controlResult
		}
		$controlResult.VerificationResult = [VerificationResult]::Failed
		return $controlResult
	}
}
