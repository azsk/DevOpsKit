using namespace Microsoft.Azure.Commands.Resources.Models.Authorization
Set-StrictMode -Version Latest 
class SecurityCenterHelper
{
	static [string] $ProviderNamespace = "Microsoft.Security";
	static [string] $PolicyProviderNamespace = "Microsoft.PolicyInsights";
	static [string] $PoliciesApi = "policies/default";
	static [string] $AlertsApi = "alerts";
	static [string] $AutoProvisioningSettingsApi = "autoProvisioningSettings";
	static [string] $SecurityContactsApi = "securityContacts";
	static [string] $TasksApi = "tasks";
	static [string] $SecurityStatusApi = "securityStatuses";
	static [string] $ApiVersion = "?api-version=2015-06-01-preview";
	static [string] $ApiVersionNew = "?api-version=2017-08-01-preview";
	static [string] $ApiVersionLatest = "?api-version=2019-09-01";
	static [string] $NewApiVersionForSecContact = "?api-version=2020-01-01-preview";
	static [PSObject] $Recommendations = $null;
	

	static [Hashtable] AuthHeaderFromUri([string] $uri)
		{
		[System.Uri] $validatedUri = $null;
        if([System.Uri]::TryCreate($uri, [System.UriKind]::Absolute, [ref] $validatedUri))
		{
			return @{
				"Authorization"= ("Bearer " + [ContextHelper]::GetAccessToken($validatedUri.GetLeftPart([System.UriPartial]::Authority))); 
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
	    $rmContext = [ContextHelper]::GetCurrentRMContext();
		$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()
		$uri = $ResourceAppIdURI + "subscriptions/$subscriptionId/providers/$([SecurityCenterHelper]::ProviderNamespace)/$($apiType)$($apiVersion)";
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
        $rmContext = [ContextHelper]::GetCurrentRMContext();
		$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()
		$uri = $ResourceAppIdURI.TrimEnd("/") + $resourceId + $apiVersion;
		return [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $uri, $body);
	}

	static [PSObject] InvokeSecurityCenterSecurityStatus([string] $subscriptionId, [string] $resourceId)
	{
		try 
		{ 	
			if((-not [string]::IsNullOrEmpty($subscriptionId)) -and (-not [String]::IsNullOrEmpty($resourceId))) 
			{
				$rmContext = [ContextHelper]::GetCurrentRMContext();
		        $ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()
				$uri = [System.String]::Format("{0}subscriptions/{1}/providers/microsoft.Security/securityStatuses?api-version=2015-06-01-preview&`$filter=tolower(Id)%20eq%20tolower('{2}/providers/Microsoft.Security/securityStatuses/{3}')", $ResourceAppIdURI, $subscriptionId, $resourceId, $resourceId.Split("/")[-1])
				$result = [WebRequestHelper]::InvokeGetWebRequest($uri);					
				if(($result | Measure-Object).Count -gt 0)
				{
					return $result				
				}										
			}				
			return $null
		} 
		catch
		{ 
			return $null;
		}       
	}


	hidden static [PSObject] InvokeGetASCTasks([string] $subscriptionId)
	{
		# Commenting this as it's costly call and expected to happen in Set-ASC/SSS/USS 
		#[SecurityCenterHelper]::RegisterResourceProvider();
		if(([SecurityCenterHelper]::Recommendations | Measure-Object).Count -eq 0)
		{
			$ascTasks = [SecurityCenterHelper]::InvokeGetSecurityCenterRequest($subscriptionId, [SecurityCenterHelper]::TasksApi, [SecurityCenterHelper]::ApiVersion)
			$tasks = [AzureSecurityCenter]::GetASCTasks($ascTasks);		
			[SecurityCenterHelper]::Recommendations = $tasks;
		}
		return [SecurityCenterHelper]::Recommendations;
	}

	static [void] RegisterResourceProvider()
	{
		[ResourceHelper]::RegisterResourceProviderIfNotRegistered([SecurityCenterHelper]::PolicyProviderNamespace);
		[ResourceHelper]::RegisterResourceProviderIfNotRegistered([SecurityCenterHelper]::ProviderNamespace);
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


class ASCTelemetryHelper {
	[string] $SubscriptionId = "";
    [string] $ASCTier = "";
    [PSObject[]] $ResourceTier = $null;
    [PSObject] $SecurityContactSettings = $null;
    [PSObject] $SecureScore = $null;
    [PSObject] $WorkspaceSettings = $null;
    [string] $SecurityEventsTier = "";
    [PSObject[]] $ASCRecommendations = $null;
    [PSObject[]] $ThreatDetection = $null;
	[string] $AutoProvisioningStatus = "";
	static [ASCTelemetryHelper] $ascData = $null;

 	ASCTelemetryHelper([string] $subscriptionId, [string] $ascTierSetting, [string] $autoProvisioningSettings, [PSObject] $securityContacts)
	{
		$this.SubscriptionId = $subscriptionId;
		$this.ASCTier = $ascTierSetting;
		$this.AutoProvisioningStatus = $autoProvisioningSettings;
		$this.SecurityContactSettings = $securityContacts;
		$this.UpdateCurrentInstance();
	}

 	[void] UpdateCurrentInstance()
	{
		$this.GetASCTierResourceWise();
		#Some API calls have been commented as we are yet to decide whether we can use them or not
		#$this.GetSecureScore();
		#$this.GetThreatDetectionSettings();
		#$this.GetASCRecommendations();
		$this.GetWorkspaceSettings();
		#$this.GetSecurityEventsTier();

 		[ASCTelemetryHelper]::ascData = $this;
	}

 	[void] GetASCTierResourceWise()
	{
		$ResourceUrl= [WebRequestHelper]::GetResourceManagerUrl()
		$validatedUri = "$ResourceUrl/subscriptions/$($this.SubscriptionId)/providers/Microsoft.Security/pricings?api-version=2018-06-01"
		$ascTierResourceWiseDetails = [WebRequestHelper]::InvokeGetWebRequest($validatedUri)

  		$ascTierResourceWiseDetailsList = [System.Collections.ArrayList]::new()
		foreach($resourceDetails in $ascTierResourceWiseDetails)
		{
			if([Helpers]::CheckMember($resourceDetails,"name"))
			{
				if([Helpers]::CheckMember($resourceDetails,"properties.pricingTier"))
				{
					$ASCResourceTier = New-Object psobject -Property @{
						Name = $resourceDetails.name;
						Tier = $resourceDetails.properties.pricingTier;
					}
					$ascTierResourceWiseDetailsList.Add($ASCResourceTier) | Out-Null
				}
			}
		}

  		$this.ResourceTier = $ascTierResourceWiseDetailsList;
	}

 	[void] GetSecureScore()
	{
		$uri = "https://s2.security.ext.azure.com/api/SecureScore/subscriptions";
		$body = '{"subscriptionId":["'+$this.SubscriptionId+'"],"limitedSelectedSubscriptionIds":[],"shouldRetrieveDataForLimitedSubscriptions":false}';

 		$result = $this.GetContentFromPostRequest($uri, $body);

 		if($null -eq $result)
		{
			$this.SecureScore = $null;
		}
		else 
		{
			$this.SecureScore = New-Object psobject -Property @{
				CurrentSecureScore = $result.currentSecureScore;
				MaxSecureScore = $result.maxSecureScore;
			}
		}
	}

 	[void] GetThreatDetectionSettings()
	{
		$uri = "https://s2.security.ext.azure.com/api/threatDetectionSettings/getThreatDetectionSettings?subscriptionId="+$this.SubscriptionId;

		$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()
		$AccessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
		$result = $null;

 		if($null -ne $AccessToken)
		{
			$header = "Bearer " + $AccessToken
			$headers = @{"Authorization"=$header;"Content-Type"="application/json";}

 			$result = [WebRequestHelper]::InvokeGetWebRequest($uri, $headers)
		}

 		if($null -eq $result)
		{
			$this.ThreatDetection = $null
		}
		else 
		{
			$TDEdetailsList = [System.Collections.ArrayList]::new();
			foreach($TDEdetails in $result)
			{
				if([Helpers]::CheckMember($TDEdetails,"name"))
				{
					if([Helpers]::CheckMember($TDEdetails,"properties.enabled"))
					{
						$TDEtype = New-Object psobject -Property @{
							Name = $TDEdetails.name;
							isEnabled = $TDEdetails.properties.enabled;
						}
						$TDEdetailsList.Add($TDEtype) | Out-Null
					}
				}
			}

 			$this.ThreatDetection = $TDEdetailsList;
		}
	}

 	[void] GetASCRecommendations()
	{
		$uri = "https://s2.security.ext.azure.com/api/Assessments/aggregated?`$pageSize=40&failedAssessmentsOnly=true";
		$body = '{"Subscriptions":["'+$this.SubscriptionId+'"],"resourceTypeFilter":[],"limitedSelectedSubscriptions":[],"shouldRetrieveDataForLimitedSubscriptions":false,"resourceGroupIdFilter":[],"resourceIdFilter":[],"categoryFilter":null}'

 		$result = $this.GetContentFromPostRequest($uri, $body);

 		if($null -eq $result)
		{
			$this.ASCRecommendations = $null
		}
		else 
		{
			$this.ASCRecommendations = $result.results
		}
	}

 	[void] GetSecurityEventsTier()
	{
		$uri = "https://s2.security.ext.azure.com/api/securityEventsTier/getSecurityEventsTier?subscriptionId="+$this.SubscriptionId;
		$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()
		$AccessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
		$result = $null;

 		if($null -ne $AccessToken)
		{
			$header = "Bearer " + $AccessToken
			$headers = @{"Authorization"=$header;"Content-Type"="application/json";}

 			$result = [WebRequestHelper]::InvokeGetWebRequest($uri, $headers)
		}

 		if($null -ne $result)
		{
			$this.SecurityEventsTier = $result.tier
		}
		else 
		{
			$this.SecurityEventsTier = $null	
		}
	}

 	[void] GetWorkspaceSettings()
	{
		$ResourceUrl= [WebRequestHelper]::GetResourceManagerUrl()
		$validatedUri = "$ResourceUrl/subscriptions/$($this.SubscriptionId)/providers/Microsoft.Security/workspaceSettings/default?api-version=2017-08-01-preview"
		$workspaceSettingsDetails = [WebRequestHelper]::InvokeGetWebRequest($validatedUri)

 		if([Helpers]::CheckMember($workspaceSettingsDetails,"properties.workspaceId"))
		{
			$this.WorkspaceSettings = New-Object psobject -Property @{
				WorkspaceId = $workspaceSettingsDetails.properties.workspaceId;
				Scope = $workspaceSettingsDetails.properties.scope;
			}
		}
		else 
		{
			$this.WorkspaceSettings = $null;
		}
	}

 	[PSObject] GetContentFromPostRequest($uri, $body)
	{
		$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()
		$AccessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
		if($null -ne $AccessToken)
		{
			$header = "Bearer " + $AccessToken
			$headers = @{"Authorization"=$header;"Content-Type"="application/json";}
			$result = ""
			$err = $null
			$output = $null
			try {
				$result = Invoke-WebRequest -Method Post -Uri $uri -Headers $headers -Body $body -ContentType "application/json" -UseBasicParsing
				if($result.StatusCode -ge 200 -and $result.StatusCode -le 399)
				{
					if($null -ne $result.Content){
						$json = (ConvertFrom-Json $result.Content)
						if($null -ne $json){
							if(($json | Get-Member -Name "value"))
							{
								$output += $json.value;
							}
							else
							{
								$output += $json;
							}
						}
					}
				}
				return $output
			}
			catch
			{
				$err = $_
				if($null -ne $err)
				{
					if($null -ne $err.ErrorDetails.Message){
						$json = (ConvertFrom-Json $err.ErrorDetails.Message)
						if($null -ne $json){
							if($json.'odata.error'.code -eq "Request_ResourceNotFound")
							{
								return $json.'odata.error'.message
							}
							return $json
						}
					}
				}
			}
		}
		return $null
	}
}
