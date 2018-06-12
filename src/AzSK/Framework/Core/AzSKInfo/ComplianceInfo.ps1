using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class ComplianceInfo: CommandBase
{    
	hidden [string] $ResourceTypeName
	hidden [bool] $BaslineControls
	hidden [PSObject] $ControlSettings
	hidden [string] $ControlSeverity
	hidden [string] $ControlIdContains
	hidden [string[]] $ControlIds = @();
	hidden [ComplianceMessageSummary[]] $ComplianceMessageSummary = @();
	hidden [ComplianceResult[]] $ComplianceScanResult = @();
	hidden [string] $SubscriptionId
	hidden [bool] $Full


	ComplianceInfo([string] $subscriptionId, [InvocationInfo] $invocationContext, [string] $resourceTypeName, [string] $resourceType, [string] $controlIds, [bool] $baslineControls,
					[string] $controlSeverity, [string] $controlIdContains, [bool] $full): 
        Base($subscriptionId, $invocationContext) 
    { 
		
		
		$this.ResourceTypeName = $resourceTypeName;
		$this.BaslineControls = $baslineControls;
		$this.ControlSeverity = $controlSeverity;
		$this.ControlIdContains = $controlIdContains
		$this.SubscriptionId = $subscriptionId

		if(-not [string]::IsNullOrEmpty($controlIds))
        {
			$this.ControlIds += $this.ConvertToStringArray($controlIds);
        }
	}

	hidden [void] GetComplianceScanData()
	{
		$StorageReportHelper = [StorageReportHelper]::new();
		$StorageReportHelper.Initialize($false);
		
		if($StorageReportHelper.HasStorageReportReadAccessPermissions())
		{
			$StorageReportData =  $StorageReportHelper.GetLocalSubscriptionScanReport($this.SubscriptionContext.SubscriptionId)
			if([Helpers]::CheckMember($StorageReportData,"ScanDetails"))
			{
				if([Helpers]::CheckMember($StorageReportData.ScanDetails,"SubscriptionScanResult") -and ($StorageReportData.ScanDetails.SubscriptionScanResult | Measure-Object).Count -gt 0)
				{
					$StorageReportData.ScanDetails.SubscriptionScanResult | ForEach-Object {
						$subScanRes = $_
						$tmpCompRes = [ComplianceResult]::new()
						$tmpCompRes.FeatureName = "SubscriptionCore"
						$this.MapScanResultToComplianceResult($subScanRes, $tmpCompRes)
						$this.ComplianceScanResult += $tmpCompRes
					}
				}

				if([Helpers]::CheckMember($StorageReportData.ScanDetails,"Resources") -and ($StorageReportData.ScanDetails.Resources | Measure-Object).Count -gt 0)
				{
					$StorageReportData.ScanDetails.Resources | ForEach-Object {
						$resource = $_
						if([Helpers]::CheckMember($resource,"ResourceScanResult") -and ($resource.ResourceScanResult | Measure-Object).Count -gt 0)
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
		$this.PublishCustomMessage("`r`nChecking presence of CA in subscription "+ $this.SubscriptionId  +" ...", [MessageType]::Default);
		$AutomationAccount=[Constants]::AutomationAccount
		$AzSKRGName=[ConfigurationManager]::GetAzSKConfigData().AzSKRGName

		$caAutomationAccount = Get-AzureRmAutomationAccount -Name  $AutomationAccount -ResourceGroupName $AzSKRGName -ErrorAction SilentlyContinue
		if($caAutomationAccount)
		{
			$this.PublishCustomMessage("`r`nCA automation account is present in subscription "+ $this.SubscriptionId  +".", [MessageType]::Default);
		}
		else
		{
			$this.PublishCustomMessage("`r`nCA automation account is not present in subscription "+ $this.SubscriptionId  +". Compliance count may differ from dashboard.", [MessageType]::Default);
		}

		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage("`r`nFetching compliance info for subscription "+ $this.SubscriptionId  +" ...", [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);

		$this.GetComplianceScanData();	
		$this.GetComplianceSummary()
		$this.ExportComplianceResultCSV()
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
			$passControlCount = (($this.ComplianceScanResult | Where-Object { ($_.VerificationResult -eq [VerificationResult]::Passed -or $_.IsControlInGrace) -and ($_.FeatureName -ne "AzSKCfg") }) | Measure-Object).Count
			$failedControlCount = (($this.ComplianceScanResult | Where-Object { ($_.VerificationResult -ne [VerificationResult]::Passed) -and (-not $_.IsControlInGrace) -and ($_.FeatureName -ne "AzSKCfg") }) | Measure-Object).Count
			$totalCompliance = (100 * $passControlCount)/($passControlCount + $failedControlCount)

			$baselineControlCount = (($this.ComplianceScanResult | Where-Object { $_.IsBaselineControl }) | Measure-Object).Count
			$baselinePassedControlCount = (($this.ComplianceScanResult | Where-Object { ($_.VerificationResult -eq [VerificationResult]::Passed -or $_.VerificationResult -eq [VerificationResult]::Disabled -or $_.IsControlInGrace) -and $_.IsBaselineControl -and ($_.FeatureName -ne "AzSKCfg") }) | Measure-Object).Count
			$baselineFailedControlCount = (($this.ComplianceScanResult | Where-Object { ($_.VerificationResult -ne [VerificationResult]::Passed) -and (-not $_.IsControlInGrace) -and $_.IsBaselineControl -and ($_.FeatureName -ne "AzSKCfg") }) | Measure-Object).Count
			$baselineCompliance = (100 * $baselinePassedControlCount)/($baselinePassedControlCount + $baselineFailedControlCount)
			
			$attestedControlCount = (($this.ComplianceScanResult | Where-Object { $_.AttestationStatus -ne [AttestationStatus]::None}) | Measure-Object).Count
			$gracePeriodControlCount = (($this.ComplianceScanResult | Where-Object { $_.IsControlInGrace }) | Measure-Object).Count

			$ComplianceStats = @();
			
			$ComplianceStat = "" | Select-Object "ComplianceType", "Total", "Passed", "Failed"
			$ComplianceStat.ComplianceType = "Baseline"
			$ComplianceStat.Total= [math]::Round($baselineCompliance,2)
			$ComplianceStat.Passed = $baselinePassedControlCount
			$ComplianceStat.Failed = $baselineFailedControlCount
			$ComplianceStats += $ComplianceStat

			$ComplianceStat = "" | Select-Object "ComplianceType", "Total", "Passed", "Failed"
			$ComplianceStat.ComplianceType = "Full"
			$ComplianceStat.Total= [math]::Round($totalCompliance,2)
			$ComplianceStat.Passed = $passControlCount
			$ComplianceStat.Failed = $failedControlCount
			$ComplianceStats += $ComplianceStat

			$this.PublishCustomMessage(($ComplianceStats | Format-Table | Out-String), [MessageType]::Default)
			$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);
			$this.PublishCustomMessage("`r`nAttested control count:        "+ $attestedControlCount , [MessageType]::Default);
			$this.PublishCustomMessage("`r`nControl in grace period count: "+ $gracePeriodControlCount , [MessageType]::Default);

			$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
			$this.PublishCustomMessage("`r`n`r`n`r`nDisclaimer: Compliance count can be differ from dashboard. Please refer dashboard for final compliance.", [MessageType]::Default);
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
}