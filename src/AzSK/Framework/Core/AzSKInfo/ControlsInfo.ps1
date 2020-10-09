using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class ControlsInfo: AzCommandBase
{    
	hidden [string] $ResourceTypeName
	hidden [string] $ResourceType
	hidden [bool] $BaslineControls
	hidden [bool] $PreviewBaslineControls
	hidden [PSObject] $ControlSettings
	hidden [string[]] $Tags = @();
	hidden [string[]] $ControlIds = @();
	hidden [bool] $Full
	hidden [string] $SummaryMarkerText = "------"
	hidden [string] $ControlSeverity
	hidden [string] $ControlIdContains

	ControlsInfo([string] $subscriptionId, [InvocationInfo] $invocationContext, [string] $resourceTypeName, [string] $resourceType, [string] $controlIds, [bool] $baslineControls,[bool] $previewBaslineControls, [string] $tags, [bool] $full, 
					[string] $controlSeverity, [string] $controlIdContains) :  Base($subscriptionId, $invocationContext)
    { 
		$this.ResourceTypeName = $resourceTypeName;
		$this.ResourceType = $resourceType;
		$this.BaslineControls = $baslineControls;
		$this.PreviewBaslineControls = $previewBaslineControls
		$this.Full = $full;
		$this.ControlSeverity = $controlSeverity;
		$this.ControlIdContains = $controlIdContains

		if(-not [string]::IsNullOrEmpty($tags))
        {
			$this.Tags += $this.ConvertToStringArray($tags);
        }
		if(-not [string]::IsNullOrEmpty($controlIds))
        {
			$this.ControlIds += $this.ConvertToStringArray($controlIds);
        }
		if($this.Full)
		{
			$this.DoNotOpenOutputFolder = $true;
		}
	}
	
	GetControlDetails() 
	{
		$resourcetypes = @() 
		$SVTConfig = @{} 
		$allControls = @()
		$controlSummary = @()

		# Filter Control for Resource Type / Resource Type Name
		if([string]::IsNullOrWhiteSpace($this.ResourceType) -and [string]::IsNullOrWhiteSpace($this.ResourceTypeName))
		{
			$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
			$this.PublishCustomMessage([Constants]::DefaultControlInfoCmdMsg, [MessageType]::Default);
			$this.DoNotOpenOutputFolder = $true;
			return;
		}

		#throw if user has set params for ResourceTypeName and ResourceType
		#Default value of ResourceTypeName is All.
		if($this.ResourceTypeName -ne [ResourceTypeName]::All -and -not [string]::IsNullOrWhiteSpace($this.ResourceType)){
			throw [SuppressedException] "Both the parameters 'ResourceTypeName' and 'ResourceType' contains values. You should use only one of these parameters."
		}

		if (-not [string]::IsNullOrEmpty($this.ResourceType)) 
		{
			$resourcetypes += ([SVTMapping]::Mapping |
					Where-Object { $_.ResourceType -eq $this.ResourceType } | Select-Object JsonFileName)
		}
		elseif($this.ResourceTypeName -ne [ResourceTypeName]::All)
		{
			$resourcetypes += ([SVTMapping]::Mapping |
					Where-Object { $_.ResourceTypeName -eq $this.ResourceTypeName } | Select-Object JsonFileName)
		}
		else
		{
			$resourcetypes += ([SVTMapping]::SubscriptionMapping | Select-Object JsonFileName)
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

		$previewBaselineControls = @();

		if([Helpers]::CheckMember($this.ControlSettings,"PreviewBaselineControls.ResourceTypeControlIdMappingList") )
		{
			$previewBaselineControls += $this.ControlSettings.PreviewBaselineControls.ResourceTypeControlIdMappingList | Select-Object ControlIds | ForEach-Object {  $_.ControlIds }
		}
		if([Helpers]::CheckMember($this.ControlSettings,"PreviewBaselineControls.SubscriptionControlIdList") )
		{
			$previewBaselineControls += $this.ControlSettings.PreviewBaselineControls.SubscriptionControlIdList | ForEach-Object {  $_ }
		}

		if($this.PreviewBaslineControls)
		{
			#If preview baseline switch is passed and there is no preview baseline control list present then throw exception 
			if (($previewBaselineControls | Measure-Object).Count -eq 0 -and -not $this.BaslineControls) 
			{
				throw ([SuppressedException]::new(("There are no preview baseline controls defined for this policy."), [SuppressedExceptionType]::Generic))
			}
			
			$this.ControlIds += $previewBaselineControls

		}

		$resourcetypes | ForEach-Object{
					$controls = [ConfigurationManager]::GetSVTConfig($_.JsonFileName); 
					[bool] $PolicyExpandedFlag = $false #Flag to represent whether control attributes have been updated or not
					if([ConfigurationHelper]::PolicyCacheContent[$_.JsonFileName].State -eq [PolicyCacheStatus]::Final)
					{
						$PolicyExpandedFlag = $true
					}

					# Filter control for enable only			
					$controls.Controls = ($controls.Controls | Where-Object { $_.Enabled -eq $true })

					# Filter control for ControlIds
					if ($this.ControlIds.Count -gt 0) 
					{
						$controls.Controls = ($controls.Controls | Where-Object { $this.ControlIds -contains $_.ControlId })
					}

					# Filter control for ControlId Contains
					if (-not [string]::IsNullOrEmpty($this.ControlIdContains)) 
					{
						$controls.Controls = ($controls.Controls | Where-Object { $_.ControlId -Match $this.ControlIdContains })
					}

					# Filter control for Tags
					if ($this.Tags.Count -gt 0) 
					{
						$controls.Controls = ($controls.Controls | Where-Object { ((Compare-Object $_.Tags $this.Tags -PassThru -IncludeEqual -ExcludeDifferent) | Measure-Object).Count -gt 0 })
					}

					# Filter control for ControlSeverity
					if (-not [string]::IsNullOrEmpty($this.ControlSeverity)) 
					{
						$controls.Controls = ($controls.Controls | Where-Object { $this.ControlSeverity -eq $_.ControlSeverity })
					}

					if ($controls.Controls.Count -gt 0)
					{
						if($PolicyExpandedFlag)
						{
							$controls.Controls | Foreach-Object {
								
								if($_.FixControl)
								{
									$fixControl = "Yes"
								}
								else
								{
									$fixControl = "No"
								}
								
								if($_.IsBaselineControl)
								{
									$isBaselineControls = "Yes"
								}
								else
								{
									$isBaselineControls = "No"
								}

								if($_.IsPreviewBaselineControl)
								{
									$isPreviewBaselineControls = "Yes"
								}
								else
								{
									$isPreviewBaselineControls = "No"
								}
													
								$ctrlObj = New-Object -TypeName PSObject
								$ctrlObj | Add-Member -NotePropertyName FeatureName -NotePropertyValue $controls.FeatureName 
								$ctrlObj | Add-Member -NotePropertyName ControlID -NotePropertyValue $_.ControlID
								$ctrlObj | Add-Member -NotePropertyName Description -NotePropertyValue $_.Description
								$ctrlObj | Add-Member -NotePropertyName ControlSeverity -NotePropertyValue $_.ControlSeverity
								$ctrlObj | Add-Member -NotePropertyName IsBaselineControl -NotePropertyValue $isBaselineControls
								$ctrlObj | Add-Member -NotePropertyName IsPreviewBaselineControl -NotePropertyValue $isPreviewBaselineControls
								$ctrlObj | Add-Member -NotePropertyName Rationale -NotePropertyValue $_.Rationale
								$ctrlObj | Add-Member -NotePropertyName Recommendation -NotePropertyValue $_.Recommendation
								$ctrlObj | Add-Member -NotePropertyName Automated -NotePropertyValue $_.Automated
								$ctrlObj | Add-Member -NotePropertyName SupportsAutoFix -NotePropertyValue $fixControl
								$tags = [system.String]::Join(", ", $_.Tags)
								$ctrlObj | Add-Member -NotePropertyName Tags -NotePropertyValue $tags 

								$allControls += $ctrlObj

								if($this.Full)
								{
									$this.PublishCustomMessage([Helpers]::ConvertObjectToString($ctrlObj, $true), [MessageType]::Info);
									$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info);
								}
							}
						}
						else
						{						
							$controls.Controls | Foreach-Object {
								$_.Description = $global:ExecutionContext.InvokeCommand.ExpandString($_.Description)
								$_.Recommendation = $global:ExecutionContext.InvokeCommand.ExpandString($_.Recommendation)
								if($_.FixControl)
								{
									$fixControl = "Yes"
								}
								else
								{
									$fixControl = "No"
								}
								
								if($baselineControls -contains $_.ControlID)
								{
									$isBaselineControls = "Yes"
								}
								else
								{
									$isBaselineControls = "No"
								}

								if($previewBaselineControls -contains $_.ControlID)
								{
									$isPreviewBaselineControls = "Yes"
								}
								else
								{
									$isPreviewBaselineControls = "No"
								}

								$ControlSeverity = $_.ControlSeverity
								if([Helpers]::CheckMember($this.ControlSettings,"ControlSeverity.$ControlSeverity"))
								{
									$_.ControlSeverity = $this.ControlSettings.ControlSeverity.$ControlSeverity
								}
								else
								{
									$_.ControlSeverity = $ControlSeverity
								}
													
								$ctrlObj = New-Object -TypeName PSObject
								$ctrlObj | Add-Member -NotePropertyName FeatureName -NotePropertyValue $controls.FeatureName 
								$ctrlObj | Add-Member -NotePropertyName ControlID -NotePropertyValue $_.ControlID
								$ctrlObj | Add-Member -NotePropertyName Description -NotePropertyValue $_.Description
								$ctrlObj | Add-Member -NotePropertyName ControlSeverity -NotePropertyValue $_.ControlSeverity
								$ctrlObj | Add-Member -NotePropertyName IsBaselineControl -NotePropertyValue $isBaselineControls
								$ctrlObj | Add-Member -NotePropertyName IsPreviewBaselineControl -NotePropertyValue $isPreviewBaselineControls
								$ctrlObj | Add-Member -NotePropertyName Rationale -NotePropertyValue $_.Rationale
								$ctrlObj | Add-Member -NotePropertyName Recommendation -NotePropertyValue $_.Recommendation
								$ctrlObj | Add-Member -NotePropertyName Automated -NotePropertyValue $_.Automated
								$ctrlObj | Add-Member -NotePropertyName SupportsAutoFix -NotePropertyValue $fixControl
								$tags = [system.String]::Join(", ", $_.Tags)
								$ctrlObj | Add-Member -NotePropertyName Tags -NotePropertyValue $tags 

								$allControls += $ctrlObj

								if($this.Full)
								{
									$this.PublishCustomMessage([Helpers]::ConvertObjectToString($ctrlObj, $true), [MessageType]::Info);
									$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info);
								}
							}
					    }

						$ctrlSummary = New-Object -TypeName PSObject
						$ctrlSummary | Add-Member -NotePropertyName FeatureName -NotePropertyValue $controls.FeatureName 
						$ctrlSummary | Add-Member -NotePropertyName Total -NotePropertyValue ($controls.Controls).Count
						$ctrlSummary | Add-Member -NotePropertyName $this.GetControlSeverity('Critical') -NotePropertyValue (($controls.Controls | Where-Object { $_.ControlSeverity -eq $this.GetControlSeverity("Critical") })|Measure-Object).Count
						$ctrlSummary | Add-Member -NotePropertyName $this.GetControlSeverity('High') -NotePropertyValue (($controls.Controls | Where-Object { $_.ControlSeverity -eq $this.GetControlSeverity("High") })|Measure-Object).Count
						$ctrlSummary | Add-Member -NotePropertyName $this.GetControlSeverity('Medium') -NotePropertyValue (($controls.Controls | Where-Object { $_.ControlSeverity -eq $this.GetControlSeverity("Medium") })|Measure-Object).Count
						$ctrlSummary | Add-Member -NotePropertyName $this.GetControlSeverity('Low') -NotePropertyValue (($controls.Controls | Where-Object { $_.ControlSeverity -eq $this.GetControlSeverity("Low") })|Measure-Object).Count
						$controlSummary += $ctrlSummary
					} 
                }

		if($controlSummary.Count -gt 0)
		{
			$controlCSV = New-Object -TypeName WriteCSVData
			$controlCSV.FileName = 'Control_Details_' + [String] $this.InvocationContext.Mycommand.ModuleName + "_" + [String] $this.GetCurrentModuleVersion()
			$controlCSV.FileExtension = 'csv'
			$controlCSV.FolderPath = ''
			$controlCSV.MessageData = $allControls| Sort-Object FeatureName, ControlSeverity

			$this.PublishAzSKRootEvent([AzSKRootEvent]::WriteCSV, $controlCSV);
		}
		else
		{
			$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
			$this.PublishCustomMessage("No controls have been found.");
			$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		}

		if($controlSummary.Count -gt 0)
		{
			$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
			$this.PublishCustomMessage("Summary of controls available in " + $this.InvocationContext.Mycommand.ModuleName +" "+  $this.GetCurrentModuleVersion(), [MessageType]::Default)
			$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);

			$ctrlSummary = New-Object -TypeName PSObject
			$ctrlSummary | Add-Member -NotePropertyName FeatureName -NotePropertyValue "Total" 
			$ctrlSummary | Add-Member -NotePropertyName Total -NotePropertyValue ($controlSummary | Measure-Object 'Total' -Sum).Sum

			$ctrlSummary | Add-Member -NotePropertyName $this.GetControlSeverity('Critical') -NotePropertyValue ($controlSummary | Measure-Object "$($this.GetControlSeverity('Critical'))" -Sum).Sum
			$ctrlSummary | Add-Member -NotePropertyName $this.GetControlSeverity('High') -NotePropertyValue ($controlSummary | Measure-Object "$($this.GetControlSeverity('High'))" -Sum).Sum
			$ctrlSummary | Add-Member -NotePropertyName $this.GetControlSeverity('Medium') -NotePropertyValue ($controlSummary | Measure-Object "$($this.GetControlSeverity('Medium'))" -Sum).Sum
			$ctrlSummary | Add-Member -NotePropertyName $this.GetControlSeverity('Low') -NotePropertyValue ($controlSummary | Measure-Object "$($this.GetControlSeverity('Low'))" -Sum).Sum

			$totalSummaryMarker = New-Object -TypeName PSObject
			$totalSummaryMarker | Add-Member -NotePropertyName FeatureName -NotePropertyValue $this.SummaryMarkerText
			$totalSummaryMarker | Add-Member -NotePropertyName Total -NotePropertyValue $this.SummaryMarkerText
			$totalSummaryMarker | Add-Member -NotePropertyName $this.GetControlSeverity('Critical') -NotePropertyValue $this.SummaryMarkerText
			$totalSummaryMarker | Add-Member -NotePropertyName $this.GetControlSeverity('High') -NotePropertyValue $this.SummaryMarkerText
			$totalSummaryMarker | Add-Member -NotePropertyName $this.GetControlSeverity('Medium') -NotePropertyValue $this.SummaryMarkerText
			$totalSummaryMarker | Add-Member -NotePropertyName $this.GetControlSeverity('Low') -NotePropertyValue $this.SummaryMarkerText

			$controlSummary += $totalSummaryMarker
			$controlSummary += $ctrlSummary

			$this.PublishCustomMessage(($controlSummary | Format-Table | Out-String), [MessageType]::Default)
		}
        
	}
	
	[string] GetControlSeverity($ControlSeverityFromServer)
	{
		if([Helpers]::CheckMember($this.ControlSettings,"ControlSeverity.$ControlSeverityFromServer"))
		{
			$ControlSeverityFromServer = $this.ControlSettings.ControlSeverity.$ControlSeverityFromServer
		}
		return $ControlSeverityFromServer
	}
}

class WriteCSVData
{
	[string] $FileName = ""
	[string] $FileExtension = ""
	[string] $FolderPath = ""
	[PSObject] $MessageData
}