Set-StrictMode -Version Latest 
class APIManagement: AzSVTBase
{   

	hidden [PSObject] $APIMContext = $null;
	hidden [PSObject] $APIMInstance = $null;
	hidden [PSObject] $APIMAPIs = $null;
	hidden [PSObject] $APIMProducts = $null;

	hidden [PSObject] $ResourceObject;

	APIManagement([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
		$this.GetResourceObject();
	}

	 hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzResource -Name $this.ResourceContext.ResourceName  `
                                    -ResourceType $this.ResourceContext.ResourceType `
                                    -ResourceGroupName $this.ResourceContext.ResourceGroupName
            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
			}
			elseif($this.ResourceObject)
			{
				$this.APIMContext = New-AzApiManagementContext -ResourceGroupName $this.ResourceContext.ResourceGroupName -ServiceName $this.ResourceContext.ResourceName
				$this.APIMInstance = Get-AzApiManagement -ResourceGroupName $this.ResourceContext.ResourceGroupName -Name $this.ResourceContext.ResourceName
				$this.APIMAPIs = Get-AzApiManagementApi -Context $this.APIMContext
				$this.APIMProducts = Get-AzApiManagementProduct -Context $this.APIMContext
			}
        }
        return $this.ResourceObject;
	}
	
	[ControlItem[]] ApplyServiceFilters([ControlItem[]] $controls)
	{
		$result = @();
		if($this.ResourceObject)
		{
			if($controls.Count -eq 0)
			{
				return $controls;
			}

			# Filter controls based on Tier
			if($this.APIMInstance.Sku -eq "Premium")
			{
				$result += $controls | Where-Object {$_.Tags -contains "PremiumSku" }
			}
			elseif($this.APIMInstance.Sku -eq "Standard")
			{
				$result += $controls | Where-Object {$_.Tags -contains "StandardSku" }
			}
			elseif($this.APIMInstance.Sku -eq "Basic")
			{
				$result += $controls | Where-Object {$_.Tags -contains "BasicSku" }
			}
			elseif($this.APIMInstance.Sku -eq "Developer")
			{
				$result += $controls | Where-Object {$_.Tags -contains "DeveloperSku" }
			}

			# Filter controls: API and Products
			if(-not $this.APIMAPIs)
			{
				$result = $result | Where-Object {$_.Tags -notcontains "APIMAPIs" }
			}
			if(-not $this.APIMProducts)
			{
				$result = $result | Where-Object {$_.Tags -notcontains "APIMProducts" }
			}
			
		}
		return $result;
	}

	hidden [ControlResult] CheckAPIMMetricAlert([ControlResult] $controlResult)
    {
		$this.CheckMetricAlertConfiguration($this.ControlSettings.MetricAlert.APIManagement, $controlResult, "");
		return $controlResult;
    }
    hidden [ControlResult] CheckAPIMURLScheme([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMAPIs)
		{
			$nonCompliantAPIs = $this.APIMAPIs | Where-Object {$_.Protocols.count -gt 1 -or $_.Protocols[0] -ne [Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementSchema]::Https } |`
								Select-Object ServiceName, ResourceGroupName, Name, ApiId, Protocols, ServiceUrl
			if(($nonCompliantAPIs|Measure-Object).Count -gt 0)
			{
			    $controlResult.AddMessage([VerificationResult]::Failed, "Below API(s) are configured to use non-secure HTTP access to the backend via API Management.", $nonCompliantAPIs)
				$controlResult.SetStateData("API(s) using non-secure HTTP access", $nonCompliantAPIs);
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
			$allNamedValues += Get-AzApiManagementProperty -Context $this.APIMContext 
			if($allNamedValues.count -eq 0)
			{
			    $controlResult.AddMessage([VerificationResult]::Passed, "No named values are present in this API Management service.")	    
			}
			else
			{
			    $nonsecretNamedValues = $allNamedValues | where-object {$_.Secret -eq $false}
			    if(($nonsecretNamedValues |Measure-Object).Count -gt 0)
			    {
			        $controlResult.AddMessage([VerificationResult]::Verify, "Below named value(s) are not marked as secret, use secret named value if it contains sensitive data.", $nonsecretNamedValues.Id)
					$controlResult.SetStateData("Unencrypted variable(s)", $nonsecretNamedValues.Id);
			    }
			    else
			    {
			        $controlResult.AddMessage([VerificationResult]::Passed, "")
			    }
			}
		}
		return $controlResult;
	}
	
	hidden [ControlResult] CheckAPIMProtocolsAndCiphersConfiguration([ControlResult] $controlResult)
    {
		$isNonCompliant = $false
	    $nonCompliantConfigurations = @()
		# TLS 1.2 is always enabled in case on APIM
		# Here we check if old, unsecure protocol configurations are enabled
		if ([Helpers]::CheckMember($this.ResourceObject, "properties.customProperties"))
		{
			$this.ResourceObject.properties.customProperties | Get-Member -MemberType Properties | `
			Where-Object { $($this.ControlSettings.APIManagement.UnsecureProtocolsAndCiphersConfiguration) -contains $_.Name } | ` 
			ForEach-Object {
				if ($this.ResourceObject.properties.customProperties."$($_.Name)" -eq 'true')
				{
					$nonCompliantConfigurations += @{ $_.Name = $this.ResourceObject.properties.customProperties."$($_.Name)" }
					$isNonCompliant = $true
				}
			}

			if($isNonCompliant)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "Ensure that protocols and ciphers configuration below are disabled.", $($nonCompliantConfigurations))
				$controlResult.SetStateData("Below protocols and ciphers configuration are enabled", $($nonCompliantConfigurations));
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, "The old versions of protocols and ciphers configuration are disabled.")
			}
		}
		
		return $controlResult;
    }
    
	hidden [ControlResult] CheckRequiresSubscription([ControlResult] $controlResult)
    {
		# Currently, two more subscription scopes: all APIs and a single API are available in the API Management Consumption tier only.
		# We do not recommend All APIs scope because a single key will grant access all APIs within an API Management instance.

		if($null -ne $this.APIMProducts)
		{
			$Product = $this.APIMProducts | Where-Object { ($_.State -eq [Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementProductState]::Published) -and ($_.SubscriptionRequired -eq $false )}
			if(($Product | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "'Requires Subscription' option is turned OFF for below Products in '$($this.ResourceContext.ResourceName)' API Management instance.", $Product )
				$controlResult.SetStateData("API product(s) open for public access without the requirement of subscriptions", $Product);
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
		if( $null -ne $this.APIMProducts)
		{
			$Product = $this.APIMProducts | Where-Object { $_.State -eq [Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementProductState]::Published }
			
			if(($null -ne $Product) -and ($Product.ApprovalRequired -contains $false))
			{
				$Product = $Product | Where-Object { $_.ApprovalRequired -eq $false}
				$controlResult.AddMessage([VerificationResult]::Verify, "'Requires Approval' option is turned OFF for below Products in '$($this.ResourceContext.ResourceName)' API Management instance.", $Product)
				$controlResult.SetStateData("API product(s) where subscription attempts are auto-approved", $Product);
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
			$tenantAccess = Get-AzApiManagementTenantAccess -Context $this.APIMContext
			
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
			$tenantSyncState = Get-AzApiManagementTenantSyncState -Context $this.APIMContext
			
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
			# Check if registration using 'Username and Password' is enabled
			$IsBasicRegistrationEnabled = $false
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()			
			$uri=[system.string]::Format($ResourceAppIdURI+"subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.ApiManagement/service/{2}/tenant/settings?api-version=2018-06-01-preview",$this.SubscriptionContext.SubscriptionId,$this.ResourceContext.ResourceGroupName,$this.ResourceContext.ResourceName)
			$json=$null;
        	try 
			{
				$json=[WebRequestHelper]::InvokeGetWebRequest($uri);
			} 
			catch
			{
				$json=$null;
			}
			$failMsg = ""
			if($null -ne $json)
			{
				if([Helpers]::CheckMember($json,"settings"))
				{
					$IsBasicRegistrationEnabled = $json.settings.'CustomPortalSettings.RegistrationEnabled'
				}
				else
				{
					$failMsg = "Unable to validate control. Please verify from portal that user registration using 'Username and Password' is disabled. To verify, go to APIM service instance -> Settings -> Identities."
				}	
			}
			
			# Check if sign in using external Identity provider is enabled
			$identityProvider = Get-AzApiManagementIdentityProvider -Context $this.APIMContext
			$nonAADIdentityProvider = $identityProvider | Where-Object { $this.ControlSettings.APIManagement.AllowedIdentityProvider -notcontains  $_.Type}
			
			# Consolidate result for attestation drift
			$result = @()
			if(($IsBasicRegistrationEnabled -eq $true) -or (-not [string]::IsNullOrEmpty($failMsg)))
			{
				$result += "Username and Password"
			}
			if(($nonAADIdentityProvider | Measure-Object).Count -gt 0)
			{
				$result += $nonAADIdentityProvider | ForEach-Object {$_.Type}
			}

			if(($result | Measure-Object).Count -gt 0)
			{		
				$controlResult.AddMessage([VerificationResult]::Verify, "$($failMsg)`r`nBelow listed Identity provider(s) are enabled in '$($this.ResourceContext.ResourceName)' API management instance. Enterprise applications using APIM must authenticate developers/applications using Azure Active Directory backed credentials.", $result)
				$controlResult.SetStateData("Sign in option enabled on developer portal other than AAD", $result);
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
			if($this.APIMInstance.VpnType -eq [Microsoft.Azure.Commands.ApiManagement.Models.PsApiManagementVpnType]::None)
			{
				$controlResult.AddMessage([VerificationResult]::Verify, "'$($this.ResourceContext.ResourceName)' API management instance is not deployed inside a virtual network. Consider hosting APIM within a virtual network for improved isolation.") 
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
		if( $null -ne $this.APIMProducts)
		{
			$Product = $this.APIMProducts | Where-Object { ($_.ProductId -eq 'starter') -or ($_.ProductId -eq 'unlimited') }
			if(($Product | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "APIM contains sample products. Delete the two sample products: Starter and Unlimited.",$Product) 
				$controlResult.SetStateData("APIM service sample product", $Product);
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
		if(($null -ne $this.APIMContext) -and ($null -ne $this.APIMAPIs))
		{
			$ClientCertAuthDisabledInAPIs = ($this.APIMAPIs).ApiId | ForEach-Object {
				$apiPolicy = Get-AzApiManagementPolicy -Context $this.APIMContext -ApiId $_
				$certThumbprint = $apiPolicy | Select-Xml -XPath "//inbound//authentication-certificate" | foreach { $_.Node.thumbprint }
			    if($certThumbprint -eq $null)
			    {
			        $_
			    }
			}

			if($null -ne $ClientCertAuthDisabledInAPIs)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "Gateway authentication using client certificate is not enabled in below APIs.", $ClientCertAuthDisabledInAPIs) 
				$controlResult.SetStateData("Gateway authentication using client certificate is not enabled in APIs", $ClientCertAuthDisabledInAPIs);
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
		if(($null -ne $this.APIMContext) -and ($null -ne $this.APIMAPIs))
		{
			$Result = @()
			$MaxApiCount = 10
			$SleepTime = 30
			if([Helpers]::CheckMember($this.ControlSettings,"SleepTime"))
			{
				$SleepTime = $this.ControlSettings.SleepTime
			}
			if([Helpers]::CheckMember($this.ControlSettings,"MaxApiCount"))
			{
				$MaxApiCount = $this.ControlSettings.MaxApiCount
			}
			$Counter = 0
			$this.APIMAPIs | Select-Object ApiId, Name | ForEach-Object {
			    #Policy Scope: API
			
				if($Counter -ge $MaxApiCount)
                {
				sleep($SleepTime)
				$Counter = 0
				}
				$Counter ++
				$APIPolicy = Get-AzApiManagementPolicy -Context $this.APIMContext -ApiId $_.ApiId
				$AllowedOrigins = ""
			    $AllowedOrigins = $APIPolicy | Select-Xml -XPath "//inbound//cors//origin" | foreach { $_.Node.InnerXML }
			    if($null -ne $AllowedOrigins)
				{
					$Policy = "" | Select-Object Scope, Name, Id, AllowedOrigins
					$Policy.Scope = "API"
					$Policy.Name = $_.Name
					$Policy.Id = $_.ApiId
					$Policy.AllowedOrigins = $($AllowedOrigins -join ",")

					$Result += $Policy
				}
			    
			    #Policy Scope: Operation
			    Get-AzApiManagementOperation -Context $this.APIMContext -ApiId $_.ApiId | ForEach-Object {
			        $OperationPolicy = Get-AzApiManagementPolicy -Context $this.APIMContext -ApiId $_.ApiId -OperationId $_.OperationId
					$AllowedOrigins = ""
			        $AllowedOrigins = $OperationPolicy | Select-Xml -XPath "//inbound//cors//origin" | foreach { $_.Node.InnerXML }
			        if($null -ne $AllowedOrigins)
			        {
			            $Policy = "" | Select-Object Scope, ScopeName, ScopeId, AllowedOrigins
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
				$controlResult.SetStateData("CORS setting Allowed Origins", $FailedResult);
			}
			elseif(($Result | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Verify,
					[MessageData]::new("CORS is enabled in APIM with access from below custom domains."),$Result);
				$controlResult.SetStateData("CORS setting Allowed Origins",$Result);
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
			$GlobalPolicy = Get-AzApiManagementPolicy -Context $this.APIMContext
			$RestrictedIPs = ""
			$RestrictedIPs = $GlobalPolicy | Select-Xml -XPath "//inbound//ip-filter" | foreach { $_.Node }
			$Policy = "" | Select Scope, ScopeName, ScopeId, Action, AddressRange, Status
			$Policy.Scope = "Global"
			$Policy.ScopeName = "NA"
			$Policy.ScopeId = "NA"
			$Policy.Action = ""
			$Policy.AddressRange = ""
			if($null -ne $RestrictedIPs)
			{
			    $Policy.Action = $RestrictedIPs.Action
			    $Policy.AddressRange = $RestrictedIPs | Select-Object Address, Address-Range
			    $Policy.Status = 'Enabled'
			}
			else
			{
			    $Policy.Status = 'Not Enabled'
			}
			$Result += $Policy
			#Policy Scope: Product
			if($null -ne $this.APIMProducts)
			{
				$this.APIMProducts | ForEach-Object {
			    $ProductPolicy = Get-AzApiManagementPolicy -Context $this.APIMContext -ProductId $_.ProductId
			    $RestrictedIPs = ""
			    $RestrictedIPs = $ProductPolicy | Select-Xml -XPath "//inbound//ip-filter" | foreach { $_.Node }
			    
				$Policy = "" | Select Scope, ScopeName, ScopeId, Action, AddressRange, Status
			    $Policy.Scope = "Product"
			    $Policy.ScopeName = $_.Title
			    $Policy.ScopeId = $_.ProductId
				$Policy.Action = ""
				$Policy.AddressRange = ""
			    if($null -ne $RestrictedIPs)
			    {
			        $Policy.Action = $RestrictedIPs.Action
			        $Policy.AddressRange = $RestrictedIPs | Select-Object Address, Address-Range
					$Policy.Status = 'Enabled'
			    }
				else
				{
					$Policy.Status = 'Not Enabled'
				}
				$Result += $Policy
			}
			}
			#Policy Scope: API
			#Policy Scope: Operation
			$MaxApiCount = 10
			$SleepTime = 30
			if([Helpers]::CheckMember($this.ControlSettings,"SleepTime"))
			{
				$SleepTime = $this.ControlSettings.SleepTime
			}
			if([Helpers]::CheckMember($this.ControlSettings,"MaxApiCount"))
			{
				$MaxApiCount = $this.ControlSettings.MaxApiCount
			}
			$Counter = 0
			if($null -ne $this.APIMAPIs)
			{
				$this.APIMAPIs | Select-Object ApiId, Name | ForEach-Object {
					#Policy Scope: API
                    if($Counter -ge $MaxApiCount)
                    {
						sleep($SleepTime)
						$Counter = 0
					}
					$Counter ++
					$APIPolicy = Get-AzApiManagementPolicy -Context $this.APIMContext -ApiId $_.ApiId
					$RestrictedIPs = ""
					$RestrictedIPs = $APIPolicy | Select-Xml -XPath "//inbound//ip-filter" | foreach { $_.Node }
					$Policy = "" | Select Scope, ScopeName, ScopeId, Action, AddressRange, Status
					$Policy.Scope = "API"
					$Policy.ScopeName = $_.Name
					$Policy.ScopeId = $_.ApiId
					$Policy.Action = ""
					$Policy.AddressRange = ""
					if($null -ne $RestrictedIPs)
					{
					    $Policy.Action = $RestrictedIPs.Action
					    $Policy.AddressRange = $RestrictedIPs | Select-Object Address, Address-Range
						$Policy.Status = 'Enabled'
					}
					else
					{
						$Policy.Status = 'Not Enabled'
					}
					$Result += $Policy
					
					#Policy Scope: Operation
					Get-AzApiManagementOperation -Context $this.APIMContext -ApiId $_.ApiId | ForEach-Object {
						$OperationPolicy = Get-AzApiManagementPolicy -Context $this.APIMContext -ApiId $_.ApiId -OperationId $_.OperationId
						$RestrictedIPs = ""
						$RestrictedIPs = $APIPolicy | Select-Xml -XPath "//inbound//ip-filter" | foreach { $_.Node }
						$Policy = "" | Select Scope, ScopeName, ScopeId, Action, AddressRange, Status
						$Policy.Scope = "Operation"
						$Policy.ScopeName = $_.Name
						$Policy.ScopeId = $_.OperationId
						$Policy.Action = ""
						$Policy.AddressRange = ""
						if($null -ne $RestrictedIPs)
						{
						    $Policy.Action = $RestrictedIPs.Action
						    $Policy.AddressRange = $RestrictedIPs | Select-Object Address, Address-Range
							$Policy.Status = 'Enabled'
						}
						else
						{
							$Policy.Status = 'Not Enabled'
						}
						$Result += $Policy
					}
				}
			}

			#Fail control if universal address range 0.0.0.0-255.255.255.255 is used
			$anyToAnyIPFilter = @()
			$allowedIPRange = $Result | Where-Object { $_.Action -eq 'Allow' }
			if(($allowedIPRange | Measure-Object).Count -gt 0)
			{
				$anyToAnyIPFilter = $allowedIPRange | ForEach-Object {
					$AddressRange = $_.AddressRange[0].'address-range' | Where-Object { 
						if(($_ | Measure-Object).Count -gt 0)
						{
							(($_.from -eq $this.ControlSettings.IPRangeStartIP -and $_.to -eq $this.ControlSettings.IPRangeEndIP) -or `
							($_.from -eq $this.ControlSettings.IPRangeEndIP -and $_.to -eq $this.ControlSettings.IPRangeStartIP))
						}
					}; 
					if($AddressRange)
					{
						return $_
					}
				}
			}

			if(($anyToAnyIPFilter | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "Below IP restriction(s) are configured in $($this.ResourceContext.ResourceName) API management instance.", $anyToAnyIPFilter)
				$controlResult.SetStateData("Restricted caller IPs",$anyToAnyIPFilter);
			}
			elseif(($Result | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Verify, "Below IP restriction(s) are configured in $($this.ResourceContext.ResourceName) API management instance.", $Result)
				$controlResult.SetStateData("Restricted caller IPs",$Result);
			}
			else
			{
			    $controlResult.AddMessage([VerificationResult]::Verify,"Unable to validate control. Please verify from portal that IP restirction is enabled for APIs.")
			}
		}	
		return $controlResult;
    }

	hidden [ControlResult] CheckApplicationInsightsEnabled([ControlResult] $controlResult)
    {
		if( $null -ne $this.APIMContext)
		{
			$apimLogger = Get-AzApiManagementLogger -Context $this.APIMContext | Where-Object { $_.Type -eq [Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementLoggerType]::ApplicationInsights }
			
			if($null -ne $apimLogger)
			{
				$controlResult.AddMessage([VerificationResult]::Verify, "Application Insights logger is enabled for" + $this.ResourceContext.ResourceName, $apimLogger) 
				$controlResult.SetStateData("APIs using Application Insights for logging",$apimLogger);
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
		if(($null -ne $this.APIMContext) -and ($null -ne $this.APIMProducts))
		{
			$GuestGroupUsedInProductList = $this.APIMProducts | ForEach-Object {
			    if((Get-AzApiManagementGroup -Context $this.APIMContext -ProductId $_.ProductId).GroupId -contains 'guests')
			    {
			        $_
			    }
			}

			if($null -ne $GuestGroupUsedInProductList)
			{
				$controlResult.AddMessage([VerificationResult]::Verify, "Guest groups is added to below products access control.", $GuestGroupUsedInProductList) 
				$controlResult.SetStateData("Products open to Guest users",$GuestGroupUsedInProductList);
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
									 [MessageData]::new("Your APIM instance is not using Delegated authentication. It is specifically turned Off."));
			}
		}
		else
		{
		   $controlResult.AddMessage([VerificationResult]::Verify,
								 [MessageData]::new("Unable to validate control. Please verify from portal if the Delegated authentication is On, then it is implemented securely."));
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckAPIManagementMsiEnabled([ControlResult] $controlResult)
    {
        if($null -ne $this.APIMInstance)
		{
			if(([Helpers]::CheckMember($this.APIMInstance.Identity,"Type",$false)) -and ($this.APIMInstance.Identity.type -eq [Microsoft.Azure.Commands.ApiManagement.Models.PsApiManagementServiceIdentityType]::SystemAssigned))
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
		$APIUserAuth = $this.CheckUserAuthorizationSettingEnabledinAPI();
		if(($APIUserAuth.Disabled | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage([VerificationResult]::Failed, "User Authorization : OAuth 2.0 or OpenID connect is not enabled in below APIs.", $APIUserAuth.Disabled)
			$controlResult.SetStateData("User Authorization not enabled in APIs",$APIUserAuth.Disabled);
		}
		else
		{
		    $controlResult.AddMessage([VerificationResult]::Passed,"")
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckJWTValidatePolicyInAPI([ControlResult] $controlResult)
    {       
		$APIUserAuth = $this.CheckUserAuthorizationSettingEnabledinAPI();
		$JWTValidatePolicyNotFound = @()
		if(($APIUserAuth -ne 'ResourceNotFound') -and ($null -ne $this.APIMContext) -and ($null -ne $this.APIMAPIs))
		{
			$JWTValidatePolicyNotFound =  $this.APIMAPIs | ForEach-Object {		
				$apiPolicy = Get-AzApiManagementPolicy -Context $this.APIMContext -ApiId $_.ApiId
				$IsPolicyEnabled = $apiPolicy | Select-Xml -XPath "//inbound//validate-jwt"
				if($null -eq $IsPolicyEnabled)
				{
					$_
				}
			}
			$Temp = @()
			if(($JWTValidatePolicyNotFound | Measure-Object).Count -gt 0 -and ($APIUserAuth.Enabled | Measure-Object).Count -gt 0)
			{
				$Temp = Compare-Object -ReferenceObject $APIUserAuth.Enabled.ApiID -DifferenceObject $JWTValidatePolicyNotFound.ApiId -IncludeEqual | Where-Object { $_.SideIndicator -eq "==" }
			}
			if(($JWTValidatePolicyNotFound | Measure-Object).Count -gt 0 -and ($APIUserAuth.Enabled | Measure-Object).Count -gt 0 -and ($Temp | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "JWT Token validation not found for OAuth/OpenID connect authorization.", $Temp)
				$controlResult.SetStateData("JWT Token validation not found",$Temp);
			}
			elseif(($JWTValidatePolicyNotFound| Measure-Object).Count -gt 0)
			{
			    $controlResult.AddMessage([VerificationResult]::Verify,"The 'validate-jwt' policy is not configured in below APIs.", $JWTValidatePolicyNotFound)
				$controlResult.SetStateData("JWT Token validation not found",$JWTValidatePolicyNotFound);
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
		if( $null -ne $this.APIMContext -and ($null -ne $this.APIMAPIs))
		{
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()
			$APIUserAuth = "" | Select-Object Enabled, Disabled
			$APIUserAuth.Enabled = @()
			$APIUserAuth.Disabled = @()
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
					if(([Helpers]::CheckMember($json[0],"properties.authenticationSettings")) -and ([Helpers]::CheckMember($json, "properties.authenticationSettings.oAuth2") -or [Helpers]::CheckMember($json, "properties.authenticationSettings.openid")))
					{
						$APIUserAuth.Enabled += $_
					}
					else
					{
						$APIUserAuth.Disabled += $_
					}
				}
			}
			return $APIUserAuth;
		}
		else
		{
			return "ResourceNotFound";
		}
    }

}