using namespace Microsoft.Azure.Commands.Network.Models
using namespace Microsoft.Azure.Commands.Compute.Models
using namespace Microsoft.Azure.Commands.Compute.Automation.Models
using namespace Microsoft.Azure.Management.Compute.Models

Set-StrictMode -Version Latest 

class VirtualMachineScaleSet: AzSVTBase
{       
	hidden [PSVirtualMachineScaleSet] $ResourceObject;
	hidden [PSObject] $VMInstances;
	hidden [PSNetworkInterface[]] $VMNICs = $null;
	hidden [PSObject] $ASCSettings = $null;
	hidden [bool] $IsVMSSDeallocated = $false
	hidden [VMSSDetails] $VMSSDetails = [VMSSDetails]::new()
	hidden [PSObject] $VMSSControlSettings = $null;
	hidden [string] $Workspace = "";
    
	VirtualMachineScaleSet([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
		$this.GetResourceObject();
		$this.GetVMSSDetails();
		
		#OS type must always be present in configuration setting file
		if([Helpers]::CheckMember($this.ControlSettings.VirtualMachineScaleSet, $this.VMSSDetails.OSType)){
			$this.VMSSControlSettings = $this.ControlSettings.VirtualMachineScaleSet.$($this.VMSSDetails.OSType);
		}
    }

	[ControlItem[]] ApplyServiceFilters([ControlItem[]] $controls)
	{
		$result = @();
		#Check VMSS type
		$VMSSType = $this.VMSSDetails.OSType
		# Filter control base on OS Image
        if($VMSSType -eq [Microsoft.Azure.Management.Compute.Models.OperatingSystemTypes]::Linux)
        {
			$result += $controls | Where-Object { $_.Tags -contains "Linux" };
		}
		elseif($VMSSType -eq [Microsoft.Azure.Management.Compute.Models.OperatingSystemTypes]::Windows)
		{
			$result += $controls | Where-Object { $_.Tags -contains "Windows" };;
		}
		# Filter control for ERvNet connected scale set
		if($this.VMSSDetails.IsVMSSConnectedToERvNet -and ($result | Where-Object { $_.Tags -contains "ERvNet" } | Measure-Object).Count -gt 0)
		{
			$result=$result | Where-Object { $_.Tags -contains "ERvNet" };
		}
		# Applying filter to exclude certain controls based on Tag Key-Value 
		if([Helpers]::CheckMember($this.ControlSettings.VirtualMachineScaleSet, "ControlExclusionsByService") -and [Helpers]::CheckMember($this.ResourceObject, "Tags")){
			$this.ControlSettings.VirtualMachineScaleSet.ControlExclusionsByService | ForEach-Object {
				if($this.ResourceObject.Tags[$_.ResourceTag] -like $_.ResourceTagValue){
					$controlTag = $_.ControlTag
					$result=$result | Where-Object { $_.Tags -notcontains $controlTag };
				}
			}
		}
		return $result;
	}


	hidden  GetVMSSDetails()
	{
		if([Helpers]::CheckMember($this.ResourceObject,"VirtualMachineProfile.StorageProfile") -and [Helpers]::CheckMember($this.ResourceObject.VirtualMachineProfile.StorageProfile,"OsDisk.OsType"))
		{
			$this.VMSSDetails.OSType = $this.ResourceObject.StorageProfile.OsDisk.OsType
		}
		else
		{
			if([Helpers]::CheckMember($this.ResourceObject,"VirtualMachineProfile.OSProfile") -and $this.ResourceObject.VirtualMachineProfile.OSProfile.LinuxConfiguration)
			{
				$this.VMSSDetails.OSType = [OperatingSystemTypes]::Linux
			}
			else
			{
				$this.VMSSDetails.OSType = [OperatingSystemTypes]::Windows
			}
		}

		if([Helpers]::CheckMember($this.ResourceObject,"VirtualMachineProfile.StorageProfile") -and $this.ResourceObject.VirtualMachineProfile.StorageProfile.ImageReference)
		{
			$this.VMSSDetails.Sku =  $this.ResourceObject.VirtualMachineProfile.StorageProfile.ImageReference.Sku
			$this.VMSSDetails.Offer = $this.ResourceObject.VirtualMachineProfile.StorageProfile.ImageReference.Offer
		}		

		#Get if VM is connected to ERvNet
		$this.VMSSDetails.IsVMSSConnectedToERvNet = $this.IsVMSSConnectedToERvNet()

	}

	hidden [PSObject] GetVMSSInstances(){
		if(-not $this.VMInstances){
			$this.VMInstances = Get-AzVmssVM -ResourceGroupName $this.ResourceContext.ResourceGroupName -VMScaleSetName $this.ResourceContext.ResourceName -ErrorAction SilentlyContinue
		}
		return $this.VMInstances;
	}

    hidden [PSVirtualMachineScaleSet] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzVmss -ResourceGroupName $this.ResourceContext.ResourceGroupName -VMScaleSetName $this.ResourceContext.ResourceName  -WarningAction SilentlyContinue 

            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
			
			#compute ASC object for VMSS
			# Commenting this as we are not using any ASC data for now
			#$this.ASCSettings = $this.GetASCSettings();
        }
        return $this.ResourceObject;
    }

    hidden [PSObject] GetASCSettings()
	{
		$result = $null;
		try 
		{ 	
			$result = [SecurityCenterHelper]::InvokeSecurityCenterSecurityStatus($this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceId);
			if(($result | Measure-Object).Count -gt 0)
			{			
				return $result;			
			}			
		}
		catch
		{
			#eat exception if no ASC settings can be found
		}
		return $null;
	}

	hidden [bool] IsVMSSConnectedToERvNet()
	{
		$IsVMSSConnectedToERvNet = $false
		if([Helpers]::CheckMember($this.ResourceObject,"VirtualMachineProfile.NetworkProfile")){
			$this.ResourceObject.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations |
			ForEach-Object {         
				if($_.IpConfigurations)
				{
					$_.IpConfigurations | 
						ForEach-Object {
				
							$subnetId = $_.Subnet.Id;		
							$subnetName = $subnetId.Substring($subnetId.LastIndexOf("/") + 1);
							#vnet id = trim '/subnets/' from subnet id 
							$vnetResource = Get-AzResource -ResourceId $subnetId.Substring(0, $subnetId.IndexOf("/subnets/"))
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

											$gatewayObject = Get-AzVirtualNetworkGateway -Name $gatewayname -ResourceGroupName $vnet.ResourceGroupName
											if( $gatewayObject.GatewayType -eq "ExpressRoute")
											{
												$IsVMSSConnectedToERvNet= $true
											}
										}
									}
								}
							}

	
						}
				}
			}
		}
		return $IsVMSSConnectedToERvNet;
	}

	hidden [controlresult[]] CheckVMSSMonitoringAgent([controlresult] $controlresult)
	{
	
		$VMSSType = $this.VMSSDetails.OSType
        if($VMSSType -eq [Microsoft.Azure.Management.Compute.Models.OperatingSystemTypes]::Linux)
        {
			$requiredExtensionType = "OmsAgentForLinux"
			$requiredPublisher = "Microsoft.EnterpriseCloud.Monitoring" 
		}else{
			$requiredExtensionType = "MicrosoftMonitoringAgent"
			$requiredPublisher = "Microsoft.EnterpriseCloud.Monitoring"
		}

        if([Helpers]::CheckMember($this.ResourceObject,"VirtualMachineProfile.ExtensionProfile") -and [Helpers]::CheckMember($this.ResourceObject.VirtualMachineProfile.ExtensionProfile,"Extensions"))
		{
			$configuredExtensions = $this.ResourceObject.VirtualMachineProfile.ExtensionProfile.Extensions
            $installedExtension = $configuredExtensions | Where-Object { $_.Type -eq $requiredExtensionType -and $_.Publisher -eq $requiredPublisher}
			if($null -ne $installedExtension -and ($installedExtension | Measure-Object).Count -gt 0){
				$controlResult.VerificationResult = [VerificationResult]::Passed
				$controlResult.AddMessage("Required Monitoring Agent '$($requiredExtensionType)' is present in VM Scale Set.");
			}else{
				$controlResult.VerificationResult = [VerificationResult]::Failed
				$controlResult.AddMessage("Required Monitoring Agent '$($requiredExtensionType)' is missing in VM Scale Set.");
			}
		
		}else{
			$controlResult.VerificationResult = [VerificationResult]::Manual
			$controlResult.AddMessage("Not able to fetch extension details for VM Scale Set.");
		}

		return $controlResult;
	}

	hidden [controlresult[]] CheckVMSSAntimalwareStatus([controlresult] $controlresult)
	{
		$requiredExtensionType = "IaaSAntimalware"
		$requiredPublisher = "Microsoft.Azure.Security"

        if([Helpers]::CheckMember($this.ResourceObject,"VirtualMachineProfile.ExtensionProfile") -and [Helpers]::CheckMember($this.ResourceObject.VirtualMachineProfile.ExtensionProfile,"Extensions"))
		{
			$configuredExtensions = $this.ResourceObject.VirtualMachineProfile.ExtensionProfile.Extensions
            $installedExtension = $configuredExtensions | Where-Object { $_.Type -eq $requiredExtensionType -and $_.Publisher -eq $requiredPublisher}
			if($null -ne $installedExtension -and ($installedExtension | Measure-Object).Count -gt 0){
				$controlResult.VerificationResult = [VerificationResult]::Passed
				$controlResult.AddMessage("Anti Malware solution '$($requiredExtensionType)' is deployed on VM Scale Set.");
			}else{
				$controlResult.VerificationResult = [VerificationResult]::Failed
				$controlResult.AddMessage("Anti Malware solution '$($requiredExtensionType)' is missing in VM Scale Set.");
			}
		
		}else{
			$controlResult.VerificationResult = [VerificationResult]::Manual
			$controlResult.AddMessage("Not able to fetch extension details for VM Scale Set.");
		}

		return $controlResult;
	}

	hidden [controlresult[]] CheckVMSSDiagnostics([controlresult] $controlresult)
	{
		$VMSSType = $this.VMSSDetails.OSType
        if($VMSSType -eq [Microsoft.Azure.Management.Compute.Models.OperatingSystemTypes]::Linux)
        {
			$requiredExtensionType = "LinuxDiagnostic"
			$requiredPublisher = "Microsoft.OSTCExtensions"
		}else{
			$requiredExtensionType = "IaaSDiagnostics"
			$requiredPublisher = "Microsoft.Azure.Diagnostics"
		}

        if([Helpers]::CheckMember($this.ResourceObject,"VirtualMachineProfile.ExtensionProfile") -and [Helpers]::CheckMember($this.ResourceObject.VirtualMachineProfile.ExtensionProfile,"Extensions"))
		{
			$configuredExtensions = $this.ResourceObject.VirtualMachineProfile.ExtensionProfile.Extensions
            $installedExtension = $configuredExtensions | Where-Object { $_.Type -eq $requiredExtensionType -and $_.Publisher -eq $requiredPublisher}
			if($null -ne $installedExtension -and ($installedExtension | Measure-Object).Count -gt 0){
				$controlResult.VerificationResult = [VerificationResult]::Passed
				$controlResult.AddMessage("Required diagnostics extension '$($requiredExtensionType)' is present in VM Scale Set.");
			}else{
				$controlResult.VerificationResult = [VerificationResult]::Failed
				$controlResult.AddMessage("Required diagnostics extension '$($requiredExtensionType)' is missing in VM Scale Set.");
			}
		
		}else{
			$controlResult.VerificationResult = [VerificationResult]::Manual
			$controlResult.AddMessage("Not able to fetch extension details for VM Scale Set.");
		}

		return $controlResult;
	}

	hidden [controlresult[]] CheckVMSSAppHealthMonitoring([controlresult] $controlresult)
	{
		$VMSSType = $this.VMSSDetails.OSType
        if($VMSSType -eq [Microsoft.Azure.Management.Compute.Models.OperatingSystemTypes]::Linux)
        {
			$requiredExtensionType = "ApplicationHealthLinux"
			$requiredPublisher = "Microsoft.ManagedServices"
		}else{
			$requiredExtensionType = "ApplicationHealthWindows"
			$requiredPublisher = "Microsoft.ManagedServices"
		}


        if([Helpers]::CheckMember($this.ResourceObject,"VirtualMachineProfile.ExtensionProfile") -and [Helpers]::CheckMember($this.ResourceObject.VirtualMachineProfile.ExtensionProfile,"Extensions"))
		{
			$configuredExtensions = $this.ResourceObject.VirtualMachineProfile.ExtensionProfile.Extensions
            $installedExtension = $configuredExtensions | Where-Object { $_.Type -eq $requiredExtensionType -and $_.Publisher -eq $requiredPublisher}
			if($null -ne $installedExtension -and ($installedExtension | Measure-Object).Count -gt 0){
				$controlResult.VerificationResult = [VerificationResult]::Passed
				$controlResult.AddMessage("Required Application Health extension '$($requiredExtensionType)' is present in VM Scale Set.");
			}else{
				$controlResult.VerificationResult = [VerificationResult]::Failed
				$controlResult.AddMessage("Required Application Health extension '$($requiredExtensionType)' is missing in VM Scale Set.");
			}
		
		}else{
			$controlResult.VerificationResult = [VerificationResult]::Manual
			$controlResult.AddMessage("Not able to fetch extension details for VM Scale Set.");
		}

		return $controlResult;
	}

	hidden [controlresult[]] CheckVMSSDiskEncryption([controlresult] $controlresult)
	{
		# Check if disk encryption is enabled or not on Vm Scale Set Model
		$vmssEncryptionStatus = Get-AzVmssDiskEncryptionStatus -ResourceGroupName $this.ResourceContext.ResourceGroupName -VMScaleSetName $this.ResourceContext.ResourceName -WarningAction SilentlyContinue
		if($null -ne $vmssEncryptionStatus){
			if([Helpers]::CheckMember($vmssEncryptionStatus,"EncryptionEnabled") -and $vmssEncryptionStatus.EncryptionEnabled -eq $true -and [Helpers]::CheckMember($vmssEncryptionStatus,"EncryptionExtensionInstalled") -and $vmssEncryptionStatus.EncryptionExtensionInstalled -eq $true){
				#If Disk encryption is enbled for VMSS, Check encryption status of each OS and Data disk
				$encryptionStatusForVMS = Get-AzVmssVMDiskEncryptionStatus -ResourceGroupName $this.ResourceContext.ResourceGroupName -VMScaleSetName $this.ResourceContext.ResourceName
				# Check for OS Disk encryption
				$nonCompliantOSDisks = $encryptionStatusForVMS | Where-Object {$_.OsVolumeEncrypted -eq 'NotEncrypted'}
				#Check for Data Disk encrytpion 
				$nonCompliantDataDisks = $encryptionStatusForVMS | Where-Object {$_.DataVolumesEncrypted -eq 'NotEncrypted'}
				$allDiskAreCompliant = $null
				# If OS disk is not encrypted for any VM instnce fail control
				if($null -ne $nonCompliantOSDisks -and ($nonCompliantOSDisks | Measure-Object).Count -gt 0){
					$allDiskAreCompliant = $false
					$controlResult.AddMessage("OS disk is not encrypted for following VMSS instances:", $nonCompliantOSDisks)	
				}
				# If Data disk is not encrypted for any VM instnce fail control
				if($null -ne $nonCompliantDataDisks -and ($nonCompliantDataDisks | Measure-Object).Count -gt 0){
					$allDiskAreCompliant = $false
					$controlResult.AddMessage("Data disk is not encrypted for following VMSS instances:", $nonCompliantDataDisks)
				}

				if($allDiskAreCompliant -eq $false){
					$controlResult.VerificationResult = [VerificationResult]::Failed
					$controlResult.AddMessage("All Virtual Machine Scale Set disks (OS and Data disks) are not encrypted.")
				}else{
					$controlResult.VerificationResult = [VerificationResult]::Passed
					$controlResult.AddMessage("All Virtual Machine Scale Set disks (OS and Data disks) are encrypted.")
				}

			}else {
				if([Helpers]::CheckMember($this.ResourceObject,"VirtualMachineProfile.StorageProfile") ){
					$controlResult.VerificationResult = [VerificationResult]::Failed
					$controlResult.AddMessage("Disk encryption is not enabled for VM Scale Set.")
				}else{
					$controlResult.VerificationResult = [VerificationResult]::Manual
					$controlResult.AddMessage("Not able to fetch 'Encryption' state for OS and Data disks. Please verify manually that both Data and OS disks should be encrypted.");
				}
			}
		}else{
			$controlResult.VerificationResult = [VerificationResult]::Manual
			$controlResult.AddMessage("Not able to fetch 'Encryption' state for OS and Data disks. Please verify manually that both Data and OS disks should be encrypted.");
		}
		return $controlResult;
	}

	hidden [controlresult[]] CheckVMSSInstancesStatus([controlresult] $controlresult)
	{
		$upgradeModeIsManual = $true
		# First Get Upgrade Policy defined for VMSS
		if([Helpers]::CheckMember($this.ResourceObject,"UpgradePolicy")){
			if($this.ResourceObject.UpgradePolicy.Mode -eq 'Manual'){
				$upgradeModeIsManual = $true
				$controlResult.AddMessage("Upgrade Policy for VM Scale Set is configured as 'Manual'");	
			}else{
				$upgradeModeIsManual = $false
			}
		}else{
			$upgradeModeIsManual = $true
			$controlResult.AddMessage("Not able to fetch Upgrade Policy details for VM Scale Set.");	
		}

        # If Upgrade Policy is defined as 'Manual', Validate that all VM instances must be running on latest VMSS model
		if($upgradeModeIsManual -eq $true){
			$allVMInstances = $this.GetVMSSInstances();
			if($null -ne $allVMInstances -and ($allVMInstances | Measure-Object).Count -gt 0){
				$nonCompliantInstances = $allVMInstances | Where-Object {$_.LatestModelApplied -ne $true}
				if($null -ne $nonCompliantInstances -and ($nonCompliantInstances|Measure-Object).Count -gt 0){
					$controlResult.VerificationResult = [VerificationResult]::Failed
					$nonCompliantInstances = $nonCompliantInstances | Select-Object "Name","InstanceId"
					$controlResult.AddMessage("Following VM instances are not running on latest VM Scale Set model:", $nonCompliantInstances);
				}else{
					$controlResult.VerificationResult = [VerificationResult]::Passed
					$controlResult.AddMessage("All VM instances are running on latest VM Scale Set model.");	
				}
			}else{
				$controlResult.VerificationResult = [VerificationResult]::Manual
				$controlResult.AddMessage("Not able to fetch individual VM instance details for VM Scale Set. Please verify manually that all VM instances are running on latest VM scale set model.");
			}
		}else{
			$controlResult.VerificationResult = [VerificationResult]::Passed
			$controlResult.AddMessage("Upgrade Policy for VM Scale Set is defined as either 'Automatic' or 'Rolling'");		
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckVMSSPublicIP([ControlResult] $controlResult)
	{	
		$publicIps = @();
		if([Helpers]::CheckMember($this.ResourceObject,"VirtualMachineProfile.NetworkProfile")){
			$vmssPublicIPs = Get-AzPublicIpAddress -ResourceGroupName $this.ResourceContext.ResourceGroupName -VirtualMachineScaleSetName $this.ResourceContext.ResourceName  -WarningAction SilentlyContinue 
			if($null -ne $vmssPublicIPs -and ($vmssPublicIPs | Measure-Object).Count -gt 0){
				$publicIps = $vmssPublicIPs |  Select-Object "Name", "ResourceGroupName", "PublicIpAllocationMethod", "IpAddress", "Id"
			}
			if($this.VMSSDetails.IsVMSSConnectedToERvNet)
			{
				$controlResult.AddMessage("This VMSS is part of an ExpressRoute connected virtual network. You must not have any Public IP assigned to such VMSS.");
			}
			if($publicIps.Count -gt 0 -and $this.VMSSDetails.IsVMSSConnectedToERvNet)
			{              
				$controlResult.AddMessage([VerificationResult]::Failed, "Following Public IPs are configured on VMSS", $publicIps);  
				#$controlResult.SetStateData("Public IP(s) associated with Virtual Machine Scale Set", $publicIps);
			}
			elseif($publicIps.Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Verify, "Validate Public IP(s) associated with Virtual Machine Scale Set. Total - $($publicIps.Count)", $publicIps);  
				#$controlResult.SetStateData("Public IP(s) associated with Virtual Machine Scale Set", $publicIps);
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, "No Public IP is associated with Virtual Machine Scale Set.");
			}
		}else{
			$controlResult.VerificationResult = [VerificationResult]::Manual;
			$controlResult.AddMessage("Not able to fetch Network configurations for VM Scale Set.");	
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckVMSSNSGConfig([ControlResult] $controlResult)
	{
		$controlResult.VerificationResult = [VerificationResult]::Failed;
		if([Helpers]::CheckMember($this.ResourceObject,"VirtualMachineProfile.NetworkProfile")){
			$this.ResourceObject.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations|
			ForEach-Object {          
				#Check NSGs applied at NIC level
				if($_.NetworkSecurityGroup)
				{
					$nsgResource = Get-AzResource -ResourceId $_.NetworkSecurityGroup.Id
					if($nsgResource){
						$nsgObject = Get-AzNetworkSecurityGroup -Name $nsgResource.Name -ResourceGroupName $nsgResource.ResourceGroupName
						if($nsgObject)
						{
							if($nsgObject.SecurityRules.Count -gt 0)
							{
								$controlResult.AddMessage("Validate NSG security rules applied to NIC - [$($_.Name)], Total - $($nsgObject.SecurityRules.Count)", $nsgObject.SecurityRules);       		                           
							}
							
							if($nsgObject.DefaultSecurityRules.Count -gt 0)
							{
								$controlResult.AddMessage("Validate default NSG security rules applied to NIC - [$($_.Name)], Total - $($nsgObject.DefaultSecurityRules.Count)", $nsgObject.DefaultSecurityRules); 
							}
							$controlResult.VerificationResult = [VerificationResult]::Verify;
							$controlResult.SetStateData("NSG security rules", $nsgObject.SecurityRules);
						}
					}
				
				}  
			
				#check NSGs applied at subnet level       
				if($_.IpConfigurations)
				{
					$_.IpConfigurations | 
						ForEach-Object {                   
							$subnetId = $_.Subnet.Id;		
							$subnetName = $subnetId.Substring($subnetId.LastIndexOf("/") + 1);
							#vnet id = trim '/subnets/' from subnet id 
							$vnetResource = Get-AzResource -ResourceId $subnetId.Substring(0, $subnetId.IndexOf("/subnets/"))
							if($vnetResource)
							{
								$vnetObject = Get-AzVirtualNetwork -Name $vnetResource.Name -ResourceGroupName $vnetResource.ResourceGroupName
								if($vnetObject)
								{
									$subnetConfig = Get-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnetObject
									if($subnetConfig -and $subnetConfig.NetworkSecurityGroup -and $subnetConfig.NetworkSecurityGroup.Id)
									{
										$nsgResource = Get-AzResource -ResourceId $subnetConfig.NetworkSecurityGroup.Id
										if($nsgResource)
										{
											$nsgObject = Get-AzNetworkSecurityGroup -Name $nsgResource.Name -ResourceGroupName $nsgResource.ResourceGroupName
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
		if($this.VMSSDetails.IsVMSSConnectedToERvNet)
		{
			$controlResult.AddMessage("This VM Scale Set is part of an ExpressRoute connected virtual network.")	
		}
		if($controlResult.VerificationResult -ne [VerificationResult]::Verify -and $this.VMSSDetails.IsVMSSConnectedToERvNet)
		{			
			$controlResult.AddMessage("No NSG was found on Virtual Machine Scale Set subnet or NIC.")	
			$controlResult.VerificationResult = [VerificationResult]::Passed;
		}
		elseif($controlResult.VerificationResult -ne [VerificationResult]::Verify)
		{
			$controlResult.AddMessage("No NSG was found on Virtual Machine Scale Set subnet or NIC.")		
		}
		}else{

			$controlResult.VerificationResult = [VerificationResult]::Manual;
			$controlResult.AddMessage("Not able to fetch Network configurations for VM Scale Set.");	
		}
	
		return $controlResult;
	}

	hidden [ControlResult] CheckVMSSOpenPorts([ControlResult] $controlResult)
	{	
	
		$isManual = $false
		$controlResult.AddMessage("Checking for Virtual Machine Scale Set management ports",$this.VMSSControlSettings.ManagementPortList);
		$vulnerableNSGsWithRules = @();
		$effectiveNSG = $null;
		$openPortsList =@();
		if([Helpers]::CheckMember($this.ResourceObject,"VirtualMachineProfile.NetworkProfile")){
			$this.ResourceObject.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations|
			ForEach-Object {   
				#Get the NSGs applied at subnet level       
				if($_.IpConfigurations)
				{
					$_.IpConfigurations | 
						ForEach-Object {                   
							$subnetId = $_.Subnet.Id;		
							$subnetName = $subnetId.Substring($subnetId.LastIndexOf("/") + 1);
							#vnet id = trim '/subnets/' from subnet id 
							$vnetResource = Get-AzResource -ResourceId $subnetId.Substring(0, $subnetId.IndexOf("/subnets/"))
							if($vnetResource)
							{
								$vnetObject = Get-AzVirtualNetwork -Name $vnetResource.Name -ResourceGroupName $vnetResource.ResourceGroupName
								if($vnetObject)
								{
									$subnetConfig = Get-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnetObject
									if($subnetConfig -and $subnetConfig.NetworkSecurityGroup -and $subnetConfig.NetworkSecurityGroup.Id)
									{
										$nsgResource = Get-AzResource -ResourceId $subnetConfig.NetworkSecurityGroup.Id
										if($nsgResource)
										{
											$nsgObject = Get-AzNetworkSecurityGroup -Name $nsgResource.Name -ResourceGroupName $nsgResource.ResourceGroupName
											if($nsgObject)
											{
												$effectiveNSG = $nsgObject
											}
										}
									}
								}
							}
						}           
				}          
				#Get NSGs applied at NIC level
				if($_.NetworkSecurityGroup)
				{
					$nsgResource = Get-AzResource -ResourceId $_.NetworkSecurityGroup.Id
					if($nsgResource){
						$nsgObject = Get-AzNetworkSecurityGroup -Name $nsgResource.Name -ResourceGroupName $nsgResource.ResourceGroupName
						if($nsgObject)
						{
							$effectiveNSG = $nsgObject
						}
					}
				}  
				         
			}
			if($effectiveNSG)
				{
					$vulnerableRules = @()
					
					if($this.VMSSControlSettings -and $this.VMSSControlSettings.ManagementPortList)
					{
						Foreach($PortDetails in  $this.VMSSControlSettings.ManagementPortList)
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
							NetworkSecurityGroupName = $effectiveNSG.Name;
							NetworkSecurityGroupId = $effectiveNSG.Id;
							VulnerableRules = $vulnerableRules
						};
					}						
				}					
		}else{
			$isManual = $true
		}

		if($isManual)
		{
			$controlResult.AddMessage([VerificationResult]::Manual, "We are not able to check the NSG rules for VM Scale Set. Please validate manually.");
			#Setting this property ensures that this control result will not be considered for the central telemetry, as control does not have the required permissions
			$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
		}
		elseif($null -eq $effectiveNSG)
		{
			#If the VMSS is connected to ERNetwork and there is no NSG, then we should not fail as this would directly conflict with the NSG control as well.
			if($this.VMSSDetails.IsVMSSConnectedToERvNet)
			{
				$controlResult.AddMessage([VerificationResult]::Passed, "VM Scale Set is part of ER Network. And no NSG found for Virtual Machine Scale Set.");  
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "Verify if NSG is attached to VM Scale Set.");
			}
			
		}
		else
		{
			#If the VM is connected to ERNetwork or not and there is NSG, then teams should apply the recommendation and attest this control for now.
			if($vulnerableNSGsWithRules.Count -eq 0)
			{              
				$controlResult.AddMessage([VerificationResult]::Passed, "No management ports are open on Virtual Machine Scale Set.");  
			}
			else
			{
				$controlResult.AddMessage("List of open ports: ",$openPortsList);
				$controlResult.AddMessage([VerificationResult]::Verify, "Management ports are open on Virtual Machine Scale Set. Please verify and remove the NSG rules in order to comply.", $vulnerableNSGsWithRules);

				$controlResult.SetStateData("Management ports list on Virtual Machine Scale Set.", $vulnerableNSGsWithRules);
			}
		}		
		return $controlResult;
	} 

	# Helper method to check if specific port is opened in NSG
	hidden [PSObject] CheckIfPortIsOpened([PSObject] $effectiveNSG,[int] $port )
	{
		$vulnerableRules = @();
		$inbloundRules = $effectiveNSG.SecurityRules | Where-Object { ($_.direction -eq "Inbound" ) }
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
				elseif($range.Count -eq 1 -and $destPort -eq $port) 
				{
					$vulnerableRules += $securityRule
				}
	
			}
		}
		return $vulnerableRules;
	}
}


Class VMSSDetails{
[OperatingSystemTypes] $OSType
[string] $Offer
[string] $Sku
[bool] $IsVMSSConnectedToERvNet
[bool] $IsVMSSDeallocated
}