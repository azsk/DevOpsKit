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


	ComplianceInfo([string] $subscriptionId, [InvocationInfo] $invocationContext, [string] $resourceTypeName, [string] $resourceType, [string] $controlIds, [bool] $baslineControls,
					[string] $controlSeverity, [string] $controlIdContains): 
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
			if([Helpers]::CheckMember($scannedControlResult,$property.Name) -or $property.Name -eq "VerificationResult" -or $property.Name -eq "AttestationStatus" -or $property.Name -eq "ControlSeverity" )
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
	}

	GetComplianceInfo()
	{
		$this.PublishCustomMessage("`r`nFetching compliance info for subscription "+ $this.SubscriptionId  +" ...", [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);

		$this.GetComplianceScanData();	

		$resourcetypes = @() 
		$SVTConfig = @{} 
		$allControls = @()
		$controlSummary = @()

		# Filter Control for Resource Type / Resource Type Name
		if([string]::IsNullOrWhiteSpace($this.ResourceTypeName))
		{
			$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
			$this.PublishCustomMessage([Constants]::DefaultControlInfoCmdMsg, [MessageType]::Default);
			$this.DoNotOpenOutputFolder = $true;
			return;
		}

		$resourcetypes += ([SVTMapping]::SubscriptionMapping | Select-Object JsonFileName)
		if($this.ResourceTypeName -ne [ResourceTypeName]::All)
		{
			$resourcetypes += ([SVTMapping]::Mapping |
					Where-Object { $_.ResourceTypeName -eq $this.ResourceTypeName } | Select-Object JsonFileName)
		}
		else
		{
			$resourcetypes += ([SVTMapping]::Mapping | Sort-Object ResourceTypeName | Select-Object JsonFileName )
		}
		
		# Fetch control Setting data
		$this.ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");

		# Filter control for baseline controls
		$baselineControls = @();
		$baselineControls += $this.ControlSettings.BaselineControls.ResourceTypeControlIdMappingList | Select-Object ControlIds | ForEach-Object {  $_.ControlIds }
		$baselineControls += $this.ControlSettings.BaselineControls.SubscriptionControlIdList | ForEach-Object { $_ }
		if($this.BaslineControls)
		{
			$this.ControlIds = $baselineControls
		}

		#$resourcetypes | ForEach-Object{
		#			$controls = [ConfigurationManager]::GetSVTConfig($_.JsonFileName); 

		#			# Filter control for enable only			
		#			$controls.Controls = ($controls.Controls | Where-Object { $_.Enabled -eq $true })

		#			# Filter control for ControlIds
		#			if ([Helpers]::CheckMember($controls, "Controls") -and $this.ControlIds.Count -gt 0) 
		#			{
		#				$controls.Controls = ($controls.Controls | Where-Object { $this.ControlIds -contains $_.ControlId })
		#			}

		#			# Filter control for ControlId Contains
		#			if ([Helpers]::CheckMember($controls, "Controls") -and (-not [string]::IsNullOrEmpty($this.ControlIdContains))) 
		#			{
		#				$controls.Controls = ($controls.Controls | Where-Object { $_.ControlId -Match $this.ControlIdContains })
		#			}

		#			# Filter control for ControlSeverity
		#			if ([Helpers]::CheckMember($controls, "Controls") -and (-not [string]::IsNullOrEmpty($this.ControlSeverity))) 
		#			{
		#				$controls.Controls = ($controls.Controls | Where-Object { $this.ControlSeverity -eq $_.ControlSeverity })
		#			}

		#			if ([Helpers]::CheckMember($controls, "Controls") -and $controls.Controls.Count -gt 0)
		#			{
		#				$SVTConfig.Add($controls.FeatureName, @($controls.Controls))
		#			} 
  #              }
	
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
			$passControlCount = (($this.ComplianceScanResult | Where-Object { $_.VerificationResult -eq [VerificationResult]::Passed -or $_.VerificationResult -eq [VerificationResult]::Disabled -or $_.IsControlInGrace }) | Measure-Object).Count
			$failedControlCount = $totalControlCount - $passControlCount
			$totalCompliance = (100 * $passControlCount)/$totalControlCount

			 $baselineControlCount = (($this.ComplianceScanResult | Where-Object { $_.IsBaselineControl }) | Measure-Object).Count
			 $baselinePassedControlCount = (($this.ComplianceScanResult | Where-Object { ($_.VerificationResult -eq [VerificationResult]::Passed -or $_.VerificationResult -eq [VerificationResult]::Disabled -or $_.IsControlInGrace) -and $_.IsBaselineControl }) | Measure-Object).Count
			 $baselineFailedControlCount = $baselineControlCount - $baselinePassedControlCount
			 $baselineCompliance = (100 * $baselinePassedControlCount)/$baselineControlCount
			
			$attestedControlCount = (($this.ComplianceScanResult | Where-Object { $_.AttestationStatus -ne [AttestationStatus]::None}) | Measure-Object).Count
			$gracePeriodControlCount = (($this.ComplianceScanResult | Where-Object { $_.IsControlInGrace }) | Measure-Object).Count
		}
		
		
		$comment = ""
		$this.AddComplianceMessage("Total compliance:", [math]::Round($totalCompliance,2) , $comment)
		$this.AddComplianceMessage("Pass control count:", $passControlCount, $comment);
		$this.AddComplianceMessage("Failed control count:", $failedControlCount, $comment);
		$this.AddComplianceMessage("Baseline compliance:",[math]::Round($baselineCompliance,2), $comment);
		$this.AddComplianceMessage("Baseline pass control count:", $baselinePassedControlCount, $comment);
		$this.AddComplianceMessage("Baseline failed control count:", $baselineFailedControlCount, $comment);
		$this.AddComplianceMessage("Attested control count: ", $attestedControlCount, $comment);
		$this.AddComplianceMessage("control in grace period count: ", $gracePeriodControlCount, $comment);

		$this.PublishCustomMessage(($this.ComplianceMessageSummary | Format-Table | Out-String), [MessageType]::Default)
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
		$controlCSV = New-Object -TypeName WriteCSVData
		$controlCSV.FileName = 'Compliance Details'
		$controlCSV.FileExtension = 'csv'
		$controlCSV.FolderPath = ''
		$controlCSV.MessageData = $this.ComplianceScanResult

		$this.PublishAzSKRootEvent([AzSKRootEvent]::WriteCSV, $controlCSV);
	}
	
	AddComplianceMessage([string] $ComplianceType, [string] $ComplianceCount, [string] $ComplianceComment)
	{
		$ComplianceMessage = New-Object -TypeName ComplianceMessageSummary
		$ComplianceMessage.ComplianceType = $ComplianceType
		$ComplianceMessage.ComplianceCount = $ComplianceCount
		$ComplianceMessage.ComplianceComment = $ComplianceComment
		$this.ComplianceMessageSummary += $ComplianceMessage
	}
}



class ComplianceMessageSummary
{
	[string] $ComplianceType = "" 
	[string] $ComplianceCount = ""
	[string] $ComplianceComment = ""
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
	
	[string] $IsControlInGrace = ""
}