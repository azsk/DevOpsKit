using namespace System.Management.Automation
Set-StrictMode -Version Latest 
class SecurityCenter: AzSKRoot
{    
	[PSObject] $Policy = $null;
	[PSObject[]] $UniquePolicies = $null;
	[string] $Off = "Off";
	[string] $On = "On";
	[string] $ContactPhoneNumber;
	[string] $ContactEmail;
	[bool] $IsValidVersion;
	[bool] $IsLatestVersion;
	[string] $CurrentVersion;
	[string] $LatestVersion;
	SecurityCenter([string] $subscriptionId,[bool]$registerASCProvider): 
        Base($subscriptionId)
    { 
		$this.LoadPolicies(); 
		if($registerASCProvider)
		{
			[SecurityCenterHelper]::RegisterResourceProvider();
		}

	}
	SecurityCenter([string] $subscriptionId): 
        Base($subscriptionId)
    { 
		$this.LoadPolicies(); 
		[SecurityCenterHelper]::RegisterResourceProvider();
	}
	
	hidden [void] LoadPolicies()
	{
		$this.Policy = $this.LoadServerConfigFile("SecurityCenter.json");
		$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		$this.CurrentVersion = [Helpers]::GetResourceGroupTag($azskRGName, [Constants]::SecurityCenterConfigVersionTagName)
		if([string]::IsNullOrWhiteSpace($this.CurrentVersion))
		{
			$this.CurrentVersion = "0.0.0"
		}
		$minSupportedVersion = [ConfigurationManager]::GetAzSKConfigData().AzSKASCMinReqdVersion 
		$this.IsLatestVersion = $this.IsLatestVersionConfiguredOnSub($this.Policy.Version, [Constants]::SecurityCenterConfigVersionTagName);
		$this.IsValidVersion = $this.IsLatestVersionConfiguredOnSub($this.Policy.Version, [Constants]::SecurityCenterConfigVersionTagName) -or [System.Version]$minSupportedVersion -le [System.Version]$this.CurrentVersion ;
		$this.LatestVersion = $this.Policy.Version;
	}

	hidden [PSObject[]] GetUniquePolicies()
	{
		if(-not $this.UniquePolicies)
		{
			$this.UniquePolicies = @();
			
			$allPolicies = @();
			
			$allPolicies += [SecurityCenterHelper]::InvokeGetSecurityCenterRequest($this.SubscriptionContext.SubscriptionId, [SecurityCenterHelper]::PoliciesApi, [SecurityCenterHelper]::ApiVersion)
			#$allPolicies += [SecurityCenterHelper]::InvokeGetSecurityCenterRequest($this.SubscriptionContext.SubscriptionId, [SecurityCenterHelper]::AutoProvisioningSettingsApi, [SecurityCenterHelper]::ApiVersionNew)
			if($allPolicies.Count -ne 0)
			{
				#Query to select only subscription level polices and other polices which are modified explicitly 
				$this.UniquePolicies += $allPolicies | Where-Object { 
											[Helpers]::CheckMember($_, "properties.policyLevel") -and
											($_.properties.policyLevel -eq "Subscription" -or 
											$_.properties.unique -eq $this.On )
										};
				if($this.UniquePolicies.Count -eq 0)
				{
					#no relevant policies found message here
					$this.PublishCustomMessage("No Subscription level or uniquely configured policies found in the Security Center", [MessageType]::Warning);
				}
			}
			else
			{
				#Error message here
				$this.PublishCustomMessage("Not able to get the Security Center policies", [MessageType]::Error);
			}
		}
		

		return $this.UniquePolicies;
	}

	[PSObject[]] GetMisconfiguredPolicies()
    {	
		$policies = @();
		$misConfiguredPolicies = @();
		$policies += $this.GetUniquePolicies();
		if($policies.Count -ne 0)
		{
			#If recommendations object is kept blank in Policy json, consider to check all properties to be 'On'
			#Check with get-member here
			#if(($this.Policy.properties.recommendations | Get-Member -MemberType Properties | Measure-Object).Count -eq 0)
			#{
				#Pick first object and add all recommendation property to policy json object
				$samplePolicy = $policies | Select-Object -First 1
				if([Helpers]::CheckMember($samplePolicy, "properties.recommendations"))
				{
					$samplePolicy.properties.recommendations | Get-Member -MemberType Properties | 
						ForEach-Object {
							$property = $_.Name;
							$value = $this.On;
							#retain the value from the configured policy on subscription
							if([Helpers]::CheckMember($samplePolicy, "properties.recommendations.$property"))
							{
								$value = $($samplePolicy.properties.recommendations.$property);
							}
							#override the value as per the expected policy from server
							if([Helpers]::CheckMember($this.Policy, "properties.recommendations.$property"))
							{
								$value = $($this.Policy.properties.recommendations.$property);
							}							
							Add-Member -InputObject $this.Policy.properties.recommendations -MemberType NoteProperty -Name $_.Name -Value $value -Force
						}
				}
			#}

			$policies | ForEach-Object {
				$isMisconfigured = $true;
				if([Helpers]::CompareObject($this.Policy.properties, $_.properties))
				{
					# Check for email address and phone number props
					if([Helpers]::CheckMember($_, "properties.securityContactConfiguration.securityContactEmails") -and 
						-not [string]::IsNullOrEmpty($_.properties.securityContactConfiguration.securityContactEmails) -and 
						[Helpers]::CheckMember($_, "properties.securityContactConfiguration.securityContactPhone") -and
						-not [string]::IsNullOrEmpty($_.properties.securityContactConfiguration.securityContactPhone))
					{
						#Capture the contact phone number and emailid. This infomration is being captured as part of the metadata for the subscription
						$this.ContactPhoneNumber = $_.properties.securityContactConfiguration.securityContactPhone
						$this.ContactEmail = $_.properties.securityContactConfiguration.securityContactEmails
						$isMisconfigured = $false
					}
				}

				if($isMisconfigured)
				{
					$misConfiguredPolicies += $_;
				}
			};
		}

		return $misConfiguredPolicies;
    }

	[MessageData[]] SetPolicies()
    {
		return $this.SetPolicies($null,$null);
	}

	[MessageData[]] SetPolicies([string] $securityContactEmails, [string] $securityPhoneNumber)
    {	
		# $file1 = $this.LoadServerConfigFile("SecurityCenter.json") | ConvertTo-Json -Depth 4 | Out-String;
		# Write-Host $($file1)
		
		$file = [ConfigurationHelper]::LoadOfflineConfigFile("SecurityCenter.json");
		# Write-Host $($file)
		$body1 = ($file.autoProvisioning) | ConvertTo-Json -Depth 2 | Out-String
		$body2 = ($file.securityContacts) | ConvertTo-Json -Depth 2 | Out-String
		$body3 = ($file.ASC_Default) | ConvertTo-Json -Depth 3 | Out-String
		
		#Write-Host $($typ)
		#$trystr = $typ | Out-String
		#Write-Host $($trystr)
		
		# $body = $file | Out-String
		# #$bodytry = $body | ConvertFrom-Json

		# Write-Host $($body)
		#Write-Host $($bodytry)

		#$file.autoProvisioning | Out-String
		# $body = $file | ConvertFrom-Json
		# Write-Host $body
		# Write-Host $($body | Get-TypeData)
		# $file[autoProvisioning]
		# $p1 = $file | Get-TypeData
		# $p2 = $file.properties | Get-TypeData
		# Write-Host $($p1)
		# Write-Host $($p2)
		# $body1 = '{
		# 	"id": "/subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Security/autoProvisioningSettings/default",
		# 	"name": "default",
		# 	"type": "Microsoft.Security/autoProvisioningSettings",
		# 	"properties": {
		# 	  "autoProvision": "On"
		# 	}
		#   }'
		# # Write-Host $($body1)
		
		# $body2 = '{
		# 	"id": "/subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Security/securityContacts/default1",
		# 	"name": "default1",
		# 	"type": "Microsoft.Security/securityContacts",
		# 	"properties": {
		# 	  "email": "azsktest@gmail.com",
		# 	  "phone": "9000900090",
		# 	  "alertNotifications": "On",
		# 	  "alertsToAdmins": "On"
		# 	}
		#   }'

		# # $display_name = "ASC Default (subscription: $($this.SubscriptionContext.SubscriptionId))"
		# # Write-Host $display_name

		# # $scope = "/subscriptions/$($this.SubscriptionContext.SubscriptionId)"
		# # Write-Host $scope  
		
		# $body3 = '{
		# 	"sku": {
		# 	  "name": "A0",
		# 	  "tier": "Free"
		# 	},
		# 	"properties": {
		# 	  "displayName": "ASC Default (subscription: abb5301a-22a4-41f9-9e5f-99badff261f8)",
		# 	  "policyDefinitionId": "/providers/Microsoft.Authorization/policySetDefinitions/1f3afdf9-d0c9-4c3d-847f-89da613e70a8",
		# 	  "scope": "/subscriptions/abb5301a-22a4-41f9-9e5f-99badff261f8",
		# 	  "notScopes": [],
		# 	  "parameters": {
		# 		"systemUpdatesMonitoringEffect": {
		# 		  "value": "AuditIfNotExists"
		# 		},
		# 		"systemConfigurationsMonitoringEffect": {
		# 		  "value": "AuditIfNotExists"
		# 		},
		# 		"endpointProtectionMonitoringEffect": {
		# 		  "value": "AuditIfNotExists"
		# 		},
		# 		"diskEncryptionMonitoringEffect": {
		# 		  "value": "AuditIfNotExists"
		# 		},
		# 		"networkSecurityGroupsMonitoringEffect": {
		# 		  "value": "AuditIfNotExists"
		# 		},
		# 		"webApplicationFirewallMonitoringEffect": {
		# 		  "value": "Disabled"
		# 		},
		# 		"sqlAuditingMonitoringEffect": {
		# 		  "value": "AuditIfNotExists"
		# 		},
		# 		"sqlEncryptionMonitoringEffect": {
		# 		  "value": "AuditIfNotExists"
		# 		},
		# 		"nextGenerationFirewallMonitoringEffect": {
		# 		  "value": "Disabled"
		# 		},
		# 		"vulnerabilityAssesmentMonitoringEffect": {
		# 		  "value": "Disabled"
		# 		},
		# 		"storageEncryptionMonitoringEffect": {
		# 		  "value": "Audit"
		# 		},
		# 		"jitNetworkAccessMonitoringEffect": {
		# 		  "value": "Disabled"
		# 		},
		# 		"adaptiveApplicationControlsMonitoringEffect": {
		# 		  "value": "Disabled"
		# 		}
		# 	  },
		# 	  "description": "This policy assignment was automatically created by Azure Security Center",
		# 	  "metadata": {
		# 		"assignedBy": "Security Center"
		# 	  }
		# 	},
		# 	"id": "/subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Authorization/policyAsssignments/SecurityCenterBuiltIn",
		# 	"type": "Microsoft.Authorization/policyAssignments",
		# 	"name": "SecurityCenterBuiltIn"
		#   }'
		#   $body1 = $file.autoProvisioning | Out-String
		#   $body2 = $file.securityContacts | Out-String
		#   $body3 = $file.ASC_Default | Out-String

		#   Write-Host $($body1)
		#   Write-Host $($body2)
		#   Write-Host $($body3)
		#   Write-Host $($file.autoProvisioning | Out-String)
		#   Write-Host $($body2)
		  $uri1 = [WebRequestHelper]::AzureManagementUri + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/$([SecurityCenterHelper]::ProviderNamespace)/$([SecurityCenterHelper]::AutoProvisioningSettingsApi)/default$([SecurityCenterHelper]::ApiVersionNew)";
		  $header =  [SecurityCenterHelper]::AuthHeaderFromUri($uri1)
		  Invoke-RestMethod -Method PUT -Uri $uri1 -Headers $header -Body $body1;
		  #Write-Host $($res)	
		  
		  $uri2 = [WebRequestHelper]::AzureManagementUri + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/$([SecurityCenterHelper]::ProviderNamespace)/$([SecurityCenterHelper]::SecurityContactsApi)/default1$([SecurityCenterHelper]::ApiVersionNew)";
		  #$header2 =  [SecurityCenterHelper]::AuthHeaderFromUri($uri2)
		  #Write-Host $($header2)
		  Invoke-RestMethod -Method PUT -Uri $uri2 -Headers $header -Body $body2;
		  #Write-Host $($res)
		  
		  $uri3 = [WebRequestHelper]::AzureManagementUri + "subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/Microsoft.Authorization/policyAssignments/SecurityCenterBuiltIn$([SecurityCenterHelper]::ApiVersionLatest)";
		  $header3 =  [SecurityCenterHelper]::AuthHeaderFromUri($uri3)
		#   Write-Host $($header3)
		  Invoke-RestMethod -Method PUT -Uri $uri3 -Headers $header -Body $body3;
		  #Write-Host $($res)

		  #$r = @();
		  #$r += [SecurityCenterHelper]::InvokePutSecurityCenterRequest($json1.id, $json1, [SecurityCenterHelper]::ApiVersionNew);
		  #Write-Host $($uri)
		  #$r = [SecurityCenterHelper]::InvokeGetSecurityCenterRequest($this.SubscriptionContext.SubscriptionId, [SecurityCenterHelper]::AutoProvisioningSettingsApi, [SecurityCenterHelper]::ApiVersionNew)
		  #$res = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put,$uri, $strbody)
		  
		
		# $x = @();
		# $x += [SecurityCenterHelper]::InvokeGetSecurityCenterRequest($this.SubscriptionContext.SubscriptionId, [SecurityCenterHelper]::SecurityContactsApi, [SecurityCenterHelper]::ApiVersionNew)
		# $x += [SecurityCenterHelper]::InvokeGetSecurityCenterRequest($this.SubscriptionContext.SubscriptionId, [SecurityCenterHelper]::AutoProvisioningSettingsApi, [SecurityCenterHelper]::ApiVersionNew)
		
		
		# Write-Host $([SecurityCenterHelper]::InvokeGetSecurityCenterRequest($this.SubscriptionContext.SubscriptionId, [SecurityCenterHelper]::AutoProvisioningSettingsApi, [SecurityCenterHelper]::ApiVersionNew))
		
		# $prop = @()
		# $prop += [pscustomobject]@{
		# 	"autoProvision": "On";
		# }
		# $prop = @()
		# $prop += [pscustomobject]@{
    	# 		'autoProvision'='On';
		# }	

		# $jsonbody = [pscustomobject]@{
		# 	'id' = "/subscriptions/20ff7fc3-e762-44dd-bd96-b71116dcdc23/providers/Microsoft.Security/autoProvisioningSettings/default"
		# 	'name' = "default"
		# 	'type' = "Microsoft.Security/autoProvisioningSettings"
		# 	'properties' = $prop
		# }

		# $body1 = $jsonbody | ConvertTo-Json

		# $JSON ='{
		# 	"id" : "/subscriptions/20ff7fc3-e762-44dd-bd96-b71116dcdc23/providers/Microsoft.Security/autoProvisioningSettings/default",
		# 	"name" : "default",
		# 	"type" : "Microsoft.Security/autoProvisioningSettings",
		# 	"properties" : [{"autoProvision":"On"}]
		# 	}'
	
		# $Text = $JSON | ConvertFrom-JSON
		# $Text

		# $Body = @{  id = "/subscriptions/20ff7fc3-e762-44dd-bd96-b71116dcdc23/providers/Microsoft.Security/autoProvisioningSettings/default";
		# 			name = "default";
		# 			type = "Microsoft.Security/autoProvisioningSettings";
		# 			properties= @(
		# 				@{
		# 					autoProvision="On"
		# 				}
        #     		)
        # 		}

		# $JSON = $Body | ConvertTo-json
		# $JSON

# $y= @"{
# 	"FirstName":   "Bob",
# 	"LastName":   "Smith",
# 	"Age":  40,
# 	"DOB":  {
# 		"Month":   "March",
# 		"Day":  20,
# 		"Year":  1975
# 	}
# } "@ | ConvertFrom-Json 

#   $y
# Get-Content -Path $body1 | ConvertFrom-Json

		
		
		# $objbody = ConvertFrom-Json -InputObject $strbody
		# Write-Host $objbody
		# $body1 = @();
		# $body1 += @{id="/subscriptions/" + $this.SubscriptionContext.SubscriptionId +"/providers/" + $([SecurityCenterHelper]::ProviderNamespace) + "/" + $([SecurityCenterHelper]::$AutoProvisioningSettingsApi) + "/default"}
		# $body1 += @{name="default"}
		# $body1 += @{type="Microsoft.Security/autoProvisioningSettings"}
		# $body1 += @{properties = @{autoProvision = "On"}}
		#$body1
		# $json1 = $body1 | ConvertTo-Json
		# # $json2 = $json1 | ConvertFrom-Json 
		# $body1 = @{
		# 	id = '/subscriptions/abb5301a-22a4-41f9-9e5f-99badff261f8/providers/Microsoft.Security/autoProvisioningSettings/default'
		# 	name = 'default'
		# 	type = 'Microsoft.Security/autoProvisioningSettings'
		# 	properties = @{
		# 	  @{autoProvision = 'On'}
		# 	}
		#   }

		#Write-Host $body1 | Get-TypeData
		# $json1 = $body1 | ConvertTo-Json | ConvertFrom-Json
		# $json1 = $body1 | ConvertTo-Json
		#Write-Host $json1
		#$json1 | Get-TypeData | Write-Host
		#Write-Host $body1
		#Write-Host $json2
		
		#$uri = [WebRequestHelper]::AzureManagementUri.TrimEnd("/") + $this.SubscriptionContext.SubscriptionId + [SecurityCenterHelper]::ApiVersionNew;
		#$r += [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Put, $uri, $t);
		  

		#   $json1 = $body1 | ConvertTo-Json
		#   $json2 = $body1 | ConvertFrom-Json

		#   $json1 | Get-TypeData
		#   $json2 | Get-TypeData
		#   $body1 | Get-TypeData
		# $m = "Check Text: $($x)";
		# $this.PublishCustomMessage($m);

		# $body1 =@"
		#  {
		# 	"id": "/subscriptions/abb5301a-22a4-41f9-9e5f-99badff261f8/providers/Microsoft.Security/autoProvisioningSettings/default",
		# 	"name": "default",
		# 	"type": "Microsoft.Security/autoProvisioningSettings",
		# 	"properties": [{
		# 	  "autoProvision": "On"
		# 	]
		# }
		# "@

		# $b1 = $body1 | ConvertFrom-Json
		# Write-Output $b1
		#[SecurityCenterHelper]::InvokePutSecurityCenterRequest($_.id, $b1);

		# $body1 = @"
		# {
		# 	"id": "/subscriptions/abb5301a-22a4-41f9-9e5f-99badff261f8/providers/Microsoft.Security/autoProvisioningSettings/default",
		# 	"name": "default",
		# 	"type": "Microsoft.Security/autoProvisioningSettings",
		# 	"properties": {
		# 	  "autoProvision": "On"
		# 	}
		#   }
		#   "@
		
		# $b1 = $body1 | ConvertFrom-Json

		# $up = $x.Policy | Select-Object -Property properties
		#Write-Output $up

		# $m1 = "Check Text 2: $($this.id)";
		# $this.PublishCustomMessage($m1);

		#$m += $this.ModifyPolicies($x, $securityContactEmails, $securityPhoneNumber)
		
		[MessageData[]] $messages = @();
		
		# $azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		
		# $policiesToProcess = @();
		# $misConfiguredPolicies = $this.GetMisconfiguredPolicies();
		# if($misConfiguredPolicies.Count -ne 0)
		# {
		# 	$messages += [MessageData]::new("Security center policies must be configured with settings mentioned below:", $this.Policy.properties);

		# 	$messageText = "Found Security Center policies which are not correctly configured. Total misconfigured policies: $($misConfiguredPolicies.Count)";
		# 	$messages += [MessageData]::new($messageText);
			
		# 	$this.PublishCustomMessage($messageText);
			
		# 	# Check if subscription level policies are misconfigured
		# 	if(($misConfiguredPolicies | Where-Object { $_.properties.policyLevel -eq "Subscription" } | Measure-Object).Count -eq 0)
		# 	{
		# 		$policiesToProcess += $this.GetUniquePolicies() | Where-Object { $_.properties.policyLevel -eq "Subscription" };
		# 	}

		# 	$policiesToProcess += $misConfiguredPolicies;

		# 	#$messages += $this.ModifyPolicies($misConfiguredPolicies, $securityContactEmails, $securityPhoneNumber)		
		# }
		# else
		# {
		# 	$this.PublishCustomMessage("All Security Center policies are correctly configured. ");
		# 	$policiesToProcess += $this.GetUniquePolicies();
		# }	

		# $messages += $this.ModifyPolicies($policiesToProcess, $securityContactEmails, $securityPhoneNumber)

		# [Helpers]::SetResourceGroupTags($azskRGName,@{[Constants]::SecurityCenterConfigVersionTagName=$this.Policy.Version}, $false)			
		return $messages;
    }

	
	[MessageData[]] ModifyPolicies([PSObject[]] $policies, [string] $securityContactEmails, [string] $securityPhoneNumber)
    {	
		[MessageData[]] $messages = @();

		if($policies.Count -ne 0)
		{					
			#Keeping a copy of policy email addresses. The original policy object is going to update while merging email addresses
			$policyEmails = @();
			if([Helpers]::CheckMember($this.Policy, "properties.securityContactConfiguration.securityContactEmails"))
			{
				$policyEmails += $this.Policy.properties.securityContactConfiguration.securityContactEmails;
			}

			$updateObject = $this.Policy | Select-Object -Property properties
			
			$policies | Where-Object { $_.properties.policyLevel -eq "Subscription" } | ForEach-Object {
				#Merge email addresses
				$allEmails = @();
				
				if(-not [string]::IsNullOrWhiteSpace($securityContactEmails))
				{
					# User provided email addresses
					$allEmails += $this.ConvertToStringArray($securityContactEmails);
				}				

				# Add email addresses from policy files
				$allEmails += $policyEmails;

				# Ignore existing email addresses if user has provided any email addresses
				if($allEmails.Count -eq 0 -and [Helpers]::CheckMember($_, "properties.securityContactConfiguration.securityContactEmails") -and $_.properties.securityContactConfiguration.securityContactEmails.Count -ne 0)
				{
					$allEmails += $_.properties.securityContactConfiguration.securityContactEmails | Where-Object { -not [string]::IsNullOrWhiteSpace($_) };
				}
				
				$updateObject.properties.securityContactConfiguration.securityContactEmails = [array] ($allEmails | Select-Object -Unique)
				
				$policyName = "";
				if([Helpers]::CheckMember($_, "name"))
				{
					$policyName = "[$($_.name)]";
				}	

				$exceptionMessage = "";
				# Check if securityContactEmails is still null, then set it to blank array
				if(-not $updateObject.properties.securityContactConfiguration.securityContactEmails)
				{
					$exceptionMessage += "'SecurityContactEmails' is required to configure ASC. Please set up Security Center policy with cmdlet Set-AzSKAzureSecurityCenterPolicies. Run 'Get-Help Set-AzSKAzureSecurityCenterPolicies -full' for more help.`r`n";
					$updateObject.properties.securityContactConfiguration.securityContactEmails = @("");
				}

				$isPhoneRequired = $true;
				$existingPhoneNumber = "";
				if([Helpers]::CheckMember($_, "properties.securityContactConfiguration.securityContactPhone"))
				{
					if(-not [string]::IsNullOrWhiteSpace($_.properties.securityContactConfiguration.securityContactPhone))
					{
						$isPhoneRequired = $false;
						$existingPhoneNumber = $_.properties.securityContactConfiguration.securityContactPhone;
					}
				}

				if($isPhoneRequired -and [string]::IsNullOrWhiteSpace($securityPhoneNumber))
				{
					$exceptionMessage += "'SecurityPhoneNumber' is required to configure ASC. Please set up Security Center policy with cmdlet Set-AzSKAzureSecurityCenterPolicies. Run 'Get-Help Set-AzSKAzureSecurityCenterPolicies -full' for more help.`r`n";
				}

				if(-not [string]::IsNullOrWhiteSpace($exceptionMessage))
				{
					throw ([SuppressedException]::new($exceptionMessage, [SuppressedExceptionType]::Generic))
				}

				# Set phone number
				if(-not [string]::IsNullOrWhiteSpace($securityPhoneNumber))
				{
					if(-not (Get-Member -InputObject $updateObject.properties.securityContactConfiguration -Name "securityContactPhone"))
					{
						Add-Member -InputObject $updateObject.properties.securityContactConfiguration -MemberType NoteProperty -Name "securityContactPhone" -Value $securityPhoneNumber
					}
				}
				elseif(-not [string]::IsNullOrWhiteSpace($existingPhoneNumber))
				{
					if(-not (Get-Member -InputObject $updateObject.properties.securityContactConfiguration -Name "securityContactPhone"))
					{
						Add-Member -InputObject $updateObject.properties.securityContactConfiguration -MemberType NoteProperty -Name "securityContactPhone" -Value $existingPhoneNumber
					}
					else
					{
						$updateObject.properties.securityContactConfiguration.securityContactPhone = $existingPhoneNumber;
					}					
				}

				$messages += [MessageData]::new("Updating [$($_.properties.policyLevel)] level Security Center policy $policyName...", $_);

				$response = [SecurityCenterHelper]::InvokePutSecurityCenterRequest($_.id, $updateObject, [SecurityCenterHelper]::ApiVersion);

				[MessageData] $resultMessage = $null
				if(($response | Measure-Object).Count -ne 0)
				{
					$resultMessage = [MessageData]::new("Successfully updated [$($_.properties.policyLevel)] level Security Center policy $policyName", [MessageType]::Update);
				}
				else
				{
					$resultMessage = [MessageData]::new("Not able to update [$($_.properties.policyLevel)] level Security Center policy $policyName", [MessageType]::Error);
				}

				$messages += $resultMessage;
				$this.PublishCustomMessage($resultMessage);
			}

			# Setting up/Load the original values
			$this.Policy.properties.securityContactConfiguration.securityContactEmails = $policyEmails;
			if((Get-Member -InputObject $this.Policy.properties.securityContactConfiguration -Name "securityContactPhone"))
			{
				$this.Policy.properties.securityContactConfiguration.securityContactPhone = "";
			}

			$nonDefaultPolicies = @();
			$nonDefaultPolicies += $policies | Where-Object { $_.properties.unique -eq $this.On } | Select-Object -Property id, name
			if($nonDefaultPolicies.Count -ne 0)
			{    
				$messageText = " `r`nFound policies at resource group level in overridden state. These policies have to be manually corrected. Total: $($nonDefaultPolicies.Count)";
				$messages += [MessageData]::new($messageText + "`r`nBelow are the policies that have to be manually corrected: ", 
									$nonDefaultPolicies);
				$this.PublishCustomMessage($messageText);
			}			
		}
			
		return $messages;
    }
}
