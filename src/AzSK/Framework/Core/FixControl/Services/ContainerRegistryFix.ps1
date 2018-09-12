Set-StrictMode -Version Latest 

class ContainerRegistryFix: FixServicesBase
{       
	[PSObject] $ResourceObject = $null;

    ContainerRegistryFix([string] $subscriptionId, [ResourceConfig] $resourceConfig, [string] $resourceGroupName): 
        Base($subscriptionId, $resourceConfig, $resourceGroupName) 
    { }

	[MessageData[]] DisableAdminAccount([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		
		$detailedLogs += [MessageData]::new("Disabling admin account for Container Registry [$($this.ResourceName)]...");
        $result = Update-AzureRmContainerRegistry `
                    -ResourceGroupName $this.ResourceGroupName `
                    -Name $this.ResourceName `
                    -DisableAdminUser `
					-ErrorAction Stop

		$detailedLogs += [MessageData]::new("Admin account has been disabled for Container Registry [$($this.ResourceName)]", $result);
		
		return $detailedLogs;
    }
}
