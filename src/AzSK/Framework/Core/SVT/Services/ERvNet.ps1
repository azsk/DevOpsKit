#using namespace Microsoft.Azure.Commands.ExpressRouteVirtualNetwork.Models
Set-StrictMode -Version Latest
class ERvNet : SVTIaasBase
{
    ERvNet([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName):
        Base($subscriptionId, $resourceGroupName, $resourceName)
    {
    }

	ERvNet([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId, $svtResource)
    {
    }

	hidden [ControlResult] CheckPublicIps([ControlResult] $controlResult)
    {
        if($null -ne $this.vNetNicsOutput )
        {
			$controlResult.AddMessage([MessageData]::new("Analyzing all the NICs configured in the VNet"));
            $publicIpCount = (($this.vNetNicsOutput | Where-Object {!([System.String]::IsNullOrWhiteSpace($_.PublicIpAddress))}) | Measure-Object).count
            if($publicIpCount -gt 0)
            {
				$publicIPList = @()
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Below Public IP(s) on the  ERVnet"));
                $this.vNetNicsOutput | ForEach-Object{
                    Set-Variable -Name nic -Scope Local -Value $_
					$publicIP = $nic | Select-Object NICName, VMName, PrimaryStatus, NetworkSecurityGroupName, PublicIpAddress, PrivateIpAddress
					$publicIPList += $publicIP
					$controlResult.AddMessage([MessageData]::new($publicIP));
                }
				$controlResult.SetStateData("Public IP(s) on the  ERVnet", $publicIPList);
            }
            else
            {
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No Public IP is configured in any NIC on the ERVnet"));
            }
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No NICs found on the ERVNet"));
        }
		if(($this.vNetNicsWIssues | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage([MessageData]::new("Not able to validate following NICs:", $this.vNetNicsWIssues));
		}
		if(($this.vNetPIPIssues | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage([MessageData]::new("Not able to validate following IPConfigurations:", $this.vNetPIPIssues));
		}

        return $controlResult;
    }

	hidden [ControlResult] CheckIPForwardingforNICs([ControlResult] $controlResult)
    {
		if($null -ne $this.vNetNicsOutput)
		{
            [array] $vNetNicsIPFwed = $this.vNetNicsOutput | Where-Object { $_.EnableIPForwarding }

            if($null -ne $vNetNicsIPFwed -and ($vNetNicsIPFwed | Measure-Object).count -gt 0)
            {
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("IP Forwarding is enabled for below NIC(s) in ERVNet"));
				$controlResult.AddMessage([MessageData]::new(($vNetNicsIPFwed | Select-Object NICName, EnableIPForwarding)));
				$controlResult.SetStateData("IP Forwarding is enabled for NIC(s) in ERVNet", $vNetNicsIPFwed);
            }
            else
            {
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("There are no NICs with EnableIPForwarding turned on the ERVNet"));
            }
		}
		else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No NICs found on the ERVNet"));
        }

		if(($this.vNetNicsWIssues | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage([MessageData]::new("Not able to validate following NICs:", $this.vNetNicsWIssues));
		}
		if(($this.vNetPIPIssues | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage([MessageData]::new("Not able to validate following IPConfigurations:", $this.vNetPIPIssues));
		}

        return $controlResult;
    }

	hidden [ControlResult] CheckNSGUseonGatewaySubnet([ControlResult] $controlResult)
    {
        $gateWaySubnet = $this.ResourceObject.Subnets | Where-Object { $_.Name -eq "GatewaySubnet" }
        if($null -ne $gateWaySubnet)
        {
            if($null -ne $gateWaySubnet.NetworkSecurityGroup -and -not [System.String]::IsNullOrWhiteSpace($gateWaySubnet.NetworkSecurityGroup.Id))
            {
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("NSG is configured on the Gateway Subnet of ERVNet", ($gateWaySubnet | Select-Object Name, NetworkSecurityGroupText)));
				$controlResult.SetStateData("Gateway subnet of ERVNet", ($gateWaySubnet | Select-Object Name, NetworkSecurityGroup));
            }
            else
            {
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("There are no NSG's configured on the Gateway subnet of ERVNet"));
            }
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No Gateway subnet found on the ERVNet"));
        }

        return $controlResult;
    }

	hidden [ControlResult] CheckVnetPeering([ControlResult] $controlResult)
    {
        $vnetPeerings = Get-AzureRmVirtualNetworkPeering -VirtualNetworkName $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName
        if($null -ne $vnetPeerings -and ($vnetPeerings|Measure-Object).count -gt 0)
        {
			$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Below peering found on ERVNet", $vnetPeerings));
			$controlResult.SetStateData("Peering found on ERVNet", $vnetPeerings);
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No VNet peerings found on ERVNet", $vnetPeerings));
        }

        return $controlResult;
    }

	hidden [ControlResult] CheckMultiNICVMUsed([ControlResult] $controlResult)
    {
		$VMNics = @()
		if($null -ne $this.vNetNicsOutput)
		{
			$vNetNicsMultiVM = $this.vNetNicsOutput | Group-Object VMId | Where-Object {-not [System.String]::IsNullOrWhiteSpace($_.Name) -and $_.Count -gt 1}

			$hasTCPPassed = $true
			if($null -ne $vNetNicsMultiVM)
			{
				$vNetNicsMultiVM | ForEach-Object{
					$NICGroup = @()
					$NICGroup += $_.Group

					if($null -ne $NICGroup)
					{
						$NICGroup | ForEach-Object{
							Set-Variable -Name tempNIC -Value $_
							if($null -ne $tempNIC.IpConfigurations )
							{
								$tempIpConfigurations = [array]($tempNIC.IpConfigurations)
								$tempIpConfigurations | ForEach-Object{
									Set-Variable -Name tempIPConfig -Value $_
									if($null -ne $tempIPConfig.Subnet)
									{
										if(-not $tempIPConfig.Subnet.Id.StartsWith($this.ResourceObject.Id,"CurrentCultureIgnoreCase"))
										{
											$hasTCPPassed = $false
										}
									}
								}
							}
						}
						$VMNics += $NICGroup
					}
				}
			}

			$controlResult.AddMessage([MessageData]::new(($this.vNetNicsOutput | Group-Object VMId | Where-Object {-not [System.String]::IsNullOrWhiteSpace($_.Name) } | Select-Object @{Name="[Count of NICs]";Expression= {$_.Count}}, @{Name="[VM ResourceID]";Expression= {$_.Name}})));
			if(-not $hasTCPPassed)
			{
				$controlResult.SetStateData("VM NIC details", $VMNics);
				$controlResult.VerificationResult = [VerificationResult]::Failed;
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("There are no VMs with more than one NIC"));
			}
		}
		else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No NICs found on the ERVNet"));
        }

		if(($this.vNetNicsWIssues | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage([MessageData]::new("Not able to validate following NICs:", $this.vNetNicsWIssues));
		}
		if(($this.vNetPIPIssues | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage([MessageData]::new("Not able to validate following IPConfigurations:", $this.vNetPIPIssues));
		}

        return $controlResult;
    }

	hidden [ControlResult] CheckUDRAddedOnSubnet([ControlResult] $controlResult)
    {
        $subnetsWithUDRs = $this.ResourceObject.Subnets | Where-Object {$null -ne $_.RouteTable -and -not [System.String]::IsNullOrWhiteSpace($_.RouteTable.Id)}

        if($null -ne $subnetsWithUDRs -and ($subnetsWithUDRs | Measure-Object).count -gt 0)
        {
			$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new(($subnetsWithUDRs | Select-Object Name, RouteTableText)));
			$controlResult.SetStateData("UDRs found on any Subnet of ERVNet", $subnetsWithUDRs);
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No UDRs found on any Subnet of ERVNet"));
        }

        return $controlResult;
    }

	hidden [ControlResult] CheckGatewayUsed([ControlResult] $controlResult)
    {
        $nonERvNetGateways = @()
		$hasTCPPassed = $true
        $gateways = Get-AzureRmVirtualNetworkGateway -ResourceGroupName $this.ResourceContext.ResourceGroupName
        $count = 0
        if(($null -ne $gateways) -and (($gateways | Measure-Object).count -gt 0))
        {
            $gateways | ForEach-Object{
                Set-Variable -Name gateway -Scope Local -Value $_

                if($null -ne $gateway.IpConfigurations)
                {
                    $tempIpConfigurations =  [array]($gateway.IpConfigurations)
                    $tempIpConfigurations | ForEach-Object{
                        Set-Variable -Name tempIpConfig -Value $_
                        if($tempIpConfig.Subnet.Id.StartsWith($this.ResourceObject.Id,"CurrentCultureIgnoreCase"))
                        {
                            if($gateway.GatewayType -ne "ExpressRoute")
                            {
								$nonERvNetGateway = New-Object System.Object
								$nonERvNetGateway | Add-Member -type NoteProperty -name ResourceName -Value $gateway.Name
								$nonERvNetGateway | Add-Member -type NoteProperty -name ResourceGroupName -Value $gateway.ResourceGroupName
								$nonERvNetGateway | Add-Member -type NoteProperty -name GatewayType -Value $gateway.GatewayType
								$nonERvNetGateway | Add-Member -type NoteProperty -name VPNType -Value $gateway.VpnType

								$nonERvNetGateways += $nonERvNetGateway

                                $hasTCPPassed = $false
                            }
							$controlResult.AddMessage([MessageData]::new("GateWay Name: " + $gateway.Name + " GatewayType: " + $gateway.GatewayType));
                            $count++
                        }
                    }
                }
            }
        }

        if($count -eq 0)
        {
			$controlResult.AddMessage([MessageData]::new("No gateways found"));
        }

        if(-not $hasTCPPassed)
        {
			$controlResult.SetStateData("Non Express Route gateways in ERVNet", $nonERvNetGateways);
			$controlResult.VerificationResult = [VerificationResult]::Failed;
        }
        else
        {
			$controlResult.VerificationResult = [VerificationResult]::Passed;
        }

        return $controlResult;
    }

	hidden [ControlResult] CheckInternalLoadBalancers([ControlResult] $controlResult)
    {
		$invalidlbList = @()
        $hasTCPPassed = $true
        $ilbs = Get-AzureRmLoadBalancer
        $count = 0

        if($null -ne $ilbs -and ($ilbs|Measure-Object).count -gt 0)
        {
            $ilbs | ForEach-Object {
                Set-Variable -Name ilb -Value $_ -Scope Local
                if($null -ne $ilb -and $null -ne $ilb.FrontendIpConfigurations)
                {
                    $ilb.FrontendIpConfigurations |ForEach-Object{
                        Set-Variable -Name frontEndIpConfig -Scope Local -Value $_

                        if($null -ne $frontEndIpConfig.Subnet)
                        {
							if($frontEndIpConfig.Subnet.Id.StartsWith($this.ResourceObject.Id,"CurrentCultureIgnoreCase"))
							{
                                if($null -ne $frontEndIpConfig.PublicIpAddress)
                                {
                                    $subParts = $frontEndIpConfig.PublicIpAddress.Id.Split('/')
                                    $publicIpResourceName = $subParts[$subParts.Length-1]
                                    $pubResourceName = Get-AzureRmPublicIpAddress -Name $publicIpResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName
                                    $hasTCPPassed = $false

									$invalidlb = New-Object System.Object
									$invalidlb | Add-Member -type NoteProperty -name Name -Value $ilbs.Name
									$invalidlb | Add-Member -type NoteProperty -name IpAddress -Value  $pubResourceName.IpAddress

									$invalidlbList += $invalidlb
									$controlResult.AddMessage([MessageData]::new("ILB Name: " + $ilbs.Name + " PublicIP: " + $pubResourceName.IpAddress));
                                }

								$controlResult.AddMessage([MessageData]::new("No public Ips found on ILB: " + $ilbs.Name));
                                $count++
                            }
                        }
                    }
                }
            }
        }

        if($count -eq 0)
        {
			$controlResult.AddMessage([MessageData]::new("No ILB found"));
        }
        if(-not $hasTCPPassed)
        {
			$controlResult.SetStateData("Non internal LBs in ERVNet", $invalidlbList);
			$controlResult.VerificationResult = [VerificationResult]::Failed;
        }
        else
        {
			$controlResult.VerificationResult = [VerificationResult]::Passed;
        }

        return $controlResult;
    }

	hidden [ControlResult] CheckOnlyNetworkResourceExist([ControlResult] $controlResult)
    {
        $resources = [array](Get-AzureRmResource -ResourceGroupName $this.ResourceContext.ResourceGroupName)

        if($null -ne $resources)
        {
            $nonApprovedResources = [array]($resources | Where-Object { -not $_.ResourceType.StartsWith("Microsoft.Network","CurrentCultureIgnoreCase")})
            if($null -ne $nonApprovedResources )
            {
				$controlResult.SetStateData("Non approved resources in ERVNet ResourceGroup", $nonApprovedResources);
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Other resource types found apart from Microsoft.Network\*. Below are the Resource IDs and Resource Types available under the ResourceGroup - ["+ $this.ResourceContext.ResourceGroupName +"]",($nonApprovedResources | Select-Object ResourceType, ResourceID)));
            }
            else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No other resource types found apart from Microsoft.Network\* . Below are the Resource ID available under the ResourceGroup - ["+ $this.ResourceContext.ResourceGroupName +"]"));
            }

			$controlResult.AddMessage([MessageData]::new("Resources configured under ResourceGroup - ["+ $this.ResourceContext.ResourceGroupName +"]",($resources | Select-Object ResourceType, ResourceID)));
        }
        else
		{
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No other resources found under the ResourceGroup - ["+ $this.ResourceContext.ResourceGroupName +"]"));
        }

        return $controlResult;
    }

	hidden [ControlResult] CheckResourceLockConfigured([ControlResult] $controlResult)
    {
        $locks = [array](Get-AzureRMResourceLock -ResourceGroupName $this.ResourceContext.ResourceGroupName -AtScope)

        if($null -eq $locks -or $locks.Length -le 0)
        {
			$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("No resource locks are configured at the ResourceGroup scope for - ["+ $this.ResourceContext.ResourceName +"]"));
        }
        else
		{
			if(($locks | Where-Object {$_.Properties.Level -eq $this.ControlSettings.ERvNet.ResourceLockLevel } | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("Found resource locks configured at the ResourceGroup scope for - ["+ $this.ResourceContext.ResourceName +"]", $locks));
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("No *$($this.ControlSettings.ERvNet.ResourceLockLevel)* resource locks are configured at the ResourceGroup scope for - ["+ $this.ResourceContext.ResourceName +"]"));
			}
        }

        return $controlResult;
    }

	hidden [ControlResult] CheckARMPolicyConfigured([ControlResult] $controlResult)
    {
		$controlSettings = $this.LoadServerConfigFile("Subscription.ARMPolicies.json");

        $hasTCPPassed = $true
        $UserTags = @()
        $UserTags += "mandatory"
        $UserTags += "sdo"
        $output = @()
        if($null -ne $controlSettings -and [Helpers]::CheckMember($controlSettings,"Policies"))
        {
            $policies = $controlSettings.Policies
            $policies | ForEach-Object{
                Set-Variable -Name pol -Scope Local -Value $_
                Set-Variable -Name polEnabled -Scope Local -Value $_.enabled
                Set-Variable -Name policyDefinitionName -Scope Local -Value $_.policyDefinitionName
                Set-Variable -Name tags -Scope Local -Value $_.tags
                $haveMatchedTags = (($tags | Where-Object { $UserTags.Contains($_.Trim().ToLower()) }).Length -gt 0)
                if($polEnabled -and $haveMatchedTags)
                {
                    $mandatoryPolicies = [array](Get-AzureRMPolicyAssignment | Where-Object {$_.Name -eq $policyDefinitionName})
                    if($null -eq $mandatoryPolicies -or $mandatoryPolicies.Length -le 0)
                    {
                        $hasTCPPassed = $false
                        $output += $pol
                    }
                }
            }
        }
        else
		{
			$controlResult.AddMessage([MessageData]::new("No mandatory ARM policies required to be configured on the subscription because of ERNetwork."));
        }

        if(-not $hasTCPPassed)
        {
			$controlResult.SetStateData("Missing mandatory policies", $output);
			$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Some of the mandatory policies are missing which are demanded by the control tags - ["+ $UserTags +"]", $output ));
        }
        else
        {
			$controlResult.VerificationResult = [VerificationResult]::Passed;
        }

        return $controlResult;
    }
}
