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
			 $nics =  Get-AzNetworkInterface #-ResourceGroupName $rgname
        	 $ipc = $VNetSubnets| Select-Object -Property 'IpConfigurations' -ExpandProperty 'IpConfigurations' 
		
				if($null -ne $ipc -and ($ipc.IpConfigurations | Measure-Object).Count -gt 0)
				{
					$this.vNetNics = $nics| Where-Object{($_.IpConfigurations.Id) -in  $ipc.IpConfigurations.Id}
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
		}
        return $this.vNetNics;
    }

	hidden [PSObject[]] GetvnetNicsProperties($vNetNics)
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
						if([FeatureFlightingManager]::GetFeatureStatus("EnableVnetFixForSub",$($this.SubscriptionContext.SubscriptionId)))
						{
			
			
							$NICPublicIpAddresses =  $nic.ipconfigurations.PublicIpAddress
							$PrivateIpAddresses = $nic.ipconfigurations.PrivateIpAddress
							$PublicIpAddresses =@()
							if(($PublicIpAddresses |Measure-Object).Count -gt 0)
							{
								$NICPublicIpAddresses | ForEach-Object{
									try
									{
					
									$IPResource = Get-AzResource -ResourceId $_.Id
									$pubResourceName = Get-AzPublicIpAddress -Name $IPResource.Name -ResourceGroupName $IPResource.ResourceGroupName
									$PublicIpAddresses += $pubResourceName.IpAddress
									}
									catch
									{
										
										$this.vNetPIPIssues += $nic
									}
											
								
								}
						    }

			
						}
						else
						{
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
