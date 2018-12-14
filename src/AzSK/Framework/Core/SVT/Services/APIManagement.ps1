Set-StrictMode -Version Latest 
class APIManagement: SVTBase
{   

	hidden [PSObject] $APIMContext = $null;
	hidden [PSObject] $APIMInstance = $null;
	hidden [PSObject] $APIMAPIs = $null;
	hidden [PSObject] $APIMProducts = $null;

	hidden [PSObject] $ResourceObject;

    APIManagement([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
		if($this.GetResourceObject())
		{
			$this.APIMContext = New-AzureRmApiManagementContext -ResourceGroupName $this.ResourceContext.ResourceGroupName -ServiceName $this.ResourceContext.ResourceName
			$this.APIMInstance = Get-AzureRmApiManagement -ResourceGroupName $this.ResourceContext.ResourceGroupName -Name $this.ResourceContext.ResourceName
			$this.APIMAPIs = Get-AzureRmApiManagementApi -Context $this.APIMContext
			$this.APIMProducts = Get-AzureRmApiManagementProduct -Context $this.APIMContext
		}
	}

	APIManagement([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
		if($this.GetResourceObject())
		{
			$this.APIMContext = New-AzureRmApiManagementContext -ResourceGroupName $this.ResourceContext.ResourceGroupName -ServiceName $this.ResourceContext.ResourceName
			$this.APIMInstance = Get-AzureRmApiManagement -ResourceGroupName $this.ResourceContext.ResourceGroupName -Name $this.ResourceContext.ResourceName
			$this.APIMAPIs = Get-AzureRmApiManagementApi -Context $this.APIMContext
			$this.APIMProducts = Get-AzureRmApiManagementProduct -Context $this.APIMContext
		}
	}

	 hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzureRmResource -ResourceName $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName
            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }

	hidden [ControlResult] CheckAPIMMetricAlert([ControlResult] $controlResult)
    {
		$this.CheckMetricAlertConfiguration($this.ControlSettings.MetricAlert.APIManagement, $controlResult, "");
		return $controlResult;
    }
    hidden [ControlResult] CheckAPIMURLScheme([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMContext)
		{
			$noncompliantAPIs = $this.APIMAPIs | where-object{$_.Protocols.count -gt 1 -or $_.Protocols[0] -ne 'https' }
			if(($noncompliantAPIs|Measure-Object).Count -gt 0)
			{
			    $controlResult.AddMessage([VerificationResult]::Failed, "Below API(s) are configured to use non-secure HTTP access to the backend via API Management.", $noncompliantAPIs)
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Passed,"")
			}
		}
        
		return $controlResult;
    }

    hidden [ControlResult] CheckSecretNamedValues([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMContext)
		{
			$allNamedValues = @()
			$allNamedValues += Get-AzureRmApiManagementProperty -Context $this.APIMContext 
			if($allNamedValues.count -eq 0)
			{
			    $controlResult.AddMessage([VerificationResult]::Passed, "Named Values are not added.")
			    
			}
			else
			{
			    $nonsecretNamedValues = $allNamedValues | where-object {$_.Secret -eq $false}
			    if(($nonsecretNamedValues|Measure-Object).Count -gt 0)
			    {
			        $controlResult.AddMessage([VerificationResult]::Verify, "Below Named Values are not marked as secret values. Please mark it as secret if it contains critical data.", $nonsecretNamedValues)
			    }
			    else
			    {
			        $controlResult.AddMessage([VerificationResult]::Passed, "")
			    }
			}
		}
		return $controlResult;
    }
    
	hidden [ControlResult] CheckRequiresSubscription([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMContext)
		{
			$Product = $this.APIMProducts | Where-Object { $_.State -eq 'Published' }
			
			if(($null -ne $Product) -and ($Product.SubscriptionRequired -contains $false))
			{
				$Product =  $Product | Where-Object { $_.SubscriptionRequired -eq $false}
				$controlResult.AddMessage([VerificationResult]::Failed, "'Requires Subscription' option is turned OFF for below Products in '$($this.ResourceContext.ResourceName)' API Management instance.", $Product ) 
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Passed,"")
			}
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckRequiresApproval([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMContext)
		{
			$Product = $this.APIMProducts | Where-Object { $_.State -eq 'Published' }
			
			if(($null -ne $Product) -and ($Product.ApprovalRequired -contains $false))
			{
				$Product = $Product | Where-Object { $_.ApprovalRequired -eq $false}
				$controlResult.AddMessage([VerificationResult]::Verify, "'Requires Approval' option is turned OFF for below Products in '$($this.ResourceContext.ResourceName)' API Management instance.", $Product) 
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Passed,"")
			}
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckManagementAPIDisabled([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMContext)
		{
			$tenantAccess = Get-AzureRmApiManagementTenantAccess -Context $this.APIMContext
			
			if(($null -ne $tenantAccess) -and ($tenantAccess.Enabled -eq $true))
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "'Enable API Management REST API' option is turned ON.") 
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Passed,"")
			}
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckGitHubIsUsedInAPIM([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMContext)
		{
			$tenantSyncState = Get-AzureRmApiManagementTenantSyncState -Context $this.APIMContext
			
			if(($tenantSyncState.IsGitEnabled -eq $true) -and ($tenantSyncState.CommitId -ne $null))
			{
				$controlResult.AddMessage([VerificationResult]::Verify, "Verify that constant string values, including secrets, across all API configuration and policies are not checked in Git repository.") 
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Passed,"")
			}
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckAADIdentityProviderEnabled([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMContext)
		{
			$identityProvider = Get-AzureRmApiManagementIdentityProvider -Context $this.APIMContext

			if($null -ne $identityProvider)
			{
				if($null -ne ($identityProvider | Where-Object {$_.Type -ne "Aad"}))
				{				
					$controlResult.AddMessage([VerificationResult]::Verify, "Below listed Identity provider(s) are enabled in '$($this.ResourceContext.ResourceName)' API management instance. It is recommended to use only Azure Active Directory backed credentials to authenticate users for enterprise application.", $identityProvider)
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Passed,"")
				}
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed,"")
			}
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckAPIMDeployedInVNet([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMInstance)
		{
			if($this.APIMInstance.VpnType -eq 'None')
			{
				$controlResult.AddMessage([VerificationResult]::Verify, "'$($this.ResourceContext.ResourceName)' API management instance is not deployed inside a virtual network. If your backend service consists corporate resources, APIM should be deployed inside the virtual network (VNET), so it can access backend services within the network.") 
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Manual,"'$($this.ResourceContext.ResourceName)' API management instance is deployed in $($this.APIMInstance.VpnType) mode inside a virtual network.")
			}
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckDefaultProductsExist([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMContext)
		{
			$Product = $this.APIMProducts
			if(($null -ne $Product) -and ($Product.ProductId -contains 'starter' -or $Product.ProductId -contains 'unlimited'))
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "APIM contains sample products. Delete the two sample products: Starter and Unlimited.") 
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Passed,"")
			}
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckClientCertAuthDisabled([ControlResult] $controlResult)
    {
		if($null -ne $this.APIMContext)
		{
			$ClientCertAuthDisabledInAPIs = ($this.APIMAPIs).ApiId | ForEach-Object {
				$apiPolicy = Get-AzureRmApiManagementPolicy -Context $this.APIMContext -ApiId $_
				$certThumbprint = $apiPolicy | Select-Xml -XPath "//inbound//authentication-certificate" | foreach { $_.Node.thumbprint }
			    if($certThumbprint -eq $null)
			    {
			        $_
			    }
			}

			if($null -ne $ClientCertAuthDisabledInAPIs)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "Client Certificate is not enabled in below APIs.", $ClientCertAuthDisabledInAPIs) 
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Passed,"")
			}
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckAPIManagementCORSAllowed([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMContext)
		{
			$Result = @()
			$this.APIMAPIs | Select-Object ApiId, Name | ForEach-Object {
			    #Policy Scope: API
				$APIPolicy = Get-AzureRmApiManagementPolicy -Context $this.APIMContext -ApiId $_.ApiId
				$AllowedOrigins = ""
			    $AllowedOrigins = $APIPolicy | Select-Xml -XPath "//inbound//cors//origin" | foreach { $_.Node.InnerXML }
			    if($null -ne $AllowedOrigins)
				{
					$Policy = "" | Select Scope, Name, Id, AllowedOrigins
					$Policy.Scope = "API"
					$Policy.Name = $_.Name
					$Policy.Id = $_.ApiId
					$Policy.AllowedOrigins = $($AllowedOrigins -join ",")

					$Result += $Policy
				}
			    
			    #Policy Scope: Operation
			    Get-AzureRmApiManagementOperation -Context $this.APIMContext -ApiId $_.ApiId | ForEach-Object {
			        $OperationPolicy = Get-AzureRmApiManagementPolicy -Context $this.APIMContext -ApiId $_.ApiId -OperationId $_.OperationId
					$AllowedOrigins = ""
			        $AllowedOrigins = $OperationPolicy | Select-Xml -XPath "//inbound//cors//origin" | foreach { $_.Node.InnerXML }
			        if($null -ne $AllowedOrigins)
			        {
			            $Policy = "" | Select Scope, ScopeName, ScopeId, AllowedOrigins
			            $Policy.Scope = "Operation"
				    	$Policy.ScopeName = $_.Name
				    	$Policy.ScopeId = $_.OperationId
						$Policy.AllowedOrigins = $($AllowedOrigins -join ",")

			            $Result += $Policy
			        }
			    }
			}

			$FailedResult = $Result | Where-Object { $_.AllowedOrigins.Split(",") -contains "*" }

			if(($FailedResult | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Failed  , 
				                      [MessageData]::new("CORS is enabled in APIM with access from all domains ('*') " + $this.ResourceContext.ResourceName, $FailedResult));
			}
			elseif(($Result | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Verify,
					[MessageData]::new("CORS is enabled in APIM with access from below custom domains."),$Result);
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Manual,
			                          [MessageData]::new("No CORS settings found for "+$this.ResourceContext.ResourceName));
			}
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckRestrictedCallerIPs([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMContext)
		{
			$Result = @()
			#Policy Scope: Gobal
			$GlobalPolicy = Get-AzureRmApiManagementPolicy -Context $this.APIMContext
			$RestrictedIPs = ""
			$RestrictedIPs = $GlobalPolicy | Select-Xml -XPath "//inbound//ip-filter" | foreach { $_.Node }
			$Policy = "" | Select Scope, ScopeName, ScopeId, Action, AllowedIPs, Status
			$Policy.Scope = "Global"
			$Policy.ScopeName = "NA"
			$Policy.ScopeId = "NA"
			$Policy.Action = ""
			$Policy.AllowedIPs = ""
			if($null -ne $RestrictedIPs)
			{
			    $Policy.Action = $RestrictedIPs.Action
			    $Policy.AllowedIPs = $RestrictedIPs.InnerXML
			    $Policy.Status = 'Enabled'
			}
			else
			{
			    $Policy.Status = 'Not Enabled'
			}
			$Result += $Policy
			#Policy Scope: Product
			$this.APIMProducts | ForEach-Object {
			    $ProductPolicy = Get-AzureRmApiManagementPolicy -Context $this.APIMContext -ProductId $_.ProductId
			    $RestrictedIPs = ""
			    $RestrictedIPs = $ProductPolicy | Select-Xml -XPath "//inbound//ip-filter" | foreach { $_.Node }
			    
				$Policy = "" | Select Scope, ScopeName, ScopeId, Action, AllowedIPs, Status
			    $Policy.Scope = "Product"
			    $Policy.ScopeName = $_.Title
			    $Policy.ScopeId = $_.ProductId
				$Policy.Action = ""
				$Policy.AllowedIPs = ""
			    if($null -ne $RestrictedIPs)
			    {
			        $Policy.Action = $RestrictedIPs.Action
			        $Policy.AllowedIPs = $RestrictedIPs.InnerXML
					$Policy.Status = 'Enabled'
			    }
				else
				{
					$Policy.Status = 'Not Enabled'
				}
				$Result += $Policy
			}
			
			
			#Policy Scope: API
			#Policy Scope: Operation
			$this.APIMAPIs | Select-Object ApiId, Name | ForEach-Object {
			    #Policy Scope: API
			    $APIPolicy = Get-AzureRmApiManagementPolicy -Context $this.APIMContext -ApiId $_.ApiId
			    $RestrictedIPs = ""
			    $RestrictedIPs = $APIPolicy | Select-Xml -XPath "//inbound//ip-filter" | foreach { $_.Node }
				$Policy = "" | Select Scope, ScopeName, ScopeId, Action, AllowedIPs, Status
			    $Policy.Scope = "API"
			    $Policy.ScopeName = $_.Name
			    $Policy.ScopeId = $_.ApiId
				$Policy.Action = ""
				$Policy.AllowedIPs = ""
			    if($null -ne $RestrictedIPs)
			    {
			        $Policy.Action = $RestrictedIPs.Action
			        $Policy.AllowedIPs = $RestrictedIPs.InnerXML
					$Policy.Status = 'Enabled'
			    }
				else
				{
					$Policy.Status = 'Not Enabled'
				}
				$Result += $Policy
			    
			    #Policy Scope: Operation
			    Get-AzureRmApiManagementOperation -Context $this.APIMContext -ApiId $_.ApiId | ForEach-Object {
			        $OperationPolicy = Get-AzureRmApiManagementPolicy -Context $this.APIMContext -ApiId $_.ApiId -OperationId $_.OperationId
			        $RestrictedIPs = ""
			        $RestrictedIPs = $APIPolicy | Select-Xml -XPath "//inbound//ip-filter" | foreach { $_.Node }
			        $Policy = "" | Select Scope, ScopeName, ScopeId, Action, AllowedIPs, Status
			        $Policy.Scope = "Operation"
			        $Policy.ScopeName = $_.Name
			        $Policy.ScopeId = $_.OperationId
					$Policy.Action = ""
					$Policy.AllowedIPs = ""
					if($null -ne $RestrictedIPs)
			        {
			            $Policy.Action = $RestrictedIPs.Action
			            $Policy.AllowedIPs = $RestrictedIPs.InnerXML
						$Policy.Status = 'Enabled'
			        }
					else
					{
						$Policy.Status = 'Not Enabled'
					}
					$Result += $Policy
			    }
			}

			if($null -ne $Result)
			{
				$controlResult.AddMessage([VerificationResult]::Verify, "Below IP restriction(s) are configured in $($this.ResourceContext.ResourceName) API management instance.", $Result) 
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Verify,"Unable to validate control.Please verify from portal, IP restirction is enabled for APIs.")
			}
		}	
		return $controlResult;
    }

	hidden [ControlResult] CheckApplicationInsightsEnabled([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMContext)
		{
			$apimLogger = Get-AzureRmApiManagementLogger -Context $this.APIMContext | Where-Object { $_.Type -eq 'ApplicationInsights' }
			
			if($null -ne $apimLogger)
			{
				$controlResult.AddMessage([VerificationResult]::Verify, "Application Insights logger is enabled for" + $this.ResourceContext.ResourceName, $apimLogger) 
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Passed,"")
			}
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckGuestGroupUsedInProduct([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMContext)
		{
			$GuestGroupUsedInProductList = $this.APIMProducts | ForEach-Object {
			    if((Get-AzureRmApiManagementGroup -Context $this.APIMContext -ProductId $_.ProductId).GroupId -contains 'guests')
			    {
			        $_
			    }
			}

			if($null -ne $GuestGroupUsedInProductList)
			{
				$controlResult.AddMessage([VerificationResult]::Verify, "Guest groups is added to below products access control.", $GuestGroupUsedInProductList) 
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Passed,"")
			}
		}	
		return $controlResult;
    }

	hidden [ControlResult] CheckDelegatedAuthNEnabled([ControlResult] $controlResult)
    {
		$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()			
		$uri=[system.string]::Format($ResourceAppIdURI+"subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.ApiManagement/service/{2}/portalsettings/delegation?api-version=2018-06-01-preview",$this.SubscriptionContext.SubscriptionId,$this.ResourceContext.ResourceGroupName,$this.ResourceContext.ResourceName)
		$json=$null;
        try 
		{ 	
			$json=[WebRequestHelper]::InvokeGetWebRequest($uri);
		} 
		catch
		{ 
			$json=$null;
		}
		if(($null -ne $json) -and (($json | Measure-Object).Count -gt 0))
		{
			if(([Helpers]::CheckMember($json[0],"properties")) -and (($json[0].properties.subscriptions.enabled -eq $true) -or ($json[0].properties.userRegistration.enabled -eq $true)))
			{
				$controlResult.AddMessage([VerificationResult]::Verify,
										 [MessageData]::new("Delegated authentication is enabled for $($this.ResourceContext.ResourceName). Please ensure that it is implemented securely."));
			}
			else
			{
			  $controlResult.AddMessage([VerificationResult]::Passed,
									 [MessageData]::new(""));
			}
		}
		else
		{
		   $controlResult.AddMessage([VerificationResult]::Verify,
								 [MessageData]::new("Unable to validate control.Please verify from portal, Delegated authentication is On or Off."));
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckAPIManagementMsiEnabled([ControlResult] $controlResult)
    {
        if($null -ne $this.APIMInstance)
		{
			if(([Helpers]::CheckMember($this.APIMInstance,"Identity.Type")) -and ($this.APIMInstance.Identity.type -eq "SystemAssigned"))
			{
				$controlResult.AddMessage([VerificationResult]::Passed,
											 [MessageData]::new("Your APIM instance is using Managed Service Identity(MSI). It is specifically turned On."));
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Failed,
											 [MessageData]::new("Your APIM instance is not using Managed Service Identity(MSI). It is specifically turned Off."));
			}
		}	
		return $controlResult;
    }
	
	hidden [ControlResult] CheckUserAuthorizationSettingInAPI([ControlResult] $controlResult)
    {       
		$UserAuthDisabledApi = $this.CheckUserAuthorizationSettingEnabledinAPI();
		if($UserAuthDisabledApi -ne 'ResourceNotFound')
		{
			if($null -ne $UserAuthDisabledApi)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "User Authorization : OAuth 2.0 or OpenID connect is not enabled in below APIs.", $UserAuthDisabledApi) 
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Passed,"")
			}
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckJWTValidatePolicyInAPI([ControlResult] $controlResult)
    {       
		$UserAuthDisabledApi = $this.CheckUserAuthorizationSettingEnabledinAPI();
		if(($UserAuthDisabledApi -ne 'ResourceNotFound') -and ($null -ne $this.APIMContext))
		{
			$JWTValidatePolicyNotFound =  $this.APIMAPIs | ForEach-Object {		
				$apiPolicy = Get-AzureRmApiManagementPolicy -Context $this.APIMContext -ApiId $_.ApiId
				$IsPolicyEnabled = $apiPolicy | Select-Xml -XPath "//inbound//validate-jwt"
				if($null -eq $IsPolicyEnabled)
				{
					$_
				}
			}
			$Temp = Compare-Object -ReferenceObject $UserAuthDisabledApi.ApiID -DifferenceObject $JWTValidatePolicyNotFound.ApiId -IncludeEqual | Where-Object { $_.SideIndicator -eq "==" }
			if(($null -ne $JWTValidatePolicyNotFound) -and ($null -ne $UserAuthDisabledApi) -and ($null -ne $Temp))
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "The ‘validate-jwt’ policy is not configured in below APIs.", $JWTValidatePolicyNotFound) 
			}
			elseif($null -ne $JWTValidatePolicyNotFound)
			{
			    $controlResult.AddMessage([VerificationResult]::Verify,"The ‘validate-jwt’ policy is not configured in below APIs.", $JWTValidatePolicyNotFound)
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed,"")
			}
		}
		return $controlResult;
    }

	hidden [PSObject] CheckUserAuthorizationSettingEnabledinAPI()
    {
		if( $null -ne $this.APIMContext)
		{
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()
			$UserAuthDisabledApi = @()
			$this.APIMAPIs | ForEach-Object {
				$uri=[system.string]::Format($ResourceAppIdURI+"subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.ApiManagement/service/{2}/apis/{3}?api-version=2018-06-01-preview",$this.SubscriptionContext.SubscriptionId,$this.ResourceContext.ResourceGroupName,$this.ResourceContext.ResourceName,$_.ApiId)
				$json=$null;
				try 
				{ 	
					$json=[WebRequestHelper]::InvokeGetWebRequest($uri);
				} 
				catch
				{ 
					$json=$null;
				}
				if(($null -ne $json) -and (($json | Measure-Object).Count -gt 0))
				{
					if(([Helpers]::CheckMember($json[0],"properties.authenticationSettings")) -and (-not ([Helpers]::CheckMember($json, "properties.authenticationSettings.oAuth2") -or [Helpers]::CheckMember($json, "properties.authenticationSettings.openid"))))
					{
						$UserAuthDisabledApi += $_
					}
				}
			}
			return $UserAuthDisabledApi;
		}
		else
		{
			return "ResourceNotFound";
		}
    }

}