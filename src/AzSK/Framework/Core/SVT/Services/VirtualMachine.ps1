using namespace Microsoft.Azure.Commands.Network.Models
using namespace Microsoft.Azure.Commands.Compute.Models
using namespace Microsoft.Azure.Management.Compute.Models
Set-StrictMode -Version Latest 

class VirtualMachine: AzSVTBase
{       
    hidden [PSVirtualMachine] $ResourceObject;
    hidden [PSNetworkInterface[]] $VMNICs = $null;
	hidden [PSObject] $ASCSettings = $null;
	hidden [bool] $IsVMDeallocated = $false
	hidden [VMDetails] $VMDetails = [VMDetails]::new()
	hidden [PSObject] $VMControlSettings = $null;
	hidden [string] $Workspace = "";
    
	VirtualMachine([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
		$this.GetVMDetails();
		$metadata= [PSObject]::new();
		$metadata| Add-Member -Name VMDetails -Value $this.VMDetails -MemberType NoteProperty;
		if([FeatureFlightingManager]::GetFeatureStatus("EnableVMASCMetadataCapture",$($this.SubscriptionContext.SubscriptionId)) -eq $true)
		{
			$metadata| Add-Member -Name VMASCDetails -Value $this.ASCSettings -MemberType NoteProperty;
		}
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
        
		# Applying filter to exclude certain controls based on Tag Key-Value 
		if([Helpers]::CheckMember($this.ControlSettings.VirtualMachine, "ControlExclusionsByService") -and [Helpers]::CheckMember($this.ResourceObject, "Tags")){
			$this.ControlSettings.VirtualMachine.ControlExclusionsByService | ForEach-Object {
				if($this.ResourceObject.Tags[$_.ResourceTag] -like $_.ResourceTagValue){
					$controlTag = $_.ControlTag
					$result=$result | Where-Object { $_.Tags -notcontains $controlTag };
				}
			}
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
								$ipResource = Get-AzResource -ResourceId $_.PublicIpAddress.Id 
								if($ipResource)
								{
									$publicIpObject = Get-AzPublicIpAddress -Name $ipResource.Name -ResourceGroupName $ipResource.ResourceGroupName
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
		$vmStatusObj = Get-AzVM -ResourceGroupName $this.ResourceContext.ResourceGroupName -Name $this.ResourceContext.ResourceName -Status -WarningAction SilentlyContinue 
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
            $this.ResourceObject = Get-AzVM -ResourceGroupName $this.ResourceContext.ResourceGroupName -Name $this.ResourceContext.ResourceName  -WarningAction SilentlyContinue 

            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
			
        }

		#compute ASC object for VM
		$this.ASCSettings = $this.GetASCSettings();

		if($null -ne $this.ASCSettings -and [Helpers]::CheckMember($this.ASCSettings,"properties.resourceDetails"))
		{
			$laWSSetting = $this.ASCSettings.properties.resourceDetails | Where-Object {$_.name -eq $this.ControlSettings.VirtualMachine.ASCPolicies.ResourceDetailsKeys.WorkspaceId };
			if($null -ne $laWSSetting)
			{
				$this.Workspace = $laWSSetting.value;
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

	hidden [PSNetworkInterface[]] GetVMNICObjects()
    {
        if (-not $this.VMNICs) 
		{
			$this.VMNICs = @();
			if($this.ResourceObject.NetworkProfile -and $this.ResourceObject.NetworkProfile.NetworkInterfaces)
			{
				$this.ResourceObject.NetworkProfile.NetworkInterfaces | 
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
		
		#Execute block if OS is Linux and WorkSpaceId is configured
		if($this.VMDetails.OSType -eq [OperatingSystemTypes]::Linux -and [FeatureFlightingManager]::GetFeatureStatus("EnableLinuxAntimalwareCheck",$($this.SubscriptionContext.SubscriptionId))) 
		{

			if($this.Workspace)
			{
				$LinuxAntimalwareStatusWSQuery =[string]::Format($this.VMControlSettings.QueryForLinuxAntimalwareStatus,($this.ResourceContext.ResourceId).ToLower());
				$queryStatusResult = [LogAnalyticsHelper]::QueryStatusfromWorkspace($this.Workspace, $LinuxAntimalwareStatusWSQuery);

				if($queryStatusResult.Count -gt 0 )
				{
					$controlResult.AddMessage([VerificationResult]::Passed,"Antimalware is configured correctly on the VM. Validated the status through ASC workspace query."); 
				}
				else {

					if(-not $this.VMDetails.IsVMDeallocated)
					{
						$controlResult.AddMessage([VerificationResult]::Failed,"Antimalware is not configured on the VM. Validated the status through ASC workspace query."); 
					}
					else 
					{
						$controlResult.AddMessage([VerificationResult]::Manual, "VM is in deallocated state. We are not able to check Security Center workspace status. Please validate VM antimalware status manually.");
					}
				}
			}
			else {
				$controlResult.AddMessage([VerificationResult]::Manual, "We are not able to check Security Center workspace status. Please validate VM antimalware status manually.");
			}
			
		}
		elseif($null -ne $this.ASCSettings -and [Helpers]::CheckMember($this.ASCSettings, "properties.policyAssessments"))
		{
			$antimalwareSetting = $null
			if([FeatureFlightingManager]::GetFeatureStatus("EnableASCPolicyOnVMCheckUsingPolicyAssessmentKey",$($this.SubscriptionContext.SubscriptionId)) -eq $true)
			{
				$antimalwareSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.assessmentKey -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.EndpointProtectionAssessmentKey};
			}
			else 
			{
				$antimalwareSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.policyName -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.EndpointProtection};
			}
			
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

	hidden [ControlResult] CheckVulnAgentStatus([ControlResult] $controlResult)
	{
		if(-not $this.VMDetails.IsVMDeallocated)
		{
			$requiredVulnExtension = $this.VMControlSettings.VulnAssessmentSolution.AgentName
			$requiredVulnExtensionVersion =  [System.Version] $this.VMControlSettings.VulnAssessmentSolution.RequiredVersion
			if([Helpers]::CheckMember($this.ResourceObject, "Extensions")){
				$installedVulnExtension = $this.ResourceObject.Extensions | Where-Object {$_.VirtualMachineExtensionType -eq $requiredVulnExtension} 
				if($null -ne $installedVulnExtension -and $installedVulnExtension.ProvisioningState -eq "Succeeded"){
					$currentVulnExtensionVersion = $null
					try {
						$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl();
						$AccessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
						$header = "Bearer " + $AccessToken
						$headers = @{"Authorization"=$header;"Content-Type"="application/json";}
						$propertiesToReplace = @{}
						$propertiesToReplace.Add("httpapplicationroutingzonename", "_httpapplicationroutingzonename")
						$uri=[system.string]::Format("{0}subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Compute/virtualMachines/{3}/extensions/{4}?api-version=2018-06-01&`$expand=instanceView",$ResourceAppIdURI,$this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName,$requiredVulnExtension)
						$result = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $headers, $null, $null, $propertiesToReplace); 
						$currentVulnExtensionVersion = [System.Version] $result.properties.instanceView.typeHandlerVersion
					}
					catch {
						# If any exception occurs, while fetching details of Extension mark control as manual
						$currentVulnExtensionVersion = $null
					}
					if($null -eq $currentVulnExtensionVersion )
					{
						$controlResult.AddMessage([VerificationResult]::Manual, "Not able to fetch details of vulnerability assessment extension '$($requiredVulnExtension)'.");
					}
					elseif($currentVulnExtensionVersion -lt $requiredVulnExtensionVersion){

						$controlResult.AddMessage([VerificationResult]::Failed, "Vulnerability assessment solution '$($requiredVulnExtension)' is present but current verison is not latest.");
						$controlResult.AddMessage("Current version : $($currentVulnExtensionVersion), Required version: $($requiredVulnExtensionVersion)");
						$controlResult.SetStateData("Current version of $($requiredVulnExtension) present is:", $currentVulnExtensionVersion.ToString());
					
					}else{

						$controlResult.AddMessage([VerificationResult]::Passed, "Required vulnerability assessment solution '$($requiredVulnExtension)' is present in VM.");
					}
				}else{
					$controlResult.AddMessage([VerificationResult]::Failed, "Required vulnerability assessment solution '$($requiredVulnExtension)' is not present in VM.");
				}
			}else{
				$controlResult.AddMessage([VerificationResult]::Failed, "Required vulnerability assessment solution '$($requiredVulnExtension)' is not present in VM.");
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Verify, "This VM is currently in a 'deallocated' state. Unable to check security controls on it.");
		}
		return $controlResult;
	}

	hidden [ControlResult] CheckGuestConfigExtension([ControlResult] $controlResult)
	{
		if(-not $this.VMDetails.IsVMDeallocated)
		{
			$guestConfigurationAssignmentName = $this.VMControlSettings.GuestExtension.AssignmentName
			$controlStatus = [VerificationResult]::Manual
            $requiredGuestExtension  = $this.VMControlSettings.GuestExtension.Name
			$requiredGuestExtensionVersion =  [System.Version] $this.VMControlSettings.GuestExtension.RequiredVersion
			$checkPolicyAssignment = $this.VMControlSettings.GuestExtension.CheckPolicyAssignment
			
			
            $ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl();
			$AccessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
			$header = "Bearer " + $AccessToken
			$headers = @{"Authorization"=$header;"Content-Type"="application/json";}
			$propertiesToReplace = @{}
			$propertiesToReplace.Add("httpapplicationroutingzonename", "_httpapplicationroutingzonename")

			# Check if Guest Configuration extension is present
			if([Helpers]::CheckMember($this.ResourceObject, "Extensions")){
				$installedGuestExtension = $this.ResourceObject.Extensions | Where-Object {$_.VirtualMachineExtensionType -eq $requiredGuestExtension -and $_.Publisher -eq "Microsoft.GuestConfiguration"} 
				if($null -ne $installedGuestExtension -and $installedGuestExtension.ProvisioningState -eq "Succeeded"){
					$controlStatus = [VerificationResult]::Passed
					$controlResult.AddMessage("Required guest configuration extension '$($requiredGuestExtension)' is present in VM.");

					$currentGuestExtensionVersion = $null
					try {
						$uri=[system.string]::Format("{0}subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Compute/virtualMachines/{3}/extensions/{4}?api-version=2018-06-01&`$expand=instanceView",$ResourceAppIdURI,$this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName,$requiredGuestExtension)
						$result = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $headers, $null, $null, $propertiesToReplace); 
						$currentGuestExtensionVersion = [System.Version] $result.properties.instanceView.typeHandlerVersion
					}
					catch {
						# If any exception occurs, while fetching details of Extension mark control as manual
						# Skip check for version
					}
				}else{
					$controlStatus = [VerificationResult]::Failed
					$controlResult.AddMessage("Required guest configuration extension '$($requiredGuestExtension)' is not present in VM.");
				}
			}else{
				$controlStatus = [VerificationResult]::Failed
				$controlResult.AddMessage("Required guest configuration extension '$($requiredGuestExtension)' is not present in VM.");
			}

			# Check if reuired Guest Configuration Assignments is present
			if($checkPolicyAssignment -eq $true){
				try{
					$uri=[system.string]::Format("{0}subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Compute/virtualMachines/{3}/providers/Microsoft.GuestConfiguration/guestConfigurationAssignments/{4}?api-version=2018-11-20",$ResourceAppIdURI,$this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName,$guestConfigurationAssignmentName)
					$result = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $headers, $null, $null, $propertiesToReplace); 
					if($null -ne $result)
					{	
						$controlResult.AddMessage("Required guest configuration assignments '$($guestConfigurationAssignmentName)' is present.");
						$controlResult.AddMessage($result);
					
					}
				}catch{
					$controlStatus = [VerificationResult]::Failed
					$controlResult.AddMessage("Required guest configuration assignments '$($guestConfigurationAssignmentName)' is not present.");	
				}
			}
        

			# Check if Managed System Identity is enabled on VM
            # Using like "*SystemAssigned*" to get correct status, if both MSI and User Assigned Identity are enabled 
			if([Helpers]::CheckMember($this.ResourceObject, "Identity") -and $this.ResourceObject.Identity.Type -like "*SystemAssigned*"){
				$controlResult.AddMessage("SystemAssigned managed identity is enabled on VM.");
			}else{
				$controlStatus = [VerificationResult]::Failed
				$controlResult.AddMessage("The VM does not have a SystemAssigned managed identity");
			}
		}
		else
		{
			$controlStatus = [VerificationResult]::Verify
			$controlResult.AddMessage("This VM is currently in a 'deallocated' state. Unable to check security controls on it.");
		}
		$controlResult.VerificationResult = $controlStatus
		return $controlResult;
	}

	hidden [ControlResult] CheckGuestConfigPolicyStatus([ControlResult] $controlResult)
	{
		$controlStatus = [VerificationResult]::Failed
		$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl();
		$AccessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
		$header = "Bearer " + $AccessToken
		$headers = @{"Authorization"=$header;"Content-Type"="application/json";}
		$propertiesToReplace = @{}
		$propertiesToReplace.Add("httpapplicationroutingzonename", "_httpapplicationroutingzonename")
		$policyAssignments = @();
		try {
				$uri=[system.string]::Format("{0}subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Compute/virtualMachines/{3}/providers/Microsoft.GuestConfiguration/guestConfigurationAssignments?api-version=2018-06-30-preview",$ResourceAppIdURI,$this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName)
				$response = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $headers, $null, $null, $propertiesToReplace); 
				if($response -ne $null -and ($response|Measure-Object).Count -gt 0)
				{
					foreach($assignment in $response){
						if([Helpers]::CheckMember($assignment, "name") -and [Helpers]::CheckMember($assignment, "properties.complianceStatus")){
						$assignmentObject = "" | Select-Object "assignmentName", "complianceStatus" 
						$assignmentObject.assignmentName = $assignment.name
						$assignmentObject.complianceStatus = $assignment.properties.complianceStatus
						$policyAssignments += $assignmentObject
						}

					}
				}
				if(($policyAssignments | Measure-Object).Count -gt 0){

					$nonCompliantPolicyAssignment = $policyAssignments | Where-Object { $_.complianceStatus -ne "Compliant"}
					if($null -ne $nonCompliantPolicyAssignment -and ( $nonCompliantPolicyAssignment | Measure-Object).Count -gt 0 ){
						$controlStatus = [VerificationResult]::Failed
						$controlResult.AddMessage("For following guest configuration assignment, compliance status is 'NonCompliant' or  'Pending'.");
						$controlResult.AddMessage($nonCompliantPolicyAssignment);
					}else{
						$controlStatus = [VerificationResult]::Passed
						$controlResult.AddMessage("For all guest configuration assignment, compliance status is 'Compliant'.");
						$controlResult.AddMessage($policyAssignments);
					}
					
				}else{
					$controlStatus = [VerificationResult]::Verify
					$controlResult.AddMessage("No guest configuration policy assignment found.");
				}
			}
			catch {
				
				if([Helpers]::CheckMember($_,"Exception.Message") -and $_.Exception.Message -imatch "404"){
					$controlStatus = [VerificationResult]::Passed
					$controlResult.AddMessage("No guest configuration policy assignment has been found for this resource.");
				}else{
					$controlStatus = [VerificationResult]::Verify
					$controlResult.AddMessage("Not able to fetch guest configuration policy assignments details.");
				}

			}
		
		$controlResult.VerificationResult = $controlStatus
		return $controlResult;
	}

	hidden [ControlResult] CheckRequiredExtensions([ControlResult] $controlResult)
	{
		if(-not $this.VMDetails.IsVMDeallocated)
		{
			$controlStatus = [VerificationResult]::Failed
			$requiredExtensions  = $this.VMControlSettings.RequiredExtensions
			
			if($null -ne $requiredExtensions -and ($requiredExtensions | Measure-Object).Count -gt 0){
				$unhealthyExtensions = @()
				$missingExtensions = @()
				$installedExtensions = @()
				$hasControlFailed = $false
				if([Helpers]::CheckMember($this.ResourceObject, "Extensions")){

					$requiredExtensions | ForEach-Object {
						$requiredExtension = $_
						$installedExtension = $this.ResourceObject.Extensions | Where-Object {$_.VirtualMachineExtensionType -eq $requiredExtension.ExtensionType <# -and $_.Publisher -eq $requiredExtension.Publisher #> } 
						if($null -eq $installedExtension){
							$missingExtensions += $requiredExtension
							$hasControlFailed = $true
						}
						elseif($installedExtension.ProvisioningState -eq "Succeeded"){
							$installedExtensions += $requiredExtension
						}else{
							$unhealthyExtensions += $requiredExtension
							$hasControlFailed = $true
						}
					}
						
					if(($installedExtensions | Measure-Object).Count -gt 0){
						$controlResult.AddMessage("Following extensions are present in VM:",$installedExtensions);
					}
					if(($unhealthyExtensions | Measure-Object).Count -gt 0){
						$controlResult.AddMessage("Following extensions are present in VM but are not healthy:",$unhealthyExtensions);
					}
					if(($missingExtensions | Measure-Object).Count -gt 0){
						$controlResult.AddMessage("Following required extensions are not present in VM:",$missingExtensions);
					}
					
					if($hasControlFailed){
						$controlStatus = [VerificationResult]::Failed
						$missingExtensions = $missingExtensions + $unhealthyExtensions
						$controlResult.SetStateData("Missing or unhealthy extensions:", $missingExtensions);
					}else{
						$controlStatus = [VerificationResult]::Passed
						$controlResult.AddMessage("All required extensions are present in VM.");
					}

				}else{
					$controlResult.AddMessage("Following required extensions are not present in VM:",$requiredExtensions);
				}
			}else{
				$controlStatus = [VerificationResult]::Passed
				$controlResult.AddMessage("No mandatory extensions need to be deployed on VM.");
			}
		}
		else
		{
			$controlStatus = [VerificationResult]::Verify
			$controlResult.AddMessage("This VM is currently in a 'deallocated' state. Unable to check security controls on it.");
		}
		$controlResult.VerificationResult = $controlStatus
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
						$ipResource = Get-AzResource -ResourceId $_.PublicIpAddress.Id 
						if($ipResource)
						{
							$publicIpObject = Get-AzPublicIpAddress -Name $ipResource.Name -ResourceGroupName $ipResource.ResourceGroupName
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
	    #Do not check for deallocated status for the VM and directly show the status from ASC
		$ascDiskEncryptionStatus = $false;

		if($null -ne $this.ASCSettings -and [Helpers]::CheckMember($this.ASCSettings, "properties.policyAssessments"))
		{
			$adeSetting = $null
			if([FeatureFlightingManager]::GetFeatureStatus("EnableASCPolicyOnVMCheckUsingPolicyAssessmentKey",$($this.SubscriptionContext.SubscriptionId)) -eq $true)
			{
				$adeSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.assessmentKey -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.DiskEncryptionAssessmentKey};
			}
			else 
			{
				$adeSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.policyName -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.DiskEncryption};
			}
			
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
			$vulnSetting = $null
			if([FeatureFlightingManager]::GetFeatureStatus("EnableASCPolicyOnVMCheckUsingPolicyAssessmentKey",$($this.SubscriptionContext.SubscriptionId)) -eq $true)
			{
				$vulnSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.assessmentKey -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.VulnerabilityScanAssessmentKey};
			}
			else 
			{
				$vulnSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.policyName -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.VulnerabilityScan};
			}

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
					$patchSetting = $null
					if([FeatureFlightingManager]::GetFeatureStatus("EnableASCPolicyOnVMCheckUsingPolicyAssessmentKey",$($this.SubscriptionContext.SubscriptionId)) -eq $true)
					{
						$patchSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.assessmentKey -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.OSUpdatesAssessmentKey};
					}
					else 
					{
						$patchSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.policyName -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.OSUpdates};
					}

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
		#[ResourceHelper]::RegisterResourceProviderIfNotRegistered([SecurityCenterHelper]::ProviderNamespace);
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
				$vulnSetting = $null
				if([FeatureFlightingManager]::GetFeatureStatus("EnableASCPolicyOnVMCheckUsingPolicyAssessmentKey",$($this.SubscriptionContext.SubscriptionId)) -eq $true)
				{
					$vulnSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.assessmentKey -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.VulnerabilityScanAssessmentKey};
				}
				else 
				{
					$vulnSetting = $this.ASCSettings.properties.policyAssessments | Where-Object {$_.policyName -eq $this.ControlSettings.VirtualMachine.ASCPolicies.PolicyAssignment.VulnerabilityScan};
				}
				
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
				$controlResult.AddMessage("Details of failing baseline rules can be obtained from Log Analytics workspace :" ,$workspaceId);
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
						$effectiveNSG = Get-AzEffectiveNetworkSecurityGroup -NetworkInterfaceName $_.Name -ResourceGroupName $_.ResourceGroupName -WarningAction SilentlyContinue -ErrorAction Stop
					}
					catch
					{
						$isManual = $true
						$statusCode = ($_.Exception).InnerException.Response.StatusCode;
						if($statusCode -eq [System.Net.HttpStatusCode]::BadRequest -or $statusCode -eq [System.Net.HttpStatusCode]::Forbidden -or $statusCode -eq [System.Net.HttpStatusCode]::Conflict)
						{							
							$controlResult.AddMessage(($_.Exception).InnerException.Message);	
						}
						# else
						# {
						# 	throw $_
						# }
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