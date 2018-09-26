using namespace System.Management.Automation
Set-StrictMode -Version Latest 
class SecurityCenter: AzSKRoot
{    	
	[PSObject] $PolicyObject = $null;
	[PSObject] $CurrentPolicyObject = $null;
	[string] $Off = "Off";
	[string] $On = "On";
	[string] $ContactPhoneNumber;
	[string] $ContactEmail;
	SecurityCenter([string] $subscriptionId,[bool]$registerASCProvider): 
        Base($subscriptionId)
    { 		
		if($registerASCProvider)
		{
			[SecurityCenterHelper]::RegisterResourceProvider();
		}
		$this.LoadPolicies(); 
		$this.LoadCurrentPolicy();
	}
	SecurityCenter([string] $subscriptionId): 
        Base($subscriptionId)
    { 
		[SecurityCenterHelper]::RegisterResourceProvider();
		$this.LoadPolicies(); 
		$this.LoadCurrentPolicy();
		#calling this function as it would fetch the current contact phone number settings 
		$this.CheckSecurityContactSettings();
	}

	SecurityCenter([string] $subscriptionId, [string] $securityContactEmail, [string] $securityContactPhoneNumber): 
        Base($subscriptionId)
    { 
		[SecurityCenterHelper]::RegisterResourceProvider();
		$this.LoadPolicies();
		$this.LoadCurrentPolicy();
		#calling this function as it would fetch the current contact phone number settings 
		$this.CheckSecurityContactSettings();
		if(-not [string]::IsNullOrWhiteSpace($securityContactPhoneNumber))
		{
			$this.ContactPhoneNumber = $securityContactPhoneNumber;
		}
		if(-not [string]::IsNullOrWhiteSpace($securityContactEmail))
		{
			$this.ContactEmail = $securityContactEmail;
		}		
	}


	hidden [string[]] CheckASCCompliance()
	{
		$statuses = @();
		$response = $this.CheckAutoProvisioningSettings();
		if(-not [string]::IsNullOrWhiteSpace($response))
		{
			$statuses += $response;
		}
		$response = $this.CheckSecurityContactSettings();
		if(-not [string]::IsNullOrWhiteSpace($response))
		{
			$statuses += $response;
		}

		$response = $this.CheckSecurityPolicySettings();
		if(($response | Measure-Object).Count -gt 0)
		{
			$statuses += $response;
		}
		return $statuses;
	}

	hidden [void] LoadCurrentPolicy()
	{
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.policySettings)
		{
			$policyName = $this.PolicyObject.policySettings.name;

			try {
				$this.CurrentPolicyObject = Get-AzureRmPolicyAssignment -Name $policyName
			}
			catch {
				#eat the exception as it would throw in non availability of policy
			}			
		}
	}
	
	hidden [void] LoadPolicies()
	{
		$this.PolicyObject = [ConfigurationManager]::LoadServerConfigFile("SecurityCenter.json");
	}

	[MessageData[]] SetPolicies([bool] $updateProvisioningSettings, [bool] $updatePolicies, [bool] $updateSecurityContacts)
    {				
		[MessageData[]] $messages = @();
		$this.PublishCustomMessage("Updating SecurityCenter policies...`n" + [Constants]::SingleDashLine, [MessageType]::Warning);
		if($updateProvisioningSettings)
		{
			$this.PublishCustomMessage("Updating AutoProvision settings...", [MessageType]::Warning);
			$this.SetAutoProvisioningSettings();						
			$this.PublishCustomMessage("Completed updating AutoProvision settings.", [MessageType]::Update);
		}
		if($updatePolicies)
		{
			$this.PublishCustomMessage("Updating SecurityPolicy settings...", [MessageType]::Warning);
			$this.SetSecurityPolicySettings();						
			$this.PublishCustomMessage("Completed updating SecurityPolicy settings.", [MessageType]::Update);
		}
		if($updateSecurityContacts)
		{
			$this.PublishCustomMessage("Updating SecurityContact settings...", [MessageType]::Warning);
			$this.SetSecurityContactSettings();	
			$this.PublishCustomMessage("Completed updating SecurityContact settings.", [MessageType]::Update);					
		}
		$this.PublishCustomMessage([Constants]::SingleDashLine + "`nCompleted configuring SecurityCenter.", [MessageType]::Update);
		return $messages;
    }

	[MessageData[]] SetAutoProvisioningSettings()
	{
		[MessageData[]] $messages = @();
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.autoProvisioning)
		{			
			$autoProvisioningUri = [WebRequestHelper]::AzureManagementUri + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/$([SecurityCenterHelper]::ProviderNamespace)/$([SecurityCenterHelper]::AutoProvisioningSettingsApi)/default$([SecurityCenterHelper]::ApiVersionNew)";
			$body = $this.PolicyObject.autoProvisioning | ConvertTo-Json -Depth 10
			$body = $body.Replace("{0}",$this.SubscriptionContext.SubscriptionId) | ConvertFrom-Json;
		  	[WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $autoProvisioningUri, $body);
		}
		return $messages;
	}

	[string] CheckAutoProvisioningSettings()
	{		
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.autoProvisioning)
		{			
			$autoProvisioningUri = [WebRequestHelper]::AzureManagementUri + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/$([SecurityCenterHelper]::ProviderNamespace)/$([SecurityCenterHelper]::AutoProvisioningSettingsApi)/default$([SecurityCenterHelper]::ApiVersionNew)";
			try
            {
                $response = [WebRequestHelper]::InvokeGetWebRequest($autoProvisioningUri);
			}
            catch
            {
				#return failure status if api throws exception.
				return "AutoProvisioning: [ASC is either not configured or not able to fetch ASC provisioning status due to access issue]"
			}
			$autoProvisionObject = $this.PolicyObject.autoProvisioning
			if(-not (-not ([Helpers]::CheckMember($autoProvisionObject,"properties.autoProvision",$false)) -or ([Helpers]::CheckMember($response,"properties.autoProvision") -and ($response.properties.autoProvision -eq $autoProvisionObject.properties.autoProvision))))
			{
				return "AutoProvisioning: [Failed]"
			}
		}
		return $null;
	}

	[MessageData[]] SetSecurityContactSettings()
	{
		[MessageData[]] $messages = @();
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.securityContacts)
		{		
			$securityContactsUri = [WebRequestHelper]::AzureManagementUri + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/$([SecurityCenterHelper]::ProviderNamespace)/$([SecurityCenterHelper]::SecurityContactsApi)/default1$([SecurityCenterHelper]::ApiVersionNew)";
			$body = $this.PolicyObject.securityContacts | ConvertTo-Json -Depth 10
			$body = $body.Replace("{0}",$this.SubscriptionContext.SubscriptionId).Replace("{1}",$this.ContactEmail).Replace("{2}",$this.ContactPhoneNumber) | ConvertFrom-Json;
		  	[WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $securityContactsUri, $body);
		}
		return $messages;
	}

	[string] CheckSecurityContactSettings()
	{
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.securityContacts)
		{
			$securityContactsUri = [WebRequestHelper]::AzureManagementUri + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/$([SecurityCenterHelper]::ProviderNamespace)/$([SecurityCenterHelper]::SecurityContactsApi)/default1$([SecurityCenterHelper]::ApiVersionNew)";
			
			try
            {
                $response = [WebRequestHelper]::InvokeGetWebRequest($securityContactsUri);
            }
            catch
            {
				#return failure status if api throws exception.
                return "SecurityContactsConfig: [Security contact details is either not configured or not able to fetch configuration due to access issue]"
			}
			$secContactObject = $this.PolicyObject.securityContacts
			if([Helpers]::CheckMember($response,"properties.email") -and -not [string]::IsNullOrWhiteSpace($response.properties.email) `
				-and [Helpers]::CheckMember($response,"properties.phone") -and -not [string]::IsNullOrWhiteSpace($response.properties.phone))				
			{
				$this.ContactEmail = $response.properties.email;
				$this.ContactPhoneNumber = $response.properties.phone;
				if(-not ((-not ([Helpers]::CheckMember($secContactObject,"properties.email",$false)) -or ([Helpers]::CheckMember($response,"properties.email") -and -not [string]::IsNullOrWhiteSpace($response.properties.email)))`
					 -and (-not ([Helpers]::CheckMember($secContactObject,"properties.phone",$false)) -or ([Helpers]::CheckMember($response,"properties.phone") -and -not [string]::IsNullOrWhiteSpace($response.properties.phone)))`
					 -and (-not ([Helpers]::CheckMember($secContactObject,"properties.alertNotifications",$false)) -or ([Helpers]::CheckMember($response,"properties.alertNotifications") -and ($response.properties.alertNotifications -eq $secContactObject.properties.alertNotifications)))`
					 -and (-not ([Helpers]::CheckMember($secContactObject,"properties.alertsToAdmins",$false)) -or ([Helpers]::CheckMember($response,"properties.alertsToAdmins") -and ($response.properties.alertsToAdmins -eq $secContactObject.properties.alertsToAdmins)))))
				{                   
					return "SecurityContactsConfig: [Failed. One of the configuration(Email,Phone,SendEmailAlertNotification,SendEmailAlertsToAdmin) is missing]"
				}				
			}
            else
            {
                return "SecurityContactsConfig: [Not able to find either email or phone number contact details]"
            }
		}
		return $null;
	}

	[MessageData[]] SetSecurityPolicySettings()
	{
		[MessageData[]] $messages = @();
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.policySettings)
		{						
			$this.UpdatePolicyObject();
			$policySettingsUri = [WebRequestHelper]::AzureManagementUri + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Authorization/policyAssignments/SecurityCenterBuiltIn$([SecurityCenterHelper]::ApiVersionLatest)";
			$body = $this.PolicyObject.policySettings | ConvertTo-Json -Depth 10
			$body = $body.Replace("{0}",$this.SubscriptionContext.SubscriptionId) | ConvertFrom-Json;
		  	[WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $policySettingsUri, $body);
		}
		return $messages;
	}

	[string[]] CheckSecurityPolicySettings()
	{
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.policySettings)
		{	
			return $this.ValidatePolicyObject();											
		}
		return $null;
	}

	[void] UpdatePolicyObject()
	{
		if($null -ne $this.CurrentPolicyObject -and $null -ne $this.PolicyObject.policySettings)	
		{
			$currentPolicyObj = $this.CurrentPolicyObject.Properties.parameters;
			$defaultPoliciesNames = Get-Member -InputObject $this.PolicyObject.policySettings.properties.parameters -MemberType NoteProperty | Select-Object Name
			$configuredPolicyObject = $this.PolicyObject.policySettings.properties.parameters;
			$defaultPoliciesNames | ForEach-Object {
				$policyName = $_.Name;				
				$currentPolicyObj.$policyName.value = $configuredPolicyObject.$policyName.value
			}
			$this.PolicyObject.policySettings.properties.parameters = $currentPolicyObj;
		}		
	}	

	[string[]] ValidatePolicyObject()
	{
		[string[]] $MisConfiguredPolicies = @();
		if($null -ne $this.CurrentPolicyObject -and $null -ne $this.PolicyObject.policySettings)	
		{
			$currentPolicyObj = $this.CurrentPolicyObject.Properties.parameters;
			$defaultPoliciesNames = Get-Member -InputObject $this.PolicyObject.policySettings.properties.parameters -MemberType NoteProperty | Select-Object Name
			$configuredPolicyObject = $this.PolicyObject.policySettings.properties.parameters;
			$defaultPoliciesNames | ForEach-Object {
				$policyName = $_.Name;				
				if($currentPolicyObj.$policyName.value -ne $configuredPolicyObject.$policyName.value)
				{
					$MisConfiguredPolicies += ("Misconfigured Policy: [" + $policyName + "]");
				}
			}
		}
		return $MisConfiguredPolicies;		
	}	
}
