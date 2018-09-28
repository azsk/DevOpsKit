Set-StrictMode -Version Latest 
class WritePsConsole: FileOutputBase
{
    hidden static [WritePsConsole] $Instance = $null;
	hidden [string] $SummaryMarkerText = "------";
    static [WritePsConsole] GetInstance()
    {
        if ($null -eq  [WritePsConsole]::Instance)
        {
            [WritePsConsole]::Instance = [WritePsConsole]::new();
        }

        return [WritePsConsole]::Instance
    }

    [void] RegisterEvents()
    {        
        $this.UnregisterEvents();

		# Mandatory: Generate Run Identifier Event
        $this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
                $currentInstance.SetRunIdentifier([AzSKRootEventArgument] ($Event.SourceArgs | Select-Object -First 1));                         
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });
			
		
		$this.RegisterEvent([AzSKGenericEvent]::CustomMessage, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
				if($Event.SourceArgs)
				{
					$messages = @();
					$messages += $Event.SourceArgs;
					$messages | ForEach-Object {
						$currentInstance.WriteMessageData($_);
					}
				}
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

		$this.RegisterEvent([AzSKGenericEvent]::Exception, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
				$exceptionObj = $Event.SourceArgs | Select-Object -First 1
				#if(($null -ne $exceptionObj) -and  ($null -ne $exceptionObj.Exception) -and (-not [String]::IsNullOrEmpty($exceptionObj.Exception.Message)))
				#{
				#	$currentInstance.WriteMessage($exceptionObj.Exception.Message, [MessageType]::Error);
				#	Write-Debug $exceptionObj
				#}
				#else
				#{
					$currentInstance.WriteMessage($exceptionObj, [MessageType]::Error);                       
				#}
            }
            catch 
            {
				#Consuming the exception intentionally to prevent infinite loop of errors
                #$currentInstance.PublishException($_);
            }
        });
		

		$this.RegisterEvent([AzSKRootEvent]::CustomMessage, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
				if($Event.SourceArgs -and $Event.SourceArgs.Messages)
				{
					$Event.SourceArgs.Messages | ForEach-Object {
						$currentInstance.WriteMessageData($_);
					}
				}
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });
		
		$this.RegisterEvent([AzSKRootEvent]::CommandStarted, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
				$currentInstance.CommandStartedAction($Event);
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

		$this.RegisterEvent([AzSKRootEvent]::CommandError, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
				$currentInstance.WriteMessage($Event.SourceArgs.ExceptionMessage, [MessageType]::Error);  
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

        $this.RegisterEvent([AzSKRootEvent]::CommandCompleted, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
				$currentInstance.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Info)
				$currentInstance.WriteMessage("Logs have been exported to: '$([WriteFolderPath]::GetInstance().FolderPath)'", [MessageType]::Info)
				$currentInstance.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Info)
				
				$currentInstance.FilePath = "";
			}
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });
        
        $this.RegisterEvent([AzSKRootEvent]::CommandCompleted, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
				$messages = $Event.SourceArgs.Messages;
				if(($messages | Measure-Object).Count -gt 0 -and $Event.SourceArgs.Messages[0].Message -eq "RecommendationData")
				{
					$reportObject = [RecommendedSecurityReport] $Event.SourceArgs.Messages[0].DataObject;
					$currentInstance.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Info)
					$currentInstance.WriteMessage("Current Combination", [MessageType]::Info)
					$currentInstance.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Info)
					if([string]::IsNullOrWhiteSpace($reportObject.ResourceGroupName))
					{
						$currentInstance.WriteMessage("ResourceGroup Name: Not Specified", [MessageType]::Default);	
					}
					else {
						$currentInstance.WriteMessage("ResourceGroup Name: [$($reportObject.ResourceGroupName)]", [MessageType]::Default);
					}

					if(($reportObject.Input.Features | Measure-Object).Count -le 0)
					{
						$currentInstance.WriteMessage("Features: Not Specified", [MessageType]::Default);
					}
					else {
						$featuresString = [String]::Join(",", $reportObject.Input.Features);
						$currentInstance.WriteMessage("Features: [$featuresString]", [MessageType]::Default);
					}

					if(($reportObject.Input.Categories | Measure-Object).Count -le 0)
					{
						$currentInstance.WriteMessage("Categories: Not Specified", [MessageType]::Default);
					}
					else {
						$categoriesString = [String]::Join(",", $reportObject.Input.Categories);
						$currentInstance.WriteMessage("Categories: [$categoriesString]", [MessageType]::Default);
					}
					$currentInstance.WriteMessage([Constants]::UnderScoreLineLine, [MessageType]::Info)					
					$currentInstance.WriteMessage("Analysis & Recommendations:", [MessageType]::Info);
					$currentInstance.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Info);
					$currentInstance.WriteMessage("Analysis of current feature group:", [MessageType]::Info);
					if($null -ne $reportObject.Recommendations.CurrentFeatureGroup)
					{
						$currentInstance.WriteMessage("Current Group Ranking: $($reportObject.Recommendations.CurrentFeatureGroup.Ranking)", [MessageType]::Default);
						$currentInstance.WriteMessage("No. of instances with same combination: $($reportObject.Recommendations.CurrentFeatureGroup.TotalOccurances)", [MessageType]::Default);
						$featuresString = [String]::Join(",", $reportObject.Recommendations.CurrentFeatureGroup.Features);
						$currentInstance.WriteMessage("Current Combination Features: $featuresString", [MessageType]::Default);
						$categoriesString = [String]::Join(",", $reportObject.Recommendations.CurrentFeatureGroup.Categories);
						$currentInstance.WriteMessage("Current Combination Categories: $categoriesString", [MessageType]::Default);
						$currentInstance.WriteMessage("Measures: [Total Pass#: $($reportObject.Recommendations.CurrentFeatureGroup.TotalSuccessCount)] [Total Fail#: $($reportObject.Recommendations.CurrentFeatureGroup.TotalFailCount)] ", [MessageType]::Default);																		
					}
					else {
						$currentInstance.WriteMessage("Cannot find exact matching combination for the current user input.", [MessageType]::Default);
					}
					$currentInstance.WriteMessage([Constants]::SingleDashLine, [MessageType]::Info);
					$currentInstance.WriteMessage("Recommendations based on categories:", [MessageType]::Info);
					if(($reportObject.Recommendations.RecommendedFeatureGroups | Measure-Object).Count -gt 0)
					{
						$orderedRecommendations = $reportObject.Recommendations.RecommendedFeatureGroups | Sort-Object -Property Ranking
						$orderedRecommendations | ForEach-Object {
							$recommendation = $_;
							$currentInstance.WriteMessage("Category Group Ranking: $($recommendation.Ranking)", [MessageType]::Default);
							$currentInstance.WriteMessage("No. of instances with same combination: $($recommendation.TotalOccurances)", [MessageType]::Default);
							$featuresString = [String]::Join(",", $recommendation.Features);
							$currentInstance.WriteMessage("Feature 	combination: $featuresString", [MessageType]::Default);
							$categoriesString = [String]::Join(",", $recommendation.Categories);
							$currentInstance.WriteMessage("Category Combination: $categoriesString", [MessageType]::Default);
							$currentInstance.WriteMessage("Measures: [Total Pass#: $($recommendation.TotalSuccessCount)] [Total Fail#: $($recommendation.TotalFailCount)] ", [MessageType]::Default);																		
							$currentInstance.WriteMessage([Constants]::SingleDashLine, [MessageType]::Info);
						}
					}

					$currentInstance.WriteMessage(($dataObject | ConvertTo-Json -Depth 10), [MessageType]::Info)
				}
				else {
					$currentInstance.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Info)
					$currentInstance.WriteMessage("Logs have been exported to: '$([WriteFolderPath]::GetInstance().FolderPath)'", [MessageType]::Info)
					$currentInstance.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Info)	
				}								
				$currentInstance.FilePath = "";
			}
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

		# SVT events
		$this.RegisterEvent([SVTEvent]::CommandStarted, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
				$currentInstance.CommandStartedAction($Event);
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });
		
		$this.RegisterEvent([SVTEvent]::CommandError, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
				$currentInstance.WriteMessage($Event.SourceArgs.ExceptionMessage, [MessageType]::Error);  
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

        $this.RegisterEvent([SVTEvent]::CommandCompleted, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
				if(($Event.SourceArgs | Measure-Object).Count -gt 0)
				{
					$controlsScanned = ($Event.SourceArgs.ControlResults|Where-Object{$_.VerificationResult -ne[VerificationResult]::NotScanned}|Measure-Object).Count -gt 0
					if($controlsScanned)
					{
						# Print summary
						$currentInstance.PrintSummaryData($Event);
					}
					
					$AttestControlParamFound = $currentInstance.InvocationContext.BoundParameters["AttestControls"];
					if($null -eq $AttestControlParamFound -and $controlsScanned)
					{
						$currentInstance.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Info)
						$currentInstance.WriteMessage([Constants]::RemediationMsg, [MessageType]::Info)
						$currentInstance.WriteMessage([Constants]::AttestationReadMsg + [ConfigurationManager]::GetAzSKConfigData().AzSKRGName, [MessageType]::Info)
						
					}
					$currentInstance.WriteMessage([Constants]::SingleDashLine, [MessageType]::Info)
				}

				$currentInstance.WriteMessage("Status and detailed logs have been exported to path - $([WriteFolderPath]::GetInstance().FolderPath)", [MessageType]::Info)
				$currentInstance.WriteMessage([Constants]::DoubleDashLine, [MessageType]::Info)
				
				$currentInstance.FilePath = "";
			}
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

		$this.RegisterEvent([SVTEvent]::EvaluationStarted, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
                if($Event.SourceArgs.IsResource())
				{
					$startHeading = ([Constants]::ModuleStartHeading -f $Event.SourceArgs.FeatureName, $Event.SourceArgs.ResourceContext.ResourceGroupName, $Event.SourceArgs.ResourceContext.ResourceName);
				}
				else
				{
					$startHeading = ([Constants]::ModuleStartHeadingSub -f $Event.SourceArgs.FeatureName, $Event.SourceArgs.SubscriptionContext.SubscriptionName, $Event.SourceArgs.SubscriptionContext.SubscriptionId);					
				}
                $currentInstance.WriteMessage($startHeading, [MessageType]::Info);
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

        $this.RegisterEvent([SVTEvent]::EvaluationCompleted, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
				if($Event.SourceArgs -and $Event.SourceArgs.Count -ne 0)
				{
					$props = $Event.SourceArgs[0];
					if($props.IsResource())
					{
						$currentInstance.WriteMessage(([Constants]::CompletedAnalysis  -f $props.FeatureName, $props.ResourceContext.ResourceGroupName, $props.ResourceContext.ResourceName), [MessageType]::Update);
					}
					else
					{
						$currentInstance.WriteMessage(([Constants]::CompletedAnalysisSub  -f $props.FeatureName, $props.SubscriptionContext.SubscriptionName, $props.SubscriptionContext.SubscriptionId), [MessageType]::Update);
					}
				}
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

		$this.RegisterEvent([SVTEvent]::EvaluationError, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
				$currentInstance.WriteMessage($Event.SourceArgs.ExceptionMessage, [MessageType]::Error);  
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

      	$this.RegisterEvent([SVTEvent]::ControlStarted, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
				if($Event.SourceArgs.IsResource())
				{
					$AnalysingControlHeadingMsg =([Constants]::AnalysingControlHeading  -f $Event.SourceArgs.FeatureName, $Event.SourceArgs.ControlItem.Description,$Event.SourceArgs.ResourceContext.ResourceName)
				}
				else
				{
					$AnalysingControlHeadingMsg =([Constants]::AnalysingControlHeadingSub  -f $Event.SourceArgs.FeatureName, $Event.SourceArgs.ControlItem.Description,$Event.SourceArgs.SubscriptionContext.SubscriptionName)
				}
				$currentInstance.WriteMessage($AnalysingControlHeadingMsg, [MessageType]::Info)                             
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });
		
		$this.RegisterEvent([SVTEvent]::ControlDisabled, {
            $currentInstance = [WritePsConsole]::GetInstance();
            try 
            {
                $currentInstance.WriteMessage(("**Disabled**: [{0}]-[{1}]" -f 
                        $Event.SourceArgs.FeatureName, 
                        $Event.SourceArgs.ControlItem.Description), [MessageType]::Warning);    
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });
    }

        #Write message on powershell console with appropriate color
    [void] WriteMessage([PSObject] $message, [MessageType] $messageType)
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

		# FilePath check ensures to print detailed error objects on PS host
		$formattedMessage = [Helpers]::ConvertObjectToString($message, (-not [string]::IsNullOrEmpty($this.FilePath)));		
        Write-Host $formattedMessage -ForegroundColor $colorCode
		#if($message.GetType().FullName -eq "System.Management.Automation.ErrorRecord")
		#{
		$this.AddOutputLog([Helpers]::ConvertObjectToString($message, $false));
		#}
		#else
		#{
		#	$this.AddOutputLog($message);
		#}
    }
	
	hidden [void] WriteMessage([PSObject] $message)
    {
		$this.WriteMessage($message, [MessageType]::Info);
	}

	hidden [void] WriteMessageData([MessageData] $messageData)
	{
		if($messageData)
		{
			$this.WriteMessage(("`r`n" + $messageData.Message), $messageData.MessageType);       
			if($messageData.DataObject)
			{
				#if (-not [string]::IsNullOrEmpty($messageData.Message)) 
				#{
				#	$this.WriteMessage("`r`n");
				#}

				$this.WriteMessage($messageData.DataObject, $messageData.MessageType);       
			}
		}
	}

	hidden [void] AddOutputLog([string] $message, [bool] $includeTimeStamp)   
    {
        if([string]::IsNullOrEmpty($message) -or [string]::IsNullOrEmpty($this.FilePath))
        {
            return;
        }
             
        if($includeTimeStamp)
        {
            $message = (Get-Date -format "MM\/dd\/yyyy HH:mm:ss") + "-" + $message
        }

        Add-Content -Value $message -Path $this.FilePath        
    } 
	    
	hidden [void] AddOutputLog([string] $message)   
    {
       $this.AddOutputLog($message, $false);  
    } 

	hidden [void] PrintSummaryData($event)
	{
		[SVTSummary[]] $summary = @();
		$event.SourceArgs | ForEach-Object {
			$item = $_
			if ($item -and $item.ControlResults)
			{
				$item.ControlResults | ForEach-Object{
					$summary += [SVTSummary]@{
						VerificationResult = $_.VerificationResult;
						ControlSeverity = $item.ControlItem.ControlSeverity;
					};
				};
			}
		};

		if($summary.Count -ne 0)
		{
			$summaryResult = @();

			$severities = @();
			$severities += $summary | Select-Object -Property ControlSeverity | Select-Object -ExpandProperty ControlSeverity -Unique;

			$verificationResults = @();
			$verificationResults += $summary | Select-Object -Property VerificationResult | Select-Object -ExpandProperty VerificationResult -Unique;

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

				$summary | Group-Object -Property ControlSeverity | ForEach-Object {
					$item = $_;
					$summaryItem = $summaryResult | Where-Object { $_.Summary -eq $item.Name } | Select-Object -First 1;
					if($summaryItem)
					{
						$summaryItem.Total = $_.Count;
						if($totalRow)
						{
							$totalRow.Total += $_.Count
						}
						$item.Group | Group-Object -Property VerificationResult | ForEach-Object {
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
							$markerRow.$propName = $this.SummaryMarkerText;				
						}
					};
				if($summaryResult.Count -ne 0)
				{		
					$this.WriteMessage(($summaryResult | Format-Table | Out-String), [MessageType]::Info)
				}
			}
		}
	}

	hidden [void] CommandStartedAction($event)
	{
		$arg = $event.SourceArgs | Select-Object -First 1;
	
		$this.SetFilePath($arg.SubscriptionContext, [FileOutputBase]::ETCFolderPath, "PowerShellOutput.LOG");  	
		
		$currentVersion = $this.GetCurrentModuleVersion();
		$moduleName = $this.GetModuleName();
		$methodName = $this.InvocationContext.InvocationName;
        $verbndnoun = $methodName.Split('-')
	    $aliasName = [CommandHelper]::Mapping | Where {$_.Verb -eq $verbndnoun[0] -and $_.Noun -eq $verbndnoun[1] }

		$this.WriteMessage([Constants]::DoubleDashLine + "`r`n$moduleName Version: $currentVersion `r`n" + [Constants]::DoubleDashLine , [MessageType]::Info);      
		# Version check message
		if($arg.Messages)
		{
			$arg.Messages | ForEach-Object {
				$this.WriteMessageData($_);
			}
		}
        
        if($aliasName)
        {
            $aliasName = $aliasName.ShortName 
            
            #Get List of parameters used with short alias
			$paramlist = @()
			$paramlist = $this.GetParamList()
            
            #Get command with short alias
            $cmID = $this.GetShortCommand($aliasName,$paramlist);

            $this.WriteMessage("Method Name: $methodName ($aliasName)`r`nInput Parameters: $(($paramlist | Out-String).TrimEnd()) `r`n`nYou can also use: $cmID `r`n" + [Constants]::DoubleDashLine , [MessageType]::Info);
        }
        else
        {
            $this.WriteMessage("Method Name: $methodName `r`nInput Parameters: $(($this.InvocationContext.BoundParameters | Out-String).TrimEnd()) `r`n" + [Constants]::DoubleDashLine , [MessageType]::Info);                           
        }
		

		$this.WriteMessage([ConfigurationManager]::GetAzSKConfigData().PolicyMessage,[MessageType]::Warning)
		
	}

	hidden [string] GetShortCommand($aliasName,$paramlist)
	{
		$aliasshort = $aliasName.ToLower()
            $cmID = "$aliasshort "
            #Looping on parameters and adding them to the short alias with key and value and if no alias found adding it as it is
            foreach($item in $paramlist)
            {
                $ky = $item.Alias
                $vl = $item.Value

				if($vl -eq $true)
                {
                    $vl = ""
                }
                if($ky)
                {
                    $cmID += "-$ky $vl "
                }
                else
                {
                    $ky = $item.Name
                    $cmID += "-$ky $vl "
                }
            }
		return $cmID;
	}

	hidden [psobject] GetParamList()
	{
		$paramlist = @()
            #Looping on parameters and creating list of smallest alias and creating parameter detail object
            $this.InvocationContext.BoundParameters.Keys | % {
                $key = $this.InvocationContext.MyCommand.Parameters.$_.Aliases #| Where {$_.Length -lt 5}
                $key = $key | sort length -Descending | select -Last 1
                $val = $this.InvocationContext.BoundParameters[$_]

                $myObject = New-Object System.Object

                $myObject | Add-Member -type NoteProperty -name Name -Value $_
                $myObject | Add-Member -type NoteProperty -name Alias -Value $key
                $myObject | Add-Member -type NoteProperty -name Value -Value $val

                $paramlist += $myObject
            }
		return $paramlist;
	}

}

class SVTSummary
{
    [VerificationResult] $VerificationResult = [VerificationResult]::Manual;
    [ControlSeverity] $ControlSeverity = [ControlSeverity]::High;
}
