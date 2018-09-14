Set-StrictMode -Version Latest 
class Databricks: SVTBase
{       
    hidden [PSObject] $ResourceObject;
	hidden [string] $ManagedResourceGroupName;
	hidden [string] $WorkSpaceLoction;
	hidden [string] $WorkSpaceBaseUrl = "https://{0}.azuredatabricks.net/api/2.0/";
	hidden [string] $PersonalAccessToken =""; 
	hidden [bool] $HasAdminAccess = $false;

    Databricks([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
                 Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
	 
		$this.GetResourceObject();
    }

    Databricks([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
	   
		$this.GetResourceObject();
    }

	 hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject)
		{
		
            $this.ResourceObject = Get-AzureRmResource -Name $this.ResourceContext.ResourceName  `
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
	    
        $vnetPeerings = Get-AzureRmVirtualNetworkPeering -VirtualNetworkName "workers-vnet" -ResourceGroupName $this.ManagedResourceGroupName
        if($null -ne $vnetPeerings  -and ($vnetPeerings|Measure-Object).count -gt 0)
        {
			$controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Verify below peering found on VNet", $vnetPeerings));
			$controlResult.SetStateData("Peering found on VNet", $vnetPeerings);

        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No VNet peering found on VNet", $vnetPeerings));
        }

        return $controlResult;
	}

	 hidden [ControlResult] CheckSecretScope([ControlResult] $controlResult)
    {
	    if(-not [string]::IsNullOrEmpty($this.PersonalAccessToken) -and $this.IsUserAdmin())
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
	    if(-not [string]::IsNullOrEmpty($this.PersonalAccessToken) -and $this.IsUserAdmin())
		{
			 $SecretScopes	= $this.InvokeRestAPICall("GET","secrets/scopes/list","")
			 if($null -ne  $SecretScopes  -and ( $SecretScopes|Measure-Object).count -gt 0)
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
	    if(-not [string]::IsNullOrEmpty($this.PersonalAccessToken) -and $this.IsUserAdmin())
		{
			$KeyVaultScopeMapping = @()
			$KeyVaultWithMultipleReference = @() 
			$SecretScopes	= $this.InvokeRestAPICall("GET","secrets/scopes/list","")
			if($null -ne  $SecretScopes  -and ( $SecretScopes|Measure-Object).count -gt 0)
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
	    if(-not [string]::IsNullOrEmpty($this.PersonalAccessToken))
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
						$currentObject.expiry_in_days = "-1"
					}
					else{
					 
					    $currentObject.comment = $_.comment
						$currentObject.token_id = $_.token_id
						$currentObject.expiry_in_days = (New-TimeSpan -Seconds (($_.expiry_time - $_.creation_time)/1000)).Days
					}
					$AccessTokensList += $currentObject

				}
				$PATwithInfiniteValidity += $AccessTokensList | Where-Object {$_.expiry_in_days -eq "-1" }
				$PATwithInfiniteValidity += $AccessTokensList | Where-Object {$_.expiry_in_days -ne "-1"} | Where-Object {$_.expiry_in_days -gt 180} 
			
				$PATwithFiniteValidity = $AccessTokensList | Where-Object {$_.expiry_in_days -ne "-1" -and $_.expiry_in_days -le 180}

				if($null -ne $PATwithInfiniteValidity -and ($PATwithInfiniteValidity| Measure-Object).Count -gt 0)
				{
					$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Following personal access token has validity more than 180 days:", $PATwithInfiniteValidity));
					$controlResult.SetStateData("Following personal access tokens have validity more than 180 days:", $PATwithInfiniteValidity);

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
	   if(-not [string]::IsNullOrEmpty($this.PersonalAccessToken) -and $this.IsUserAdmin())
	   {    
	        $controlResult.VerificationResult = [VerificationResult]::Verify;
		    $accessList = [RoleAssignmentHelper]::GetAzSKRoleAssignmentByScope($this.GetResourceId(), $false, $true);
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
				$controlResult.AddMessage("Note: Users that have been explicitly added in the 'admins' group in the workspace are considered 'active' admins");
				$controlResult.AddMessage([MessageData]::new("", $potentialAdminUsers));
			}
			if(($activeAdminUsers|Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage("`r`nValidate that the following identities have active admin access to resource - [$($this.ResourceContext.ResourceName)]");
				$controlResult.AddMessage("Note: Users that have been explicitly added in the 'admins' group in the workspace are considered 'active' admins");
				$controlResult.AddMessage([MessageData]::new("", $activeAdminUsers));
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
	   if(-not [string]::IsNullOrEmpty($this.PersonalAccessToken) -and $this.IsUserAdmin())
	   {    
	        $controlResult.VerificationResult = [VerificationResult]::Verify;
			# Get All Active Users
			$guestAdminUsers =@()
			$requestBody = "group_name=admins"
			$activeAdmins = $this.InvokeRestAPICall("GET","groups/list-members",$requestBody);
			if($null -ne $activeAdmins -and ($activeAdmins.members | Measure-Object).Count -gt 0)
			{
				$activeAdmins.members | ForEach-Object{
				 if($_.user_name.Split('@')[1] -ne 'microsoft.com')
				 {
					$guestAdminUsers +=$_
				 }
				}
			}
			if($null -ne $guestAdminUsers -and ($guestAdminUsers | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Following guest accounts have admin access on workspace:", $guestAdminUsers));
			}
			else{
				$controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Verify guest accounts should not have admin access on workspace."));
			}
			
	   }
	   else
	   {
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual, "Not able to fetch admin details. This has to be manually verified.");
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
		   # No need to break execution
		 } 
		return  $ResponseObject 
	}

	hidden [string] ReadAccessToken()
	{ 
	     $scanSource = [RemoteReportHelper]::GetScanSource();
         if($scanSource -eq [ScanSource]::SpotCheck)
		 { 
		   $input = Read-Host "Enter PAT(personal access token) for '$($this.ResourceContext.ResourceName)' workspace"
           $input = $input.Trim()
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
		$this.PersonalAccessToken = $this.ReadAccessToken()
		#$this.HasAdminAccess = $this.IsUserAdmin()
	}

	hidden [bool] IsUserAdmin()
	{
	  try
	  {
		  $currentContext = [Helpers]::GetCurrentRMContext()
		  $userId = $currentContext.Account.Id;
		  $requestBody = "user_name="+$userId
		  $parentGroups = $this.InvokeRestAPICall("GET","groups/list-parents",$requestBody)
		  if($parentGroups.group_names.Contains("admins"))
		  {
			  return $true;
		  }else
		  {
			 return $false;
		  }
	  }
	  catch{
		return $false;
	  }
	  
	}

}
