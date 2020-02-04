Set-StrictMode -Version Latest
class SVTIaasBase: AzSVTBase
{
	hidden [PSObject] $ResourceObject;
	hidden [PSObject[]] $vNetNics;
	hidden [PSObject[]] $vNetNicsWIssues;
	hidden [PSObject[]] $vNetPIPIssues;
	hidden [PSObject[]] $vNetNicsOutput;

	SVTIaasBase([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName):
        Base($subscriptionId, $resourceGroupName, $resourceName)
    {
        $this.GetResourceObject();
		$this.GetvNetNics($this.ResourceObject.Subnets);
		$this.GetvnetNicsProperties($this.vNetNics);
    }

	SVTIaasBase([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId, $svtResource)
    {
		$this.GetResourceObject();
		$this.GetvNetNics($this.ResourceObject.Subnets);
		$this.GetvnetNicsProperties($this.vNetNics);
    }

	hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzVirtualNetwork -ResourceGroupName $this.ResourceContext.ResourceGroupName `
											 -Name $this.ResourceContext.ResourceName
            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }

	hidden [PSObject[]] GetvNetNics($VNetSubnets)
    {
		if([FeatureFlightingManager]::GetFeatureStatus("EnableVnetFixForSub",$($this.SubscriptionContext.SubscriptionId)))
		{
			if (-not $this.vNetNics)
			{
				$this.vNetNicsWIssues = @();
				$VNetSubnets | ForEach-Object{
					Set-Variable -Name currentsubnet -Scope Local -Value $_
					if($null -ne $currentsubnet.IpConfigurations )
					{
							$currentsubnet.IpConfigurations | ForEach-Object{
							Set-Variable -Name currentipconfig -Scope Local -Value $_
							if($currentipconfig.Id.Contains("Microsoft.Network/networkInterfaces"))
							{
									$currentipconfig = $currentipconfig.Id.ToLower()
									$nicresourceid =  $currentipconfig.Substring(0,$currentipconfig.LastIndexOf("ipconfigurations")-1)
									try
									{
										#<TODO: Perf Issue - Get-AzResource is called in foreach which will Provider list and perform issue. Resource Ids can be passed from base location>
										$nic = Get-AzResource -ResourceId $nicresourceid
										$this.vNetNics += $nic
									}
									catch
									{
										$this.vNetNicsWIssues += $nicresourceid;
									}								
							}
						}
					}
				}
			}
			return $this.vNetNics;
		}
		else
		{
			if (-not $this.vNetNics)
			{
				$this.vNetNicsWIssues = @();
				$VNetSubnets | ForEach-Object{
					Set-Variable -Name currentsubnet -Scope Local -Value $_
					if($null -ne $currentsubnet.IpConfigurations )
					{
							$currentsubnet.IpConfigurations | ForEach-Object{
							Set-Variable -Name currentipconfig -Scope Local -Value $_
							if($currentipconfig.Id.Contains("Microsoft.Network/networkInterfaces"))
							{
									$currentipconfig = $currentipconfig.Id.ToLower()
									$nicresourceid =  $currentipconfig.Substring(0,$currentipconfig.LastIndexOf("ipconfigurations")-1)
									try
									{
										#<TODO: Perf Issue - Get-AzResource is called in foreach which will Provider list and perform issue. Resource Ids can be passed from base location>
										$nic = Get-AzResource -ResourceId $nicresourceid
										$this.vNetNics += $nic
									}
									catch
									{
										$this.vNetNicsWIssues += $nicresourceid;
									}								
							}
						}
					}
				}
			}
			return $this.vNetNics;			
		}
    }

<<<<<<< HEAD
	hidden [PSObject[]] GetvnetNicsProperties($vNetNics)
	{
		if([FeatureFlightingManager]::GetFeatureStatus("EnableVnetFixForSub",$($this.SubscriptionContext.SubscriptionId)))
		{	if(-not $this.vNetNicsOutput)
			{
				if($null -ne $vNetNics )
				{
					$this.vNetPIPIssues = @();
					$tempVNetNICS = [array]($vNetNics)
					$tempVNetNICS | ForEach-Object{
						Set-Variable -Name nic -Scope Local -Value $_
						Set-Variable -Name nicproperties -Scope Local -Value $_.Properties
						try
						{
							$out = ""| Select-Object NICName, VMName, VMId, PrimaryStatus, NetworkSecurityGroupName,NetworkSecurityGroupId, PublicIpAddress, PrivateIpAddress,  EnableIPForwarding, IpConfigurations
							$out.NICName = $nic.Name
							$out.IpConfigurations = $nicproperties.IpConfigurations
							$out.EnableIPForwarding = $nicproperties.EnableIPForwarding
							$PublicIpAddresses = @()
							$PrivateIpAddresses = @()
							$nicproperties.IpConfigurations | ForEach-Object{
								Set-Variable -Name ipconfiguration -Scope Local -Value $_
								try
								{
									if(($ipconfiguration | Get-Member -Name "Properties") -and ($ipconfiguration.Properties | Get-Member -Name "PublicIpAddress") -and $ipconfiguration.Properties.PublicIpAddress)
									{
										$IPResource = Get-AzResource -ResourceId $ipconfiguration.Properties.PublicIpAddress.Id
										$pubResourceName = Get-AzPublicIpAddress -Name $IPResource.Name -ResourceGroupName $IPResource.ResourceGroupName
										$PublicIpAddresses += $pubResourceName.IpAddress
=======
	hidden [ControlResult] CheckNSGUseonGatewaySubnet([ControlResult] $controlResult)
    {
        $gateWaySubnet = $this.ResourceObject.Subnets | Where-Object {$_.Name -eq "GatewaySubnet"}
        if($null -ne $gateWaySubnet)
        {
            if($null-ne $gateWaySubnet.NetworkSecurityGroup  -and -not [System.String]::IsNullOrWhiteSpace($gateWaySubnet.NetworkSecurityGroup.Id))
            {
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("NSG is configured on the Gateway Subnet of VNet", ($gateWaySubnet | Select-Object Name, NetworkSecurityGroupText)));
				$controlResult.SetStateData("Gateway subnet of VNet", ($gateWaySubnet | Select-Object Name, NetworkSecurityGroup));
            }
            else
            {
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("There are no NSG's configured on the Gateway subnet of VNet"));
            }
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No Gateway subnet found on the VNet"));
        }

        return $controlResult;
    }

	hidden [ControlResult] CheckNSGConfigured([ControlResult] $controlResult)
    {
        $hasTCPPassed = $true
        if($null -ne $this.ResourceObject.Subnets)
        {
            $subnetsWithoutNSG = $this.ResourceObject.Subnets | Where-Object {$null -eq $_.NetworkSecurityGroup -and $_.Name.ToLower() -ne "gatewaysubnet"}
            $subnetsWithNSG = $this.ResourceObject.Subnets | Where-Object {$null -ne $_.NetworkSecurityGroup -and $_.Name.ToLower() -ne "gatewaysubnet"}

            if($null-ne $subnetsWithoutNSG  -and ($subnetsWithoutNSG | Measure-Object).count -gt 0)
            {
				$hasTCPPassed = $false
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("NSG is not configured for below subnet(s) of VNet", ($subnetsWithoutNSG | Select-Object Name, Id)));
            }
            if($null-ne $subnetsWithNSG  -and ($subnetsWithNSG | Measure-Object).Count -gt 0)
            {
                # Invalid NSG rules list for whole vNet
                $InvalidRulesList = @()
                $subnetsWithNSG | ForEach-Object{
                            # Invalid NSG rules list for current subnet
                            $InvalidRulesListForSubnet = @()
							$nsgid = $_.NetworkSecurityGroup.Id
							$nsglist = Get-AzResource -ResourceId $nsgid

							$nsglist | ForEach-Object{
								$rules = $_.Properties.SecurityRules
								$rules | ForEach-Object{
									$ruleproperties = $_.Properties
									if((($ruleproperties.Direction -eq "outbound") -or ($ruleproperties.Direction -eq "inbound")) -and (([Helpers]::CheckMember($ruleproperties,"SourceAddressPrefix")) -and $ruleproperties.SourceAddressPrefix -eq '*') -and $ruleproperties.DestinationAddressPrefix -eq '*' -and $ruleproperties.Access -eq "allow")
									{
										$InvalidRulesListForSubnet += $_ | Select-Object Id, Properties
>>>>>>> 4583f1488ecf243f9b6b4c7e515fee21bc872f53
									}
									$PrivateIpAddresses += $ipconfiguration.Properties.PrivateIpAddress
								}
								catch
								{
									$this.vNetPIPIssues += $ipconfiguration
								}
							}
<<<<<<< HEAD
							$out.PublicIpAddress = ([System.String]::Join(";",$PublicIpAddresses))
							$out.PrivateIpAddress = ([System.String]::Join(";",$PrivateIpAddresses))
=======
					$currentsubnet=$_
                    if(($InvalidRulesListForSubnet | Measure-Object).Count -gt 0)
                    {
                        $InvalidRulesList += $InvalidRulesListForSubnet
						$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Potentially dangerous any to any outbound/inbound security rule(s) found in subnet - ["+ $currentsubnet.Name +"]", $InvalidRulesListForSubnet));
                    }
                }
                if(($InvalidRulesList | Measure-Object).Count -gt 0)
                {
                    $hasTCPPassed = $false
                    $controlResult.SetStateData("Potentially dangerous any to any outbound/inbound security rule(s) found in vNet", $InvalidRulesList);
                }
            }
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No subnets found on VNet"));
        }
>>>>>>> 4583f1488ecf243f9b6b4c7e515fee21bc872f53

							if(($nicproperties | Get-Member -Name "VirtualMachine") -and $nicproperties.VirtualMachine )
							{
								$vmresource = Get-AzResource -ResourceId $nicproperties.VirtualMachine.Id
								$out.VMName = $vmresource.Name
							}
							else {
								$out.VMName = ""
							}
							if($null -ne ($nicproperties | Get-Member primary))
							{
								$out.PrimaryStatus = $nicproperties.primary
							}

							if(($nicproperties | Get-Member -Name "NetworkSecurityGroup") -and $nicproperties.NetworkSecurityGroup)
							{
								$nsgresource = Get-AzResource -ResourceId $nicproperties.NetworkSecurityGroup.Id
								$out.NetworkSecurityGroupName = $nsgresource.Name
							}
							$this.vNetNicsOutput += $out
						}
						catch
						{
							#eat the exception. Error nic is already added to the list
						}
					}
					$this.vNetNicsOutput = [array]($this.vNetNicsOutput)
				}
			}
			return $this.vNetNicsOutput;
		}
		else
		{
			if(-not $this.vNetNicsOutput)
			{
				if($null -ne $vNetNics )
				{
					$this.vNetPIPIssues = @();
					$tempVNetNICS = [array]($vNetNics)
					$tempVNetNICS | ForEach-Object{
						Set-Variable -Name nic -Scope Local -Value $_
						Set-Variable -Name nicproperties -Scope Local -Value $_.Properties
						try
						{
							$out = ""| Select-Object NICName, VMName, VMId, PrimaryStatus, NetworkSecurityGroupName,NetworkSecurityGroupId, PublicIpAddress, PrivateIpAddress,  EnableIPForwarding, IpConfigurations
							$out.NICName = $nic.Name
							$out.IpConfigurations = $nicproperties.IpConfigurations
							$out.EnableIPForwarding = $nicproperties.EnableIPForwarding
							$PublicIpAddresses = @()
							$PrivateIpAddresses = @()
							$nicproperties.IpConfigurations | ForEach-Object{
								Set-Variable -Name ipconfiguration -Scope Local -Value $_
								try
								{
									if(($ipconfiguration | Get-Member -Name "Properties") -and ($ipconfiguration.Properties | Get-Member -Name "PublicIpAddress") -and $ipconfiguration.Properties.PublicIpAddress)
									{
										$IPResource = Get-AzResource -ResourceId $ipconfiguration.Properties.PublicIpAddress.Id
										$pubResourceName = Get-AzPublicIpAddress -Name $IPResource.Name -ResourceGroupName $IPResource.ResourceGroupName
										$PublicIpAddresses += $pubResourceName.IpAddress
									}
									$PrivateIpAddresses += $ipconfiguration.Properties.PrivateIpAddress
								}
								catch
								{
									$this.vNetPIPIssues += $ipconfiguration
								}
							}
							$out.PublicIpAddress = ([System.String]::Join(";",$PublicIpAddresses))
							$out.PrivateIpAddress = ([System.String]::Join(";",$PrivateIpAddresses))

							if(($nicproperties | Get-Member -Name "VirtualMachine") -and $nicproperties.VirtualMachine )
							{
								$vmresource = Get-AzResource -ResourceId $nicproperties.VirtualMachine.Id
								$out.VMName = $vmresource.Name
							}
							else {
								$out.VMName = ""
							}
							if($null -ne ($nicproperties | Get-Member primary))
							{
								$out.PrimaryStatus = $nicproperties.primary
							}

							if(($nicproperties | Get-Member -Name "NetworkSecurityGroup") -and $nicproperties.NetworkSecurityGroup)
							{
								$nsgresource = Get-AzResource -ResourceId $nicproperties.NetworkSecurityGroup.Id
								$out.NetworkSecurityGroupName = $nsgresource.Name
							}
							$this.vNetNicsOutput += $out
						}
						catch
						{
							#eat the exception. Error nic is already added to the list
						}
					}
					$this.vNetNicsOutput = [array]($this.vNetNicsOutput)
				}
			}
			return $this.vNetNicsOutput;
		}

		
	}
}