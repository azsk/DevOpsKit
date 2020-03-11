Set-StrictMode -Version Latest 
class ServiceFabric : AzSVTBase
{       
    hidden [PSObject] $ResourceObject;
	hidden [string] $ClusterTagValue;
	hidden [PSObject] $ApplicationList;
	hidden [string] $DefaultTagName = "clusterName"
    hidden [string] $CertStoreLocation = "CurrentUser"
	hidden [string] $CertStoreName = "My"
	hidden [boolean] $IsSDKAvailable = $false

    ServiceFabric([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
		
    }

	hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) 
		{
            $this.ResourceObject =  Get-AzResource -ResourceGroupName $this.ResourceContext.ResourceGroupName -ResourceType $this.ResourceContext.ResourceType -Name $this.ResourceContext.ResourceName    

			$this.ResourceObject.Tags.GetEnumerator() | Where-Object { $_.Key -eq $this.DefaultTagName } | ForEach-Object {$this.ClusterTagValue = $_.Value }
			
			# Check if Service Fabric SDK is installed
			try {

			    $scanSource = [RemoteReportHelper]::GetScanSource();         
				if($scanSource -eq [ScanSource]::SpotCheck -and (Get-Command Connect-ServiceFabricCluster -ErrorAction SilentlyContinue)){	
					$this.IsSDKAvailable = $true		
				}else
				{
				  $this.IsSDKAvailable = $false	
				}

			}catch {
				# No need to break execution
				# All controls which requires SDK to be present in user machine will be treated as manual controls
				$this.IsSDKAvailable = $false
			}
			
			
			if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }

	[ControlItem[]] ApplyServiceFilters([ControlItem[]] $controls)
	{
		$result = @();
		$VMType = "Windows"
		#Check VM type
		if([Helpers]::CheckMember($this.ResourceObject.Properties,"vmImage")){
			$VMType = $this.ResourceObject.Properties.vmImage
		}
        if($VMType -eq "Linux")
        {
			$result += $controls | Where-Object { $_.Tags -contains "Linux" };
		}
		else
		{
			$result += $controls | Where-Object { $_.Tags -contains "Windows" };;
		}
		return $result;
	}

	hidden [ControlResult] CheckSecurityMode([ControlResult] $controlResult)
	{
		$isCertificateEnabled = [Helpers]::CheckMember($this.ResourceObject.Properties,"certificate" ) 
		
		#Validate if primary certificate is enabled on cluster. Presence of certificate property value indicates, security mode is turned on.
		if($isCertificateEnabled)
        {			
			$controlResult.AddMessage([VerificationResult]::Passed,"Service Fabric cluster is secured with certificate", $this.ResourceObject.Properties.certificate);
        }
        else
        {			
			$controlResult.AddMessage([VerificationResult]::Failed,"Service Fabric cluster is not secured with certificate");
        }
		return $controlResult;    
	}

	hidden [ControlResult] CheckClusterCertificateSSL([ControlResult] $controlResult)
	{
		$managementEndpointUri = $this.ResourceObject.Properties.managementEndpoint
		$managementEndpointUriScheme = ([System.Uri]$managementEndpointUri).Scheme               

		#Validate if cluster management endpoint url is SSL enabled
		if($managementEndpointUriScheme -eq "https")
		{   
			#Hit web request to management endpoint uri and validate certificate trust level             
			$request = [System.Net.HttpWebRequest]::Create($managementEndpointUri) 
			try
			{
				$request.GetResponse().Dispose()
				$controlResult.AddMessage([VerificationResult]::Passed,"Service Fabric cluster is protected with CA signed certificate");                    
			}
			catch [System.Net.WebException]
			{
				#Trust failure indicates self-signed certificate or domain mismatch certificate present on endpoint
				if ($_.Exception.Status -eq [System.Net.WebExceptionStatus]::TrustFailure)
				{                        
					$controlResult.AddMessage([VerificationResult]::Verify,"Validate if self-signed certificate is not used for cluster management endpoint protection",$this.ResourceObject.Properties.managementEndpoint);
					$controlResult.SetStateData("Management endpoint", $this.ResourceObject.Properties.managementEndpoint);
				}
				elseif($_.Exception.Message.Contains('403'))
				{
					$controlResult.AddMessage([VerificationResult]::Passed,"Service Fabric cluster is protected with CA signed certificate");
				}
				else
				{					
				    $controlResult.AddMessage([VerificationResult]::Manual,"Unable to Validate certificate details. Please verify manually that self-signed certificate is not used for cluster management endpoint protection",$this.ResourceObject.Properties.managementEndpoint);
					$controlResult.AddMessage($_.Exception.Message);
				}
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Failed,"Service Fabric cluster is not protected by SSL")
		}
		return $controlResult;    
	}

	hidden [ControlResult] CheckAADClientAuthentication([ControlResult] $controlResult)
	{
		$isAADEnabled = [Helpers]::CheckMember($this.ResourceObject.Properties,"azureActiveDirectory")
		
		#Presence of 'AzureActiveDirectory' indicates, AAD authentication is enabled for client authentication
		if($isAADEnabled)
        {			
			$controlResult.AddMessage([VerificationResult]::Passed,"AAD is enabled for client authentication",$this.ResourceObject.Properties.azureActiveDirectory )
        }
        else
        {			
			$controlResult.AddMessage([VerificationResult]::Failed,"AAD is not enabled for client authentication")
        }

		return $controlResult
	}

	hidden [ControlResult] CheckClusterProtectionLevel([ControlResult] $controlResult)
	{
		$fabricSecuritySettings = $this.ResourceObject.Properties.fabricSettings | Where-Object {$_.Name -eq "Security"}

		#Absence of security settings indicates, secure mode is not enabled on cluster.
		if($null -ne $fabricSecuritySettings)
		{
			$clusterProtectionLevel = $fabricSecuritySettings.parameters | Where-Object { $_.name -eq "ClusterProtectionLevel"}
			if($null -ne $clusterProtectionLevel -and $clusterProtectionLevel.value -eq "EncryptAndSign")
			{
			  $controlResult.AddMessage([VerificationResult]::Passed,"Cluster security is ON with 'EncryptAndSign' protection level",$clusterProtectionLevel);
			}
			else 
			{
			  $controlResult.AddMessage([VerificationResult]::Failed,"Cluster security is not set with 'EncryptAndSign' protection level. Current protection level is :", $clusterProtectionLevel);
				$controlResult.SetStateData("Cluster protection level", $clusterProtectionLevel);
			}
		}
		else
		{
		  $controlResult.AddMessage([VerificationResult]::Failed,"Cluster security is OFF");
		}

		return $controlResult
	}

	hidden [ControlResult[]] CheckNSGConfigurations([ControlResult] $controlResult)
	{
		$isVerify = $true;
		$nsgEnabledVNet = @{};
		$nsgDisabledVNet = @{};

		$virtualNetworkResources = $this.GetLinkedResources("Microsoft.Network/virtualNetworks") 
		if($virtualNetworkResources -ne $null)
		{
			#Iterate through all cluster linked VNet resources      
			$virtualNetworkResources |ForEach-Object{            
				$virtualNetwork=Get-AzVirtualNetwork -ResourceGroupName $_.ResourceGroupName -Name $_.Name 
				$subnetConfig = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $virtualNetwork
				#Iterate through Subnet and validate if NSG is configured or not
				$subnetConfig | ForEach-Object{
					$subnetName =$_.Name
					$isCompliant =  ($null -ne $_.NetworkSecurityGroup)		
					#If NSG is enabled on Subnet display all security rules applied 
					if($isCompliant)
					{
						$nsgResource = Get-AzResource -ResourceId $_.NetworkSecurityGroup.Id
						$nsgResourceDetails = Get-AzNetworkSecurityGroup -ResourceGroupName $nsgResource.ResourceGroupName -Name $nsgResource.Name                
						
						$nsgEnabledVNet.Add($subnetName, $nsgResourceDetails)
					}
					#If NSG is not enabled on Subnet, fail the TCP with Subnet details
					else
					{
						$nsgDisabledVNet.Add($subnetName, $_)
						$isVerify = $false
					} 
				}                
			}

			if($nsgEnabledVNet.Keys.Count -gt 0)
			{
				$nsgEnabledVNet.Keys  | Foreach-Object {
					$controlResult.AddMessage("Validate NSG security rules applied on subnet '$_'",$nsgEnabledVNet[$_]);
				}
			}

			if($nsgDisabledVNet.Keys.Count -gt 0)
			{
				$nsgDisabledVNet.Keys  | Foreach-Object {
					$controlResult.AddMessage("NSG is not configured on subnet '$_'",$nsgDisabledVNet[$_]);
				}
			}

			if($isVerify)
			{
				$controlResult.VerificationResult = [VerificationResult]::Verify;
			}
			else
			{
				$controlResult.VerificationResult = [VerificationResult]::Failed;
			}

			$NSGState = New-Object -TypeName PSObject 
			$NSGState | Add-Member -NotePropertyName NSGConfiguredSubnet -NotePropertyValue $nsgEnabledVNet
			$NSGState | Add-Member -NotePropertyName NSGNotConfiguredSubnet -NotePropertyValue $nsgDisabledVNet

			$controlResult.SetStateData("NSG security rules applied on subnet", $NSGState);
		}else{
			$controlResult.AddMessage("Not able to fetch details of VNet resources linked with cluster.");
			$controlResult.AddMessage("Manually verify that NSG is enabled on Subnet.");
			$controlResult.VerificationResult = [VerificationResult]::Manual;
		}
        

		return $controlResult        
	}

	hidden [ControlResult[]] CheckVmssDiagnostics([ControlResult] $controlResult)
	{
		$isPassed = $true;
		$diagnosticsEnabledScaleSet = @{};
		$diagnosticsDisabledScaleSet = @{};
		$vmssResources = $this.GetLinkedResources("Microsoft.Compute/virtualMachineScaleSets")
		if($null -ne $vmssResources -and ($vmssResources | Measure-Object).Count -gt 0){
			#Iterate through cluster linked vmss resources             
			$vmssResources | ForEach-Object{
				$VMScaleSetName = $_.Name	
				$nodeTypeResource = Get-AzVMss -ResourceGroupName  $_.ResourceGroupName -VMScaleSetName  $VMScaleSetName

				# Fetch diagnostics settings based on OS 
				if($this.ResourceObject.Properties.vmImage -eq "Linux")
				{
					$diagnosticsSettings = $nodeTypeResource.VirtualMachineProfile.ExtensionProfile.Extensions  | ? { $_.Type -eq "LinuxDiagnostic" -and $_.Publisher -eq "Microsoft.OSTCExtensions" }				
				}
				else
				{
					$diagnosticsSettings = $nodeTypeResource.VirtualMachineProfile.ExtensionProfile.Extensions  | ? { $_.Type -eq "IaaSDiagnostics" -and $_.Publisher -eq "Microsoft.Azure.Diagnostics" }
				}
				#Validate if diagnostics is enabled on vmss 
				if($null -ne $diagnosticsSettings )
				{
					$diagnosticsEnabledScaleSet.Add($VMScaleSetName, $diagnosticsSettings)		
				}
				else
				{
					$isPassed = $false;
					$diagnosticsDisabledScaleSet.Add($VMScaleSetName, $diagnosticsSettings)		
				} 
			}

			if($diagnosticsEnabledScaleSet.Keys.Count -gt 0)
			{
				$diagnosticsEnabledScaleSet.Keys  | Foreach-Object {
					$controlResult.AddMessage("Diagnostics is enabled on Vmss '$_'",$diagnosticsEnabledScaleSet[$_]);
				}
			}

			if($diagnosticsDisabledScaleSet.Keys.Count -gt 0)
			{
				$diagnosticsDisabledScaleSet.Keys  | Foreach-Object {
					$controlResult.AddMessage("Diagnostics is disabled on Vmss '$_'",$diagnosticsDisabledScaleSet[$_]);
				}
			}

			if($isPassed)
			{
				$controlResult.VerificationResult = [VerificationResult]::Passed;
			}
			else
			{
				$controlResult.VerificationResult = [VerificationResult]::Failed;
				$controlResult.SetStateData("Diagnostics is disabled on Vmss", $diagnosticsDisabledScaleSet);
			}
		}else{
			$controlResult.AddMessage("Not able to fetch details of VM Scale Sets resources linked with cluster.");
			$controlResult.AddMessage("Manually verify that Diagnostics is enabled.");
			$controlResult.VerificationResult = [VerificationResult]::Manual;
		}
		
		return $controlResult        
	}
	hidden [ControlResult[]] CheckReverseProxyPort([ControlResult] $controlResult)
	{
		# add attestation details
		$isPassed = $true;
		$reverseProxyEnabledNode = @{};
		$reverseProxyDisabledNode = @();
		$reverseProxyExposedNode = @{};
		$nodeTypes= $this.ResourceObject.Properties.nodeTypes
		#Iterate through each node           
		$nodeTypes | ForEach-Object{

			if([Helpers]::CheckMember($_,"reverseProxyEndpointPort"))
			{
				$reverseProxyEnabledNode.Add($_.name, $_.reverseProxyEndpointPort)
			}else{
				$reverseProxyDisabledNode += $_.name
			}
		}
		# if reverse proxy is not enabled in any node, pass TCP
		if(($reverseProxyEnabledNode | Measure-Object).Count -gt 0)
		{
			$lbWithBackendPorts = @{}
			$loadBalancerResources = $this.GetLinkedResources("Microsoft.Network/loadBalancers")
			if($null -ne $loadBalancerResources -and ($loadBalancerResources | Measure-Object).Count -gt 0 ){
				#Collect all open ports on load balancer  
				$loadBalancerResources | ForEach-Object{
					$loadBalancerBackendPorts = @()
					$loadBalancerResource = Get-AzLoadBalancer -Name $_.Name -ResourceGroupName $_.ResourceGroupName
					$loadBalancingRules = @($loadBalancerResource.FrontendIpConfigurations | ? { $null -ne $_.PublicIpAddress } | ForEach-Object { $_.LoadBalancingRules })
				
					$loadBalancingRules | ForEach-Object {
						$loadBalancingRuleId = $_.Id;
						$loadBalancingRule = $loadBalancerResource.LoadBalancingRules | ? { $_.Id -eq  $loadBalancingRuleId } | Select-Object -First 1
						$loadBalancerBackendPorts += $loadBalancingRule.BackendPort;
					};  
					if($loadBalancerBackendPorts.Count -gt 0)
					{
						$loadBalancerResource.BackendAddressPools | ForEach-Object {
							$BackendAddressPools = $_
							if ([Helpers]::CheckMember($BackendAddressPools, "BackendIpConfigurations") -and ($BackendAddressPools.BackendIpConfigurations | Measure-Object).Count -gt 0)
							{
								$backEndIpConfiguration = $BackendAddressPools.BackendIpConfigurations | Select -First 1
								$pattern = "providers/Microsoft.Compute/virtualMachineScaleSets/(.*?)/"
								$result = [regex]::match($backEndIpConfiguration.Id, $pattern)
								if ($result.Success)
								{
									$nodeName = $result.Groups[1].Value
									$lbWithBackendPorts.Add($nodeName, $loadBalancerBackendPorts)
								}

							}
					}
					} 
				}
				#If no ports open, Pass the TCP
				if($lbWithBackendPorts.Count -eq 0)
				{
					$controlResult.AddMessage("No ports enabled in load balancer.")  
					$controlResultList += $controlResult      
				}
				#If Ports are open for public in load balancer, check if any reverse proxy port is exposed
				else
				{
					$reverseProxyEnabledNode.Keys  | Foreach-Object {
						$loadBalancerBackendPorts = @()
						$nodeName = $_
						$lbWithBackendPorts.Keys | ForEach-Object{
							if($_ -eq $nodeName){
								$loadBalancerBackendPorts = $lbWithBackendPorts[$_]
							}
						}
						if($loadBalancerBackendPorts.Count -gt 0 -and  $loadBalancerBackendPorts.Contains( [Int32] $reverseProxyEnabledNode[$_]))
						{
							$isPassed = $false;
							$controlResult.AddMessage("Reverse proxy port is publicly exposed for node '$_'");
							$reverseProxyExposedNode.Add($_, $reverseProxyEnabledNode[$_])
						}else{
							$controlResult.AddMessage("Reverse proxy port is not publicly exposed for node '$_'.") 
						}
						
					}
				}
			}else{
				$controlResult.AddMessage("Not able to fetch details of Load Balancer resources linked with cluster.");
				$controlResult.AddMessage("Manually verify that Reverse proxy port is not publicly exposed for any node.");
				$controlResult.VerificationResult = [VerificationResult]::Manual;
				return $controlResult
			}
		
		}else{
			$controlResult.AddMessage("Reverse proxy service is not enabled in cluster.") 
		}
		if($isPassed)
		{
			
			$controlResult.VerificationResult = [VerificationResult]::Passed;
		}
		else
		{
			$controlResult.VerificationResult = [VerificationResult]::Failed;
			$controlResult.SetStateData("Reverse proxy port is publicly exposed", $reverseProxyExposedNode);
		}
		return $controlResult
	}

	hidden [ControlResult] CheckClusterUpgradeMode([ControlResult] $controlResult)
	{
		if([Helpers]::CheckMember($this.ResourceObject.Properties,"upgradeMode") -and $this.ResourceObject.Properties.upgradeMode -eq "Automatic")
        {			
			$controlResult.AddMessage([VerificationResult]::Passed,"Upgrade mode for cluster is set to automatic." )
        }
        else
        {			
			$controlResult.AddMessage([VerificationResult]::Failed,"Upgrade mode for cluster is set to manual.")
        }

		return $controlResult
	}

	hidden [ControlResult[]] CheckStatefulServiceReplicaSetSize([ControlResult] $controlResult)
	{   
		$isConnectionSuccessful = $false
		if($this.IsSDKAvailable -eq $true)
		{
            #Function to validate authentication and connect with Service Fabric cluster     
			$sfCluster = $null       
			$uri = ([System.Uri]$this.ResourceObject.Properties.managementEndpoint).Host                
			$primaryNodeType = $this.ResourceObject.Properties.nodeTypes | Where-Object { $_.isPrimary -eq $true }
					
			$ClusterConnectionUri = $uri +":"+ $primaryNodeType.clientConnectionEndpointPort
			$isClusterSecure =  [Helpers]::CheckMember($this.ResourceObject.Properties,"certificate" )               
					
			if($isClusterSecure)
			{
					$serviceFabricCertificate = $this.ResourceObject.Properties.certificate              
					$CertThumbprint= $this.ResourceObject.Properties.certificate.thumbprint
					$serviceFabricAAD = $null
					if([Helpers]::CheckMember($this.ResourceObject.Properties,"azureActiveDirectory" ))
					{
						$serviceFabricAAD =$this.ResourceObject.Properties.azureActiveDirectory
					}  
					if($null -ne $serviceFabricAAD)
					{
						try
						{
							$this.PublishCustomMessage("Connecting Service Fabric using AAD...")
							$sfCluster = Connect-ServiceFabricCluster -ConnectionEndpoint $ClusterConnectionUri -AzureActiveDirectory -ServerCertThumbprint $CertThumbprint #-SecurityToken "
							$isConnectionSuccessful = $true
							$this.PublishCustomMessage("Connection using AAD is successful.")
						}
						catch
						{
						    $this.PublishCustomMessage("You may not have permission to connect with cluster", [MessageType]::Warning);
						}
					}              
					else
					{
						$this.PublishCustomMessage("Validating if cluster certificate present on machine...")
						$IsCertPresent = (Get-ChildItem -Path "Cert:\$($this.CertStoreLocation)\$($this.CertStoreName)" | Where-Object {$_.Thumbprint -eq $CertThumbprint }| Measure-Object).Count                   
						if($IsCertPresent)
						{
						   try
						   {
							  $this.PublishCustomMessage("Connecting Service Fabric using certificate")
							  $sfCluster = Connect-serviceFabricCluster -ConnectionEndpoint $ClusterConnectionUri -KeepAliveIntervalInSec 10 -X509Credential -ServerCertThumbprint $CertThumbprint -FindType FindByThumbprint -FindValue $CertThumbprint -StoreLocation $this.CertStoreLocation -StoreName $this.CertStoreName 
							  $isConnectionSuccessful = $true
						   }catch
						   {
						       $this.PublishCustomMessage("Cannot connect with Service Fabric cluster using cluster certificate. Verify that valid cluster certificate is present in 'CurrentUser' location.", [MessageType]::Warning);	
						   }
												
						}
						else
						{
						    $this.PublishCustomMessage("Cannot connect with Service Fabric cluster due to unavailability of cluster certificate in local machine. Validate cluster certificate is present in 'CurrentUser' location.", [MessageType]::Warning);					
						}
					}                    
			}
			else
			{
				$sfCluster = Connect-serviceFabricCluster -ConnectionEndpoint $ClusterConnectionUri
				$isConnectionSuccessful = $true
				$this.PublishCustomMessage("Service Fabric connection is successful");
			}
			
			try
			{
			  $this.ApplicationList = Get-ServiceFabricApplication -ErrorAction SilentlyContinue
			}catch
			{
			   # No need to break execution, handled in next condition
			}

			$isPassed = $true;
			$complianteServices = @{};
			$nonComplianteServices = @{};
			#Iterate through the applications present in cluster     
			if($isConnectionSuccessful -eq $false)
			{
			  $controlResult.AddMessage([VerificationResult]::Manual,"Cannot connect with Service Fabric cluster.")
			  $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;

			}elseif($this.ApplicationList)
			{
				$this.ApplicationList | ForEach-Object{
					$serviceFabricApplication = $_

					Get-ServiceFabricService -ApplicationName $serviceFabricApplication.ApplicationName | ForEach-Object{                
						$serviceName = $_.ServiceName 
						$serviceDescription = Get-ServiceFabricServiceDescription -ServiceName $_.ServiceName 
						#Filter application with Stateful service type
						if($serviceDescription.ServiceKind -eq "Stateful")
						{
							#Validate minimum replica and target replica size for each service 					
							$isCompliant = !($serviceDescription.MinReplicaSetSize -lt 3 -or $serviceDescription.TargetReplicaSetSize -lt 3)
							
							$stateObject = "" | Select-Object "MinReplicaSetSize" ,"TargetReplicaSetSize"
							$stateObject.MinReplicaSetSize = $serviceDescription.MinReplicaSetSize
							$stateObject.TargetReplicaSetSize = $serviceDescription.TargetReplicaSetSize
							if($isCompliant)
							{
								$complianteServices.Add($serviceName, $stateObject)
							} 
							else
							{ 
								$isPassed = $False
								$nonComplianteServices.Add($serviceName, $stateObject)
							}
						}                
					}
				}

				if($complianteServices.Keys.Count -gt 0)
				{
					$controlResult.AddMessage("Replica set size for below services are complaint");
					$complianteServices.Keys  | Foreach-Object {
						$controlResult.AddMessage("Replica set size details for service '$_'",$complianteServices[$_]);
					}
				}

				if($nonComplianteServices.Keys.Count -gt 0)
				{
					$controlResult.AddMessage("Replica set size for below services are non-complaint");
					$nonComplianteServices.Keys  | Foreach-Object {
						$controlResult.AddMessage("Replica set size details for service '$_'",$nonComplianteServices[$_]);
					}
				}

				if($isPassed)
				{
					$controlResult.VerificationResult = [VerificationResult]::Passed;
				}
				else
				{
					$controlResult.VerificationResult = [VerificationResult]::Failed;
					$controlResult.SetStateData("Replica set size are non-complaint for", $nonComplianteServices);
				}
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed,"No stateful service found.")
			}
		}else{
			
			$scanSource = [RemoteReportHelper]::GetScanSource();
			if($scanSource -eq [ScanSource]::SpotCheck)
			{ 
			   $controlResult.AddMessage("Service Fabric SDK is not present in user machine. To evaluate this control SDK should be available on user machine.")
			}
		    $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.VerificationResult = [VerificationResult]::Manual;
		}
		
		return $controlResult;
	}

	hidden [ControlResult[]] CheckStatelessServiceInstanceCount([ControlResult] $controlResult)
	{
	    $isConnectionSuccessful = $false
		if($this.IsSDKAvailable -eq $true)
		{
           
            #Function to validate authentication and connect with Service Fabric cluster     
			$sfCluster = $null       
			$uri = ([System.Uri]$this.ResourceObject.Properties.managementEndpoint).Host                
			$primaryNodeType = $this.ResourceObject.Properties.nodeTypes | Where-Object { $_.isPrimary -eq $true }
					
			$ClusterConnectionUri = $uri +":"+ $primaryNodeType.clientConnectionEndpointPort
			$isClusterSecure =  [Helpers]::CheckMember($this.ResourceObject.Properties,"certificate" )               
					
			if($isClusterSecure)
			{
					$serviceFabricCertificate = $this.ResourceObject.Properties.certificate              
					$CertThumbprint= $this.ResourceObject.Properties.certificate.thumbprint
					$serviceFabricAAD = $null
					if([Helpers]::CheckMember($this.ResourceObject.Properties,"azureActiveDirectory" ))
					{
						$serviceFabricAAD =$this.ResourceObject.Properties.azureActiveDirectory
					}  
					if($null -ne $serviceFabricAAD)
					{
						try
						{
							$this.PublishCustomMessage("Connecting Service Fabric using AAD...")
							$sfCluster = Connect-ServiceFabricCluster -ConnectionEndpoint $ClusterConnectionUri -AzureActiveDirectory -ServerCertThumbprint $CertThumbprint #-SecurityToken "
							$isConnectionSuccessful = $true
							$this.PublishCustomMessage("Connection using AAD is successful.")
						}
						catch
						{
						    $this.PublishCustomMessage("You may not have permission to connect with cluster", [MessageType]::Warning);
						}
					}              
					else
					{
						$this.PublishCustomMessage("Validating if cluster certificate present on machine...")
						$IsCertPresent = (Get-ChildItem -Path "Cert:\$($this.CertStoreLocation)\$($this.CertStoreName)" | Where-Object {$_.Thumbprint -eq $CertThumbprint }| Measure-Object).Count                   
						if($IsCertPresent)
						{
						   try
						   {
							  $this.PublishCustomMessage("Connecting Service Fabric using certificate")
							  $sfCluster = Connect-serviceFabricCluster -ConnectionEndpoint $ClusterConnectionUri -KeepAliveIntervalInSec 10 -X509Credential -ServerCertThumbprint $CertThumbprint -FindType FindByThumbprint -FindValue $CertThumbprint -StoreLocation $this.CertStoreLocation -StoreName $this.CertStoreName 
							  $isConnectionSuccessful = $true
						   }catch
						   {
						       $this.PublishCustomMessage("Cannot connect with Service Fabric cluster using cluster certificate. Verify that valid cluster certificate is present in 'CurrentUser' location.", [MessageType]::Warning);	
						   }
												
						}
						else
						{
						    $this.PublishCustomMessage("Cannot connect with Service Fabric cluster due to unavailability of cluster certificate in local machine. Validate cluster certificate is present in 'CurrentUser' location.", [MessageType]::Warning);					
						}
					}                    
			}
			else
			{
				$sfCluster = Connect-serviceFabricCluster -ConnectionEndpoint $ClusterConnectionUri
				$isConnectionSuccessful = $true
				$this.PublishCustomMessage("Service Fabric connection is successful");
			}

			try
			{
				$this.ApplicationList = Get-ServiceFabricApplication -ErrorAction SilentlyContinue
			}catch
			{
			   # No need to break execution, handled in next condition
			}
			
			$isPassed = $true;
			$complianteServices = @{};
			$nonComplianteServices = @{};
			   
			if($isConnectionSuccessful -eq $false)
			{
			  $controlResult.AddMessage([VerificationResult]::Manual,"Cannot connect with Service Fabric cluster.")
			  $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			}elseif($this.ApplicationList)
			{
			    #Iterate through the applications present in cluster
				$this.ApplicationList | ForEach-Object{
					$serviceFabricApplication = $_
					Get-ServiceFabricService -ApplicationName $serviceFabricApplication.ApplicationName | 
					ForEach-Object{
						$serviceName = $_.ServiceName                 
						$serviceDescription = Get-ServiceFabricServiceDescription -ServiceName $serviceName 
						#Filter application with Stateless service type
						if($serviceDescription.ServiceKind -eq "Stateless")
						{	 
							#Validate instancecount it -1 (auto) or greater than equal to 3              
							$isCompliant = ($serviceDescription.InstanceCount -eq -1 -or $serviceDescription.InstanceCount -ge 3)
							if($isCompliant)
							{
								$complianteServices.Add($serviceName, $serviceDescription.InstanceCount)
							} 
							else
							{ 
								$isPassed = $False
								$nonComplianteServices.Add($serviceName, $serviceDescription.InstanceCount)
							}
							
						} 
					} 
				}
				if($complianteServices.Keys.Count -gt 0)
				{
					$controlResult.AddMessage("Instance count for below services are complaint");
					$complianteServices.Keys  | Foreach-Object {
						$controlResult.AddMessage("Instance count details for service '$_'",$complianteServices[$_]);
					}
				}
	
				if($nonComplianteServices.Keys.Count -gt 0)
				{
					$controlResult.AddMessage("Instance count for below services are non-complaint");
					$nonComplianteServices.Keys  | Foreach-Object {
						$controlResult.AddMessage("Instance count details for service '$_'",$nonComplianteServices[$_]);
					}
				}
	
				if($isPassed)
				{
					$controlResult.VerificationResult = [VerificationResult]::Passed;
				}
				else
				{
					$controlResult.VerificationResult = [VerificationResult]::Failed;
					$controlResult.SetStateData("Instance count are non-complaint for", $nonComplianteServices);
				}
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed,"No stateless service found.")
			} 
		}else{

		     $scanSource = [RemoteReportHelper]::GetScanSource();
             if($scanSource -eq [ScanSource]::SpotCheck)
		     { 
				$controlResult.AddMessage("Service Fabric SDK is not present in user machine. To evaluate this control SDK should be available on user machine.")
		     }
		     $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			 $controlResult.VerificationResult = [VerificationResult]::Manual;
		}
		
		
		return $controlResult;        
	}

	hidden [ControlResult[]] CheckPublicEndpointSSL([ControlResult] $controlResult)
	{	
		$isConnectionSuccessful = $false
		if($this.IsSDKAvailable -eq $true)
		{          
            #Function to validate authentication and connect with Service Fabric cluster     
			$sfCluster = $null       
			$uri = ([System.Uri]$this.ResourceObject.Properties.managementEndpoint).Host                
			$primaryNodeType = $this.ResourceObject.Properties.nodeTypes | Where-Object { $_.isPrimary -eq $true }
					
			$ClusterConnectionUri = $uri +":"+ $primaryNodeType.clientConnectionEndpointPort
			$isClusterSecure =  [Helpers]::CheckMember($this.ResourceObject.Properties,"certificate" )               
					
			if($isClusterSecure)
			{
					$serviceFabricCertificate = $this.ResourceObject.Properties.certificate              
					$CertThumbprint= $this.ResourceObject.Properties.certificate.thumbprint
					$serviceFabricAAD = $null
					if([Helpers]::CheckMember($this.ResourceObject.Properties,"azureActiveDirectory" ))
					{
						$serviceFabricAAD =$this.ResourceObject.Properties.azureActiveDirectory
					}  
					if($null -ne $serviceFabricAAD)
					{
						try
						{
							$this.PublishCustomMessage("Connecting Service Fabric using AAD...")
							$sfCluster = Connect-ServiceFabricCluster -ConnectionEndpoint $ClusterConnectionUri -AzureActiveDirectory -ServerCertThumbprint $CertThumbprint #-SecurityToken "
							$isConnectionSuccessful = $true
							$this.PublishCustomMessage("Connection using AAD is successful.")
						}
						catch
						{
						    $this.PublishCustomMessage("You may not have permission to connect with cluster", [MessageType]::Warning);
						}
					}              
					else
					{
						$this.PublishCustomMessage("Validating if cluster certificate present on machine...")
						$IsCertPresent = (Get-ChildItem -Path "Cert:\$($this.CertStoreLocation)\$($this.CertStoreName)" | Where-Object {$_.Thumbprint -eq $CertThumbprint }| Measure-Object).Count                   
						if($IsCertPresent)
						{
						   try
						   {
							  $this.PublishCustomMessage("Connecting Service Fabric using certificate")
							  $sfCluster = Connect-serviceFabricCluster -ConnectionEndpoint $ClusterConnectionUri -KeepAliveIntervalInSec 10 -X509Credential -ServerCertThumbprint $CertThumbprint -FindType FindByThumbprint -FindValue $CertThumbprint -StoreLocation $this.CertStoreLocation -StoreName $this.CertStoreName 
							  $isConnectionSuccessful = $true
						   }catch
						   {
						       $this.PublishCustomMessage("Cannot connect with Service Fabric cluster using cluster certificate. Verify that valid cluster certificate is present in 'CurrentUser' location.", [MessageType]::Warning);	
						   }
												
						}
						else
						{
						    $this.PublishCustomMessage("Cannot connect with Service Fabric cluster due to unavailability of cluster certificate in local machine. Validate cluster certificate is present in 'CurrentUser' location.", [MessageType]::Warning);					
						}
					}                    
			}
			else
			{
				$sfCluster = Connect-serviceFabricCluster -ConnectionEndpoint $ClusterConnectionUri
				$isConnectionSuccessful = $true
				$this.PublishCustomMessage("Service Fabric connection is successful");
			}

			try
			{
				$this.ApplicationList = Get-ServiceFabricApplication -ErrorAction SilentlyContinue
			}catch
			{
			   #No need to break execution, handled in next condition
			}
			
			$isManual = $false;
			$isPassed = $true;
			$compliantPort = @{};
			$nonCompliantPort = @{};

			$loadBalancerBackendPorts = @()
			$loadBalancerResources = $this.GetLinkedResources("Microsoft.Network/loadBalancers")
			if($null -ne $loadBalancerResources -and ($loadBalancerResources|Measure-Object).Count -gt 0){
				#Collect all open ports on load balancer  
				$loadBalancerResources | ForEach-Object{
					$loadBalancerResource = Get-AzLoadBalancer -Name $_.Name -ResourceGroupName $_.ResourceGroupName
					$loadBalancingRules = @($loadBalancerResource.FrontendIpConfigurations | ? { $null -ne $_.PublicIpAddress } | ForEach-Object { $_.LoadBalancingRules })
				
					$loadBalancingRules | ForEach-Object {
						$loadBalancingRuleId = $_.Id;
						$loadBalancingRule = $loadBalancerResource.LoadBalancingRules | ? { $_.Id -eq  $loadBalancingRuleId } | Select-Object -First 1
						$loadBalancerBackendPorts += $loadBalancingRule.BackendPort;
					};   
				}
				
				#If no ports open, Pass the TCP
				if($loadBalancerBackendPorts.Count -eq 0)
				{
					$controlResult.AddMessage("No ports enabled.")       
				}
				#If Ports are open for public in load balancer, map load balancer ports with application endpoint ports and validate if SSL is enabled.
				else
				{
			
				if($isConnectionSuccessful -eq $false)
				{
						$isManual = $true;
						$controlResult.AddMessage("Cannot connect with Service Fabric cluster.")
						$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
				}
				elseif($this.ApplicationList)
					{
						$controlResult.AddMessage("List of publicly exposed port",$loadBalancerBackendPorts) 

						$this.ApplicationList | 
						ForEach-Object{
							$serviceFabricApplication = $_
							Get-ServiceFabricServiceType -ApplicationTypeName $serviceFabricApplication.ApplicationTypeName -ApplicationTypeVersion $serviceFabricApplication.ApplicationTypeVersion | 
							ForEach-Object{
								$currentService = $_
								$serviceManifest = [xml](Get-ServiceFabricServiceManifest -ApplicationTypeName $serviceFabricApplication.ApplicationTypeName -ApplicationTypeVersion $serviceFabricApplication.ApplicationTypeVersion -ServiceManifestName $_.ServiceManifestName)
								if([Helpers]::CheckMember($serviceManifest.ServiceManifest,"Resources.Endpoints"))
								{
									$serviceManifest.ServiceManifest.Resources.Endpoints.ChildNodes | 
									ForEach-Object{
										$endpoint = $_
										$serviceTypeName = $currentService.ServiceTypeName
								
										if(-not [Helpers]::CheckMember($endpoint,"Port"))
										{
											#Add message
											#$childControlResult.AddMessage([VerificationResult]::Passed) 
										}
										else
										{
											if($loadBalancerBackendPorts.Contains([Int32] $endpoint.Port) )
											{                      
												if([Helpers]::CheckMember($endpoint,"Protocol") -and $endpoint.Protocol -eq "https"){  
													$compliantPort.Add($serviceFabricApplication.ApplicationName.OriginalString + "/" + $serviceTypeName + "/"+$endpoint.Name,  $endpoint.Port) 
													
												}
												elseif([Helpers]::CheckMember($endpoint,"Protocol") -and $endpoint.Protocol -eq "http"){  
													$isPassed = $false;
											
													$nonCompliantPort.Add($serviceFabricApplication.ApplicationName.OriginalString + "/" + $serviceTypeName + "/"+$endpoint.Name,  $endpoint.Port) 
												}
												else {  
													$isPassed = $false;
													$nonCompliantPort.Add($serviceFabricApplication.ApplicationName.OriginalString + "/" + $serviceTypeName + "/"+$endpoint.Name,  $endpoint.Port) 
												
												}                            
											}
											else
											{   
												$compliantPort.Add($serviceFabricApplication.ApplicationName.OriginalString + "/" + $serviceTypeName + "/"+$endpoint.Name,  $endpoint.Port)                     
												
											}
										} 							
									} 
								}
											
							}
						}             
					}
					else
					{
						$controlResult.AddMessage("No service found.")
					}    
				} 	

				if($compliantPort.Keys.Count -gt 0)
				{
					$controlResult.AddMessage("Following endpoint(s) are compliant");
					$compliantPort.Keys  | Foreach-Object {
						$controlResult.AddMessage("Endpoint: '$_' Port: $($compliantPort[$_])");
					}
				}

				if($nonCompliantPort.Keys.Count -gt 0)
				{
					$controlResult.AddMessage("Following publicly exposed endpoint(s) are not secured using SSL");
					$nonCompliantPort.Keys  | Foreach-Object {
						$controlResult.AddMessage("EndPoint: '$_' Port: $($nonCompliantPort[$_])");
					}
				}

				if($isManual)
				{
					$controlResult.VerificationResult = [VerificationResult]::Manual;
				}
				elseif($isPassed)
				{
					$controlResult.VerificationResult = [VerificationResult]::Passed;
				}
				else
				{
					$controlResult.VerificationResult = [VerificationResult]::Failed;
					$controlResult.SetStateData("Following ports are non-complaint", $nonCompliantPort);
				}
			}else{
				$controlResult.AddMessage("Not able to fetch details of Load Balancer resources linked with cluster.");
				$controlResult.AddMessage("Manually verify that all publicly exposed endpoint(s) are secured using SSL");
				$controlResult.VerificationResult = [VerificationResult]::Manual;
			}
			
		}else{
			
			$scanSource = [RemoteReportHelper]::GetScanSource();
			if($scanSource -eq [ScanSource]::SpotCheck)
			{ 
			   $controlResult.AddMessage("Service Fabric SDK is not present in user machine. To evaluate this control SDK should be available on user machine.")
			}
		    $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
			$controlResult.VerificationResult = [VerificationResult]::Manual;
		}
	
			
		return $controlResult       
	}
	[void] CheckClusterAccess()
	{	
		#Function to validate authentication and connect with Service Fabric cluster     
        $sfCluster = $null       
        $uri = ([System.Uri]$this.ResourceObject.Properties.managementEndpoint).Host                
        $primaryNodeType = $this.ResourceObject.Properties.nodeTypes | Where-Object { $_.isPrimary -eq $true }
                
        $ClusterConnectionUri = $uri +":"+ $primaryNodeType.clientConnectionEndpointPort
        $this.PublishCustomMessage("Connecting with Service Fabric cluster...")
        $this.PublishCustomMessage("Validating if Service Fabric is secure...")
        
        $isClusterSecure =  [Helpers]::CheckMember($this.ResourceObject.Properties,"certificate" )               
                
        if($isClusterSecure)
        {
			$serviceFabricCertificate = $this.ResourceObject.Properties.certificate              
            $this.PublishCustomMessage("Service Fabric is secure")
            $CertThumbprint= $this.ResourceObject.Properties.certificate.thumbprint
			$serviceFabricAAD = $null
			if([Helpers]::CheckMember($this.ResourceObject.Properties,"azureActiveDirectory" ))
			{
			 $serviceFabricAAD =$this.ResourceObject.Properties.azureActiveDirectory
			}  
            if($null -ne $serviceFabricAAD)
            {
                try
                {
                    $this.PublishCustomMessage("Connecting Service Fabric using AAD...")
                    $sfCluster = Connect-ServiceFabricCluster -ConnectionEndpoint $ClusterConnectionUri -AzureActiveDirectory -ServerCertThumbprint $CertThumbprint #-SecurityToken "
                     $this.PublishCustomMessage("Connection using AAD is successful.")
                }
                catch
                {
					throw ([SuppressedException]::new(("You may not have permission to connect with cluster"), [SuppressedExceptionType]::InvalidOperation))
                }
            }              
            else
            {
                $this.PublishCustomMessage("Validating if cluster certificate present on machine...")
                $IsCertPresent = (Get-ChildItem -Path "Cert:\$($this.CertStoreLocation)\$($this.CertStoreName)" | Where-Object {$_.Thumbprint -eq $CertThumbprint }| Measure-Object).Count                   
                if($IsCertPresent)
                {
					$this.PublishCustomMessage("Connecting Service Fabric using certificate")
					$sfCluster = Connect-serviceFabricCluster -ConnectionEndpoint $ClusterConnectionUri -KeepAliveIntervalInSec 300 -X509Credential -ServerCertThumbprint $CertThumbprint -FindType FindByThumbprint -FindValue $CertThumbprint -StoreLocation $this.CertStoreLocation -StoreName $this.CertStoreName 
                }
                else
                {
					throw ([SuppressedException]::new(("Cannot connect with Service Fabric due to unavailability of cluster certificate in local machine. Validate cluster certificate is present in 'CurrentUser' location."), [SuppressedExceptionType]::InvalidOperation))
                }
            }                    
        }
        else
        {
            $this.PublishCustomMessage("Service Fabric is unsecure");
            $sfCluster = Connect-serviceFabricCluster -ConnectionEndpoint $ClusterConnectionUri
            $this.PublishCustomMessage("Service Fabric connection is successful");
        }
	}

	[PSObject] GetLinkedResources([string] $resourceType)
	{
	    return  Get-AzResource -TagName $this.DefaultTagName -TagValue $this.ClusterTagValue | Where-Object { ($_.ResourceType -EQ $resourceType) -and ($_.ResourceGroupName -eq $this.ResourceContext.ResourceGroupName) }
	}	

}