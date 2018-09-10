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
	}

	SecurityCenter([string] $subscriptionId, [string] $securityContactEmail, [string] $securityContactPhoneNumber): 
        Base($subscriptionId)
    { 
		[SecurityCenterHelper]::RegisterResourceProvider();
		$this.ContactPhoneNumber = $securityContactPhoneNumber;
		$this.ContactEmail = $securityContactEmail;
		$this.LoadPolicies(); 
		$this.LoadCurrentPolicy();
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
		if($updateProvisioningSettings)
		{
			$this.SetAutoProvisioningSettings();						
		}
		if($updatePolicies)
		{
			$this.SetSecurityPolicySettings();						
		}
		if($updateSecurityContacts)
		{
			$this.SetSecurityContactSettings();						
		}
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
}
