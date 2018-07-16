using namespace Microsoft.Azure.Commands.Resources.Models.Authorization
Set-StrictMode -Version Latest 
class SecurityCenterHelper
{
	static [string] $ProviderNamespace = "Microsoft.Security";
	static [string] $PoliciesApi = "policies/default";
	static [string] $AlertsApi = "alerts";
	static [string] $TasksApi = "tasks";
	static [string] $SecurityStatusApi = "securityStatuses";
	static [string] $ApiVersion = "?api-version=2015-06-01-preview";

	static [System.Object[]] InvokeGetSecurityCenterRequest([string] $subscriptionId, [string] $apiType)
	{
		if([string]::IsNullOrWhiteSpace($subscriptionId))
		{
			throw [System.ArgumentException] ("The argument 'subscriptionId' is null");
		}

		if([string]::IsNullOrWhiteSpace($apiType))
		{
			throw [System.ArgumentException] ("The argument 'apiType' is null");
		}
		
		# Commenting this as it's costly call and expected to happen in Set-ASC/SSS/USS 
		#[SecurityCenterHelper]::RegisterResourceProvider();
	
		$uri = [WebRequestHelper]::AzureManagementUri + "subscriptions/$subscriptionId/providers/$([SecurityCenterHelper]::ProviderNamespace)/$($apiType)$([SecurityCenterHelper]::ApiVersion)";
        return [WebRequestHelper]::InvokeGetWebRequest($uri);
	}

	static [System.Object[]] InvokePutSecurityCenterRequest([string] $resourceId, [System.Object] $body)
	{
		if([string]::IsNullOrWhiteSpace($resourceId))
		{
			throw [System.ArgumentException] ("The argument 'resourceId' is null");
		}

		# Commenting this as it's costly call and expected to happen in Set-ASC/SSS/USS 
		#[SecurityCenterHelper]::RegisterResourceProvider();

		$uri = [WebRequestHelper]::AzureManagementUri.TrimEnd("/") + $resourceId + [SecurityCenterHelper]::ApiVersion;
		return [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $uri, $body);
	}


	hidden static [PSObject] InvokeGetASCTasks([string] $subscriptionId)
	{
		# Commenting this as it's costly call and expected to happen in Set-ASC/SSS/USS 
		#[SecurityCenterHelper]::RegisterResourceProvider();
		$ascTasks = [SecurityCenterHelper]::InvokeGetSecurityCenterRequest($subscriptionId, [SecurityCenterHelper]::TasksApi)
		$tasks = [AzureSecurityCenter]::GetASCTasks($ascTasks);		
		return $tasks;
	}

	static [void] RegisterResourceProvider()
	{
		[Helpers]::RegisterResourceProviderIfNotRegistered([SecurityCenterHelper]::ProviderNamespace);
	}

	static [void] RegisterResourceProviderNoException()
	{
		try
		{
			[SecurityCenterHelper]::RegisterResourceProvider();
		}
		catch
		{ 
			[EventBase]::PublishGenericException($_);
		}
	}
}
