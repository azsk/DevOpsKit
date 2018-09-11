#using namespace Microsoft.Azure.Commands.VirtualNetwork.Models
Set-StrictMode -Version Latest
class VirtualNetwork: SVTIaasBase
{
    VirtualNetwork([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName):
        Base($subscriptionId, $resourceGroupName, $resourceName)
    {
    }

	VirtualNetwork([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId, $svtResource)
    {
    }

	hidden [ControlResult] CheckPublicIps([ControlResult] $controlResult)
    {
        if($null -ne $this.vNetNicsOutput)
        {
			$controlResult.AddMessage([MessageData]::new("Analyzing all the NICs configured in the VNet"));
            $PublicIpCount = (($this.vNetNicsOutput | Where-Object {!([System.String]::IsNullOrWhiteSpace($_.PublicIpAddress))}) | Measure-Object).count
            if($PublicIpCount -gt 0)
            {
				$publicIPList = @()
				$controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Verify below Public IP(s) on the Vnet"));
                $this.vNetNicsOutput | ForEach-Object{
                    Set-Variable -Name nic -Scope Local -Value $_
					$publicIP = $nic | Select-Object NICName, VMName, PrimaryStatus, NetworkSecurityGroupName, PublicIpAddress, PrivateIpAddress
					$publicIPList += $publicIP
					$controlResult.AddMessage([MessageData]::new($publicIP));
                }

				$controlResult.SetStateData("Public IP(s) on the Vnet", $publicIPList);
            }
            else
            {
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No Public IP is configured in any NIC on the Vnet"));
            }
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No NICs found on the VNet with Public IP configured"));
        }

        return $controlResult;
    }

	hidden [ControlResult] CheckIPForwardingforNICs([ControlResult] $controlResult)
    {
        if($null -ne $this.vNetNicsOutput -and ($this.vNetNicsOutput | Measure-Object).count -gt 0)
		{
			[array] $vNetNicsIPFwed = $this.vNetNicsOutput | Where-Object { $_.EnableIPForwarding }

			if($null -ne $vNetNicsIPFwed -and ($vNetNicsIPFwed | Measure-Object).count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Verify IP Forwarding is enabled for below NIC(s) in VNet"));
				$controlResult.AddMessage([MessageData]::new(($vNetNicsIPFwed | Select-Object NICName, EnableIPForwarding)));
				$controlResult.SetStateData("IP Forwarding is enabled for NIC(s) in VNet", $vNetNicsIPFwed);
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("There are no NICs with EnableIPForwarding turned on the VNet"));
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("There are no NICs with EnableIPForwarding turned on the VNet"));
		}

        return $controlResult;
    }

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
                #$checkSubnets = @()
                $InvalidRulesList = @()
                $subnetsWithNSG | ForEach-Object{
							$nsgid = $_.NetworkSecurityGroup.Id
							$nsglist = Get-AzureRmResource -ResourceId $nsgid

							$nsglist | ForEach-Object{
								$rules = $_.Properties.SecurityRules
								$rules | ForEach-Object{
									$ruleproperties = $_.Properties
									if((($ruleproperties.Direction -eq "outbound") -or ($ruleproperties.Direction -eq "inbound")) -and (([Helpers]::CheckMember($ruleproperties,"SourceAddressPrefix")) -and $ruleproperties.SourceAddressPrefix -eq '*') -and $ruleproperties.DestinationAddressPrefix -eq '*' -and $ruleproperties.Access -eq "allow")
									{
										$InvalidRulesList += $_ | Select-Object Id, Properties
									}
								}
							}
					$currentsubnet=$_
                    if(($InvalidRulesList | Measure-Object).Count -gt 0)
                    {
						$controlResult.SetStateData("Potentially dangerous any to any outbound security rule(s) found in subnet - ["+ $_.Name +"]", $InvalidRulesList);
						$hasTCPPassed = $false
						$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Potentially dangerous any to any outbound security rule(s) found in subnet - ["+ $_.Name +"]", $InvalidRulesList));
                    }
                }
            }
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No subnets found on VNet"));
        }

		if($hasTCPPassed -eq $true)
        {
			  $controlResult.VerificationResult = [VerificationResult]::Passed;
        }

        return $controlResult;
    }

	hidden [ControlResult] CheckGatewayUsed([ControlResult] $controlResult)
    {
        $vNetGateways = @()
        $VNetSubnets = $this.ResourceObject.Subnets
        if($null -ne $VNetSubnets)
        {
            $VNetSubnets | ForEach-Object{
                Set-Variable -Name currentsubnet -Scope Local -Value $_
                if($null -ne $currentsubnet.IpConfigurations )
                {
                    $currentsubnet.IpConfigurations | ForEach-Object{
						Set-Variable -Name currentipconfig -Scope Local -Value $_
						if($currentipconfig.Id.ToLower().Contains("microsoft.network/virtualnetworkgateways"))
						{
							$currentipconfig = $currentipconfig.Id.ToLower()
							$gatewayresourceid =  $currentipconfig.Substring(0,$currentipconfig.LastIndexOf("ipconfigurations")-1)
							$gateway = Get-AzureRmResource -ResourceId $gatewayresourceid

							$vNetGateway = New-Object System.Object
							$vNetGateway | Add-Member -type NoteProperty -name ResourceName -Value $gateway.Name
							$vNetGateway | Add-Member -type NoteProperty -name ResourceGroupName -Value $gateway.ResourceGroupName
							$vNetGateway | Add-Member -type NoteProperty -name GatewayType -Value $gateway.Properties.gatewayType
							$vNetGateway | Add-Member -type NoteProperty -name VPNType -Value $gateway.Properties.vpnType

							$vNetGateways += $vNetGateway
						}
                    }
                }
			}
        }

        if($null -ne $vNetGateways -and ($vNetGateways | Measure-Object).Count -gt 0)
        {
            $controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Verify below virtual network gateways found on VNet", $vNetGateways));
			$controlResult.SetStateData("Virtual Network Gateways found on VNet", $vNetGateways);
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No gateways found in VNet"));
        }

        return $controlResult;
    }

	hidden [ControlResult] CheckVnetPeering([ControlResult] $controlResult)
    {
        $vnetPeerings = Get-AzureRmVirtualNetworkPeering -VirtualNetworkName $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName
        if($null -ne $vnetPeerings -and ($vnetPeerings|Measure-Object).count -gt 0)
        {
			$controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Verify below peering found on VNet", $vnetPeerings));
			$controlResult.SetStateData("Peering found on VNet", $vnetPeerings);
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No VNet peering found on VNet", $vnetPeerings));
        }

        return $controlResult;
    }
}