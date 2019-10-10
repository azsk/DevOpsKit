#using namespace Microsoft.Azure.Commands.AppService.Models
Set-StrictMode -Version Latest
class AppService: AzSVTBase
{
    hidden [PSObject] $ResourceObject;
	hidden [PSObject] $WebAppDetails;
	hidden [PSObject] $SiteConfigs;
	hidden [PSObject] $AuthenticationSettings;
	hidden [bool] $IsReaderRole;

    AppService([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId, $svtResource)
    {
				$this.GetResourceObject();
	    	$this.AddResourceMetadata($this.ResourceObject.Properties)

    }

	hidden [string] FormatURL([string] $AppURL)
	{
		$ind = $AppURL.IndexOf('.')
		$AppURL = $AppURL.Substring($ind+1)
		return $AppURL
	}
    hidden [PSObject] GetResourceObject()
    {
			if (-not $this.ResourceObject)
			{
				# Get App Service details
							$this.ResourceObject = Get-AzResource -Name $this.ResourceContext.ResourceName  `
																					-ResourceType $this.ResourceContext.ResourceType `
																					-ResourceGroupName $this.ResourceContext.ResourceGroupName

							if(-not $this.ResourceObject)
							{
					throw ([SuppressedException]::new(("Resource '$($this.ResourceContext.ResourceName)' not found under Resource Group '$($this.ResourceContext.ResourceGroupName)'"), [SuppressedExceptionType]::InvalidOperation))
							}

				# Get web sites details
				$this.WebAppDetails = Get-AzWebApp -Name $this.ResourceContext.ResourceName `
										-ResourceGroupName $this.ResourceContext.ResourceGroupName 

				try
				{ 
					$this.AuthenticationSettings = Invoke-AzResourceAction -ResourceType "Microsoft.Web/sites/config/authsettings" `
																																											-ResourceGroupName $this.ResourceContext.ResourceGroupName `
																																											-ResourceName $this.ResourceContext.ResourceName `
																																											-Action list `
																																											-ApiVersion $this.ControlSettings.AppService.AADAuthAPIVersion `
																																											-Force `
																																											-ErrorAction Stop
					$this.IsReaderRole = $false;
				}
				catch
				{
					if(($_.Exception | Get-Member -Name "HttpStatus" ) -and $_.Exception.HttpStatus -eq "Forbidden")
					{
						$this.IsReaderRole = $true;
					}	
				}

				try{
					$this.SiteConfigs = Get-AzResource -ResourceGroupName $this.ResourceContext.ResourceGroupName -ResourceType Microsoft.Web/sites/config -ResourceName $this.ResourceContext.ResourceName -ApiVersion 2018-02-01
				  # Append SiteConfig to ResourceObject
					if($null -ne $this.SiteConfigs -and [Helpers]::CheckMember($this.SiteConfigs,"Properties") -and [Helpers]::CheckMember($this.ResourceObject.Properties,"siteConfig", $false)){
						$this.ResourceObject.Properties.siteConfig = $this.SiteConfigs.Properties
					}
				}catch{
					$this.SiteConfigs = $null
					# No need to break execution , null object is handled in respective controls
				}
		}
        return $this.ResourceObject;
    }
	
	[ControlItem[]] ApplyServiceFilters([ControlItem[]] $controls)
	{
		$serviceFilterTag = "AppService";
		$osFilterTag = "Windows";
		if([Helpers]::CheckMember($this.ResourceObject, "Kind"))
		{
			if($this.ResourceObject.Kind -like "*functionapp*")
			{
				$serviceFilterTag = "FunctionApp";
			}
			if($this.ResourceObject.Kind -like "*linux*")
			{
				$osFilterTag = "Linux";
			}
		}
		
		$result = @();
		$result += $controls | Where-Object { $_.Tags -contains $serviceFilterTag } | Where-Object { $_.Tags -contains $osFilterTag };
		return $result;
	}

    hidden [ControlResult] CheckAppServiceCustomDomainWithSSLConfig([ControlResult] $controlResult)
	{
		# Get custom domain URLs
        $customHostNames = $this.ResourceObject.Properties.HostNames |
								Where-Object {
									 -not $_.Contains(".azurewebsites.")
								};

        # Combine custom domain name and SSL configuration TCP

        if(($customHostNames | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage([MessageData]::new("Custom domains are configured for resource " + $this.ResourceContext.ResourceName), $customHostNames);

			$SSLStateNotEnabled = $this.ResourceObject.Properties.hostNameSslStates | Where-Object { ($customHostNames -contains $_.name) -and  ($_.sslState -eq 'Disabled')} | Select-Object -Property Name
			if($null -eq $SSLStateNotEnabled)
			{
				$controlResult.AddMessage([VerificationResult]::Passed,
											[MessageData]::new("SSL configuration for resource " + $this.ResourceContext.ResourceName + " is enabled for all custom domains", $this.ResourceObject.Properties.hostNameSslStates));
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Failed,
											[MessageData]::new("SSL configuration for resource " + $this.ResourceContext.ResourceName + " is not enabled for all custom domains", $this.ResourceObject.Properties.hostNameSslStates));
			}
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Failed,
                                    [MessageData]::new("Custom domains are not configured for resource " + $this.ResourceContext.ResourceName, $this.ResourceObject.Properties.HostNames));
        }

        return $controlResult;
    }

    hidden [ControlResult] CheckAppServiceADAuthentication([ControlResult] $controlResult)
    {
		if($this.IsReaderRole)
		{
			#Setting this property ensures that this control result wont be considered for the central telemetry. As control doesnt have the required permissions
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual,
                                    [MessageData]::new("Control can not be validated due to insufficient access permission on resource"));
		}
		else
		{
			#Checks if functions app present
			if([Helpers]::CheckMember($this.ResourceObject, "Kind") -and ($this.ResourceObject.Kind -eq "functionapp"))
			{
				$ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
				$accessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
				$authorisationToken = "Bearer " + $accessToken
				$headers = @{"Authorization"=$authorisationToken;"Content-Type"="application/json"}

				if([Helpers]::CheckMember($this.WebAppDetails,"EnabledHostNames"))
				{
					if((($this.WebAppDetails.EnabledHostNames | where-object { $_.Contains('scm') }) | Measure-Object).Count -eq 1)
					{
						$scmURL = $this.WebAppDetails.EnabledHostNames | where-object { $_.Contains('scm') }
						$apiFunctionsUrl = [string]::Format("https://{0}/api/functions",$scmURL)
					}
					else
					{
						$temp = @($this.WebAppDetails.EnabledHostNames | where-object { $_.Contains('.azurewebsites.') })
						$AppURL = $this.FormatURL($temp[0])
						$apiFunctionsUrl = [string]::Format("https://{0}.scm.{1}/api/functions",$this.ResourceContext.ResourceName,$AppURL)
					}
				}
				else
				{
					$temp = @($this.ResourceObject.Properties.HostNames | where-object { $_.Contains('.azurewebsites.') })
					$AppURL = $this.FormatURL($temp[0])
					$apiFunctionsUrl = [string]::Format("https://{0}.scm.{1}/api/functions",$this.ResourceContext.ResourceName,$AppURL)
				}
				
				try
				{
						$functionDetail = [WebRequestHelper]::InvokeGetWebRequest($apiFunctionsUrl, $headers)
				
						#check if functions are present in FunctionApp	
						if([Helpers]::CheckMember($functionDetail,"config"))
						{
							$bindingsDetail =$functionDetail.config.bindings
								$ishttpTriggerFunction=$false
							if(($bindingsDetail| Measure-Object).Count -gt 0)
							{
								$bindingsDetail |	 ForEach-Object{
								if($_.type -eq "httpTrigger" )
										{
										$ishttpTriggerFunction=$true
									}
								}
								#if HTTP trigger function is not present, then AAD authentication is not required
								if(!$ishttpTriggerFunction)
								{
									$controlResult.AddMessage([VerificationResult]::Passed,
											[MessageData]::new("AAD Authentication for resource " + $this.ResourceContext.ResourceName + " is not required."));
									return $controlResult;
								}
							}
						}
						#if no function is present in Functions App, then AAD authentication is not required
						else
						{
						$controlResult.AddMessage([VerificationResult]::Passed,
									[MessageData]::new("AAD Authentication for resource " + $this.ResourceContext.ResourceName + " is not required."));
						return $controlResult;
					
						}
				}
				catch
				{
					$controlResult.AddMessage([VerificationResult]::Manual,
					        [MessageData]::new("Unable to fetch details of functions."));
					return $controlResult;
				}
				
			}

			$AADEnabled = $false
			if([Helpers]::CheckMember($this.AuthenticationSettings,"Properties"))
			{
				$aadSettings = New-Object PSObject
				if([Helpers]::CheckMember($this.AuthenticationSettings.Properties,"enabled"))
				{
					Add-Member -InputObject $aadSettings -MemberType NoteProperty -Name "Enabled" -Value $this.AuthenticationSettings.Properties.enabled
				}
				
				if([Helpers]::CheckMember($this.AuthenticationSettings.Properties,"ClientId"))
				{
					Add-Member -InputObject $aadSettings -MemberType NoteProperty -Name "ClientId" -Value $this.AuthenticationSettings.Properties.ClientId

					if(([Helpers]::CheckMember($this.AuthenticationSettings.Properties,"enabled")) -and ($this.AuthenticationSettings.Properties.enabled -eq $True))
					{
						if($null -ne $this.AuthenticationSettings.Properties.ClientId)
						{
							$AADEnabled = $True;
						}
					}
				}				

			
				#Check if any non AAD authenticaion is also enabled
				if([Helpers]::CheckMember($this.ControlSettings,"AppService.NonAADAuthProperties")){
					$nonAadSettings = New-Object PSObject
					$nonAADAuthEnabled = $false
					$NonAADAuthProperties = $this.ControlSettings.AppService.NonAADAuthProperties 
					ForEach($authProperty in 	$NonAADAuthProperties){
						if([Helpers]::CheckMember($this.AuthenticationSettings.Properties,$authProperty)){
							$nonAADAuthEnabled = $true
							Add-Member -InputObject $nonAadSettings -MemberType NoteProperty -Name $authProperty -Value $this.AuthenticationSettings.Properties.$($authProperty)
						}
					}
					if($nonAADAuthEnabled ){
						if($AADEnabled)
						{
							$controlResult.AddMessage("AAD Authentication for resource " + $this.ResourceContext.ResourceName + " is enabled "+ $aadSettings)
						}
						#Fail the control if non AAD authentication is enabled, irrespective of AAD is enabled or not 
						$controlResult.AddMessage([VerificationResult]::Failed,
						[MessageData]::new("Authentication mechanism other than AAD is enabled for " + $this.ResourceContext.ResourceName ));
						$controlResult.AddMessage($nonAadSettings);
						$controlResult.SetStateData("App Service authentication settings", $nonAadSettings);
						return $controlResult;
					}
				}
				
				if($AADEnabled)
				{
					if([FeatureFlightingManager]::GetFeatureStatus("EnableAppServiceAADAuthAllowAnonymousCheck",$($this.SubscriptionContext.SubscriptionId)) -eq $true)
					{
						if(([Helpers]::CheckMember($this.AuthenticationSettings.Properties,"unauthenticatedClientAction")))
						{
							
							Add-Member -InputObject $aadSettings -MemberType NoteProperty -Name "UnauthenticatedClientAction" -Value $this.AuthenticationSettings.Properties.unauthenticatedClientAction
							if( $this.AuthenticationSettings.Properties.unauthenticatedClientAction -eq 'AllowAnonymous')
							{
								$controlResult.AddMessage([VerificationResult]::Failed,
											[MessageData]::new("AAD Authentication for resource " + $this.ResourceContext.ResourceName + " is enabled."));
								$controlResult.AddMessage("Action to take when request is not authenticated is set to $($this.AuthenticationSettings.Properties.unauthenticatedClientAction)")
								$controlResult.AddMessage($aadSettings);
								return $controlResult;
							}
						}
					}
					$controlResult.AddMessage([VerificationResult]::Passed,
											[MessageData]::new("AAD Authentication for resource " + $this.ResourceContext.ResourceName + " is enabled", $aadSettings));
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Verify,
											[MessageData]::new("Verify that AAD Authentication for resource " + $this.ResourceContext.ResourceName + " is enabled", $aadSettings));
					$controlResult.SetStateData("App Service AAD settings", $aadSettings);
				}				
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Verify,
											[MessageData]::new("Verify that AAD Authentication for resource " + $this.ResourceContext.ResourceName + " is enabled"));
			}

		}

      return $controlResult;
    }

    hidden [ControlResult] CheckAppServiceRemoteDebuggingConfiguration([ControlResult] $controlResult)
	{
		if([Helpers]::CheckMember($this.WebAppDetails,"SiteConfig"))
		{
			if([Helpers]::CheckMember($this.WebAppDetails.SiteConfig,"RemoteDebuggingEnabled") -and $this.WebAppDetails.SiteConfig.RemoteDebuggingEnabled)
			{
				$controlResult.AddMessage([VerificationResult]::Failed,
											[MessageData]::new("Remote debugging for resource " + $this.ResourceContext.ResourceName + " is turned on", ($this.WebAppDetails.SiteConfig | Select-Object RemoteDebuggingEnabled)));
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed,
											[MessageData]::new("Remote debugging for resource " + $this.ResourceContext.ResourceName + " is turned off", ($this.WebAppDetails.SiteConfig | Select-Object RemoteDebuggingEnabled)));
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Manual,
											[MessageData]::new("Could not validate remote debugging settings on the AppService: " + $this.ResourceContext.ResourceName + "."));
		}

      return $controlResult;
	}

    hidden [ControlResult] CheckAppServiceWebSocketsConfiguration([ControlResult] $controlResult)
	{
		if($this.WebAppDetails.SiteConfig.WebSocketsEnabled)
        {
			$controlResult.EnableFixControl = $true;
			$controlResult.AddMessage([VerificationResult]::Failed,
                                     [MessageData]::new("Web sockets for resource " + $this.ResourceContext.ResourceName + " is enabled", ($this.WebAppDetails.SiteConfig | Select-Object WebSocketsEnabled)));
        }
		else
        {
           $controlResult.AddMessage([VerificationResult]::Passed,
                                     [MessageData]::new("Web sockets for resource " + $this.ResourceContext.ResourceName + " is not enabled", ($this.WebAppDetails.SiteConfig | Select-Object WebSocketsEnabled)));
        }

      return $controlResult;
	}

    hidden [ControlResult] CheckAppServiceAlwaysOnConfiguration([ControlResult] $controlResult)
	{
		if($this.WebAppDetails.SiteConfig.AlwaysOn)
        {
           $controlResult.AddMessage([VerificationResult]::Passed,
                                     [MessageData]::new("Always On feature for resource " + $this.ResourceContext.ResourceName + " is enabled", ($this.WebAppDetails.SiteConfig | Select-Object AlwaysOn)));
        }
		else
        {
           $controlResult.AddMessage([VerificationResult]::Failed,
                                     [MessageData]::new("Always On feature for resource " + $this.ResourceContext.ResourceName + " is not enabled", ($this.WebAppDetails.SiteConfig | Select-Object AlwaysOn)));
        }

      return $controlResult;
    }

    hidden [ControlResult] CheckAppService64BitPlatformConfiguration([ControlResult] $controlResult)
	{
		if($this.WebAppDetails.SiteConfig.Use32BitWorkerProcess)
        {
			$controlResult.EnableFixControl = $true;
           $controlResult.AddMessage([VerificationResult]::Failed,
                                     [MessageData]::new("32-bit platform is used for resource " + $this.ResourceContext.ResourceName, ($this.WebAppDetails.SiteConfig | Select-Object Use32BitWorkerProcess)));
        }
		else
        {
           $controlResult.AddMessage([VerificationResult]::Passed,
                                     [MessageData]::new("64-bit platform is used for resource " + $this.ResourceContext.ResourceName, ($this.WebAppDetails.SiteConfig | Select-Object Use32BitWorkerProcess)));
        }

      return $controlResult;
    }

    hidden [ControlResult] CheckAppServiceDotNetFrameworkVersion([ControlResult] $controlResult)
	{
		$dotNetFrameworkVersion = $this.WebAppDetails.SiteConfig.NetFrameworkVersion
		$splitVersionNumber = $this.ControlSettings.AppService.LatestDotNetFrameworkVersionNumber.split(".")

		# Compare App Service Net Framework version with latest Net Framework version from configuration
		$isCompliant =  $dotNetFrameworkVersion.CompareTo($splitVersionNumber[0] + "." + $splitVersionNumber[1]) -eq 0

		if($isCompliant)
		{
			$controlResult.AddMessage([VerificationResult]::Passed,
										[MessageData]::new("Latest .Net Framework version is used for resource " + $this.ResourceContext.ResourceName, ($this.WebAppDetails.SiteConfig | Select-Object NetFrameworkVersion)));
		}
		else
		{
			$controlResult.EnableFixControl = $true;
			$controlResult.AddMessage([VerificationResult]::Failed,
										[MessageData]::new("Latest .Net Framework version is not used for resource " + $this.ResourceContext.ResourceName, ($this.WebAppDetails.SiteConfig | Select-Object NetFrameworkVersion)));
		}

		return $controlResult;
    }

    hidden [ControlResult] CheckAppServiceInstanceCount([ControlResult] $controlResult)
		{
			# Get number of instances
			$resource = Get-AzResource -ResourceId $this.ResourceObject.Properties.ServerFarmId
			if(($resource|Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($resource,"Sku"))
			{
				$sku = $resource.Sku
				if($sku.Capacity -ge $this.ControlSettings.AppService.Minimum_Instance_Count)
				{
					$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("SKU for resource " + $this.ResourceContext.ResourceName + " is :", $sku));
				}
				else
				{
					$controlResult.EnableFixControl = $true;
					$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("SKU for resource " + $this.ResourceContext.ResourceName + " is :", $sku));
				}
			}
			else
			{
					$controlResult.EnableFixControl = $true;
					$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Resource not found. Please verify that the app service exists."));
			}
			

      return $controlResult;
    }

    hidden [ControlResult] CheckAppServiceBackupConfiguration([ControlResult] $controlResult)
	{
		try
		{
			if($this.IsReaderRole)
			{
				#Setting this property ensures that this control result wont be considered for the central telemetry. As control doesnt have the required permissions
				$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
				$controlResult.AddMessage([VerificationResult]::Manual,
                                        [MessageData]::new("Control can not be validated due to insufficient access permission on resource"));
			}
			else
			{
				$backupConfiguration = Get-AzWebAppBackupConfiguration `
													-ResourceGroupName $this.ResourceContext.ResourceGroupName `
													-Name $this.ResourceContext.ResourceName `
													-ErrorAction Stop

				$isCompliant = $False
				If ($null -ne $backupConfiguration)
				{
					# Backup must be enabled and retention period days must be more than 365 and backup start date is less than current time (backup has been already started)
					# and at least one backup is available
					If($backupConfiguration.Enabled -eq $True -and `
					($backupConfiguration.RetentionPeriodInDays -eq $this.ControlSettings.AppService.Backup_RetentionPeriod_Forever -or $backupConfiguration.RetentionPeriodInDays -ge $this.ControlSettings.AppService.Backup_RetentionPeriod_Min) -and`
						$backupConfiguration.StartTime -le $(Get-Date) -and $backupConfiguration.KeepAtLeastOneBackup -eq $True)
					{
						$isCompliant = $True
					}
				}

				if(-not $isCompliant)
				{
					$controlResult.VerificationResult = [VerificationResult]::Failed;
					if($null -ne $backupConfiguration)
					{
						$controlResult.AddMessage([MessageData]::new("Configured backup for resource " + $this.ResourceContext.ResourceName + " is not as per the security guidelines. Please make sure that the configured backup is inline with below settings:-"));
						$controlResult.AddMessage([MessageData]::new("Enabled=True, StorageAccountEncryption=Enabled, RetentionPeriodInDays=0 or RetentionPeriodInDays>=" + $this.ControlSettings.AppService.Backup_RetentionPeriod_Min +", BackupStartTime<=CurrentTime, KeepAtLeastOneBackup=True", $backupConfiguration));
					}
					else
					{
						$controlResult.AddMessage([MessageData]::new("Backup for resource " + $this.ResourceContext.ResourceName + " is not configured", $backupConfiguration));
					}
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Passed,
										[MessageData]::new("Backup for resource " + $this.ResourceContext.ResourceName + " is enabled", $backupConfiguration));
				}
			}
			
		}
		catch
		{
			if(($_.Exception).Response.StatusCode.value__ -eq 404)
			{
					$controlResult.AddMessage([VerificationResult]::Failed,
										[MessageData]::new("Backup for resource " + $this.ResourceContext.ResourceName + " is not configured"));
			}
			else
			{
					throw $_
			}
        }

		return $controlResult;
    }

    hidden [ControlResult] CheckAppServiceDiagnosticLogsConfiguration([ControlResult] $controlResult)
	{
		$diagnosticLogsConfig = New-Object PSObject
		Add-Member -InputObject $diagnosticLogsConfig -MemberType NoteProperty -Name "HttpLoggingEnabled" -Value $this.WebAppDetails.SiteConfig.HttpLoggingEnabled
		Add-Member -InputObject $diagnosticLogsConfig -MemberType NoteProperty  -Name "DetailedErrorLoggingEnabled" -Value $this.WebAppDetails.SiteConfig.DetailedErrorLoggingEnabled
		Add-Member -InputObject $diagnosticLogsConfig -MemberType NoteProperty  -Name "RequestTracingEnabled" -Value $this.WebAppDetails.SiteConfig.RequestTracingEnabled

        $isCompliant =  $diagnosticLogsConfig.HttpLoggingEnabled -eq $true -and `
                        $diagnosticLogsConfig.DetailedErrorLoggingEnabled -eq $true -and `
                        $diagnosticLogsConfig.RequestTracingEnabled -eq $true

		if($isCompliant)
        {
           $controlResult.AddMessage([VerificationResult]::Passed,
                                     [MessageData]::new("Diagnostics logs for resource " + $this.ResourceContext.ResourceName + " are enabled", $diagnosticLogsConfig));
        }
		else
        {
			$controlResult.EnableFixControl = $true;
			$controlResult.AddMessage([VerificationResult]::Failed,
                                     [MessageData]::new("All configurations of diagnostics logs for resource " + $this.ResourceContext.ResourceName + " are not enabled", $diagnosticLogsConfig));
        }

		return $controlResult;
    }

    hidden [ControlResult] CheckAppServiceHttpCertificateSSL([ControlResult] $controlResult)
	{	
		
		$isHttpsEnabled = $this.ResourceObject.Properties.httpsOnly
		
		if($isHttpsEnabled)
		{
			$controlResult.VerificationResult = [VerificationResult]::Passed
		}
		else
		{
			$controlResult.EnableFixControl = $true;
			$controlResult.VerificationResult = [VerificationResult]::Failed
		}
		
	
		return $controlResult;
    }
    hidden [ControlResult] CheckFunctionsAppHttpCertificateSSL([ControlResult] $controlResult)
	{	
			if($this.IsReaderRole)
			{
				#Setting this property ensures that this control result wont be considered for the central telemetry. As control doesnt have the required permissions
				$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
				$controlResult.AddMessage([VerificationResult]::Manual,
                                [MessageData]::new("Control can not be validated due to insufficient access permission on resource"));
			}
			else
			{
				$ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
				$accessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
				$authorisationToken = "Bearer " + $accessToken
				$headers = @{"Authorization"=$authorisationToken;"Content-Type"="application/json"}
				if([Helpers]::CheckMember($this.WebAppDetails,"EnabledHostNames"))
				{
					if((($this.WebAppDetails.EnabledHostNames | where-object { $_.Contains('scm') }) | Measure-Object).Count -eq 1)
					{
						$scmURL = $this.WebAppDetails.EnabledHostNames | where-object { $_.Contains('scm') }
						$apiFunctionsUrl = [string]::Format("https://{0}/api/functions",$scmURL)
					}
					else
					{
						$temp = @($this.WebAppDetails.EnabledHostNames | where-object { $_.Contains('.azurewebsites.') })
						$AppURL = $this.FormatURL($temp[0])
						$apiFunctionsUrl = [string]::Format("https://{0}.scm.{1}/api/functions",$this.ResourceContext.ResourceName,$AppURL)
					}
			  }
				else
				{
					$temp = @($this.ResourceObject.Properties.HostNames | where-object { $_.Contains('.azurewebsites.') })
					$AppURL = $this.FormatURL($temp[0])
					$apiFunctionsUrl = [string]::Format("https://{0}.scm.{1}/api/functions",$this.ResourceContext.ResourceName,$AppURL)
				}
				try
				{
						
					$functionDetail = $null
					#$apiFunctionsUrl = [string]::Format("https://{0}.scm.azurewebsites.net/api/functions",$this.ResourceContext.ResourceName)
					if( [FeatureFlightingManager]::GetFeatureStatus("UseAzCommandForFunctionAppDetails",$($this.SubscriptionContext.SubscriptionId)) -eq $true)
					{
						$functionAppDetails = Get-AzResource -ResourceGroupName $this.ResourceContext.ResourceGroupName -ResourceName $this.ResourceContext.ResourceName -ResourceType 'Microsoft.Web/sites/functions' -ApiVersion '2015-08-01' -ErrorAction SilentlyContinue
						if($null -ne $functionAppDetails -and [Helpers]::CheckMember($functionAppDetails,"Properties"))
						{
							$functionDetail = $functionAppDetails | ForEach-Object{ $_.Properties } 
						}
					}else{
						$functionDetail = [WebRequestHelper]::InvokeGetWebRequest($apiFunctionsUrl, $headers)
					}
					
						#check if functions are present in FunctionApp	
						if($null -ne $functionDetail -and [Helpers]::CheckMember($functionDetail,"config"))
						{
							$bindingsDetail =$functionDetail.config.bindings
								$ishttpTriggerFunction=$false
							if(($bindingsDetail| Measure-Object).Count -gt 0)
							{
							$bindingsDetail |	 ForEach-Object{
								if($_.type -eq "httpTrigger" )
								{
									$ishttpTriggerFunction=$true
								}
							}
							#if HTTP trigger function is not present, then Http check is not required
							if(!$ishttpTriggerFunction)
								{

								$controlResult.AddMessage([VerificationResult]::Passed,
									[MessageData]::new("Enabling 'HttpsOnly' is not required for resource " + $this.ResourceContext.ResourceName + "."));
							
							}
							else
								{
									$isHttpsEnabled = $this.ResourceObject.Properties.httpsOnly
									if($isHttpsEnabled)
											{
													$controlResult.VerificationResult = [VerificationResult]::Passed
											}
									else
											{
													$controlResult.VerificationResult = [VerificationResult]::Failed
											}
								}

						
						}
				
						}
						#if no function is present in Functions App, then Http check is not required
						else
						{
							$controlResult.AddMessage([VerificationResult]::Passed,
									[MessageData]::new("Enabling 'HttpsOnly' is not required for this resource " + $this.ResourceContext.ResourceName + "."));
						}
				}
				catch
				{
					$controlResult.AddMessage([VerificationResult]::Manual,
									[MessageData]::new("Unable to fetch details of functions."));
							
				}
		
	  	}
		return $controlResult;
    	
	}

    hidden [ControlResult] CheckAppServiceLoadCertAppSettings([ControlResult] $controlResult)
	{
		if($this.IsReaderRole)
		{
			$controlResult.AddMessage([VerificationResult]::Manual,
                                        [MessageData]::new("Control can not be validated due to insufficient access permission on resource"));
		}
		else
		{
			$appSettings = $this.WebAppDetails.SiteConfig.AppSettings
	   		$appSettingParameterList = $null

			if(($appSettings| Measure-Object).Count -gt 0)
			{
				$appSettingParameterList = $appSettings | Where-Object { $_.Name -eq $this.ControlSettings.AppService.LoadCertAppSettings -and $_.Value -eq "*"}
			}

			if($null -ne $appSettingParameterList)
			{
			   $controlResult.AddMessage([VerificationResult]::Failed,
										 [MessageData]::new("'WEBSITE_LOAD_CERTIFICATES' parameter defined equal to '*' is found in App Settings for resource " + $this.ResourceContext.ResourceName));
			}
			else
			{
			   $controlResult.AddMessage([VerificationResult]::Passed,
										 [MessageData]::new("'WEBSITE_LOAD_CERTIFICATES' parameter defined equal to '*' is not found in App Settings for resource " + $this.ResourceContext.ResourceName));
			}
		}
		return $controlResult;
    }

	hidden [ControlResult] CheckFunctionsEditMode([ControlResult] $controlResult)
	{
		
			$appSettings = $this.WebAppDetails.SiteConfig.AppSettings
			$appEditMode = $null

			if(($appSettings| Measure-Object).Count -gt 0)
			{
				$appEditMode = $appSettings | Where-Object { $_.Name -eq "FUNCTION_APP_EDIT_MODE" }
			}

			if($null -eq $appEditMode){
				$controlResult.AddMessage([VerificationResult]::Verify,
				[MessageData]::new("Verify that Functions app edit mode should be defined as 'readonly' for resource " + $this.ResourceContext.ResourceName));
			}
			elseif($appEditMode.Value -eq "readonly")
			{
			   $controlResult.AddMessage([VerificationResult]::Passed,
										 [MessageData]::new("Functions app edit mode is defined as 'readonly' for resource " + $this.ResourceContext.ResourceName));
			}
			else
			{
			   $controlResult.AddMessage([VerificationResult]::Failed,
										 [MessageData]::new("Functions app edit mode is defined as 'readwrite' for resource " + $this.ResourceContext.ResourceName));
			}
		return $controlResult;
    }
	
	hidden [ControlResult] CheckFunctionsAuthorizationLevel([ControlResult] $controlResult)
	{
		if($this.IsReaderRole)
		{
			#Setting this property ensures that this control result wont be considered for the central telemetry. As control doesnt have the required permissions
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual,
                                    [MessageData]::new("Control can not be validated due to insufficient access permission on resource"));
		}
		elseif([Helpers]::CheckMember($this.WebAppDetails,"State") -and ($this.WebAppDetails.State -eq "Stopped"))
		{
			$controlResult.AddMessage([VerificationResult]::Manual,
                                    [MessageData]::new("Control can not be validated as the resource is in 'Stopped' state."));
		}
		else
		{
		$ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
		$accessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
		$authorisationToken = "Bearer " + $accessToken
		$headers = @{"Authorization"=$authorisationToken;"Content-Type"="application/json"}
		if([Helpers]::CheckMember($this.WebAppDetails,"EnabledHostNames"))
		{
			if((($this.WebAppDetails.EnabledHostNames | where-object { $_.Contains('scm') }) | Measure-Object).Count -eq 1)
			{
				$scmURL = $this.WebAppDetails.EnabledHostNames | where-object { $_.Contains('scm') }
				$apiFunctionsUrl = [string]::Format("https://{0}/api/functions",$scmURL)
			}
			else
			{
				$temp = @($this.WebAppDetails.EnabledHostNames | where-object { $_.Contains('.azurewebsites.') })
				$AppURL = $this.FormatURL($temp[0])
				$apiFunctionsUrl = [string]::Format("https://{0}.scm.{1}/api/functions",$this.ResourceContext.ResourceName,$AppURL)
			}
		}
		else
		{
			$temp = @($this.ResourceObject.Properties.HostNames | where-object { $_.Contains('.azurewebsites.') })
			$AppURL = $this.FormatURL($temp[0])
			$apiFunctionsUrl = [string]::Format("https://{0}.scm.{1}/api/functions",$this.ResourceContext.ResourceName,$AppURL)
		}
		$functionDetail = $null
		#$apiFunctionsUrl = [string]::Format("https://{0}.scm.azurewebsites.net/api/functions",$this.ResourceContext.ResourceName)
		if([FeatureFlightingManager]::GetFeatureStatus("UseAzCommandForFunctionAppDetails",$($this.SubscriptionContext.SubscriptionId)) -eq $true)
    {
			$functionAppDetails = Get-AzResource -ResourceGroupName $this.ResourceContext.ResourceGroupName -ResourceName $this.ResourceContext.ResourceName -ResourceType 'Microsoft.Web/sites/functions' -ApiVersion '2015-08-01' -ErrorAction SilentlyContinue
			if($null -ne $functionAppDetails -and [Helpers]::CheckMember($functionAppDetails,"Properties"))
			{
				$functionDetail = $functionAppDetails | ForEach-Object{ $_.Properties } 
			}
    }else{
			$functionDetail = [WebRequestHelper]::InvokeGetWebRequest($apiFunctionsUrl, $headers)
		}
		#check if functions are present in FunctionApp	
		if($null -ne $functionDetail -and [Helpers]::CheckMember($functionDetail,"config"))
		{
		$bindingsDetail =$functionDetail.config.bindings
			$authorizationLevel = $null

		if(($bindingsDetail| Measure-Object).Count -gt 0)
		{
			$bindingsDetail |	 ForEach-Object{
			if($_.type -eq "httpTrigger" )
					{
					if([Helpers]::CheckMember($_,"authLevel"))
						{
								if($_.authLevel -ne 'function')
							{
								$authorizationLevel=$_.authLevel
							}
						} 
					}
			}
		}
		
		if($null -ne $authorizationLevel)
		{
				$controlResult.AddMessage([VerificationResult]::Failed,
										[MessageData]::new("Authorization level for all functions in a Functions app is not defined as 'Function' for resource " + $this.ResourceContext.ResourceName));
		}
		else
		{
				$controlResult.AddMessage([VerificationResult]::Passed,
										[MessageData]::new("Authorization level for all functions in a Functions app is defined as 'Function' for resource  " + $this.ResourceContext.ResourceName));
		}
		}
		else
		{
				$controlResult.AddMessage([VerificationResult]::Passed,
										[MessageData]::new("No functions are found in Functions app resource  " + $this.ResourceContext.ResourceName));
		}
		}
		return $controlResult;
    }
	  hidden [ControlResult] CheckAppServiceCORSAllowed([ControlResult] $controlResult)
	{
		if($this.IsReaderRole)
		{
			$controlResult.AddMessage([VerificationResult]::Manual,
                                        [MessageData]::new("Control can not be validated due to insufficient access permission on resource"));
		}
		else
		{
             $corsSettings=$this.WebAppDetails.SiteConfig.Cors
			if([Helpers]::CheckMember($corsSettings,"AllowedOrigins") -and ($corsSettings.AllowedOrigins | Measure-Object).Count -ne 0)
			{
			 
		       if($corsSettings.AllowedOrigins.Contains("*"))
			   {
					$controlResult.AddMessage([VerificationResult]::Failed,
						[MessageData]::new("CORS is enabled in app service with access from all domains ('*') " + $this.ResourceContext.ResourceName, $corsSettings.AllowedOrigins));
				    $controlResult.SetStateData("CORS setting Allowed Origins",$corsSettings.AllowedOrigins);
			   }
			   else
			   {
					$controlResult.AddMessage([VerificationResult]::Verify,
						[MessageData]::new("CORS is enabled in app service with access from custom domains " , $corsSettings.AllowedOrigins));
				    $controlResult.SetStateData("CORS setting Allowed Origins",$corsSettings.AllowedOrigins);
			   
			   }
			}
			else 
			{	
				$controlResult.AddMessage([VerificationResult]::Manual,
                                      [MessageData]::new("No CORS settings found for "+$this.ResourceContext.ResourceName));	   
			}
			
		}
		return $controlResult;
    }
    hidden [ControlResult] CheckAppServiceMsiEnabled([ControlResult] $controlResult)
	  {
	     if($this.IsReaderRole)
		{
			$controlResult.AddMessage([VerificationResult]::Manual,
                                        [MessageData]::new("Control can not be validated due to insufficient access permission on resource"));
		}
		else
		{
			$appSettings = $this.WebAppDetails.SiteConfig.AppSettings
	   		$msiObject = $null

			if(($appSettings| Measure-Object).Count -gt 0)
			{
				$msiObject = $appSettings | Where-Object { $_.Name -eq "WEBSITE_DISABLE_MSI"}
			}

			if($msiObject -eq $null)
			{	
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()			
			  $uri=[system.string]::Format($ResourceAppIdURI+"subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Web/sites/{2}?api-version=2016-08-01",$this.SubscriptionContext.SubscriptionId,$this.ResourceContext.ResourceGroupName,$this.ResourceContext.ResourceName)
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
			     if(([Helpers]::CheckMember($json[0],"Identity")) -and ($json[0].Identity.type -eq "SystemAssigned" -or $json[0].Identity.type -eq "UserAssigned"))
                 		{                  
                    		 $controlResult.AddMessage([VerificationResult]::Passed,
                                 [MessageData]::new("Your app service is using Managed Service Identity (MSI). It is specifically turned on. Make sure this MSI identity is used to access the resources."));
                  		}
                	     else
                 	        {
                  		 $controlResult.AddMessage([VerificationResult]::Failed,
                                 [MessageData]::new("Your app service is not using Managed Service Identity(MSI). It is specifically turned Off."));
                 		}
			  }
			  else
			  {
			     $controlResult.AddMessage([VerificationResult]::Verify,
										 [MessageData]::new("Unable to validate control.Please verify from portal, Managed Service Identity(MSI) is On or Off."));
			  }
			}
			elseif($msiObject.Value -eq "false")
			{
			    $controlResult.AddMessage([VerificationResult]::Verify,
										 [MessageData]::new("Your app service is using Managed Service Identity(MSI). Found the value below in the app settings",$msiObject));
				$controlResult.SetStateData("Managed Service Identity Settings",$msiObject);
			}
			else
			{
			   $controlResult.AddMessage([VerificationResult]::Verify,
										 [MessageData]::new("Your app service is not using Managed Service Identity(MSI). It is specifically turned Off. Found the value below in the app settings",$msiObject));
			   $controlResult.SetStateData("Managed Service Identity Settings",$msiObject);
			}
		}
		return $controlResult;
    }
		 
		hidden [ControlResult] CheckAppServiceTLSVersion([ControlResult] $controlResult)
		{	
				$requiredVersion = [System.Version] $this.ControlSettings.AppService.TLS_Version
	
        if($null -ne $this.SiteConfigs -and [Helpers]::CheckMember($this.SiteConfigs.Properties,"minTlsVersion")){
					  $minTlsVersion = [System.Version]	$this.SiteConfigs.Properties.minTlsVersion
						if($minTlsVersion -ge $requiredVersion)
						{
							$controlResult.VerificationResult = [VerificationResult]::Passed
						}
						else
						{
							$controlResult.VerificationResult = [VerificationResult]::Failed
							$controlResult.AddMessage("Current Minimum TLS Version: $($minTlsVersion), Required Minimum TLS Version: $($requiredVersion)");
							$controlResult.SetStateData("Current Minimum TLS Version",$minTlsVersion.ToString());
						}
				}else{
						$controlResult.VerificationResult = [VerificationResult]::Manual
						$controlResult.AddMessage("Unable to fetch TLS settings.");
				}
				return $controlResult;
		}

		hidden [ControlResult] CheckAppServiceInstalledExtensions([ControlResult] $controlResult)
		{	
			  try{
					$installedExtensions = Get-AzResource -ResourceGroupName $this.ResourceContext.ResourceGroupName -ResourceType Microsoft.Web/sites/siteextensions -ResourceName $this.ResourceContext.ResourceName -ApiVersion 2018-02-01 -ErrorAction silentlycontinue
				}
				catch{
					$installedExtensions = $null
				}
				if($installedExtensions -ne $null -and ($installedExtensions | Measure-Object).Count -gt 0)
				{
					$extensions = $installedExtensions | Select-Object "Name", "ResourceId"
					$controlResult.AddMessage([VerificationResult]::Verify,
					[MessageData]::new("Following extensions are installed on resource:",$installedExtensions));
          $controlResult.SetStateData("Installed extensions",$extensions);
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Passed,[MessageData]::new("No extension is installed on resource " +$this.ResourceContext.ResourceName));
					
				}
				return $controlResult;
		}

		hidden [ControlResult] CheckAppServiceAccessRestriction([ControlResult] $controlResult)
		{	
				$ipSecurityRestrictions = $false
				$scmIpSecurityRestrictions = 	$false
				$controlResult.VerificationResult = [VerificationResult]::Verify
				$scmIpSecurityRestrictionsUseMain = $this.SiteConfigs.Properties.scmIpSecurityRestrictionsUseMain
				# Check IP restrictions for main website
				if($null -eq $this.SiteConfigs.Properties.ipSecurityRestrictions){
					$controlResult.AddMessage("IP rule based access restriction is not set up for app: " +$this.ResourceContext.ResourceName);
				}else{
					$ipSecurityRestrictions = $true
					$controlResult.AddMessage("Following IP rule based access restriction is cofigured for app: "+$this.ResourceContext.ResourceName);
					$controlResult.AddMessage($this.SiteConfigs.Properties.ipSecurityRestrictions);
				}
				# Check IP restrictions for scm website
				if($scmIpSecurityRestrictionsUseMain -eq $true){
					$scmIpSecurityRestrictions = $ipSecurityRestrictions
					$controlResult.AddMessage("IP based access restriction rules are same for both scm site and main app.");
				}elseif($null -eq $this.SiteConfigs.Properties.scmIpSecurityRestrictions){
					$scmIpSecurityRestrictions = 	$false
					$controlResult.AddMessage("IP based access restriction is not set up for scm site used by app.");
				}else{
					$ipSecurityRestrictions = $true
					$controlResult.AddMessage("Following IP based access restriction is configured for scm site used by app:");
					$controlResult.AddMessage($this.SiteConfigs.Properties.scmIpSecurityRestrictions);
				}
				return $controlResult;
		}

		hidden [ControlResult] CheckAppServiceCORSCredential([ControlResult] $controlResult)
		{	
				$supportCredentials = $false
				$controlResult.VerificationResult = [VerificationResult]::Verify
				if($null -ne $this.SiteConfigs -and [Helpers]::CheckMember( $this.SiteConfigs.Properties,"cors.supportCredentials") -and $this.SiteConfigs.Properties.cors.supportCredentials){
					 $supportCredentials = $true	
					 $controlResult.AddMessage("CORS Response header 'Access-Control-Allow-Credentials' is enabled for resource.");
				}else{
				   $controlResult.VerificationResult = [VerificationResult]::Passed
				   $controlResult.AddMessage("CORS Response header 'Access-Control-Allow-Credentials' is disabled for resource.");
				}
				$controlResult.SetStateData("Response header 'Access-Control-Allow-Credentials' is set to: ",$supportCredentials);
				return $controlResult;
		}

}
