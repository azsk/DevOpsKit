Set-StrictMode -Version Latest 
class ServiceFabric : SVTBase
{       
    hidden [PSObject] $ResourceObject;
	hidden [string] $ClusterTagValue;
	hidden [PSObject] $ApplicationList;
	hidden [string] $DefaultTagName = "clusterName"
    hidden [string] $CertStoreLocation = "CurrentUser"
    hidden [string] $CertStoreName = "My"
    ServiceFabric([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
		
    }

	hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) 
		{
            $this.ResourceObject =  Get-AzureRmResource -ResourceGroupName $this.ResourceContext.ResourceGroupName -ResourceType $this.ResourceContext.ResourceType -Name $this.ResourceContext.ResourceName -ApiVersion 2016-03-01        

			$this.ResourceObject.Tags.GetEnumerator() | Where-Object { $_.Key -eq $this.DefaultTagName } | ForEach-Object {$this.ClusterTagValue = $_.Value }
			
			## Commented below two lines of code. This will be covered once Service Fabric module gets available as part of AzureRM modules set.
			#$this.CheckClusterAccess();
			#$this.ApplicationList = Get-ServiceFabricApplication 
            
			if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
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
					throw $_
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
			if($clusterProtectionLevel.value -eq "EncryptAndSign")
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
		[ControlResult[]] $controlResultList = @()		

		$virtualNetworkResources = $this.GetLinkedResources("Microsoft.Network/virtualNetworks") 
        #Iterate through all cluster linked VNet resources      
		$virtualNetworkResources |ForEach-Object{            
			$virtualNetwork=Get-AzureRmVirtualNetwork -ResourceGroupName $_.ResourceGroupName -Name $_.Name 
			$subnetConfig = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $virtualNetwork
			#Iterate through Subnet and validate if NSG is configured or not
			$subnetConfig | ForEach-Object{
				$subnetName =$_.Name
				[ControlResult] $childControlResult = $this.CreateControlResult($subnetName);    				
				$isCompliant =  ($null -ne $_.NetworkSecurityGroup)		
				#If NSG is enabled on Subnet display all security rules applied 
				if($isCompliant)
				{
					$nsgResource = Get-AzureRmResource -ResourceId $_.NetworkSecurityGroup.Id
					$nsgResourceDetails = Get-AzureRmNetworkSecurityGroup -ResourceGroupName $nsgResource.ResourceGroupName -Name $nsgResource.Name                
					
					$childControlResult.AddMessage([VerificationResult]::Verify, "Validate NSG security rules applied on subnet '$subnetName' ", $nsgResourceDetails)					
					$childControlResult.SetStateData("NSG security rules applied on subnet", $nsgResourceDetails);
				}
				#If NSG is not enabled on Subnet, fail the TCP with Subnet details
				else
				{
					$childControlResult.AddMessage([VerificationResult]::Failed, "NSG is not configured on subnet '$subnetName'",$_)		
				} 
				$controlResultList += $childControlResult 
			}                
		}

		return $controlResultList
	}

	hidden [ControlResult[]] CheckStorageEncryption([ControlResult] $controlResult)
	{
		[ControlResult[]] $controlResultList = @()
	    $vmssResources = $this.GetLinkedResources("Microsoft.Compute/virtualMachineScaleSets")
		#Iterate through cluster linked vmss resources  
		$vmssResources | ForEach-Object{
			$vmssResourceId = Get-AzureRmResource -ResourceId $_.ResourceId 
			#Get all storage account details where vmss disk is stored
			if([Helpers]::CheckMember($vmssResourceId.Properties.virtualMachineProfile.storageProfile.osDisk,"vhdContainers"))
			{
				$vmssResourceId.Properties.virtualMachineProfile.storageProfile.osDisk.vhdContainers | ForEach-Object{
					$storageName = Convert-String -InputObject $_ -Example "https://accountname.blob.core.windows.net/vhds=accountname"
					$storageAccount = Get-AzureRmStorageAccount -Name $storageName -ResourceGroupName $this.ResourceContext.ResourceGroupName              
					[ControlResult] $childControlResult = $this.CreateControlResult($storageName);
					#Validate if storage account storing vmss os disk/Cluster data is encrypted or not  
					if($null -ne $storageAccount.Encryption)
					{                     
						$childControlResult.AddMessage([VerificationResult]::Passed, "Storage encryption is enabled for '$storageName'");
					}
					else
					{                        
						$childControlResult.AddMessage([VerificationResult]::Failed, "Storage encryption is not enabled for '$storageName'");
					}				
					$controlResultList += $childControlResult
				}
			}
			else
			{
				$controlResult.AddMessage([MessageData]::new("Unable to fetch storage account of VHDs. Manually verify that encryption must be enabled on all storage accounts which store VHDs of Service Fabric cluster VMs."));
				$controlResult.VerificationResult = [VerificationResult]::Manual;
                $controlResultList += $controlResult
			}
		}
		return $controlResultList; 
	}

	hidden [ControlResult[]] CheckVmssDiagnostics([ControlResult] $controlResult)
	{
		[ControlResult[]] $controlResultList = @()
		$vmssResources = $this.GetLinkedResources("Microsoft.Compute/virtualMachineScaleSets")
		#Iterate through cluster linked vmss resources             
		$vmssResources | ForEach-Object{
			$VMScaleSetName = $_.Name	
			[ControlResult] $childControlResult = $this.CreateControlResult($VMScaleSetName);  		
			$nodeTypeResource = Get-AzureRmVmss -ResourceGroupName  $_.ResourceGroupName -VMScaleSetName  $VMScaleSetName
			$diagnosticsSettings = $nodeTypeResource.VirtualMachineProfile.ExtensionProfile.Extensions  | ? { $_.Type -eq "IaaSDiagnostics" -and $_.Publisher -eq "Microsoft.Azure.Diagnostics" }
			#Validate if diagnostics is enabled on vmss 
			if($null -ne $diagnosticsSettings )
			{                
				$childControlResult.AddMessage([VerificationResult]::Passed, "Diagnostics is enabled on Vmss '$VMScaleSetName'",$diagnosticsSettings);
			}
			else
			{
				$childControlResult.AddMessage([VerificationResult]::Failed, "Diagnostics is disabled on Vmss '$VMScaleSetName'");
			} 
        
			$controlResultList += $childControlResult 
		}
		return $controlResultList        
	}

	hidden [ControlResult[]] CheckStatefulServiceReplicaSetSize([ControlResult] $controlResult)
	{
		[ControlResult[]] $controlResultList = @() 
		#Iterate through the applications present in cluster     
		if($this.ApplicationList)
		{
			$this.ApplicationList | ForEach-Object{
				$serviceFabricApplication = $_

				Get-ServiceFabricService -ApplicationName $serviceFabricApplication.ApplicationName  | ForEach-Object{                
					$serviceName = $_.ServiceName 
					[ControlResult] $childControlResult = $this.CreateControlResult($serviceName);  	
					$serviceDescription = Get-ServiceFabricServiceDescription -ServiceName $_.ServiceName 
					#Filter application with Stateful service type
					if($serviceDescription.ServiceKind -eq "Stateful")
					{
						[ControlResult] $childControlResult = $this.CreateControlResult($serviceName)     
						#Validate minimum replica and target replica size for each service 					
						$isCompliant = !($serviceDescription.MinReplicaSetSize -lt 3 -or $serviceDescription.TargetReplicaSetSize -lt 3)

						if($isCompliant){ $controlStatus = [VerificationResult]::Passed } else{ $controlStatus = [VerificationResult]::Failed }
						$childControlResult.AddMessage([VerificationResult]::Failed, "Replica set size details for service '$serviceName'",$serviceDescription)
						$controlResultList += $childControlResult 
					}                
				}
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed,"No stateful service found.")
			$controlResultList += $controlResult
		}
		return $controlResultList
	}

	hidden [ControlResult[]] CheckStatelessServiceInstanceCount([ControlResult] $controlResult)
	{
	    [ControlResult[]] $controlResultList = @()  
		#Iterate through the applications present in cluster         
		if($this.ApplicationList)
		{
			$this.ApplicationList | ForEach-Object{
				$serviceFabricApplication = $_
				Get-ServiceFabricService -ApplicationName $serviceFabricApplication.ApplicationName | 
				ForEach-Object{
					$serviceName = $_.ServiceName         
					[ControlResult] $childControlResult = $this.CreateControlResult($serviceName);         
					$serviceDescription = Get-ServiceFabricServiceDescription -ServiceName $serviceName 
					#Filter application with Stateless service type
					if($serviceDescription.ServiceKind -eq "Stateless")
					{					
						$instantCount = $serviceDescription.InstanceCount
						Add-OutputLogEvent -OutputLogFilePath $outputLogFilePath -EventData "Service Fabric service [$serviceName] has instance count : [$instantCount]"  
						#Validate instancecount it -1 (auto) or greater than equal to 3              
						if($serviceDescription.InstanceCount -eq -1 -and $serviceDescription.InstanceCount -ge 3){$controlStatus = [VerificationResult]::Passed } else{ $controlStatus = [VerificationResult]::Failed }
						$childControlResult.AddMessage([VerificationResult]::Failed, "Instance count for service '$serviceName'",$serviceDescription)
						$controlResultList += $childControlResult 
					} 
				} 
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed,"No stateless service found.")
			$controlResultList += $controlResult
		} 
		return $controlResultList        
	}

	hidden [ControlResult[]] CheckPublicEndpointSSL([ControlResult] $controlResult)
	{
		[ControlResult[]] $controlResultList = @() 
		$loadBalancerBackendPorts = @()
		$loadBalancerResources = $this.GetLinkedResources("Microsoft.Network/loadBalancers")
		#Collect all open ports on load balancer  
		$loadBalancerResources | ForEach-Object{
			$loadBalancerResource = Get-AzureRmLoadBalancer -Name $_.Name -ResourceGroupName $_.ResourceGroupName
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
			$controlResult.AddMessage([VerificationResult]::Passed,"No ports enabled.")  
			$controlResultList += $controlResult      
		}
		#If Ports are open for public in load balancer, map load balancer ports with application endpoint ports and validate if SSL is enabled.
		else
		{
			$controlResult.AddMessage("List of publicly exposed port",$loadBalancerBackendPorts)        
         
			if($this.ApplicationList)
			{
				$this.ApplicationList | 
				ForEach-Object{
					$serviceFabricApplication = $_
					Get-ServiceFabricServiceType -ApplicationTypeName $serviceFabricApplication.ApplicationTypeName -ApplicationTypeVersion $serviceFabricApplication.ApplicationTypeVersion | 
					ForEach-Object{
						$currentService = $_
						$serviceManifest = [xml](Get-ServiceFabricServiceManifest -ApplicationTypeName $serviceFabricApplication.ApplicationTypeName -ApplicationTypeVersion $serviceFabricApplication.ApplicationTypeVersion -ServiceManifestName $_.ServiceManifestName)

						$serviceManifest.ServiceManifest.Resources.Endpoints.ChildNodes | 
						ForEach-Object{
							$endpoint = $_
							$serviceTypeName = $currentService.ServiceTypeName
							[ControlResult] $childControlResult = $this.CreateControlResult($serviceTypeName +"_" + $endpoint.Name);  
                    
							if($null -eq $endpoint.Port)
							{
								#Add message
								$childControlResult.AddMessage([VerificationResult]::Passed) 
							}
							else
							{
								if($loadBalancerBackendPorts.Contains($endpoint.Port) )
								{                      
									if($endpoint.Protocol -eq "https"){  $controlResult.AddMessage([VerificationResult]::Passed,"Endpoint is protected with SSL") }
									elseif($endpoint.Protocol -eq "http"){  $controlResult.AddMessage([VerificationResult]::Failed,"Endpoint is not protected with SSL") }
									else {  $controlResult.AddMessage([VerificationResult]::Verify,"Verify if endpoint is protected with SSL",$endpoint) }                            
								}
								else
								{                        
									$controlResult.AddMessage([VerificationResult]::Passed,"Endpoint is not publicly opened")
								}
							}  
							$controlResultList += $childControlResult 
						}                   
					}
				}             
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed,"No service found.")
				$controlResultList += $controlResult
			}    
		} 
		return $controlResultList        
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
            $serviceFabricAAD =$this.ResourceObject.Properties.azureActiveDirectory
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
                $IsCertPresent = (Get-ChildItem -Path Cert:\$this.CertStoreLocation\$this.CertStoreName | Where-Object {$_.Thumbprint -eq $CertThumbprint }).Count                    
                if($IsCertPresent)
                {
                    $this.PublishCustomMessage("Connecting Service Fabric using certificate")
                    $sfCluster = Connect-serviceFabricCluster -ConnectionEndpoint $ClusterConnectionUri -KeepAliveIntervalInSec 10 -X509Credential -ServerCertThumbprint $CertThumbprint -FindType FindByThumbprint -FindValue $CertThumbprint -StoreLocation $this.CertStoreLocation -StoreName $this.CertStoreName 
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
	    return  Get-AzureRmResource -TagName $this.DefaultTagName -TagValue $this.ClusterTagValue | Where-Object { ($_.ResourceType -EQ $resourceType) -and ($_.ResourceGroupName -eq $this.ResourceContext.ResourceGroupName) }
	}	
}
