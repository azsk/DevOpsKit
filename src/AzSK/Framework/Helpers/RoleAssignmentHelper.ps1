using namespace Microsoft.Azure.Commands.Resources.Models.Authorization
Set-StrictMode -Version Latest 
class RoleAssignmentHelper
{
	static [PSRoleAssignment[]] GetAzSKRoleAssignmentByScope([string] $scope, [bool] $recurse, [bool] $includeClassicAdministrators)
	{
		[PSRoleAssignment[]] $roleAssignments = @();

		try
		{
			if($includeClassicAdministrators)
			{
				$roleAssignments = Get-AzureRmRoleAssignment -Scope $scope -IncludeClassicAdministrators -ErrorAction Stop;
			}
			else
			{
				$roleAssignments = Get-AzureRmRoleAssignment -Scope $scope -ErrorAction Stop;
			}
			return $roleAssignments;		
		}
		catch
		{ 
			# Eat the current exception which typically happens when the caller doesn't have access to GraphAPI. It will fall back to the below custom API based approach.
		}

		$requestUri = [WebRequestHelper]::AzureManagementUri + $scope;
		$roleAssignments = [RoleAssignmentHelper]::GetRMRoleAssignment($requestUri, $recurse);
		if($includeClassicAdministrators)
		{
			$roleAssignments += [RoleAssignmentHelper]::GetAzSKClassicAdministrators();
		}
		return $roleAssignments;		
	}

	static [PSRoleAssignment[]] GetAzSKRoleAssignment([bool] $recurse, [bool] $includeClassicAdministrators)
	{
		[PSRoleAssignment[]] $roleAssignments = @();
		try
		{
			if($includeClassicAdministrators)
			{
				$roleAssignments = Get-AzureRmRoleAssignment -IncludeClassicAdministrators -ErrorAction Stop;
			}
			else
			{
				$roleAssignments = Get-AzureRmRoleAssignment -ErrorAction Stop;
			}
			return $roleAssignments;
		}
		catch
		{ 
			# Eat the current exception which typically happens when the caller doesn't have access to GraphAPI. It will fall back to the below custom API based approach.
		}

		$roleAssignments = [RoleAssignmentHelper]::GetAzSKRoleAssignment("", "", "", $recurse, $includeClassicAdministrators);
		
		return $roleAssignments;		
	}

	static [PSRoleAssignment[]] GetAzSKRoleAssignment([string] $resourceGroupName, [bool] $recurse, [bool] $includeClassicAdministrators)
	{
		[PSRoleAssignment[]] $roleAssignments = @();
		try
		{
			if($includeClassicAdministrators)
			{
				$roleAssignments = Get-AzureRmRoleAssignment -ResourceGroupName $resourceGroupName -IncludeClassicAdministrators -ErrorAction Stop;
			}
			else
			{
				$roleAssignments = Get-AzureRmRoleAssignment -ResourceGroupName $resourceGroupName -ErrorAction Stop;
			}
			return $roleAssignments;
		}
		catch
		{ 
			# Eat the current exception which typically happens when the caller doesn't have access to GraphAPI. It will fall back to the below custom API based approach.
		}

		$roleAssignments = [RoleAssignmentHelper]::GetAzSKRoleAssignment($resourceGroupName, "", "", $recurse, $includeClassicAdministrators);
		
		return $roleAssignments;
	}

	static [PSRoleAssignment[]] GetAzSKRoleAssignment([string] $resourceGroupName, [string] $resourceName, [string] $resourceType, [bool] $recurse, [bool] $includeClassicAdministrators)
	{
		[PSRoleAssignment[]] $roleAssignments = @();
		try
		{
			if($includeClassicAdministrators)
			{
				$roleAssignments = Get-AzureRmRoleAssignment -ResourceGroupName $resourceGroupName -ResourceName $resourceName -ResourceType $resourceType -IncludeClassicAdministrators -ErrorAction Stop;
			}
			else
			{
				$roleAssignments = Get-AzureRmRoleAssignment -ResourceGroupName $resourceGroupName -ResourceName $resourceName -ResourceType $resourceType -ErrorAction Stop;
			}

			return $roleAssignments;
		}
		catch
		{ 
			# Eat the current exception which typically happens when the caller doesn't have access to GraphAPI. It will fall back to the below custom API based approach.
		}

		$currentContext = [Helpers]::GetCurrentRMContext();
        $subscriptionId = $currentContext.Subscription.Id;

		$subscriptionPath = "subscriptions/$subscriptionId";
		$resourceGroupPath = "/resourceGroups/$resourceGroupName";
		$resourceNamePath = "/providers/$resourceType/$resourceName";

		$requestUri = [WebRequestHelper]::AzureManagementUri + $subscriptionPath;

		if(-not [string]::IsNullOrEmpty($resourceGroupName))
		{
			$requestUri += $resourceGroupPath;
			if((-not [string]::IsNullOrEmpty($resourceType)) -and (-not [string]::IsNullOrEmpty($resourceName)))
			{
				$requestUri += $resourceNamePath;
			}
		}

		$roleAssignments = [RoleAssignmentHelper]::GetRMRoleAssignment($requestUri, $recurse);
		if($includeClassicAdministrators)
		{
			$roleAssignments += [RoleAssignmentHelper]::GetAzSKClassicAdministrators();
		}
		return $roleAssignments;
	}

	hidden static [PSRoleAssignment[]] GetRMRoleAssignment([string] $roleAssignmentUri, [bool] $recurse)
	{
		$recurseParam = "&`$filter=atScope()";
		$roleAssignmentPath = "/providers/Microsoft.Authorization/roleAssignments?api-version=2015-07-01";
		$roleAssignmentUri += $roleAssignmentPath;

		if(-not $recurse)
		{
			$roleAssignmentUri += $recurseParam;
		}

		$webResponse = [WebRequestHelper]::InvokeGetWebRequest($roleAssignmentUri);

		[PSRoleAssignment[]] $roleAssignments = @();
        $roleDefnMapping = @{}
        if(($webResponse | Measure-Object).Count -gt 0)
        {
			
			#get role definition details only for unique roles
			$webResponse.properties | Select-Object roleDefinitionId -Unique | ForEach-Object{
				$roleDefinitionId = $_.roleDefinitionId.Substring($_.roleDefinitionId.LastIndexOf("/") + 1);
				$roleDefinitionName = [string]::Empty
		
				$roleDefinition = (Get-AzureRmRoleDefinition -Id $roleDefinitionId -ErrorAction SilentlyContinue) | Select-Object -First 1
				if($roleDefinition -and [Helpers]::CheckMember($roleDefinition,"Name")) 
				{ 
					$roleDefinitionName = $roleDefinition.Name;
				}
				$roleDefnMapping.Add($roleDefinitionId,$roleDefinitionName)
			}
			#assign role name(roleDefinitionName) to each role assignment 
			$webResponse | ForEach-Object{
				try 
				{
					$roleDefinitionId = $_.properties.roleDefinitionId.Substring($_.properties.roleDefinitionId.LastIndexOf("/") + 1);
					$roleAssignments += [PSRoleAssignment]@{
					RoleAssignmentId = $_.id;
					Scope = $_.properties.scope;
					RoleDefinitionName = $roleDefnMapping[$roleDefinitionId];
					RoleDefinitionId = $roleDefinitionId;	
					ObjectId = $_.properties.principalId;
					};
				}
				catch 
				{
					[EventBase]::PublishException($_)
				}
			}
        }
        
		
		if($roleAssignments.Count -gt 0)
		{
			$objectIds = $roleAssignments | Select-Object -Property ObjectId -Unique | ForEach-Object { "$($_.ObjectId)" };
			$objectIdResponse = [RoleAssignmentHelper]::GetADObjectsByObjectIds($objectIds);
			
			$roleAssignments | ForEach-Object {
				$currentItem = $_;
				if($objectIdResponse.Count -ne 0)
				{
					$filteredResponse = $objectIdResponse | Where-Object { $_.ObjectId -eq $currentItem.ObjectId } | Select-Object -First 1
					if($filteredResponse)
					{
						$currentItem.ObjectType = $filteredResponse.objectType;
						$currentItem.DisplayName = $filteredResponse.displayName;
						if(($filteredResponse | Get-Member -Name "userPrincipalName"))
						{
							$currentItem.SignInName = $filteredResponse.userPrincipalName;
						}
					}
				}
				else
				{
					if(-not [string]::IsNullOrWhiteSpace($currentItem.ObjectId))
					{
						$currentItem.ObjectType = "NOGRAPHACCESS"
						$currentItem.DisplayName = "NOGRAPHACCESS"
						$currentItem.SignInName = "NOGRAPHACCESS"
					}
					else
					{
						$currentItem.ObjectId = [Guid]::Empty.Guid						
					}
				}
			}
		}

		return $roleAssignments;
	}

	hidden static [PSRoleAssignment[]] GetAzSKClassicAdministrators()
	{
		$currentContext = [Helpers]::GetCurrentRMContext();
        $subscriptionId = $currentContext.Subscription.Id;

		$subscriptionPath = "subscriptions/$subscriptionId";
		$requestUri = [WebRequestHelper]::AzureManagementUri + $subscriptionPath;
		$requestUri += "/providers/Microsoft.Authorization/classicAdministrators?api-version=2015-06-01";
		
		$webResponse = [WebRequestHelper]::InvokeGetWebRequest($requestUri);

		[PSRoleAssignment[]] $roleAssignments = @();
		$webResponse | 
		ForEach-Object {
			$roleAssignments += [PSRoleAssignment]@{
				SignInName = $_.properties.emailAddress;
				DisplayName = $_.properties.emailAddress;
				Scope = "/subscriptions/$subscriptionId";
				RoleDefinitionName = $_.properties.role;
				RoleDefinitionId = $_.id;	
				ObjectId = [Guid]::Empty.Guid;
				ObjectType = $_.properties.role
			};
		}

		return $roleAssignments;		
	}

	hidden static [System.Object[]] GetADObjectsByObjectIds([string[]] $objectIds)
	{
		$rmContext = [Helpers]::GetCurrentRMContext();
		$tenantId = $rmContext.Tenant.Id

		$uri = [WebRequestHelper]::GraphApiUri + "$tenantId/getObjectsByObjectIds?api-version=1.6"
		$body = "{`"objectIds`":" + ($objectIds | ConvertTo-Json ) + "}";
		$webResponse = @();
		
		try
		{
			$webResponse = [WebRequestHelper]::InvokePostWebRequest($uri, $body);
		}
		catch
		{
			# Access denied exception occurs here. It will fall back to the below custom API based approach.
		}
		return $webResponse;
	}

	hidden static [bool] HasGraphAccess()
	{
		$hasAccess = $false;
		$rmContext = [Helpers]::GetCurrentRMContext()
		$tenantId = $rmContext.Tenant.Id
	
		$uri = [WebRequestHelper]::GraphApiUri + "$tenantId/users?`$top=1&api-version=1.6"
		$webResponse = @();
		
		try
		{
			$webResponse = [WebRequestHelper]::InvokeGetWebRequest($uri);
			$hasAccess = $true;
		}
		catch
		{
			$hasAccess = $false;
		}
		return $hasAccess;
	}
}
