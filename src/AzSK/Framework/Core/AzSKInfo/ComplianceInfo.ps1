using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class ComplianceInfo: CommandBase
{    
	hidden [ComplianceMessageSummary[]] $ComplianceMessageSummary = @();
	hidden [ComplianceResult[]] $ComplianceScanResult = @();
	hidden [string] $SubscriptionId
	hidden [bool] $Full
	hidden $baselineControls = @();
	hidden [PSObject] $ControlSettings
	hidden [PSObject] $EmptyResource = @();
	 
	ComplianceInfo([string] $subscriptionId, [InvocationInfo] $invocationContext, [bool] $full): Base($subscriptionId, $invocationContext) 
    { 
		$this.SubscriptionId = $subscriptionId
		$this.Full = $full
	}

	hidden [void] GetComplianceScanData()
	{
		$ComplianceRptHelper = [ComplianceReportHelper]::new($this.SubscriptionContext, $this.GetCurrentModuleVersion());
		if($ComplianceRptHelper.HaveRequiredPermissions())
		{
			$ComplianceReportData =  $ComplianceRptHelper.GetSubscriptionComplianceReport();
			$this.ComplianceScanResult = @();
			if(($ComplianceReportData | Measure-Object).Count -gt 0)
			{
				$ComplianceReportData | ForEach-Object{				
					$this.ComplianceScanResult += [ComplianceResult]::new($_);
				}
			}
		}			
	}
	
	hidden [void] GetComplianceInfo()
	{
		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		
		$azskConfig = [ConfigurationManager]::GetAzSKConfigData();	
		$settingStoreComplianceSummaryInUserSubscriptions = [ConfigurationManager]::GetAzSKSettings().StoreComplianceSummaryInUserSubscriptions;
		#return if feature is turned off at server config
		if(-not $azskConfig.StoreComplianceSummaryInUserSubscriptions -and -not $settingStoreComplianceSummaryInUserSubscriptions)		
		{
			$this.PublishCustomMessage("NOTE: This feature is currently disabled in your environment. Please contact the cloud security team for your org. ", [MessageType]::Warning);	
			return;
		}		

		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage("`r`nFetching compliance info for subscription ["+ $this.SubscriptionId  +"] ...", [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);

		$this.GetComplianceScanData();
		if(($this.ComplianceScanResult | Measure-Object).Count -le 0)
		{
			$this.PublishCustomMessage("No previously persisted compliance data found in the subscription ["+ $this.SubscriptionId +"]`nCompliance data will get persisted as you perform scans (or when scans happen from CA/CICD).", [MessageType]::Default);
			return;
		}			
		#$this.GetControlDetails();
		$this.ComputeCompliance();
		$this.GetComplianceSummary()
		$this.ExportComplianceResultCSV()
	}


	hidden [void] ComputeCompliance()
	{
		$this.ComplianceScanResult | ForEach-Object {
			# ToDo: Add condition to check whether control in grace
			if($_.FeatureName -eq "AzSKCfg" -or $_.VerificationResult -eq [VerificationResult]::Disabled -or $_.VerificationResult -eq [VerificationResult]::Error)
			{
				$_.EffectiveResult = [VerificationResult]::Skipped
			}
			else
			{
				if($_.VerificationResult -eq [VerificationResult]::Passed)
				{
					$_.EffectiveResult = ([VerificationResult]::Passed).ToString();
					
					$lastScannedDate = [datetime] $_.LastScannedOn
					$days = [DateTime]::UtcNow.Subtract($lastScannedDate).Days

					[int]$allowedDays = [Constants]::ControlResultComplianceInDays
					
					if(($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings,"ResultComplianceInDays.DefaultControls"))
					{
						[int32]::TryParse($this.ControlSettings.ResultComplianceInDays.DefaultControls, [ref]$allowedDays)
					}
					if($_.HasOwnerAccessTag)
					{
						if(($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings,"ResultComplianceInDays.OwnerAccessControls"))
						{
							[int32]::TryParse($this.ControlSettings.ResultComplianceInDays.OwnerAccessControls, [ref]$allowedDays)
						}
					}

					#revert back to actual result if control result is stale 
					if($days -ge $allowedDays)
					{
						$_.EffectiveResult = ([VerificationResult]::Failed).ToString();
					}					
				}
				else
				{
					$_.EffectiveResult = ([VerificationResult]::Failed).ToString();
				}
			}			
		}	
	}

	hidden [void] GetComplianceSummary()
	{
		$totalCompliance = 0.0
		$baselineCompliance = 0.0
		$passControlCount = 0
		$failedControlCount = 0
		$baselinePassedControlCount = 0
		$baselineFailedControlCount = 0
		$attestedControlCount = 0
		$gracePeriodControlCount = 0
		$totalControlCount = 0
		$baselineControlCount = 0
		$attestedControlCount = 0
		$gracePeriodControlCount = 0

		if(($this.ComplianceScanResult |  Measure-Object).Count -gt 0)
		{
			$this.ComplianceScanResult | ForEach-Object {
				$result = $_
				#ideally every proper control should fall under effective result in passed/failed/skipped
				if($result.EffectiveResult -eq [VerificationResult]::Passed -or $result.EffectiveResult -eq [VerificationResult]::Failed)
				{
					# total count has been kept inside to exclude not-scanned and skipped controls
					$totalControlCount++
										
					if($result.EffectiveResult -eq [VerificationResult]::Passed)
					{
						$passControlCount++
						#baseline controls condition shouldnot increment if it wont fall in passed/ failed state
						if($result.IsBaselineControl -eq "True")
						{
							$baselineControlCount++
							$baselinePassedControlCount++
						}
					}
					elseif($result.EffectiveResult -eq [VerificationResult]::Failed)
					{
						$failedControlCount++
						if($result.IsBaselineControl -eq "True")
						{
							$baselineControlCount++
							$baselineFailedControlCount++
						}
					}

					if(-not [string]::IsNullOrEmpty($result.AttestationStatus) -and ($result.AttestationStatus -ne [AttestationStatus]::None))
					{
						$attestedControlCount++
					}
					if($result.IsControlInGrace -eq "True")
					{
						$gracePeriodControlCount++
					}
				}
			}
			
			if(($passControlCount + $failedControlCount) -ne 0)
			{
				$totalCompliance = (100 * $passControlCount)/($passControlCount + $failedControlCount)
			}
			else {
				$totalCompliance = 0;
			}
			
			
			$ComplianceStats = @();
			
			if(($baselinePassedControlCount + $baselineFailedControlCount) -ne 0)
			{
				$baselineCompliance = (100 * $baselinePassedControlCount)/($baselinePassedControlCount + $baselineFailedControlCount)
				$ComplianceStat = "" | Select-Object "ComplianceType", "Pass-%", "No. of Passed Controls", "No. of Failed Controls"
				$ComplianceStat.ComplianceType = "Baseline"
				$ComplianceStat."Pass-%"= [math]::Round($baselineCompliance,2)
				$ComplianceStat."No. of Passed Controls" = $baselinePassedControlCount
				$ComplianceStat."No. of Failed Controls" = $baselineFailedControlCount
				$ComplianceStats += $ComplianceStat
			}					

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

	hidden [void] GetControlsInGracePeriod()
	{
		$this.PublishCustomMessage("List of control in grace period", [MessageType]::Default);	
	}

	hidden [void] ExportComplianceResultCSV()
	{
		$this.ComplianceScanResult | ForEach-Object {
			if($_.IsBaselineControl -eq "True")
			{
				$_.IsBaselineControl = "Yes"
			}
			else {
				$_.IsBaselineControl = "No"
			}

			if($_.IsControlInGrace -eq "True")
			{
				$_.IsControlInGrace = "Yes"
			}
			else {
				$_.IsControlInGrace = "No"
			}
			if($_.AttestationStatus.ToLower() -eq "none")
			{
				$_.AttestationStatus = ""
			}
			if($_.HasOwnerAccessTag -eq "True")
			{
				$_.HasOwnerAccessTag = "Yes"
			}
			else {
				$_.HasOwnerAccessTag = "No"
			}			
		}

		$objectToExport = $this.ComplianceScanResult
		if(-not $this.Full)
		{
			$objectToExport = $this.ComplianceScanResult | Select-Object "ControlId", "VerificationResult", "ActualVerificationResult", "FeatureName", "ResourceGroupName", "ResourceName", "ChildResourceName", "IsBaselineControl", `
								"ControlSeverity", "AttestationStatus", "AttestedBy", "Justification", "LastScannedOn", "ScanSource", "ScannedBy", "ScannerModuleName", "ScannerVersion"
		}

		$controlCSV = New-Object -TypeName WriteCSVData
		$controlCSV.FileName = 'ComplianceDetails_' + $this.RunIdentifier
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
	[string] $VerificationResult = ([VerificationResult]::Manual).ToString();
	[string] $ActualVerificationResult= ([VerificationResult]::Manual).ToString();
	[string] $FeatureName = ""
	[string] $ResourceGroupName = ""
	[string] $ResourceName = ""
	[string] $ChildResourceName = ""
	[string] $IsBaselineControl = ""
	[string] $ControlSeverity = ([ControlSeverity]::High).ToString();

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
	[string] $ResourceId = ""
	[string] $EffectiveResult = ([VerificationResult]::NotScanned).ToString();

	ComplianceResult([ComplianceStateTableEntity] $persistedEntity)
	{
		$this.ControlId = $persistedEntity.ControlId;
		$this.VerificationResult = $persistedEntity.VerificationResult;
		$this.ActualVerificationResult = $persistedEntity.ActualVerificationResult;
		$this.FeatureName = $persistedEntity.FeatureName;
		$this.ResourceGroupName = $persistedEntity.ResourceGroupName;
		$this.ResourceName = $persistedEntity.ResourceName;
		$this.ChildResourceName = $persistedEntity.ChildResourceName;
		$this.IsBaselineControl = $persistedEntity.IsBaselineControl;
		$this.ControlSeverity = $persistedEntity.ControlSeverity;
		$this.AttestationCounter = $persistedEntity.AttestationCounter;
		$this.AttestationStatus = $persistedEntity.AttestationStatus;
		$this.AttestedBy = $persistedEntity.AttestedBy;
		$this.AttestedDate = $persistedEntity.AttestedDate;
		$this.Justification = $persistedEntity.Justification;
		$this.UserComments = $persistedEntity.UserComments;
		$this.LastScannedOn = $persistedEntity.LastScannedOn;
		$this.FirstScannedOn = $persistedEntity.FirstScannedOn;
		$this.FirstFailedOn = $persistedEntity.FirstFailedOn;
		$this.FirstAttestedOn = $persistedEntity.FirstAttestedOn;
		$this.LastResultTransitionOn = $persistedEntity.LastResultTransitionOn;
		$this.ScanSource = $persistedEntity.ScanSource;
		$this.ScannedBy = $persistedEntity.ScannedBy;
		$this.ScannerModuleName = $persistedEntity.ScannerModuleName;
		$this.ScannerVersion = $persistedEntity.ScannerVersion;
		#this.$IsControlInGrace = $persistedEntity.
		$this.HasOwnerAccessTag = $persistedEntity.HasOwnerAccessTag;
		$this.ResourceId = $persistedEntity.ResourceId;
		#this.$EffectiveResult = if($persistedEntity.VerificationResult;
		
	}

	ComplianceResult($featureName, $resourceId, $resourceGroupName, $resourceName, $controlId, $verificationResult, $isBaselineControl, $controlSeverity, $effectiveResult)
	{
		$this.ControlId = $controlId
		$this.FeatureName = $featureName
		$this.VerificationResult = $verificationResult
		$this.ResourceGroupName = $resourceGroupName
		$this.ResourceName = $resourceName
		$this.IsBaselineControl = $isBaselineControl
		$this.ControlSeverity = $controlSeverity
		$this.ResourceId = $resourceId
		$this.EffectiveResult = $effectiveResult
	}
}