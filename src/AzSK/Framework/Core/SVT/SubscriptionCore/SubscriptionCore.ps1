#using namespace Microsoft.Azure.Commands.Search.Models
Set-StrictMode -Version Latest
class SubscriptionCore: SVTBase
{
	hidden [AzureSecurityCenter] $ASCSettings
	hidden [ManagementCertificate[]] $ManagementCertificates
	hidden [PSObject] $RoleAssignments
	hidden [PSObject] $ApprovedAdmins;
	hidden [PSObject] $ApprovedSPNs;
	hidden [PSObject] $MandatoryAccounts;
	hidden [PSObject] $DeprecatedAccounts;
	hidden [PSObject] $CurrentContext;
	hidden [bool] $HasGraphAPIAccess;
	hidden [PSObject] $MisConfiguredASCPolicies;
	hidden [SecurityCenter] $SecurityCenterInstance;
	hidden [string[]] $SubscriptionMandatoryTags = @();
	hidden [System.Collections.Generic.List[TelemetryRBAC]] $PIMAssignments;
	hidden [System.Collections.Generic.List[TelemetryRBAC]] $permanentAssignments;
	hidden [CustomData] $CustomObject;

	SubscriptionCore([string] $subscriptionId):
        Base($subscriptionId)
    {
		$this.GetResourceObject();		
    }

	hidden [void] GetResourceObject()
	{
		$this.ASCSettings = [AzureSecurityCenter]::new()
		$this.CurrentContext = [Helpers]::GetCurrentRMContext();
		$this.MandatoryAccounts = $null
		$this.RoleAssignments = $null
		$this.ApprovedAdmins = $null
		$this.ApprovedSPNs = $null
		$this.DeprecatedAccounts = $null
		$this.HasGraphAPIAccess = [RoleAssignmentHelper]::HasGraphAccess();
		
		#Compute the policies ahead to get the security Contact Phone number and email id
		$this.SecurityCenterInstance = [SecurityCenter]::new($this.SubscriptionContext.SubscriptionId,$false);
		$this.MisConfiguredASCPolicies = $this.SecurityCenterInstance.CheckASCCompliance();

		#Fetch AzSKRGTags
		$azskRG = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		$azskRGTags = [Helpers]::GetResourceGroupTags($azskRG) ;

		[hashtable] $subscriptionMetada = @{}
		$subscriptionMetada.Add("HasGraphAccess",$this.HasGraphAPIAccess);
		$subscriptionMetada.Add("ASCSecurityContactEmailIds", $this.SecurityCenterInstance.ContactEmail);
		$subscriptionMetada.Add("ASCSecurityContactPhoneNumber", $this.SecurityCenterInstance.ContactPhoneNumber);
		$subscriptionMetada.Add("FeatureVersions", $azskRGTags);
		$this.SubscriptionContext.SubscriptionMetadata = $subscriptionMetada;
		$this.SubscriptionMandatoryTags += [ConfigurationManager]::GetAzSKConfigData().SubscriptionMandatoryTags;
	}
	hidden [ControlResult] CheckSubscriptionAdminCount([ControlResult] $controlResult)
	{
		$this.GetRoleAssignments()
		$this.LoadRBACConfig()
		#Excessive number of admins (> 5)

		$scope = $this.SubscriptionContext.Scope;

		$SubAdmins = @();
		$SubAdmins += $this.RoleAssignments | Where-Object { $_.RoleDefinitionName -eq 'CoAdministrator' `
																				-or $_.RoleDefinitionName -like '*ServiceAdministrator*' `
																				-or ($_.RoleDefinitionName -eq 'Owner' -and $_.Scope -eq $scope)}
		
		if($this.HasGraphAPIAccess -eq $false)
		{
			$this.PublishCustomMessage("Current Azure login context doesn't have graph api access");
		}
		$ClientSubAdmins = @()
		$ApprovedSubAdmins = @()

		$SubAdmins | ForEach-Object{
			$tempAdmin = $_
			$objId = $_.ObjectId
			$isApprovedAdmin = $false
			foreach($admin in $this.ApprovedAdmins)
			{
				$tempObjId = $admin.ObjectId
				if($admin.ObjectType -eq "ServicePrincipal")
				{
					$out = $null
					try { $out = $this.RoleAssignments | Where-Object { $_.ObjectId -eq $admin.ObjectId} } catch {}
					if($null -ne $out)
					{
						$tempObjId = $out[0].ObjectId
					}
				}
				if($objId -eq $tempObjId)
				{
					$ApprovedSubAdmins += $tempAdmin
					$isApprovedAdmin = $true
				}
			}
			if(-not $isApprovedAdmin)
			{
				$ClientSubAdmins += $tempAdmin
			}
		}

		$controlResult.AddMessage("There are a total of $($SubAdmins.Count) admin/owner accounts in your subscription`r`nOf these, the following $($ClientSubAdmins.Count) admin/owner accounts are not from a central team.", ($ClientSubAdmins | Select-Object DisplayName,SignInName,ObjectType, ObjectId));

		if(($ApprovedSubAdmins | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage("The following $($ApprovedSubAdmins.Count) admin/owner (approved) accounts are from a central team:`r`n", ($ApprovedSubAdmins | Select-Object DisplayName, SignInName, ObjectType, ObjectId));
		}
		$controlResult.AddMessage("Note: Approved central team accounts don't count against your limit");

		if($ClientSubAdmins.Count -gt $this.ControlSettings.NoOfApprovedAdmins)
		{
			$controlResult.VerificationResult = [VerificationResult]::Failed
			$controlResult.AddMessage("Number of admins/owners configured at subscription scope are more than the approved limit: $($this.ControlSettings.NoOfApprovedAdmins). Total: " + $ClientSubAdmins.Count);
		}
		else {
			$controlResult.AddMessage([VerificationResult]::Passed,
										"Number of admins/owners configured at subscription scope are with in approved limit: $($this.ControlSettings.NoOfApprovedAdmins). Total: " + $ClientSubAdmins.Count);
		}

		return $controlResult;
	}

	hidden [ControlResult] CheckApprovedCentralAccountsRBAC([ControlResult] $controlResult)
	{
		$this.GetRoleAssignments()
		$this.LoadRBACConfig()
        $state = $true
        $scope = $this.SubscriptionContext.Scope
		$out = $null
		$missingMandatoryAccount = @()
		$foundMandatoryAccount = @()
        if($null -ne $this.MandatoryAccounts)
        {
            foreach($admin in $this.MandatoryAccounts)
            {
                try{ $out = $this.RoleAssignments | Where-Object { $_.ObjectId -eq $admin.ObjectId -and $_.Scope -eq $scope -and $_.RoleDefinitionName -eq $admin.RoleDefinitionName }} catch { }
                if($null -eq  $out)
                {
					$missingMandatoryAccount+= $admin
                    $state = $false
                }
                else
                {
					$foundMandatoryAccount += $admin
                }
            }
			if(($foundMandatoryAccount | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage("Found mandatory accounts:",$foundMandatoryAccount)
			}
			if(($missingMandatoryAccount | Measure-Object).Count -gt 0)
			{
				$controlResult.SetStateData("Mandatory accounts which are not added to subscription", $missingMandatoryAccount);

				$controlResult.AddMessage("Missing mandatory accounts:",$missingMandatoryAccount)
			}
        }
        if(-not $state)
        {
			$controlResult.EnableFixControl = $true;
			if($controlResult.FixControlParameters)
			{
				$controlResult.FixControlParameters.Tags = $this.SubscriptionMandatoryTags;
			}
            $controlResult.VerificationResult = [VerificationResult]::Failed;
        }
        else {
            $controlResult.VerificationResult = [VerificationResult]::Passed
        }
		return $controlResult
	}

	hidden [ControlResult] ValidateCentralAccountsRBAC([ControlResult] $controlResult)
	{
		$this.GetRoleAssignments()
		$this.LoadRBACConfig()

		$scope = $this.SubscriptionContext.Scope;

		$SubAdmins = @();
		$SubAdmins += $this.RoleAssignments | Where-Object { $_.RoleDefinitionName -eq 'CoAdministrator' `
																				-or $_.RoleDefinitionName -like '*ServiceAdministrator*' `
																				-or ($_.RoleDefinitionName -eq 'Owner' -and $_.Scope -eq $scope)}
		if($this.HasGraphAPIAccess -eq $false)
		{
			$this.PublishCustomMessage("Current Azure login context doesn't have graph api access");
		}
		$ClientSubAdmins = @()
		$ApprovedSubAdmins = @()

		$SubAdmins | ForEach-Object{
			$tempAdmin = $_
			$objId = $_.ObjectId
			$isApprovedAdmin = $false
			foreach($admin in $this.ApprovedAdmins)
			{
				$tempObjId = $admin.ObjectId
				if($admin.ObjectType -eq "ServicePrincipal")
				{
					$out = $null
					#do we need to check for scope
					try { $out = $this.RoleAssignments | Where-Object { $_.ObjectId -eq $admin.ObjectId} } catch {}
					if($null -ne $out)
					{
						$tempObjId = $out[0].ObjectId
					}
				}
				if($objId -eq $tempObjId)
				{
					$ApprovedSubAdmins += $tempAdmin
					$isApprovedAdmin = $true
				}
			}
			if(-not $isApprovedAdmin)
			{
				$ClientSubAdmins += $tempAdmin
			}
		}		

		$stateData = @{
			Owners = @();
			CoAdmins = @();
		};

		$stateData.Owners += $ClientSubAdmins | Where-Object { -not ($_.RoleDefinitionName -eq 'CoAdministrator' -or $_.RoleDefinitionName -like '*ServiceAdministrator*') };
		$stateData.CoAdmins += $ClientSubAdmins | Where-Object { $_.RoleDefinitionName -eq 'CoAdministrator' -or $_.RoleDefinitionName -like '*ServiceAdministrator*' };

		$controlResult.SetStateData("All Subscription Owners/CoAdministrators/ServiceAdministrators (excludes accounts from central team)", $stateData);

		if(($ApprovedSubAdmins | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage("The following $($ApprovedSubAdmins.Count) admin/owner (approved) accounts are from a central team:`r`n", ($ApprovedSubAdmins | Select-Object DisplayName, SignInName, ObjectType, ObjectId));
		}		

		if($ClientSubAdmins.Count -gt 0)
		{
			$controlResult.VerificationResult = [VerificationResult]::Verify
			$controlResult.AddMessage("Please review the list of Admins and Owners for your subscription. Make sure to remove any that do not require persistent access. (Note: Owners that are part of a central approved list are to be retained. They are not listed above.)",($ClientSubAdmins | Select-Object DisplayName,SignInName,ObjectType, ObjectId));			
		}
		else {
			$controlResult.AddMessage([VerificationResult]::Passed,
										"No persistent owners/admins found on your subscription.");
		}

		return $controlResult;
	}

	hidden [ControlResult] CheckDeprecatedAccountsRBAC([ControlResult] $controlResult)
	{
		$this.GetRoleAssignments()
		$this.LoadRBACConfig()
        $state = $true
        $scope = $this.SubscriptionContext.Scope
		$out = $null
		$foundDeprecatedAccounts = @()
        if($null -ne  $this.DeprecatedAccounts)
        {
            foreach($depAcct in $this.DeprecatedAccounts)
            {
				foreach($roleassignment in $this.RoleAssignments){
				 if($roleassignment.ObjectId -eq $depAcct.ObjectId){
					$foundDeprecatedAccounts += $roleassignment
                    $state = $false
				 }
				}
            }
        }
        if(-not $state)
        {
			$controlResult.EnableFixControl = $true;
            #$controlResult.AddMessage([VerificationResult]::Failed, "Found deprecated accounts on the subscription:", $foundDeprecatedAccounts, $true, "DeprecatedAccounts")
			$controlResult.SetStateData("Deprecated accounts which have access to subscription", $foundDeprecatedAccounts);
            $controlResult.AddMessage([VerificationResult]::Failed, "Found deprecated accounts on the subscription:", $foundDeprecatedAccounts)
        }
        else {
			$controlResult.VerificationResult = [VerificationResult]::Passed
        }
		return $controlResult
	}

	hidden [ControlResult] CheckNonAADAccountsRBAC([ControlResult] $controlResult)
	{
		if($this.HasGraphAPIAccess)
		{
			$this.GetRoleAssignments()
			Set-Variable -Name liveAccounts -Scope Local

			$liveAccounts = [array]($this.RoleAssignments | Where-Object {$_.SignInName -like '*#EXT#@*.onmicrosoft.com'} )

			if(($liveAccounts | Measure-Object).Count -gt 0)
			{
				$controlResult.SetStateData("Non-AAD accounts which have access to subscription", $liveAccounts);
				$controlResult.AddMessage([VerificationResult]::Failed, "Found non-AAD account access present on the subscription:",($liveAccounts | Select-Object SignInName,DisplayName, Scope, RoleDefinitionName))
				#$controlResult.AddMessage([VerificationResult]::Failed, "Found non-AAD account access present on the subscription:",($liveAccounts | Select-Object SignInName,DisplayName, Scope, RoleDefinitionName), $true, "NonAADAccounts")
				$controlResult.VerificationResult =[VerificationResult]::Failed
			}
			else {
				$controlResult.VerificationResult =[VerificationResult]::Passed
			}
		}
		else
		{
			#If the VM is connected to ERNetwork and there is no NSG, then we should not fail as this would directly conflict with the NSG control as well.
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual, "Not able to query Graph API. This has to be manually verified.");
		}

		return $controlResult
	}

	hidden [ControlResult] CheckSVCAccountsRBAC([ControlResult] $controlResult)
	{
		if($this.HasGraphAPIAccess)
		{
			$this.GetRoleAssignments()
			$serviceAccounts = @()
			if($null -ne $this.CurrentContext)
			{
				$GraphAccessToken = [Helpers]::GetAccessToken([WebRequestHelper]::GraphAPIUri)
			}

			$uniqueUsers = @();
			$uniqueUsers += $this.RoleAssignments | Sort-Object SignInName -Unique | Select-Object DisplayName, SignInName,ObjectId, ObjectType
			$uniqueUsers | ForEach-Object{
				Set-Variable -Name user -Scope Local -Value $_
				Set-Variable -Name ObjectId -Scope Local -Value $_.ObjectId
				Set-Variable -Name SignInName -Scope Local -Value $_.SignInName
				Set-Variable -Name ObjectType -Scope Local -Value $_.ObjectType
				$isServiceAccount = [IdentityHelpers]::IsServiceAccount($_.ObjectId, $_.SignInName, $_.ObjectType, $GraphAccessToken)
				if($isServiceAccount)
				{
					$userScopes = $this.RoleAssignments | Where-Object {$_.SignInName -eq $SignInName}
					$userScopes | ForEach-Object{
						Set-Variable -Name userScope -Scope Local -Value $_
						$serviceAccounts += $userScope
					}
				}
			}

			if(($serviceAccounts | Measure-Object).Count -gt 0)
			{
				$serviceAccounts = $serviceAccounts | Where-Object {-not ($_.SignInName -like 'Sc-*')}
			}

			if(($serviceAccounts | Measure-Object).Count -gt 0)
			{
				$controlResult.SetStateData("Non-MFA enabled accounts present in the subscription", $serviceAccounts);
				#$controlResult.AddMessage([VerificationResult]::Failed, "Found non-MFA enabled accounts present on the subscription",($serviceAccounts | Select-Object Scope, DisplayName, SignInName, RoleDefinitionName, ObjectId, ObjectType), $true, "NonMFAAccounts")
				$controlResult.AddMessage([VerificationResult]::Failed, "Found non-MFA enabled accounts present on the subscription",($serviceAccounts | Select-Object Scope, DisplayName, SignInName, RoleDefinitionName, ObjectId, ObjectType));
			}
			else {
				$controlResult.VerificationResult =[VerificationResult]::Passed
			}
		}
		else
		{
			#If the VM is connected to ERNetwork and there is no NSG, then we should not fail as this would directly conflict with the NSG control as well.
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual, "Not able to query Graph API. This has to be manually verified.");
		}

		return $controlResult
	}

	hidden [ControlResult] CheckCoAdminCount([ControlResult] $controlResult)
	{
		$this.GetRoleAssignments()
        Set-Variable -Name classicCoAdmins -Scope Local

        $classicCoAdmins = $this.RoleAssignments | Where-Object { $_.RoleDefinitionName -eq 'CoAdministrator' `
																				-or $_.RoleDefinitionName -like '*ServiceAdministrator*' }
		$count = ($classicCoAdmins | Measure-Object).Count
        #$controlResult.AddMessage("No. of CoAdministrators found: $count",  ($classicCoAdmins | Select-Object DisplayName, Scope, ObjectType, ObjectId), $true, "CoAdminsList")
        $controlResult.AddMessage("No. of classic administrators found: $count",  ($classicCoAdmins | Select-Object DisplayName, Scope, ObjectType, ObjectId))
		$controlResult.SetStateData("Classic admins present in the subscription", $classicCoAdmins);

        if($count -gt $this.ControlSettings.NoOfClassicAdminsLimit)
        {
            $controlResult.VerificationResult = [VerificationResult]::Failed
		}
		else {
			$controlResult.VerificationResult =[VerificationResult]::Passed
		}

		return $controlResult
	}

	hidden [ControlResult] CheckManagementCertsPresence([ControlResult] $controlResult)
	{
		try
		{
			$this.GetManagementCertificates()
			if($this.ControlSettings.WhitelistedMgmtCerts | Get-Member -Name "Thumbprints")
			{
				$this.ManagementCertificates | ForEach-Object {
					Set-Variable -Name certObject -Value $_ -Scope Local
					if(($this.ControlSettings.WhitelistedMgmtCerts.Thumbprints | Where-Object {$_ -eq $certObject.CertThumbprint} | Measure-Object).Count -gt 0)
					{
						$certObject.Whitelisted = $true
						if($certObject.Difference.Days -gt $this.ControlSettings.WhitelistedMgmtCerts.ApprovedValidityRangeInDays)
						{
							$this.PublishCustomMessage("WARNING: Certificate expiry has been set more than the approved value: [$($this.ControlSettings.WhitelistedMgmtCerts.ApprovedValidityRangeInDays) days] for certificate: [$($certObject.CertThumbprint)]", [MessageType]::Warning);
						}
					}
				}
			}

			$FilteredMgmtCerts = @();
			$FilteredMgmtCerts += $this.ManagementCertificates | Where-Object {-not $_.Whitelisted}
			Set-Variable -Name isCompliant -Scope Local


			$whitelistedMgmtCerts = @();
			$whitelistedMgmtCerts += $this.ManagementCertificates | Where-Object { $_.Whitelisted}

			if($whitelistedMgmtCerts.Count -gt 0)
			{
				$controlResult.AddMessage("Whitelisted management certificates on the subscription.",($whitelistedMgmtCerts | Select-Object CertThumbprint, SubjectName, Issuer, Created , ExpiryDate , IsExpired, Whitelisted))
			}

			if($null -ne $FilteredMgmtCerts  -and $FilteredMgmtCerts.Count -gt 0)
			{
				$controlResult.SetStateData("Management certificates in the subscription", $FilteredMgmtCerts);
				#$controlResult.AddMessage([VerificationResult]::Failed,"Found Management certificates on the subscription.",($this.ManagementCertificates | Select-Object CertThumbprint, SubjectName, Issuer, Created , ExpiryDate , IsExpired, Whitelisted), $true, "MgmtCerts")
				$controlResult.AddMessage([VerificationResult]::Failed,"Management certificates which needs to be removed.",($FilteredMgmtCerts | Select-Object CertThumbprint, SubjectName, Issuer, Created , ExpiryDate , IsExpired, Whitelisted))
			}
			else {
				$controlResult.VerificationResult = [VerificationResult]::Passed
			}
		}
		catch
		{
			#Check specifically for forbidden error instead of any exception
			if([Helpers]::CheckMember($_.Exception,"Response") -and  ($_.Exception).Response.StatusCode -eq [System.Net.HttpStatusCode]::Forbidden)
            {
				#If the VM is connected to ERNetwork and there is no NSG, then we should not fail as this would directly conflict with the NSG control as well.
				$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
                $controlResult.AddMessage([VerificationResult]::Manual, "You do not have required permissions to check for management certificates on this subscription. This control requires 'Co-Admin' privilege.");	
				$controlResult.AddMessage([MessageData]::new([Constants]::CoAdminElevatePermissionMsg));
				
				return $controlResult
            }
            else
            {
                throw $_
            }			
		}
		return $controlResult
	}

	hidden [ControlResult] CheckAzureSecurityCenterSettings([ControlResult] $controlResult)
	{
		if ($this.SecurityCenterInstance)
		{
			#$controlResult.AddMessage([MessageData]::new("Security center policies must be configured with settings mentioned below:", $this.SecurityCenterInstance.Policy.properties));			

			if(($this.MisConfiguredASCPolicies | Measure-Object).Count -ne 0)
			{
				$controlResult.EnableFixControl = $true;

				$controlResult.SetStateData("Security Center misconfigured policies", $this.MisConfiguredASCPolicies);
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Following security center policies are not correctly configured. Please update the policies in order to comply.", $this.MisConfiguredASCPolicies));
			}
			# elseif(-not $this.SecurityCenterInstance.IsLatestVersion -and $this.SecurityCenterInstance.IsValidVersion)
			# {
			# 	$this.PublishCustomMessage("WARNING: The Azure Security Center policies in your subscription are out of date.`nPlease update to the latest version by running command Update-AzSKSubscriptionSecurity.", [MessageType]::Warning);
			# 	$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("Current security center policies are configured as per older policy. To update as per latest configuration, run command Update-AzSKSubscriptionSecurity."));
			# }
			# elseif(($this.MisConfiguredASCPolicies | Measure-Object).Count -ne 0)
			# {
			# 	$controlResult.EnableFixControl = $true;

			# 	$controlResult.SetStateData("Security Center misconfigured policies", $this.MisConfiguredASCPolicies);
			# 	$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Following security center policies are not correctly configured. Please update the policies in order to comply.", $this.MisConfiguredASCPolicies));
			# }
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("All security center policies are correctly configured."));
			}
		}
		return $controlResult
	}

	hidden [ControlResult] CheckAzureSecurityCenterAlerts([ControlResult] $controlResult)
	{
		$this.GetASCAlerts()

		$activeAlerts = ($this.ASCSettings.Alerts | Where-Object {$_.State -eq "Active"})
		if(($activeAlerts | Measure-Object).Count -gt 0)
		{
			$controlResult.SetStateData("Active alert in Security Center", $activeAlerts);
			$controlResult.AddMessage([VerificationResult]::Failed,"Azure Security Center have active alerts that need to resolved.")
		}
		else {
			$controlResult.VerificationResult =[VerificationResult]::Passed
		}

		$controlResult.AddMessage(($activeAlerts | Select-Object State, AlertDisplayName, AlertName, Description, ReportedTimeUTC, RemediationSteps))

		return $controlResult
	}	

	hidden [ControlResult] CheckSPNsRBAC([ControlResult] $controlResult)
	{
		if($this.HasGraphAPIAccess)
		{
			$this.GetRoleAssignments()
			$this.LoadRBACConfig()

			$scope = $this.SubscriptionContext.Scope
			$approvedIds = @();
			$approvedIds += $this.ApprovedSPNs | Select-Object -Property ObjectId | Select-Object -ExpandProperty ObjectId;

			$servicePrincipalNames = $this.RoleAssignments | Where-Object {$_.ObjectType -eq "ServicePrincipal" -and ($approvedIds -notcontains $_.ObjectId ) -and ($_.RoleDefinitionName -eq "Owner" -or $_.RoleDefinitionName -eq "Contributor") -and $_.Scope -eq $scope}
			if(($servicePrincipalNames | Measure-Object).Count -gt 0)
			{
				$controlResult.SetStateData("Service Principals (excluding approved central accounts) having owner or contributor access on subscription", $servicePrincipalNames);
				$controlResult.VerificationResult = [VerificationResult]::Failed
				#$controlResult.AddMessage("Below is the list SPNs which have either owner or contributor access on subscription:", ($servicePrincipalNames | Select-Object DisplayName, SignInName,ObjectType), $true, "CriticalSPNs")
				$controlResult.AddMessage("Below is the list SPNs (excluding approved central accounts) which have either owner or contributor access on subscription:", $servicePrincipalNames)
			}
			else {
					$controlResult.VerificationResult =[VerificationResult]::Passed
			}
		}
		else
		{
			#If the VM is connected to ERNetwork and there is no NSG, then we should not fail as this would directly conflict with the NSG control as well.
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual, "Not able to query Graph API. This has to be manually verified.");
		}
		return $controlResult
	}

	hidden [ControlResult] CheckResourceLocksUsage([ControlResult] $controlResult)
	{
        $foundLocks = $true
		$lockDtls = $null
        #Command will throw exception if no locks found
        try {
                $lockDtls = Get-AzureRmResourceLock -ErrorAction Stop # -Scope "/subscriptions/$SubscriptionId"
        }
        catch
        {
            $foundLocks = $false
        }
        if($null -eq $lockDtls)
        {
            $foundLocks = $false
        }

        if($foundLocks)
        {
			$controlResult.SetStateData("Resource Locks on subscription", $lockDtls);
			#$controlResult.AddMessage([VerificationResult]::Verify, "Subscription lock details :", ($lockDtls | Select-Object Name,  @{Name="Lock Level";Expression={$_.Properties.level}}, LockId, @{Name="Notes";Expression={$_.Properties.notes}} ), $true, "SubscriptionLocks")
			$controlResult.AddMessage([VerificationResult]::Verify, "Subscription lock details :", ($lockDtls | Select-Object Name,  @{Name="Lock Level";Expression={$_.Properties.level}}, LockId, @{Name="Notes";Expression={$_.Properties.notes}} ))
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Failed, "There are no resource locks present on the subscription.");
        }
		return $controlResult
	}

	hidden [ControlResult] CheckARMPoliciesCompliance([ControlResult] $controlResult)
	{

		$subARMPol = [ARMPolicy]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, "", $false);
        $output = @()
        $foundMandatoryPolicies = $true

		[bool] $IsValidVersion = $false;
		[bool] $IsLatestVersion = $false;
		[string] $CurrentVersion = "0.0.0";
		[string] $LatestVersion = "0.0.0";
		$AzSKRG = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
		# $CurrentVersion = [Helpers]::GetResourceGroupTag($AzSKRG, [Constants]::ARMPolicyConfigVersionTagName)
		# if([string]::IsNullOrWhiteSpace($CurrentVersion))
		# {
		# 	$CurrentVersion = "0.0.0"
		# }
		# $minSupportedVersion = [ConfigurationManager]::GetAzSKConfigData().AzSKARMPolMinReqdVersion 
		# $IsLatestVersion = $this.IsLatestVersionConfiguredOnSub($subARMPolConfig.Version,[Constants]::ARMPolicyConfigVersionTagName);
		# $IsValidVersion = $this.IsLatestVersionConfiguredOnSub($subARMPolConfig.Version,[Constants]::ARMPolicyConfigVersionTagName) -or [System.Version]$minSupportedVersion -le [System.Version]$CurrentVersion ;
		# $LatestVersion = $subARMPolConfig.Version;

        $nonCompliantPolicies = $subARMPol.ValidatePolicyConfiguration();

        if(($nonCompliantPolicies | Measure-Object).Count -le 0)
        {
            $controlResult.AddMessage([VerificationResult]::Passed, "Found all the mandatory policies on the Subscription.");
        }
		# elseif(-not $IsLatestVersion -and $IsValidVersion)
		# {
		# 	$this.PublishCustomMessage("WARNING: The Azure Resource Manager policies in your subscription are out of date.`nPlease update to the latest version by running command Update-AzSKSubscriptionSecurity.", [MessageType]::Warning);			
		# 	$controlResult.AddMessage([VerificationResult]::Passed, "ARM policies has been configured with older policy on the subscription. To update as per latest configuration, run command Update-AzSKSubscriptionSecurity.");
		# }
        else
        {
			# $controlResult.EnableFixControl = $true;
			# if($controlResult.FixControlParameters)
			# {
			# 	$controlResult.FixControlParameters.Tags = $this.SubscriptionMandatoryTags;
			# }
			$controlResult.SetStateData("Missing ARM policies", $nonCompliantPolicies);
			$controlResult.AddMessage([VerificationResult]::Failed, "Some of the mandatory policies are missing]", $nonCompliantPolicies);
        }
		return $controlResult
	}

	hidden [ControlResult] CheckCriticalAlertsPresence([ControlResult] $controlResult)
	{
        $alertDiffList = @()
		$operationDiffList = @()
		$alertConfig =  $this.LoadServerConfigFile("Subscription.InsARMAlerts.json");
		$subInsightsAlertsConfig = $alertConfig.AlertList | Where-Object {$_.tags -contains "Mandatory"}
        $foundRequiredAlerts = $true
		[bool] $IsValidVersion = $false;
		[bool] $IsLatestVersion = $false;
		[string] $CurrentVersion = "0.0.0";
		[string] $LatestVersion = "0.0.0";
		$AlertsPkgRG = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
		$CurrentVersion = [Helpers]::GetResourceGroupTag($AlertsPkgRG, [Constants]::AzSKAlertsVersionTagName)
		if([string]::IsNullOrWhiteSpace($CurrentVersion))
		{
			$CurrentVersion = "0.0.0"
		}
		$minSupportedVersion = [ConfigurationManager]::GetAzSKConfigData().AzSKAlertsMinReqdVersion 
		$IsLatestVersion = $this.IsLatestVersionConfiguredOnSub($alertConfig.Version,[Constants]::AzSKAlertsVersionTagName);
		$IsValidVersion = $this.IsLatestVersionConfiguredOnSub($alertConfig.Version,[Constants]::AzSKAlertsVersionTagName) -or [System.Version]$minSupportedVersion -le [System.Version]$CurrentVersion ;
		$LatestVersion = $alertConfig.Version;

        if($null -ne $subInsightsAlertsConfig)
        {
            $subInsightsAlertsConfig =[array]($subInsightsAlertsConfig)

			
            $alertsRG = [array] (Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -eq "$AlertsPkgRG"})
            $configuredAlerts = $null
            if (($alertsRG | Measure-Object).Count -eq 1)
            {
                $configuredAlerts = Get-AzureRmResource -ResourceType "Microsoft.Insights/activityLogAlerts" -ResourceGroupName  $AlertsPkgRG -ExpandProperties -ErrorAction SilentlyContinue
            }

            if((($alertsRG | Measure-Object).Count -eq 1) -and ($null -ne $configuredAlerts)){
                $subInsightsAlertsConfig | ForEach-Object{                    
					Set-Variable -Name alert -Scope Local -Value $_
                    Set-Variable -Name alertEnabled -Scope Local -Value $_.Enabled
                    Set-Variable -Name alertName -Scope Local -Value $_.Name
                    Set-Variable -Name tags -Scope Local -Value $_.Tags
                    $haveMatchedTags = ((($tags | Where-Object { $this.SubscriptionMandatoryTags -contains $_ }) | Measure-Object).Count -gt 0)
                    
					if($alertEnabled -and $haveMatchedTags)
                    {
                        $foundAlert = [array]($configuredAlerts | Where-Object  {$_.Name -eq $alertName})
						#Verify if alert present
                        if($null -eq $foundAlert -or ($foundAlert | Measure-Object).Count -le 0)
                        {
                            $foundRequiredAlerts = $false
                            $alertDiffList += $alert
                        }
						#if alert exists then verify operation list 
						else
						{
							$diffObj= $foundAlert.Properties.condition.allOf[2].anyOf | Select-Object equals
							$refObj= $alert.AlertOperationList | Where-Object {$_.Enabled -eq $true} | Select-Object OperationName
							$opDiffList= Compare-Object -ReferenceObject $refObj -DifferenceObject $diffObj | Select-Object -property @{N='OperationList';E={$_.InputObject.equals}}  
							if($null -ne $opDiffList)
							{
								$opList=  $opDiffList.OperationList
								$foundRequiredAlerts = $false
								$operationDiffList += @{Name=$alertName; Description=$alert.Description; OperationNameList = $opList }
							}
						}
                    }
                }
            }
            else {
				#If new alerts are not found and server flag EnableV1AlertFailure is false, 
				#then check for V1 alerts presence and pass the control with the warning
				if(-not $this.ControlSettings.SubscriptionCore.EnableV1AlertFailure)
				{
					$foundRequiredAlerts= $this.CheckV1CriticalAlertsPresence();					
				}
				else
				{
					$foundRequiredAlerts = $false					
				}
            }
        }

        if($foundRequiredAlerts)
        {
            $controlResult.AddMessage([VerificationResult]::Passed, "Insights alerts has been configured on the subscription.");
        }
		elseif(-not $IsLatestVersion -and $IsValidVersion)
		{
			$this.PublishCustomMessage("WARNING: The Azure Insight alerts configured in your subscription are out of date.`nPlease update to the latest version by running command Update-AzSKSubscriptionSecurity.", [MessageType]::Warning);			
			$controlResult.AddMessage([VerificationResult]::Passed, "Insights alerts has been configured with older policy on the subscription. To update as per latest configuration, run command Update-AzSKSubscriptionSecurity.");
		}
        else
        {
			$controlResult.EnableFixControl = $true;			
			$controlResult.AddMessage([VerificationResult]::Failed, "Missing mandatory critical alerts");
			if($controlResult.FixControlParameters)
			{
				$controlResult.FixControlParameters.Tags = $this.SubscriptionMandatoryTags;
			}
			
				if(($alertDiffList| Measure-Object).Count -ne 0)
				{
					$controlResult.AddMessage([VerificationResult]::Failed, "Missing mandatory critical alerts list on the subscription.", $alertDiffList);	
					$controlResult.SetStateData("Missing mandatory critical alerts", $alertDiffList);
				}
				if(($operationDiffList | Measure-Object).Count -ne 0)
				{
					$controlResult.AddMessage([VerificationResult]::Failed, "Operation mismatch in critical alerts on the subscription.", $operationDiffList);	
					$controlResult.SetStateData("Missing mandatory critical alerts", $operationDiffList);
				}
				

									
        }
		return $controlResult
	}

	#Below function is to check V1 critical alerts presence. This is temporary function to support backward compatibility for alert.
	hidden [bool] CheckV1CriticalAlertsPresence()
	{
        $output = @()
        $subInsightsAlertsConfig = $this.LoadServerConfigFile("Subscription.InsAlerts.json")
        $foundRequiredAlerts = $true
        if($null -ne $subInsightsAlertsConfig)
        {
            $subInsightsAlertsConfig =[array]($subInsightsAlertsConfig)

			$AlertsPkgRG = "AzSKAlertsRG"
            $alertsRG = [array] (Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -match "^$AlertsPkgRG"})
            $configuredAlerts = $null
            if (($alertsRG | Measure-Object).Count -eq 1)
            {
                $configuredAlerts = Get-AzureRmAlertRule -ResourceGroup $AlertsPkgRG -WarningAction SilentlyContinue
            }

            if((($alertsRG | Measure-Object).Count -eq 1) -and ($null -ne $configuredAlerts)){
                $subInsightsAlertsConfig | ForEach-Object{
                    Set-Variable -Name alert -Scope Local -Value $_
                    Set-Variable -Name alertEnabled -Scope Local -Value $_.Enabled
                    Set-Variable -Name alertName -Scope Local -Value $_.Name
                    Set-Variable -Name tags -Scope Local -Value $_.Tags
                    $haveMatchedTags = ((($tags | Where-Object { $this.SubscriptionMandatoryTags -contains $_ }) | Measure-Object).Count -gt 0)
                    if($alertEnabled -and $haveMatchedTags)
                    {
                        $foundAlert = [array]($configuredAlerts | Where-Object  {$_.Name -eq $alertName})
                        if($null -eq $foundAlert -or ($foundAlert | Measure-Object).Count -le 0)
                        {
                            $foundRequiredAlerts = $false
                            $output += $alert
                        }
                    }
                }
            }
            else {
                $foundRequiredAlerts = $false
            }
        }

        if($foundRequiredAlerts)
        {
			$this.PublishCustomMessage("Old AzSK alerts are present on subscription. This will be deprecated soon. Please update alerts with 'Set-AzSKAlerts' cmdlet.", [MessageType]::Warning);
			return $true
        }
        else
        {
			return $false
        }		
	}

	hidden [ControlResult] CheckCustomRBACRolesPresence([ControlResult] $controlResult)
	{
		$this.GetRoleAssignments()
        $out = @()
		$customRoles = @();
		$customRolesWithAssignment = @()

		$whitelistedCustomRoleIds = @();
		$whitelistedCustomRoleIds += $this.ControlSettings.WhitelistedCustomRBACRoles | Select-Object -Property Id | Select-Object -ExpandProperty Id
		$CustomRBACAssignedRolesCount=0;
		$customRoles += Get-AzureRmRoleDefinition -Custom | Where-Object { $whitelistedCustomRoleIds -notcontains $_.Id };
		$customRoles | ForEach-Object {
			$role = $_;
			$roleWithAssignment = $role | Select-Object *, RoleAssignmentCount;
			$roleWithAssignment.RoleAssignmentCount = ($this.RoleAssignments | Where-Object { $_.RoleDefinitionId -eq $role.Id } | Measure-Object).Count;
			$CustomRBACAssignedRolesCount+=$roleWithAssignment.RoleAssignmentCount;
			$customRolesWithAssignment += $roleWithAssignment;
		}

		if($whitelistedCustomRoleIds.Count -ne 0)
		{
            $controlResult.AddMessage("No. of whitelisted custom RBAC roles: $($whitelistedCustomRoleIds.Count)", $this.ControlSettings.WhitelistedCustomRBACRoles);
		}

        if($CustomRBACAssignedRolesCount -eq 0)
        {
			$controlResult.AddMessage([VerificationResult]::Passed, "No custom RBAC role definitions with active role assignments found. ")
		}
        else
        {			
			$customRoleAssignments = $customRolesWithAssignment | Where-object { $_.RoleAssignmentCount -gt 0} 
			$controlResult.SetStateData("Custom RBAC definitions with active assignments", $customRoleAssignments)
			$out= $customRoleAssignments | Select-Object Name,Description,Id,RoleAssignmentCount;
            $controlResult.AddMessage([VerificationResult]::Verify, "Found $($customRolesWithAssignment.Count) custom RBAC role definitions`r`nCustom RBAC roles definitions with active role assignments : `n", $out);
        }

		return $controlResult
	}

	hidden [ControlResult] CheckPresenceOfClassicResources([ControlResult] $controlResult)
	{
       $classicResources = [array] (Get-AzureRMResource | Where-Object {$_.ResourceType -like "*classic*"} )
        if(($classicResources | Measure-Object).Count -gt 0)
        {
			#$controlResult.SetStateData("Classic resources on subscription", $classicResources);

			$ClassicStorageCount = 0;
			$CloudServiceCount = 0;
			$ClassicVMCount = 0;
			$ClassicVNetCount = 0;

			$ClassicVMCount = (Get-AzureRmResource -ResourceType Microsoft.ClassicCompute/virtualMachines | Measure-Object).Count;
			$ClassicStorageCount = (Get-AzureRmResource -ResourceType Microsoft.ClassicStorage/storageAccounts | Measure-Object).Count;
			$CloudServiceCount = (Get-AzureRmResource -ResourceType Microsoft.ClassicCompute/domainNames | Measure-Object).Count;
			$ClassicVNetCount = (Get-AzureRmResource -ResourceType Microsoft.ClassicNetwork/virtualNetworks | Measure-Object).Count;

            #$controlResult.AddMessage([VerificationResult]::Failed, "Found classic resources on the subscription.", $classicResources, $true, "ClassicResources")

			$classicResourcesCount = New-Object -TypeName PSObject
			$classicResourcesCount | Add-Member -NotePropertyName VMCount -NotePropertyValue $ClassicVMCount
			$classicResourcesCount | Add-Member -NotePropertyName Storagecount -NotePropertyValue $ClassicStoragecount
			$classicResourcesCount | Add-Member -NotePropertyName CloudServicecount -NotePropertyValue $CloudServicecount
			$classicResourcesCount | Add-Member -NotePropertyName ClassicVNetCount -NotePropertyValue $ClassicVNetCount

			$controlResult.AddMessage("Found classic resources on the subscription :");
			$controlResult.AddMessage($classicResourcesCount);
			$controlResult.SetStateData("Classic resources on subscription", $classicResourcesCount);

            $controlResult.AddMessage([VerificationResult]::Failed, "Classic resource details" ,$classicResources)
        }
        else
        {
           $controlResult.VerificationResult = [VerificationResult]::Passed
        }

		return $controlResult
	}

	hidden [ControlResult] CheckPresenceOfClassicVMs([ControlResult] $controlResult)
	{
        $classicVMResources = [array] (Get-AzureRmResource -ResourceType Microsoft.ClassicCompute/virtualMachines)
        if(($classicVMResources | Measure-Object).Count -gt 0)
        {
			$controlResult.SetStateData("Classic virtual machines on subscription", $classicVMResources);
            #$controlResult.AddMessage([VerificationResult]::Failed, "Found classic resources on the subscription.", $classicResources, $true, "ClassicResources")
            $controlResult.AddMessage([VerificationResult]::Failed, "Found classic virtual machines on the subscription.", $classicVMResources)
        }
        else
        {
           $controlResult.VerificationResult = [VerificationResult]::Passed
        }

		return $controlResult
	}

	hidden [ControlResult] CheckPublicIpUsage([ControlResult] $controlResult)
	{
		$publicIps = Get-AzureRmPublicIpAddress
		$ipFlatList = [System.Collections.ArrayList]::new()
		foreach($publicIp in $publicIps){
			$ip = $publicIp | Select-Object ResourceGroupName, Name, Location, PublicIpAllocationMethod, IpAddress, PublicIpAddressVersion, AssociatedResourceType, AssociatedResourceId, AssociatedResourceName, Fqdn
			$ip.AssociatedResourceType = "Not Associated"
			$ip.AssociatedResourceName = "Not Associated"
			$ip.Fqdn = "Not Set"
			$ipConfig = $publicIp.IpConfiguration
			if($null -ne $ipConfig -and ![string]::IsNullOrWhiteSpace($ipConfig.Id)) {
				$ip.AssociatedResourceId = $ipConfig.Id
				try {
					$providerIndex = $ipConfig.Id.IndexOf("/providers/")
					$associatedResourceTypeStart = $providerIndex + 11
					$associatedResourceTypeEnd = $ipConfig.Id.IndexOf("/", $ipConfig.Id.IndexOf("/", $associatedResourceTypeStart) + 1)
					$associatedResourceTypeLength =  $associatedResourceTypeEnd - $associatedResourceTypeStart
					$ip.AssociatedResourceType = $ipConfig.Id.SubString($associatedResourceTypeStart, $associatedResourceTypeLength)
					$associatedResourceNameStart = $associatedResourceTypeEnd + 1
					$associatedResourceNameLength = $ipConfig.Id.IndexOf("/", $associatedResourceNameStart) - $associatedResourceNameStart
					$ip.AssociatedResourceName = $ipConfig.Id.SubString($associatedResourceNameStart, $associatedResourceNameLength)
				}
				catch {}
			}
			if($null -ne $publicIp.DnsSettings -and ![string]::IsNullOrWhiteSpace($publicIp.DnsSettings.Fqdn)) {
				$ip.Fqdn = $publicIp.DnsSettings.Fqdn
			}
			$ipFlatList.Add($ip) | Out-Null
		}
		if($ipFlatList.Count -gt 0)
        {
			$controlResult.SetStateData("Public IPs on the subscription", $ipFlatList);
            $controlResult.AddMessage([VerificationResult]::Verify, "Found public IPs on the subscription.", $ipFlatList)
        }
        else
        {
           $controlResult.VerificationResult = [VerificationResult]::Passed
        }
		return $controlResult
	}

	hidden [ControlResult] CheckPermanentRoleAssignments([ControlResult] $controlResult)
	{
		$message='';
		if($null -eq $this.PIMAssignments -and $null -eq $this.permanentAssignments)
		{
			$message=$this.GetPIMRoles();
		}
		
		$criticalRoles=$this.ControlSettings.CriticalPIMRoles;
		$permanentRoles=$this.permanentAssignments;
		if(($permanentRoles| measure-object).Count -gt 0 )
		{
			$criticalPermanentRoles=$permanentRoles|Where-Object{$_.RoleDefinitionName -in $criticalRoles}
			if($criticalPermanentRoles.Count-gt 0)
			{
				$controlResult.SetStateData("Permanent role assignments present on subscription",$criticalPermanentRoles)
				$controlResult.AddMessage([VerificationResult]::Failed, "Subscription contains permanent role assignment for critical roles : $criticalRoles")
				$permanentRolesbyRoleDefinition=$criticalPermanentRoles|Sort-Object -Property RoleDefinitionName
				$controlResult.AddMessage($permanentRolesbyRoleDefinition);
				
			}
			else {
				$controlResult.AddMessage([VerificationResult]::Passed)
			}
		}
		else
		{
			$controlResult.AddMessage("Unable to fetch PIM data, please verify manually.")
			$controlResult.AddMessage($message);
		}

		return $controlResult

	}	   
	hidden [void] LoadRBACConfig()
	{
		if(($this.MandatoryAccounts | Measure-Object).Count -eq 0 `
			-or ($this.ApprovedAdmins | Measure-Object).Count -eq 0 `
			-or ($this.DeprecatedAccounts | Measure-Object).Count -eq 0 `
			)
			{
				$this.MandatoryAccounts = @()
				$this.ApprovedAdmins = @()
				$this.ApprovedSPNs = @()
				$subRBACConfig = $this.LoadServerConfigFile("Subscription.RBAC.json")
				if($null -ne $subRBACConfig)
				{
					 $subRBACConfig.ValidActiveAccounts | Where-Object {$_.Enabled} | ForEach-Object{
						 if($_.RoleDefinitionName -eq "Owner")
						 {
							$this.ApprovedAdmins += $_
						 }
						 if(($_.Tags | Where-Object {$_ -eq $this.SubscriptionMandatoryTags } | Measure-Object).Count -gt 0)
						 {
							$this.MandatoryAccounts += $_
						 }
						 if($_.ObjectType -eq "ServicePrincipal")
						 {
							$this.ApprovedSPNs += $_
						 }
					}
				}
				$this.DeprecatedAccounts = $subRBACConfig.DeprecatedAccounts | Where-Object {$_.Enabled}
			}
	}

	hidden [void] GetRoleAssignments()
	{
		if($null -eq $this.RoleAssignments)
		{
			$this.RoleAssignments =  [RoleAssignmentHelper]::GetAzSKRoleAssignment($true,$true)
			#filter deleted user/group/spn assignments
			$deletedUserAssignments = $this.RoleAssignments | Where-Object{ [string]::IsNullOrWhiteSpace($_.DisplayName) -and [string]::IsNullOrWhiteSpace($_.SignInName) -and $_.ObjectType -eq 'Unknown'}
			if(($deletedUserAssignments | Measure-Object).Count -gt 0)
			{
				$this.RoleAssignments = $this.RoleAssignments | Where-Object{ $deletedUserAssignments.RoleAssignmentId -inotcontains $_.RoleAssignmentId }			
			}
		}
	}

	hidden [void] GetManagementCertificates()
	{
		$ResourceAppIdURI = [WebRequestHelper]::ClassicManagementUri;
		$ClassicAccessToken = [Helpers]::GetAccessToken($ResourceAppIdURI)
		if($null -ne $ClassicAccessToken)
		{
			$header = "Bearer " + $ClassicAccessToken
			$headers = @{"Authorization"=$header;"Content-Type"="application/json"; "x-ms-version" ="2013-08-01"}
			$uri = [string]::Format("{0}/{1}/certificates","https://management.core.windows.net",$this.SubscriptionContext.SubscriptionId)
			$mgmtCertsResponse = Invoke-WebRequest -Method GET -Uri $uri -Headers $headers -UseBasicParsing
			if($mgmtCertsResponse.StatusCode -ge 200 -and $mgmtCertsResponse.StatusCode -le 399)
			{
				if($null -ne $mgmtCertsResponse.Content)
				{
					[xml] $mgmtCerts = $mgmtCertsResponse.Content;
					$this.ManagementCertificates = @();
					if($null -ne $mgmtCerts -and [Helpers]::CheckMember($mgmtCerts, "SubscriptionCertificates.SubscriptionCertificate"))
					{
						$this.ManagementCertificates = [ManagementCertificate]::ListManagementCertificates($mgmtCerts.SubscriptionCertificates.SubscriptionCertificate)
					}
				}
			}
		}
	}

	hidden [void] GetASCAlerts()
	{
		$ResourceAppIdURI = [WebRequestHelper]::AzureManagementUri;
		$AccessToken = [Helpers]::GetAccessToken($ResourceAppIdURI)
		if($null -ne $AccessToken)
		{
			$header = "Bearer " + $AccessToken
			$headers = @{"Authorization"=$header;"Content-Type"="application/json";}

			# Commenting this as it's costly call and expected to happen in Set-ASC/SSS/USS 
			#[SecurityCenterHelper]::RegisterResourceProvider();

			$uri=[system.string]::Format("https://management.azure.com/subscriptions/{0}/providers/microsoft.Security/alerts?api-version=2015-06-01-preview",$this.SubscriptionContext.SubscriptionId)
			$result = ""
			$err = $null
			$output = $null
			try {
				$result = Invoke-WebRequest -Method GET -Uri $uri -Headers $headers -UseBasicParsing
				if($result.StatusCode -ge 200 -and $result.StatusCode -le 399){
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
			}
			catch{
				$err = $_
				if($null -ne $err)
				{
					if($null -ne $err.ErrorDetails.Message){
						$json = (ConvertFrom-Json $err.ErrorDetails.Message)
						if($null -ne $json){
							$return = $json
							if($json.'odata.error'.code -eq "Request_ResourceNotFound")
							{
								$return = $json.'odata.error'.message
							}
						}
					}
				}
			}
			$this.ASCSettings.Alerts = [AzureSecurityCenter]::GetASCAlerts($output)
		}
	}	
   
	hidden [string] GetPIMRoles()
	{
		$message='';
		if($null -eq $this.PIMAssignments)
		{
			$resourceAppIdURI =[WebRequestHelper]::ClassicManagementUri;
			$accessToken = [Helpers]::GetAccessToken($ResourceAppIdURI)
			if($null -ne $AccessToken)
			{
				$authorisationToken = "Bearer " + $accessToken
				$headers = @{"Authorization"=$authorisationToken;"Content-Type"="application/json"}
				$uri=[Constants]::PIMAPIUri +"?`$filter=type%20eq%20%27subscription%27&`$orderby=displayName"
				try
				{
					#Get external id for the current subscription
					$response=[WebRequestHelper]::InvokeGetWebRequest($uri, $headers)
					$subId=$this.SubscriptionContext.SubscriptionId;
					$extID=$response| Where-Object{$_.externalId.split('/') -contains $subId}
					$resourceID=$extID.id;
					$this.PIMAssignments=@();
					$this.permanentAssignments=@();
					if($null -ne $response -and $null -ne $resourceID)
					{
						#Get RoleAssignments from PIM API 
						$url=[string]::Format([Constants]::PIMAPIUri +"/{0}/roleAssignments?`$expand=subject,roleDefinition(`$expand=resource)", $resourceID)
						$responseContent=[WebRequestHelper]::InvokeGetWebRequest($url, $headers)
						foreach ($roleAssignment in $responseContent)
						{
							$item= New-Object TelemetryRBAC 
							$item.SubscriptionId= $subId;
							$item.RoleAssignmentId = $roleAssignment.externalId
							$item.RoleDefinitionId=$roleAssignment.roleDefinition.templateId
							$item.Scope=$roleAssignment.roleDefinition.resource.externalId;
							$item.RoleDefinitionName = $roleAssignment.roleDefinition.displayName
							$item.ObjectId = $roleAssignment.subject.id
							$item.DisplayName = $roleAssignment.subject.displayName
							$item.ObjectType=$roleAssignment.subject.type;	
							if($roleAssignment.IsPermanent -eq $false)
							{
								#If roleAssignment is non permanent and not active
								$item.IsPIMEnabled=$true;
								if($roleAssignment.assignmentState -eq "Eligible")
								{
									$this.PIMAssignments.Add($item);
								}
							}
							else
							{
								#If roleAssignment is permanent
								$item.IsPIMEnabled=$false;
								$this.permanentAssignments.Add($item);

							}
						}
				
					}
					$message='OK';
				}
				catch
				{
					$message=$_;
				}
			}
		}

		return($message);
	}

	hidden [void] PublishRBACTelemetryData()
	{
		$AccessRoles= $this.RoleAssignments;
		$PIMRoles=$this.PIMAssignments
		if($AccessRoles -ne $null)
		{
			$RBACAssignment = New-Object "System.Collections.Generic.List[TelemetryRBAC]"
			$subId=$this.SubscriptionContext.SubscriptionId;
				 foreach($item in $AccessRoles)
				{  	$matchingAssignment=New-Object TelemetryRBAC;
					$RBACTelemetry= New-Object TelemetryRBAC;
					$RBACTelemetry.SubscriptionId= $subId;
					$RBACTelemetry.DisplayName=$item.DisplayName;
					$RBACTelemetry.ObjectId= $item.ObjectId;
					$RBACTelemetry.Scope=$item.Scope;
					$RBACTelemetry.ObjectType=$item.ObjectType;
					$RBACTelemetry.RoleAssignmentId="";
					if($item.RoleAssignmentId -ne $null)
					{
						$RBACTelemetry.RoleAssignmentId=$item.RoleAssignmentId.tostring();
					}
					$RBACTelemetry.RoleDefinitionName=$item.RoleDefinitionName;
					$RBACTelemetry.RoleDefinitionId= $item.RoleDefinitionId;
					if($null -ne $PIMRoles)
					{
						$matchingObject=$PIMRoles| Where-Object{$_.ObjectId -eq $RBACTelemetry.ObjectId -and $_.RoleDefinitionId -eq $RBACTelemetry.RoleDefinitionId -and $_.Scope -eq $RBACTelemetry.Scope}
						if($null -ne $matchingObject)
						{
							$RBACTelemetry.IsPIMEnabled=$true;	
							
						}
					}
					$RBACAssignment.Add($RBACTelemetry);
				
				
				}
		
		
			if($null -ne $PIMRoles){
				$RBACAssignment.AddRange($PIMRoles);
			}
			$this.CustomObject=New-Object CustomData;
			$this.CustomObject.Value=$RBACAssignment;
			$this.CustomObject.Name="RBACTelemetry";
			
		}	
	
	}



}
