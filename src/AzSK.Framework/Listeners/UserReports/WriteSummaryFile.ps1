Set-StrictMode -Version Latest 
class WriteSummaryFile: FileOutputBase
{   
    hidden static [WriteSummaryFile] $Instance = $null;

    static [WriteSummaryFile] GetInstance()
    {
        if ( $null -eq  [WriteSummaryFile]::Instance)
        {
            [WriteSummaryFile]::Instance = [WriteSummaryFile]::new();
        }
    
        return [WriteSummaryFile]::Instance
    }

    [void] RegisterEvents()
    {
        $this.UnregisterEvents();       

        $this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
            $currentInstance = [WriteSummaryFile]::GetInstance();
            try 
            {
                $currentInstance.SetRunIdentifier([AzSKRootEventArgument] ($Event.SourceArgs | Select-Object -First 1));            
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

        $this.RegisterEvent([SVTEvent]::CommandStarted, {
            $currentInstance = [WriteSummaryFile]::GetInstance();
            try 
            {
                $currentInstance.SetFilePath($Event.SourceArgs.SubscriptionContext, ("SecurityReport-" + $currentInstance.RunIdentifier + ".csv"));
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });
        
        $this.RegisterEvent([SVTEvent]::CommandCompleted, {
            $currentInstance = [WriteSummaryFile]::GetInstance();
			
			if(($Event.SourceArgs.ControlResults|Where-Object{$_.VerificationResult -ne[VerificationResult]::NotScanned}|Measure-Object).Count -gt 0)
			{
				$currentInstance.SetFilePath($Event.SourceArgs[0].SubscriptionContext, ("SecurityReport-" + $currentInstance.RunIdentifier + ".csv"));
			}
			else
			{
				# While running GAI -InfoType AttestationInfo, no controls are evaluated. So the value of VerificationResult is by default NotScanned for all controls.
				# In that case the csv file should be renamed to AttestationReport.
				$currentInstance.SetFilePath($Event.SourceArgs[0].SubscriptionContext, ("AttestationReport-" + $currentInstance.RunIdentifier + ".csv"));
			}

			# Export CSV Report
			try 
			{
				$currentInstance.WriteToCSV($Event.SourceArgs);
				$currentInstance.FilePath = "";
			}
			catch 
			{
				$currentInstance.PublishException($_);
			}

        });

        $this.RegisterEvent([AzSKRootEvent]::UnsupportedResources, {
            $currentInstance = [WriteSummaryFile]::GetInstance();
            try 
            {
				$message = $Event.SourceArgs.Messages | Select-Object -First 1
				if($message -and $message.DataObject)
				{
					$filePath = $currentInstance.CalculateFilePath($Event.SourceArgs.SubscriptionContext, [FileOutputBase]::ETCFolderPath, ("UnsupportedResources-" + $currentInstance.RunIdentifier + ".csv.LOG"));
					$message.DataObject | Export-Csv $filePath -NoTypeInformation
                }
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

		$this.RegisterEvent([AzSKRootEvent]::WriteCSV, {
            $currentInstance = [WriteSummaryFile]::GetInstance();
            try 
            {
				$fileName = 'Control Details';
				$folderPath = '';
				$fileExtension = 'csv';

				$message = $Event.SourceArgs.Messages | Select-Object -First 1
				if($message -and $message.DataObject)
				{
					if(-not [string]::IsNullOrEmpty($message.DataObject.FileName))
					{
						$fileName = $message.DataObject.FileName
					}
					if(-not [string]::IsNullOrEmpty($message.DataObject.FolderPath))
					{
						$folderPath = $message.DataObject.FolderPath
					}
					if(-not [string]::IsNullOrEmpty($message.DataObject.FileExtension))
					{
						$fileExtension = $message.DataObject.FileExtension
					}
						
					$filePath = $currentInstance.CalculateFilePath($Event.SourceArgs.SubscriptionContext, $folderPath, ($fileName + "." + $fileExtension));
					$message.DataObject.MessageData | Export-Csv $filePath -NoTypeInformation
                }
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
		});
		# Event for Writing File Detailed Log
		$this.RegisterEvent([AzSKRootEvent]::WriteExcludedResources,{
			$currentInstance = [WriteSummaryFile]::GetInstance();
            try 
            {
				$message = $Event.SourceArgs.Messages | Select-Object -First 1
				$printMessage="";
				if($message -and $message.DataObject)
				{
					$filePath = $currentInstance.CalculateFilePath($Event.SourceArgs.SubscriptionContext, [FileOutputBase]::ETCFolderPath, ("ExcludedResources-" + $currentInstance.RunIdentifier + ".txt.LOG"));
					
					$ExcludedType = $message.DataObject.ExcludedResourceType
					if($ExcludedType -eq 'All')
					{
						$ExcludedType = 'None'
					}
					$ExcludedRGs = $message.DataObject.ExcludedResourceGroupNames
					
					$ExcludeResourceName = $message.DataObject.ExcludeResourceNames
					$ExcludedResources = $message.DataObject.ExcludedResources  
					$ExcludedRGsResources = $ExcludedResources | Where-Object {$_.ResourceGroupName -in $ExcludedRGs}
					$ExcludedTypeResources = $ExcludedResources | Select-Object -ExpandProperty ResourceTypeMapping |Where-Object {$_.ResourceTypeName -in $ExcludedType}
					$ExplicitlyExcludedResource =$ExcludedResources| Where-Object {$_.ResourceName -in $ExcludeResourceName}
					$printMessage += [Constants]::DoubleDashLine +"`r`nNumber of resource groups excluded: $(($ExcludedRGs | Measure-Object).Count | Out-String)"
					$printMessage += "`r`nNumber of resources excluded: $(($ExcludedResources | Measure-Object).Count | Out-String)"
					$printMessage += "`r`n`nDistribution of resources being excluded is as follows:"+"`r`n"+[Constants]::SingleDashLine
					$printMessage += "`r`nNumber of resources excluded due to excluding resource groups: $(($ExcludedRGsResources | Measure-Object).Count | Out-String)"
					$printMessage += "`r`nNumber of resources excluded due to excluding resource type '$ExcludedType': $(($ExcludedTypeResources | Measure-Object).Count | Out-String)"
					$printMessage += "`r`nNumber of resources excluded explicitly: $(($ExplicitlyExcludedResource| Measure-Object).Count|Out-String)"
					$printMessage += "`r`n"+[Constants]::SingleDashLine +"`r`n"+[Constants]::DoubleDashLine+"`r`nFollowing are the list of resource groups and resources being excluded" 
					$printMessage += "`r`n"+[Constants]::SingleDashLine+"`r`nResource groups excluded:"
					$detailedList += "`r`n-------------------------"
					if(($ExcludedRGs | Measure-Object).Count -gt 0)
					{
						$detailedList +="`r`n$($ExcludedRGS |Sort-Object|Format-Table |Out-String)"
					}
					else 
					{
						$detailedList += "`r`n N/A"
					}
					$detailedList += "`r`nResources excluded:"
					$detailedList += "`r`n-------------------------"
					if(($ExcludedResources | Measure-Object).Count -gt 0)
					{
						$detailedList += "`r`n$($ExcludedResources| Sort-Object -Property "ResourceGroupName"|Select-Object -Property ResourceName,ResourceGroupName -ExpandProperty ResourceTypeMapping| Select-Object  -Property ResourceName,ResourceGroupName,ResourceTypeName,ResourceType|Format-Table | Out-String)"
					}
					else 
					{
						$detailedList += "`r`n N/A"						
					}
					$printMessage += $detailedList
					
					Add-Content -Value $printMessage -Path $filePath 
												
				}
				
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
		});
	}
	
	

   [void] WriteToCSV([SVTEventContext[]] $arguments)
    {
        if ([string]::IsNullOrEmpty($this.FilePath)) {
            return;
        }
        [CsvOutputItem[]] $csvItems = @();
		$anyAttestedControls = $null -ne ($arguments | 
			Where-Object { 
				$null -ne ($_.ControlResults | Where-Object { $_.AttestationStatus -ne [AttestationStatus]::None } | Select-Object -First 1) 
			} | Select-Object -First 1);

		#$anyFixableControls = $null -ne ($arguments | Where-Object { $_.ControlItem.FixControl } | Select-Object -First 1);
		#Validate if preview baseline control flag is passed to mark csv
		$UsePreviewBaselineControls = $false
		if($this.InvocationContext.BoundParameters['UsePreviewBaselineControls'] -eq $True)
		{
			[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
			$previewBaselineControlsDetails = $partialScanMngr.GetPreviewBaselineControlDetails()
			if($previewBaselineControlsDetails)
			{
				$UsePreviewBaselineControls =$True
			}
		}
        $arguments | ForEach-Object {
            $item = $_
            if ($item -and $item.ControlResults) {
				

                $item.ControlResults | ForEach-Object{
                    $csvItem = [CsvOutputItem]@{
                        ControlID = $item.ControlItem.ControlID;
                        ControlSeverity = $item.ControlItem.ControlSeverity;
                        Description = $item.ControlItem.Description;
                        FeatureName = $item.FeatureName;
                        ChildResourceName = $_.ChildResourceName;
						Recommendation = $item.ControlItem.Recommendation;	
				
                    };
					if($_.VerificationResult -ne [VerificationResult]::NotScanned)
					{
						$csvItem.Status = $_.VerificationResult.ToString();
					}
					if($this.InvocationContext.BoundParameters['IncludeUserComments'] -eq $True)
					{
                      $csvItem.UserComments=$_.UserComments;	
					}
					#if($anyFixableControls)
					#{
					if($item.ControlItem.FixControl)
					{
						$csvItem.SupportsAutoFix = "Yes";
					}
					else
					{
						$csvItem.SupportsAutoFix = "No";
					}
					#}
					
					if($item.ControlItem.IsBaselineControl)
					{
						$csvItem.IsBaselineControl = "Yes";
					}
					else
					{
						$csvItem.IsBaselineControl = "No";
					}
					if($item.ControlItem.IsPreviewBaselineControl)
					{
						$csvItem.IsPreviewBaselineControl = "Yes";
					}
					else
					{
						$csvItem.IsPreviewBaselineControl = "No";
					}

					if($anyAttestedControls)
					{
						$csvItem.ActualStatus = $_.ActualVerificationResult.ToString();
					}

					if($item.IsResource())
					{
						$csvItem.ResourceName = $item.ResourceContext.ResourceName;
                        $csvItem.ResourceGroupName = $item.ResourceContext.ResourceGroupName;
						$csvItem.ResourceId = $item.ResourceContext.ResourceId;
						$csvItem.DetailedLogFile = "/$([Helpers]::SanitizeFolderName($item.ResourceContext.ResourceGroupName))/$($item.FeatureName).LOG";

						
					}
					else
					{
					    $csvItem.ResourceId = $item.SubscriptionContext.scope;
						$csvItem.DetailedLogFile = "/$([Helpers]::SanitizeFolderName($item.SubscriptionContext.SubscriptionName))/$($item.FeatureName).LOG"
						
					}

					if($_.AttestationStatus -ne [AttestationStatus]::None)
					{
						$csvItem.AttestedSubStatus = $_.AttestationStatus.ToString();
						if($null -ne $_.StateManagement -and $null -ne $_.StateManagement.AttestedStateData)
						{
							$csvItem.AttesterJustification = $_.StateManagement.AttestedStateData.Justification
							$csvItem.AttestedBy =  $_.StateManagement.AttestedStateData.AttestedBy
							if(![string]::IsNullOrWhiteSpace($_.StateManagement.AttestedStateData.ExpiryDate))
							{
								$csvItem.AttestationExpiryDate =  $_.StateManagement.AttestedStateData.ExpiryDate
							}
							if(![string]::IsNullOrWhiteSpace($_.StateManagement.AttestedStateData.AttestedDate))
							{
								$csvItem.AttestedOn=  $_.StateManagement.AttestedStateData.AttestedDate
							}
						}
					}
					#Changes for compliance table dependency removal
    				#removing IsControlInGrace from csv output
					# if($_.IsControlInGrace -eq $true)
					# {
					# 	$csvItem.IsControlInGrace = "Yes"
					# }
					# else 
					# {
					# 	$csvItem.IsControlInGrace = "No"
					# }					
                    $csvItems += $csvItem;
                }                                
            }
        } 

        if ($csvItems.Count -gt 0) {
			# Remove Null properties
			$nonNullProps = @();
			
			[CsvOutputItem].GetMembers() | Where-Object { $_.MemberType -eq [System.Reflection.MemberTypes]::Property } | ForEach-Object {
				$propName = $_.Name;
				if(($csvItems | Where-object { -not [string]::IsNullOrWhiteSpace($_.$propName) } | Measure-object).Count -ne 0)
				{
					$nonNullProps += $propName;
				}
			};
			if($this.InvocationContext.BoundParameters['IncludeUserComments'] -eq $true -and -not ([Helpers]::CheckMember($nonNullProps, "UserComments")))
			{
			  $nonNullProps += "UserComments";
			}
            $csvItems | Select-Object -Property $nonNullProps | Export-Csv $this.FilePath -NoTypeInformation
        }
    }	

}


