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
			$this.ResourceObject = Get-AzStorageAccount -Name $this.ResourceName -ResourceGroupName $this.ResourceGroupName
		}

		return $this.ResourceObject;
	}

	[MessageData[]] EnableHttpsTrafficOnly([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$detailedLogs += [MessageData]::new("Enabling 'HTTPS traffic only' on storage [$($this.ResourceName)]...");
		Set-AzStorageAccount -Name $this.ResourceName -ResourceGroupName $this.ResourceGroupName -EnableHttpsTrafficOnly $true
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
			$actionGrpId = ""

			if($serviceMapping)
			{
				$targetId = $storageObject.Id

				Write-Host "Please enter alert name: " -ForegroundColor Cyan
				$alertName = Read-Host "Alert Name"
				$alertName = $alertName.Trim();
				
				Write-Host "Please provide action group id: `n[0]: Create New action group`n[1]: Use existing action group" -ForegroundColor Cyan
				$userChoice = Read-Host "User Choice"
				$userChoice = $userChoice.Trim();
				
				if([string]::IsNullOrWhiteSpace($userChoice) -or ($userChoice.Trim() -ne '0' -and $userChoice.Trim() -ne '1'))
				{
					Write-Host "Invalid option." -ForegroundColor Yellow
				}
				if ($userChoice.Trim() -eq '0' -or $userChoice.Trim() -eq '1')
				{
					if($userChoice.Trim() -eq '1')
					{
						Write-Host "Existing action group name for this resource group: " -ForegroundColor Cyan
						$actionGrpName = Read-Host "Action Group Name"
						$actionGrpName = $actionGrpName.Trim();
						$actionGrp = Get-AzActionGroup -Name $actionGrpName -ResourceGroupName $storageObject.ResourceGroupName
						$actionGrpId = New-AzActionGroup -ActionGroupId $actionGrp.Id
					}
					elseif($userChoice.Trim() -eq '0')
					{
						$email = New-AzActionGroupReceiver -EmailReceiver
						$actionGrp = Set-AzActionGroup -Receiver $email -ResourceGroupName $storageObject.ResourceGroupName
						$actionGrpId = New-AzActionGroup -ActionGroupId $actionGrp.Id
					}

					$dimension = New-AzMetricAlertRuleV2DimensionSelection -DimensionName "Authentication" -ValuesToInclude "Anonymous"
					$condition = New-AzMetricAlertRuleV2Criteria -MetricName "Transactions" -DimensionSelection $dimension -TimeAggregation Total -Operator GreaterThan -Threshold 0 -MetricNamespace "Microsoft.Storage/storageAccounts"
					
					Add-AzMetricAlertRuleV2  -ActionGroup $actionGrpId `
						-Condition $condition `
						-Name $alertName `
						-ResourceGroupName $storageObject.ResourceGroupName `
						-WindowSize 01:00:00 `
						-Frequency 01:00:00 `
						-TargetResourceId $targetId `
						-Severity 3 `
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
					Set-AzStorageServiceLoggingProperty `
						-ServiceType $_ `
						-LoggingOperations All `
						-Context $storageObject.Context `
						-RetentionDays $this.ControlSettings.Diagnostics_RetentionPeriod_Min `
						-ErrorAction Stop
				}

				#Check Metrics logging property
				$serviceMapping.Services | 
				ForEach-Object {
					Set-AzStorageServiceMetricsProperty `
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
			$allContainers += Get-AzStorageContainer -Context $storageObject.Context -ErrorAction Stop

			if($allContainers.Count -ne 0)
			{
				$allContainers | ForEach-Object {
					Set-AzStorageContainerAcl -Name $_.Name -Permission Off -Context $storageObject.Context
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
