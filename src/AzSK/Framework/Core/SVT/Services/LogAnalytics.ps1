Set-StrictMode -Version Latest 
class LogAnalytics: AzSVTBase
{       
	hidden [PSObject] $ResourceObject;

	LogAnalytics([string] $subscriptionId, [SVTResource] $svtResource): 
	Base($subscriptionId, $svtResource)
	{
		$this.GetResourceObject();
	}

	hidden [PSObject] GetResourceObject()
 {
		if (-not $this.ResourceObject)
		{
			$this.ResourceObject = Get-AzResource -ResourceId $this.ResourceId
			if (-not $this.ResourceObject)
			{
				throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
			}
		}

		return $this.ResourceObject;
	}

	hidden [ControlResult] CheckResourceRBACAccess([ControlResult] $controlResult)
	{	
		$controlResult = $this.CheckRBACAccess($controlResult, $this.AccessList)
		if ($this.ResourceObject.Properties.features.enableLogAccessUsingOnlyResourcePermissions -eq "false")
		{
			$controlResult.VerificationResult = [VerificationResult]::Failed;
			$controlResult.AddMessage("The access control mode is set to 'Require workspace permissions'. Switch to Resource-specific mode for better RBAC management.");
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckLinkedAutomationAccountSPNsRBAC([ControlResult] $controlResult)
	{	
		$linkedServiceDetail = 
		$AzureManagementUri = [WebRequestHelper]::GetResourceManagerUrl()
		$uri = [system.string]::Format($AzureManagementUri + "subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{3}/LinkedServices/Automation?api-version=2015-11-01-preview", $this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName)
		try
		{
			$linkedServiceDetail = [WebRequestHelper]::InvokeGetWebRequest($uri);
			if (($linkedServiceDetail | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($linkedServiceDetail, "properties.resourceId"))
			{ 
				$AutomationAccountName = $linkedServiceDetail.properties.resourceId.Split(" / ")[-1]
				$controlResult.AddMessage([VerificationResult]::Verify, "Log analytics workspaces in linked to [$($AutomationAccountName)] automation account.");
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, "No linked automation account found for - [$($this.ResourceContext.ResourceName)].");
			}
		}
		catch
		{
			# If exception occur, control should go into Manual state
			$controlResult.AddMessage([VerificationResult]::Manual, "Unable to get linked automation account for - [$($this.ResourceContext.ResourceName)].");
		}
		
		return $controlResult;
	}

	hidden [ControlResult] CheckDataRetentionPeriod([ControlResult] $controlResult)
	{
		$controlResult.VerificationResult = [VerificationResult]::Verify;
		$controlResult.AddMessage("The data log retention period is set to $($this.ResourceObject.Properties.retentionInDays)");
		return $controlResult;
	}
}
