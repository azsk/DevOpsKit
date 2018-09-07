using namespace Microsoft.Azure.Commands.Resources.Models.Authorization
Set-StrictMode -Version Latest 
class SecurityCenterHelper
{
	static [string] $ProviderNamespace = "Microsoft.Security";
	static [string] $PoliciesApi = "policies/default";
	static [string] $AlertsApi = "alerts";
	static [string] $AutoProvisioningSettingsApi = "autoProvisioningSettings";
	static [string] $SecurityContactsApi = "securityContacts";
	static [string] $TasksApi = "tasks";
	static [string] $SecurityStatusApi = "securityStatuses";
	static [string] $ApiVersion = "?api-version=2015-06-01-preview";
	static [string] $ApiVersionNew = "?api-version=2017-08-01-preview";
	static [string] $ApiVersionLatest = "?api-version=2018-03-01";

	static [Hashtable] AuthHeaderFromUri([string] $uri)
		{
		[System.Uri] $validatedUri = $null;
        if([System.Uri]::TryCreate($uri, [System.UriKind]::Absolute, [ref] $validatedUri))
		{
			return @{
				"Authorization"= ("Bearer " + [Helpers]::GetAccessToken($validatedUri.GetLeftPart([System.UriPartial]::Authority))); 
				"Content-Type"="application/json"
			};

		}
		
		return @{ "Content-Type"="application/json" };
	}
	
	static [System.Object[]] InvokeGetSecurityCenterRequest([string] $subscriptionId, [string] $apiType, [string] $apiVersion)
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
	
		$uri = [WebRequestHelper]::AzureManagementUri + "subscriptions/$subscriptionId/providers/$([SecurityCenterHelper]::ProviderNamespace)/$($apiType)$($apiVersion)";
        return [WebRequestHelper]::InvokeGetWebRequest($uri);
	}

	static [System.Object[]] InvokePutSecurityCenterRequest([string] $resourceId, [System.Object] $body, [string] $apiVersion)
	{
		if([string]::IsNullOrWhiteSpace($resourceId))
		{
			throw [System.ArgumentException] ("The argument 'resourceId' is null");
		}

		# Commenting this as it's costly call and expected to happen in Set-ASC/SSS/USS 
		#[SecurityCenterHelper]::RegisterResourceProvider();

		$uri = [WebRequestHelper]::AzureManagementUri.TrimEnd("/") + $resourceId + $apiVersion;
		return [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $uri, $body);
	}


	hidden static [PSObject] InvokeGetASCTasks([string] $subscriptionId)
	{
		# Commenting this as it's costly call and expected to happen in Set-ASC/SSS/USS 
		#[SecurityCenterHelper]::RegisterResourceProvider();
		$ascTasks = [SecurityCenterHelper]::InvokeGetSecurityCenterRequest($subscriptionId, [SecurityCenterHelper]::TasksApi, [SecurityCenterHelper]::ApiVersion)
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
