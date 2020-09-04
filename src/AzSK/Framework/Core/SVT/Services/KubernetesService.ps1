Set-StrictMode -Version Latest 
class KubernetesService: AzSVTBase
{
	hidden [PSObject] $ResourceObject;

	KubernetesService([string] $subscriptionId, [SVTResource] $svtResource): 
	Base($subscriptionId, $svtResource) 
 { 
		$this.GetResourceObject();
	}

	hidden [PSObject] GetResourceObject()
 {
		if (-not $this.ResourceObject) 
		{
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl();
			$AccessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
			if ($null -ne $AccessToken)
			{

				$header = "Bearer " + $AccessToken
				$headers = @{"Authorization" = $header; "Content-Type" = "application/json"; }

				$uri = [system.string]::Format("{0}subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.ContainerService/managedClusters/{3}?api-version=2020-06-01", $ResourceAppIdURI, $this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName)
				$result = ""
				$err = $null
				try
				{
					$propertiesToReplace = @{}
					$propertiesToReplace.Add("httpapplicationroutingzonename", "_httpapplicationroutingzonename")
					$result = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $headers, $null, $null, $propertiesToReplace); 
					if (($null -ne $result) -and (($result | Measure-Object).Count -gt 0))
					{
						$this.ResourceObject = $result[0]
					}
				}
				catch
				{
					$err = $_
					if ($null -ne $err)
					{
						throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
					}
				}
			}
		}
		return $this.ResourceObject;
	}

	hidden [controlresult[]] CheckClusterRBAC([controlresult] $controlresult)
	{
		if ([Helpers]::CheckMember($this.ResourceObject, "Properties"))
		{
			if ([Helpers]::CheckMember($this.ResourceObject.Properties, "enableRBAC") -and $this.ResourceObject.Properties.enableRBAC)
			{
				$controlResult.VerificationResult = [VerificationResult]::Passed
			}
			else
			{
				$controlResult.VerificationResult = [VerificationResult]::Failed
			}
		}

		return $controlResult;
	}

	hidden [controlresult[]] CheckAADEnabled([controlresult] $controlresult)
	{
		if ([Helpers]::CheckMember($this.ResourceObject, "Properties"))
		{
			# Legacy AAD Auth integration
			if ([Helpers]::CheckMember($this.ResourceObject.Properties, "aadProfile") -and [Helpers]::CheckMember($this.ResourceObject.Properties.aadProfile, "clientAppID") -and [Helpers]::CheckMember($this.ResourceObject.Properties.aadProfile, "serverAppID") -and [Helpers]::CheckMember($this.ResourceObject.Properties.aadProfile, "tenantID"))
			{
				$controlResult.AddMessage([VerificationResult]::Passed,
					[MessageData]::new("AAD profile configuration details", $this.ResourceObject.Properties.aadProfile));
			}
			# AKS-managed Azure AD integration
			elseif ([Helpers]::CheckMember($this.ResourceObject.Properties, "aadProfile") -and [Helpers]::CheckMember($this.ResourceObject.Properties.aadProfile, "managed"))
			{
				$controlResult.AddMessage([VerificationResult]::Passed,
					[MessageData]::new("AAD profile configuration details", $this.ResourceObject.Properties.aadProfile));
			}
			else
			{
				$controlResult.VerificationResult = [VerificationResult]::Failed
			}
		}

		return $controlResult;
	}

	hidden [controlresult[]] CheckKubernetesVersion([controlresult] $controlresult)
	{
		if (([Helpers]::CheckMember($this.ResourceObject, "Properties")) -and [Helpers]::CheckMember($this.ResourceObject.Properties, "kubernetesVersion"))
		{
			$requiredKubernetesVersion = $null
			$requiredKubernetesVersionPresent = $false
			<#
		    $ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl();
            $AccessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
			$header = "Bearer " + $AccessToken
			$headers = @{"Authorization"=$header;"Content-Type"="application/json";}

			$uri=[system.string]::Format("{0}subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.ContainerService/managedClusters/{3}/upgradeProfiles/default?api-version=2018-03-31",$ResourceAppIdURI,$this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName)
			$result = ""
			$err = $null
			try {
				$propertiesToReplace = @{}
				$propertiesToReplace.Add("httpapplicationroutingzonename", "_httpapplicationroutingzonename")
				$result = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $headers, $null, $null, $propertiesToReplace); 
				if(($null -ne $result) -and (($result | Measure-Object).Count -gt 0))
				{
					$upgradeProfile = $result.properties.controlPlaneProfile.upgrades
					$requiredKubernetsVersion = "0.0.0"
					$upgradeProfile | Foreach-Object { 
						if([System.Version] $requiredKubernetsVersion -le [System.Version] $_)
						{ 
							$requiredKubernetsVersion = $_
						} 
					}
					$requiredKubernetsVersion = [System.Version] $requiredKubernetsVersion
				}
			}
			catch{
				#If any exception occurs, get required kubernetes version from config
				$requiredKubernetsVersion = [System.Version] $this.ControlSettings.KubernetesService.kubernetesVersion
			}
			#>
			$supportedKubernetesVersion = $this.ControlSettings.KubernetesService.kubernetesVersion
			$resourceKubernetesVersion = [System.Version] $this.ResourceObject.Properties.kubernetesVersion
			$supportedKubernetesVersion | ForEach-Object {
				if ($resourceKubernetesVersion -eq [System.Version] $_)
				{
					$requiredKubernetesVersionPresent = $true
				}
			}

			if (-not $requiredKubernetesVersionPresent)
			{
				$controlResult.AddMessage([VerificationResult]::Failed,
					[MessageData]::new("AKS cluster is not running on required Kubernetes version."));
				$controlResult.AddMessage([MessageData]::new("Current Kubernetes version: ", $resourceKubernetesVersion.ToString()));
				$controlResult.AddMessage([MessageData]::new("Kubernetes cluster must be running on any one of the following versions: ", $supportedKubernetesVersion));

			}
			else
			{
				$controlResult.VerificationResult = [VerificationResult]::Passed
			}
		}

		return $controlResult;
	}

	hidden [controlresult[]] CheckMonitoringConfiguration([controlresult] $controlresult)
	{
		if ([Helpers]::CheckMember($this.ResourceObject, "Properties"))
		{
			if ([Helpers]::CheckMember($this.ResourceObject.Properties, "addonProfiles.omsagent") -and [Helpers]::CheckMember($this.ResourceObject.Properties.addonProfiles.omsagent, "config"))
			{
				if ($this.ResourceObject.Properties.addonProfiles.omsagent.config -and $this.ResourceObject.Properties.addonProfiles.omsagent.enabled -eq $true)
				{
					$controlResult.AddMessage([VerificationResult]::Passed,
						[MessageData]::new("Configuration of monitoring agent for resource " + $this.ResourceObject.name + " is ", $this.ResourceObject.Properties.addonProfiles.omsagent));
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Failed,
						[MessageData]::new("Monitoring agent is not enabled for resource " + $this.ResourceObject.name));
				}
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Failed,
					[MessageData]::new("Monitoring agent is not configured for resource " + $this.ResourceObject.name));
			}
		}
		return $controlResult;
	}


	hidden [controlresult[]] CheckNodeOpenPorts([controlresult] $controlresult)
	{
		# If node rg property is null, set control state to manual and return
		if ([Helpers]::CheckMember($this.ResourceObject, "Properties") -and [Helpers]::CheckMember($this.ResourceObject.Properties, "nodeResourceGroup"))
		{
			$nodeRG = $this.ResourceObject.Properties.nodeResourceGroup
		}
		else{
			$controlResult.AddMessage([VerificationResult]::Manual, "Unable to validate open ports as node ResourceGroup property is null.");
			return $controlResult;
		}

		$agentPoolType = ""
		# Check if backend pool contains VM or VMSS
		if([Helpers]::CheckMember($this.ResourceObject.Properties, "agentPoolProfiles")){

			if([Helpers]::CheckMember($this.ResourceObject.Properties.agentPoolProfiles[0], "type") -and $this.ResourceObject.Properties.agentPoolProfiles[0].type -eq "VirtualMachineScaleSets"){
				$agentPoolType = "VirtualMachineScaleSets"
			}else{
				$agentPoolType = "VirtualMachines"
			}

		}else{
			# if there are no nodes, set control state to manual and return
			$controlResult.AddMessage([VerificationResult]::Manual, "Unable to validate open ports as node ResourceGroup property is null.");
			return $controlResult;
		}

		if($agentPoolType -eq "VirtualMachines"){
			# Check open mgt. ports in backend VMs
			$vms = Get-AzVM -ResourceGroupName $nodeRG -ErrorAction SilentlyContinue 
			if (($vms | Measure-Object).Count -gt 0)
			{
				$isManual = $false
				$vulnerableNSGsWithRules = @();
				$effectiveNSG = $null;
				$openPortsList = @();
				$VMControlSettings = $this.ControlSettings.VirtualMachine.Linux
				$controlResult.AddMessage("Checking for Virtual Machine management ports", $VMControlSettings.ManagementPortList);
				$vmWithoutNSG = @();
				$vms | ForEach-Object {
					$vmObject = $_
					if ($vmObject.NetworkProfile -and $vmObject.NetworkProfile.NetworkInterfaces)
					{
						$vmObject.NetworkProfile.NetworkInterfaces | ForEach-Object {          
							$nicResourceIdParts = $_.Id.Split("/")
							$nicResourceName = $nicResourceIdParts[-1]
							$nicRGName = $nicResourceIdParts[4]
							try
							{
								$effectiveNSG = Get-AzEffectiveNetworkSecurityGroup -NetworkInterfaceName $nicResourceName -ResourceGroupName $nicRGName -WarningAction SilentlyContinue -ErrorAction Stop
							}
							catch
							{
								$isManual = $true
								$statusCode = ($_.Exception).InnerException.Response.StatusCode;
								if ($statusCode -eq [System.Net.HttpStatusCode]::BadRequest -or $statusCode -eq [System.Net.HttpStatusCode]::Forbidden)
								{							
									$controlResult.AddMessage(($_.Exception).InnerException.Message);	
								}
								else
								{
									throw $_
								}
							}

							if ($effectiveNSG)
							{
								$vulnerableRules = @()
								if ($VMControlSettings -and $VMControlSettings.ManagementPortList)
								{
									$inbloundRules = $effectiveNSG.EffectiveSecurityRules | Where-Object { ($_.direction -eq "Inbound" -and $_.Name -notlike "defaultsecurityrules*") }
									Foreach ($PortDetails in $VMControlSettings.ManagementPortList)
									{
										$portVulnerableRules = $this.CheckIfPortIsOpened($inbloundRules, $PortDetails.Port)
										if (($null -ne $portVulnerableRules) -and ($portVulnerableRules | Measure-Object).Count -gt 0)
										{
											$vulnerableRules += $PortDetails
										}
									}							
								}				
						
								if ($vulnerableRules.Count -ne 0)
								{
									$vulnerableNSGsWithRules += @{
										Association          = $effectiveNSG.Association;
										NetworkSecurityGroup = $effectiveNSG.NetworkSecurityGroup;
										VulnerableRules      = $vulnerableRules;
										NicId              = $_.Id
									};
								}						
							}
							else
							{
								$vmWithoutNSG += $vmObject.Name
							}	
						}
					}
				}

				if ($isManual)
				{
					$controlResult.AddMessage([VerificationResult]::Manual, "Unable to check the NSG rules for some NICs. Please validate manually.");
					#Setting this property ensures that this control result will not be considered for the central telemetry, as control does not have the required permissions
					$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
					if ($vulnerableNSGsWithRules.Count -ne 0)
					{
						$controlResult.AddMessage([VerificationResult]::Manual, "Management ports are open on node VM. Please verify and remove the NSG rules in order to comply.", $vulnerableNSGsWithRules);
					}
				}
				elseif (($vmWithoutNSG | Measure-Object).Count -gt 0)
				{
					#If the VM is connected to ERNetwork and there is no NSG, then we should not fail as this would directly conflict with the NSG control as well.
					$controlResult.AddMessage([VerificationResult]::Failed, "Verify if NSG is attached to all node VM.");
					$controlResult.AddMessage("Following VM nodes don't have any NSG attached:", $vmWithoutNSG);
				}
				else
				{
					#If the VM is connected to ERNetwork or not and there is NSG, then teams should apply the recommendation and attest this control for now.
					if ($vulnerableNSGsWithRules.Count -eq 0)
					{              
						$controlResult.AddMessage([VerificationResult]::Passed, "No management ports are open on node VM");  
					}
					else
					{
						$controlResult.AddMessage([VerificationResult]::Verify, "Management ports are open on node VM. Please verify and remove the NSG rules in order to comply.", $vulnerableNSGsWithRules);
						$controlResult.SetStateData("Management ports list on node VM", $vulnerableNSGsWithRules);
					}
				}
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Manual, "Unable to fetch node VM details. Please verify NSG rules manually on node VM.");
			}

		}
		else{
			# Check open mgt. ports in backend VMSS
			$vmss = Get-AzVmss -ResourceGroupName $nodeRG -ErrorAction SilentlyContinue 
			$vmssWithoutNSG = @()
			$isManual = $false
			$vulnerableNSGsWithRules = @();
			$effectiveNSG = $null;
			$openPortsList =@();
			$nsgAtSubnetLevelChecked = $false
			$nsgAtSubnetLevel = $null
			$vmssMgtPortList = @($this.ControlSettings.VirtualMachineScaleSet.Linux.ManagementPortList + $this.ControlSettings.VirtualMachineScaleSet.Windows.ManagementPortList )
			$applicableNSGForVMSS =  @{}
			$vmss | ForEach-Object {
				$currentVMSS = $_
				if([Helpers]::CheckMember($currentVMSS,"VirtualMachineProfile.NetworkProfile")){
					$currentVMSS.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations|
					ForEach-Object {   
						$effectiveNSGForCurrentNIC = $null
						#Get the NSGs applied at subnet level       
						if(-not $nsgAtSubnetLevelChecked -and $_.IpConfigurations)
						{        
							$nsgAtSubnetLevelChecked = $true
							$subnetId = $_.IpConfigurations[0].Subnet.Id;		
							$subnetName = $subnetId.Substring($subnetId.LastIndexOf("/") + 1);
							# get vnet name and rg name from subnet id
							# sample subnet id: /subscriptions/00000000000000000000/resourceGroups/rgName/providers/Microsoft.Network/virtualNetworks/vnetName/subnets/subNetName
							$subnetIdParts = $subnetId.Trim().Split("/")
							$vnetResourceGroupName = $subnetIdParts[4]
							$vnetResourceName = $subnetIdParts[8]
							$vnetObject = Get-AzVirtualNetwork -Name $vnetResourceName -ResourceGroupName $vnetResourceGroupName
							if($vnetObject)
							{
								$subnetConfig = Get-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnetObject
								if($subnetConfig -and $subnetConfig.NetworkSecurityGroup -and $subnetConfig.NetworkSecurityGroup.Id)
								{
									# get nsg name and rg name from nsg id
									# sample nsg id: /subscriptions/000000000000000000/resourceGroups/rgName/providers/Microsoft.Network/networkSecurityGroups/nsgName
									$nsgIdParts = $subnetConfig.NetworkSecurityGroup.Id.Trim().Split("/")
									$nsgResourceGroupName = $nsgIdParts[4]
									$nsgResourceName = $nsgIdParts[8]
									$nsgObject = Get-AzNetworkSecurityGroup -Name $nsgResourceName -ResourceGroupName $nsgResourceGroupName
									if($nsgObject)
									{
										$nsgAtSubnetLevel = $nsgObject
										$applicableNSGForVMSS[$nsgAtSubnetLevel.Id] =  $nsgAtSubnetLevel
									}
								}
							}          
						}      
						
						#Get NSGs applied at NIC level
						if($_.NetworkSecurityGroup)
						{
							if (-not $applicableNSGForVMSS.ContainsKey($_.NetworkSecurityGroup.Id)){
								# get nsg name and rg name from nsg id
								# sample nsg id: /subscriptions/000000000000000000/resourceGroups/rgName/providers/Microsoft.Network/networkSecurityGroups/nsgName
								$nsgIdParts = $_.NetworkSecurityGroup.Id.Trim().Split("/")
								$nsgResourceGroupName = $nsgIdParts[4]
								$nsgResourceName = $nsgIdParts[8]
								$nsgObject = Get-AzNetworkSecurityGroup -Name $nsgResourceName -ResourceGroupName $nsgResourceGroupName
								if($nsgObject)
								{
									$effectiveNSGForCurrentNIC = $nsgObject.Id
									$applicableNSGForVMSS[$_.NetworkSecurityGroup.Id] =  $nsgObject
								}else
								{
									$effectiveNSGForCurrentNIC = $nsgAtSubnetLevel
								}	
							}else{
								$effectiveNSGForCurrentNIC = $_.NetworkSecurityGroup.Id
							}
						} else{
							$effectiveNSGForCurrentNIC = $nsgAtSubnetLevel 
						} 

						if(-not $effectiveNSGForCurrentNIC){
							$vmssWithoutNSG = $currentVMSS.Name
						}
					}
				}else{
					$isManual = $true
				}
			}
			
			$applicableNSGForVMSS.Keys | ForEach-Object {
				$currentNSG = $applicableNSGForVMSS[$_]
				$vulnerableRules = @()
				if($vmssMgtPortList.Count -gt 0)
				{
					$vmssMgtPortList = $vmssMgtPortList  | Select-Object -Unique -Property Port,Name
					$inbloundRules = $currentNSG.SecurityRules | Where-Object { ($_.direction -eq "Inbound" ) }
					Foreach($PortDetails in  $vmssMgtPortList)
					{
						$portVulnerableRules = $this.CheckIfPortIsOpened($inbloundRules,$PortDetails.Port)
						if(($null -ne $portVulnerableRules) -and ($portVulnerableRules | Measure-Object).Count -gt 0)
						{
							$vulnerableRules += $PortDetails
						}
					}							
				}				
				if($vulnerableRules.Count -ne 0)
				{
					$vulnerableNSGsWithRules += @{
						NetworkSecurityGroupName = $currentNSG.Name;
						NetworkSecurityGroupId = $currentNSG.Id;
						VulnerableRules = $vulnerableRules
					};
				}						
			}

			if ($isManual)
			{
				$controlResult.AddMessage([VerificationResult]::Manual, "Unable to check the NSG rules. Please validate manually.");
				#Setting this property ensures that this control result will not be considered for the central telemetry, as control does not have the required permissions
				$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
				if ($vulnerableNSGsWithRules.Count -ne 0)
				{
					$controlResult.AddMessage([VerificationResult]::Manual, "Management ports are open on AKS backend node pools. Please verify and remove the NSG rules in order to comply.", $vulnerableNSGsWithRules);
				}
			}
			elseif (($vmssWithoutNSG | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "Verify if NSG is attached to all node pools.");
				$controlResult.AddMessage("Following VMSS node pools don't have any NSG attached:", $vmssWithoutNSG);
			}
			else
			{
				if ($vulnerableNSGsWithRules.Count -eq 0)
				{              
					$controlResult.AddMessage([VerificationResult]::Passed, "No management ports are open on AKS backend node pools");  
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Verify, "Management ports are open on AKS backend node pools. Please verify and remove the NSG rules in order to comply.", $vulnerableNSGsWithRules);
					$controlResult.SetStateData("Management ports list on AKS backend node pools", $vulnerableNSGsWithRules);
				}
			}
		}
		return $controlResult;
	}

	hidden [PSObject] CheckIfPortIsOpened([PSObject] $inbloundRules, [int] $port )
	{
		$vulnerableRules = @();
		foreach ($securityRule in $inbloundRules)
		{
			foreach ($destPort in $securityRule.destinationPortRange)
			{
				$range = $destPort.Split("-")
				#For ex. in case of VM if we provide the input 22 in the destination port range field, it will be interpreted as 22-22 as we are passing effective NSG secuirty rules
				#Or if NSG rules contains a open port range like 22-28
				if ($range.Count -eq 2)
				{
					$startPort = $range[0]
					$endPort = $range[1]
					if (($port -ge $startPort -and $port -le $endPort) -and $securityRule.access.ToLower() -eq "deny")
					{
						break;
					}
					elseif (($port -ge $startPort -and $port -le $endPort) -and $securityRule.access.ToLower() -eq "allow")
					{
						$vulnerableRules += $securityRule
					}
					else
					{
						continue;
					}
				}
				#In case of VMSS if we are passing the raw NSG secuirty rules so it will keep single port as single port only  
				elseif($range.Count -eq 1 -and $destPort -eq $port) 
				{
					$vulnerableRules += $securityRule
				}
			
			}
		}
		return $vulnerableRules;
	}

	hidden [controlresult[]] CheckHTTPAppRouting([controlresult] $controlresult)
	{
		if ([Helpers]::CheckMember($this.ResourceObject, "Properties"))
		{
			if ([Helpers]::CheckMember($this.ResourceObject.Properties, "Addonprofiles.httpApplicationRouting") -and $this.ResourceObject.Properties.Addonprofiles.httpApplicationRouting.enabled -eq $true)
			{
			
				$controlResult.AddMessage([VerificationResult]::Failed, "HTTP application routing is 'Enabled' for this cluster.");
			
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, "HTTP application routing is 'Disabled' for this cluster.");
			}
		}

		return $controlResult;
	}
	
}