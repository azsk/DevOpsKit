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
			
			$allPolicies += [SecurityCenterHelper]::InvokeGetSecurityCenterRequest($this.SubscriptionContext.SubscriptionId, [SecurityCenterHelper]::PoliciesApi)
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
		[MessageData[]] $messages = @();
		#setting the tag at AzSKRG
		$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		
		$policiesToProcess = @();
		$misConfiguredPolicies = $this.GetMisconfiguredPolicies();
		if($misConfiguredPolicies.Count -ne 0)
		{
			$messages += [MessageData]::new("Security center policies must be configured with settings mentioned below:", $this.Policy.properties);

			$messageText = "Found Security Center policies which are not correctly configured. Total misconfigured policies: $($misConfiguredPolicies.Count)";
			$messages += [MessageData]::new($messageText);
			
			$this.PublishCustomMessage($messageText);
			
			# Check if subscription level policies are misconfigured
			if(($misConfiguredPolicies | Where-Object { $_.properties.policyLevel -eq "Subscription" } | Measure-Object).Count -eq 0)
			{
				$policiesToProcess += $this.GetUniquePolicies() | Where-Object { $_.properties.policyLevel -eq "Subscription" };
			}

			$policiesToProcess += $misConfiguredPolicies;

			#$messages += $this.ModifyPolicies($misConfiguredPolicies, $securityContactEmails, $securityPhoneNumber)		
		}
		else
		{
			$this.PublishCustomMessage("All Security Center policies are correctly configured. ");
			$policiesToProcess += $this.GetUniquePolicies();
		}	

		$messages += $this.ModifyPolicies($policiesToProcess, $securityContactEmails, $securityPhoneNumber)

		[Helpers]::SetResourceGroupTags($azskRGName,@{[Constants]::SecurityCenterConfigVersionTagName=$this.Policy.Version}, $false)			
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

				$response = [SecurityCenterHelper]::InvokePutSecurityCenterRequest($_.id, $updateObject);

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
