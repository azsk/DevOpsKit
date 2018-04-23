using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class ARMCheckerStatus: EventBase
{
	hidden [string] $ARMControls;
	hidden [string] $PSLogPath;
	[bool] $DoNotOpenOutputFolder = $false;

	ARMCheckerStatus([InvocationInfo] $invocationContext) 
    {
	    if (-not $invocationContext)
		{
            throw [System.ArgumentException] ("The argument 'invocationContext' is null. Pass the `$PSCmdlet.MyInvocation from PowerShell command.");
        }
        $this.InvocationContext = $invocationContext;

		#load config file here.
		$this.ARMControls = [ConfigurationHelper]::LoadOfflineConfigFile("ARMControls.json", $false);
		if([string]::IsNullOrWhiteSpace($this.ARMControls))
		{
			throw ([SuppressedException]::new(("There are no controls to evaluate in ARM checker. Please contact support team."), [SuppressedExceptionType]::InvalidOperation))
		}

		if($null -ne $this.InvocationContext.BoundParameters["DoNotOpenOutputFolder"])
		{
			$this.DoNotOpenOutputFolder = $this.InvocationContext.BoundParameters["DoNotOpenOutputFolder"];
		}
	}

	hidden [void] CommandStartedAction()
	{
		$currentVersion = $this.GetCurrentModuleVersion();
		$moduleName = $this.GetModuleName();
		$methodName = $this.InvocationContext.InvocationName;
		
		$this.WriteMessage([Constants]::DoubleDashLine + "`r`n$moduleName Version: $currentVersion `r`n" + [Constants]::DoubleDashLine , [MessageType]::Info);      
		$this.WriteMessage("Method Name: $methodName `r`nInput Parameters: $(($this.InvocationContext.BoundParameters | Out-String).TrimEnd()) `r`n" + [Constants]::DoubleDashLine , [MessageType]::Info);                           
	}

	hidden [void] CommandCompletedAction($resultsFolder)
	{
		$this.WriteMessage([Constants]::SingleDashLine, [MessageType]::Info);
		$this.WriteMessage("Status and detailed logs have been exported to path - $($resultsFolder)", [MessageType]::Info);
		$this.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Info);
	}


	[string] EvaluateStatus([string] $armTemplatePath,[Boolean]  $isRecurse,[string] $ExemptControlListPath)
	{
	    if(-not (Test-Path -path $armTemplatePath))
		{
			$this.WriteMessage("ARMTemplate file path or folder path is empty, verify that the path is correct and try again", [MessageType]::Error);
			return $null;
		}
		$this.PSLogPath = "";
		$baseDirectory = [System.IO.Path]::GetDirectoryName($armTemplatePath);
	    if($isRecurse -eq $true)
		{
			$ARMTemplates = Get-ChildItem -Path $armTemplatePath -Recurse -Filter '*.json' 
		}
		else
		{
			$ARMTemplates = Get-ChildItem -Path $armTemplatePath -Filter '*.json' 
		}

	    $armEvaluator = [AzSK.ARMChecker.Lib.ArmTemplateEvaluator]::new([string] $this.ARMControls);
		$skippedFiles = @();
		$timeMarker = [datetime]::Now.ToString("yyyyMMdd_HHmmss")
		$resultsFolder = [Constants]::AzSKLogFolderPath + [Constants]::AzSKModuleName + "Logs\ARMChecker\" + $timeMarker + "\";
		$csvFilePath = $resultsFolder + "ARMCheckerResults_" + $timeMarker + ".csv";
		[System.IO.Directory]::CreateDirectory($resultsFolder) | Out-Null
		$this.PSLogPath = $resultsFolder + "PowerShellOutput.LOG";
		$this.CommandStartedAction();
		$csvResults = @();
		$armcheckerscantelemetryEvents = [System.Collections.ArrayList]::new()
		$scannedFileCount = 0

		foreach($armTemplate in $ARMTemplates)
		{
			$armFileName = $armTemplate.FullName.Replace($baseDirectory, "");
			try
			{
				$results = @();
				$armTemplateContent = Get-Content $armTemplate.FullName -Raw		
				$libResults = $armEvaluator.Evaluate($armTemplateContent, $null);
				$results += $libResults | Where-Object {$_.VerificationResult -ne "NotSupported"} | Select-Object -ExcludeProperty "IsEnabled"		
		
				$this.WriteMessage(([Constants]::DoubleDashLine + "`r`nStarting analysis: [FileName: $armFileName] `r`n" + [Constants]::SingleDashLine), [MessageType]::Info);
				$scannedFileCount += 1;
				if($results.Count -gt 0)
				{
					foreach($result in $results)
					{
						$csvResultItem = "" | Select-Object "ControlId", "Status", "ResourceType",  "Severity", `
															"PropertyPath", "LineNumber", "CurrentValue", "ExpectedValue", `
															"ResourcePath", "ResourceLineNumber", "Description","FilePath"

						$csvResultItem.ResourceType = $result.ResourceType
						$csvResultItem.ControlId = $result.ControlId
						$csvResultItem.Description = $result.Description
						$csvResultItem.ExpectedValue = $result.ExpectedValue
						$csvResultItem.Severity = $result.Severity.ToString()
						$csvResultItem.Status = $result.VerificationResult
						$csvResultItem.FilePath = $armFileName					

						if($result.ResultDataMarkers.Count -gt 0)
						{
							$csvResultItem.LineNumber = $result.ResultDataMarkers[0].LineNumber
							$csvResultItem.PropertyPath = $result.ResultDataMarkers[0].JsonPath
							$data = $result.ResultDataMarkers[0].DataMarker
							if($data -ieq "true" -or $data -ieq "false") {
								$csvResultItem.CurrentValue = $data.ToLower()
							}
							else
							{
								$csvResultItem.CurrentValue = $data
							}
						}
						else
						{
							$csvResultItem.LineNumber = -1
							$csvResultItem.PropertyPath = "Not found"
							$csvResultItem.CurrentValue = ""
						}
						$csvResultItem.ResourceLineNumber = $result.ResourceDataMarker.LineNumber
						$csvResultItem.ResourcePath = $result.ResourceDataMarker.JsonPath
						$csvResults += $csvResultItem;

						$this.WriteResult($result);

						$properties = @{};
						$properties.Add("ResourceType", $result.ResourceType)
						$properties.Add("ControlId", $result.ControlId)
						$properties.Add("VerificationResult", $result.VerificationResult);

						$telemetryEvent = "" | Select-Object Name, Properties, Metrics
						$telemetryEvent.Name = "ARMChecker Control Scanned"
						$telemetryEvent.Properties = $properties
						$armcheckerscantelemetryEvents.Add($telemetryEvent)
					}
					$this.WriteMessage([Constants]::SingleDashLine, [MessageType]::Info);
					$this.WriteSummary($results, "Severity", "VerificationResult");
				}
				else
				{
					$this.WriteMessage("No controls have been evaluated for file: $armFileName", [MessageType]::Info);
				}
			}
			catch
			{
				#Write-Host ([Helpers]::ConvertObjectToString($_, $false)) -ForegroundColor Red
				$skippedFiles += $armFileName;
			}		
		}
		# Read Exempt Control List File here	
		$EffectiveResults=@()
		if(-not([string]::IsNullOrEmpty($ExemptControlListPath)) -and (Test-Path -path $ExemptControlListPath))
		{
			$exemptControlList=Get-Content $ExemptControlListPath | ConvertFrom-Csv
            $EffectiveResults = Compare-Object -ReferenceObject $csvResults -DifferenceObject $exemptControlList -PassThru -IncludeEqual -Property ControlId,PropertyPath,FilePath 
		     $EffectiveResults| ForEach-Object {
		         if($_.SideIndicator -eq "==")
			    {
			     $_.Status= "Exempted"
			   }
		    }
		      $EffectiveResults=   $EffectiveResults | Select-Object "ControlId", "Status", "ResourceType",  "Severity", `
															"PropertyPath", "LineNumber", "CurrentValue", "ExpectedValue", `
															"ResourcePath", "ResourceLineNumber", "Description","FilePath"
			}
		
		if(($EffectiveResults |Measure-Object).Count -eq 0)
		{
		  $EffectiveResults=$csvResults
		}
		 $EffectiveResults| Export-Csv $csvFilePath -NoTypeInformation -Force

		if($skippedFiles.Count -ne 0)
		{
			$this.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Warning);
			$this.WriteMessage("Skipped file(s): $($skippedFiles.Count)", [MessageType]::Warning);
			$skippedFiles | ForEach-Object {
				$this.WriteMessage($_, [MessageType]::Warning);
			};
			$this.WriteMessage([Constants]::SingleDashLine, [MessageType]::Warning);
		}

		$teleEvent = "" | Select-Object Name, Properties, Metrics
		$teleEvent.Name = "ARMChecker Command Completed"
	    $teleEvent.Properties = @{};
		$teleEvent.Properties.Add("Total", $csvResults.Count);

		if($csvResults.Count -ne 0)
		{
			$this.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Info);
			$this.WriteSummary($EffectiveResults, "Severity", "Status");
			$this.WriteMessage("Total scanned file(s): $scannedFileCount", [MessageType]::Info);

			$resultsGroup = $EffectiveResults | Group-Object Status | ForEach-Object {
				$teleEvent.Properties.Add($_.Name, $_.Count);
			};
		}
		else
		{
			$this.WriteMessage("No controls have been evaluated for ARM Template(s).", [MessageType]::Error);
		}

		$this.CommandCompletedAction($resultsFolder);	

		$armcheckerscantelemetryEvents.Add($teleEvent)
		[AIOrgTelemetryHelper]::PublishARMCheckerEvent($armcheckerscantelemetryEvents)

		if((-not $this.DoNotOpenOutputFolder) -and (-not [string]::IsNullOrEmpty($resultsFolder)))
		{
			try
			{
				Invoke-Item -Path $resultsFolder;
			}
			catch
			{
				#ignore if any exception occurs
			}
		}
		return $resultsFolder
	}

	hidden [void] WriteResult($result)
	{
		$messageType = [MessageType]::Info;
		switch ($result.VerificationResult)
		{
			Passed
			{ 
				$messageType = [MessageType]::Update;
			}
			Verify
			{
				$messageType = [MessageType]::Warning;
			}
			Failed
			{
				$messageType = [MessageType]::Error;
			}
		}
		$this.WriteMessage("$($result.VerificationResult): [$($result.ControlId)]", $messageType);
	}
	hidden [void] WriteSummary($summary, $severityPropertyName, $resultPropertyName)
	{
		if($summary.Count -ne 0)
		{
			$summaryResult = @();

			$severities = @();
			$severities += $summary | Select-Object -Property $severityPropertyName | Select-Object -ExpandProperty $severityPropertyName -Unique;

			$verificationResults = @();
			$verificationResults += $summary | Select-Object -Property $resultPropertyName | Select-Object -ExpandProperty $resultPropertyName -Unique;

			if($severities.Count -ne 0)
			{
				# Create summary matrix
				$totalText = "Total";
				$MarkerText = "MarkerText";
				$rows = @();
				$rows += [Enum]::GetNames([ControlSeverity]) | Where-Object { $severities -contains $_ };
				$rows += $MarkerText;
				$rows += $totalText;
				$rows += $MarkerText;
				$rows | ForEach-Object {
					$result = [PSObject]::new();
					Add-Member -InputObject $result -Name "Summary" -MemberType NoteProperty -Value $_.ToString()
					Add-Member -InputObject $result -Name $totalText -MemberType NoteProperty -Value 0

					[Enum]::GetNames([VerificationResult]) | Where-Object { $verificationResults -contains $_ } |
					ForEach-Object {
						Add-Member -InputObject $result -Name $_.ToString() -MemberType NoteProperty -Value 0
					};
					$summaryResult += $result;
				};

				$totalRow = $summaryResult | Where-Object { $_.Summary -eq $totalText } | Select-Object -First 1;

				$summary | Group-Object -Property $severityPropertyName | ForEach-Object {
					$item = $_;
					$summaryItem = $summaryResult | Where-Object { $_.Summary -eq $item.Name } | Select-Object -First 1;
					if($summaryItem)
					{
						$summaryItem.Total = $_.Count;
						if($totalRow)
						{
							$totalRow.Total += $_.Count
						}
						$item.Group | Group-Object -Property $resultPropertyName | ForEach-Object {
							$propName = $_.Name;
							$summaryItem.$propName += $_.Count;
							if($totalRow)
							{
								$totalRow.$propName += $_.Count
							}
						};
					}
				};
				$markerRows = $summaryResult | Where-Object { $_.Summary -eq $MarkerText } 
				$markerRows | ForEach-Object { 
					$markerRow = $_
					Get-Member -InputObject $markerRow -MemberType NoteProperty | ForEach-Object {
							$propName = $_.Name;
							$markerRow.$propName = "------";				
						}
					};
				if($summaryResult.Count -ne 0)
				{		
					$this.WriteMessage(($summaryResult | Format-Table | Out-String), [MessageType]::Info)
				}
			}
		}
	}
	hidden [void] WriteMessage([PSObject] $message, [MessageType] $messageType)
    {
        if(-not $message)
        {
            return;
        }
        
        $colorCode = [System.ConsoleColor]::White

        switch($messageType)
        {
            ([MessageType]::Critical) {  
                $colorCode = [System.ConsoleColor]::Red              
            }
            ([MessageType]::Error) {
                $colorCode = [System.ConsoleColor]::Red             
            }
            ([MessageType]::Warning) {
                $colorCode = [System.ConsoleColor]::Yellow              
            }
            ([MessageType]::Info) {
                $colorCode = [System.ConsoleColor]::Cyan
            }  
            ([MessageType]::Update) {
                $colorCode = [System.ConsoleColor]::Green
            }
            ([MessageType]::Deprecated) {
                $colorCode = [System.ConsoleColor]::DarkYellow
            }
			([MessageType]::Default) {
                $colorCode = [System.ConsoleColor]::White
            }           
        }   

		$formattedMessage = [Helpers]::ConvertObjectToString($message, (-not [string]::IsNullOrEmpty($this.PSLogPath)));		
        Write-Host $formattedMessage -ForegroundColor $colorCode

		$this.AddOutputLog([Helpers]::ConvertObjectToString($message, $false));
    }

	hidden [void] AddOutputLog([string] $message)   
    {
        if([string]::IsNullOrEmpty($message) -or [string]::IsNullOrEmpty($this.PSLogPath))
        {
            return;
        }
             
        Add-Content -Value $message -Path $this.PSLogPath        
    } 
}

