using namespace Microsoft.Azure.Commands.Network.Models
using namespace Microsoft.Azure.Commands.Compute.Models
using namespace Microsoft.Azure.Management.Compute.Models
Set-StrictMode -Version Latest 

class VirtualMachine: SVTBase
{       
    hidden [PSVirtualMachine] $ResourceObject;
    hidden [PSNetworkInterface[]] $VMNICs = $null;
	hidden [PSObject] $ASCSettings = $null;
	hidden [bool] $IsVMDeallocated = $false
	hidden [VMDetails] $VMDetails = [VMDetails]::new()
	hidden [PSObject] $VMControlSettings = $null;
	hidden [string] $Workspace = "";

    VirtualMachine([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
        $this.GetResourceObject();		
    }
    
	VirtualMachine([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
		$this.GetVMDetails();
		$metadata = @{
			VMDetails = $this.VMDetails;
			ASCDetails = $this. ASCSettings;
		};		
		$this.AddResourceMetadata($metadata);
		
		#OS type must always be present in configuration setting file
		if([Helpers]::CheckMember($this.ControlSettings.VirtualMachine, $this.VMDetails.OSType)){
			$this.VMControlSettings = $this.ControlSettings.VirtualMachine.$($this.VMDetails.OSType);
		}
    }

	[ControlItem[]] ApplyServiceFilters([ControlItem[]] $controls)
	{
		$result = @();
		#Check VM type
		$VMType = $this.ResourceObject.StorageProfile.OsDisk.OsType
        if($VMType -eq [Microsoft.Azure.Management.Compute.Models.OperatingSystemTypes]::Linux)
        {
			$result += $controls | Where-Object { $_.Tags -contains "Linux" };
		}
		elseif($VMType -eq [Microsoft.Azure.Management.Compute.Models.OperatingSystemTypes]::Windows)
		{
			$result += $controls | Where-Object { $_.Tags -contains "Windows" };;
		}
		if($this.VMDetails.IsVMConnectedToERvNet -and ($result | Where-Object { $_.Tags -contains "ERvNet" } | Measure-Object).Count -gt 0)
		{
			$result=$result | Where-Object { $_.Tags -contains "ERvNet" };
		}
		return $result;
	}

	hidden  GetVMDetails()
	{
		if($this.ResourceObject.StorageProfile.OsDisk)
		{
			$this.VMDetails.OSType = $this.ResourceObject.StorageProfile.OsDisk.OsType
		}
		else
		{
			if($this.ResourceObject.OSProfile -and $this.ResourceObject.OSProfile.LinuxConfiguration)
			{
				$this.VMDetails.OSType = [OperatingSystemTypes]::Linux
			}
			else
			{
				$this.VMDetails.OSType = [OperatingSystemTypes]::Windows
			}
		}

		if($this.ResourceObject.StorageProfile -and $this.ResourceObject.StorageProfile.ImageReference)
		{
			$this.VMDetails.Sku =  $this.ResourceObject.StorageProfile.ImageReference.Sku
			$this.VMDetails.Offer = $this.ResourceObject.StorageProfile.ImageReference.Offer
		}		
		#Get if VM is connected to ERvNet
		$this.VMDetails.IsVMConnectedToERvNet = $this.IsVMConnectedToERvNet()
		#Get VM deallocation status
		$this.VMDetails.IsVMDeallocated = $this.GetVMDeallocationStatus();
	}

	hidden [bool] IsVMConnectedToERvNet()
	{
		$IsVMConnectedToERvNet = $false
		$publicIPs = ""
		$privateIPs = ""
		$this.GetVMNICObjects() |
			ForEach-Object {         
		if($_.IpConfigurations)
				{
					$_.IpConfigurations | 
						ForEach-Object {
							#Fetch Private IPs to persist in the virtual machine metadata
							$privateIPs += $_.PrivateIpAddress + ";"
							#Fetch Public IPs to persist in the virtual machine metadata
							if($_.PublicIpAddress)
							{
								$ipResource = Get-AzureRmResource -ResourceId $_.PublicIpAddress.Id 
								if($ipResource)
								{
									$publicIpObject = Get-AzureRmPublicIpAddress -Name $ipResource.Name -ResourceGroupName $ipResource.ResourceGroupName
									if($publicIpObject)
									{
										#$_.PublicIpAddress = $publicIpObject;
										$publicIPs += $publicIpObject.IpAddress + ";";
									}
								}
							}
							$subnetId = $_.Subnet.Id;		
							$subnetName = $subnetId.Substring($subnetId.LastIndexOf("/") + 1);
							#vnet id = trim '/subnets/' from subnet id 
							$vnetResource = Get-AzureRmResource -ResourceId $subnetId.Substring(0, $subnetId.IndexOf("/subnets/"))

							$vnetResource | ForEach-Object {
								$vnet = $_
								if($null-ne $vnet.properties -and $null -ne $vnet.properties.subnets)
								{
									$vnet.properties.subnets | ForEach-Object {
										$subnet = $_;
										if($subnet.name -eq "GatewaySubnet" -and $null -ne $subnet.properties -and ([Helpers]::CheckMember($subnet.properties,"ipConfigurations")) -and ($subnet.properties.ipConfigurations | Measure-Object).Count -gt 0)
										{
											#41 number is the total character count of "Microsoft.Network/virtualNetworkGateways/"
											$gatewayname = $subnet.properties.ipConfigurations[0].id.Substring($subnet.properties.ipConfigurations[0].id.LastIndexOf("Microsoft.Network/virtualNetworkGateways/") + 41);
											$gatewayname = $gatewayname.Substring(0, $gatewayname.IndexOf("/"));

											$gatewayObject = Get-AzureRmVirtualNetworkGateway -Name $gatewayname -ResourceGroupName $vnet.ResourceGroupName
											if( $gatewayObject.GatewayType -eq "ExpressRoute")
											{
												$IsVMConnectedToERvNet= $true
											}
										}
									}
								}
							}

							#if($vnetResource.ResourceGroupName -in $this.ConvertToStringArray([ConfigurationManager]::GetAzSKConfigData().ERvNetResourceGroupNames))
							#{
							#	$IsVMConnectedToERvNet= $true
							#}
						}
				}
			}


		$this.VMDetails.PublicIPs = $publicIPs;
		$this.VMDetails.PrivateIPs = $privateIPs;
		return $IsVMConnectedToERvNet;
	}

	hidden [bool] GetVMDeallocationStatus()
	{
		$vmStatusObj = Get-AzureRmVM -ResourceGroupName $this.ResourceContext.ResourceGroupName -Name $this.ResourceContext.ResourceName -Status -WarningAction SilentlyContinue 
		if($vmStatusObj.Statuses -and ($vmStatusObj.Statuses | Where-Object { $_.Code.ToLower() -eq "powerState/running" }))
		{
			return $false			
		}
		else
		{
			return $true
		}
	}
	 
    hidden [PSVirtualMachine] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzureRmVM -ResourceGroupName $this.ResourceContext.ResourceGroupName -Name $this.ResourceContext.ResourceName  -WarningAction SilentlyContinue 

            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
			
        }

		#compute ASC object for VM
		$this.ASCSettings = $this.GetASCSettings();

		if($null -ne $this.ASCSettings -and [Helpers]::CheckMember($this.ASCSettings,"properties.resourceDetails"))
		{
			$omsSetting = $this.ASCSettings.properties.resourceDetails | Where-Object {$_.name -eq $this.ControlSettings.VirtualMachine.ASCPolicies.ResourceDetailsKeys.WorkspaceId };
			if($null -ne $omsSetting)
			{
				$this.Workspace = $omsSetting.value;
			}
		}

        return $this.ResourceObject;
    }

	hidden [PSObject] GetASCSettings()
	{
		$result = $null;
		# Commenting this as it's costly call and expected to happen in Set-ASC/SSS/USS 
		try 
		{ 	
			$result = [SecurityCenterHelper]::InvokeSecurityCenterSecurityStatus($this.SubscriptionContext.SubscriptionId);
			if(($result | Measure-Object).Count -gt 0)
			{
				$key = ("$($this.ResourceContext.ResourceName):VirtualMachine").ToLower();
				$vmSecurityState = $null;
				if($result.ContainsKey($key))
				{
					$vmSecurityState = $result[$key];
				}			
				return $vmSecurityState;			
			}			
		}
		catch
		{
			#eat exception if no ASC settings can be found
		}
		return $null;
	}

	hidden [PSNetworkInterface[]] GetVMNICObjects()
    {
        if (-not $this.VMNICs) 
		{
			$this.VMNICs = @();
			if($this.ResourceObject.NetworkProfile -and $this.ResourceObject.NetworkProfile.NetworkInterfaces)
			{
				$this.ResourceObject.NetworkProfile.NetworkInterfaces | 
					ForEach-Object {          
						$currentNic = Get-AzureRmResource -ResourceId $_.Id -ErrorAction SilentlyContinue
						if($currentNic)
						{
							$nicResource = Get-AzureRmNetworkInterface -Name $currentNic.Name `
												-ResourceGroupName $currentNic.ResourceGroupName `
												-ExpandResource NetworkSecurityGroup `
												-ErrorAction SilentlyContinue
							if($nicResource)
							{
								$this.VMNICs += $nicResource;
							}
						}
					}
			}            
        }
        return $this.VMNICs;
    }
	
    hidden [ControlResult] CheckOSVersion([ControlResult] $controlResult)
    {

		$vmSkuDetails = $this.VMDetails | Select-Object OSType,Offer,Sku
		#in the case of classic migrated VM, we have noticed that there is no Metadata present
		if([string]::IsNullOrWhiteSpace($this.VMDetails.Offer) -or [string]::IsNullOrWhiteSpace($this.VMDetails.Sku))
		{
            $controlResult.AddMessage([VerificationResult]::Manual,"No metadata found for this VM. Verify if you are using recommended OS Sku as per Org security policy",$vmSkuDetails); 
			return 	$controlResult;
		}
		$supportedSkuList = $this.VMControlSettings.SupportedSkuList | Where-Object { $_.Offer -eq $this.VMDetails.Offer } 
		if($supportedSkuList)
		{
			if($supportedSkuList.Sku -contains $this.VMDetails.Sku)
			{
				$controlResult.AddMessage([VerificationResult]::Passed,"Virtual Machine OS Sku is compliant with the Org security policy",$vmSkuDetails);				
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Failed,"Virtual Machine OS Sku is not compliant with the Org security policy",$vmSkuDetails);								
			}		
		}
		else
		{
            $controlResult.AddMessage([VerificationResult]::Verify,"Verify if you are using recommended OS Sku as per Org security policy",$vmSkuDetails); 
		}		
		return $controlResult;
    }

	hidden [ControlResult] CheckOSAutoUpdateStatus([ControlResult] $controlResult)
	{		
		#TCP is not applicable for Linux. #This method is deprecated
		if($this.ResourceObject.OSProfile -and $this.ResourceObject.OSProfile.WindowsConfiguration)
		{
			$message = "";
			$verificationResult = [VerificationResult]::Failed;

			if($this.ResourceObject.OSProfile.WindowsConfiguration.EnableAutomaticUpdates -eq $true)
			{
				$verificationResult = [VerificationResult]::Passed;
				$message = "Automatic OS updates are enabled on Windows Virtual Machine";
			}
			else
			{
				$message = "Automatic OS updates are disabled on Windows Virtual Machine. Please enable OS automatic updates in order to comply.";
			}

			$controlResult.AddMessage($verificationResult, $message, $this.ResourceObject.OSProfile.WindowsConfiguration);	
		
		}
		elseif($this.VMDetails.OSType -eq [OperatingSystemTypes]::Linux)
		{
            if([Helpers]::CheckMember($this.ResourceObject.OSProfile,"LinuxConfiguration")){
				$controlResult.AddMessage([VerificationResult]::Manual, "The control is not applicable in case of a Linux Virtual Machine. It's good practice to periodically update the OS of Virtual Machine.", $this.ResourceObject.OSProfile.LinuxConfiguration); 
			}
			else{
				$controlResult.AddMessage([VerificationResult]::Manual, "The control is not applicable in case of a Linux Virtual Machine. It's good practice to periodically update the OS of Virtual Machine.")
			}
		}
		else
		{
            $controlResult.AddMessage([MessageData]::new("We are not able to fetch the required data for the resource", [MessageType]::Error)); 
		}
			
		return $controlResult;
	}

	hidden [ControlResult] CheckAntimalwareStatus([ControlResult] $controlResult)
	{
		#Do not check for deallocated status for the VM and directly show the status from ASC
		if($null -ne $this.ASCSettings -and [Helpers]::CheckMember($this.ASCSettings, "properties.policyAssessments"))
		{
			$antimalwareSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.policyName -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.EndpointProtection};
			if($null -ne $antimalwareSetting)
			{
				$controlResult.AddMessage("VM endpoint protection details:", $antimalwareSetting);
				if($antimalwareSetting.assessmentResult -eq 'Healthy' )
				{				
					$controlResult.AddMessage([VerificationResult]::Passed,"Antimalware is configured correctly on the VM. Validated the status through ASC."); 
				}
				elseif($antimalwareSetting.assessmentResult -eq 'Low')
				{				
					$controlResult.AddMessage([VerificationResult]::Verify,"Validate configurations of antimalware using ASC."); 
				}
				elseif($antimalwareSetting.assessmentResult -eq 'None')
				{					
					$controlResult.AddMessage([VerificationResult]::Manual, "The control is not applicable due to the ASC current policy."); 
				}
				else
				{					
					$controlResult.AddMessage([VerificationResult]::Failed,"Antimalware is not configured correctly on the VM. Validated the status through ASC."); 
				}
			}						
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Manual, "We are not able to check Security Center status right now. Please validate manually.");
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckNSGConfig([ControlResult] $controlResult)
	{
		$controlResult.VerificationResult = [VerificationResult]::Failed;
		$this.GetVMNICObjects() |
			ForEach-Object {          
				#Check NSGs applied at NIC level
				if($_.NetworkSecurityGroup)
				{
					if($_.NetworkSecurityGroup.SecurityRules.Count -gt 0)
					{
						$controlResult.AddMessage("Validate NSG security rules applied to NIC - [$($_.Name)], Total - $($_.NetworkSecurityGroup.SecurityRules.Count)", $_.NetworkSecurityGroup.SecurityRules);          	
					}
					if($_.NetworkSecurityGroup.DefaultSecurityRules.Count -gt 0)
					{
						$controlResult.AddMessage("Validate default NSG security rules applied to NIC - [$($_.Name)], Total - $($_.NetworkSecurityGroup.DefaultSecurityRules.Count)", $_.NetworkSecurityGroup.DefaultSecurityRules); 
					}
					$controlResult.VerificationResult = [VerificationResult]::Verify;
					$controlResult.SetStateData("NSG security rules", $_.NetworkSecurityGroup.SecurityRules);
				}  
			
				#check NSGs applied at subnet level       
				if($_.IpConfigurations)
				{
					$_.IpConfigurations | 
						ForEach-Object {                   
							$subnetId = $_.Subnet.Id;		
							$subnetName = $subnetId.Substring($subnetId.LastIndexOf("/") + 1);
							#vnet id = trim '/subnets/' from subnet id 
							$vnetResource = Get-AzureRmResource -ResourceId $subnetId.Substring(0, $subnetId.IndexOf("/subnets/"))
							if($vnetResource)
							{
								$vnetObject = Get-AzureRmVirtualNetwork -Name $vnetResource.Name -ResourceGroupName $vnetResource.ResourceGroupName
								if($vnetObject)
								{
									$subnetConfig = Get-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnetObject
									if($subnetConfig -and $subnetConfig.NetworkSecurityGroup -and $subnetConfig.NetworkSecurityGroup.Id)
									{
										$nsgResource = Get-AzureRmResource -ResourceId $subnetConfig.NetworkSecurityGroup.Id
										if($nsgResource)
										{
											$nsgObject = Get-AzureRmNetworkSecurityGroup -Name $nsgResource.Name -ResourceGroupName $nsgResource.ResourceGroupName
											if($nsgObject)
											{
												if($nsgObject.SecurityRules.Count -gt 0)
												{
													$controlResult.AddMessage("Validate  NSG security rules applied to Subnet - [$subnetName] in Virtual Network - [$($vnetResource.Name)]. Total - $($nsgObject.SecurityRules.Count)", $nsgObject.SecurityRules);			                           
												}
												
												if($nsgObject.DefaultSecurityRules.Count -gt 0)
												{
													$controlResult.AddMessage("Validate default NSG security rules applied to Subnet - [$subnetName] in Virtual Network - [$($vnetResource.Name)]. Total - $($nsgObject.DefaultSecurityRules.Count)", $nsgObject.DefaultSecurityRules);
												}
												$controlResult.VerificationResult = [VerificationResult]::Verify;
												$controlResult.SetStateData("NSG security rules", $nsgObject.SecurityRules);
											}
										}
									}
								}
							}
						}           
				}            
			}
		if($this.VMDetails.IsVMConnectedToERvNet)
		{
			$controlResult.AddMessage("This VM is part of an ExpressRoute connected virtual network.")	
		}
		if($controlResult.VerificationResult -ne [VerificationResult]::Verify -and $this.VMDetails.IsVMConnectedToERvNet)
		{			
			$controlResult.AddMessage("No NSG was found on Virtual Machine subnet or NIC.")	
			$controlResult.VerificationResult = [VerificationResult]::Passed;
		}
		elseif($controlResult.VerificationResult -ne [VerificationResult]::Verify)
		{
			$controlResult.AddMessage("No NSG was found on Virtual Machine subnet or NIC.")		
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckPublicIP([ControlResult] $controlResult)
	{	
		$publicIps = @();
        $this.GetVMNICObjects() | 
			ForEach-Object {
				$_.IpConfigurations | Where-Object { $_.PublicIpAddress } |
					ForEach-Object {
						$ipResource = Get-AzureRmResource -ResourceId $_.PublicIpAddress.Id 
						if($ipResource)
						{
							$publicIpObject = Get-AzureRmPublicIpAddress -Name $ipResource.Name -ResourceGroupName $ipResource.ResourceGroupName
							if($publicIpObject)
							{
								$_.PublicIpAddress = $publicIpObject;
								$publicIps += $publicIpObject;
							}
						}
					}
			}
		 
		if($this.VMDetails.IsVMConnectedToERvNet)
		{
			$controlResult.AddMessage("This VM is part of an ExpressRoute connected virtual network. You must not have any Public IP assigned to such VM. ");
		}
		if($publicIps.Count -gt 0 -and $this.VMDetails.IsVMConnectedToERvNet)
		{              
			$controlResult.AddMessage([VerificationResult]::Failed, "Total Public IPs Found- $($publicIps.Count)", $publicIps);  
			$controlResult.SetStateData("Public IP(s) associated with Virtual Machine", $publicIps);
		}
		elseif($publicIps.Count -gt 0)
		{
			$controlResult.AddMessage([VerificationResult]::Verify, "Validate Public IP(s) associated with Virtual Machine. Total - $($publicIps.Count)", $publicIps);  
			$controlResult.SetStateData("Public IP(s) associated with Virtual Machine", $publicIps);
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed, "No Public IP is associated with Virtual Machine");
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckDiskEncryption([ControlResult] $controlResult)
	{	
		if(-not $this.VMDetails.IsVMDeallocated)
		{
			$ascDiskEncryptionStatus = $false;

			if($null -ne $this.ASCSettings -and [Helpers]::CheckMember($this.ASCSettings, "properties.policyAssessments"))
			{
				$adeSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.policyName -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.DiskEncryption};
				if($null -ne $adeSetting)
				{
					if($adeSetting.assessmentResult -eq 'Healthy')
					{
						$ascDiskEncryptionStatus = $true;
					}
				}
				$controlResult.AddMessage("VM disk encryption details:", $adeSetting);
			}				
				
			if($ascDiskEncryptionStatus)
			{
				$verificationResult  = [VerificationResult]::Passed;
				$message = "All Virtual Machine disks (OS and Data disks) are encrypted. Validated the status through ASC.";
				$controlResult.AddMessage($verificationResult, $message);
			}
			else
			{            
				$verificationResult  = [VerificationResult]::Failed;
				$message = "All Virtual Machine disks (OS and Data disks) are not encrypted. Validated the status through ASC.";
				$controlResult.AddMessage($verificationResult, $message);
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Verify, "This VM is currently in a 'deallocated' state. Unable to check security controls on it.");
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckASCStatus([ControlResult] $controlResult)
	{
		#This is deprecated method. Commented the code below
		#$isManual = $false;
        # if($this.ASCSettings) 
        # {        
		# 	if($this.ASCSettings.SecurityState -ne 'Healthy')
		# 	{
		# 		$controlResult.VerificationResult = [VerificationResult]::Failed

		# 	}
		# 	else
		# 	{
		# 		$controlResult.VerificationResult = [VerificationResult]::Passed
		# 	}

		# 	$controlResult.AddMessage("Security Center status for Virtual Machine [$($this.ResourceContext.ResourceName)] is: [$($this.ASCSettings.SecurityState)]", $this.ASCSettings);
		# 	$controlResult.SetStateData("Security Center status for Virtual Machine", $this.ASCSettings);
        # }
        # else
        # {            
        #     $isManual = $true;
        # }

        # if($isManual)
       	# {
		# 	$controlResult.AddMessage([VerificationResult]::Manual, "We are not able to check Security Center status right now. Please validate manually.");
		# }

		 return $controlResult;
	}

	#No contol found with this method name
	hidden [ControlResult] CheckASCVulnerabilities([ControlResult] $controlResult)
	{
		$ascVMVulnerabilitiesStatusHealthy = $false;

		if($null -ne $this.ASCSettings -and [Helpers]::CheckMember($this.ASCSettings, "properties.policyAssessments"))
		{
			$vulnSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.policyName -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.VulnerabilityScan};
			if($null -ne $vulnSetting)
			{
				if($vulnSetting.assessmentResult -eq 'Healthy')
				{
					$ascVMVulnerabilitiesStatusHealthy = $true;
				}
			}
			$controlResult.AddMessage("VM vuln scan details:", $vulnSetting);
		}			
		
		if($ascVMVulnerabilitiesStatusHealthy)
		{
			$controlResult.VerificationResult = [VerificationResult]::Passed

		}
		else
		{
			$controlResult.VerificationResult = [VerificationResult]::Failed
		}

		$controlResult.AddMessage("Security Center VM Vulnerability status for Virtual Machine [$($this.ResourceContext.ResourceName)]", $ascVMVulnerabilitiesStatusHealthy);		

		return $controlResult;
	}

	hidden [ControlResult] CheckASCVMMissingPatchingStatus([ControlResult] $controlResult)
	{
		#Do not check for deallocated status for the VM and directly show the status from ASC
		$isVerify = $false;
		$ASCApprovedPatchStatus=$this.VMControlSettings.ASCApprovedPatchingHealthStatuses;
		#Get VM ASC Setting
		$ASCSettingsforVM=$this.ASCSettings;
		if($null -ne $ASCSettingsforVM)
		{
				# workspace associated by ASC to send logs for this VM
				$workspaceId=$this.Workspace;
				$queryforPatchDetails=[string]::Format($this.VMControlSettings.QueryforMissingPatches,($this.ResourceContext.ResourceId).ToLower());       		

				$ascPatchStatus = "";

				if($null -ne $this.ASCSettings -and [Helpers]::CheckMember($this.ASCSettings, "properties.policyAssessments"))
				{
					$patchSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.policyName -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.OSUpdates};
					if($null -ne $patchSetting)
					{
						$ascPatchStatus = $patchSetting.assessmentResult;
					}
					$controlResult.AddMessage("VM patch status details:", $patchSetting);
				}		
				
				if($ascPatchStatus -in $ASCApprovedPatchStatus)
				{
					$controlResult.VerificationResult = [VerificationResult]::Passed	
				}
				else
				{
					$controlResult.VerificationResult=[VerificationResult]::Verify;
					$controlResult.AddMessage("Details of missing patches can be obtained from the following workspace");
					$controlResult.AddMessage("Workspace : ",$workspaceId);
					$controlResult.AddMessage("The following query can be used to obtain patch details:");
					$controlResult.AddMessage("Query : ",$queryforPatchDetails);
				}				
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Manual, "We are not able to check Security Center status right now. Please validate manually.");
		}
	  return $controlResult;
	}

	hidden [ControlResult] CheckASCVMRecommendations([ControlResult] $controlResult)
	{

		$isManual = $false;
		$result = $null 
		
		$activeRecommendations = @()
		$ASCWhitelistedRecommendations = @();
		$ASCWhitelistedRecommendations += $this.VMControlSettings.ASCRecommendations;
		#[Helpers]::RegisterResourceProviderIfNotRegistered([SecurityCenterHelper]::ProviderNamespace);
		$tasks = [SecurityCenterHelper]::InvokeGetASCTasks($this.SubscriptionContext.SubscriptionId);
        $found = $false;
		if($null -ne $ASCWhitelistedRecommendations -and $null -ne $tasks)
		{
			$tasks | ForEach-Object {
				$recommendation = $_;
				if(($ASCWhitelistedRecommendations | Where-Object { $_ -eq $recommendation.Name -and `
																			$recommendation.State -eq "Active" -and`
																			$recommendation.ResourceId -eq $this.ResourceContext.ResourceId} | Measure-Object).Count -gt 0)
				{
					$found = $true;
					$activeRecommendations += $_;
				}
			}
		}
		elseif($null -ne $tasks -and ($tasks | Where-Object { $_.State -eq "Active" -and $_.ResourceId -eq $this.ResourceContext.ResourceId} | Measure-Object).Count -gt 0)
		{
			$found = $true;
			$activeRecommendations = $tasks | Where-Object { $_.State -eq "Active" -and $_.ResourceId -eq $this.ResourceContext.ResourceId} 
		}

		if($found)
		{
			$controlResult.SetStateData("Active recommendations in Security Center", $activeRecommendations);
			$controlResult.AddMessage([VerificationResult]::Failed,"Azure Security Center has active recommendations that need to resolved.")
		}
		else {
			$controlResult.VerificationResult =[VerificationResult]::Passed
		}

		$controlResult.AddMessage(($activeRecommendations | Select-Object Name, State, ResourceId));

		return $controlResult
	}

	hidden [ControlResult] CheckASCVMSecurityBaselineStatus([ControlResult] $controlResult)
	{
		
		$isVerfiy= $false;
		$baselineIds = @();
		$baselineIds += $this.VMControlSettings.BaselineIds
		$queryforFailingBaseline=[string]::Format($this.VMControlSettings.QueryforBaselineRule,($this.ResourceContext.ResourceId).ToLower());
		$ASCApprovedStatuses=$this.VMControlSettings.ASCApprovedBaselineStatuses
		# Get ASC Settings for the VM
		$ASCSettingsforVM=$this.ASCSettings;

		if($null -ne $ASCSettingsforVM)
		{
			# workspace associated by ASC to send logs for this VM
			$workspaceId=$this.Workspace;
			$vulnStatus = "";

			if($null -ne $this.ASCSettings -and [Helpers]::CheckMember($this.ASCSettings, "properties.policyAssessments"))
			{
				$vulnSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.policyName -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.VulnerabilityScan};
				if($null -ne $vulnSetting)
				{
					$vulnStatus = $vulnSetting.assessmentResult;
				}
				$controlResult.AddMessage("VM patch status details:", $vulnSetting);
			}		

			if($vulnStatus -in  $ASCApprovedStatuses)
			{
				$controlResult.VerificationResult = [VerificationResult]::Passed
			}
			else
			{
				$controlResult.VerificationResult = [VerificationResult]::Verify
				$controlResult.AddMessage("Unable to validate baseline status from workspace.Please verify.");
				$controlResult.AddMessage("Details of failing baseline rules can be obtained from OMS workspace :" ,$workspaceId);
				$controlResult.AddMessage("The following query can be used to obtain failing baseline rules :  ",$queryforFailingBaseline);
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Manual, "We are not able to check Security Center status right now. Please validate manually.");
		}
		return $controlResult;
	}
	
	hidden [ControlResult] CheckVMDiagnostics([ControlResult] $controlResult)
	{		
		if($this.ResourceObject.Extensions)
		{
			$diagnosticExtensionType = if($this.VMDetails.OSType -eq [OperatingSystemTypes]::Linux) { "LinuxDiagnostic" } else { "IaaSDiagnostics" }
			
			$diagExtension = $this.ResourceObject.Extensions | Where-Object { $_.VirtualMachineExtensionType -eq $diagnosticExtensionType } | Select-Object -First 1
			if($diagExtension -and ($diagExtension.ProvisioningState -eq "Succeeded"))
			{
				$controlResult.AddMessage([VerificationResult]::Passed, "'$diagnosticExtensionType' extension is installed on Virtual Machine");
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "'$diagnosticExtensionType' extension is either not installed or provisioning failed on Virtual Machine");
			}
		}
		else
		{
            $controlResult.AddMessage([MessageData]::new("We are not able to fetch the required data for the resource", [MessageType]::Error)); 
		}

		return $controlResult;
	}

	hidden [ControlResult] CheckOpenPorts([ControlResult] $controlResult)
	{	
		if(-not $this.VMDetails.IsVMDeallocated)
		{
			
			$isManual = $false
			$controlResult.AddMessage("Checking for Virtual Machine management ports",$this.VMControlSettings.ManagementPortList);
			$vulnerableNSGsWithRules = @();
			$effectiveNSG = $null;
			$openPortsList =@();
			$this.GetVMNICObjects() | 
				ForEach-Object {	
					try
					{
						$effectiveNSG = Get-AzureRmEffectiveNetworkSecurityGroup -NetworkInterfaceName $_.Name -ResourceGroupName $_.ResourceGroupName -WarningAction SilentlyContinue -ErrorAction Stop
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
						
						if($this.VMControlSettings -and $this.VMControlSettings.ManagementPortList)
						{
							Foreach($PortDetails in  $this.VMControlSettings.ManagementPortList)
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
				$controlResult.AddMessage([VerificationResult]::Manual, "We are not able to check the NSG rules for some NICs. Please validate manually.");
				#Setting this property ensures that this control result will not be considered for the central telemetry, as control does not have the required permissions
				$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
				if($vulnerableNSGsWithRules.Count -ne 0)
				{
					$controlResult.AddMessage([VerificationResult]::Manual, "Management ports are open on Virtual Machine. Please verify and remove the NSG rules in order to comply.", $vulnerableNSGsWithRules);
				}
			}
			elseif($null -eq $effectiveNSG)
			{
				#If the VM is connected to ERNetwork and there is no NSG, then we should not fail as this would directly conflict with the NSG control as well.
				if($this.VMDetails.IsVMConnectedToERvNet)
				{
					$controlResult.AddMessage([VerificationResult]::Passed, "VM is part of ER Network. And no NSG found for Virtual Machine");  
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Failed, "Verify if NSG is attached to VM.");
				}
				
			}
			else
			{
				#If the VM is connected to ERNetwork or not and there is NSG, then teams should apply the recommendation and attest this control for now.
				if($vulnerableNSGsWithRules.Count -eq 0)
				{              
					$controlResult.AddMessage([VerificationResult]::Passed, "No management ports are open on Virtual Machine");  
				}
				else
				{
					$controlResult.AddMessage("List of open ports: ",$openPortsList);
					$controlResult.AddMessage([VerificationResult]::Verify, "Management ports are open on Virtual Machine. Please verify and remove the NSG rules in order to comply.", $vulnerableNSGsWithRules);

					$controlResult.SetStateData("Management ports list on Virtual Machine", $vulnerableNSGsWithRules);
				}
			}		
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Verify, "This VM is currently in a 'deallocated' state. Unable to check security controls on it.");
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
}


Class VMDetails{
[OperatingSystemTypes] $OSType
[string] $Offer
[string] $Sku
[bool] $IsVMConnectedToERvNet
[bool] $IsVMDeallocated
[string] $PublicIPs
[string] $PrivateIPs
}