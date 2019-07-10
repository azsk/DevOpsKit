using namespace System.Management.Automation
Set-StrictMode -Version Latest 
class SecurityCenter: AzSKRoot
{    	
	[PSObject] $PolicyObject = $null;
	[PSObject] $CurrentPolicyObject = $null;
	[bool] $PolicyAPIFail = $false;
	[string] $Off = "Off";
	[string] $On = "On";
	[string] $ContactPhoneNumber;
	[string] $ContactEmail;
	[string] $AlertNotifStatus;
	[string] $AlertAdminStatus;
	[string] $AutoProvisioningSettings = "";
	[string] $ASCTier = "";
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
		#this function would fetch auto provisioning settings
		$this.CheckAutoProvisioningSettings();
		#this function would fetch ASC Tier details
		$this.CheckASCTierSettings();
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
		#this function would fetch auto provisioning settings
		$this.CheckAutoProvisioningSettings();
		#this function would fetch ASC Tier details
		$this.CheckASCTierSettings();
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

		$this.CheckASCTierSettings();

		return $statuses;
	}

	hidden [void] LoadCurrentPolicy()
	{
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.policySettings)
		{
			$policyName = $this.PolicyObject.policySettings.name;

			try {
				$this.CurrentPolicyObject = Get-AzPolicyAssignment -Name $policyName
			}
			catch {
				$this.PolicyAPIFail = $true;
				#eat the exception as it would throw in non availability of policy
			}			
		}
	}
	
	hidden [void] LoadPolicies()
	{
		$this.PolicyObject = [ConfigurationManager]::LoadServerConfigFile("SecurityCenter.json");
	}

	[MessageData[]] SetPolicies([bool] $updateProvisioningSettings, [bool] $updatePolicies, [bool] $updateSecurityContacts, [bool] $setOptionalPolicy)
    {				
		[MessageData[]] $messages = @();
		$this.PublishCustomMessage("Updating SecurityCenter policies...`n" + [Constants]::SingleDashLine, [MessageType]::Warning);

		$this.PublishCustomMessage("Updating Security Center version...", [MessageType]::Warning);
		$this.SetSecurityCenterVersion();		
		$this.PublishCustomMessage("Completed updating Security Center version.", [MessageType]::Update);

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
		if($setOptionalPolicy)
		{
			$this.PublishCustomMessage("Updating optional SecurityPolicy settings...", [MessageType]::Warning);
			$this.SetSecurityOptionalPolicySettings();						
			$this.PublishCustomMessage("Completed optional SecurityPolicy settings.", [MessageType]::Update);
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

	[MessageData[]] SetSecurityCenterVersion()
	{
		[MessageData[]] $messages = @();
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.autoProvisioning)
		{			
			$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
			[Helpers]::SetResourceGroupTags($azskRGName,@{[Constants]::SecurityCenterConfigVersionTagName=$this.PolicyObject.Version},$false)				
		}
		return $messages;
	}

	[MessageData[]] SetAutoProvisioningSettings()
	{
		[MessageData[]] $messages = @();
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.autoProvisioning)
		{			
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()
			$autoProvisioningUri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/$([SecurityCenterHelper]::ProviderNamespace)/$([SecurityCenterHelper]::AutoProvisioningSettingsApi)/default$([SecurityCenterHelper]::ApiVersionNew)";
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
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()		
			$autoProvisioningUri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/$([SecurityCenterHelper]::ProviderNamespace)/$([SecurityCenterHelper]::AutoProvisioningSettingsApi)/default$([SecurityCenterHelper]::ApiVersionNew)";
			try
            {
				$response = [WebRequestHelper]::InvokeGetWebRequest($autoProvisioningUri);
				if([Helpers]::CheckMember($response, "properties.autoProvision"))
				{
					$this.AutoProvisioningSettings = $response.properties.autoProvision;
				}			
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
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()		
			$securityContactsUri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/$([SecurityCenterHelper]::ProviderNamespace)/$([SecurityCenterHelper]::SecurityContactsApi)/default1$([SecurityCenterHelper]::ApiVersionNew)";
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
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()
			$securityContactsUri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/$([SecurityCenterHelper]::ProviderNamespace)/$([SecurityCenterHelper]::SecurityContactsApi)/default1$([SecurityCenterHelper]::ApiVersionNew)";
			
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
				if([Helpers]::CheckMember($response, "properties.alertNotifications"))
				{
					$this.AlertNotifStatus = $response.properties.alertNotifications;
				}
				if([Helpers]::CheckMember($response, "properties.alertsToAdmins"))
				{
					$this.AlertAdminStatus = $response.properties.alertsToAdmins;
				}
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

	[void] CheckASCTierSettings()
	{
		$ResourceUrl= [WebRequestHelper]::GetResourceManagerUrl()
		$validatedUri ="$ResourceUrl/subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Security/pricings/default?api-version=2017-08-01-preview"
		$ascTierContentDetails = [WebRequestHelper]::InvokeGetWebRequest($validatedUri)

 		if([Helpers]::CheckMember($ascTierContentDetails,"properties.pricingTier"))
		{
			$this.ASCTier = $ascTierContentDetails.properties.pricingTier
		}
	}
	
	[MessageData[]] SetSecurityPolicySettings()
	{
		[MessageData[]] $messages = @();
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.policySettings)
		{	
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()				
			$this.UpdatePolicyObject();
			$policySettingsUri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Authorization/policyAssignments/SecurityCenterBuiltIn$([SecurityCenterHelper]::ApiVersionLatest)";
			$body = $this.PolicyObject.policySettings | ConvertTo-Json -Depth 10
			$body = $body.Replace("{0}",$this.SubscriptionContext.SubscriptionId) | ConvertFrom-Json;
		  	[WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $policySettingsUri, $body);
		}
		return $messages;
	}

	[MessageData[]] SetSecurityOptionalPolicySettings()
	{
		[MessageData[]] $messages = @();
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.optionalPolicySettings)
		{	
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()				
			$this.UpdateOptionalPolicyObject();
			$policySettingsUri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Authorization/policyAssignments/SecurityCenterBuiltIn$([SecurityCenterHelper]::ApiVersionLatest)";
			$body = $this.PolicyObject.optionalPolicySettings | ConvertTo-Json -Depth 10
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

	[string[]] CheckOptionalSecurityPolicySettings()
	{
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.optionalPolicySettings)
		{	
			return $this.ValidateOptionalPolicyObject();											
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
                if([Helpers]::CheckMember($currentPolicyObj,$policyName))
                {
                    $currentPolicyObj.$policyName.value = $configuredPolicyObject.$policyName.value
                }else
                {
                    $currentPolicyObj | Add-Member -NotePropertyName $policyName -NotePropertyValue $configuredPolicyObject.$policyName
                }				
				
			}
			$this.PolicyObject.policySettings.properties.parameters = $currentPolicyObj;
		}		
	}	

	[void] UpdateOptionalPolicyObject()
	{
		if($null -ne $this.CurrentPolicyObject -and $null -ne $this.PolicyObject.optionalPolicySettings)	
		{
			$currentPolicyObj = $this.CurrentPolicyObject.Properties.parameters;
			$defaultPoliciesNames = Get-Member -InputObject $this.PolicyObject.optionalPolicySettings.properties.parameters -MemberType NoteProperty | Select-Object Name
			$configuredPolicyObject = $this.PolicyObject.optionalPolicySettings.properties.parameters;
			$defaultPoliciesNames | ForEach-Object {
				$policyName = $_.Name;
                if([Helpers]::CheckMember($currentPolicyObj,$policyName))
                {
                    $currentPolicyObj.$policyName.value = $configuredPolicyObject.$policyName.value
                }else
                {
                    $currentPolicyObj | Add-Member -NotePropertyName $policyName -NotePropertyValue $configuredPolicyObject.$policyName
                }				
				
			}
			$this.PolicyObject.optionalPolicySettings.properties.parameters = $currentPolicyObj;
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
             		
				if((-not [Helpers]::CheckMember($currentPolicyObj,$policyName)) -or ($currentPolicyObj.$policyName.value -ne $configuredPolicyObject.$policyName.value))
				{
					$MisConfiguredPolicies += ("Misconfigured Mandatory Policy: [" + $policyName + "]");
				}
                
			}
		}elseif($null -eq $this.CurrentPolicyObject -and  $null -ne $this.PolicyObject.policySettings)
        {
			if($this.PolicyAPIFail)
			{
				$MisConfiguredPolicies += ("Mandatory ASC Policies information can't be fetched beacuse either mandatory ASC policies are not configured or due to API access failure.");
			}
			else
			{
				$MisConfiguredPolicies += ("Mandatory ASC Policies are not configured");	
			}
               
        }
		
		return $MisConfiguredPolicies;		
	}	
	[string[]] ValidateOptionalPolicyObject()
	{
	 	[string[]] $MisConfiguredOptionalPolicies = @();
		if($null -ne $this.CurrentPolicyObject -and $null -ne $this.PolicyObject.optionalPolicySettings)	
		{
			$currentPolicyObj = $this.CurrentPolicyObject.Properties.parameters;
			$optionalPoliciesNames = Get-Member -InputObject $this.PolicyObject.optionalPolicySettings.properties.parameters -MemberType NoteProperty | Select-Object Name
			$configuredOptionalPolicyObject = $this.PolicyObject.optionalPolicySettings.properties.parameters;
			$optionalPoliciesNames | ForEach-Object {
				$policyName = $_.Name;		
						
				if((-not [Helpers]::CheckMember($currentPolicyObj,$policyName)) -or ($currentPolicyObj.$policyName.value -ne $configuredOptionalPolicyObject.$policyName.value))
				{
					$MisConfiguredOptionalPolicies += ("Misconfigured Optional Policy: [" + $policyName + "]");
				}
				
		}
	 	}elseif($null -eq $this.CurrentPolicyObject -and  $null -ne $this.PolicyObject.optionalPolicySettings)
         {
            if($this.PolicyAPIFail)
			{
				$MisConfiguredOptionalPolicies += ("Optional ASC Policies information can't be fetched due to API access failure.");
			}
			else
			{
				$MisConfiguredOptionalPolicies += ("Optional ASC Policies are not configured");	
			}
         }
	
	 	return $MisConfiguredOptionalPolicies;		
	}	
}