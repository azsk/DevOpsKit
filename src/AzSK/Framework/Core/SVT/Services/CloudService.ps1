
#
# CloudServices.ps1
#
Set-StrictMode -Version Latest 
class CloudService: SVTBase
{
	hidden [PSCloudService] $ResourceObject;
	hidden [bool] $hasClassicPermissions = $true;
	hidden [string] $cloudServiceAPIVersion = "2016-04-01"


	CloudService([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
        $this.GetResourceObject();
    }

	CloudService([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {          
			$this.UpdateCloudServiceInstance()            
        }

        return $this.ResourceObject;
    }

	[ControlItem[]] ApplyServiceFilters([ControlItem[]] $controls)
	{
		if($null -ne $this.ResourceObject -and ( $this.ResourceObject.DeploymentSlots | Measure-Object).Count -gt 0)
		{
			# ignoring "VirtualMachine" slot in cloud service as it contains only classic VM roles.
			$this.ResourceObject.DeploymentSlots = $this.ResourceObject.DeploymentSlots | Where-Object { $_.SlotType -ne "VirtualMachine" }
		}
		
		return $controls;
	}

	hidden [void] UpdateCloudServiceInstance()
	{
		#step 1: load data from ARM model
		$this.ResourceObject = [PSCloudService]::new($this.ResourceContext.ResourceName, $this.ResourceContext.ResourceGroupName)
		$this.ResourceObject.LoadCloudConfiguration();

		#step 2: load from classic config model
		try
		{		
			$ResourceAppIdURI = [WebRequestHelper]::ClassicManagementUri;
			$ClassicAccessToken = [Helpers]::GetAccessToken($ResourceAppIdURI)
			if($null -ne $ClassicAccessToken) 
			{
				$header = "Bearer " + $ClassicAccessToken
				$headers = @{"Authorization"=$header;"Content-Type"="application/json"; "x-ms-version" ="2013-08-01"}
				$uri = [string]::Format("{0}/{1}/services/hostedservices/{2}?embed-detail=true","https://management.core.windows.net", $this.SubscriptionContext.SubscriptionId ,$this.ResourceContext.ResourceName)        
				$cloudServiceResponse = Invoke-WebRequest -Method GET -Uri $uri -Headers $headers
				if($cloudServiceResponse.StatusCode -ge 200 -and $cloudServiceResponse.StatusCode -le 399)
				{			 
					if($null -ne $cloudServiceResponse.Content)
					{				
						[xml] $cloudService = $cloudServiceResponse.Content
						$this.ResourceObject.LoadCloudConfigurationFromClassicConfig($cloudServiceResponse.Content);
					}
				}			
			}
		}
		catch
		{
			$this.hasClassicPermissions = $false;
		}
	}

	hidden [ControlResult] CheckCloudServiceHttpCertificateSSLOnInstanceEndpoints([ControlResult] $controlResult)
	{
		if($this.hasClassicPermissions)
		{
			$isCompliant = $true;
			$nonCompliantInstanceEndpoints = @();
			if($null -ne $this.ResourceObject -and $null -ne $this.ResourceObject.RoleInstances -and ($this.ResourceObject.RoleInstances | Measure-Object).Count -gt 0)
			{
				$this.ResourceObject.RoleInstances | Foreach-Object{
					$roleInstance = $_;
					if($null -ne $roleInstance -and ($roleInstance.InstanceEndpoints | Measure-Object).Count -gt 0)
					{
						$roleInstance.InstanceEndpoints | ForEach-Object {
							$instanceEndpoint = $_
							if($instanceEndpoint.Protocol -eq "http")
							{
								$isCompliant = $false;
								$nonCompliantInstanceEndpoints += $_
							}
						}
					}
				}
			}
			if($isCompliant)
			{
				$controlResult.VerificationResult = [VerificationResult]::Passed;
			}
			else
			{
				#$controlResult.AddMessage([VerificationResult]::Failed,  "Instance endpoints of cloud service must have http disabled.",$nonCompliantInstanceEndpoints, $true, "InstanceEndpoints");
				$controlResult.AddMessage([VerificationResult]::Failed,  "Instance endpoints of cloud service must have http disabled.",$nonCompliantInstanceEndpoints);
			}   
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Manual,  "Don't have the required permissions to scan the cloud service.");
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckCloudServiceHttpCertificateSSLOnInputEndpoints([ControlResult] $controlResult)
	{		
		$InputEndpoints = @();
		if($null -ne $this.ResourceObject -and $null -ne $this.ResourceObject.DeploymentSlots)
		{
			$this.ResourceObject.DeploymentSlots | ForEach-Object {
				$DeploymentSlot = $_;
				if($null -ne $DeploymentSlot -and $null -ne $DeploymentSlot.Roles)
				{
					$DeploymentSlot.Roles | ForEach-Object {
						$Role = $_;
						if($null -ne $Role.InputEndpoints)
						{
							$Role.InputEndpoints | ForEach-Object {
								$inpEp = $_;
								$inputEndpoint = "" | Select-Object SlotName, RoleName, PublicIpAddress, PrivatePort, PublicPort, Protocol, VirtualIpName, IsCompliant
								$inputEndpoint.SlotName = $DeploymentSlot.SlotName;
								$inputEndpoint.RoleName = $Role.RoleName;		
								$inputEndpoint.PublicIpAddress = $inpEp.PublicIpAddress;		
								$inputEndpoint.PrivatePort = $inpEp.PrivatePort;		
								$inputEndpoint.PublicPort = $inpEp.PublicPort;		
								$inputEndpoint.Protocol = $inpEp.Protocol;		
								$inputEndpoint.VirtualIpName = $inpEp.VirtualIpName;	
								$inputEndpoint.IsCompliant = "False"
								if($inpEp.protocol -ne "http")
								{
									$inputEndpoint.IsCompliant = "True"
								}
								$InputEndpoints += $inputEndpoint
							}
						}
					}
				}
			}
		}
		
		$nonCompliantEP = ($InputEndpoints | Where-Object { $_.IsCompliant -eq "False"})
		if(($nonCompliantEP | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage([VerificationResult]::Failed,  "There are active non SSL enabled input endpoints.", $nonCompliantEP);				
			#$controlResult.SetStateData("Active non SSL enabled input endpoints", $nonCompliantEP);
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed,  "There are no active non SSL enabled input endpoints.", $InputEndpoints);				
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckCloudServiceInstanceEndpoints([ControlResult] $controlResult)
	{
		if($this.hasClassicPermissions)
		{			
			$instanceEndpoints = @();
			if($null -ne $this.ResourceObject -and $null -ne $this.ResourceObject.DeploymentSlots)
			{
				$this.ResourceObject.DeploymentSlots | ForEach-Object {
					$DeploymentSlot = $_;
					if($null -ne $DeploymentSlot -and $null -ne $DeploymentSlot.Roles)
					{
						$DeploymentSlot.Roles | ForEach-Object {
							$Role = $_;
							if($null -ne $Role.RoleInstances -and ($Role.RoleInstances | Measure-Object).Count -gt 0)
							{
								$Role.RoleInstances | ForEach-Object {
									$instanceEndpoints += $_
								}
							}
						}
					}
				}
			}
			#$controlResult.AddMessage([VerificationResult]::Verify,  "Validate the IP Settings configured for the instance endpoints on cloud service.", $instanceEndpoints, $true, "InstanceEndpoints" );
			$controlResult.AddMessage([VerificationResult]::Verify,  "Validate the IP Settings configured for the instance endpoints on cloud service.", $instanceEndpoints);
		}
		else
		{
			#Setting this property ensures that this control result wont be considered for the central telemetry. As control doesn't have the required permissions
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual, "You do not have required permissions to check for internal endpoints on this cloud service. This control requires 'Co-Admin' privilege.");	
			$controlResult.AddMessage([MessageData]::new([Constants]::CoAdminElevatePermissionMsg));
			
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckCloudServiceInputEndpoints([ControlResult] $controlResult)
	{
		$InputEndpoints = @();
		if($null -ne $this.ResourceObject -and $null -ne $this.ResourceObject.DeploymentSlots)
		{
			$this.ResourceObject.DeploymentSlots | ForEach-Object {
				$DeploymentSlot = $_;
				if($null -ne $DeploymentSlot -and $null -ne $DeploymentSlot.Roles)
				{
					$DeploymentSlot.Roles | ForEach-Object {
						$Role = $_;
						if($null -ne $Role.InputEndpoints)
						{
							$Role.InputEndpoints | ForEach-Object {
								$InputEndpoints += $_
							}
						}
					}
				}
			}
		}
		#$controlResult.AddMessage([VerificationResult]::Verify,  "Remove any un-used internal endpoints from your cloud service.", $inputEndpoints, $true, "InputEndpoints" );
		$controlResult.AddMessage([VerificationResult]::Verify,  "Remove any un-used input endpoints from your cloud service.", $InputEndpoints);
		return $controlResult;
	}

	hidden [ControlResult] CheckCloudServiceRemoteDebuggingStatus([ControlResult] $controlResult)
	{
		if($this.hasClassicPermissions)
		{
			$isCompliant = $true;
			$nonCompliantInstanceEndpoints = @();
			if($null -ne $this.ResourceObject -and $null -ne $this.ResourceObject.DeploymentSlots)
			{
				$this.ResourceObject.DeploymentSlots | ForEach-Object {
					$DeploymentSlot = $_;
					if($null -ne $DeploymentSlot -and $null -ne $DeploymentSlot.Roles)
					{
						$DeploymentSlot.Roles | ForEach-Object {
							$Role = $_;
							if($null -ne $Role.RoleInstances -and ($Role.RoleInstances | Measure-Object).Count -gt 0)
							{
								$Role.RoleInstances | ForEach-Object {
									$roleInstance = $_;
									if($null -ne $roleInstance -and ($roleInstance.InstanceEndpoints | Measure-Object).Count -gt 0)
									{
										$roleInstance.InstanceEndpoints | ForEach-Object {
											$instanceEndpoint = $_
											if($instanceEndpoint.Name -like "Microsoft.WindowsAzure.Plugins.RemoteDebugger*")
											{
												$isCompliant = $false;
												$nonCompliantInstanceEndpoints += $_
											}
										}
									}
								}
							}
						}
					}
				}
			}			

			if($isCompliant)
			{
				$controlResult.VerificationResult = [VerificationResult]::Passed;
			}
			else
			{
				#$controlResult.AddMessage([VerificationResult]::Failed,  "Remote debugging endpoints enabled on cloud service.", $nonCompliantInstanceEndpoints, $true, "InstanceEndpoints");
				$controlResult.AddMessage([VerificationResult]::Failed,  "Remote debugging endpoints enabled on cloud service.", $nonCompliantInstanceEndpoints);
			}   
		}
		else
		{
			#Setting this property ensures that this control result wont be considered for the central telemetry. As control doesn't have the required permissions
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual, "You do not have required permissions to check for remote debugging on this cloud service. This control requires 'Co-Admin' privilege.");	
			$controlResult.AddMessage([MessageData]::new([Constants]::CoAdminElevatePermissionMsg));		
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckCloudServiceAntiMalwareStatus([ControlResult] $controlResult)
	{
		if($this.hasClassicPermissions)
		{
			$isCompliant = $false;
			$extensions = @{};
			if($null -ne $this.ResourceObject -and $null -ne $this.ResourceObject.DeploymentSlots)
			{
				$this.ResourceObject.DeploymentSlots | ForEach-Object {
					$DeploymentSlot = $_;
					if($null -ne $DeploymentSlot -and $null -ne $DeploymentSlot.Roles)
					{
						$DeploymentSlot.Roles | ForEach-Object {
							$Role = $_;
							if($null -ne $Role.Extensions)
							{
								$Role.Extensions | ForEach-Object {
									$extension = $_;
									$extensions.Add($DeploymentSlot.SlotName + "->" + $extension.RoleName,"Disabled");
									if($null -ne $extension -and $null -ne $extension.ExtensionId)
									{
										$extension.ExtensionId | ForEach-Object {
											$extensionId = $_
											if($extensionId.Id -like "*Antimalware*")
											{
												$extensions[$DeploymentSlot.SlotName + "->" + $extension.RoleName] = "Enabled"
											}
										}
									}
								}
							}
						}
					}
				}
			}			

			if($extensions.Count -gt 0)
			{
				if(($extensions.Values | Where-Object { $_ -eq "Disabled"} | Measure-Object).Count -le 0)
				{
					$controlResult.VerificationResult = [VerificationResult]::Passed;
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Failed,  "Antimalware extension is not enabled on cloud service.", $extensions);
				}
			}
			else
			{
				$controlResult.VerificationResult = [VerificationResult]::Passed;
			}
		}
		else
		{
			#Setting this property ensures that this control result wont be considered for the central telemetry. As control doesn't have the required permissions
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual, "You do not have required permissions to check for antimalware extension on this cloud service. This control requires 'Co-Admin' privilege.");	
			$controlResult.AddMessage([MessageData]::new([Constants]::CoAdminElevatePermissionMsg));		
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckCloudServiceOSPatchStatus([ControlResult] $controlResult)
	{
		$OSPatchVersions = @();
		$isCompliant = $true;
		if($null -ne $this.ResourceObject -and $null -ne $this.ResourceObject.DeploymentSlots)
		{
			$this.ResourceObject.DeploymentSlots | ForEach-Object {
				$DeploymentSlot = $_;
				if(-not $DeploymentSlot.IsOSAutoUpdateTurnedOn)
				{
					$isCompliant = $false;
				}
			}
		}
		
		if(-not $isCompliant)
		{
			$controlResult.AddMessage([VerificationResult]::Failed,  "Cloud service is not set up for automatic OS updates.");				
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed,  "Cloud service is enabled with automatic OS updates");				
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckCloudServiceRemoteDesktopAccess([ControlResult] $controlResult)
	{
		if($this.hasClassicPermissions)
		{
			$extensions = @{};
			if($null -ne $this.ResourceObject -and $null -ne $this.ResourceObject.DeploymentSlots)
			{
				$this.ResourceObject.DeploymentSlots | ForEach-Object {
					$DeploymentSlot = $_;
					if($null -ne $DeploymentSlot -and $null -ne $DeploymentSlot.Roles)
					{
						$DeploymentSlot.Roles | ForEach-Object {
							$Role = $_;
							if($null -ne $Role.Extensions)
							{
								$Role.Extensions | ForEach-Object {
									$extension = $_;
									$extensions.Add($DeploymentSlot.SlotName + "->" + $extension.RoleName,"Disabled");
									if($null -ne $extension -and $null -ne $extension.ExtensionId)
									{
										$extension.ExtensionId | ForEach-Object {
											$extensionId = $_
											if($extensionId.Id -like "*RDP*")
											{
												$extensions[$DeploymentSlot.SlotName + "->" + $extension.RoleName] = "Enabled"
											}
										}
									}
								}
							}
						}
					}
				}
			}			

			if($extensions.Count -gt 0)
			{
				if(($extensions.Values | Where-Object { $_ -eq "Enabled"} | Measure-Object).Count -le 0)
				{
					$isCompliant = $true;
				}
				else
				{
					$isCompliant = $false;
					$controlResult.AddMessage("Remote desktop endpoints are enabled on cloud service.", $extensions);
				}
			}
			else
			{
				$isCompliant = $true;
			} 
			#$b.ServiceConfiguration.Role[0].ConfigurationSettings.Setting.SyncRoot["Microsoft.WindowsAzure.Plugins.RemoteAccess.Enabled"]
			$nonCompliantInstanceEndpoints = @();
			if($isCompliant)
			{
				if($null -ne $this.ResourceObject -and ($this.ResourceObject.DeploymentSlots | Measure-Object).Count -gt 0)
				{
					$this.ResourceObject.DeploymentSlots | ForEach-Object {
						$DeploymentSlot = $_;
						if($null -ne $DeploymentSlot -and ($DeploymentSlot.Roles| Measure-Object).Count -gt 0)
						{
							$DeploymentSlot.Roles | ForEach-Object {
								$Role = $_;
								if(($Role.RoleInstances | Measure-Object).Count -gt 0)
								{
									$Role.RoleInstances | ForEach-Object {
										$roleInstance = $_;
										if($null -ne $roleInstance -and ($roleInstance.InstanceEndpoints | Measure-Object).Count -gt 0)
										{
											$roleInstance.InstanceEndpoints | ForEach-Object {
												$instanceEndpoint = $_
												if($instanceEndpoint.Name -like "Microsoft.WindowsAzure.Plugins.RemoteForwarder*")
												{
													$isCompliant = $false;
													$nonCompliantInstanceEndpoints += $_
												}
											}
										}
									}
								}
							}
						}
					}
				}				
			}			

			if($isCompliant)
			{
				$controlResult.VerificationResult = [VerificationResult]::Passed;
			}
			else
			{
				$controlResult.VerificationResult = [VerificationResult]::Failed;
				$controlResult.AddMessage("Found RemoteForwarder endpoint configured for your Cloud Service. This endpoint has to be removed from the configuration.", $nonCompliantInstanceEndpoints);
			}   
		}
		else
		{
			#Setting this property ensures that this control result wont be considered for the central telemetry. As control doesn't have the required permissions
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.AddMessage([VerificationResult]::Manual, "You do not have required permissions to check for Remote Desktop (RDP) access on this cloud service. This control requires 'Co-Admin' privilege.");	
			$controlResult.AddMessage([MessageData]::new([Constants]::CoAdminElevatePermissionMsg));		
		}
		return $controlResult;
	}
}
