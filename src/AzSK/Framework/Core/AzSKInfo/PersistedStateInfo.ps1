using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class PersistedStateInfo: CommandBase
{    
	
	hidden [PSObject] $AzSKRG = $null
	hidden [String] $AzSKRGName = ""
	hidden [string] $subscriptionId;


	PersistedStateInfo([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext) 
    { 
		#$this.DoNotOpenOutputFolder = $true;
		$this.AzSKRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		$this.AzSKRG = Get-AzureRmResourceGroup -Name $this.AzSKRGName -ErrorAction SilentlyContinue
		$this.subscriptionId = $subscriptionId;
	}
	
	[MessageTableData[]] UpdatePersistedState([string] $filePath)
    {	
	    [string] $errorMessages="";
	    $customErrors=@();
	    [MessageTableData[]] $messages = @();
	   
	   try
	   {
		#Check for file path exist
		 if(-not (Test-Path -path $filePath))
		{  
			$this.PublishCustomMessage("Could not find file: $filePath . `n Please rerun the command with correct path.",[MessageType]::Error);
			return $messages;
		}
		# Read Local CSV file
		$controlResultSet = Get-ChildItem -Path $filePath -Filter '*.csv' -Force | Get-Content | Convertfrom-csv
		$resultsGroups=$controlResultSet | Group-Object -Property ResourceId 
		$totalCount=($controlResultSet | Measure-Object).Count
		if($totalCount -eq 0)
		{
		  $this.PublishCustomMessage("Could not find any control in file: $filePath .",[MessageType]::Error);
		  return $messages;
		}
		# Read file from Storage
	    $storageReportHelper = [ComplianceReportHelper]::new($this.subscriptionId); 
		$storageReportHelper.Initialize($false);	
		$StorageReportJson =$storageReportHelper.GetLocalSubscriptionScanReport();
		$SelectedSubscription=$null;
		$erroredControls=@();
		$ResourceScanResult=$null;
		$ResourceData=@();
		$successCount=0;
		
		if($null -ne $StorageReportJson -and [Helpers]::CheckMember($StorageReportJson,"Subscriptions"))
		{
	    	$SelectedSubscription = $StorageReportJson.Subscriptions | where-object {$_.SubscriptionId -eq $this.SubscriptionContext.SubscriptionId}
		}
		if(($SelectedSubscription|Measure-Object).Count -gt 0)
		{
		$this.PublishCustomMessage("Updating user comments in AzSK control data for $totalCount controls... ", [MessageType]::Warning);

        foreach ($resultGroup in $resultsGroups) {

		            if($resultGroup.Group[0].FeatureName -eq "SubscriptionCore")
					{
						if([Helpers]::CheckMember($SelectedSubscription.ScanDetails,"SubscriptionScanResult"))
						{
						  $ResourceData=$SelectedSubscription.ScanDetails.SubscriptionScanResult
						  $ResourceScanResult=$ResourceData
						 }
					}else
					{
						 if([Helpers]::CheckMember($SelectedSubscription.ScanDetails,"Resources"))
						 {
						  $ResourceData=$SelectedSubscription.ScanDetails.Resources | Where-Object {$_.ResourceId -eq $resultGroup.Name}	 
						  } 
						  if(($ResourceData | Measure-Object).Count -gt 0 )
						  {
							  $ResourceScanResult=$ResourceData.ResourceScanResult
						  }
					}
					if(($ResourceScanResult | Measure-Object).Count -gt 0)
					{
                     $resultGroup.Group | ForEach-Object{
					try
					{
					     $currentItem=$_
				    	 $matchedControlResult=$ResourceScanResult | Where-Object {		
	 	                   ($_.ControlID -eq $currentItem.ControlID -and (  ([Helpers]::CheckMember($currentItem, "ChildResourceName") -and $_.ChildResourceName -eq $currentItem.ChildResourceName) -or (-not([Helpers]::CheckMember($currentItem, "ChildResourceName")) -and -not([Helpers]::CheckMember($_, "ChildResourceName")))))
		                 }
									
					     if(($matchedControlResult|Measure-Object).Count -eq 1)
					     {
						  $successCount+=1;
					      $matchedControlResult.UserComments=$currentItem.UserComments
					     }else
						 {
						  $customErr = [PSObject]::new();
					      Add-Member -InputObject $customErr -Name "ControlId" -MemberType NoteProperty -Value $currentItem.ControlId
					      Add-Member -InputObject $customErr -Name "ResourceName" -MemberType NoteProperty -Value $currentItem.ResourceName
						  Add-Member -InputObject $customErr -Name "Reason" -MemberType NoteProperty -Value "Could not find previous persisted state"
						  $customErrors+=$customErr
						  $erroredControls+=$currentItem			 
						 }
				    }catch{
					$this.PublishException($_);
				    $erroredControls+=$currentItem
					}		
                    }
					}
					else{
					$erroredControls+=$resultGroup.Group
					}
                }
				if($successCount -gt 0)
				{
					$finalscanReport=$storageReportHelper.MergeScanReport($SelectedSubscription);
				    $storageReportHelper.SetLocalSubscriptionScanReport($finalscanReport);
				}
				# If updation failed for any control, genearte error file
				if(($erroredControls | Measure-Object).Count -gt 0)
				{
				  $controlCSV = New-Object -TypeName WriteCSVData
		          $controlCSV.FileName = 'Controls_NotUpdated'
			      $controlCSV.FileExtension = 'csv'
			      $controlCSV.FolderPath = ''
			      $controlCSV.MessageData = $erroredControls
			      $this.PublishAzSKRootEvent([AzSKRootEvent]::WriteCSV, $controlCSV);
				  $this.PublishCustomMessage("[$successCount/$totalCount] user comments have been updated successfully.", [MessageType]::Update);
				  $this.PublishCustomMessage("[$(($erroredControls | Measure-Object).Count)/$totalCount] user comments could not be updated due to an error. See the log file for details.", [MessageType]::Warning);
				}else
				{
				  $this.PublishCustomMessage("All User Comments have been updated successfully.", [MessageType]::Update);
				}
		}else
		{
		 $this.PublishEvent([AzSKGenericEvent]::Exception, "Unable to update user comments. Could not find previous persisted state in DevOps Kit storage.");
		}
		}
		catch
		{
		 $this.PublishException($_);
		}
		if(($customErrors | Measure-Object).Count -gt 0)
		{
        $messages += [MessageTableData]::new("Unable to update user comments for following controls:",$customErrors)
		}
		return $messages;
    }
}