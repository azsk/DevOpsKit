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
	    $storageReportHelper = [StorageReportHelper]::new(); 
		$storageReportHelper.Initialize($false);	
		$StorageReportJson =$null;
		# Check for write access
		if($storageReportHelper.HasStorageReportWriteAccessPermissions())
		{
	  	  $StorageReportJson = $storageReportHelper.GetLocalSubscriptionScanReport();
		}else
		{
		 $this.PublishCustomMessage("You don't have the required permissions to update user comments. If you'd like to update user comments, please request your subscription owner to grant you 'Contributor' access to the 'AzSKRG' resource group.",[MessageType]::Error);
		 return $messages;
		}
	
		$SelectedSubscription=$null;
		$erroredControls=@();
		$PersistedControlScanResult=@();
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
							  $startIndex=$resultGroup.Name.lastindexof("/")
							  $lastIndex=$resultGroup.Name.length-$startIndex-1
							  $localSubID=$resultGroup.Name.substring($startIndex+1,$lastIndex)
							  if($localSubID -eq $this.SubscriptionContext.SubscriptionId)
							  {
							  $ResourceData=$SelectedSubscription.ScanDetails.SubscriptionScanResult
							  $PersistedControlScanResult=$ResourceData
							  }
							 }
						}else
						{
							 if([Helpers]::CheckMember($SelectedSubscription.ScanDetails,"Resources"))
							 {
							  $ResourceData=$SelectedSubscription.ScanDetails.Resources | Where-Object {$_.ResourceId -eq $resultGroup.Name}	 
							  } 
							  if(($ResourceData | Measure-Object).Count -gt 0 )
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
				    			 $matchedControlResult=$PersistedControlScanResult | Where-Object {		
	 							   ($_.ControlID -eq $currentItem.ControlID -and (  ([Helpers]::CheckMember($currentItem, "ChildResourceName") -and $_.ChildResourceName -eq $currentItem.ChildResourceName) -or (-not([Helpers]::CheckMember($currentItem, "ChildResourceName")) -and -not([Helpers]::CheckMember($_, "ChildResourceName")))))
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
									 }else
									 {
									  $erroredControls+=$this.CreateCustomErrorObject($currentItem,"Could not find previous persisted state.")		 
									 }
								 }else
								 {    
									  $erroredControls+=$this.CreateCustomErrorObject($currentItem,"User Comment's length is greater than 255.")
								 }
							}catch{
							$this.PublishException($_);
							$erroredControls+=$currentItem

							}		
						}
						}
						else{
					
						$resultGroup.Group| ForEach-Object{
						$erroredControls+=$this.CreateCustomErrorObject($_,"Could not find previous persisted state.")
						}
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

		return $messages;
    }

	hidden [PSObject] CreateCustomErrorObject($currentItem,$reason)
	{
	 $currentItem | Add-Member -NotePropertyName ErrorDetails -NotePropertyValue $reason
	 return $currentItem;
	}
}


