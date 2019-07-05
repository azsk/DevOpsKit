Set-StrictMode -Version Latest 
class Databricks: AzSVTBase
{       
    hidden [PSObject] $ResourceObject;
	hidden [string] $ManagedResourceGroupName;
	hidden [string] $WorkSpaceLoction;
	hidden [string] $WorkSpaceBaseUrl = "https://{0}.azuredatabricks.net/api/2.0/";
	hidden [string] $PersonalAccessToken =""; 
	hidden [bool] $HasAdminAccess = $false;
	hidden [bool] $IsTokenRead = $false;

    Databricks([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
	   
		$this.GetResourceObject();
    }

	 hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject)
		{
		
            $this.ResourceObject = Get-AzResource -Name $this.ResourceContext.ResourceName  `
			-ResourceType $this.ResourceContext.ResourceType `
			-ResourceGroupName $this.ResourceContext.ResourceGroupName

            if(-not $this.ResourceObject)
            {
				throw ([SuppressedException]::new(("Resource '$($this.ResourceContext.ResourceName)' not found under Resource Group '$($this.ResourceContext.ResourceGroupName)'"), [SuppressedExceptionType]::InvalidOperation))
            }
			else
			{
			   $this.InitializeRequiredVariables();
			}
        }
        return $this.ResourceObject;
    }

	
    hidden [ControlResult] CheckVnetPeering([ControlResult] $controlResult)
    {
				$managedRG = Get-AzResourceGroup -Name $this.ManagedResourceGroupName -ErrorAction SilentlyContinue
				if($managedRG){
					$vnetPeerings = Get-AzVirtualNetworkPeering -VirtualNetworkName "workers-vnet" -ResourceGroupName $this.ManagedResourceGroupName
					if($null -ne $vnetPeerings  -and ($vnetPeerings|Measure-Object).count -gt 0)
					{
							$controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Verify below peering found on VNet", $vnetPeerings));
							$controlResult.SetStateData("Peering found on VNet", $vnetPeerings);
	
					}
					else
					{
							$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No VNet peering found on VNet", $vnetPeerings));
					}

				}else{
					$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
					$controlResult.AddMessage([VerificationResult]::Manual, [MessageData]::new("Managed Resource Group $($this.ManagedResourceGroupName) was not found."));
				}
     

        return $controlResult;
	}

	 hidden [ControlResult] CheckSecretScope([ControlResult] $controlResult)
    {
	    if($this.IsTokenAvailable() -and $this.IsUserAdmin())
		{
			 $SecretScopes	= $this.InvokeRestAPICall("GET","secrets/scopes/list","")
			 if($null -ne  $SecretScopes  -and ( $SecretScopes|Measure-Object).count -gt 0)
			 {
		       $controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Verify secrets and keys must not be as plain text in notebook"));
             }
			 else
			 {
			   $controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("No secret scope found in your workspace."));
             }
		}else
		{
		   $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
		   $controlResult.AddMessage([VerificationResult]::Manual, "Not able to fetch secret scope details. This has to be manually verified.");
		}
	   

        return $controlResult;
	}

	 hidden [ControlResult] CheckSecretScopeBackend([ControlResult] $controlResult)
    {
	    if($this.IsTokenAvailable() -and $this.IsUserAdmin())
		{
			 $SecretScopes	= $this.InvokeRestAPICall("GET","secrets/scopes/list","")
			 if($null -ne  $SecretScopes  -and (( $SecretScopes|Measure-Object).count -gt 0) -and [Helpers]::CheckMember($SecretScopes,"scopes"))
			 {
				  $DatabricksBackedSecret = $SecretScopes.scopes | where {$_.backend_type -ne "AZURE_KEYVAULT"}
				  if($null -ne $DatabricksBackedSecret -and ( $SecretScopes|Measure-Object).count -gt 0)
				  {
					$controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Following Databricks backed secret scopes found:", $DatabricksBackedSecret));
					$controlResult.SetStateData("Following Databricks backed secret scope found:", $DatabricksBackedSecret);
				  }
				  else
				  {
					$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("All secret scopes in the workspace are Key Vault backed."));
				  }
             }
			 else
			 {
			   $controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("No secret scope found in your workspace."));
             }
		}else
		{
		   $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
		   $controlResult.AddMessage([VerificationResult]::Manual, "Not able to fetch secret scope details. This has to be manually verified.");
		}
	   

        return $controlResult;
	}

	hidden [ControlResult] CheckKeyVaultReference([ControlResult] $controlResult)
    {
	    if($this.IsTokenAvailable() -and $this.IsUserAdmin())
		{
			$KeyVaultScopeMapping = @()
			$KeyVaultWithMultipleReference = @() 
			$SecretScopes	= $this.InvokeRestAPICall("GET","secrets/scopes/list","")
			if($null -ne  $SecretScopes  -and (( $SecretScopes|Measure-Object).count -gt 0) -and [Helpers]::CheckMember($SecretScopes,"scopes"))
			{
			  $KeyVaultBackedSecretScope = $SecretScopes.scopes | where {$_.backend_type -eq "AZURE_KEYVAULT"}
			  if($null -ne $KeyVaultBackedSecretScope -and ( $KeyVaultBackedSecretScope | Measure-Object).count -gt 0)
			  {
				$KeyVaultBackedSecretScope | ForEach-Object {
					$KeyVaultScopeMappingObject = "" | Select-Object "ScopeName", "KeyVaultResourceId"
					$KeyVaultScopeMappingObject.ScopeName = $_.name
					$KeyVaultScopeMappingObject.KeyVaultResourceId = $_.keyvault_metadata.resource_id
					$KeyVaultScopeMapping += $KeyVaultScopeMappingObject
				}
				# Check if same keyvault is referenced by multiple secret scopes
				$KeyVaultWithManyReference = $KeyVaultScopeMapping | Group-object -Property KeyVaultResourceId | Where-Object {$_.Count -gt 1} 
				if($null -ne $KeyVaultWithManyReference -and ($KeyVaultWithManyReference | Measure-Object).Count -gt 0)
				{
					$KeyVaultWithManyReference | ForEach-Object { $KeyVaultWithMultipleReference += $_.Name }
					$controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Following KeyVault(s) are referenced by multiple secret scope:", $KeyVaultWithMultipleReference));
					$controlResult.SetStateData("Following KeyVault(s) are referenced by multiple secret scope:", $KeyVaultWithMultipleReference);

				}else
				{
					$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("All KeyVault backed secret scope are linked with independent KeyVault.", $KeyVaultWithMultipleReference));
				}
			  }
			  else
			  {
				$controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("No KeyVault backed secret scope found in your workspace."));
			  }
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("No secret scope is found in your workspace."));
			}

		}else
		{
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
		    $controlResult.AddMessage([VerificationResult]::Manual, "Not able to fetch secret scope details. This has to be manually verified.");
		}
	   

        return $controlResult;
	}

	hidden [ControlResult] CheckAccessTokenExpiry([ControlResult] $controlResult)
    {   
	    if($this.IsTokenAvailable())
		{
			 $AccessTokens = $this.InvokeRestAPICall("GET","token/list","")
			if($null -ne $AccessTokens -and ($AccessTokens.token_infos| Measure-Object).Count -gt 0)
			{   
			    $PATwithInfiniteValidity =@()
				$AccessTokensList =@()
				$AccessTokens.token_infos | ForEach-Object {
					$currentObject = "" | Select-Object "comment","token_id","expiry_in_days"
					if($_.expiry_time -eq "-1")
					{
						$currentObject.comment = $_.comment
						$currentObject.token_id = $_.token_id
						$currentObject.expiry_in_days = "Never"
					}
					else{
					 
					    $currentObject.comment = $_.comment
						$currentObject.token_id = $_.token_id
						$currentObject.expiry_in_days = (New-TimeSpan -Seconds (($_.expiry_time - $_.creation_time)/1000)).Days
					}
					$AccessTokensList += $currentObject

				}
				$PATwithInfiniteValidity += $AccessTokensList | Where-Object {$_.expiry_in_days -eq "Never" }
				$PATwithInfiniteValidity += $AccessTokensList | Where-Object {$_.expiry_in_days -ne "Never"} | Where-Object {$_.expiry_in_days -gt 180} 
			
				$PATwithFiniteValidity = $AccessTokensList | Where-Object {$_.expiry_in_days -ne "Never" -and $_.expiry_in_days -le 180}

				if($null -ne $PATwithInfiniteValidity -and ($PATwithInfiniteValidity| Measure-Object).Count -gt 0)
				{
					$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Following personal access tokens have validity more than 180 days:", $PATwithInfiniteValidity));
					#$controlResult.SetStateData("Following personal access tokens have validity more than 180 days:", $PATwithInfiniteValidity);

				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("Following personal access tokens have validity less than 180 days:", $PATwithFiniteValidity));
				}

			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Manual, [MessageData]::new("No personal access token found in your workspace."));
			}	

		}else
		{
		   $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
		   $controlResult.AddMessage([VerificationResult]::Manual, "Not able to fetch PAT (personal access token) details. This has to be manually verified.");
		} 
	   
        return $controlResult;
	}

	hidden [ControlResult] CheckAdminAccess([ControlResult] $controlResult)
	{   
	   if($this.IsTokenAvailable() -and $this.IsUserAdmin())
	   {    
	        $controlResult.VerificationResult = [VerificationResult]::Verify;
		    $accessList = [RoleAssignmentHelper]::GetAzSKRoleAssignmentByScope($this.ResourceId, $false, $true);
			$adminAccessList = $accessList | Where-Object { $_.RoleDefinitionName -eq 'Owner' -or $_.RoleDefinitionName -eq 'Contributor'}
			# Add check for User Type
			$potentialAdminUsers = @()
			$activeAdminUsers =@()
			$adminAccessList | ForEach-Object {
				if([Helpers]::CheckMember($_, "SignInName"))
				{
				   $potentialAdminUsers += $_.SignInName
				}
			}	
			# Get All Active Users
			$requestBody = "group_name=admins"
			$activeAdmins = $this.InvokeRestAPICall("GET","groups/list-members",$requestBody);
			if($null -ne $activeAdmins -and ($activeAdmins | Measure-Object).Count -gt 0)
			{
				$activeAdminUsers += $activeAdmins.members
			}
			if(($potentialAdminUsers|Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage("`r`nValidate that the following identities have potential admin access to resource - [$($this.ResourceContext.ResourceName)]");
				$controlResult.AddMessage("Note: Users that have 'Owner' or 'Contributor' role on the Databricks workspace resource are considered 'potential' admins");
				$controlResult.AddMessage([MessageData]::new("", $potentialAdminUsers));
			}
			if(($activeAdminUsers|Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage("`r`nValidate that the following identities have active admin access to resource - [$($this.ResourceContext.ResourceName)]");
				$controlResult.AddMessage("Note: Users that have been explicitly added in the 'admins' group in the workspace are considered 'active' admins");
				$controlResult.AddMessage([MessageData]::new("", $activeAdminUsers));
				$controlResult.SetStateData("Following identities have active admin access to resource:", $activeAdminUsers);
			}
	   }
	   else
	   {
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual, "Not able to fetch admin details. This has to be manually verified.");
	   }
		
		return $controlResult;
	}

	hidden [ControlResult] CheckGuestAdminAccess([ControlResult] $controlResult)
	{   
	   if($this.IsTokenAvailable() -and $this.IsUserAdmin())
	   {    
			# Get All Active Users
			$guestAdminUsers =@()
			$requestBody = "group_name=admins"
			$activeAdmins = $this.InvokeRestAPICall("GET","groups/list-members",$requestBody);
			if($null -ne $activeAdmins -and ($activeAdmins.members | Measure-Object).Count -gt 0)
			{ 
			    if(($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings,"Databricks.Tenant_Domain"))
				{    
				     $tenantDomain = $this.ControlSettings.Databricks.Tenant_Domain
					 $activeAdmins.members | ForEach-Object{
					 if($_.user_name.Split('@')[1] -ne $tenantDomain)
					 {
						$guestAdminUsers +=$_
					 }
					}
				}
				
			}
			if($null -ne $guestAdminUsers -and ($guestAdminUsers | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Following guest accounts have admin access on workspace:", $guestAdminUsers));
				$controlResult.SetStateData("Following guest accounts have admin access on workspace:", $guestAdminUsers);
			}
			else{
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No guest account with admin access on workspace found."));
			}
			
	   }
	   else
	   {
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual, "Not able to fetch admin details. This has to be manually verified.");
	   }
		
		return $controlResult;
	}

	hidden [ControlResult] CheckWorkspaceAccessEnabled([ControlResult] $controlResult)
	{   
	   $premiumSku = $this.CheckPremiumSku()
	   if($premiumSku)
	   {    
		$controlResult.AddMessage([VerificationResult]::Verify, "Please verify that Workspace Access Control is enabled for resource '$($this.ResourceContext.ResourceName)'");
	   }
	   else
	   {
		$controlResult.AddMessage([VerificationResult]::Failed, "Workspace Access Control is Disabled for resource '$($this.ResourceContext.ResourceName)'");	
	   }
		
		return $controlResult;
	}

	hidden [ControlResult] CheckJobAccessEnabled([ControlResult] $controlResult)
	{   
	   $premiumSku = $this.CheckPremiumSku()
	   if($premiumSku)
	   {    
		$controlResult.AddMessage([VerificationResult]::Verify, "Please verify that Job Access Control is enabled for resource '$($this.ResourceContext.ResourceName)'");
	   }
	   else
	   {
		$controlResult.AddMessage([VerificationResult]::Failed, "Job Access Control is Disabled for resource '$($this.ResourceContext.ResourceName)'");	
	   }
		
		return $controlResult;
	}

	hidden [ControlResult] CheckClusterAccessEnabled([ControlResult] $controlResult)
	{   
	   $premiumSku = $this.CheckPremiumSku()
	   if($premiumSku)
	   {    
		$controlResult.AddMessage([VerificationResult]::Verify, "Please verify that Cluster Access Control is enabled for resource '$($this.ResourceContext.ResourceName)'");
	   }
	   else
	   {
		$controlResult.AddMessage([VerificationResult]::Failed, "Cluster Access Control is Disabled for resource '$($this.ResourceContext.ResourceName)'");	
	   }
		
		return $controlResult;
	}

	hidden [PSObject] InvokeRestAPICall([string] $method, [string] $operation , [string] $queryString)
	{   
	     $ResponseObject = $null;
		 try
		 {
			 $uri = $this.WorkSpaceBaseUrl + $operation 
			 if(-not [string]::IsNullOrWhiteSpace($queryString))
			 {
			  $uri =  $uri +'?'+ $queryString
			 }
			 $ResponseObject = Invoke-RestMethod -Method $method -Uri $uri `
							   -Headers @{"Authorization" = "Bearer "+$this.PersonalAccessToken} `
							   -ContentType 'application/json' -UseBasicParsing
		 }
		 catch
		 {
			# Todo : Check for suppressed exception
			$this.PublishCustomMessage("Could not evaluate control due to Databricks API call failure. Token may be invalid.", [MessageType]::Error);
			$ExceptionMsg = $_.Exception.Tostring()
			throw ([SuppressedException]::new(("Could not evaluate control due to Databricks API call failure. Token may be invalid." + $ExceptionMsg) , [SuppressedExceptionType]::Generic))	    
		 } 
		return  $ResponseObject 
	}

	hidden [string] ReadAccessToken()
	{ 
	     $scanSource = [RemoteReportHelper]::GetScanSource();
         if($scanSource -eq [ScanSource]::SpotCheck)
		 { 
		   $input = ""
		   $input = Read-Host "Enter PAT (personal access token) for '$($this.ResourceContext.ResourceName)' Databricks workspace"
		   if($null -ne $input)
		   {
			 $input = $input.Trim()
		   }  
		   return $input;
		 }
		 else
		 { 
			return $null;
		 }
	   
	}

	hidden InitializeRequiredVariables()
	{
		$this.WorkSpaceLoction = $this.ResourceObject.Location
		$count = $this.ResourceObject.Properties.managedResourceGroupId.Split("/").Count
		$this.ManagedResourceGroupName = $this.ResourceObject.Properties.managedResourceGroupId.Split("/")[$count-1]
		$this.WorkSpaceBaseUrl=[system.string]::Format($this.WorkSpaceBaseUrl,$this.WorkSpaceLoction)
		#$this.HasAdminAccess = $this.IsUserAdmin()
	}

	hidden [bool] IsUserAdmin()
	{
	  try
	  {
	      #Users must be admin to inoke this API call
		   $uri = $this.WorkSpaceBaseUrl + "groups/list" 		
		   $ResponseObject = Invoke-RestMethod -Method "GET" -Uri $uri `
							   -Headers @{"Authorization" = "Bearer "+$this.PersonalAccessToken} `
							   -ContentType 'application/json' -UseBasicParsing
		  if($null -ne $ResponseObject -and ([Helpers]::CheckMember($ResponseObject,"group_names")))
		  {
		    return $true;
		  }else
		  {
		    return  $false;
		  }
	  }
	  catch{
		 # If exception occurs user is not admin
		 $this.PublishCustomMessage("Could not evaluate control due to Databricks API call failure. Token may be invalid.", [MessageType]::Error); 
		return $false;
	  }
	  
	}

	hidden [bool] IsTokenAvailable()
	{
	   $status = $false;
	   if(!$this.IsTokenRead)
	   {
	     $this.IsTokenRead = $true;
	     $this.PersonalAccessToken = $this.ReadAccessToken()
	   }

	   if(-not [string]::IsNullOrEmpty($this.PersonalAccessToken))
	   {
	      $status = $true;
	   }

	   return $status; 
	}

	hidden [bool] CheckPremiumSku()
	{
	   $IsPremium = $false;
	   $skuName = $this.ResourceObject.Sku.Name
	   if($skuName -ne "standard")
	   {
		   $IsPremium = $true
	   }
	   return $IsPremium; 
	}

}
