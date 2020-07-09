#using namespace Microsoft.Azure.Commands.ExpressRouteVirtualNetwork.Models
Set-StrictMode -Version Latest
class ERvNet : SVTIaasBase
{
	ERvNet([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId, $svtResource)
    {
    }

	hidden [ControlResult] CheckPublicIps([ControlResult] $controlResult)
    {
        if($null -ne $this.vNetNicsOutput)
        {
            $PublicIps = @();
			$controlResult.AddMessage([MessageData]::new("Analyzing all the NICs configured in the VNet"));
            $PublicIps += ($this.vNetNicsOutput | Where-Object {!([System.String]::IsNullOrWhiteSpace($_.PublicIpAddress))})
            if($PublicIps.Count -gt 0)
            {
				$publicIPList = @()
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Verify below Public IP(s) on the ErVnet"));
                $PublicIps | ForEach-Object{
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
        $whiteListedRGs = $this.ControlSettings.ERvNet.WhiteListedRGs
        $whiteListedRemoteVirtualNetworkId = $this.ControlSettings.ERvNet.WhiteListedRemoteVirtualNetworkId
        $exemptedHubSubscriptionId = ""
        if(-not [string]::IsNullOrWhiteSpace($whiteListedRemoteVirtualNetworkId))
        {
            $exemptedHubSubscriptionId = $whiteListedRemoteVirtualNetworkId.Split("/")[2]
        }
        
        $vnetPeerings = Get-AzVirtualNetworkPeering -VirtualNetworkName $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName
        if($null -ne $vnetPeerings -and ($vnetPeerings|Measure-Object).count -gt 0)
        {
            $filteredVnetPeerings = @()
            # Filter whitelisted vNet peerings, if resource is in whitelisted RG
            if((-not [string]::IsNullOrEmpty($whiteListedRemoteVirtualNetworkId)) -and (($whiteListedRGs | Measure-Object).Count -gt 0) -and ($whiteListedRGs -contains $this.ResourceContext.ResourceGroupName))
            {
                $filteredVnetPeerings += $vnetPeerings | Where-Object { $_.RemoteVirtualNetwork.id -notlike $whiteListedRemoteVirtualNetworkId }
            }else{
                # All vNet peering are non-compliant, if resource is not in whitelisted RG
                $filteredVnetPeerings = $vnetPeerings
            }

            # If there is any non-compliant vNet peering fail the control
            if($null -ne $filteredVnetPeerings -and ($filteredVnetPeerings|Measure-Object).count -gt 0)
            {
                if(-not ($exemptedHubSubscriptionId -eq $this.SubscriptionContext.SubscriptionId)){
                    $controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Below peering found on ERVNet", $vnetPeerings));
                    $controlResult.SetStateData("Peering found on ERVNet", $vnetPeerings);
                }else{
                    $controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("All VNet peerings are exempted for ERvNet in current Subscription.", $vnetPeerings));
                }

            }else{
                $controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No additional VNet peerings found on ERVNet", $vnetPeerings));
            }

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
			$vNetNicsMultiVM = $this.vNetNicsOutput | Group-Object VMName | Where-Object {-not [System.String]::IsNullOrWhiteSpace($_.Name) -and $_.Count -gt 1}

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
									if($null -ne $tempIPConfig.properties.Subnet)
									{
										if(-not $tempIPConfig.properties.Subnet.Id.StartsWith($this.ResourceObject.Id,"CurrentCultureIgnoreCase"))
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

        $whiteListedRGs = $this.ControlSettings.ERvNet.WhiteListedRGs
        $whiteListedaddressPrefix =  $this.ControlSettings.ERvNet.WhiteListedaddressPrefix
        $whiteListednextHopType =  $this.ControlSettings.ERvNet.WhiteListednextHopType
        $whiteListedRemoteVirtualNetworkId = $this.ControlSettings.ERvNet.WhiteListedRemoteVirtualNetworkId
        $exemptedHubSubscriptionId = ""
        if(-not [string]::IsNullOrWhiteSpace($whiteListedRemoteVirtualNetworkId))
        {
            $exemptedHubSubscriptionId = $whiteListedRemoteVirtualNetworkId.Split("/")[2]
        }
      
        $subnetsWithUDRs = $this.ResourceObject.Subnets | Where-Object {$null -ne $_.RouteTable -and -not [System.String]::IsNullOrWhiteSpace($_.RouteTable.Id)}

        if($null -ne $subnetsWithUDRs -and ($subnetsWithUDRs | Measure-Object).count -gt 0)
        {
            $nonCompliantSubnetsWithUDRs = @()
            # Filter whitelisted UDR's, if resource is in whitelisted RG
            if(($whiteListedRGs | Measure-Object).Count -gt 0 -and ($whiteListedRGs -contains $this.ResourceContext.ResourceGroupName)){
                $subnetsWithUDRs | Foreach-Object {
                    $IsUDRPermitted = $true
                    try{
                        $routeTableResourceId = $_.RouteTable.Id
                        $routeTable = Get-AzResource -ResourceId $routeTableResourceId -ErrorAction SilentlyContinue
                        if($null -ne  $routeTable -and ($whiteListedRGs -contains $routeTable.ResourceGroupName) -and [Helpers]::CheckMember($routeTable,"Properties.routes")){
                            $routes =  $routeTable.Properties.routes
                            $routes | ForEach-Object {
                                $addressPrefix =  $_.properties.addressPrefix
                                $nextHopType  = $_.properties.nextHopType
                                if(-not($addressPrefix -eq $whiteListedaddressPrefix -and $nextHopType -eq $whiteListednextHopType)){
                                    $IsUDRPermitted = $false
                                }
                            }
                        }else{
                            $IsUDRPermitted = $false
                        }
                    }catch{
                        $IsUDRPermitted = $false
                    }
                    if(-not $IsUDRPermitted){
                        $nonCompliantSubnetsWithUDRs += $_
                    }
                }
            }else{
                # All UDR's are non-compliant, if resource is not in whitelisted RG
                $nonCompliantSubnetsWithUDRs = $subnetsWithUDRs
            }

            # If there is any non-compliant UDR fail the control
            if($null -ne $nonCompliantSubnetsWithUDRs -and ($nonCompliantSubnetsWithUDRs | Measure-Object).count -gt 0){
                
                if(-not ($exemptedHubSubscriptionId -eq $this.SubscriptionContext.SubscriptionId)){
                    $controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new(($subnetsWithUDRs | Select-Object Name, RouteTableText)));
                    $controlResult.SetStateData("UDRs found on any Subnet of ERVNet", $subnetsWithUDRs);
                }else{
                    $controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("All UDRs are exempted for ERvNet in current Subscription.", [MessageData]::new(($subnetsWithUDRs | Select-Object Name, RouteTableText))));
                }
            
            }else{
                $controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("No additional UDRs found on any Subnet of ERVNet"));
            }

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
        $gateways = Get-AzVirtualNetworkGateway -ResourceGroupName $this.ResourceContext.ResourceGroupName
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
        $ilbs = Get-AzLoadBalancer
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
                                    $pubResourceName = Get-AzPublicIpAddress -Name $publicIpResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName
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
        $resources = [array](Get-AzResource -ResourceGroupName $this.ResourceContext.ResourceGroupName)

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
        $locks = [array](Get-AzResourceLock -ResourceGroupName $this.ResourceContext.ResourceGroupName -AtScope)

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
        $output = @()
        $missingPolicies = @()
        $configuredPolicies = @()
        $subscriptionId = $this.SubscriptionContext.SubscriptionId 
        $resourceGroupName = $this.ResourceContext.ResourceGroupName
        if($null -ne $controlSettings -and [Helpers]::CheckMember($controlSettings,"Policies"))
        {
            $policies = $controlSettings.Policies
            $enabledPolicies = @()
            $sdoPolicies = @()
            #Filter to get only enabled and sdo tagged policy
            $enabledPolicies += $policies | Where-Object {( ($_.tags.Trim().ToLower().Contains("sdo")) -and ($_.enabled) )}
            #Filter to get policy applicable for current ErvNet RG
            if(($enabledPolicies | Measure-Object).Count -gt 0){
                $enabledPolicies | ForEach-Object {
                    $ErvNetRGPatterns = ((($_.applicableForRGs | ForEach-Object {'^' + [regex]::escape($_) + '$' }) -join '|') ) -replace '[\\]',''
                    if(($this.ResourceContext.ResourceGroupName.ToLower() -imatch $ErvNetRGPatterns)){
                        $sdoPolicies += $_
                    }
                }
            }

            if(($sdoPolicies | Measure-Object).Count -gt 0)
            {
                $configuredPolicies = Get-AzPolicyAssignment -IncludeDescendent -ErrorAction SilentlyContinue
                if($null -ne $configuredPolicies -and ($configuredPolicies | Measure-Object).Count -gt 0){
                    $sdoPolicies | ForEach-Object{
                        Set-Variable -Name pol -Scope Local -Value $_
                        Set-Variable -Name policyDefinitionName -Scope Local -Value $_.policyDefinitionName
                        Set-Variable -Name tags -Scope Local -Value $_.tags
                        $policyScope =  ( $_.scope -replace "subscriptionId",$subscriptionId ) -replace "resourceGroupName" , $resourceGroupName
                          
                        $foundPolicies = [array]($configuredPolicies | Where-Object {$_.Name -like $policyDefinitionName -and $_.properties.scope -eq $policyScope -and $_.properties.enforcementMode -eq "Default"})
                    
                        if($null -ne $foundPolicies)
                        {
                            if($foundPolicies.Length -gt 0)
                            {
                                $output += $pol
                            }
                            else{
                                $missingPolicies += $pol
                            }
                        }
                        else{
                            $missingPolicies += $pol
                        }
                        
                    }
                }else{
                    $missingPolicies += $sdoPolicies
                }
                
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Passed,[MessageData]::new("No mandatory ARM policies required to be configured on the subscription because of ERNetwork."));
            }
            
        }
        if(($missingPolicies | Measure-Object).Count -le 0)
        {
            $controlResult.VerificationResult = [VerificationResult]::Passed;
        }
        else
        {
            $missingPolicies = $missingPolicies | select-object "policyDefinitionName"
			$controlResult.SetStateData("Missing mandatory policies", $missingPolicies);
			$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Following mandatory policies are missing which are demanded by the control tags:",$missingPolicies));
        }
        return $controlResult;
    }
}
