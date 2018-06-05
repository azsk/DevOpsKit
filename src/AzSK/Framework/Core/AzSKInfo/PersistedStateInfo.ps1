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
	   [MessageData[]] $messages = @();
		#Check for file path exist
		 if(-not (Test-Path -path $filePath))
		{  
			$this.PublishException("Provided file path is empty, Please re-run the command with correct path.");
			return $messages;
		}
		# Read Local CSV file
		$controlResultSet = Get-ChildItem -Path $filePath -Filter '*.csv' -Force | Get-Content | Convertfrom-csv
		$resultsGroups=$controlResultSet | Group-Object -Property ResourceId 
		# Read file from Storage
	    $storageReportHelper = [StorageReportHelper]::new(); 
		$storageReportHelper.Initialize($false);	
		$StorageReportJson =$storageReportHelper.GetLocalSubscriptionScanReport();
		$SelectedSubscription = $StorageReportJson.Subscriptions | where-object {$_.SubscriptionId -eq $this.SubscriptionContext.SubscriptionId}
		$erroredControls=@();
		$ResourceScanResult=$null;
		$successCount=0;
		$totalCount=($controlResultSet | Measure-Object).Count
        foreach ($resultGroup in $resultsGroups) {

		            if($resultGroup.Group[0].FeatureName -eq "SubscriptionCore")
					{
					  $ResourceData=$SelectedSubscription.ScanDetails.SubscriptionScanResult
					  $ResourceScanResult=$ResourceData
					}else
					{
					  $ResourceData=$SelectedSubscription.ScanDetails.Resources | Where-Object {$_.ResourceId -eq $resultGroup.Name}	  
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
						  $this.PublishCustomMessage("Updation of User Comments failed for "+ "ControlID: "+$currentItem.ControlId+" ResourceName: "+$currentItem.ResourceName, [MessageType]::Warning);
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
			    	$StorageReportJson =[LocalSubscriptionReport] $StorageReportJson
				    $storageReportHelper.SetLocalSubscriptionScanReport($StorageReportJson);
				}
				# If updation failed for any control, genearte error file
				if(($erroredControls | Measure-Object).Count -gt 0)
				{
				  $controlCSV = New-Object -TypeName WriteCSVData
		          $controlCSV.FileName = 'Errored_Controls'
			      $controlCSV.FileExtension = 'csv'
			      $controlCSV.FolderPath = ''
			      $controlCSV.MessageData = $erroredControls
			      $this.PublishAzSKRootEvent([AzSKRootEvent]::WriteCSV, $controlCSV);
				  $this.PublishCustomMessage("$(($erroredControls | Measure-Object).Count)/$totalCount User Comments have not been Updated.", [MessageType]::Warning);
				  $this.PublishCustomMessage("$successCount/$totalCount User Comments have been Updated successfully.", [MessageType]::Update);
				}else
				{
				  $this.PublishCustomMessage("All User Comments have been updated successfully.", [MessageType]::Update);
				}
		
		return $messages;
    }
}


