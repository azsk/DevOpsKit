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
            try 
            {
                $controlsScanned = ($Event.SourceArgs.ControlResults|Where-Object{$_.VerificationResult -ne[VerificationResult]::NotScanned}|Measure-Object).Count -gt 0
				if(!$controlsScanned)
				{
					$currentInstance.SetFilePath($Event.SourceArgs[0].SubscriptionContext, ("AttestationReport-" + $currentInstance.RunIdentifier + ".csv"));
				}
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
						UserComments=$_.UserComments;					
                    };
					if($_.VerificationResult -ne [VerificationResult]::NotScanned)
					{
						$csvItem.Status = $_.VerificationResult.ToString();
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

					if($_.IsControlInGrace)
					{
						$csvItem.IsControlInGrace = "Yes";
					}
					else
					{
						$csvItem.IsControlInGrace = "No";
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
						}
					}
					
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
			if($this.InvocationContext.BoundParameters['IncludeUserComments'] -ne $null -and $this.InvocationContext.BoundParameters['IncludeUserComments'] -eq $true -and -not ([Helpers]::CheckMember($nonNullProps, "UserComments")))
			{
			  $nonNullProps += "UserComments";
			}
            $csvItems | Select-Object -Property $nonNullProps | Export-Csv $this.FilePath -NoTypeInformation
        }
    }
}

class CsvOutputItem
{
    #Fields from JSON
    [string] $ControlID = ""
    [string] $Status = ""
    [string] $FeatureName = ""
    [string] $ResourceGroupName = ""
    [string] $ResourceName = ""
    [string] $ChildResourceName = ""
    [string] $ControlSeverity = ""
	[string] $IsBaselineControl = ""
    [string] $SupportsAutoFix = ""    
    [string] $Description = ""
	[string] $ActualStatus = ""
	[string] $AttestedSubStatus = ""
	[string] $AttestationExpiryDate = "" 
	[string] $AttestedBy = ""
	[string] $AttesterJustification = ""
    [string] $Recommendation = ""
	[string] $ResourceId = ""
    [string] $DetailedLogFile = ""
	[string] $IsControlInGrace
	[string] $UserComments = ""
}
