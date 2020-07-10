using namespace Microsoft.Azure.Commands.KeyVault.Models
Set-StrictMode -Version Latest 
class KeyVault: AzSVTBase
{       
    hidden [PSKeyVaultIdentityItem] $ResourceObject;
    hidden [PSObject[]] $AllEnabledKeys = $null;
    hidden [PSObject[]] $AllEnabledSecrets = $null;
	hidden [boolean] $HasFetchKeysPermissions=$false;
	hidden [boolean] $HasFetchSecretsPermissions=$true;
	hidden [PSObject[]] $AllApplicationsList = $null;
	hidden [PSObject[]] $AADApplicationsList = $null;
	hidden [boolean] $ErrorWhileFetchingApplicationDetails = $false;

    KeyVault([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
		$this.GetResourceObject();
		$this.CheckCurrentContextPermissionsOnVaultObjects();
    }

    hidden [PSKeyVaultIdentityItem] GetResourceObject()
    {
        if (-not $this.ResourceObject) 
		{
            $this.ResourceObject = Get-AzKeyVault -VaultName $this.ResourceContext.ResourceName `
                                            -ResourceGroupName $this.ResourceContext.ResourceGroupName
            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }
	hidden [void] CheckCurrentContextPermissionsOnVaultObjects()
	{

		$currentContext=[ContextHelper]::GetCurrentRMContext();
		$CurrentContextId=$currentContext.Account.Id;
		$CurrentContextObjectId=$null
		try{
				if($currentContext.Account.Type -eq 'User')
				{
					$CurrentContextObjectId=Get-AzADUser -UserPrincipalName $CurrentContextId|Select-Object -Property Id
				}
				elseif($currentContext.Account.Type -eq 'ServicePrincipal')
				{
					$CurrentContextObjectId=Get-AzADServicePrincipal -ServicePrincipalName $CurrentContextId|Select-Object -Property Id
				}
				$accessPolicies = $this.ResourceObject.AccessPolicies
				$currentContextAccess=$accessPolicies|Where-Object{$_.ObjectId -eq $CurrentContextObjectId.Id }
				if($null -ne $currentContextAccess)
				{
					if(('List' -in $currentContextAccess.PermissionsToKeys) -and ('Get' -in $currentContextAccess.PermissionsToKeys))
					{
						$this.HasFetchKeysPermissions=$true
					}
					if(('List' -in $currentContextAccess.PermissionsToSecrets) -and ('Get' -in $currentContextAccess.PermissionsToSecrets))
					{
						$this.HasFetchSecretsPermissions=$true
					}
				}
			}catch
			{
				$this.HasFetchKeysPermissions=$false;
				$this.HasFetchSecretsPermissions=$false;
			}
	}

    hidden [ControlResult] CheckAdvancedAccessPolicies([ControlResult] $controlResult)
    {
        $accessPolicies = @{};
        $accessPolicies.Add("Enable access to Azure Virtual Machines for deployment", $this.ResourceObject.EnabledForDeployment);
        $accessPolicies.Add("Enable access to Azure Resource Manager for template deployment", $this.ResourceObject.EnabledForTemplateDeployment);
        $accessPolicies.Add("Enable access to Azure Disk Encryption for volume encryption", $this.ResourceObject.EnabledForDiskEncryption);
        
		$controlResult.SetStateData("Key Vault advanced access policies", $accessPolicies);

        if($this.ResourceObject.EnabledForDeployment -and $this.ResourceObject.EnabledForDiskEncryption -and $this.ResourceObject.EnabledForTemplateDeployment)
        {          
            $controlResult.AddMessage([VerificationResult]::Failed,
                                      [MessageData]::new("All Advanced Access Policies are enabled - ["+ $this.ResourceContext.ResourceName +"]"  , 
                                                         $accessPolicies));
        }
        elseif($this.ResourceObject.EnabledForDeployment -or $this.ResourceObject.EnabledForDiskEncryption -or $this.ResourceObject.EnabledForTemplateDeployment)
        {
            $controlResult.AddMessage([VerificationResult]::Verify,
                                     [MessageData]::new("Validate Advanced Access Policies - ["+ $this.ResourceContext.ResourceName +"]" , 
                                                         $accessPolicies));
        }
        else
        {       
            $controlResult.AddMessage([VerificationResult]::Passed, 
                                      [MessageData]::new("All Advanced Access Policies are disabled - ["+ $this.ResourceContext.ResourceName +"]", 
                                                         $accessPolicies));
        }  
        return $controlResult;
    }

    hidden [ControlResult] CheckAccessPolicies([ControlResult] $controlResult)
    {
            $accessPolicies = $this.ResourceObject.AccessPolicies
 			$controlResult.VerificationResult = [VerificationResult]::Verify; 
			$controlResult.SetStateData("Access policies and their assigned permissions to Key/Secret/Certificate", $accessPolicies);
			$controlResult.AddMessage([MessageData]::new("Validate access policies and their assigned permissions to Key/Secret/Certificate - ["+ $this.ResourceContext.ResourceName +"]" , 
                                                         $accessPolicies));
        return $controlResult;
    }

	hidden [PSObject[]] FetchAllEnabledKeysWithVersions([ControlResult] $controlResult)
	{
			if($this.HasFetchKeysPermissions -eq $true)
			{
				if( $null -eq $this.AllEnabledKeys)
				{
					try
					{
						$keysResult = @();
						$keysResult += Get-AzKeyVaultKey -VaultName $this.ResourceContext.ResourceName -ErrorAction Stop | 
										Where-Object { $_.Enabled -eq $true };
						
						$this.AllEnabledKeys = @();
						if($keysResult.Count -gt 0) 
						{
							$keysResult | ForEach-Object {
								Get-AzKeyVaultKey -VaultName $this.ResourceContext.ResourceName -Name $_.Name -IncludeVersions |
								Where-Object { $_.Enabled -eq $true } | 
                                Select-Object -First $this.ControlSettings.KeyVault.MaxRecommendedVersions |
								ForEach-Object {
                                    $this.AllEnabledKeys += Get-AzKeyVaultKey -VaultName $this.ResourceContext.ResourceName -Name $_.Name -Version $_.Version ;
								}
							}
						}
					}
					catch
					{
						# null indicates exception
						$this.AllEnabledKeys = $null;

						if ($_.Exception.GetType().FullName -eq "Microsoft.Azure.KeyVault.Models.KeyVaultErrorException")
						{
							$controlResult.AddMessage([MessageData]::new("Access denied: Read access is required on Key Vault Keys."));
						}
						else
						{
							throw $_
						}
					}
				}
			}
			else
			{
				$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
				$controlResult.AddMessage([MessageData]::new("Control can not be validated due to insufficient access permission on keys"));

			}
			
		return $this.AllEnabledKeys;
	}

	hidden [PSObject[]] FetchAllEnabledSecretsWithVersions([ControlResult] $controlResult)
	{

		if($this.HasFetchSecretsPermissions -eq $true)
		{
			if($null -eq $this.AllEnabledSecrets)
			{
				try
				{
					$secretsResult = @();
					$secretsResult += Get-AzKeyVaultSecret -VaultName $this.ResourceContext.ResourceName -ErrorAction Stop | 
									Where-Object { $_.Enabled -eq $true };

					$this.AllEnabledSecrets = @();
					if($secretsResult.Count -gt 0) 
					{
						$secretsResult | ForEach-Object {
							Get-AzKeyVaultSecret -VaultName $this.ResourceContext.ResourceName -Name $_.Name -IncludeVersions |
							Where-Object { $_.Enabled -eq $true } | 
                            Select-Object -First $this.ControlSettings.KeyVault.MaxRecommendedVersions |
							ForEach-Object {
								$this.AllEnabledSecrets += Get-AzKeyVaultSecret -VaultName $this.ResourceContext.ResourceName -Name $_.Name -Version $_.Version ;
							}
						}
					}
				}
				catch
				{
					# null indicates exception
					$this.AllEnabledSecrets = $null;

					if ($_.Exception.GetType().FullName -eq "Microsoft.Azure.KeyVault.Models.KeyVaultErrorException")
					{
						$controlResult.AddMessage([MessageData]::new("Access denied: Read access is required on Key Vault Secrets."));
					}
					else
					{
						throw $_
					}
				}
			}
		}
		else
		{
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([MessageData]::new("Control can not be validated due to insufficient access permission on secrets"));

		}
		return $this.AllEnabledSecrets;
	}

    hidden [ControlResult] CheckKeyHSMProtected([ControlResult] $controlResult)
    {

		$enabledKeys = $this.FetchAllEnabledKeysWithVersions($controlResult);
		if($null -ne $enabledKeys)
		{
			if($enabledKeys.Count -ne 0)
			{
				$nonHsmKeys = @();
				$nonHsmKeys += $enabledKeys | Where-Object { $_.Attributes.KeyType -ne $this.ControlSettings.KeyVault.KeyType };
				if($nonHsmKeys.Count -eq 0)
				{ 
					$controlResult.AddMessage( [VerificationResult]::Passed,
						[MessageData]::new("All Keys, including previous versions, are protected by HSM for Key Vault - ["+ $this.ResourceContext.ResourceName +"]"));   
				}
				else 
				{
					$nonHsmKeysDetails = $nonHsmKeys | Select-Object Name, Version -ExpandProperty Attributes;
					$controlResult.SetStateData("Keys not protected by HSM", $nonHsmKeysDetails);
					$controlResult.AddMessage([VerificationResult]::Failed,
						[MessageData]::new("Following Keys, including previous versions, are not protected by HSM."  , 
								($nonHsmKeysDetails )));
				}
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed,
					[MessageData]::new("No Keys (enabled) found in - ["+ $this.ResourceContext.ResourceName +"]"));
			}
		}

		return $controlResult;
    }
	
    hidden [ControlResult] CheckKeyMinimumOperations([ControlResult] $controlResult)
    {
		$enabledKeys = $this.FetchAllEnabledKeysWithVersions($controlResult);
		if($null -ne $enabledKeys)
		{
			if($enabledKeys.Count -ne 0)
			{
				$keyOperations = $enabledKeys | Select-Object Name, Version, @{Label="Key Operations"; Expression={[system.string]::Join(", ",$_.Key.KeyOps)}} 
				$controlResult.SetStateData("Key Vault key operations", $keyOperations);
				$controlResult.AddMessage([VerificationResult]::Verify,
											[MessageData]::new("Verify the operations permitted using Key on - ["+ $this.ResourceContext.ResourceName +"]",
											($keyOperations )) );   
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed,
					[MessageData]::new("No Keys (enabled) found in - ["+ $this.ResourceContext.ResourceName +"]"));
			}
		}

		return $controlResult;
    }

    hidden [ControlResult] CheckAppAuthenticationCertificate([ControlResult] $controlResult)
    {
        try{
              $outputList = @();
              if([FeatureFlightingManager]::GetFeatureStatus("EnableKeyVaultApplicationsFix",$($this.SubscriptionContext.SubscriptionId)) -eq $true)
              {
                  $this.GetApplicationsInAccessPolicy()
                  if($this.ErrorWhileFetchingApplicationDetails)
                  {
                    # When there is exception to read  application details, mark control as Manual 
                    $controlResult.AddMessage([VerificationResult]::Manual,
                                        [MessageData]::new("Unable to fetch application details due to insufficient privileges."));
                    $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
                    return $controlResult
                    }
                    $appList = $this.AADApplicationsList
              }
              else
              {
                  $appList = $this.GetAzureRmKeyVaultApplications()
              }
              
              $appList |
                ForEach-Object {
                    $credentials = Get-AzADAppCredential -ApplicationId $_.ApplicationId
                    $compliance =  if (($credentials| Where-Object { $_.Type -eq $this.ControlSettings.KeyVault.ADAppCredentialTypePwd } | Measure-Object).Count -eq 0 ) { "Yes" } else { "No" } ;
                    $output = New-Object System.Object
                    $output | Add-Member -type NoteProperty -name AzureADAppName -Value $_.DisplayName
                    $output | Add-Member -type NoteProperty -name ApplicationId -Value $_.ApplicationId
                    $output | Add-Member -type NoteProperty -name CertificateCredentialCount -Value ($credentials | Where-Object { $_.Type -eq $this.ControlSettings.KeyVault.ADAppCredentialTypeCrt } | Measure-Object ).Count
                    $output | Add-Member -type NoteProperty -name PasswordCredentialCount -Value ($credentials | Where-Object { $_.Type -eq $this.ControlSettings.KeyVault.ADAppCredentialTypePwd } | Measure-Object).Count
                    $output | Add-Member -type NoteProperty -name Compliance -Value $compliance
                    $outputList += $output;
                }
         
                if(($outputList| Measure-Object).Count -gt 0)
                {
                    $controlResult.AddMessage([MessageData]::new("Compliance details of Azure Active Directory applications:",
                                                                  $outputList));
          
                    if (($outputList | Where-Object { ($_.Compliance -eq "No") } | Measure-Object ).Count -gt 0)
                    {
                        $controlResult.SetStateData("Compliance details of Azure Active Directory applications:", $outputList);
                        $controlResult.AddMessage([VerificationResult]::Failed ,
                                                  [MessageData]::new("Remove the password credentials from Azure AD Applications which are non-compliant.") );
                    }
                    else
                    {
                        $controlResult.VerificationResult = [VerificationResult]::Passed
                    }
                }
                else
                {
                    $controlResult.AddMessage([VerificationResult]::Passed ,
                                                  [MessageData]::new("No Azure AD Applications have access to Key Vault.") );
                }
        }
        catch
        {
             if ($_.Exception.GetType().FullName -eq "Microsoft.Azure.KeyVault.Models.KeyVaultErrorException")
             {
                $controlResult.AddMessage([MessageData]::new("Access denied: Read access is required on Key Vault Keys."));
             }
             else
             {
                 throw $_
             }    
        }
        return $controlResult;
    }

   
	hidden [ControlResult] CheckAppsSharingKeyVault([ControlResult] $controlResult)
	{		
		if([FeatureFlightingManager]::GetFeatureStatus("EnableKeyVaultApplicationsFix",$($this.SubscriptionContext.SubscriptionId)) -eq $true)
		{
			$this.GetApplicationsInAccessPolicy()
			if($this.ErrorWhileFetchingApplicationDetails)
			{
				# When there is exception to read  application details, mark control as Manual 
				$controlResult.AddMessage([VerificationResult]::Manual,
										[MessageData]::new("Unable to fetch application details due to insufficient privileges."));
			    $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
				return $controlResult
			}
			$appList = $this.AllApplicationsList
			$controlResult.SetStateData("Key Vault sharing app list", ($appList| Select-Object -Property ApplicationId, DisplayName, Id, ObjectType))
		}
		else
		{
			$appList = $this.GetAzureRmKeyVaultApplications()
			$controlResult.SetStateData("Key Vault sharing app list", $appList); 
		}		

		if( ($appList | Measure-Object ).Count -gt 1)
		{
			$controlResult.AddMessage([VerificationResult]::Verify,
										[MessageData]::new("Validate that applications requires access to Key Vault. Total:" + ($appList | Measure-Object ).Count , 
															$appList)); 
		}
		elseif( ($appList | Measure-Object ).Count -eq 1)
        {
           $controlResult.AddMessage([VerificationResult]::Passed,
                                     "Only 1 application has access to Key Vault.", $appList); 
        } 
		else
        {
           $controlResult.AddMessage([VerificationResult]::Passed,
                                     "No applications have access to Key Vault."); 
        } 
      
		return $controlResult;
    }

	hidden [void] ProcessKeySecretExpiryDate([PSObject[]] $enabledResources, [ControlResult] $controlResult, [string] $resourceType, [bool] $isAccessDenied, [int] $rotationDurationDays)
	{
		if($enabledResources.Count -ne 0)
		{
			$utcNow = [DateTime]::UtcNow;
			$utcNow30 = $utcNow.AddDays(30);

			$withoutExpiry = @();
			$withoutExpiry += $enabledResources | Where-Object { $null -eq $_.Attributes.Expires };
			if($withoutExpiry.Count -gt 0)
			{
				# result = Failed
				$withoutExpiryDetails = $withoutExpiry | Select-Object -Property Name, Version -ExpandProperty Attributes;
				$controlResult.SetStateData("Following $resourceType, including previous versions, does not have expiry date.", 
				($withoutExpiryDetails));
				$this.SetVerificationResultForExpiryDate($controlResult, [VerificationResult]::Failed, $isAccessDenied)
				$controlResult.AddMessage([MessageData]::new("Following $resourceType, including previous versions, does not have expiry date.", 
														($withoutExpiryDetails) ));
			}

			$longActiveResources = @(); # VerificationResult = Failed
			$needToDisableResources = @(); # VerificationResult = Failed
			$needToRotateResources = @(); # VerificationResult = Verify

			$enabledResources | ForEach-Object {
				$expiryDate = $null

				if($null -ne $_.Attributes.Expires)
				{
					$expiryDate = [DateTime] $_.Attributes.Expires
				}

				#check if expiry is future or null
				if(($null -eq $expiryDate) -or ($utcNow30 -le $expiryDate))
				{
					$createdDate = [DateTime] $_.Attributes.Created

					# check if resource is created/active for more than 180 days ago
					if(($utcNow - $createdDate).TotalDays -ge $rotationDurationDays)
					{
						$longActiveResources += $_;
						$this.SetVerificationResultForExpiryDate($controlResult, [VerificationResult]::Failed, $isAccessDenied);
					}
					else
					{
						$this.SetVerificationResultForExpiryDate($controlResult, [VerificationResult]::Passed, $isAccessDenied);
					}
				}
				# resource already expired but still enabled
				elseif($expiryDate -lt $utcNow)
				{
					$needToDisableResources += $_;
					$this.SetVerificationResultForExpiryDate($controlResult, [VerificationResult]::Failed, $isAccessDenied);
				}
				# resource is about to expire within next 30 days
				elseif(($utcNow -le $expiryDate) -and ($expiryDate -le $utcNow30))
				{
					$needToRotateResources += $_;
					$this.SetVerificationResultForExpiryDate($controlResult, [VerificationResult]::Verify, $isAccessDenied);
				}
			};

			# Display summary messages
			if ($longActiveResources.Count -gt 0)
			{
				$longActiveResourcesDetails = $longActiveResources | Select-Object -Property Name, Version -ExpandProperty Attributes;
				$controlResult.SetStateData("Following $resourceType, including previous versions, are more than $rotationDurationDays days old.", 
				($longActiveResourcesDetails ) );
				$controlResult.AddMessage([MessageData]::new("Following $resourceType, including previous versions, are more than $rotationDurationDays days old.", 
											($longActiveResourcesDetails ) ));
			}

			if ($needToDisableResources.Count -gt 0)
			{
				$needToDisableResourcesDetails = $needToDisableResources | Select-Object -Property Name, Version -ExpandProperty Attributes;
				$controlResult.SetStateData("Following $resourceType, including previous versions, are expired but 'Enabled'.", 
				($needToDisableResourcesDetails ) );
				$controlResult.AddMessage([MessageData]::new("Following $resourceType, including previous versions, are expired but 'Enabled'.", 
											($needToDisableResourcesDetails ) ));
			}

			if ($needToRotateResources.Count -gt 0)
			{
				$needToRotateResourcesDetails = $needToRotateResources | Select-Object -Property Name, Version -ExpandProperty Attributes;
				$controlResult.SetStateData("Following $resourceType, including previous versions, are about to expire within next 30 days. Please rotate the $resourceType.", 
				($needToRotateResourcesDetails ) );
				$controlResult.AddMessage([MessageData]::new("Following $resourceType, including previous versions, are about to expire within next 30 days. Please rotate the $resourceType.", 
											($needToRotateResourcesDetails ) ));
			}
		}
		else
		{
			$this.SetVerificationResultForExpiryDate($controlResult, [VerificationResult]::Passed, $isAccessDenied);
			$controlResult.AddMessage([MessageData]::new("No $resourceType (enabled) found in - ["+ $this.ResourceContext.ResourceName +"]"));
		}
	}

	hidden [void] SetVerificationResultForExpiryDate([ControlResult] $controlResult, [VerificationResult] $newResult, [bool] $isAccessDenied)
	{
		if($isAccessDenied)
		{
			$controlResult.VerificationResult = [VerificationResult]::Manual;
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			return;
		}

		$stateMachine = @(
			[VerificationResult]::Manual,
			[VerificationResult]::Passed,
			[VerificationResult]::Verify,
			[VerificationResult]::Failed
		);

		$existingIndex = [array]::indexof($stateMachine, $controlResult.VerificationResult);
		$newIndex = [array]::indexof($stateMachine, $newResult);
		if($existingIndex -le $newIndex)
		{
			$controlResult.VerificationResult = $newResult;
		}
	}

	hidden [ControlResult] CheckKeyExpirationDate([ControlResult] $controlResult)
	{
		$isKeysCompliant = $True
		$isAccessDenied = $False

		if($this.HasFetchKeysPermissions -eq $true -and $this.HasFetchSecretsPermissions -eq $true)
		{
			$enabledKeys = $this.FetchAllEnabledKeysWithVersions($controlResult);
			if($null -ne $enabledKeys)
			{
				$this.ProcessKeySecretExpiryDate($enabledKeys, $controlResult, "Keys", $isAccessDenied, $this.ControlSettings.KeyVault.KeyRotationDuration_Days);
			}
			else
			{
				$isAccessDenied = $True
			}

			$enabledSecrets = $this.FetchAllEnabledSecretsWithVersions($controlResult);
			if($null -ne $enabledSecrets)
			{
				$this.ProcessKeySecretExpiryDate($enabledSecrets, $controlResult, "Secrets", $isAccessDenied, $this.ControlSettings.KeyVault.SecretRotationDuration_Days);
			}
			else
			{
				$isAccessDenied = $True
			}
		}
		else
		{
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage("Control can not be validated due to insufficient access permission on KeyVault keys or secrets")
			$this.SetVerificationResultForExpiryDate($controlResult, [VerificationResult]::Manual, $isAccessDenied);
		}

		return $controlResult;
   }

   hidden [PSObject] GetAzureRmKeyVaultApplications()  
     {
        $applicationList = @();
        $this.ResourceObject.AccessPolicies  | 
        ForEach-Object { 
            $svcPrincipal= Get-AzADServicePrincipal -ObjectId $_.ObjectId
            if($svcPrincipal){
                $application = Get-AzADApplication -ApplicationId $svcPrincipal.ApplicationId
                if($application){
                    $applicationList += $application
                }
            }
        }
        return $applicationList;
}
    hidden [void] GetApplicationsInAccessPolicy()  
     {
		try{
			#Fetch Application details only once if not fetched previously
			if($null -eq $this.AllApplicationsList -or $null -eq  $this.AADApplicationsList)
			{
				#list of all applications including AAD applicatins, enterprise applications 
				$this.AllApplicationsList = @()
				$this.AADApplicationsList = @()
				$this.ResourceObject.AccessPolicies  | 
        		ForEach-Object { 
            		$svcPrincipal= Get-AzADServicePrincipal -ObjectId $_.ObjectId
					if($svcPrincipal)
					{
                		$application = Get-AzADApplication -ApplicationId $svcPrincipal.ApplicationId
                		if($application){
							$this.AADApplicationsList += $application
						}
						$this.AllApplicationsList += $svcPrincipal
            		}
				}				        
			}			
		}
		catch
		{
			#Unable to fetch details about service principals
			#this is possible when scanning the control with  powershell CICD task(VSO). If SPN used in CICD task does not have appropriate permissions, control was resulting into Error
			#Added catch block to avoid control going to Error in such case.
			$this.ErrorWhileFetchingApplicationDetails = $true
		}		
	 }
	 
	hidden [ControlResult] CheckKeyVaultSoftDelete([ControlResult] $controlResult)
	{
		$isSoftDeleteEnable=$this.ResourceObject.EnableSoftDelete;
		if($isSoftDeleteEnable -eq $true){
		    $controlResult.AddMessage([VerificationResult]::Passed,
										[MessageData]::new("Soft delete is enabled for this Key Vault")); 
			}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Failed,
										[MessageData]::new("Soft delete is disabled for this Key Vault")); 
		}

		return $controlResult;
		
	}

	hidden [PSObject[]] CheckExcessKeyVersions([ControlResult] $controlResult)
	{
		$allExcessVersionKeys = @();

		if($this.HasFetchKeysPermissions -eq $true)
		{
				try
				{
					$keysResult = @();
					$keysResult += Get-AzKeyVaultKey -VaultName $this.ResourceContext.ResourceName -ErrorAction Stop | 
									Where-Object { $_.Enabled -eq $true };

					if($keysResult.Count -gt 0) 
					{
						$keysResult | ForEach-Object {
							$count = 0
							$currentKey = $_
							Get-AzKeyVaultKey -VaultName $this.ResourceContext.ResourceName -Name $_.Name -IncludeVersions |
							Where-Object { $_.Enabled -eq $true } | 
							ForEach-Object {
								if ($count -eq $this.ControlSettings.KeyVault.MaxRecommendedVersions) 
								{
									$allExcessVersionKeys += $currentKey
									break
								}
								$count++
							}
						}
					}
				}
				catch
				{
					if ($_.Exception.GetType().FullName -eq "Microsoft.Azure.KeyVault.Models.KeyVaultErrorException")
					{
						$controlResult.AddMessage([VerificationResult]::Manual,
							[MessageData]::new("Access denied: Read access is required on Key Vault Keys to validate the number of keys."));
					}
					else
					{
						throw $_
					}
				}
		}
		else
		{
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual,
				[MessageData]::new("Number of keys can not be validated due to insufficient access permission on keys"));
		}

		return $allExcessVersionKeys;
	}

	hidden [PSObject[]] CheckExcessSecretVersions([ControlResult] $controlResult)
	{
		$allExcessVersionSecrets = @();

		if($this.HasFetchSecretsPermissions -eq $true)
		{
				try
				{
					$secretsResult = @();
					$secretsResult += Get-AzKeyVaultSecret -VaultName $this.ResourceContext.ResourceName -ErrorAction Stop | 
									Where-Object { $_.Enabled -eq $true };

					if($secretsResult.Count -gt 0) 
					{
						$secretsResult | ForEach-Object {
							$count = 0
							$currentSecret = $_
							Get-AzKeyVaultSecret -VaultName $this.ResourceContext.ResourceName -Name $_.Name -IncludeVersions |
							Where-Object { $_.Enabled -eq $true } | 
							ForEach-Object {
								if ($count -eq $this.ControlSettings.KeyVault.MaxRecommendedVersions) 
								{
									$allExcessVersionSecrets += $currentSecret
									break
								}
								$count++
							}
						}
					}
				}
				catch
				{
					if ($_.Exception.GetType().FullName -eq "Microsoft.Azure.KeyVault.Models.KeyVaultErrorException")
					{
						$controlResult.AddMessage([VerificationResult]::Manual,
							[MessageData]::new("Access denied: Read access is required on Key Vault Secrets to validate the number of secrets."));
					}
					else
					{
						throw $_
					}
				}
		}
		else
		{
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual,
				[MessageData]::new("Number of secrets can not be validated due to insufficient access permission on secrets"));
		}

		return $allExcessVersionSecrets;
	}

	hidden [ControlResult] CheckExcessVersions([ControlResult] $controlResult)
	{
		if($this.HasFetchSecretsPermissions -eq $true -or $this.HasFetchKeysPermissions -eq $true)
		{
			$excessKeys = $this.CheckExcessKeyVersions($controlResult);
			$excessSecrets = $this.CheckExcessSecretVersions($controlResult);
			$excessVersionResources = @();
	
			if ($excessKeys.Count -ne 0 -or $excessSecrets.Count -ne 0) 
			{
				if ($excessKeys.Count -ne 0) 
				{
					$excessKeysDetails = $excessKeys | Select-Object Name, Version, Enabled, Created, Updated, RecoveryLevel;
					$excessVersionResources += $excessKeysDetails
					$controlResult.AddMessage([VerificationResult]::Failed,
						[MessageData]::new("Following Keys have more than "+ $this.ControlSettings.KeyVault.MaxRecommendedVersions +" enabled versions."  , 
								($excessKeysDetails )));	
				}
				if ($excessSecrets.Count -ne 0) 
				{
					$excessSecretsDetails = $excessSecrets | Select-Object Name, Version, Enabled, Created, Updated, RecoveryLevel;
					$excessVersionResources += $excessSecretsDetails
					$controlResult.AddMessage([VerificationResult]::Failed,
						[MessageData]::new("Following Secrets have more than "+ $this.ControlSettings.KeyVault.MaxRecommendedVersions +" enabled versions."  , 
								($excessSecretsDetails )));	
				}	
	
				if($excessVersionResources.Count -gt 0)
				{
					$excessVersionResourcesDetails = $excessVersionResources | Select-Object -Property Name, Version, Enabled, Created, Updated, RecoveryLevel
					$controlResult.SetStateData("Following keys and secrets have more than "+ $this.ControlSettings.KeyVault.MaxRecommendedVersions +" enabled versions.", 
						($excessVersionResourcesDetails));
				}
	
			}
			else 
			{
				try 
				{
					$keysResult = @();
					$keysResult += Get-AzKeyVaultKey -VaultName $this.ResourceContext.ResourceName -ErrorAction Stop | 
									Where-Object { $_.Enabled -eq $true };
					
					$secretsResult = @();
					$secretsResult += Get-AzKeyVaultSecret -VaultName $this.ResourceContext.ResourceName -ErrorAction Stop | 
									Where-Object { $_.Enabled -eq $true };
				
					if ($keysResult.Count -eq 0 -and $secretsResult.Count -eq 0) 
					{
						$controlResult.AddMessage( [VerificationResult]::Passed,
						[MessageData]::new("No Keys and Secrets are enabled for Key Vault - ["+ $this.ResourceContext.ResourceName +"]"));   
					}
					else 
					{
						if ($excessKeys.Count -eq 0 -and $excessSecrets.Count -eq 0)
						{
							$controlResult.AddMessage( [VerificationResult]::Passed,
							[MessageData]::new("All Keys and Secrets have at the most "+ $this.ControlSettings.KeyVault.MaxRecommendedVersions +" versions enabled for Key Vault - ["+ $this.ResourceContext.ResourceName +"]"));   
						}		
					}	
				}
				catch 
				{
					if ($_.Exception.GetType().FullName -eq "Microsoft.Azure.KeyVault.Models.KeyVaultErrorException")
					{
						$controlResult.AddMessage([VerificationResult]::Manual,
							[MessageData]::new("Access denied: Read access is required on Key Vault Secrets and Keys to validate the number of secrets and keys."));
					}
					else
					{
						throw $_
					}
					
				}
			}	
		}
		else
		{
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual,
				[MessageData]::new("Control can not be validated due to insufficient access permission on keys and secrets"));
		}

		return $controlResult
	}
}


