#
# CloudService.ps1
#
Set-StrictMode -Version Latest 
class PSCloudService
{
	[PSObject] $CloudServiceName
	[PSObject] $CloudServiceRGName	
	[DeploymentSlot[]] $DeploymentSlots	
	[PSObject] $VirtualIps
	[PSObject] $UpgradeType
	[PSObject] $UpgradeDomainCount
	[Extension[]] $Extensions
	[string] $CloudServiceResourceType = "Microsoft.ClassicCompute/domainNames"
	[string] $CloudServiceAPIVersion = "2016-04-01"

	PSCloudService([string] $cloudServiceName, [string] $cloudServiceRGName)
	{
		$this.CloudServiceName = $cloudServiceName;
		$this.CloudServiceRGName = $cloudServiceRGName;
	}

	[void] LoadCloudConfiguration()
	{
		$cloudServiceSlots = Get-AzureRmResource -ResourceGroupName $this.CloudServiceRGName `
								-Name $this.CloudServiceName `
								-ResourceType "$($this.CloudServiceResourceType)/slots" `
								-ApiVersion $this.CloudServiceAPIVersion

		if(($cloudServiceSlots | Measure-Object).Count -gt 0)
		{
			$this.DeploymentSlots = @();			
			$cloudServiceSlots | ForEach-Object {
				$cloudSlot = $_;
				$DeploymentSlot	= [DeploymentSlot]::new();
				$DeploymentSlot.SlotName = $cloudSlot.Name;
				if(([Helpers]::CheckMember($cloudSlot,"Properties")) -and ([Helpers]::CheckMember($cloudSlot.Properties,"configuration")))
				{
					$DeploymentSlot.CloudCSCFG = [xml]$cloudSlot.Properties.configuration

					if($null -ne $DeploymentSlot.CloudCSCFG.ServiceConfiguration)						
					{
						$DeploymentSlot.IsOSAutoUpdateTurnedOn = $false;
						if($null -ne $DeploymentSlot.CloudCSCFG.ServiceConfiguration.Attributes["osVersion"] -and $DeploymentSlot.CloudCSCFG.ServiceConfiguration.Attributes["osVersion"].value -eq "*")
						{
							$DeploymentSlot.IsOSAutoUpdateTurnedOn = $true;
						}						
					}
				}
				
				if(([Helpers]::CheckMember($cloudSlot,"Properties")) -and ([Helpers]::CheckMember($cloudSlot.Properties,"slotType")))
				{
					$DeploymentSlot.SlotType = $cloudSlot.Properties.slotType
				}

				#get roles
				$cloudServiceRoles = Get-AzureRmResource -ResourceGroupName $this.CloudServiceRGName `
										-Name "$($this.CloudServiceName)/$($DeploymentSlot.SlotName)" `
										-ResourceType "$($this.CloudServiceResourceType)/slots/roles" `
										-ApiVersion $this.CloudServiceAPIVersion
	
				if(($cloudServiceRoles | Measure-Object).Count -gt 0)
				{
					$DeploymentSlot.Roles = @();
					$cloudServiceRoles | ForEach-Object{
						$cloudRole = $_;
						$Role = [Role]::new();
						$Role.RoleName = $cloudRole.Name
						if([Helpers]::CheckMember($cloudRole,"Properties"))
						{
							$Role.OSVersion = $cloudRole.Properties.osVersion	
							$cloudRoleProps = $cloudRole.Properties;
							if([Helpers]::CheckMember($cloudRoleProps,"inputEndpoints") -and ($cloudRoleProps.inputEndpoints | Measure-Object).Count -gt 0)
							{
								$Role.InputEndpoints = @();								
								$cloudRole.Properties.inputEndpoints | ForEach-Object{
									$roleInputEP = $_
									$InputEndPoint = [InputEndpoint]::new();
									if([Helpers]::CheckMember($roleInputEP,"publicIpAddress"))
									{
										$InputEndPoint.PublicIPAddress = $roleInputEP.publicIpAddress;
									}
									$InputEndPoint.Protocol = $roleInputEP.protocol;
									$InputEndPoint.PrivatePort = $roleInputEP.privatePort;
									$InputEndPoint.PublicPort = $roleInputEP.publicPort;
									if([Helpers]::CheckMember($roleInputEP,"virtualIpName"))
									{
										$InputEndPoint.VirtualIPName = $roleInputEP.virtualIpName;
									}
									$Role.InputEndpoints += $InputEndPoint;
								}
							}							
						}
						$Role.IsRemoteAccessEnabled = $false;
						$Role.IsRemoteForwarderEnabled = $false;
						if($null-ne $DeploymentSlot.CloudCSCFG `
							-and $null -ne $DeploymentSlot.CloudCSCFG.ServiceConfiguration `
							-and $null -ne $DeploymentSlot.CloudCSCFG.ServiceConfiguration.Role)
						{
							foreach($configRole in $DeploymentSlot.CloudCSCFG.ServiceConfiguration.Role)
							{
								if($configRole.name -eq $Role.RoleName)
								{
									if([Helpers]::CheckMember($configRole,"ConfigurationSettings") -and $null -ne $configRole.ConfigurationSettings `
										-and [Helpers]::CheckMember($configRole.ConfigurationSettings,"Setting") `
										-and $null -ne $configRole.ConfigurationSettings.Setting)
										{
											foreach ($setting in $configRole.ConfigurationSettings.Setting)
											{
												if($setting.name -eq "Microsoft.WindowsAzure.Plugins.RemoteAccess.Enabled" -and $setting.value -eq "true")
												{
													$Role.IsRemoteAccessEnabled = $true;
												}
												elseif($setting.name -eq "Microsoft.WindowsAzure.Plugins.RemoteForwarder.Enabled" -and $setting.value -eq "true")
												{
													$Role.IsRemoteForwarderEnabled = $true;
												}
											}
										}
								}
							}
						}
						$DeploymentSlot.Roles += $Role;

					}
				}		
				
				$this.DeploymentSlots += $DeploymentSlot;
			}
		}		
	}

	hidden [void] LoadCloudConfigurationFromClassicConfig([xml] $CloudServiceResponse)
	{				
		# Get the results from the API as XML         
		
		if($null -ne $CloudServiceResponse.hostedservice)
		{		
			if([Helpers]::CheckMember($CloudServiceResponse.hostedservice, "Deployments")){
                if([Helpers]::CheckMember($CloudServiceResponse.hostedservice.Deployments , "Deployment")){
				foreach($svc in $CloudServiceResponse.hostedservice.Deployments.Deployment)
				{
					$DeploymentSlot = $this.DeploymentSlots | Where-Object { $_.SlotName -eq $svc.DeploymentSlot}
					
					if($null -ne $svc.RoleInstanceList)
					{
						foreach($instance in $svc.RoleInstanceList.RoleInstance)
						{
							[RoleInstance] $roleInstance = [RoleInstance]::new()
							$roleInstance.RoleName = $instance.RoleName
							$roleInstance.InstanceName = $instance.InstanceName
							$roleInstance.PowerState = $instance.PowerState
							if([Helpers]::CheckMember($instance, "IpAddress"))
							{
								$roleInstance.IPAddress = $instance.IpAddress
							}
							
							if([Helpers]::CheckMember($instance, "InstanceEndpoints") -and $null -ne $instance.InstanceEndpoints -and $null -ne $instance.InstanceEndpoints.InstanceEndpoint)
							{
								$roleInstance.InstanceEndpoints = [array]($instance.InstanceEndpoints.InstanceEndpoint | Select-Object Name, Vip, PublicPort, LocalPort, Protocol)
							}

							$Role = $DeploymentSlot.Roles | Where-Object { $_.RoleName -eq $roleInstance.RoleName}
							if($null -eq $Role.RoleInstances)
							{
								$Role.RoleInstances = @()
							}

							if([Helpers]::CheckMember($svc, "RoleList"))
							{
								$roleFromClassicObj = $svc.RoleList.Role | Where-Object { $_.RoleName -eq $roleInstance.RoleName }
							
								if($null -ne $roleFromClassicObj)
								{
									if([Helpers]::CheckMember($roleFromClassicObj, "RoleType"))
									{
										$Role.RoleType = $roleFromClassicObj.RoleType
									}
								}
							}
							
							$Role.RoleInstances += $roleInstance		        
							
                            if([Helpers]::CheckMember($svc, "VirtualIPs") -and [Helpers]::CheckMember($svc.VirtualIPs, "VirtualIP"))
                            {
							    $Role.VirtualIPs = [array]($svc.VirtualIPs.VirtualIP | Select-Object Address, IsDnsProgrammed)
                            }

                            if([Helpers]::CheckMember($svc, "UpgradeDomainCount"))
                            {
							    $Role.UpgradeDomainCount = $svc.UpgradeDomainCount
                            }

							#    Write-Host `nRole Extensions: -ForegroundColor DarkYellow
							#    Write-Host ------------------

							$Role.Extensions = @()
							if(([Helpers]::CheckMember($svc ,"ExtensionConfiguration")) -and ([Helpers]::CheckMember($svc.ExtensionConfiguration,"NamedRoles") ))
							{
								foreach($instanceRole in $svc.ExtensionConfiguration.NamedRoles.Role)
								{
									if($instanceRole.RoleName -eq $instance.RoleName)
									{
										[Extension] $extension = [Extension]::new()
										$extension.RoleName = $instanceRole.RoleName		    
										if($null -ne $instanceRole.Extensions.Extension)
										{
											$extension.ExtensionId =  ($instanceRole.Extensions.Extension | Select-Object Id ) 
										}
										$Role.Extensions += $extension
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

}

class RoleInstance
{	
	[PSObject] $RoleName
	[PSObject] $InstanceName
	[PSObject] $PowerState
	[PSObject] $IPAddress
	[PSObject] $InstanceEndpoints
}

class Role
{
	[string] $RoleName
	[string] $OSVersion
	[string] $RoleType
	[InputEndpoint[]] $InputEndpoints
	[RoleInstance[]] $RoleInstances
	[bool] $IsRemoteForwarderEnabled
	[bool] $IsRemoteAccessEnabled
	[PSObject] $VirtualIPs
	[PSObject] $UpgradeDomainCount
	[Extension[]] $Extensions
}

class InputEndpoint
{
	[string] $PublicIPAddress
	[string] $PrivatePort
	[string] $PublicPort
	[string] $Protocol
	[string] $VirtualIPName
}

class Extension
{
	[PSObject] $RoleName
	[PSObject] $ExtensionId
}

class DeploymentSlot
{
	[string] $SlotName
	[PSObject] $CloudCSCFG 
	[Role[]] $Roles
	[bool] $IsOSAutoUpdateTurnedOn
	[string] $SlotType
}