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
				# Export CSV Report
				try 
				{
					$currentInstance.SetFilePath($Event.SourceArgs[0].SubscriptionContext, ("AttestationReport-" + $currentInstance.RunIdentifier + ".csv"));
					$currentInstance.WriteToCSV($Event.SourceArgs);
					$currentInstance.FilePath = "";
				}
				catch 
				{
					$currentInstance.PublishException($_);
				}

				# Persist scan data to subscription
				try 
				{
					$currentInstance.PersistScanDataToStorage($Event.SourceArgs, $currentInstance.GetCurrentModuleVersion())
				}
				catch 
				{
					$currentInstance.PublishException($_);
				}
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
			if($this.InvocationContext.BoundParameters['IncludeUserComments'] -eq $true -and -not ([Helpers]::CheckMember($nonNullProps, "UserComments")))
			{
			  $nonNullProps += "UserComments";
			}
            $csvItems | Select-Object -Property $nonNullProps | Export-Csv $this.FilePath -NoTypeInformation
        }
    }

	[void] PersistScanDataToStorage($svtEventContextResults, $scannerVersion)
	{
		$settings = [ConfigurationManager]::GetAzSKConfigData();
		if(-not $settings.PersistScanReportInSubscription) 
		{
			return;
		}

		# ToDo: Can we use here [RemoteReportHelper]??
		$scanSource = [RemoteReportHelper]::GetScanSource();
		$scannerVersion = $scannerVersion

		# ToDo: Need to calculate ScanKind
		#$scanKind = [RemoteReportHelper]::GetServiceScanKind($this.InvocationContext.MyCommand.Name, $this.InvocationContext.BoundParameters);
		$scanKind = [ServiceScanKind]::Partial;

		# ToDo: Need disable comment, should be run while CA
		# ToDo: Resource inventory helper
		# if($scanSource -eq [ScanSource]::Runbook) 
		# { 
			$resources = "" | Select-Object "SubscriptionId", "ResourceGroups"
			$resources.ResourceGroups = [System.Collections.ArrayList]::new()
			# ToDo: cache this properties as AzSKRoot.
			$resourcesFlat = Find-AzureRmResource
			$supportedResourceTypes = [SVTMapping]::GetSupportedResourceMap()
			# Not considering nested resources to reduce complexity
			$filteredResoruces = $resourcesFlat | Where-Object { $supportedResourceTypes.ContainsKey($_.ResourceType.ToLower()) }
			$grouped = $filteredResoruces | Group-Object {$_.ResourceGroupName} | Select-Object Name, Group
			foreach($group in $grouped){
				$resourceGroup = "" | Select-Object Name, Resources
				$resourceGroup.Name = $group.Name
				$resourceGroup.Resources = [System.Collections.ArrayList]::new()
				foreach($item in $group.Group){
					$resource = "" | Select-Object Name, ResourceId, Feature
					if($item.Name.Contains("/")){
						$splitName = $item.Name.Split("/")
						$resource.Name = $splitName[$splitName.Length - 1]
					}
					else{
						$resource.Name = $item.Name;
					}
					$resource.ResourceId = $item.ResourceId
					$resource.Feature = $supportedResourceTypes[$item.ResourceType.ToLower()]
					$resourceGroup.Resources.Add($resource) | Out-Null
				}
				$resources.ResourceGroups.Add($resourceGroup) | Out-Null
			}
		# }
		$subId = $svtEventContextResults[0].SubscriptionContext.SubscriptionId
		$StorageReportHelperInstance = [ComplianceReportHelper]::new($subId);
		$StorageReportHelperInstance.Initialize($true);
		if($StorageReportHelperInstance.HasStorageReportWriteAccessPermissions())
		{
			$finalScanReport = $StorageReportHelperInstance.MergeSVTScanResult($svtEventContextResults, $resources, $scanSource, $scannerVersion, $scanKind)
			$StorageReportHelperInstance.SetLocalSubscriptionScanReport($finalScanReport)
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
	[string] $UserComments = ""
}
