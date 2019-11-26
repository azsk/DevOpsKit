Set-StrictMode -Version Latest 

class AppServiceFix: FixServicesBase
{       
	[PSObject] $ResourceObject = $null;
    AppServiceFix([string] $subscriptionId, [ResourceConfig] $resourceConfig, [string] $resourceGroupName): 
        Base($subscriptionId, $resourceConfig, $resourceGroupName) 
    { }

	[PSObject] FetchAppServiceObject()
	{
		if(-not $this.ResourceObject)
		{
			$this.ResourceObject = Get-AzWebApp -Name $this.ResourceName -ResourceGroupName $this.ResourceGroupName
		}

		return $this.ResourceObject;
	}

	[MessageData[]] DisableWebSocket([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		
		$detailedLogs += [MessageData]::new("Disabling web socket for app service [$($this.ResourceName)]...");
		$result = Set-AzWebApp `
					-ResourceGroupName $this.ResourceGroupName `
					-Name $this.ResourceName `
					-WebSocketsEnabled $false `
					-ErrorAction Stop

		$detailedLogs += [MessageData]::new("Web socket has been disabled for app service [$($this.ResourceName)]", $result);
		
		return $detailedLogs;
    }

	[MessageData[]] SetLatestDotNetVersion([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		
		$detailedLogs += [MessageData]::new("Setting up .Net version for app service [$($this.ResourceName)]...");
		$result = Set-AzWebApp `
					-ResourceGroupName $this.ResourceGroupName `
					-Name $this.ResourceName `
					-NetFrameworkVersion $this.ControlSettings.AppService.LatestDotNetFrameworkVersionNumber `
					-ErrorAction Stop

		$detailedLogs += [MessageData]::new(".Net version has been set to latest version for app service [$($this.ResourceName)]", $result);
		
		return $detailedLogs;
    }

	[MessageData[]] Set64bitPlatform([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		
		$detailedLogs += [MessageData]::new("Setting up platform architecture to 64 bit for app service [$($this.ResourceName)]...");
		$result = Set-AzWebApp `
					-ResourceGroupName $this.ResourceGroupName `
					-Name $this.ResourceName `
					-Use32BitWorkerProcess $false `
					-ErrorAction Stop

		$detailedLogs += [MessageData]::new("Platform architecture has been set to 64 bit for app service [$($this.ResourceName)]", $result);
		
		return $detailedLogs;
    }

	[MessageData[]] EnableLogging([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		
		$detailedLogs += [MessageData]::new("Setting up logging and request tracing for app service [$($this.ResourceName)]...");
		$result = Set-AzWebApp `
					-ResourceGroupName $this.ResourceGroupName `
					-Name $this.ResourceName `
					-DetailedErrorLoggingEnabled $true `
					-HttpLoggingEnabled $true `
					-RequestTracingEnabled $true `
					-ErrorAction Stop

		$detailedLogs += [MessageData]::new("Logging and request tracing has been enabled for app service [$($this.ResourceName)]", $result);
		
		return $detailedLogs;
    }

	[MessageData[]] SetMultipleInstances([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$instanceCount = $this.ControlSettings.AppService.Minimum_Instance_Count;
		$detailedLogs += [MessageData]::new("Setting up minimum $instanceCount instances for app service [$($this.ResourceName)]...");

		$appServiceObject = $this.FetchAppServiceObject();
		if($appServiceObject)
		{
			$serverFarm = Get-AzResource -ResourceId $appServiceObject.ServerFarmId

			if($serverFarm)
			{
			
				if($serverFarm.Sku.Capacity -ge $this.ControlSettings.AppService.Minimum_Instance_Count)
				{
					$detailedLogs += [MessageData]::new("No action is required as minimum $instanceCount instances have already been set up for app service [$($this.ResourceName)].");
				}
				elseif([Helpers]::CheckMember($serverFarm,"Properties.maximumNumberOfWorkers") -and $serverFarm.Properties.maximumNumberOfWorkers -le $this.ControlSettings.AppService.Minimum_Instance_Count) {
					$detailedLogs += [MessageData]::new("Not able to setup minimum $instanceCount instances  for app service [$($this.ResourceName)] as maximum number of instances allowed for current App Service plan is less than $instanceCount.");
				}
				else
				{
					$result = Set-AzAppServicePlan `
									-Name $serverFarm.Name `
									-ResourceGroupName $serverFarm.ResourceGroupName `
									-NumberofWorkers $instanceCount `
									-ErrorAction Stop
					$detailedLogs += [MessageData]::new("Minimum instances have been set up for app service [$($this.ResourceName)]", $result);
				}
			}
			else
			{
				$detailedLogs += [MessageData]::new("Not able to fetch server farm with id [$($appServiceObject.ServerFarmId)]");
			}
		}
		else
		{
			$detailedLogs += [MessageData]::new("Unable to fetch app service [$($this.ResourceName)]");
		}
		
		return $detailedLogs;
    }

	[MessageData[]] EnableHttpsFlag([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		
		$detailedLogs += [MessageData]::new("Enabling HTTPS only flag for app service [$($this.ResourceName)]...");
		$result = Set-AzResource -ResourceName $this.ResourceName `
						-ResourceGroupName $this.ResourceGroupName `
						-ResourceType 'Microsoft.Web/sites' `
						-Properties @{httpsOnly='true'} `
						-Force `
						-ErrorAction Stop

		$detailedLogs += [MessageData]::new("HTTPS only flag is enabled for app service [$($this.ResourceName)]", $result);
		
		return $detailedLogs;
    }

		[MessageData[]] SetMinTLSVersion([PSObject] $parameters)
    {
			[MessageData[]] $detailedLogs = @();
			
			$detailedLogs += [MessageData]::new("Setting up minimum TLS Version to $($this.ControlSettings.AppService.TLS_Version) for app service [$($this.ResourceName)]...");
		
			$params = @{
					ApiVersion        = '2018-02-01'
					ResourceName      = '{0}/web' -f $this.ResourceName
					ResourceGroupName = $this.ResourceGroupName
					PropertyObject    = @{ minTlsVersion = $this.ControlSettings.AppService.TLS_Version }
					ResourceType      = 'Microsoft.Web/sites/config'
				}
				
			$result = Set-AzResource @params -ErrorAction Stop

			$detailedLogs += [MessageData]::new("Minimum TLS Version has been set to $($this.ControlSettings.AppService.TLS_Version) for app service [$($this.ResourceName)]", $result);
		
			return $detailedLogs;
    }
}
