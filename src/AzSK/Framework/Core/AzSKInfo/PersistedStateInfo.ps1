using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class PersistedStateInfo: AzCommandBase
{    
	
	hidden [PSObject] $AzSKRG = $null
	hidden [String] $AzSKRGName = ""


	PersistedStateInfo([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext) 
    { 
		#$this.DoNotOpenOutputFolder = $true;
		$this.AzSKRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		$this.AzSKRG = Get-AzResourceGroup -Name $this.AzSKRGName -ErrorAction SilentlyContinue
	}
	

	[MessageData[]] UpdatePersistedState([string] $filePath)
    {	
	    [string] $errorMessages="";
	    $customErrors=@();
	    [MessageData[]] $messages = @();
	   
		try
		{
			$azskConfig = [ConfigurationManager]::GetAzSKConfigData();	
			$successCount = 0;
			$totalCount = 0;
			$settingStoreComplianceSummaryInUserSubscriptions = [ConfigurationManager]::GetAzSKSettings().StoreComplianceSummaryInUserSubscriptions;
			#return if feature is turned off at server config
			if(-not $azskConfig.StoreComplianceSummaryInUserSubscriptions -and -not $settingStoreComplianceSummaryInUserSubscriptions) 	
			{
				$this.PublishCustomMessage("NOTE: This feature is currently disabled in your environment. Please contact the cloud security team for your org.", [MessageType]::Warning);	
				return $messages;
			} 
			# if IsComplianceStateCachingEnabled is false, return message indicating Compliance state table caching is disabled by default	
			if(!$this.IsComplianceStateCachingEnabled)
        	{
            	$this.PublishCustomMessage([Constants]::ComplianceInfoCachingDisabled, [MessageType]::Warning);	
            	return $messages;
        	}
			#Check for file path exist
			if(-not (Test-Path -path $filePath))
			{  
				$this.PublishCustomMessage("Could not find file: [$filePath]. `nPlease rerun the command with correct path.", [MessageType]::Error);
				return $messages;
			}
			# Read Local CSV file
            [CsvOutputItem[]] $controlResultSet  =@();
			$controlResultSet = Get-ChildItem -Path $filePath -Filter '*.csv' -Force | Get-Content | Convertfrom-csv
			#pick only those controls whose usercomments has been updated
			$controlResultSet = $controlResultSet | Where-Object {$_.FeatureName -ne "AzSKCfg" -and -not [string]::IsNullOrWhiteSpace($_.UserComments)}
			$erroredControls = @();
			$totalCount = ($controlResultSet | Measure-Object).Count;
			$invalidUserComments = $controlResultSet | Where-Object { $_.UserComments.length -gt 255} 
			if(($invalidUserComments | Measure-Object).Count -eq 0)
			{
				if(($invalidUserComments | Measure-Object).Count -eq $totalCount )
				{
					$this.PublishCustomMessage("Could not find any control in file with usercomments: [$filePath].",[MessageType]::Error);
					return $messages;
				}
				else {
					$scannedResources = $controlResultSet | Group-Object -Property ResourceId 
					# Read file from Storage
					$complianceReportHelper = [ComplianceReportHelper]::new($this.SubscriptionContext, $this.GetCurrentModuleVersion()); 
					$PersistedScanControls =$null;
					# Check for write access
					if($complianceReportHelper.HaveRequiredPermissions() -eq 1)
					{
						[ComplianceStateTableEntity[]] $PersistedScanControls = $complianceReportHelper.GetSubscriptionComplianceReport();
					}
					else
					{
						$this.PublishCustomMessage("You don't have the required permissions to update user comments. If you'd like to update user comments, please request your subscription owner to grant you 'Contributor' access to the DevOps Kit resource group.", [MessageType]::Warning);
						return $messages;
					}
					[ComplianceStateTableEntity[]] $UpdatedPersistedControls = @();
					$scannedResources | ForEach-Object {
						$scannedResource = $_
						$scannedResource.Group | ForEach-Object {
							try {
								$control = $_;
								$partsToHash = $scannedResource.Name;
								$partitionKey = [Helpers]::ComputeHash($partsToHash.ToLower());
								$filteredPersistedControl = $PersistedScanControls | Where-Object { $_.PartitionKey -eq $partitionKey -and $_.ControlID -eq $control.ControlID}
								if(($filteredPersistedControl | Measure-Object).Count -gt 0)
								{
									$encoder = [System.Text.Encoding]::UTF8
									$encUserComments= $encoder.GetBytes($control.UserComments)
									$encUserCommentsString= $encoder.GetString($encUserComments)
									$filteredPersistedControl.UserComments = $encUserCommentsString
									$UpdatedPersistedControls += $filteredPersistedControl;
									$successCount += 1
								}
								else {
									$erroredControls += $this.CreateCustomErrorObject($control,"Could not find previous persisted state.");
								}				
							}
							catch {
								$this.PublishException($_);
								$erroredControls+=$this.CreateCustomErrorObject($currentItem,"Could not find previous persisted state.")
							}									
						}				
					}

					if(($UpdatedPersistedControls | Measure-Object).Count -gt 0)
					{
						$complianceReportHelper.SetLocalSubscriptionScanReport($UpdatedPersistedControls);												
					}
				}
			}
			else {
				$invalidUserComments | ForEach-Object {
					$erroredControls+=$this.CreateCustomErrorObject($_,"User Comment's length should not exceed 255 characters.")
				}
			}
			
			# If updation failed for any control, genearte error file
			if(($erroredControls | Measure-Object).Count -gt 0)
			{
				$nonNullProps=@();
				[CsvOutputItem].GetMembers() | Where-Object { $_.MemberType -eq [System.Reflection.MemberTypes]::Property } | ForEach-Object {
					$propName = $_.Name;
					if(($erroredControls | Where-object { -not [string]::IsNullOrWhiteSpace($_.$propName) } | Measure-object).Count -ne 0)
					{
						$nonNullProps += $propName;
					}
				};
				$nonNullProps += "ErrorDetails"
				$csvItems = $erroredControls | Select-Object -Property $nonNullProps
				$controlCSV = New-Object -TypeName WriteCSVData
				$controlCSV.FileName = "Controls_NotUpdated_" + $this.RunIdentifier
				$controlCSV.FileExtension = 'csv'
				$controlCSV.FolderPath = ''
				$controlCSV.MessageData = $csvItems
				$this.PublishAzSKRootEvent([AzSKRootEvent]::WriteCSV, $controlCSV);
				$this.PublishCustomMessage("[$successCount/$totalCount] user comments have been updated successfully.", [MessageType]::Update);
				$this.PublishCustomMessage("[$(($erroredControls | Measure-Object).Count)/$totalCount] user comments could not be updated due to an error. See the log file for details.", [MessageType]::Warning);
			}
			else
			{
				$this.PublishCustomMessage("All User Comments have been updated successfully.", [MessageType]::Update);
			}
		}
		catch
		{
			$this.PublishEvent([AzSKGenericEvent]::Exception, "Unable to update user comments. Could not find previous persisted state in DevOps Kit storage.");
			$this.PublishException($_);
		}
		return $messages;
	}

	hidden [PSObject] CreateCustomErrorObject($currentItem,$reason)
	{
		$currentItem | Add-Member -NotePropertyName ErrorDetails -NotePropertyValue $reason
		return $currentItem;
	}
}

