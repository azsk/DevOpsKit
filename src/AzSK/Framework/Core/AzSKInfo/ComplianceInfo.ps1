using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class ComplianceInfo: CommandBase
{    
	hidden [ComplianceMessageSummary[]] $ComplianceMessageSummary = @();
	hidden [ComplianceResult[]] $ComplianceScanResult = @();
	hidden [string] $SubscriptionId
	hidden [bool] $Full
	hidden $SVTConfig = @{}
	hidden $baselineControls = @();

	ComplianceInfo([string] $subscriptionId, [InvocationInfo] $invocationContext, [bool] $full): Base($subscriptionId, $invocationContext) 
    { 
		$this.SubscriptionId = $subscriptionId
	}

	hidden [void] GetComplianceScanData()
	{
		$ComplianceReportHelper = [ComplianceReportHelper]::new($this.SubscriptionContext.SubscriptionId);
		$StorageReportData =  $ComplianceReportHelper.GetLocalSubscriptionScanReport($this.SubscriptionContext.SubscriptionId)
		
		if($null -ne $StorageReportData -and $null -ne $StorageReportData.ScanDetails)
		{
			if(($StorageReportData.ScanDetails.SubscriptionScanResult | Measure-Object).Count -gt 0)
			{
				$StorageReportData.ScanDetails.SubscriptionScanResult | ForEach-Object {
					$subScanRes = $_
					$tmpCompRes = [ComplianceResult]::new()
					$tmpCompRes.FeatureName = "SubscriptionCore"
					$this.MapScanResultToComplianceResult($subScanRes, $tmpCompRes)
					$this.ComplianceScanResult += $tmpCompRes
				}
			}

			if(($StorageReportData.ScanDetails.Resources | Measure-Object).Count -gt 0)
			{
				$StorageReportData.ScanDetails.Resources | ForEach-Object {
					$resource = $_
					if($null -ne $resource -and ($resource.ResourceScanResult | Measure-Object).Count -gt 0)
					{
						$resource.ResourceScanResult | ForEach-Object {
							$resourceScanRes = $_
							$tmpCompRes = [ComplianceResult]::new()
							$tmpCompRes.FeatureName = $resource.FeatureName
							$tmpCompRes.ResourceGroupName = $resource.ResourceGroupName
							$tmpCompRes.ResourceName = $resource.ResourceName

							$this.MapScanResultToComplianceResult($resourceScanRes, $tmpCompRes)
							$this.ComplianceScanResult += $tmpCompRes
						}
					}
				}
			}
		}
	}
	
	MapScanResultToComplianceResult([LSRControlResultBase] $scannedControlResult, [ComplianceResult] $complianceResult)
	{
		$complianceResult.PSObject.Properties | ForEach-Object {
			$property = $_
			try
			{
				if([Helpers]::CheckMember($scannedControlResult,$property.Name) -or $property.Name -eq "VerificationResult" -or $property.Name -eq "AttestationStatus" -or $property.Name -eq "ControlSeverity" -or $property.Name -eq "ScanSource")
				{
					$propValue= $scannedControlResult | Select-Object -ExpandProperty $property.Name
					if([Constants]::AzSKDefaultDateTime -eq $propValue)
					{
						$_.Value = ""
					}
					else
					{
						$_.Value = $propValue
					}
				
				}	
			}
			catch
			{
				# need to add detail in catch block
				#$currentInstance.PublishException($_);
			}
		}
	}

	GetComplianceInfo()
	{
		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage("`r`nChecking if the subscription ["+ $this.SubscriptionId  +"] is setup for Continuous Assurance (CA) scanning...", [MessageType]::Default);
		$AutomationAccount=[Constants]::AutomationAccount
		$AzSKRGName=[ConfigurationManager]::GetAzSKConfigData().AzSKRGName

		$caAutomationAccount = Get-AzureRmAutomationAccount -Name  $AutomationAccount -ResourceGroupName $AzSKRGName -ErrorAction SilentlyContinue
		if($caAutomationAccount)
		{
			$this.PublishCustomMessage("`r`nCA setup found in the subscription ["+ $this.SubscriptionId +"].", [MessageType]::Default);
		}
		else
		{
			$this.PublishCustomMessage("`r`nCA setup not found in the subscription ["+ $this.SubscriptionId +"].", [MessageType]::Default);
			$this.PublishCustomMessage("`r`nCompliance data may be inaccurate when CA is not setup or is unhealthy.", [MessageType]::Default);
		}

		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage("`r`nFetching compliance info for subscription "+ $this.SubscriptionId  +" ...", [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);

		$this.GetComplianceScanData();	
		$this.ComputeCompliance();
		$this.GetComplianceSummary()
		$this.ExportComplianceResultCSV()
	}

	GetControlDetails() 
	{
		$resourcetypes = @() 

		$resourcetypes += ([SVTMapping]::SubscriptionMapping | Select-Object JsonFileName)
		$resourcetypes += ([SVTMapping]::Mapping | Sort-Object ResourceTypeName | Select-Object JsonFileName )
		
		# Fetch control Setting data
		$this.ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");

		# Filter control for baseline controls
		
		$this.baselineControls += $this.ControlSettings.BaselineControls.ResourceTypeControlIdMappingList | Select-Object ControlIds | ForEach-Object {  $_.ControlIds }
		$this.baselineControls += $this.ControlSettings.BaselineControls.SubscriptionControlIdList | ForEach-Object { $_ }

		$resourcetypes | ForEach-Object{
			$controls = [ConfigurationManager]::GetSVTConfig($_.JsonFileName); 

			# Filter control for enable only			
			$controls.Controls = ($controls.Controls | Where-Object { $_.Enabled -eq $true })

			if ([Helpers]::CheckMember($controls, "Controls") -and $controls.Controls.Count -gt 0)
			{
				$this.SVTConfig.Add($controls.FeatureName, @($controls.Controls))
			} 
		}
    }

	ComputeCompliance()
	{
		$this.ComplianceScanResult | ForEach-Object {
			# ToDo: Add condition to check whether control in grace
			if($_.FeatureName -eq "AzSKCfg" -or $_.VerificationResult -eq [VerificationResult]::Disabled)
			{
				$_.FinalResult = [VerificationResult]::Skipped
			}
			else
			{
				if($_.VerificationResult -eq [VerificationResult]::Passed)
				{
					$days = [System.DateTime]::UtcNow.Subtract($_.LastScannedOn).Days
					$allowedDays = [Constants]::ControlResultComplianceDays
					if($_.HasOwnerAccessTag)
					{
						$allowedDays = [Constants]::OwnerControlResultComplianceDays
					}
				
					if($days -ge $allowedDays)
					{
						$_.FinalResult = [VerificationResult]::Failed
					}
					else
					{
						$_.FinalResult = [VerificationResult]::Passed
					}
				}
				else
				{
					$_.FinalResult = [VerificationResult]::Failed
				}
			}
			
		}

		#Append resource inventory and missing controls
		$groupedResult = $this.ComplianceScanResult | Group-Object { $_.FeatureName, $_.ResourceName } 
		foreach($result in $groupedResult){
			

		}
	}

	GetComplianceSummary()
	{
		
		$totalCompliance = 0.0
		$baselineCompliance = 0.0
		$passControlCount = 0
		$failedControlCount = 0
		$baselinePassedControlCount = 0
		$baselineFailedControlCount = 0
		$attestedControlCount = 0
		$gracePeriodControlCount = 0

		if(($this.ComplianceScanResult |  Measure-Object).Count -gt 0)
		{
			$totalControlCount = ($this.ComplianceScanResult |  Measure-Object).Count
			$passControlCount = (($this.ComplianceScanResult | Where-Object { ($_.FinalResult -eq [VerificationResult]::Passed ) }) | Measure-Object).Count
			$failedControlCount = (($this.ComplianceScanResult | Where-Object { ($_.FinalResult -eq [VerificationResult]::Failed) }) | Measure-Object).Count
			$totalCompliance = (100 * $passControlCount)/($passControlCount + $failedControlCount)

			$baselineControlCount = (($this.ComplianceScanResult | Where-Object { $_.IsBaselineControl }) | Measure-Object).Count
			$baselinePassedControlCount = (($this.ComplianceScanResult | Where-Object { ($_.FinalResult -eq [VerificationResult]::Passed) -and $_.IsBaselineControl }) | Measure-Object).Count
			$baselineFailedControlCount = (($this.ComplianceScanResult | Where-Object { ($_.FinalResult -eq [VerificationResult]::Failed) -and $_.IsBaselineControl }) | Measure-Object).Count
			$baselineCompliance = (100 * $baselinePassedControlCount)/($baselinePassedControlCount + $baselineFailedControlCount)
			
			$attestedControlCount = (($this.ComplianceScanResult | Where-Object { $_.AttestationStatus -ne [AttestationStatus]::None}) | Measure-Object).Count
			$gracePeriodControlCount = (($this.ComplianceScanResult | Where-Object { $_.IsControlInGrace }) | Measure-Object).Count

			$ComplianceStats = @();
			
			$ComplianceStat = "" | Select-Object "ComplianceType", "Pass-%", "No. of Passed Controls", "No. of Failed Controls"
			$ComplianceStat.ComplianceType = "Baseline"
			$ComplianceStat."Pass-%"= [math]::Round($baselineCompliance,2)
			$ComplianceStat."No. of Passed Controls" = $baselinePassedControlCount
			$ComplianceStat."No. of Failed Controls" = $baselineFailedControlCount
			$ComplianceStats += $ComplianceStat

			$ComplianceStat = "" | Select-Object "ComplianceType", "Pass-%", "No. of Passed Controls", "No. of Failed Controls"
			$ComplianceStat.ComplianceType = "Full"
			$ComplianceStat."Pass-%"= [math]::Round($totalCompliance,2)
			$ComplianceStat."No. of Passed Controls" = $passControlCount
			$ComplianceStat."No. of Failed Controls" = $failedControlCount
			$ComplianceStats += $ComplianceStat

			$this.PublishCustomMessage(($ComplianceStats | Format-Table | Out-String), [MessageType]::Default)
			$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);
			$this.PublishCustomMessage("`r`nAttested control count:        "+ $attestedControlCount , [MessageType]::Default);
			$this.PublishCustomMessage("`r`nControl in grace period count: "+ $gracePeriodControlCount , [MessageType]::Default);

			$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
			$this.PublishCustomMessage("`r`n`r`n`r`nDisclaimer: Compliance summary/control counts may differ slightly from the central telemetry/dashboard due to various timing/sync lags.", [MessageType]::Default);
		}
	}

	GetControlsInGracePeriod()
	{
		$this.PublishCustomMessage("List of control in grace period", [MessageType]::Default);
	
	}

	ExportComplianceResultCSV()
	{
		$this.ComplianceScanResult | ForEach-Object {
			if($_.IsBaselineControl.ToLower() -eq "true")
			{
				$_.IsBaselineControl = "Yes"
			}
			if($_.IsControlInGrace.ToLower() -eq "true")
			{
				$_.IsControlInGrace = "Yes"
			}
			if($_.AttestationStatus.ToLower() -eq "none")
			{
				$_.AttestationStatus = ""
			}
			if($_.HasOwnerAccessTag.ToLower() -eq "true")
			{
				$_.HasOwnerAccessTag = "Yes"
			}
			
		}

		$objectToExport = $this.ComplianceScanResult
		if(-not $this.Full)
		{
			$objectToExport = $this.ComplianceScanResult | Select-Object "ControlId", "VerificationResult", "FeatureName", "ResourceGroupName", "ResourceName", "ChildResourceName", "IsBaselineControl", `
								"ControlSeverity", "AttestationStatus", "AttestedBy", "Justification", "IsControlInGrace", "ScanSource", "ScannedBy", "ScannerModuleName", "ScannerVersion"
		}

		$controlCSV = New-Object -TypeName WriteCSVData
		$controlCSV.FileName = 'Compliance Details_' + $this.RunIdentifier
		$controlCSV.FileExtension = 'csv'
		$controlCSV.FolderPath = ''
		$controlCSV.MessageData = $objectToExport

		$this.PublishAzSKRootEvent([AzSKRootEvent]::WriteCSV, $controlCSV);
	}
	
	AddComplianceMessage([string] $ComplianceType, [string] $ComplianceCount, [string] $ComplianceComment)
	{
		$ComplianceMessage = New-Object -TypeName ComplianceMessageSummary
		$ComplianceMessage.ComplianceType = $ComplianceType
		$ComplianceMessage.ComplianceCount = $ComplianceCount
		$this.ComplianceMessageSummary += $ComplianceMessage
	}
}



class ComplianceMessageSummary
{
	[string] $ComplianceType = "" 
	[string] $ComplianceCount = ""
	#[string] $ComplianceComment = ""
}

class ComplianceResult
{
	[string] $ControlId = ""
	[VerificationResult] $VerificationResult = [VerificationResult]::Manual
	[string] $FeatureName = ""
	[string] $ResourceGroupName = ""
	[string] $ResourceName = ""
	[string] $ChildResourceName = ""
	[string] $IsBaselineControl = ""
	[ControlSeverity] $ControlSeverity = [ControlSeverity]::High

	[string] $AttestationCounter = ""
	[string] $AttestationStatus = ""
	[string] $AttestedBy = ""
	[string] $AttestedDate = ""
	[string] $Justification = ""

	[String] $UserComments = ""

	[string] $LastScannedOn = ""
	[string] $FirstScannedOn = ""
	[string] $FirstFailedOn = ""
	[string] $FirstAttestedOn = ""
	[string] $LastResultTransitionOn = ""
	[string] $ScanSource = ""
	[string] $ScannedBy = ""
	[string] $ScannerModuleName = ""
	[string] $ScannerVersion = ""
	[string] $IsControlInGrace = ""
	[string] $HasOwnerAccessTag = ""
	[VerificationResult] $FinalResult = [VerificationResult]::NotScanned
}