using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class ARMCheckerStatus: EventBase
{
	hidden [string] $ARMControls;
	hidden [string []] $BaselineControls;
	hidden [string] $PSLogPath;
	hidden [string] $SFLogPath;
	[bool] $DoNotOpenOutputFolder = $false;

	ARMCheckerStatus([InvocationInfo] $invocationContext) 
    {
	    if (-not $invocationContext)
		{
            throw [System.ArgumentException] ("The argument 'invocationContext' is null. Pass the `$PSCmdlet.MyInvocation from PowerShell command.");
        }
		$this.InvocationContext = $invocationContext;
		# Set current Module name and Version
		$this.SetAzSKModuleName($this.invocationContext);
		$this.SetCurrentAzSKModuleVersion($this.invocationContext);
		# Load config file here.
		$this.ARMControls=$this.LoadARMControlsFile();
		if([string]::IsNullOrWhiteSpace($this.ARMControls))
		{
			throw ([SuppressedException]::new(("There are no controls to evaluate in ARM checker. Please contact support team."), [SuppressedExceptionType]::InvalidOperation))
		}

		if($null -ne $this.InvocationContext.BoundParameters["DoNotOpenOutputFolder"])
		{
			$this.DoNotOpenOutputFolder = $this.InvocationContext.BoundParameters["DoNotOpenOutputFolder"];
		}
	}

	hidden [void] SetAzSKModuleName([InvocationInfo] $invocationContext)
	{
		if($invocationContext)
		{
			[Constants]::SetAzSKModuleName($invocationContext.MyCommand.Module.Name);
		}
	}

	hidden [void] SetCurrentAzSKModuleVersion([InvocationInfo] $invocationContext)
	{
		if($invocationContext)
		{
			[Constants]::SetAzSKCurrentModuleVersion($invocationContext.MyCommand.Version);
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
		$this.WriteMessage([Constants]::RemediationMsgForARMChekcer, [MessageType]::Info);
		$this.WriteMessage("For further details, refer: "+[Constants]::CICDShortLink,[MessageType]::Info) 
		$this.WriteMessage([Constants]::SingleDashLine, [MessageType]::Info);
		$this.WriteMessage("Status and detailed logs have been exported to: $($resultsFolder)", [MessageType]::Info);
		$this.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Info);
	}


	[string] EvaluateStatus([string] $armTemplatePath, [string] $parameterFilePath ,[Boolean]  $isRecurse,[string] $exemptControlListPath,[string] $ExcludeFiles, [string] $ExcludeControlIds, [string] $ControlIds,[Boolean] $UseBaselineControls,[Boolean] $UsePreviewBaselineControls, [string[]]$Severity)
	{
        $this.CommandStartedAction();
	    if(-not (Test-Path -path $armTemplatePath))
		{
			$this.WriteMessage("ARMTemplate file path or folder path is empty, verify that the path is correct and try again", [MessageType]::Error);
			return $null;
		}
		
		#load baseline control list 
		$ErrorLoadingControlSettings = $this.LoadControlSettingsFile($UseBaselineControls, $UsePreviewBaselineControls);
		if($ErrorLoadingControlSettings){
			return $null;
		}

		# Check if parameter file path is provided by user
		if([string]::IsNullOrEmpty($parameterFilePath))
		{
			$parameterFileProvided = $false;
		}else{
			$parameterFileProvided = $true;
		}

		# Check if provided parameter file path is valid  
		if($parameterFileProvided -and -not (Test-Path -path $parameterFilePath))
		{
		    $parameterFileProvided = $false;
			$this.WriteMessage("Template parameter file path or folder path is empty, verify that the path is correct and try again", [MessageType]::Warning);
		}

		# Check if provided parameter file path is a single file or folder 
		$ParameterFiles = $null;
		$paramterFileContent = $null;
		if($parameterFileProvided -and (Test-Path -path $parameterFilePath -PathType Leaf))
		{
		  $paramterFileContent = Get-Content $parameterFilePath -Raw
		}elseif ($parameterFileProvided) {
			if($isRecurse -eq $true)
			{
				$ParameterFiles = Get-ChildItem -Path $parameterFilePath -Recurse -Filter '*.parameters.json' 
			}
			else
			{
				$ParameterFiles = Get-ChildItem -Path $parameterFilePath -Filter '*.parameters.json' 
			}
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
		$resultsFolder = Join-Path $([Constants]::AzSKLogFolderPath) $([Constants]::AzSKModuleName + "Logs") | Join-Path -ChildPath "ARMChecker" | Join-Path -ChildPath $timeMarker ;
		$csvFilePath = Join-Path $resultsFolder ("ARMCheckerResults_" + $timeMarker + ".csv");
		[System.IO.Directory]::CreateDirectory($resultsFolder) | Out-Null
		$this.PSLogPath = Join-Path $resultsFolder "PowerShellOutput.LOG";
		$this.SFLogPath = Join-Path $resultsFolder "SkippedFiles.LOG";
		
		$csvResults = @();
		$armcheckerscantelemetryEvents = [System.Collections.ArrayList]::new()
		$scannedFileCount = 0
		$exemptControlList=@()
		$filesToExclude=@()
		$filesToExcludeCount=0
		$excludedFiles=@()
		$filteredFiles = @();
		$ControlsToScanBySeverity =@();
		try{
		  if(-not([string]::IsNullOrEmpty($exemptControlListPath)) -and (Test-Path -path $exemptControlListPath -PathType Leaf))
		  {
		    $exemptControlListFile=Get-Content $exemptControlListPath | ConvertFrom-Csv
	        $exemptControlList=$exemptControlListFile| where {$_.Status -eq "Failed" -or $_.Status -eq "Verify"} 
		  }
		}catch{
		    $this.WriteMessage("Unable to read file containing list of controls to skip, Please verify file path.", [MessageType]::Warning);
		}
		if(-not([string]::IsNullOrEmpty($ExcludeFiles)))
		{
		  $ExcludeFileFilters = @();
		  $ExcludeFileFilters = $this.ConvertToStringArray($ExcludeFiles);
		  $ExcludeFileFilters | ForEach-Object {
			if($isRecurse -eq $true)
			{
			  $filesToExclude = Get-ChildItem -Path $armTemplatePath -Recurse -Filter $_
			}
			else{
				$filesToExclude = Get-ChildItem -Path $armTemplatePath -Filter $_
			}
			if($null -ne $filesToExclude -and ($filesToExclude | Measure-Object).Count -gt 0)
			{
			   $filesToExclude | Select-Object Name | ForEach-Object { $filteredFiles += $_.Name}
			}
		  }
		$filesToExclude = $filteredFiles -join ","
		$filesToExcludeCount = ($filesToExclude| Measure-Object).Count 
		}

		# Check if both -ControlIds and ExcludeControlIds switch are provided , return with error message
		if(-not([string]::IsNullOrEmpty($ControlIds)) -and -not([string]::IsNullOrEmpty($ExcludeControlIds))){
			$this.WriteMessage("InvalidArgument: Both the parameters 'ControlIds' and 'ExcludeControlIds' contain values. You should use only one of these parameters.", [MessageType]::Error);
		    return $null;
		}

		# Check if both -ControlIds and UseBaselineControls switch are provided , return with error message
		if(-not([string]::IsNullOrEmpty($ControlIds)) -and $UseBaselineControls){
			$this.WriteMessage("InvalidArgument: Both the parameters 'ControlIds' and 'UseBaselineControls' contain values. You should use only one of these parameters.", [MessageType]::Error);
			return $null;
		}

		# Check if both -ControlIds and UsePreviewBaselineControls switch are provided , return with error message
		if(-not([string]::IsNullOrEmpty($ControlIds)) -and $UsePreviewBaselineControls){
			$this.WriteMessage("InvalidArgument: Both the parameters 'ControlIds' and 'UsePreviewBaselineControls' contain values. You should use only one of these parameters.", [MessageType]::Error);
			return $null;
		}

		# Check if specific control ids to scan are provided by user  
		$ControlsToScan = @();
		if(-not([string]::IsNullOrEmpty($ControlIds)))
		{
		  $ControlsToScan = $this.ConvertToStringArray($ControlIds);
		} 

		if(-not([string]::IsNullOrEmpty($Severity)))
        {
			$Severity = $this.ConvertToStringArray($Severity);
			$InvalidSeverities = @();
			$InvalidSeverities += $Severity | Where-Object {$_ -notin [Enum]::GetNames('ControlSeverity')}
			#Discard the severity inputs that are not in enum 
			$Severity = $Severity | Where-Object {$_ -in [Enum]::GetNames('ControlSeverity')}
			if($InvalidSeverities.Count -gt 0)
			{
				$this.WriteMessage("WARNING: No control severity corresponds to `"$($InvalidSeverities -join ', ')`" for your org.",[MessageType]::Warning);
			}
			$ControlsToScanBySeverity = $Severity
        }

		# Check if exclude control ids are provided by user 
		$ControlsToExclude = @();
		if(-not([string]::IsNullOrEmpty($ExcludeControlIds)))
		{
		  $ControlsToExclude = $this.ConvertToStringArray($ExcludeControlIds);
		}

		foreach($armTemplate in $ARMTemplates)
		{
		    $armFileName = $armTemplate.FullName.Replace($baseDirectory, ".");
		    if(($filesToExcludeCount -eq 0) -or (-not $filteredFiles.Contains($armTemplate.Name)))
			{		
			try
			{
				$results = @();
				$csvResultsForCurFile=@();
				$relatedParameterFile = $null
				$relatedParameterFileName = $null
				$armTemplateContent = Get-Content $armTemplate.FullName -Raw	
				if($null -ne $ParameterFiles -and ($ParameterFiles | Measure-Object).Count -gt 0)
				{
					$relatedParameterFileName = $armTemplate.Name.Replace(".json",".parameters.json");
					$relatedParameterFile = $ParameterFiles | Where-Object { $_.Name -eq $relatedParameterFileName }
					if($null -ne $relatedParameterFile)
					{
						$relatedParameterFile = $relatedParameterFile | Select-Object -First 1
						$paramterFileContent = Get-Content $relatedParameterFile.FullName -Raw
					}
					$libResults = $armEvaluator.Evaluate($armTemplateContent, $paramterFileContent);
				}else
				{
					$libResults = $armEvaluator.Evaluate($armTemplateContent, $paramterFileContent);
					#$libResults = $armEvaluator.Evaluate($armTemplateContent, $null);
				}
				
				$results += $libResults | Where-Object {$_.VerificationResult -ne "NotSupported"} | Select-Object -ExcludeProperty "IsEnabled"		
		
				if($null -ne $results -and ( $results| Measure-Object).Count -gt 0 -and $this.BaselineControls.Count -gt 0){
					$results = $results | Where-Object {$this.BaselineControls -contains $_.ControlId}
				}

				if($null -ne $results -and ( $results | Measure-Object).Count  -gt 0 -and ( $ControlsToScan | Measure-Object).Count -gt 0 ){
                    $results = $results | Where-Object {$ControlsToScan -contains $_.ControlId}
                    
                }

				if($null -ne $results -and ( $results | Measure-Object).Count  -gt 0  -and ( $ControlsToExclude | Measure-Object).Count -gt 0){
					$results = $results | Where-Object {$ControlsToExclude -notcontains $_.ControlId}
				}

				if($null -ne $results -and ( $results | Measure-Object).Count  -gt 0  -and ( $ControlsToScanBySeverity | Measure-Object).Count -gt 0){
					$results = $results | Where-Object {$_.Severity -in $ControlsToScanBySeverity}
				}

				
				$this.WriteMessage(([Constants]::DoubleDashLine + "`r`nStarting analysis: [FileName: $armFileName] `r`n" + [Constants]::SingleDashLine), [MessageType]::Info);
				if($null -ne $relatedParameterFile){
					$this.WriteMessage(("`r`n[ParameterFileName: $relatedParameterFileName] `r`n" + [Constants]::SingleDashLine), [MessageType]::Info);
				}
				if($null -ne $results -and ($results | Measure-Object).Count -gt 0)
				{   $scannedFileCount += 1;
					foreach($result in $results)
					{	       
						$csvResultItem = "" | Select-Object "ControlId", "FeatureName","Status", "SupportedResources",  "Severity", `
															"PropertyPath", "LineNumber", "CurrentValue", "ExpectedProperty", "ExpectedValue", `
															"ResourcePath", "ResourceLineNumber", "Description","FilePath"
									

						$csvResultItem.SupportedResources = $result.SupportedResources
						$csvResultItem.ControlId = $result.ControlId
						$csvResultItem.FeatureName = $result.FeatureName
						$csvResultItem.Description = $result.Description
						$csvResultItem.ExpectedProperty = $result.ExpectedProperty
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
						if(($exemptControlList|Measure-Object).Count -gt 0)
						{				
                         $csvResultItem = Compare-Object -ReferenceObject $csvResultItem -DifferenceObject $exemptControlList -PassThru -IncludeEqual -Property ControlId,PropertyPath 
		                 $csvResultItem| ForEach-Object {
		                               if($_.SideIndicator -eq "==")
			                           {
			                             $_.Status = "Skipped"
			                           }
		                  }
			             $csvResultItem =$csvResultItem | where {$_.SideIndicator -eq "==" -or $_.SideIndicator -eq "<="}
						 $csvResultItem =$csvResultItem | Select-Object "ControlId", "FeatureName","Status", "SupportedResources",  "Severity", `
															"PropertyPath", "LineNumber", "CurrentValue", "ExpectedProperty", "ExpectedValue", `
															"ResourcePath", "ResourceLineNumber", "Description","FilePath"
						 								    									
						}
						$properties = @{};
						$properties.Add("ResourceType", $csvResultItem.FeatureName)
						$properties.Add("ControlId", $csvResultItem.ControlId)
						$properties.Add("VerificationResult", $csvResultItem.Status);

						$telemetryEvent = "" | Select-Object Name, Properties, Metrics
						$telemetryEvent.Name = "ARMChecker Control Scanned"
						$telemetryEvent.Properties = $properties
						[bool] $flag = $true;
						foreach($cr in $csvResults)
						{
							if($cr.ExpectedProperty -eq $csvResultItem.ExpectedProperty -and $cr.ControlId -eq $csvResultItem.ControlId -and $cr.LineNumber -eq $csvResultItem.LineNumber -and $cr.ResourceLineNumber -eq $csvResultItem.ResourceLineNumber -and $cr.FilePath -eq $csvResultItem.FilePath -and $cr.ExpectedValue -eq $csvResultItem.ExpectedValue)
							{
								$flag = $false;
								break;
							}
						}
						if($flag)
						{
							$csvResults += $csvResultItem;
							$this.WriteResult($csvResultItem);
							$csvResultsForCurFile+=$csvResultItem;
							$armcheckerscantelemetryEvents.Add($telemetryEvent)
				    	}
					}
					$this.WriteMessage([Constants]::SingleDashLine, [MessageType]::Info);
					$this.WriteSummary($csvResultsForCurFile, "Severity", "Status");
				}
				else
				{
				    $skippedFiles += $armFileName;
					$this.WriteMessage("No controls have been evaluated for file: $armFileName", [MessageType]::Info);
				}
			}
			catch
			{
				$skippedFiles += $armFileName;
			}	
			}
			else
			{
			  $excludedFiles += $armFileName;
			}	
		}
		
		if($csvResults.Count -ge 0)
		{
		    $csvResults| Export-Csv $csvFilePath -NoTypeInformation -Force
        }

		if($excludedFiles.Count -ne 0)
		{
			$this.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Warning);
			$this.WriteMessage("Excluded file(s): $($excludedFiles.Count)", [MessageType]::Warning);
			$excludedFiles | ForEach-Object {
				$this.WriteMessage($_, [MessageType]::Warning);
			};
			$this.WriteMessage([Constants]::SingleDashLine, [MessageType]::Warning);
		}

		if($skippedFiles.Count -ne 0)
		{
			$this.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Warning);
			$this.WriteMessage("Skipped file(s): $($skippedFiles.Count)", [MessageType]::Warning);
			$skippedFiles | ForEach-Object {
				$this.WriteMessage($_, [MessageType]::Warning);
				$this.AddSkippedFilesLog([Helpers]::ConvertObjectToString($_, $false));
			};
			$this.WriteMessage([Constants]::SingleDashLine, [MessageType]::Warning);
			$this.WriteMessage("One or more files were skipped during the scan. `nEither the files are invalid as ARM templates or those resource types are currently not supported by this command.`nPlease verify the files and re-run the command. `nFor files that should not be included in the scan, you can use the '-ExcludeFiles' parameter.",[MessageType]::Error);
			$this.WriteMessage([Constants]::SingleDashLine, [MessageType]::Warning);
		}

		

		$teleEvent = "" | Select-Object Name, Properties, Metrics
		$teleEvent.Name = "ARMChecker Command Completed"
	    $teleEvent.Properties = @{};
		$teleEvent.Properties.Add("Total", $csvResults.Count);

		if($csvResults.Count -ne 0)
		{
			$this.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Info);
			$this.WriteSummary($csvResults, "Severity", "Status");
			$this.WriteMessage("Total scanned file(s): $scannedFileCount", [MessageType]::Info);

			$resultsGroup = $csvResults | Group-Object Status | ForEach-Object {
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
		switch ($result.Status)
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
			Exempted
			{
				$messageType = [MessageType]::Update;
			}
		}
		$this.WriteMessage("$($result.Status): [$($result.ControlId)]", $messageType);
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
				$rows += $severities;
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
	hidden [void] AddSkippedFilesLog([string] $message)   
    {
        if([string]::IsNullOrEmpty($message) -or [string]::IsNullOrEmpty($this.PSLogPath))
        {
            return;
        }
             
        Add-Content -Value $message -Path $this.SFLogPath        
	} 
	
	hidden [Object] MergeExtensionFile([Object] $source,[Object] $extend)
	{ 	
		if([Helpers]::CheckMember($extend,"resourceControlSets")){
			$extend.resourceControlSets | ForEach-Object {
				try{
						$currentFeature  = $_
						$existingFeature = $source.resourceControlSets | Where-Object {$_.featureName -eq $currentFeature.featureName } 
						if($existingFeature -ne $null)
						{
							$existingFeature.controls += $currentFeature.controls
						
						}else{
						
							$source.resourceControlSets += $currentFeature
						}
					}catch{
							# No need to break execution, source file will be returned
					}
			}

		}
		
			
	   return $source;
	}


	hidden [string] LoadARMControlsFile()
	{ 	
	   $serverFileContent=$null;
	   $ARMControlsFileURI = [Constants]::ARMControlsFileURI
	   $checkExtensionFile = $false
	   try
	   {
			if(-not [ConfigurationManager]::GetLocalAzSKSettings().EnableAADAuthForOnlinePolicyStore)
			{
				$serverFileContent = [ConfigurationManager]::LoadServerConfigFile("ARMControls.json");
				$checkExtensionFile = $true
			}
			else 
			{
				$AzureContext = Get-AzContext
				if(-not [string]::IsNullOrWhiteSpace($AzureContext)) 
				{
					$serverFileContent = [ConfigurationManager]::LoadServerConfigFile("ARMControls.json");
					$checkExtensionFile = $true
				}
				else
				{
					$serverFileContent = [ConfigurationHelper]::InvokeControlsAPI($ARMControlsFileURI, '', '', '');
				}
	        }
	    }
	   catch
	   {
         try
         {
            $serverFileContent = [ConfigurationHelper]::InvokeControlsAPI($ARMControlsFileURI, '', '', '');
         }
         catch
         {
         # No Need to break Execution
		 # Load Offline File
         }
	   }
	   if($null -eq $serverFileContent)
	   {
	     $serverFileContent = [ConfigurationHelper]::LoadOfflineConfigFile("ARMControls.json", $false);
	   }
	   #Check if extension file is present on server
	   $extFileName = "ARMControls.ext.json"
	   $extFileContent = $null
	   $usePolicyStore = [ConfigurationManager]::GetAzSKSettings().UseOnlinePolicyStore
	   $policyStoreUrlOrFolder = [ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl
	   $useAADAuthForPolicyStore = [ConfigurationManager]::GetAzSKSettings().EnableAADAuthForOnlinePolicyStore
	   #Check if not in local policy debug mode then get .ext.json file from server.
	   if(-not [ConfigurationHelper]::LocalPolicyEnabled) 
	   {
			if($checkExtensionFile -eq $true)
			{
			   $extFileContent = [ConfigurationManager]::LoadServerFileRaw($extFileName);
			}
	   }
	   #Check if there is an .ext.json file in local org policy folder
	   elseif ([ConfigurationHelper]::IsPolicyPresentOnServer($extFileName, $usePolicyStore, $policyStoreUrlOrFolder, $useAADAuthForPolicyStore))
	   {
		   Write-Warning "########## Looking for [$extFileName] locally..... ##########"
		   $extFileContent = [ConfigurationHelper]::LoadOfflineConfigFile($extFileName, <#$parseJson#> $true, $policyStoreUrlOrFolder)
	   }	  
	   if($null -ne $extFileContent ){
		$serverFileContent = $this.MergeExtensionFile($serverFileContent, $extFileContent )
	   }
	   $serverFileContent= $serverFileContent | ConvertTo-Json -Depth 10
	   return $serverFileContent;
	}

	hidden [boolean] LoadControlSettingsFile([Boolean] $UseBaselineControls, [Boolean] $UsePreviewBaselineControls)
	{ 	
			
		if($UseBaselineControls -eq $true -or $UsePreviewBaselineControls -eq $true){
			# Fetch control Settings data
			$ControlSettings = $null
			if(-not [ConfigurationManager]::GetLocalAzSKSettings().EnableAADAuthForOnlinePolicyStore)
			{
				$ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");
			}
			else 
			{
				$AzureContext = Get-AzContext
				if(-not [string]::IsNullOrWhiteSpace($AzureContext)) 
				{
					$ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");
				}
				else
				{
					Write-Host "No Azure login found. Azure login context is required to fetch baseline controls defined for this policy." -ForegroundColor Red 
					# return true if EnableAADAuthForOnlinePolicyStore is true but Az login context is null
					return $true
				}
			}
			# Filter control list for baseline controls
			$baselineControlList = @();
			if($UseBaselineControls)
			{
				if([Helpers]::CheckMember($ControlSettings ,"BaselineControls.ResourceTypeControlIdMappingList"))
				{
					$baselineControlList += $ControlSettings.BaselineControls.ResourceTypeControlIdMappingList | Select-Object ControlIds | ForEach-Object {  $_.ControlIds }
				}
			
			}
			# Filter control list for preview baseline controls
			$previewBaselineControls = @();
			if($UsePreviewBaselineControls)
			{
				if([Helpers]::CheckMember($ControlSettings,"PreviewBaselineControls.ResourceTypeControlIdMappingList") )
				{
					$previewBaselineControls += $ControlSettings.PreviewBaselineControls.ResourceTypeControlIdMappingList | Select-Object ControlIds | ForEach-Object {  $_.ControlIds }
				}
				$baselineControlList += $previewBaselineControls
			}

			if($baselineControlList -and $baselineControlList.Count -gt 0)
			{
				$this.BaselineControls += $baselineControlList
				
			}
			else
			{
				Write-Host "There are no baseline/preview-baseline controls defined for your org." -ForegroundColor Yellow 
				$this.BaselineControls = @()
			}
		}
		else
		{
			$this.BaselineControls = @()
		}
		return $false
	}
}