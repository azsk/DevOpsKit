using namespace Microsoft.Azure.Commands.Network.Models
using namespace Microsoft.Azure.Commands.Compute.Models
using namespace Microsoft.Azure.Commands.Compute.Automation.Models
using namespace Microsoft.Azure.Management.Compute.Models

Set-StrictMode -Version Latest 

class VirtualMachineScaleSet: AzSVTBase
{       
	hidden [PSVirtualMachineScaleSet] $ResourceObject;
	hidden [PSVirtualMachineScaleSetVMList] $VMInstances;
    hidden [PSNetworkInterface[]] $VMNICs = $null;
	hidden [PSObject] $ASCSettings = $null;
	hidden [bool] $IsVMDeallocated = $false
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
		if($this.VMDetails.IsVMConnectedToERvNet -and ($result | Where-Object { $_.Tags -contains "ERvNet" } | Measure-Object).Count -gt 0)
		{
			$result=$result | Where-Object { $_.Tags -contains "ERvNet" };
		}
		# Applying filter to exclude certain controls based on Tag Key-Value 
		if([Helpers]::CheckMember($this.VMSSControlSettings, "ExcludeControlsForServices") -and [Helpers]::CheckMember($this.ResourceObject, "Tags")){
			$this.VMSSControlSettings.ExcludeControlsForServices | ForEach-Object {
				if($this.ResourceObject.Tags[$_.ResourceTag] -eq $_.ResourceTagValue){
					$filterTag = $_.FilterTag
					$result=$result | Where-Object { $_.Tags -notcontains $filterTag };
					break;
				}
			}
		}
		return $result;
	}


	hidden  GetVMSSDetails()
	{
		if([Helpers]::CheckMember($this.ResourceObject.VirtualMachineProfile.StorageProfile,"OsDisk.OsType"))
		{
			$this.VMSSDetails.OSType = $this.ResourceObject.StorageProfile.OsDisk.OsType
		}
		else
		{
			if($this.ResourceObject.VirtualMachineProfile.OSProfile -and $this.ResourceObject.VirtualMachineProfile.OSProfile.LinuxConfiguration)
			{
				$this.VMSSDetails.OSType = [OperatingSystemTypes]::Linux
			}
			else
			{
				$this.VMSSDetails.OSType = [OperatingSystemTypes]::Windows
			}
		}

		if($this.ResourceObject.VirtualMachineProfile.StorageProfile -and $this.ResourceObject.VirtualMachineProfile.StorageProfile.ImageReference)
		{
			$this.VMSSDetails.Sku =  $this.ResourceObject.VirtualMachineProfile.StorageProfile.ImageReference.Sku
			$this.VMSSDetails.Offer = $this.ResourceObject.VirtualMachineProfile.StorageProfile.ImageReference.Offer
		}		

		$this.VMSSDetails.IsVMConnectedToERvNet = $false
		#Get if VM is connected to ERvNet
		#$this.VMDetails.IsVMConnectedToERvNet = $this.IsVMConnectedToERvNet()
		#Get VM deallocation status
		#$this.VMDetails.IsVMDeallocated = $this.GetVMDeallocationStatus();
	}

	hidden [PSVirtualMachineScaleSetVMList] GetVMSSInstances(){
		if(-not $this.VMInstances){
			$this.VMInstances = Get-AzVmssVM -ResourceGroupName $this.ResourceContext.ResourceGroupName -VMScaleSetName $this.ResourceContext.ResourceName
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
			
        }
        return $this.ResourceObject;
    }

	hidden [controlresult[]] CheckVMSSMonitoringAgent([controlresult] $controlresult)
	{
	
		$VMSSType = $this.VMSSDetails.OSType
        if($VMSSType -eq [Microsoft.Azure.Management.Compute.Models.OperatingSystemTypes]::Linux)
        {
			$requiredExtensionType = "MicrosoftMonitoringAgent"
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
			$requiredExtensionType = "IaaSDiagnostics"
			$requiredPublisher = "Microsoft.Azure.Diagnostics"
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
					$controlResult.AddMessage("OS disk is not encrypted for following VM instances:", $nonCompliantOSDisks)	
				}
				# If Data disk is not encrypted for any VM instnce fail control
				if($null -ne $nonCompliantDataDisks -and ($nonCompliantDataDisks | Measure-Object).Count -gt 0){
					$allDiskAreCompliant = $false
					$controlResult.AddMessage("Data disk is not encrypted for following VM instances:", $nonCompliantDataDisks)
				}

				if($allDiskAreCompliant -eq $false){
					$controlResult.VerificationResult = [VerificationResult]::Failed
					$controlResult.AddMessage("All Virtual Machine Scale Set disks (OS and Data disks) are not encrypted.")
				}else{
					$controlResult.VerificationResult = [VerificationResult]::Passed
					$controlResult.AddMessage("All Virtual Machine Scale Set disks (OS and Data disks) are encrypted.")
				}

			}else {
				$controlResult.VerificationResult = [VerificationResult]::Failed
				$controlResult.AddMessage("Disk encryption is not enabled for VM Scale Set.")
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
		if([Helpers]::CheckMember($this.ResourceObject,"UpgradePolicy.Mode")){
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

}


Class VMSSDetails{
[OperatingSystemTypes] $OSType
[string] $Offer
[string] $Sku
[bool] $IsVMSSConnectedToERvNet
[bool] $IsVMSSDeallocated
[string] $PublicIPs
[string] $PrivateIPs
}