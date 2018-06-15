using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class PersistedStateInfo: CommandBase
{    
	
	hidden [PSObject] $AzSKRG = $null
	hidden [String] $AzSKRGName = ""


	PersistedStateInfo([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext) 
    { 
		#$this.DoNotOpenOutputFolder = $true;
		$this.AzSKRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		$this.AzSKRG = Get-AzureRmResourceGroup -Name $this.AzSKRGName -ErrorAction SilentlyContinue
	}
	

	[MessageData[]] UpdatePersistedState([string] $filePath)
    {	
	    [string] $errorMessages="";
	    $customErrors=@();
	    [MessageData[]] $messages = @();
	   
		try
		{
			$azskConfig = [ConfigurationManager]::GetAzSKConfigData();
			<#if(!$azskConfig.PersistScanReportInSubscription) 
			{
				$this.PublishCustomMessage("NOTE: This feature is currently disabled in your environment. Please contact the cloud security team for your org.", [MessageType]::Warning);	
				return $messages;
			} #>
			#Check for file path exist
			if(-not (Test-Path -path $filePath))
			{  
				$this.PublishCustomMessage("Could not find file: [$filePath]. `nPlease rerun the command with correct path.", [MessageType]::Error);
				return $messages;
			}
			# Read Local CSV file
            [CsvOutputItem[]] $controlResultSet  =@();
			$controlResultSet = Get-ChildItem -Path $filePath -Filter '*.csv' -Force | Get-Content | Convertfrom-csv
            $controlResultSet = $controlResultSet | Where-Object {$_.FeatureName -ne "AzSKCfg"}
			$totalCount = ($controlResultSet | Measure-Object).Count
			if($totalCount -eq 0)
			{
				$this.PublishCustomMessage("Could not find any control in file: [$filePath].",[MessageType]::Error);
				return $messages;
			}
			$resultsGroups = $controlResultSet | Group-Object -Property ResourceId 
			# Read file from Storage
			$complianceReportHelper = [ComplianceReportHelper]::new($this.SubscriptionContext.SubscriptionId); 
			$StorageReportJson =$null;
			# Check for write access
			if($complianceReportHelper.azskStorageInstance.HaveWritePermissions -eq 1)
			{
				[LSRSubscription] $StorageReportJson = $complianceReportHelper.GetLocalSubscriptionScanReport($this.SubscriptionContext.SubscriptionId);
			}
			else
			{
				$this.PublishCustomMessage("You don't have the required permissions to update user comments. If you'd like to update user comments, please request your subscription owner to grant you 'Contributor' access to the DevOps Kit resource group.", [MessageType]::Warning);
				return $messages;
			}
	
			$erroredControls=@();
			$PersistedControlScanResult=@();
			$ResourceData=@();
			$successCount=0;
		
			if($null -ne $StorageReportJson -and $null -ne $StorageReportJson.ScanDetails)
			{
				$this.PublishCustomMessage("Updating user comments in AzSK control data for $totalCount controls... ", [MessageType]::Warning);

				foreach ($resultGroup in $resultsGroups) {
					#count check has been done before itself. Here it is safe to assume atleast one group. resultGroup data is populated from CSV
					if($resultGroup.Group[0].FeatureName -eq "SubscriptionCore" -and ($StorageReportJson.ScanDetails.SubscriptionScanResult | Measure-Object).Count -gt 0)
					{						
						$startIndex = $resultGroup.Name.lastindexof("/")
						$lastIndex = $resultGroup.Name.length - $startIndex-1
						$localSubID = $resultGroup.Name.substring($startIndex+1,$lastIndex)
						if($localSubID -eq $this.SubscriptionContext.SubscriptionId)
						{
							$PersistedControlScanResult=$StorageReportJson.ScanDetails.SubscriptionScanResult
						}						
					}
					elseif($resultGroup.Group[0].FeatureName -ne "SubscriptionCore" -and $resultGroup.Group[0].FeatureName -ne "AzSKCfg" -and ($StorageReportJson.ScanDetails.Resources | Measure-Object).Count -gt 0)
					{						 
						$ResourceData = $StorageReportJson.ScanDetails.Resources | Where-Object { $_.ResourceId -eq $resultGroup.Name }	 
						if($null -ne $ResourceData -and ($ResourceData.ResourceScanResult | Measure-Object).Count -gt 0 )
						{
							$PersistedControlScanResult=$ResourceData.ResourceScanResult
						}
					}
					if(($PersistedControlScanResult | Measure-Object).Count -gt 0)
					{
						$resultGroup.Group | ForEach-Object{
							try
							{
								$currentItem=$_
								$matchedControlResult = $PersistedControlScanResult | Where-Object {		
									($_.ControlID -eq $currentItem.ControlID -and (($currentItem.FeatureName -ne "SubscriptionCore" -and $_.ChildResourceName -eq $currentItem.ChildResourceName) -or $currentItem.FeatureName -eq "SubscriptionCore"))
								}
								$encoder = [System.Text.Encoding]::UTF8
								$encUserComments= $encoder.GetBytes($currentItem.UserComments)
								$decUserComments= $encoder.GetString($encUserComments)
								if($decUserComments.length -le 255)
								{
									if(($matchedControlResult|Measure-Object).Count -eq 1)
									{
										$successCount+=1;
										$matchedControlResult.UserComments= $decUserComments
									}
									else
									{
										$erroredControls+=$this.CreateCustomErrorObject($currentItem,"Could not find previous persisted state.")		 
									}
								}
								else
								{    
									$erroredControls+=$this.CreateCustomErrorObject($currentItem,"User Comment's length should not exceed 255 characters.")
								}
							}
							catch
							{
								$this.PublishException($_);
								$erroredControls+=$this.CreateCustomErrorObject($currentItem,"Could not find previous persisted state.")
							}		
						}		
					}
					else
					{
						$resultGroup.Group| ForEach-Object{
							$erroredControls+=$this.CreateCustomErrorObject($_,"Could not find previous persisted state.")
						}
					}
				}
				if($successCount -gt 0)
				{
					[LocalSubscriptionReport] $complianceReport = [LocalSubscriptionReport]::new();
					$complianceReport.Subscriptions += $StorageReportJson;
					$complianceReportHelper.SetLocalSubscriptionScanReport($complianceReport);
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
			else
			{
				$this.PublishEvent([AzSKGenericEvent]::Exception, "Unable to update user comments. Could not find previous persisted state in DevOps Kit storage.");
			}
		}
		catch
		{
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

