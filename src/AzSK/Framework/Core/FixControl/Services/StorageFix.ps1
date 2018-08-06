using namespace Microsoft.Azure.Commands.Sql.Auditing.Model
using namespace Microsoft.Azure.Commands.Sql.ServerUpgrade.Model
using namespace Microsoft.Azure.Commands.Sql.TransparentDataEncryption.Model
using namespace Microsoft.Azure.Commands.Sql.ThreatDetection.Model

Set-StrictMode -Version Latest 

class StorageFix: FixServicesBase
{
	[PSObject] $ResourceObject = $null;

    StorageFix([string] $subscriptionId, [ResourceConfig] $resourceConfig, [string] $resourceGroupName): 
        Base($subscriptionId, $resourceConfig, $resourceGroupName) 
    { }

	[PSObject] FetchStorageObject()
	{
		if(-not $this.ResourceObject)
		{
			$this.ResourceObject = Get-AzureRmStorageAccount -Name $this.ResourceName -ResourceGroupName $this.ResourceGroupName
		}

		return $this.ResourceObject;
	}

	[MessageData[]] SetSku([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$skuName = $parameters.SkuName;
		$detailedLogs += [MessageData]::new("Setting up the Sku [$skuName] for storage [$($this.ResourceName)]...");
		Set-AzureRmStorageAccount -Name $this.ResourceName -ResourceGroupName $this.ResourceGroupName -SkuName $skuName
		$detailedLogs += [MessageData]::new("Sku setup completed for storage [$($this.ResourceName)]");
		return $detailedLogs;
    }

	[MessageData[]] EnableHttpsTrafficOnly([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$detailedLogs += [MessageData]::new("Enabling 'HTTPS traffic only' on storage [$($this.ResourceName)]...");
		Set-AzureRmStorageAccount -Name $this.ResourceName -ResourceGroupName $this.ResourceGroupName -EnableHttpsTrafficOnly $true
		$detailedLogs += [MessageData]::new("'HTTPS traffic only' is enabled on storage [$($this.ResourceName)]");
		return $detailedLogs;
    }

	[MessageData[]] SetupAlertsForAuthNRequest([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$detailedLogs += [MessageData]::new("Setting up alerts for anonymous authentication requests on storage [$($this.ResourceName)]...");
		$storageObject = $this.FetchStorageObject();
		if($storageObject)
		{
			$serviceMapping = $this.ControlSettings.StorageKindMapping | Where-Object { $_.Kind -eq $storageObject.Kind } | Select-Object -First 1;
        
			if($serviceMapping)
			{
				$emailAction = New-AzureRmAlertRuleEmail -SendToServiceOwner -WarningAction SilentlyContinue
				$serviceMapping.Services | 
				ForEach-Object {
					$targetId = $storageObject.Id + "/services/" + $_

					$alertName = $this.ResourceName + $_ + "alert"
					Add-AzureRmMetricAlertRule -Location $storageObject.Location `
						-MetricName AnonymousSuccess `
						-Name $alertName `
						-Operator GreaterThan `
						-ResourceGroup $storageObject.ResourceGroupName `
						-TargetResourceId $targetId `
						-Threshold 0 -TimeAggregationOperator Total -WindowSize 01:00:00  `
						-Action $emailAction `
						-WarningAction SilentlyContinue `
						-ErrorAction Stop
				}
			}

			$detailedLogs += [MessageData]::new("Alerts for anonymous authentication requests have been set up on storage [$($this.ResourceName)]");
		}
		else
		{
			$detailedLogs += [MessageData]::new("Unable to fetch storage account [$($this.ResourceName)]");
		}

		return $detailedLogs;
    }

	[MessageData[]] EnableAuditOnAuthN([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$detailedLogs += [MessageData]::new("Enabling audit on authentication requests on storage [$($this.ResourceName)]...");
		$storageObject = $this.FetchStorageObject();
		if($storageObject)
		{
			$serviceMapping = $this.ControlSettings.StorageKindMapping | Where-Object { $_.Kind -eq $storageObject.Kind } | Select-Object -First 1;
        
			if($serviceMapping)
			{
				#Check Metrics diagnostics log property
				$serviceMapping.DiagnosticsLogServices | 
				ForEach-Object {
					Set-AzureStorageServiceLoggingProperty `
						-ServiceType $_ `
						-LoggingOperations All `
						-Context $storageObject.Context `
						-RetentionDays $this.ControlSettings.Diagnostics_RetentionPeriod_Min `
						-ErrorAction Stop
				}

				#Check Metrics logging property
				$serviceMapping.Services | 
				ForEach-Object {
					Set-AzureStorageServiceMetricsProperty `
						-MetricsType Hour `
						-ServiceType $_ `
						-Context $storageObject.Context `
						-MetricsLevel ServiceAndApi `
						-RetentionDays $this.ControlSettings.Diagnostics_RetentionPeriod_Min `
						-ErrorAction Stop
				}
			}

			$detailedLogs += [MessageData]::new("Audit has been enabled for authentication requests on storage [$($this.ResourceName)]");
		}
		else
		{
			$detailedLogs += [MessageData]::new("Unable to fetch storage account [$($this.ResourceName)]");
		}

		return $detailedLogs;
    }

	[MessageData[]] DisableAnonymousAccessOnContainers([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$detailedLogs += [MessageData]::new("Disabling anonymous access on all containers on storage [$($this.ResourceName)]...");
		$storageObject = $this.FetchStorageObject();
		if($storageObject)
		{
			$allContainers = @();
			$allContainers += Get-AzureStorageContainer -Context $storageObject.Context -ErrorAction Stop

			if($allContainers.Count -ne 0)
			{
				$allContainers | ForEach-Object {
					Set-AzureStorageContainerAcl -Name $_.Name -Permission Off -Context $storageObject.Context
				};
				$detailedLogs += [MessageData]::new("Anonymous access has been disabled on all containers on storage [$($this.ResourceName)]");
			}
			else
			{
				$detailedLogs += [MessageData]::new("There are no containers on storage account which have anonymous access enabled [$($this.ResourceName)]");
			}			
		}
		else
		{
			$detailedLogs += [MessageData]::new("Unable to fetch storage account [$($this.ResourceName)]");
		}

		return $detailedLogs;
    }

}
