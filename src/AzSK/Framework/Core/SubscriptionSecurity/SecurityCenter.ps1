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
	[string] $VMASCTier = "";
	[string] $SQLASCTier = "";
	[string] $AppSvcASCTier = "";
	[string] $StorageASCTier = "";

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

	hidden [void] LoadCurrentPolicy()
	{
		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.policySettings)
		{
			#Fetching all the ASC initiative assignments.
			$policyDefinitionId = $this.PolicyObject.policySettings.properties.policyDefinitionId;

			try {
				$this.CurrentPolicyObject = Get-AzPolicyAssignment -PolicyDefinitionId $policyDefinitionId
			}
			catch {
				$this.PolicyAPIFail = $true;
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
			[ResourceGroupHelper]::SetResourceGroupTags($azskRGName,@{[Constants]::SecurityCenterConfigVersionTagName=$this.PolicyObject.Version},$false)				
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

	[hashtable] CheckASCTierSettings()
	{
		[string[]] $ResourceASCTier = @();
		[string[]] $resourceName = @();
		[hashtable] $hashvalue = @{}
		$ResourceUrl= [WebRequestHelper]::GetResourceManagerUrl()
		$validatedUri ="$ResourceUrl/subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Security/pricings/default?api-version=2017-08-01-preview"
		$ascTierContentDetails = [WebRequestHelper]::InvokeGetWebRequest($validatedUri)

 		if([Helpers]::CheckMember($ascTierContentDetails,"properties.pricingTier"))
		{
			$this.ASCTier = $ascTierContentDetails.properties.pricingTier
		}

		$validatedUri = "$ResourceUrl/subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Security/pricings?api-version=2018-06-01"
		$ascTierResourceWiseDetails = [WebRequestHelper]::InvokeGetWebRequest($validatedUri)

        foreach($resourceDetails in $ascTierResourceWiseDetails)
        {
            if([Helpers]::CheckMember($resourceDetails,"properties.pricingTier"))
            {
				$resourceName = $resourceDetails.name
				$ResourceASCTier = $resourceDetails.properties.pricingTier
				$hashvalue.Add($resourceName,$ResourceASCTier)
            }
            
		}  
		return $hashvalue
	}
	
	[MessageData[]] SetSecurityPolicySettings()
	{
		[MessageData[]] $messages = @();

		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.policySettings)
		{	
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()		
			
			$defaultPoliciesNames = Get-Member -InputObject $this.PolicyObject.policySettings.properties.parameters -MemberType NoteProperty | Select-Object Name
			$configuredPolicyObject = $this.PolicyObject.policySettings.properties.parameters;	

			$this.UpdatePolicyObject();
			$policyLocation = $null

			#Get existing Policysetting to check if Location parameter is available (since policies set via Portal have an extra Location parameter)
            	try{
					$policySettingsUri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Authorization/policyAssignments$([SecurityCenterHelper]::ApiVersionLatest)";
					$existingsettings = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $policySettingsUri, $null )
					$scInitiative = [ConfigurationManager]::GetAzSKConfigData().AzSKSecurityCenterInitiativeName

					foreach ($setting in $existingsettings) {
						if($setting.properties.policyDefinitionId -match $scInitiative){
							if([Helpers]::CheckMember($setting,'Location')) {
								$policyLocation = $setting.Location
							}
						}
					}
				}
				catch{
					#eat exception, do not break existing flow
				}
			
			$policySettingsUri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Authorization/policyAssignments/SecurityCenterBuiltIn$([SecurityCenterHelper]::ApiVersionLatest)";
			$body = $this.PolicyObject.policySettings | ConvertTo-Json -Depth 10
			$body = $body.Replace("{0}",$this.SubscriptionContext.SubscriptionId) | ConvertFrom-Json;

			#If Location parameter is present in policy then append the property in the request body
            if ($null -ne $policyLocation) {
				$body | Add-Member -Name "Location" -value $policyLocation -MemberType NoteProperty
			}
			
		  	[WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $policySettingsUri, $body);

			if($null -ne $this.CurrentPolicyObject)
			{
			
				[PSObject] $defaultDisabledPoliciesNames = @(); # This will store the mandatory policies name that require 'Disabled' policy effect.
				$defaultPoliciesNames | ForEach-Object{
					$policyName = $_.Name;
					if($configuredPolicyObject.$policyName.value -eq "Disabled"){
						$defaultDisabledPoliciesNames += $policyName; 
					}
				}


				$this.CurrentPolicyObject | where{
					if($_.ResourceType -eq 'Microsoft.Authorization/policyAssignments' -and (-not [Helpers]::CheckMember($_,'ResourceGroupName'))) #Filtering out ASC policy assignments only at subscription scope. We are currently skipping MG & RG level scoped assignments.
					{
						$currentPolicyObj = $_.Properties.parameters #For each ASC policy assignment, we will set the policies in $defaultDisabledPoliciesNames to 'Disabled' effect so that overall effect across sub is 'Disabled'.
						$defaultDisabledPoliciesNames | where{
							$policyName = $_;
							if([Helpers]::CheckMember($currentPolicyObj,$policyName) -and ($currentPolicyObj.$policyName.value -ne $configuredPolicyObject.$policyName.value))
							{
								$currentPolicyObj.$policyName.value = $configuredPolicyObject.$policyName.value
							}
						}

						
						$_.Properties.parameters = $currentPolicyObj;
						$policySettingsUri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Authorization/policyAssignments/$($_.Name)$([SecurityCenterHelper]::ApiVersionLatest)";

						$body = New-Object PSObject
						$body | Add-Member -NotePropertyName sku -NotePropertyValue $_.sku
						$body | Add-Member -NotePropertyName id -NotePropertyValue $_.PolicyAssignmentId
						$body | Add-Member -NotePropertyName type -NotePropertyValue $_.ResourceType
						$body | Add-Member -NotePropertyName name -NotePropertyValue $_.Name
						$body | Add-Member -NotePropertyName properties -NotePropertyValue $_.properties

						#If Location parameter is present in policy then append the property in the request body
						if($body.properties.policyDefinitionId -match $scInitiative) {
							if ($null -ne $policyLocation) {
								$body | Add-Member -NotePropertyName Location -NotePropertyValue $policyLocation
							}
						}
						

						[WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $policySettingsUri, $body);
					}
					else
					{
						$this.PublishCustomMessage("Skipping policy validation & update for the assignment [$($_.ResourceId)]. This support will be added in an upcoming release." , [MessageType]::Warning);
					}
				}
			} 
		}

		return $messages;
	}

	[MessageData[]] SetSecurityOptionalPolicySettings()
	{
		[MessageData[]] $messages = @();

		if($null -ne $this.PolicyObject -and $null -ne $this.PolicyObject.optionalPolicySettings)
		{	
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()		

			$optionalPoliciesNames = Get-Member -InputObject $this.PolicyObject.optionalPolicySettings.properties.parameters -MemberType NoteProperty | Select-Object Name
			$configuredOptionalPolicyObject = $this.PolicyObject.optionalPolicySettings.properties.parameters;

			$this.UpdateOptionalPolicyObject();
			
			$policySettingsUri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Authorization/policyAssignments/SecurityCenterBuiltIn$([SecurityCenterHelper]::ApiVersionLatest)";
			$body = $this.PolicyObject.optionalPolicySettings | ConvertTo-Json -Depth 10
			$body = $body.Replace("{0}",$this.SubscriptionContext.SubscriptionId) | ConvertFrom-Json;
		  	[WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $policySettingsUri, $body);

			if($null -ne $this.CurrentPolicyObject)
			{

				[PSObject] $optionalDisabledPoliciesNames = @(); # This will store the optional policies name that require 'Disabled' policy effect.
				$optionalPoliciesNames | ForEach-Object{
					$policyName = $_.Name;
					if($configuredOptionalPolicyObject.$policyName.value -eq "Disabled"){
						$optionalDisabledPoliciesNames += $policyName; 
					}
				}

				$this.CurrentPolicyObject | where{
					if($_.ResourceType -eq 'Microsoft.Authorization/policyAssignments' -and (-not [Helpers]::CheckMember($_,'ResourceGroupName'))) #Filtering out ASC policy assignments only at subscription scope. We are currently skipping MG & RG level scoped assignments.
					{
						$currentPolicyObj = $_.Properties.parameters #For each ASC policy assignment, we will set the policies in $optionalDisabledPoliciesNames to 'Disabled' effect so that overall effect across sub is 'Disabled'.
						$optionalDisabledPoliciesNames | where{
							$policyName = $_;
							if([Helpers]::CheckMember($currentPolicyObj,$policyName) -and ($currentPolicyObj.$policyName.value -ne $configuredOptionalPolicyObject.$policyName.value))
							{
								$currentPolicyObj.$policyName.value = $configuredOptionalPolicyObject.$policyName.value
							}
						}

						$_.Properties.parameters = $currentPolicyObj;
						$policySettingsUri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Authorization/policyAssignments/$($_.Name)$([SecurityCenterHelper]::ApiVersionLatest)";

						$body = New-Object PSObject
						$body | Add-Member -NotePropertyName sku -NotePropertyValue $_.sku
						$body | Add-Member -NotePropertyName id -NotePropertyValue $_.PolicyAssignmentId
						$body | Add-Member -NotePropertyName type -NotePropertyValue $_.ResourceType
						$body | Add-Member -NotePropertyName name -NotePropertyValue $_.Name
						$body | Add-Member -NotePropertyName properties -NotePropertyValue $_.properties

						[WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $policySettingsUri, $body);
					}
					else
					{
						$this.PublishCustomMessage("Skipping policy validation & update for the assignment [$($_.ResourceId)]. This support will be added in an upcoming release." , [MessageType]::Warning);
					}
				}
			}   
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
			$ASCAssignment = $this.CurrentPolicyObject | where {$_.Name -eq $this.PolicyObject.policySettings.name}
			$ASCcount = ($ASCAssignment | Measure-Object).Count
			if($ASCcount -eq 1)
			{
				$currentPolicyObj = $ASCAssignment.Properties.parameters;
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
	}	

	[void] UpdateOptionalPolicyObject()
	{
		if($null -ne $this.CurrentPolicyObject -and $null -ne $this.PolicyObject.optionalPolicySettings)	
		{
			$ASCAssignment = $this.CurrentPolicyObject | where {$_.Name -eq $this.PolicyObject.policySettings.name}
			$ASCcount = ($ASCAssignment | Measure-Object).Count
			if($ASCcount -eq 1)
			{
				$currentPolicyObj = $ASCAssignment.Properties.parameters;
				$optionalPoliciesNames = Get-Member -InputObject $this.PolicyObject.optionalPolicySettings.properties.parameters -MemberType NoteProperty | Select-Object Name
				$configuredOptionalPolicyObject = $this.PolicyObject.optionalPolicySettings.properties.parameters;
				$optionalPoliciesNames | ForEach-Object {
					$policyName = $_.Name;
					if([Helpers]::CheckMember($currentPolicyObj,$policyName))
					{
						$currentPolicyObj.$policyName.value = $configuredOptionalPolicyObject.$policyName.value
					}else
					{
						$currentPolicyObj | Add-Member -NotePropertyName $policyName -NotePropertyValue $configuredOptionalPolicyObject.$policyName
					}				
					
				}
				$this.PolicyObject.optionalPolicySettings.properties.parameters = $currentPolicyObj;
			}
		}		
	}	

	[string[]] ValidatePolicyObject()
	{
		[string[]] $MisConfiguredPolicies = @();

		if($null -ne $this.CurrentPolicyObject -and $null -ne $this.PolicyObject.policySettings)
		{
			$subPolicy = $this.CurrentPolicyObject | where {$_.ResourceType -eq 'Microsoft.Authorization/policyAssignments' -and (-not [Helpers]::CheckMember($_,'ResourceGroupName'))} #Filtering out ASC policy assignments only at subscription scope. We are currently skipping MG & RG level scoped assignments.
			$assignCount = ($subPolicy | Measure-Object).Count # Total no. of ASC initiative assignments (duplicates).
			$defaultPoliciesNames = Get-Member -InputObject $this.PolicyObject.policySettings.properties.parameters -MemberType NoteProperty | Select-Object Name
			$configuredPolicyObject = $this.PolicyObject.policySettings.properties.parameters;

			$defaultPoliciesNames | ForEach-Object {
				$policyName = $_.Name;		
                $counter = 0; 					# count of misconfigured instances of the policy under iteration.
				$polNotFoundCounter = 0;		# count of assignments in which the policy under iteration is absent.

				if($configuredPolicyObject.$policyName.value -ne "Disabled")				# If the desired effect of a policy is not "Disabled" i.e. "Audit/AuditIfNotExists", then atleast one initiative assignment should have the correct effect so that the policy is correctly configured on the sub.
				{
					$enabledAssignments = $subPolicy | where{[Helpers]::CheckMember($_.Properties.parameters,$policyName) -and $_.Properties.parameters.$policyName.value -eq $configuredPolicyObject.$policyName.value}	
					$counter = ($enabledAssignments | Measure-Object).Count

					if($counter -eq 0) # If policy is absent/misconfigured in all the assignments, then the overall effect of the policy is opposite of what is required (Here "Audit/AuditIfNotExists").
					{
						$MisConfiguredPolicies += ("Misconfigured Mandatory Policy: [" + $policyName + "]");
					}

				}
				elseif($configuredPolicyObject.$policyName.value -eq "Disabled")           # If the desired effect of a policy is "Disabled", then no initiative assignments should have a stronger effect (Audit / AuditIfNotExists) for the policy under consideration.
				{
		
					$enabledAssignments = $subPolicy | where{[Helpers]::CheckMember($_.Properties.parameters,$policyName) -and $_.Properties.parameters.$policyName.value -ne $configuredPolicyObject.$policyName.value}	
					$counter = ($enabledAssignments | Measure-Object).Count

					if($counter -gt 0)		# This means in atleast one assignment, the effect is not 'Disabled', i.e it is "Audit/AuditIfNotExists" making the stronger effect win.
					{
						$MisConfiguredPolicies += ("Misconfigured Mandatory Policy: [" + $policyName + "]");
					}
					else					# This means either the policy is absent in all the assignments or it is configured correctly wherever present.
					{
						$absentAssignments = $subPolicy | where{-not [Helpers]::CheckMember($_.Properties.parameters,$policyName)}
						$polNotFoundCounter = ($absentAssignments | Measure-Object).Count
						if($polNotFoundCounter -eq $assignCount)		# This means policy is absent across all assignments meaning it is not in effect on the sub.
						{
							$MisConfiguredPolicies += ("Misconfigured Mandatory Policy: [" + $policyName + "]");
						}
					}
				}
			}

		}
		elseif($null -eq $this.CurrentPolicyObject -and  $null -ne $this.PolicyObject.policySettings)
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
			$subPolicy = $this.CurrentPolicyObject | where {$_.ResourceType -eq 'Microsoft.Authorization/policyAssignments' -and (-not [Helpers]::CheckMember($_,'ResourceGroupName'))} #Filtering out ASC policy assignments only at subscription scope. We are currently skipping MG & RG level scoped assignments.
			$assignCount = ($subPolicy | Measure-Object).Count 				# Total no. of ASC initiative assignments (duplicates).
			$optionalPoliciesNames = Get-Member -InputObject $this.PolicyObject.optionalPolicySettings.properties.parameters -MemberType NoteProperty | Select-Object Name
			$configuredOptionalPolicyObject = $this.PolicyObject.optionalPolicySettings.properties.parameters;

			$optionalPoliciesNames | ForEach-Object {
				$policyName = $_.Name;		
                $counter = 0;							# count of misconfigured instances of the policy under iteration.
				$polNotFoundCounter = 0;				# count of assignments in which the policy under iteration is absent.


				if($configuredOptionalPolicyObject.$policyName.value -ne "Disabled")		# If the desired effect of a policy is not "Disabled" i.e. "Audit/AuditIfNotExists", then atleast one initiative assignment should have the correct effect so that the policy is correctly configured on the sub.
				{

					$enabledAssignments = $subPolicy | where{[Helpers]::CheckMember($_.Properties.parameters,$policyName) -and $_.Properties.parameters.$policyName.value -eq $configuredOptionalPolicyObject.$policyName.value}	
					$counter = ($enabledAssignments | Measure-Object).Count

					if($counter -eq 0)			# If policy is absent/misconfigured in all the assignments, then the overall effect of the policy is opposite of what is required (Here "Audit/AuditIfNotExists").
					{
						$MisConfiguredOptionalPolicies += ("Misconfigured Optional Policy: [" + $policyName + "]");
					}

				}
				elseif($configuredOptionalPolicyObject.$policyName.value -eq "Disabled")    # If the desired effect of a policy is "Disabled", then no initiative assignments should have a stronger effect (Audit / AuditIfNotExists) for the policy under consideration.
				{
	
					$enabledAssignments = $subPolicy | where{[Helpers]::CheckMember($_.Properties.parameters,$policyName) -and $_.Properties.parameters.$policyName.value -ne $configuredOptionalPolicyObject.$policyName.value}	
					$counter = ($enabledAssignments | Measure-Object).Count

					if($counter -gt 0)				# This means in atleast one assignment, the effect is not 'Disabled', i.e it is "Audit/AuditIfNotExists" making the stronger effect win.
					{
						$MisConfiguredOptionalPolicies += ("Misconfigured Optional Policy: [" + $policyName + "]");
					}
					else							# This means either the policy is absent in all the assignments or it is configured correctly wherever present.
					{
						$absentAssignments = $subPolicy | where{-not [Helpers]::CheckMember($_.Properties.parameters,$policyName)}
						$polNotFoundCounter = ($absentAssignments | Measure-Object).Count

						if($polNotFoundCounter -eq $assignCount)		# This means policy is absent across all assignments meaning it is not in effect on the sub.
						{
							$MisConfiguredOptionalPolicies += ("Misconfigured Optional Policy: [" + $policyName + "]");
						}
					}
				}
			}

		}
		elseif($null -eq $this.CurrentPolicyObject -and  $null -ne $this.PolicyObject.optionalPolicySettings)
        {
			if($this.PolicyAPIFail)
			{
				$MisConfiguredOptionalPolicies += ("Optional ASC Policies information can't be fetched beacuse either mandatory ASC policies are not configured or due to API access failure.");
			}
			else
			{
				$MisConfiguredOptionalPolicies += ("Optional ASC Policies are not configured");	
			}
               
        }
	
	 	return $MisConfiguredOptionalPolicies;		
	}	

	# Get SecurtiySolution details for the subscription
	[PSObject[]] GetASCSecuritySolutionsDetails()
	{
		$SecuritySolutionsDetails = @();
		$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()		
		$securitySolutionsUri = $ResourceAppIdURI + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/$([SecurityCenterHelper]::ProviderNamespace)/securitySolutions?api-version=2015-06-01-preview";
		try
		{
			$SecuritySolutionsDetails += [WebRequestHelper]::InvokeWebRequest("Get", $securitySolutionsUri, $null);
		}
		catch
		{
			#eat exception, do not break existing flow
		}
		return $SecuritySolutionsDetails;
	}
}