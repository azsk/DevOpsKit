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

	# This functions checks for both control level and resource level RBAC
	hidden [ControlResult] CheckResourceRBACAccess([ControlResult] $controlResult)
	{	
		$controlResult = $this.CheckRBACAccess($controlResult)
		
		if (-not [Helpers]::CheckMember($this.ResourceObject, "Properties.features.enableLogAccessUsingOnlyResourcePermissions"))
		{
			$controlResult.AddMessage("Unable to read access control mode of this workspace. Please follow the recommendation to verify this setting.");
		}
		elseif ($this.ResourceObject.Properties.features.enableLogAccessUsingOnlyResourcePermissions -eq "false")
		{
			$controlResult.VerificationResult = [VerificationResult]::Failed;
			$controlResult.AddMessage("The access control mode is set to 'Require workspace permissions'. Switch to Resource-specific mode for granular RBAC management.");
		}
		return $controlResult;
	}

	# This function lists the automation account connected to your workspace
	hidden [ControlResult] CheckLinkedAutomationAccountSPNsRBAC([ControlResult] $controlResult)
	{	
		$AzureManagementUri = [WebRequestHelper]::GetResourceManagerUrl()
		# Rest API to fetch linked automation account
		$uri = [system.string]::Format($AzureManagementUri + "subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}/LinkedServices/Automation?api-version=2015-11-01-preview", $this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName)
		try
		{
			$linkedServiceDetail = [WebRequestHelper]::InvokeGetWebRequest($uri);
			if (($linkedServiceDetail | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($linkedServiceDetail, "properties.resourceId"))
			{ 
				$AutomationAccountName = $linkedServiceDetail.properties.resourceId.Split(" / ")[-1]
				$controlResult.AddMessage([VerificationResult]::Verify, "Log analytics workspaces in linked to [$($AutomationAccountName)] automation account. Verify the RBAC access granted to its Run as Account.");
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

	# This function lists the data retention period for your logs
	hidden [ControlResult] CheckDataRetentionPeriod([ControlResult] $controlResult)
	{

		$controlResult.VerificationResult = [VerificationResult]::Verify;
		# Default retention - Applicable at workspace level
		$controlResult.AddMessage("The default data log retention period is: $($this.ResourceObject.Properties.retentionInDays)");

		# Retention by data type
		$AzureManagementUri = [WebRequestHelper]::GetResourceManagerUrl()
		# Rest API to fetch retention period of all data type
		$uri = [system.string]::Format($AzureManagementUri + "subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.OperationalInsights/workspaces/{2}/Tables?api-version=2017-04-26-preview", $this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName)
		try
		{
			$retentionByDataType = [WebRequestHelper]::InvokeGetWebRequest($uri);
			if (($retentionByDataType | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($retentionByDataType, "id"))
			{
				$ListOfDataTypeWithRetention = @()
				$ListOfDataTypeWithoutRetention = @()
				$retentionByDataType | ForEach-Object { 
					$Obj = "" | Select-Object DataTypeName, RetentionInDays
					if ([Helpers]::CheckMember($_, "properties.RetentionInDays"))
					{
						$Obj.DataTypeName = $_.name
						$Obj.RetentionInDays = $_.properties.RetentionInDays
						$ListOfDataTypeWithRetention += $Obj
					}
					else
					{
						$Obj.DataTypeName = $_.name
						$ListOfDataTypeWithoutRetention += $Obj
					}

				}
				
				if (($ListOfDataTypeWithRetention | Measure-Object).Count -gt 0)
				{
					$controlResult.AddMessage("Below is the list of data type (tables) where retention period is set:", $ListOfDataTypeWithRetention);
				}
				
				if (($ListOfDataTypeWithoutRetention | Measure-Object).Count -gt 0)
				{
					$controlResult.AddMessage("Below is the list of data type (tables) where retention period is not set (default retention period is applicable for these tables):", $ListOfDataTypeWithoutRetention.DataTypeName);
				}
			}
		}
		catch
		{
			# This is an empty block to avoid breaking the execution flow
		}

		return $controlResult;
	}

	# This function lists the solutions connected to your workspace along with publisher, containedResources and referencedResources details
	hidden [ControlResult] CheckSolutionsLinkedToWorkspace([ControlResult] $controlResult)
	{
		try
		{
			$AzureManagementUri = [WebRequestHelper]::GetResourceManagerUrl()
			$accessToken = [ContextHelper]::GetAccessToken($AzureManagementUri)
			if ($null -ne $accessToken)
			{
				$authorisationToken = "Bearer " + $accessToken
				$pathQuery = [system.string]::Format("/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.OperationsManagement/solutions?`$filter=properties/workspaceResourceId%2520eq%2520%2527{2}%2527&api-version=2015-11-01-preview", $this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName)
				$headers = @{
					"Authorization"   = $authorisationToken;
					"Content-Type"    = "application/json";
					"x-ms-path-query" = $pathQuery
				}
				$uri = "https://management.azure.com/api/invoke"

				# Rest API to fetch linked solutions' detail
				$linkedSolutionDetail = [WebRequestHelper]::InvokeGetWebRequest($uri, $headers);
				if (($linkedSolutionDetail | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($linkedSolutionDetail, "id"))
				{
					$linkedSolutionDetailCustomObj = @()
					$linkedSolutionDetail | ForEach-Object {

						$Obj = "" | Select-Object Name, Publisher, containedResources, referencedResources
						$Obj.Name = $_.plan.name
						$Obj.Publisher = $_.plan.publisher
						if ([Helpers]::CheckMember($_, "properties.containedResources"))
						{
							$Obj.containedResources = $_.properties.containedResources
						}
						if ([Helpers]::CheckMember($_, "properties.referencedResources"))
						{
							$Obj.referencedResources = $_.properties.referencedResources
						}
						
						$linkedSolutionDetailCustomObj += $Obj

					}
					$controlResult.AddMessage([VerificationResult]::Verify, "Verify the endpoints and azure resources accessed by the solution connected to your workspace.", $linkedSolutionDetailCustomObj);
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Passed, "No solution is linked to this workspace.");
				}
			}
		}
		catch
		{
			# If exception occur, control should go into Manual state
			$controlResult.AddMessage([VerificationResult]::Manual, "Unable to get linked solutions for - [$($this.ResourceContext.ResourceName)]. Please verify the solution connected to your workspace from portal.");
		}
		return $controlResult;
	}
}
