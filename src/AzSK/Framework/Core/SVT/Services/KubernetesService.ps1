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
			if($null -ne $AccessToken)
			{

				$header = "Bearer " + $AccessToken
				$headers = @{"Authorization"=$header;"Content-Type"="application/json";}

				$uri=[system.string]::Format("{0}subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.ContainerService/managedClusters/{3}?api-version=2018-03-31",$ResourceAppIdURI,$this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName)
				$result = ""
				$err = $null
				try {
					$propertiesToReplace = @{}
					$propertiesToReplace.Add("httpapplicationroutingzonename", "_httpapplicationroutingzonename")
					$result = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $headers, $null, $null, $propertiesToReplace); 
					if(($null -ne $result) -and (($result | Measure-Object).Count -gt 0))
					{
						$this.ResourceObject = $result[0]
					}
				}
				catch{
					$err = $_
					if($null -ne $err)
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
        if([Helpers]::CheckMember($this.ResourceObject,"Properties"))
		{
			if([Helpers]::CheckMember($this.ResourceObject.Properties,"enableRBAC") -and $this.ResourceObject.Properties.enableRBAC)
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
		if([Helpers]::CheckMember($this.ResourceObject,"Properties"))
		{
			if([Helpers]::CheckMember($this.ResourceObject.Properties,"aadProfile") -and [Helpers]::CheckMember($this.ResourceObject.Properties.aadProfile,"clientAppID") -and [Helpers]::CheckMember($this.ResourceObject.Properties.aadProfile,"serverAppID") -and [Helpers]::CheckMember($this.ResourceObject.Properties.aadProfile,"tenantID"))
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
		if(([Helpers]::CheckMember($this.ResourceObject,"Properties")) -and [Helpers]::CheckMember($this.ResourceObject.Properties,"kubernetesVersion"))
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
                if($resourceKubernetesVersion -eq [System.Version] $_){
					$requiredKubernetesVersionPresent = $true
				}
			}

			if(-not $requiredKubernetesVersionPresent)
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
		if([Helpers]::CheckMember($this.ResourceObject,"Properties"))
		{
			if([Helpers]::CheckMember($this.ResourceObject.Properties,"addonProfiles.omsagent") -and [Helpers]::CheckMember($this.ResourceObject.Properties.addonProfiles.omsagent,"config"))
			{
				if($this.ResourceObject.Properties.addonProfiles.omsagent.config -and $this.ResourceObject.Properties.addonProfiles.omsagent.enabled -eq $true)
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
		if([Helpers]::CheckMember($this.ResourceObject,"Properties") -and [Helpers]::CheckMember($this.ResourceObject.Properties,"nodeResourceGroup"))
		{
			$nodeRG = $this.ResourceObject.Properties.nodeResourceGroup
			$vms = Get-AzVM -ResourceGroupName $nodeRG -WarningAction SilentlyContinue 
			if(($vms | Measure-Object).Count -gt 0)
			{
				$isManual = $false
				$vulnerableNSGsWithRules = @();
				$effectiveNSG = $null;
				$openPortsList =@();
				$vmObject = $vms[0]
				$VMControlSettings = $this.ControlSettings.VirtualMachine.Linux
				$controlResult.AddMessage("Checking for Virtual Machine management ports",$VMControlSettings.ManagementPortList);
				$VMNICs = @();
				if($vmObject.NetworkProfile -and $vmObject.NetworkProfile.NetworkInterfaces)
				{
					$vmObject.NetworkProfile.NetworkInterfaces | 
					ForEach-Object {          
						$currentNic = Get-AzResource -ResourceId $_.Id -ErrorAction SilentlyContinue
						if($currentNic)
						{
							$nicResource = Get-AzNetworkInterface -Name $currentNic.Name `
												-ResourceGroupName $currentNic.ResourceGroupName `
												-ExpandResource NetworkSecurityGroup `
												-ErrorAction SilentlyContinue
							if($nicResource)
							{
								$VMNICs += $nicResource;
							}
						}
					}
				}

				$VMNICs | 
					ForEach-Object {	
					try
					{
						$effectiveNSG = Get-AzEffectiveNetworkSecurityGroup -NetworkInterfaceName $_.Name -ResourceGroupName $_.ResourceGroupName -WarningAction SilentlyContinue -ErrorAction Stop
					}
					catch
					{
						$isManual = $true
						$statusCode = ($_.Exception).InnerException.Response.StatusCode;
						if($statusCode -eq [System.Net.HttpStatusCode]::BadRequest -or $statusCode -eq [System.Net.HttpStatusCode]::Forbidden)
						{							
							$controlResult.AddMessage(($_.Exception).InnerException.Message);	
						}
						else
						{
							throw $_
						}
					}
					if($effectiveNSG)
					{
						$vulnerableRules = @()
						
						if($VMControlSettings -and $VMControlSettings.ManagementPortList)
						{
							Foreach($PortDetails in $VMControlSettings.ManagementPortList)
							{
								$portVulnerableRules = $this.CheckIfPortIsOpened($effectiveNSG,$PortDetails.Port)
								if(($null -ne $portVulnerableRules) -and ($portVulnerableRules | Measure-Object).Count -gt 0)
								{
									$openPortsList += $PortDetails
									$vulnerableRules += $openPortsList
								}
							}							
						}				
						
						if($vulnerableRules.Count -ne 0)
						{
							$vulnerableNSGsWithRules += @{
								Association = $effectiveNSG.Association;
								NetworkSecurityGroup = $effectiveNSG.NetworkSecurityGroup;
								VulnerableRules = $vulnerableRules;
								NicName = $_.Name
							};
						}						
					}					
				}

				if($isManual)
				{
					$controlResult.AddMessage([VerificationResult]::Manual, "Unable to check the NSG rules for some NICs. Please validate manually.");
					#Setting this property ensures that this control result will not be considered for the central telemetry, as control does not have the required permissions
					$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
					if($vulnerableNSGsWithRules.Count -ne 0)
					{
						$controlResult.AddMessage([VerificationResult]::Manual, "Management ports are open on node VM. Please verify and remove the NSG rules in order to comply.", $vulnerableNSGsWithRules);
					}
				}
				elseif($null -eq $effectiveNSG)
				{
					#If the VM is connected to ERNetwork and there is no NSG, then we should not fail as this would directly conflict with the NSG control as well.
					if($this.VMDetails.IsVMConnectedToERvNet)
					{
						$controlResult.AddMessage([VerificationResult]::Passed, "Node VM is connected ER Network. And no NSG found for Virtual Machine");  
					}
					else
					{
						$controlResult.AddMessage([VerificationResult]::Failed, "Verify if NSG is attached to node VM.");
					}
				
				}
				else
				{
					#If the VM is connected to ERNetwork or not and there is NSG, then teams should apply the recommendation and attest this control for now.
					if($vulnerableNSGsWithRules.Count -eq 0)
					{              
						$controlResult.AddMessage([VerificationResult]::Passed, "No management ports are open on node VM");  
					}
					else
					{
						$controlResult.AddMessage("List of open ports: ",$openPortsList);
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
		
		return $controlResult;
	}

	hidden [PSObject] CheckIfPortIsOpened([PSObject] $effectiveNSG,[int] $port )
	{
		$vulnerableRules = @();
		$inbloundRules = $effectiveNSG.EffectiveSecurityRules | Where-Object { ($_.direction -eq "Inbound" -and $_.Name -notlike "defaultsecurityrules*") }
		foreach($securityRule in $inbloundRules){
			foreach($destPort in $securityRule.destinationPortRange) {
				$range =$destPort.Split("-")
				#For ex. if we provide the input 22 in the destination port range field, it will be interpreted as 22-22
				if($range.Count -eq 2) {
					$startPort = $range[0]
					$endPort = $range[1]
					if(($port -ge $startPort -and $port -le $endPort) -and $securityRule.access.ToLower() -eq "deny")
					{
						break;
					}
					elseif(($port -ge $startPort -and $port -le $endPort) -and $securityRule.access.ToLower() -eq "allow")
					{
						$vulnerableRules += $securityRule
					}
					else
					{
						continue;
					}
				}
				else 
				{
					throw "Error while reading port range $($destPort)."
				}
	
			}
		}
		return $vulnerableRules;
	}

	hidden [controlresult[]] CheckHTTPAppRouting([controlresult] $controlresult)
	{
        if([Helpers]::CheckMember($this.ResourceObject,"Properties"))
		{
			if([Helpers]::CheckMember($this.ResourceObject.Properties,"Addonprofiles.httpApplicationRouting") -and $this.ResourceObject.Properties.Addonprofiles.httpApplicationRouting.enabled -eq $true)
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