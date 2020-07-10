#using namespace Microsoft.Azure.Commands.Search.Models
Set-StrictMode -Version Latest
class SubscriptionCore: AzSVTBase
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
	hidden [PSObject] $ASCTierDetails;
	hidden [PSObject] $MisConfiguredOptionalASCPolicies;
	hidden [PSObject] $MisConfiguredSecurityPolicySettings;
	hidden [PSObject] $MisConfiguredAutoProvisioningSettings;
	hidden [PSObject] $MisConfiguredSecurityContactDetails;
	hidden [PSObject[]] $ASCSecuritySolutionDetails;
	hidden [SecurityCenter] $SecurityCenterInstance;
	hidden [hashtable] $ResourceTier;
	hidden [string[]] $SubscriptionMandatoryTags = @();
	hidden [System.Collections.Generic.List[TelemetryRBAC]] $PIMAssignments;
	hidden [System.Collections.Generic.List[TelemetryRBAC]] $permanentAssignments;
	hidden [System.Collections.Generic.List[TelemetryRBAC]] $RGLevelPIMAssignments;
	hidden [System.Collections.Generic.List[TelemetryRBAC]] $RGLevelPermanentAssignments;
	hidden [System.Collections.Generic.List[TelemetryRBACExtended]] $PIMAssignmentswithPName = @();
	hidden [System.Collections.Generic.List[TelemetryRBACExtended]] $PIMRGLevelAssignmentswithPName = @();
	hidden [CustomData] $CustomObject;
	hidden $SubscriptionExtId;

	SubscriptionCore([string] $subscriptionId):
        Base($subscriptionId)
    {
		$this.GetResourceObject();		
    }

	hidden [void] GetResourceObject()
	{
		$this.ASCSettings = [AzureSecurityCenter]::new()
		$this.CurrentContext = [ContextHelper]::GetCurrentRMContext();
		$this.MandatoryAccounts = $null
		$this.RoleAssignments = $null
		$this.ApprovedAdmins = $null
		$this.ApprovedSPNs = $null
		$this.DeprecatedAccounts = $null
		$this.HasGraphAPIAccess = [RoleAssignmentHelper]::HasGraphAccess();
		
		#Compute the policies ahead to get the security Contact Phone number and email id
		$this.SecurityCenterInstance = [SecurityCenter]::new($this.SubscriptionContext.SubscriptionId,$false);
		$this.MisConfiguredOptionalASCPolicies = $this.SecurityCenterInstance.CheckOptionalSecurityPolicySettings();
		$this.ASCTierDetails = $this.SecurityCenterInstance.CheckASCTierSettings();
		$this.MisConfiguredSecurityPolicySettings = $this.SecurityCenterInstance.CheckSecurityPolicySettings();
		$this.MisConfiguredAutoProvisioningSettings = $this.SecurityCenterInstance.CheckAutoProvisioningSettings();
		$this.MisConfiguredSecurityContactDetails = $this.SecurityCenterInstance.CheckSecurityContactSettings();
		if([FeatureFlightingManager]::GetFeatureStatus("EnableSecuritySolutionsDataCapture",$($this.SubscriptionContext.SubscriptionId)))
		{
			$this.ASCSecuritySolutionDetails = $this.SecurityCenterInstance.GetASCSecuritySolutionsDetails();
		
		}	#Fetch AzSKRGTags
		$azskRG = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		$azskRGTags = [ResourceGroupHelper]::GetResourceGroupTags($azskRG) ;

		[hashtable] $subscriptionMetada = @{}
		$subscriptionMetada.Add("HasGraphAccess",$this.HasGraphAPIAccess);
		$subscriptionMetada.Add("ASCSecurityContactEmailIds", $this.SecurityCenterInstance.ContactEmail);
		$subscriptionMetada.Add("ASCSecurityContactPhoneNumber", $this.SecurityCenterInstance.ContactPhoneNumber);
		$subscriptionMetada.Add("FeatureVersions", $azskRGTags);
		$subscriptionMetada.Add("SecuritySolutions", $this.ASCSecuritySolutionDetails);
		$this.SubscriptionContext.SubscriptionMetadata = $subscriptionMetada;
		$this.SubscriptionMandatoryTags += [ConfigurationManager]::GetAzSKConfigData().SubscriptionMandatoryTags;

	}

	[ControlItem[]] ApplyServiceFilters([ControlItem[]] $controls)
	{
		$result = $controls;

		#Scan resource group persistent access control only when scan source is equal to CA. We are filtering this control due to performance issue.
		$isRGPersistentAccessCheckEnabled = [FeatureFlightingManager]::GetFeatureStatus("EnableResourceGroupPersistentAccessCheck",$($this.SubscriptionContext.SubscriptionId))
		if($isRGPersistentAccessCheckEnabled -eq $false)
		{
			$result = $result | Where-Object { $_.Tags -notcontains "RGPersistentAccess" }
		}
		
		return $result;
	}


	hidden [ControlResult] CheckSubscriptionAdminCount([ControlResult] $controlResult)
	{
		$this.GetRoleAssignments()
		$this.LoadRBACConfig()
		#Excessive number of admins (> 5)

		$scope = $this.SubscriptionContext.Scope;

		$SubAdmins = @();
		$SubAdmins += $this.RoleAssignments | Where-Object { ($_.RoleDefinitionName -eq 'CoAdministrator' `
			-or $_.RoleDefinitionName -like '*ServiceAdministrator*' `
			-or $_.RoleDefinitionName -eq 'Owner') -and $_.Scope -eq $scope}

		#Commented the below code since Co-Admin can exist independently now.
		#Excluded the Co-Administrator since one couldn't be Co-admin without having the Owner privileges.
		#$SubAdmins += $this.RoleAssignments | Where-Object { ($_.RoleDefinitionName -like '*ServiceAdministrator*' `
		#	-or $_.RoleDefinitionName -eq 'Owner') -and $_.Scope -eq $scope}
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

		$controlResult.AddMessage("There are a total of $($SubAdmins.Count) admin/owner accounts in your subscription`r`nOf these, the following $($ClientSubAdmins.Count) admin/owner accounts are not from a central team.", ($ClientSubAdmins | Select-Object DisplayName, SignInName, ObjectType, ObjectId, RoleDefinitionName));

		if(($ApprovedSubAdmins | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage("The following $($ApprovedSubAdmins.Count) admin/owner (approved) accounts are from a central team:`r`n", ($ApprovedSubAdmins | Select-Object DisplayName, SignInName, ObjectType, ObjectId, RoleDefinitionName));
		}
		$controlResult.AddMessage("Note: Approved central team accounts don't count against your limit");

		if($ClientSubAdmins.Count -gt $this.ControlSettings.NoOfApprovedAdmins)
		{
			$controlResult.VerificationResult = [VerificationResult]::Failed
			$controlResult.AddMessage("Number of admins/owners configured at subscription scope are more than the approved limit: $($this.ControlSettings.NoOfApprovedAdmins). Total: " + $ClientSubAdmins.Count);
		}
		else
		{
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
			$liveAccounts =@()

			if ([Helpers]::CheckMember($this.ControlSettings.SubscriptionCore,"NonADIdentitiesPatterns") -and ($this.ControlSettings.SubscriptionCore.NonADIdentitiesPatterns | Measure-Object).Count -ne 0) 
			{
				$NonADIdentitiesPattern = (('^' + (($this.ControlSettings.SubscriptionCore.NonADIdentitiesPatterns |foreach {[regex]::escape($_)}) –join '|') + '$')) -replace '[\\]',''
				$liveAccounts = [array]($this.RoleAssignments | Where-Object {$_.SignInName -and $_.SignInName.ToLower() -imatch $NonADIdentitiesPattern} )
				#Exclude whitelisted patterns for non-AD identities
				if( ($liveAccounts | Measure-Object).Count -gt 0 -and  [Helpers]::CheckMember($this.ControlSettings.SubscriptionCore,"WhitelistedNonADIndentitiesPatterns") -and ($this.ControlSettings.SubscriptionCore.WhitelistedNonADIndentitiesPatterns | Measure-Object).Count -ne 0)
				{
					$WhiteListedNonADIdentitiesPattern = (('^' + (($this.ControlSettings.SubscriptionCore.WhitelistedNonADIndentitiesPatterns |foreach {[regex]::escape($_)}) –join '|') + '$')) -replace '[\\]',''
					$liveAccounts = [array]($liveAccounts | Where-Object {$_.SignInName -and $_.SignInName.ToLower() -inotmatch $WhiteListedNonADIdentitiesPattern} )
				}				
			}

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
				$GraphUri = [WebRequestHelper]::GetGraphUrl()
				$GraphAccessToken = [ContextHelper]::GetAccessToken($GraphUri)
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

	hidden [ControlResult] CheckAzureSecurityCenterAlerts([ControlResult] $controlResult)
	{
		$this.GetASCAlerts()
		$activeAlerts = ($this.ASCSettings.Alerts | Where-Object {$_.State -eq "Active" })
		if(($activeAlerts | Measure-Object).Count -gt 0 )
		{
			  if( [Helpers]::CheckMember($this.ControlSettings, 'ASCAlertsThresholdInDays')  )
			  {
				 $AlertDaysCheck = $this.ControlSettings.ASCAlertsThresholdInDays
				 $AlertSeverityCheck = $this.ControlSettings.ASCAlertsThresholdInDays.PSObject.Properties.Name;	
				 $activeAlerts = $activeAlerts | Where-Object {$_.ReportedSeverity -in $AlertSeverityCheck}			
				 $activeAlerts = $activeAlerts | Where-Object{ ( [System.DateTime]::Parse($_.ReportedTimeUTC).AddDays($AlertDaysCheck.($_.ReportedSeverity)) -le ([System.DateTime]::UtcNow)) }
				 if(($activeAlerts | Measure-Object).Count -gt 0)
				 {
					$controlResult.SetStateData("Active alert in Security Center", ($activeAlerts | Select-Object AlertName, ReportedTimeUTC));
					$controlResult.AddMessage([VerificationResult]::Failed,"Azure Security Center have active alerts that need to resolved.")
                    $controlResult.AddMessage(($activeAlerts | Select-Object State, AlertDisplayName, AlertName, Description, ReportedTimeUTC,ReportedSeverity, RemediationSteps))
					return $controlResult;
				 }
				 else
				 {
					$controlResult.VerificationResult =[VerificationResult]::Passed
					return $controlResult;
				 }
			  }
			 $controlResult.SetStateData("Active alert in Security Center", ($activeAlerts | Select-Object AlertName, ReportedTimeUTC));
			 $controlResult.AddMessage([VerificationResult]::Failed,"Azure Security Center have active alerts that need to resolved.")
             $controlResult.AddMessage(($activeAlerts | Select-Object State, AlertDisplayName, AlertName, Description, ReportedTimeUTC,ReportedSeverity, RemediationSteps))

				
		}
		else 
		{
			 $controlResult.VerificationResult =[VerificationResult]::Passed
		}
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
                $lockDtls = Get-AzResourceLock -ErrorAction Stop # -Scope "/subscriptions/$SubscriptionId"
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
			$controlResult.SetStateData("Resource Locks on subscription", ($lockDtls | Select-Object @{Name="LockLevel";Expression={$_.Properties.level}}, LockId))
			#$controlResult.AddMessage([VerificationResult]::Verify, "Subscription lock details :", ($lockDtls | Select-Object Name,  @{Name="Lock Level";Expression={$_.Properties.level}}, LockId, @{Name="Notes";Expression={$_.Properties.notes}} ), $true, "SubscriptionLocks")
			$controlResult.AddMessage([VerificationResult]::Verify, "Subscription lock details :", ($lockDtls | Select-Object @{Name="LockLevel";Expression={$_.Properties.level}}, LockId))
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Failed, "There are no resource locks present on the subscription.");
        }
		return $controlResult
	}

	hidden [ControlResult] CheckARMPoliciesCompliance([ControlResult] $controlResult)
	{

		$subARMPol = [ARMPolicy]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, "Mandatory", $false);
        $output = @()
        $foundMandatoryPolicies = $true

		[bool] $IsValidVersion = $false;
		[bool] $IsLatestVersion = $false;
		[string] $CurrentVersion = "0.0.0";
		[string] $LatestVersion = "0.0.0";
		$AzSKRG = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
        $nonCompliantPolicies = $subARMPol.ValidatePolicyConfiguration();

        if(($nonCompliantPolicies | Measure-Object).Count -le 0)
        {
            $controlResult.AddMessage([VerificationResult]::Passed, "Found all the mandatory policies on the Subscription.");
        }
        else
        {
			$controlResult.EnableFixControl = $true;
			$controlResult.SetStateData("Missing ARM policies", $nonCompliantPolicies);
			$controlResult.AddMessage([VerificationResult]::Failed, "Some of the mandatory policies are missing]", $nonCompliantPolicies);
        }
		return $controlResult
	}

	hidden [ControlResult] CheckCriticalAlertsPresence([ControlResult] $controlResult)
	{
        $alertDiffList = @()
		$operationsDiffList = @()
        $foundRequiredAlerts = $false
		$isValidVersion = $false;
		$isLatestVersion = $false;
		$currentVersion = "0.0.0";
		$latestVersion = "0.0.0";
		$configuredAlerts = $null
    
        # Get list of alerts from Json file
		$alertConfig =  $this.LoadServerConfigFile("Subscription.InsARMAlerts.json");
		$subInsightsAlertsConfig = $alertConfig.AlertList | Where-Object { ($_.tags -contains "Mandatory") -or ($_.tags -contains "Optional")}
        
        # Get currently set alert's version
		$alertsPkgRG = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
		$currentVersion = [ResourceGroupHelper]::GetResourceGroupTag($alertsPkgRG, [Constants]::AzSKAlertsVersionTagName)
		if([string]::IsNullOrWhiteSpace($currentVersion))
		{
			$currentVersion = "0.0.0"
		}
		$minSupportedVersion = [ConfigurationManager]::GetAzSKConfigData().AzSKAlertsMinReqdVersion 
		$IsLatestVersion = [ResourceGroupHelper]::IsLatestVersionConfiguredOnSub($alertConfig.Version,[Constants]::AzSKAlertsVersionTagName);
		$IsValidVersion = ($IsLatestVersion) -or ([System.Version]$minSupportedVersion -le [System.Version]$currentVersion) ;
		$LatestVersion = $alertConfig.Version;

        # Get currently configured alerts from azure portal
        if(($subInsightsAlertsConfig | Measure-Object).Count -gt 0)
		{		
            $alertsRG = Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -eq "$alertsPkgRG"}
            if (($alertsRG | Measure-Object).Count -eq 1)
            {
                $configuredAlerts = Get-AzResource -ResourceType "Microsoft.Insights/activityLogAlerts" -ResourceGroupName  $alertsPkgRG -ExpandProperties -ErrorAction SilentlyContinue
			}			
			if(($configuredAlerts | Measure-Object).Count -gt 0)
			{
				$matchingAlertRulesNames = Compare-Object -ReferenceObject $configuredAlerts.Name -DifferenceObject $subInsightsAlertsConfig.Name -IncludeEqual -ExcludeDifferent
				if(($matchingAlertRulesNames| Measure-Object).count -gt 0)
				{
					$configuredAlerts = $configuredAlerts | Where-Object { $matchingAlertRulesNames.InputObject -contains $_.Name }
					if(($configuredAlerts | Measure-Object).Count -gt 0)
					{
						$currentAlertsOperationsList = $configuredAlerts | ForEach-Object { 
							if([Helpers]::CheckMember($_,"Properties.condition") -and (($_.Properties.condition.allOf | Measure-Object).Count -eq 3) -and [Helpers]::CheckMember($_.Properties.condition.allOf[2],"anyOf"))
							{
								$_.Properties.condition.allOf[2].anyOf
							}
						} | Select-Object -property @{N='OperationName';E={$_.equals}} -Unique	
					}
					else
					{
						$currentAlertsOperationsList = $null
					}
                    $requiredAlertsOperations = ($subInsightsAlertsConfig | Where{ $_.Tags -contains $this.SubscriptionMandatoryTags}).AlertOperationList 
                    $requiredAlertsOperationsList = ($requiredAlertsOperations | Where-Object { $_.Tags -contains $this.SubscriptionMandatoryTags }).OperationName
					if((($currentAlertsOperationsList| Measure-Object).Count -gt 0) -and (($requiredAlertsOperationsList | Measure-Object).Count -gt 0))
					{
						$operationsDiffList = Compare-Object -ReferenceObject $requiredAlertsOperationsList -DifferenceObject $currentAlertsOperationsList.OperationName | Where-Object { $_.SideIndicator -eq "<=" }
						if(($operationsDiffList| Measure-Object).Count -eq 0)
						{
							$foundRequiredAlerts = $true
						}
						else
						{
							$operationsDiffList = $operationsDiffList.InputObject
							$foundRequiredAlerts = $false
						}
					}
					elseif(($requiredAlertsOperationsList| Measure-Object).Count -eq 0)
					{
						$foundRequiredAlerts = $true
					}
					elseif(($currentAlertsOperationsList | Measure-Object).Count -eq 0)
					{
						$foundRequiredAlerts = $false
					}
				}
				else
				{
					# Alert(s) not found in specified RG
					$foundRequiredAlerts = $false
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
		else
		{
			# No alert(s) defined in JSON file
			$foundRequiredAlerts = $true	
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
				if(($operationsDiffList | Measure-Object).Count -ne 0)
				{
					$controlResult.AddMessage([VerificationResult]::Failed, "Operation mismatch in critical alerts on the subscription.", $operationsDiffList);	
					$controlResult.SetStateData("Missing mandatory critical alerts", $operationsDiffList);
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

			$alertsPkgRG = "AzSKAlertsRG"
            $alertsRG = [array] (Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -match "^$alertsPkgRG"})
            $configuredAlerts = $null
            if (($alertsRG | Measure-Object).Count -eq 1)
            {
                $configuredAlerts = Get-AzAlertRule -ResourceGroup $alertsPkgRG -WarningAction SilentlyContinue
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
		$customRoles += Get-AzRoleDefinition -Custom | Where-Object { $whitelistedCustomRoleIds -notcontains $_.Id };
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
       $classicResources = [array] (Get-AzResource | Where-Object {$_.ResourceType -like "*classic*"} )
        if(($classicResources | Measure-Object).Count -gt 0)
        {
			#$controlResult.SetStateData("Classic resources on subscription", $classicResources);

			$ClassicStorageCount = 0;
			$CloudServiceCount = 0;
			$ClassicVMCount = 0;
			$ClassicVNetCount = 0;

			$ClassicVMCount = (Get-AzResource -ResourceType Microsoft.ClassicCompute/virtualMachines | Measure-Object).Count;
			$ClassicStorageCount = (Get-AzResource -ResourceType Microsoft.ClassicStorage/storageAccounts | Measure-Object).Count;
			$CloudServiceCount = (Get-AzResource -ResourceType Microsoft.ClassicCompute/domainNames | Measure-Object).Count;
			$ClassicVNetCount = (Get-AzResource -ResourceType Microsoft.ClassicNetwork/virtualNetworks | Measure-Object).Count;

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
        $classicVMResources = [array] (Get-AzResource -ResourceType Microsoft.ClassicCompute/virtualMachines)
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
		$publicIps = Get-AzPublicIpAddress
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
		$message = '';
		$whitelistedPermanentRoles = $null
		try 
		{
		if($null -eq $this.PIMAssignments -and $null -eq $this.permanentAssignments)
		{
			$message=$this.GetPIMRoles();
		}
		if($message -ne 'OK') # if there is some while making request message will contain exception
		{

				$controlResult.AddMessage("Unable to fetch PIM data.")
				$controlResult.AddMessage($message);
		}
		else 
		{
			$criticalRoles = $this.ControlSettings.CriticalPIMRoles.Subscription;
			$permanentRoles = $this.permanentAssignments;
			if([Helpers]::CheckMember($this.ControlSettings,"WhitelistedPermanentRoles"))
			{
				$whitelistedPermanentRoles = $this.ControlSettings.whitelistedPermanentRoles
			}
			if(($permanentRoles | measure-object).Count -gt 0 )
			{
				
				$criticalPermanentRoles = $permanentRoles | Where-Object{$_.RoleDefinitionName -in $criticalRoles -and ($_.ObjectType -eq 'User' -or $_.ObjectType -eq 'Group')}
				if($null -ne $whitelistedPermanentRoles)
				{
					$criticalPermanentRoles = $criticalPermanentRoles | Where-Object{ $_.DisplayName -notin $whitelistedPermanentRoles.DisplayName}
				}
				if(($criticalPermanentRoles| measure-object).Count -gt 0)
				{
					$controlResult.SetStateData("Permanent role assignments present on subscription",$criticalPermanentRoles)
					$controlResult.AddMessage([VerificationResult]::Failed, "Subscription contains permanent role assignment for critical roles : $criticalRoles")
					$permanentRolesbyRoleDefinition=$criticalPermanentRoles|Sort-Object -Property RoleDefinitionName
					$controlResult.AddMessage($permanentRolesbyRoleDefinition);
					
				}
				else 
				{
					$controlResult.AddMessage([VerificationResult]::Passed, "No permanent assignments found for the following roles at subscription scope: $($criticalRoles -join ', ')")
				}
			}
			else
			{	
				$controlResult.AddMessage([VerificationResult]::Passed, "No permanent assignments found for the following roles at subscription scope: $($criticalRoles -join ', ')")
			}
	
		}
		}
		catch {
			#setting has required access to false in case of api failure
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual, "Unable to fetch PIM data.")
		}

		return $controlResult

	}
	# This function evaluates permanent role assignments at resource group level.
	hidden [ControlResult] CheckRGLevelPermanentRoleAssignments([ControlResult] $controlResult)
	{
		try{
		$criticalRoles = $this.ControlSettings.CriticalPIMRoles.ResourceGroup;
		# Check if the scan is run in  CA mode or in SDL mode explicity ran for this control or user is getting into an attestation mode
		# The logic being this control is only scanned in CA mode and if user needs to attest then they would otherwise need to manually set scan source in client as 'CA'
		if(-not([string]::IsNullOrEmpty($this.InvocationContext.BoundParameters['ControlIds'])) -or  -not( [string]::IsNullOrEmpty($this.InvocationContext.BoundParameters['ControlsToAttest'])) -or [AzSKSettings]::GetInstance().GetScanSource() -eq 'CA')
		{
			$whitelistedPermanentRoles = $null
			$message=$this.GetRGLevelPIMRoles();
			if($message -ne 'OK') # if there is some while making request message will contain exception
			{

				$controlResult.AddMessage("Unable to fetch PIM data.")
				$controlResult.AddMessage($message);
				return $controlResult;
			}
			else
			{
			# 'Owner' and 'User Access Administrator' are high privileged roles. These roles should not be give permanent access at resource group level.
				$permanentRoles = $this.RGLevelPermanentAssignments;
				if([Helpers]::CheckMember($this.ControlSettings,"WhitelistedPermanentRoles"))
				{
					$whitelistedPermanentRoles = $this.ControlSettings.whitelistedPermanentRoles
				}				
				if(($permanentRoles | measure-object).Count -gt 0 )
				{
					$criticalPermanentRoles = $permanentRoles | Where-Object{$_.RoleDefinitionName -in $criticalRoles -and ($_.ObjectType -eq 'User' -or $_.ObjectType -eq 'Group')}
					if($null -ne $whitelistedPermanentRoles)
					{
						$criticalPermanentRoles = $criticalPermanentRoles | Where-Object{ $_.DisplayName -notin $whitelistedPermanentRoles.DisplayName}
						
					}
					if(($criticalPermanentRoles| measure-object).Count -gt 0)
					{
						$controlResult.SetStateData("Permanent role assignments present on resource groups",$criticalPermanentRoles)
						$controlResult.AddMessage([VerificationResult]::Failed, "Resource groups contains permanent role assignment for critical roles : $($criticalRoles -join ',')")
						$permanentRolesbyRoleDefinition=$criticalPermanentRoles|Sort-Object -Property RoleDefinitionName | Select-Object SubscriptionId, @{Name="ResourceGroupName"; Expression={$_.Scope.Split("/")[-1]}}, DisplayName, ObjectType, RoleDefinitionName | Format-List | Out-String
						$controlResult.AddMessage($permanentRolesbyRoleDefinition);
						
					}
					else 
					{
						$controlResult.AddMessage([VerificationResult]::Passed, "No permanent assignments found for the following roles at resource group scope: $($criticalRoles -join ', ')")
					}
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Passed, "No permanent assignments found for the following roles at resource group scope: $($criticalRoles -join ', ')")
					
				}		
			
				
			}
		}
		else
		{
			# If full GSS scan run is non CA mode, attestation switch not being passed, the control will read result from compliance state table
			# Since actually control is not evaluated in this code path, we need to put the 'HasRequiredAccess' flag as false, so that this result does not count for compliance
 			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			if([FeatureFlightingManager]::GetFeatureStatus("FetchRGPIMControlStatusFromComplianceState",$($this.SubscriptionContext.SubscriptionId)) )
			{
				#[string] $controlId = $controlItem.ControlID;
				$controlResult.AddMessage("Note: `n By default, this control is not evaluated in manual scan mode as it takes substantial amount of time to scan. The control status in this CSV is based on the previous CA runbook scan for the control. To determine why the control has failed, you can look at the detailed log files in the AzSK storage account in AzSKRG under a container named 'ca-scan-logs' `n If you would like to override this behavior and evaluate the control from PS console, you can specify the control id explicitly in the scan cmdlet (e.g., gss -s <sub_id> -cids 'Azure_Subscription_AuthZ_Dont_Grant_Persistent_Access_RG '")
				$result = $this.GetControlStatusFromComplianceState('Azure_Subscription_AuthZ_Dont_Grant_Persistent_Access_RG');
				# since this control has actually only two states 'Passed' and 'Failed', but in case we are not able to read attestation data we need to tell the reason for the same
				
				switch($result)
				{
					
					"Manual"{
						$controlResult.AddMessage([VerificationResult]::Manual,"")
						$controlResult.AddMessage("Unable to query compliance state results")
					}
                    Default
                    {
                        
                        $controlResult.AddMessage([VerificationResult]::$result,"")
					
                    }
					
				} 
				
			}
		}
	}
	catch{
		#setting has required access to false in case of api failure
		$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
		$controlResult.AddMessage([VerificationResult]::Manual, "Unable to fetch PIM data.")
	}

		return $controlResult

	}
	
	hidden [ControlResult] CheckMandatoryTags([ControlResult] $controlResult)
	{
					#Check if mandatory tags list present
			if([Helpers]::CheckMember($this.ControlSettings,"MandatoryTags") -and ($this.ControlSettings.MandatoryTags | Measure-Object).Count -ne 0)
			{
				$whitelistedResourceGroupsRegex = [System.Collections.ArrayList]::new()
				if ([Helpers]::CheckMember($this.ControlSettings,"WhitelistedResourceGroups") -and ($this.ControlSettings.WhitelistedResourceGroups | Measure-Object).Count -ne 0) 
				{
					$whitelistedResourceGroupsRegex = $this.ControlSettings.WhitelistedResourceGroups						
				}
				$whitelistedResourceGroupsRegex = (('^' + (($whitelistedResourceGroupsRegex |foreach {[regex]::escape($_)}) –join '|') + '$')) -replace '[\\]',''
				$resourceGroups = Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -inotmatch $whitelistedResourceGroupsRegex}

					if(($resourceGroups | Measure-Object).Count -gt 0)
					{
									$rgTagStatus = $true
									$controlResult.AddMessage("`nTotal number of RGs:" + ($resourceGroups | Measure-Object).Count)
									$this.ControlSettings.MandatoryTags | ForEach-Object {
													$tagObject = $_
													
													$controlResult.AddMessage("`nPolicy Requirement: `n`tTag: '$($tagObject.Name)' `n`tScope: '$($tagObject.Scope)' `n`tExpected Values: '$($tagObject.Values)' `n`tExpected Type: '$($tagObject.Type)'")

													#Step1 Validate if tag present on RG                                        
													$rgListwithoutTags = $resourceGroups | Where-Object { [string]::IsNullOrWhiteSpace($_.Tags) -or (-not ($_.Tags.Keys -icontains $tagObject.Name))}
													
													if(($rgListwithoutTags | Measure-Object).Count -gt 0)
													{
																	$rgTagStatus = $false
																	$controlResult.AddMessage("`nTotal number of RGs without Tag: " + ($rgListwithoutTags | Measure-Object).Count, ($rgListwithoutTags | Select-Object ResourceGroupName | ForEach-Object {$_.ResourceGroupName}))
													}
													
													$rgListwithDuplicateTags = $resourceGroups | Where-Object { (-not [string]::IsNullOrWhiteSpace($_.Tags)) -and (($_.Tags.Keys -match "\b$($tagObject.Name)\b") | Measure-Object).Count -gt 1 }
													
													if(($rgListwithDuplicateTags | Measure-Object).Count -gt 0)
													{
																	$rgTagStatus = $false
																	$controlResult.AddMessage("`nTotal number of RGs with duplicate Tag(multiple Tags with same name): " + ($rgListwithDuplicateTags | Measure-Object).Count, ($rgListwithDuplicateTags | Select-Object ResourceGroupName | ForEach-Object {$_.ResourceGroupName}))
													}

													$rgListwithTags = $resourceGroups | Where-Object { (-not [string]::IsNullOrWhiteSpace($_.Tags)) -and (($_.Tags.Keys -match "\b$($tagObject.Name)\b") | Measure-Object).Count -eq 1 }
													
													if(($rgListwithTags| Measure-Object).Count -gt 0)
													{
																	if($tagObject.Values -notcontains "*")
																	{
																					#Validate if expected tag value is present 
																					$rgListwithoutTagValue = $rgListwithTags | Where-Object { $_.Tags[$_.Tags.Keys -match "\b$($tagObject.Name)\b"] -inotin $tagObject.Values} #$rgListwithTags | Where-Object { $_.Tags | Where-Object { $_.GetEnumerator() | Where-Object { $_.Key -eq $tagObject.Name -and $_.Value -notin $tagObject.Values}}}
																					if(($rgListwithoutTagValue | Measure-Object).Count -gt 0)
																					{
																									$rgTagStatus = $false
																									$controlResult.AddMessage("`nTotal number of RGs without expected value : " + ($rgListwithoutTagValue | Measure-Object).Count, ($rgListwithoutTagValue | Select-Object ResourceGroupName | ForEach-Object {$_.ResourceGroupName}))
																					}
																	}

																	#Validate tag value type
																	if($tagObject.ValidateTagValueType -and ($rgListwithTags| Measure-Object).Count -gt 0)
																	{     
																					switch($tagObject.Type)
																					{
																									("Guid") {  
																													$emptyGuid = [Guid]::Empty 
																													$RGListWithoutExpectedTypeValue = $rgListwithTags | Where-Object { (-not [Guid]::TryParse($_.Tags[$_.Tags.Keys -match "\b$($tagObject.Name)\b"], [ref] $emptyGuid))} #$rgListwithTags | Where-Object { $_.Tags | Where-Object { $_.GetEnumerator() | Where-Object {$_.Key -eq $tagObject.Name -and (-not [Guid]::TryParse($_.Value, [ref] $emptyGuid))}}}
																													if(($RGListWithoutExpectedTypeValue | Measure-Object).Count -gt 0)
																													{
																																	$rgTagStatus = $false
																																	$controlResult.AddMessage("`nTotal number of RGs without expected value type: " + ($RGListWithoutExpectedTypeValue | Measure-Object).Count,($RGListWithoutExpectedTypeValue | Select-Object ResourceGroupName | foreach {$_.ResourceGroupName}))
																													}
																									}
																					}
																	}
													}
													$controlResult.AddMessage([Constants]::UnderScoreLineLine)
									}
									
									if(-not $rgTagStatus)
									{
													$controlResult.AddMessage([VerificationResult]::Failed, "Resource group(s) failed to comply with mandatory tags." )
									}
									else
									{
													$controlResult.AddMessage([VerificationResult]::Passed, "Resource group(s) comply with mandatory tags." )
									}                                                              
					}
					else
					{
									$controlResult.AddMessage([VerificationResult]::Passed,"No resource group(s) found" )
					}
			}
			else
			{
							$controlResult.AddMessage([VerificationResult]::Passed,"No mandatory tags required" )
			}

			return $controlResult
	}


	hidden [ControlResult] CheckASCTier ([ControlResult] $controlResult)
	{
		$ascTierContentDetails = $this.SecurityCenterInstance.ASCTier;
		$this.ResourceTier = $this.ASCTierDetails;
		[string[]] $standard = @();
		[string[]] $MisconfiguredASCTier = @(); #This will store information of all the misconfigured ASC pricing tier for individual resource types.

		if(-not [string]::IsNullOrWhiteSpace($ascTierContentDetails))		
		{
			[bool] $bool = $true;
			$ascTier = "Standard"
			if([Helpers]::CheckMember($this.ControlSettings,"SubscriptionCore.ASCTier"))
			{
				$bool = $bool -and ($this.ControlSettings.SubscriptionCore.ASCTier -contains $ascTierContentDetails)
			}
			else
			{
				$bool = $bool -and ($ascTier -eq $ascTierContentDetails)
			}
			if( -not $bool)
			{
				$MisconfiguredASCTier += ("Free pricing tier is configured for the subscription.")
			}
			$standard= $this.ControlSettings.SubscriptionCore.Standard
			$this.ResourceTier.GetEnumerator() | Where-Object {$_.Value -eq "Free"} | ForEach-Object { #this fetches the list of all resources for which free tier is enabled on portal and checks if that resource should have standard tier enforced.
				foreach($std in $standard)
					{
						if($std -eq $_.Key) 
						{
							$bool = $false -and $bool
							$MisconfiguredASCTier += ("Standard pricing tier is not configured for [$($_.Key)].")	
						}
						else{
							$bool = $true -and $bool
						}
					}
			}
			$this.SubscriptionContext.SubscriptionMetadata.Add("MisconfiguredASCTier",$MisconfiguredASCTier); #Adding misconfigured ASC tier in the metadata.
			if($bool)			
			{
				$controlResult.AddMessage([VerificationResult]::Passed, "Expected pricing tier is configured for ASC." )
			}
			else
			{
				$controlResult.SetStateData("Expected pricing tier is not configured for ASC.", $MisconfiguredASCTier);
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Expected pricing tier is not configured for ASC.", $MisconfiguredASCTier));
			}
		}
		return $controlResult
	}

	hidden [ControlResult] CheckCredentialHygiene([ControlResult] $controlResult)
    {
        $AzSKRG = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
        $containerName = [Constants]::RotationMetadataContainerName
        $StorageAccount = Get-AzStorageAccount -ResourceGroupName $AzSKRG -ErrorAction SilentlyContinue | Where-Object {$_.StorageAccountName -like 'azsk*'} -ErrorAction SilentlyContinue
        $keys = $null;
		
		if($StorageAccount){
			$keys = Get-AzStorageAccountKey -ResourceGroupName $AzSKRG -Name $StorageAccount.StorageAccountName -ErrorAction SilentlyContinue
		}
		
		if($keys) #Adequate permissions to read credential metadata
		{
			$context = New-AzStorageContext -StorageAccountName $StorageAccount.StorageAccountName -StorageAccountKey $keys.Value[0]
			$container = Get-AzStorageContainer -Name $containerName -Context $context -ErrorAction Ignore
			
			if($container){
				$credBlobs = $container | Get-AzStorageBlob

				$expiredCount = 0; # Count of credentials near to expiry (< 7d)/have expired
				$aboutToExpireCount = 0; # Count of credentials approaching expiry (7d < expiry < 30d)
				$healthyCount = 0; # Count of credentials far from expiry (> 30d)
				[PSObject] $expiredCredentials = @(); # List of credentials near to expiry (< 7d)/have expired
				[PSObject] $aboutToExpireCredentials = @(); # List of credentials approaching expiry (7d < expiry < 30d)
				[PSObject] $healthyCredentials = @(); # List of credentials far from expiry (> 30d)
				[CredHygieneAlert[]] $credAlertObject = @(); # Array of cred alert objects

				$AzSKTemp = (Join-Path $([Constants]::AzSKAppFolderPath) $([Constants]::RotationMetadataSubPath)); 

				$tempSubPath = Join-Path $AzSKTemp $($this.SubscriptionContext.SubscriptionId)

				if(![string]::isnullorwhitespace($this.SubscriptionContext.SubscriptionId)){
					if(-not (Test-Path $tempSubPath))
					{
						New-Item -ItemType Directory -Path $tempSubPath -ErrorAction Stop | Out-Null
					}	
				}
				else{
					if(-not (Test-Path $AzSKTemp))
					{
						New-Item -ItemType Directory -Path $AzSKTemp -ErrorAction Stop | Out-Null
					}
				}

				$credBlobs | ForEach-Object{
					$file = Join-Path $AzSKTemp -ChildPath $($this.SubscriptionContext.SubscriptionId) | Join-Path -ChildPath $($_.Name)
					
					$blobContent = Get-AzStorageBlobContent -Blob $_.Name -Container $container.Name -Context $context -Destination $file -Force -ErrorAction Ignore    
					$credentialInfo = Get-ChildItem -Path $file -Force | Get-Content | ConvertFrom-Json

					$currentTime = [DateTime]::UtcNow;
					$lastRotatedTime = $credentialInfo.lastUpdatedOn;
					$expiryTime = $lastRotatedTime.AddDays($credentialInfo.rotationInt);

					# Preparing array of cred alert objects to send to LA.	
					$credAlert = [CredHygieneAlert]::new()
					$credAlert.ExpiryDueInDays = ($expiryTime - $currentTime).Days
					if($credAlert.ExpiryDueInDays -le 0){
						$credAlert.IsExpired = $true
						$credAlert.ExpiryDueInDays = 0
					}
					else{
						$credAlert.IsExpired = $false
					}
					
					$credAlert.CredentialName = $credentialInfo.credName
					
					if([Helpers]::CheckMember($credentialInfo,"credGroup")){
						$credAlert.CredentialGroup = $credentialInfo.credGroup
					}
					
					$credAlert.LastUpdatedBy = $credentialInfo.lastUpdatedBy
					$credAlert.SubscriptionId = $this.SubscriptionContext.SubscriptionId
					$credAlert.SubscriptionName = $this.SubscriptionContext.SubscriptionName
					$credAlertObject += $credAlert;
					
					if($expiryTime -le $currentTime.AddDays($this.ControlSettings.SubscriptionCore.credHighTH)){ #Checking for expired/about to expire credentials
						$expiredCount += 1;
						$expiredCredentials += $credentialInfo;
					}
					elseif(($expiryTime -gt $currentTime.AddDays($this.ControlSettings.SubscriptionCore.credHighTH)) -and ($expiryTime -le $currentTime.AddDays($this.ControlSettings.SubscriptionCore.credModerateTH))){ #Checking for credentials nearing expiry.
						$aboutToExpireCount +=1;
						$aboutToExpireCredentials += $credentialInfo;
					}
					else{#Checking for healthy credentials
						$healthyCount +=1;
						$healthyCredentials += $credentialInfo;
					}
				}

				$this.PublishEvent([SVTEvent]::PostCredHygiene, $credAlertObject)

				$controlResult.AddMessage("`nCredentials that have expired or are very close to expiry: $expiredCount `n", $expiredCredentials)
				$controlResult.AddMessage("`nCredentials that are approaching expiry: $aboutToExpireCount `n", $aboutToExpireCredentials)
				$controlResult.AddMessage("`nCredentials that are not near expiry: $healthyCount `n", $healthyCredentials)

				if($expiredCount -gt 0){ # Fail the control if any expired/about to expire credential found
					$controlResult.VerificationResult = [VerificationResult]::Failed;
					$controlResult.AddMessage("`nPlease update them soon using the cmd Update-AzSKTrackedCredential with the 'ResetLastUpdate' switch with other required parameters (Subscription Id, credential name, etc.).`n")
				}
				elseif($aboutToExpireCount -gt 0){ # Verify the control if any credential approaching expiry found
					$controlResult.VerificationResult = [VerificationResult]::Verify
				}
				else{ # No expired/about-to-expire credentials
					$controlResult.VerificationResult = [VerificationResult]::Passed
				}
			}
			else{ # No tracked credentials.
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("There are no AzSK-tracked credentials in the subscription."))
			}
		}	
		else
		{
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual, [MessageData]::new("Insufficient permissions to read credential metadata."))
		}	
		return $controlResult
	}
	

	# Control in json to be added in Org Policy if the Org wants to enforce conditional access policy on PIM activation for critical roles
	hidden [ControlResult] CheckPIMCATag([ControlResult] $controlResult)
	{
		$resourceId = ""
		if([Helpers]::CheckMember($this.SubscriptionExtId,'id'))
		{
			$resourceId = $this.SubscriptionExtId.id;
		}
		$ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
		$accessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
		$authorisationToken = "Bearer " + $accessToken
		$headers = @{"Authorization"=$authorisationToken;"Content-Type"="application/json"}
		try
		{
			if([string]::IsNullOrEmpty($resourceId))
			{
				
				$uri=[Constants]::PIMAPIUri +"?`$filter=type%20eq%20%27subscription%27&`$orderby=displayName"			
				#Get external id for the current subscription
				$response=[WebRequestHelper]::InvokeGetWebRequest($uri, $headers)
				$subId=$this.SubscriptionContext.SubscriptionId;
				$this.SubscriptionExtId = ($response| Where-Object{$_.externalId.split('/') -contains $subId}).id
				$resourceId=$this.SubscriptionExtId;
			
			}
			$roleurl = "https://api.azrbac.mspim.azure.com/api/v2/privilegedAccess/azureResources/resources/" + $resourceId + "/roleDefinitions?`$select=id,displayName,type,templateId,resourceId,externalId,subjectCount,eligibleAssignmentCount,activeAssignmentCount&`$orderby=activeAssignmentCount%20desc"
			$roles = [WebRequestHelper]::InvokeGetWebRequest($roleurl, $headers)
			$roles= $roles | Where-Object{$_.DisplayName -in $this.ControlSettings.CriticalPIMRoles.Subscription}
			$missingCAPolicyOnRoles = @();
			$validRoles = @();
			$invalidRoles = @();
			$nonCompliantPIMCAPolicyTagRoles = @();
			foreach($role in $roles)
			{
				#API call to fetch existing role settings with respect to ACRS Rule
				$url ="https://api.azrbac.mspim.azure.com/api/v2/privilegedAccess/azureResources/roleSettingsV2?`$expand=resource,roleDefinition(`$expand=resource)&`$filter=(resource/id+eq+%27$($resourceId)%27)+and+(roleDefinition/id+eq+%27$($role.id)%27)"
				$rolesettings = [WebRequestHelper]::InvokeGetWebRequest($url, $headers)
				$CAPolicyOnRoles = ($($($rolesettings.lifeCycleManagement | Where-Object {$_.caller -eq 'EndUser' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'AcrsRule'}).setting | ConvertFrom-Json
				
				if($CAPolicyOnRoles.acrsRequired)
				{
					$validRoles +=$role
					if([Helpers]::CheckMember($this.ControlSettings,"CheckPIMCAPolicyTags"))
					{
						if([Helpers]::CheckMember($this.ControlSettings,"PIMCAPolicyTags"))
						{
							if($CAPolicyOnRoles.acrs -notin $this.ControlSettings.PIMCAPolicyTags)
							{
								$nonCompliantPIMCAPolicyTagRoles +=$role;
							}
						}
					}
				}
				else 
				{
						$invalidRoles +=$role
				}

				
			}	
			if([Helpers]::CheckMember($this.ControlSettings,"CheckPIMCAPolicyTags"))
			{
				if($missingCAPolicyOnRoles.Count -gt 0)
				{
					$controlResult.VerificationResult = [VerificationResult]::Failed
					$controlResult.AddMessage("Roles that donot have required CA policy tags $($this.ControlSetting,"PIMCAPolicyTags" -join ',') `n $($missingCAPolicyOnRoles | Format-List) ");
				}
				elseif($invalidRoles.Count -gt 0)
				{
					$controlResult.VerificationResult = [VerificationResult]::Failed
					$controlResult.AddMessage("Role with Acr required turned off `n $($invalidRoles | Format-List | Out-String) ");
					
				}
				else
				{
					$controlResult.VerificationResult = [VerificationResult]::Passed	
				}		
			}
			else {
				if($invalidRoles.Count -gt 0)
				{
					$controlResult.VerificationResult = [VerificationResult]::Failed
					$controlResult.AddMessage("Role with Acr required turned off `n $($invalidRoles | Format-List | Out-String) ");
					
				}
				else
				{
					$controlResult.VerificationResult = [VerificationResult]::Passed	
				}
			}
		}
		catch
		{
			$controlResult.AddMessage($_);
			$controlResult.VerificationResult = [VerificationResult]::Manual
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckPIMCATagRGScope([ControlResult] $controlResult)
	{
		$resourceId =""
		$resourceGroupIDs = @()
		$validRoles = @();
		$missingCAPolicyOnRoles = @();
		$nonCompliantPIMCAPolicyTagRoles = @();

		$ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
		$accessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
		$authorisationToken = "Bearer " + $accessToken
		$headers = @{"Authorization"=$authorisationToken;"Content-Type"="application/json"}
		
		try
		{
			#Fetch details of all resourcegroups in the subscription
			$uri=[Constants]::PIMAPIUri +"?`$filter=(type%20eq%20%27resourcegroup%27)%20and%20contains(tolower(externalId),%20%27{0}%27)&`$orderby=displayName" -f $this.SubscriptionContext.SubscriptionId.ToLower()
			$response=[WebRequestHelper]::InvokeGetWebRequest($uri, $headers)
			$subId=$this.SubscriptionContext.SubscriptionId;
			$extID=$response| Where-Object{$_.externalId.split('/') -contains $subId}
			$resourceGroupIDs=$extID.id;
				
			if(($resourceGroupIDs | Measure-Object).Count -gt 0 )
			{
				foreach($rgID in $resourceGroupIDs)
				{
					#Get applicable roles of RG, which will also provide role ids for role secific api call
					$roleurl = "https://api.azrbac.mspim.azure.com/api/v2/privilegedAccess/azureResources/resources/" + $rgID + "/roleDefinitions?`$select=id,displayName,type,templateId,resourceId,externalId,subjectCount,eligibleAssignmentCount,activeAssignmentCount&`$orderby=activeAssignmentCount%20desc"
					$roles = [WebRequestHelper]::InvokeGetWebRequest($roleurl, $headers)
					$roles= $roles | Where-Object{$_.DisplayName -in $this.ControlSettings.CriticalPIMRoles.ResourceGroup}

					foreach($role in $roles)
					{
						#API call to fetch existing role settings with respect to ACRS Rule
						$url = "https://api.azrbac.mspim.azure.com/api/v2/privilegedAccess/azureResources/roleSettingsV2?`$expand=resource,roleDefinition(`$expand=resource)&`$filter=(resource/id+eq+%27$($rgID)%27)+and+(roleDefinition/id+eq+%27$($role.id)%27)"
						$rolesettings = [WebRequestHelper]::InvokeGetWebRequest($url, $headers)
						$CAPolicyOnRoles = ($($($rolesettings.lifeCycleManagement | Where-Object {$_.caller -eq 'EndUser' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'AcrsRule'}).setting | ConvertFrom-Json
						
						#Create custom object to display only required information in detail logs
						$item = New-Object psobject -Property @{
							RoleId    			= $role.id
							RoleName  			= $role.displayName
							Type     			= $role.type
							ResourceGroupName   = $rolesettings.resource.displayName
							SubjectCount 		= $role.subjectCount
						}

						# If Conditional Access is enabled then check if correct CA policy is applied
						if($CAPolicyOnRoles.acrsRequired)
						{
							$validRoles +=$item
							if([Helpers]::CheckMember($this.ControlSettings,"CheckPIMCAPolicyTags"))
							{
								if([Helpers]::CheckMember($this.ControlSettings,"PIMCAPolicyTags"))
								{
									if($CAPolicyOnRoles.acrs -notin $this.ControlSettings.PIMCAPolicyTags)
									{
										# Invalid CA POlicy applied
										$nonCompliantPIMCAPolicyTagRoles +=$item;
									}
								}
							}
						}
						else 
						{
							#CA policy is not enabled
							$missingCAPolicyOnRoles +=$item
						}
					}	
				}
			}

			if(($nonCompliantPIMCAPolicyTagRoles | Measure-Object).Count -gt 0 )
			{
				$controlResult.VerificationResult = [VerificationResult]::Failed
				$controlResult.AddMessage("Roles that do not have required CA policy tags $($this.ControlSetting,"PIMCAPolicyTags" -join ',') `n $($nonCompliantPIMCAPolicyTagRoles | Format-List) ");
			}
			elseif(($missingCAPolicyOnRoles | Measure-Object).Count -gt 0 )
			{
				$controlResult.VerificationResult = [VerificationResult]::Failed
				$controlResult.AddMessage("Role with Acr required turned off `n $($missingCAPolicyOnRoles | Format-List | Out-String) ");
			}
			else
			{
				$controlResult.VerificationResult = [VerificationResult]::Passed	
			}		
		}
		catch
		{
			$controlResult.AddMessage($_);
			$controlResult.VerificationResult = [VerificationResult]::Manual
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckNonAlternateAccountsinPIMAccess([ControlResult] $controlResult)
    {
		if(-not([string]::IsNullOrEmpty($this.InvocationContext.BoundParameters['ControlIds'])) -or  -not( [string]::IsNullOrEmpty($this.InvocationContext.BoundParameters['ControlsToAttest'])) -or [AzSKSettings]::GetInstance().GetScanSource() -eq 'CA')
		{
		
			$AltAccountRegX = [string]::Empty;
			$message = [string]::Empty;
			$messageSub= [string]::Empty;
			if([FeatureFlightingManager]::GetFeatureStatus("EnableResourceGroupPersistentAccessCheck",$($this.SubscriptionContext.SubscriptionId)))
			{
				$messageSub=$this.GetRGLevelPIMRoles();
			}
			$messageRG=$this.GetPIMRoles();
			$AssignmentsAtSubAndRGLevel = New-Object "System.Collections.Generic.List[TelemetryRBACExtended]"
			$AssignmentsForCriticalRoles =  @();
			if($null -ne $this.PIMAssignmentswithPName)
			{
				#$AssignmentsAtSubAndRGLevel.Add($this.PIMAssignmentswithPName)
				$AssignmentsForCriticalRoles += $this.PIMAssignmentswithPName | Where-Object {$_.RoleDefinitionName -in $this.ControlSettings.CriticalPIMRoles.Subscription}
			}
			if($null -ne $this.PIMRGLevelAssignmentswithPName)
			{
				$AssignmentsForCriticalRoles += $this.PIMRGLevelAssignmentswithPName | Where-Object {$_.RoleDefinitionName -in $this.ControlSettings.CriticalPIMRoles.ResourceGroup}
			}
			
			# get the altenate account pattern from org policy control settings
			if( [Helpers]::CheckMember($this.ControlSettings,"AlernateAccountRegularExpressionForOrg"))
			{
				$AltAccountRegX = $this.ControlSettings.AlernateAccountRegularExpressionForOrg
			}
			else
			{
				# if unable to get the altenate account pattern from policy control settings, let the control be manual 
				$controlResult.AddMessage("Unable to get the alternate account pattern for your org. Please verify manually")
				return $controlResult;
			}
			if(($AssignmentsForCriticalRoles | Measure-Object).Count -gt 0)
				{
										
					$nonAltPIMAccounts = $AssignmentsForCriticalRoles | Where-Object{$_.ObjectType -eq 'User' -and $_.PrincipalName -notmatch $AltAccountRegX}
					if(($nonAltPIMAccounts | Measure-Object).Count -gt 0)
					{
						$nonAltPIMAccountsWithRoles = $AssignmentsForCriticalRoles | Where-Object{$_.DisplayName -in $nonAltPIMAccounts.DisplayName}
						$controlResult.AddMessage([VerificationResult]::Failed, "Non alternate accounts are assigned critical roles")
						$controlResult.AddMessage($($nonAltPIMAccountsWithRoles | Select-Object -Property "PrincipalName", "RoleDefinitionName","Scope","ObjectType" ))
					}
					else
					{
						$controlResult.AddMessage([VerificationResult]::Passed, "No Non alternate accounts are assigned critical roles")
					}
				}
				else
				{
					if($messageSub -ne 'OK' -or $messageRG -ne 'OK' )
					{
						$controlResult.AddMessage("Unable to fetch PIM data, please verify manually.")
						$controlResult.AddMessage($message);
						return $controlResult;
					}
					else
					{
						$controlResult.AddMessage([VerificationResult]::Passed,"No assignments for critical found at subscription and resource group level")
					}
				}
			
		
		}
		else
		{
			# If full GSS scan run is non CA mode, attestation switch not being passed, the control will read result from compliance state table
			# Since actually control is not evaluated in this code path, we need to put the 'HasRequiredAccess' flag as false, so that this result does not count for compliance
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			if([FeatureFlightingManager]::GetFeatureStatus("FetchRGPIMControlStatusFromComplianceState",$($this.SubscriptionContext.SubscriptionId)) )
			{
				#[string] $controlId = $controlItem.ControlID;
				$controlResult.AddMessage("Note: `n By default, this control is not evaluated in manual scan mode as it takes substantial amount of time to scan. The control status in this CSV is based on the previous CA runbook scan for the control. To determine why the control has failed, you can look at the detailed log files in the AzSK storage account in AzSKRG under a container named 'ca-scan-logs' `n If you would like to override this behavior and evaluate the control from PS console, you can specify the control id explicitly in the scan cmdlet (e.g., gss -s <sub_id> -cids 'Azure_Subscription_Use_Only_Alt_Credentials'")
				$result = $this.GetControlStatusFromComplianceState('Azure_Subscription_Use_Only_Alt_Credentials');
				# since this control has actually only two states 'Passed' and 'Failed', but in case we are not able to read attestation data we need to tell the reason for the same
				if(($result | Measure-Object).Count -eq 1)
				{
					switch($result)
					{
						
						"Manual"{
							$controlResult.AddMessage([VerificationResult]::Manual,"")
							$controlResult.AddMessage("Unable to query compliance state results")
						}
						Default
						{
							
							$controlResult.AddMessage([VerificationResult]::$result,"")
						
						}
						
					} 
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Manual,"")
					$controlResult.AddMessage("Unable to query compliance state results")
				}
				
			}
		}
		return $controlResult;
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
		$ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
		$ClassicAccessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
		if($null -ne $ClassicAccessToken)
		{
			$header = "Bearer " + $ClassicAccessToken
			$headers = @{"Authorization"=$header;"Content-Type"="application/json"; "x-ms-version" ="2013-08-01"}
			$uri = [string]::Format("{0}/{1}/certificates",$ResourceAppIdURI,$this.SubscriptionContext.SubscriptionId)
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
		$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()
		$AccessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
		if($null -ne $AccessToken)
		{
			$header = "Bearer " + $AccessToken
			$headers = @{"Authorization"=$header;"Content-Type"="application/json";}

			# Commenting this as it's costly call and expected to happen in Set-ASC/SSS/USS 
			#[SecurityCenterHelper]::RegisterResourceProvider();

			$uri=[system.string]::Format($ResourceAppIdURI+"subscriptions/{0}/providers/microsoft.Security/alerts?api-version=2015-06-01-preview",$this.SubscriptionContext.SubscriptionId)
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
			$ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
			$accessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
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
					$this.SubscriptionExtId = $response| Where-Object{$_.externalId.split('/') -contains $subId}
					$resourceID=$this.SubscriptionExtId.id;
					$this.PIMAssignments=@();
					$this.permanentAssignments=@();
					if($null -ne $response -and $null -ne $resourceID)
					{
						#Get RoleAssignments from PIM API 
						$url=[string]::Format([Constants]::PIMAPIUri +"/{0}/roleAssignments?`$expand=subject,roleDefinition(`$expand=resource)", $resourceID)
						#NextLink handled in the web request
                        $responseContent = [WebRequestHelper]::InvokeWebRequest('Get', $url, $headers, $null, [string]::Empty, @{} )
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
							$item.MemberType = $roleAssignment.memberType;
							if($roleAssignment.memberType -ne 'Inherited')
								{
									if($roleAssignment.assignmentState -eq 'Eligible')
									{
										#If roleAssignment is non permanent, even the active PIM assignments would appear in this list
										$item.IsPIMEnabled=$true;
										$this.PIMAssignments.Add($item);
										$tempRBExtendObject = [TelemetryRBACExtended]::new($item, $roleAssignment.subject.principalName)
										$this.PIMAssignmentswithPName.Add($tempRBExtendObject);
									}
									else
									{
										#If roleAssignment is permanent the linkedEligbibleRoleAssignmentId would be null when the assignment is permanently Active
										if([string]::IsNullOrEmpty($roleAssignment.linkedEligibleRoleAssignmentId))
										{
											$item.IsPIMEnabled=$false;
											$this.permanentAssignments.Add($item);
											$tempRBExtendObject = [TelemetryRBACExtended]::new($item, $roleAssignment.subject.principalName)
											$this.PIMAssignmentswithPName.Add($tempRBExtendObject);
										}

									}
								}
						}
						
					}
					$message='OK';
				}
				catch
				{
					$message="Please make sure your subscription has onboarded Privileged Identity Management (PIM).";
				}
			}
		}

		return($message);
	}

	hidden [string] GetRGLevelPIMRoles()
	{
		$message='';
		if($null -eq $this.RGLevelPIMAssignments -and $null -eq $this.RGLevelPermanentAssignments)
		{
			$ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
			$accessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
			if($null -ne $AccessToken)
			{
				$authorisationToken = "Bearer " + $accessToken
				$headers = @{"Authorization"=$authorisationToken;"Content-Type"="application/json"}
				$uri=[Constants]::PIMAPIUri +"?`$filter=(type%20eq%20%27resourcegroup%27)%20and%20contains(tolower(externalId),%20%27{0}%27)&`$orderby=displayName" -f $this.SubscriptionContext.SubscriptionId.ToLower()
				try
				{
					#Get external id for the current subscription
					$response=[WebRequestHelper]::InvokeGetWebRequest($uri, $headers)
					
					$subId=$this.SubscriptionContext.SubscriptionId;
					$extID=$response| Where-Object{$_.externalId.split('/') -contains $subId}
					$resourceIDs=$extID.id;
					$this.RGLevelPIMAssignments=@();
					$this.RGLevelPermanentAssignments=@();
					if($null -ne $response -and $null -ne $resourceIDs)
					{
						$loopCount = 0
						foreach($resourceID in $resourceIDs)
						{
							#This check is to avoid too many API calls in a minute
							$loopCount++;
							if($loopCount -eq 400)
							{
								sleep 60;
								$loopCount = 0
							}
							#Get RoleAssignments from PIM API 
							$url=[string]::Format([Constants]::PIMAPIUri +"/{0}/roleAssignments?`$expand=subject,roleDefinition(`$expand=resource)", $resourceID)
							#NextLink handled in the web request
                            $responseContent = [WebRequestHelper]::InvokeWebRequest('Get', $url, $headers, $null, [string]::Empty, @{} )
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
								$item.MemberType = $roleAssignment.memberType;
								if($roleAssignment.memberType -ne 'Inherited')
								{
									if($roleAssignment.assignmentState -eq "Eligible")
									{
										#If roleAssignment is non permanent and not active
										$item.IsPIMEnabled=$true;
										$this.RGLevelPIMAssignments.Add($item);
										$tempRBExtendObject = [TelemetryRBACExtended]::new($item, $roleAssignment.subject.principalName)
										$this.PIMRGLevelAssignmentswithPName.Add($tempRBExtendObject);
										
									}
									else
									{
										#If roleAssignment is permanent the linkedEligbibleRoleAssignmentId would be null when the assignment is permanently Active
										if([string]::IsNullOrEmpty($roleAssignment.linkedEligibleRoleAssignmentId))
										{
											$item.IsPIMEnabled=$false;
											$this.RGLevelpermanentAssignments.Add($item);
											$tempRBExtendObject = [TelemetryRBACExtended]::new($item, $roleAssignment.subject.principalName)
											$this.PIMRGLevelAssignmentswithPName.Add($tempRBExtendObject);
										}
										
										
									}
								}
							}
						}
					}
					$message='OK';
				}
				catch
				{
					$message="Please make sure your subscription has onboarded Privileged Identity Management (PIM).";
				}
			}
		}

		return($message);
	}

	hidden [void] PublishRBACTelemetryData()
	{
		$AccessRoles= $this.RoleAssignments | Where-Object{(($_.scope).split('/') | Measure-Object).Count -gt 5} ; # restrict the Get-AzRoleAssignment only for resource level
		# Other assignments will be obtained from PIM API
		$PIMRoles=$this.PIMAssignments;
		$RBACAssignment = New-Object "System.Collections.Generic.List[TelemetryRBAC]"
		if($AccessRoles -ne $null)
		{
			
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
							$RBACTelemetry.IsPIMEnabled= $matchingObject.IsPIMEnabled;	# take the PIMEligibility from PIM assignments
							
						}
					}
					$RBACAssignment.Add($RBACTelemetry);
				
				
				}
		}
		
			if($null -ne $PIMRoles){
				$RBACAssignment.AddRange($PIMRoles);
			}
			if($null -ne $this.permanentAssignments)
			{
				$RBACAssignment.AddRange($this.permanentAssignments);
			}
			if($null -ne $this.RGLevelPermanentAssignments)
			{
				$RBACAssignment.AddRange($this.RGLevelPermanentAssignments);
			}
			if($null -ne $this.RGLevelPIMAssignments)
			{
				$RBACAssignment.AddRange($this.RGLevelPIMAssignments);
			}
			
			
				
			$this.CustomObject=New-Object CustomData;
			$this.CustomObject.Value=$RBACAssignment;
			$this.CustomObject.Name="RBACTelemetry";
			
			
	
	}

	hidden [string] GetControlStatusFromComplianceState([string]$controlId)
	{
		$verificationResult = "Manual"
		#As fetching ComplianceStateData from ComplianceState table is disabled by default, when run in non CA mode without passing control Id explicitly, result will always be Manual
		if(($this.ComplianceStateData | Measure-Object).Count -gt 0)
		{
			
			$controlComplianceData = ($this.ComplianceStateData | Where-Object{$_.ControlID -eq $controlId})
			if($null -ne $controlComplianceData)
			{
				
				$verificationResult = $controlComplianceData.VerificationResult
				
			}
			else 
			{
				$verificationResult = "Manual"
			}
		}
		return $verificationResult
	}
	hidden [ControlResult] CheckSecurityPolicy([ControlResult] $controlResult)
	{
		if ($this.SecurityCenterInstance)
		{
			$this.SubscriptionContext.SubscriptionMetadata.Add("MissingOptionalASCPolicies",$this.MisConfiguredOptionalASCPolicies);
			$this.SubscriptionContext.SubscriptionMetadata.Add("MissingMandatorySecurityPolicies",$this.MisConfiguredSecurityPolicySettings);

			if(($this.MisConfiguredSecurityPolicySettings | Measure-Object).Count -ne 0)
			{
				$controlResult.EnableFixControl = $true;
				$controlResult.SetStateData("Security Center misconfigured policies", $this.MisConfiguredSecurityPolicySettings);
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Following security center policies are not correctly configured. Please update the policies in order to comply.", $this.MisConfiguredSecurityPolicySettings));
			}
			
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("All security center policies are correctly configured."));
			}
		}
		return $controlResult
	}

	hidden [ControlResult] CheckAutoProvisioningForSecurity([ControlResult] $controlResult)
	{
		if ($this.SecurityCenterInstance)
		{
			$this.SubscriptionContext.SubscriptionMetadata.Add("MissingAutoProvisioningPolicies",$this.MisConfiguredAutoProvisioningSettings);

			if(-not [string]::IsNullOrWhiteSpace($this.MisConfiguredAutoProvisioningSettings))
		      {
				 $controlResult.EnableFixControl = $true;
			     $controlResult.SetStateData("Misconfigured AutoProvisioning Policy", $this.MisConfiguredAutoProvisioningSettings);
			     $controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("AutoProvisioning setting is disabled.", $this.MisConfiguredAutoProvisioningSettings));
			  }
			
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("AutoProvisioning is enabled."));
			}
		}
		return $controlResult
	}

	hidden [ControlResult] CheckSecurityContactDetails([ControlResult] $controlResult)
	{
		if ($this.SecurityCenterInstance)
		{
			$this.SubscriptionContext.SubscriptionMetadata.Add("MissingSecurityContactDetails",$this.MisConfiguredSecurityContactDetails);

			if(-not [string]::IsNullOrWhiteSpace($this.MisConfiguredSecurityContactDetails))
		      {
				 $controlResult.EnableFixControl = $true;
			     $controlResult.SetStateData("Misconfigured Security Contact Details", $this.MisConfiguredSecurityContactDetails);
			     $controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Security contacts are not configured.", $this.MisConfiguredSecurityContactDetails));
		      }
			
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("Security contacts are correctly configured."));
			}
		}
		return $controlResult
	}
}

