using namespace System.Management.Automation
Set-StrictMode -Version Latest 

# The class serves as an intermediate class to call multiple subscription security module classes

class SubscriptionSecurity: CommandBase
{    
	[string] $Tags
	SubscriptionSecurity([string] $subscriptionId, [InvocationInfo] $invocationContext, [string] $tags): 
        Base($subscriptionId, $invocationContext)
    { 
		$this.Tags = $tags;
	}
	SubscriptionSecurity([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext)
    {}
	[MessageData[]] SetSubscriptionSecurity(
		# Inputs for Security Center
		[string] $securityContactEmails, [string] $securityPhoneNumber, 
		# Inputs for Alerts
		[string] $targetResourceGroup, [string] $alertResourceGroupLocation
	)
    {	
		[MessageData[]] $messages = @();		

		#Create all the required AzSK Resources if missing
		try
		{
			$this.SetupAzSKResources();
		}
		catch
		{
			$this.CommandError($_);
		}

		#region Migration
		#AzSK TBR
		#[MigrationHelper]::TryMigration($this.SubscriptionContext, $this.InvocationContext);		
		#endregion
		
		# Set up Security Center
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nConfiguring Security Center`r`n" + [Constants]::DoubleDashLine);
			$secCenter = [SecurityCenter]::new($this.SubscriptionContext.SubscriptionId);
			if ($secCenter) 
			{
				$messages += $secCenter.SetPolicies($securityContactEmails, $securityPhoneNumber);
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted Security Center configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  
		
		# Set up RBAC
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nSetting up subscription RBAC`r`n" + [Constants]::DoubleDashLine);
			$rbac = [RBAC]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $this.Tags);
			if ($rbac) 
			{
				$messages += $rbac.SetRBACAccounts();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted subscription RBAC configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		# Set up ARM policies
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nSetting up ARM policies`r`n" + [Constants]::DoubleDashLine);
			$armPolicy = [ARMPolicy]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $this.Tags);
			if ($armPolicy) 
			{
				$messages += $armPolicy.SetARMPolicies();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted ARM policy configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		# Set up Alerts
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nSetting up Alerts`r`n" + [Constants]::DoubleDashLine);
			$alert = [Alerts]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $this.Tags);
			if ($alert) 
			{
				$messages += $alert.SetAlerts($targetResourceGroup, $securityContactEmails,$null,$alertResourceGroupLocation);
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted Alerts configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		return $messages;
    }
	
	[MessageData[]] RemoveSubscriptionSecurity([bool] $deleteResourceGroup, [string] $alertNames)
    {	
		[MessageData[]] $messages = @();

		# Remove ARM policies
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nRemoving ARM policies`r`n" + [Constants]::DoubleDashLine);
			$armPolicy = [ARMPolicy]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $this.Tags);
			if ($armPolicy) 
			{
				$messages += $armPolicy.RemoveARMPolicies();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nRemoved ARM policies`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		# Remove Alerts
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nRemoving Alerts`r`n" + [Constants]::DoubleDashLine);
			$alert = [Alerts]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $this.Tags);
			if ($alert) 
			{
				$messages += $alert.RemoveAlerts($deleteResourceGroup, $alertNames);
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nRemoved Alerts`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		return $messages;
    }

	[MessageData[]] UpdateSubscriptionSecurity()
    {	
		[MessageData[]] $messages = @();

		#check migrate flag
		$MigrateOption = $this.InvocationContext.BoundParameters["Migrate"];
		if($MigrateOption)
		{
			$this.Migrate();
			return $messages;
		}
		else
		{
			$isMigrationCompleted = [UserSubscriptionDataHelper]::IsMigrationCompleted($this.SubscriptionContext.SubscriptionId);
			if($isMigrationCompleted -ne "COMP")
			{
				$MigrationWarning = [ConfigurationManager]::GetAzSKConfigData().MigrationWarning;
				throw ([SuppressedException]::new($MigrationWarning,[SuppressedExceptionType]::Generic))
			}
		}

		#Adding all mandatory tags 
		$mandatoryTags = [string]::Join(",", [ConfigurationManager]::GetAzSKConfigData().SubscriptionMandatoryTags);

		#Create all the required AzSK Resources if missing
		try
		{
			$this.SetupAzSKResources();
		}
		catch
		{
			$this.CommandError($_);
		}


		#region Migration
		#AzSK TBR

		#[MigrationHelper]::TryMigration($this.SubscriptionContext, $this.InvocationContext);		

		#endregion

		# Set up Alerts
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nUpdating Alerts...`r`n" + [Constants]::DoubleDashLine);
			$alert = [Alerts]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $mandatoryTags);
			if ($alert) 
			{
				#calling alert method with default params i.e. without security contanct email and phone number
				$messages += $alert.SetAlerts();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted updates for Alerts configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }
		
		# Set up Security Center
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nUpdating Security Center configuration...`r`n" + [Constants]::DoubleDashLine);
			$secCenter = [SecurityCenter]::new($this.SubscriptionContext.SubscriptionId);
			if ($secCenter) 
			{
				#calling the ASC policy method with default params i.e. without ASC security poc email and phone number
				$messages += $secCenter.SetPolicies();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted updates for Security Center configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  
		
		# Set up RBAC
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nUpdating subscription RBAC with required central accounts...`r`n" + [Constants]::DoubleDashLine);
			$rbac = [RBAC]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $mandatoryTags);
			if ($rbac) 
			{
				#calling the rbac command to set the subscription with all the required approved accounts
				$messages += $rbac.SetRBACAccounts();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted updates for subscription RBAC configuration for central mandatory accounts`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		# Remove RBAC
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nUpdating subscription RBAC to remove any deprecated accounts...`r`n" + [Constants]::DoubleDashLine);
			$rbac = [RBAC]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $null);
			if ($rbac) 
			{
				#calling the rbac command to set the subscription with all the required approved accounts
				$messages += $rbac.RemoveRBACAccounts();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted updates for subscription RBAC configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		# Set up ARM policies
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nUpdating ARM policies...`r`n" + [Constants]::DoubleDashLine);
			$armPolicy = [ARMPolicy]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $mandatoryTags);
			if ($armPolicy) 
			{
				$messages += $armPolicy.SetARMPolicies();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted updates for ARM policy configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  
		  

		#Update CA
		$caAccount = [CCAutomation]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext);
		if ($caAccount) 
		{
			#Passing parameter FixRuntimeAccount, RenewCertificate and FixModules as false by default
			$messages += $caAccount.UpdateAzSKContinuousAssurance($false, $false, $false);
		}
		return $messages;
    }

	[MessageData[]] SetupAzSKResources()
	{
		[MessageData[]] $messages = @();

		$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nValidating the required resources for AzSK...`r`n" + [Constants]::DoubleDashLine);
		#Check for the presence of AzSK RG
		$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		$azskLocation = [ConfigurationManager]::GetAzSKConfigData().AzSKLocation;
		try 
        {
			$storageAccountName = ([Constants]::StorageAccountPreName + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"))
			$StorageAccountInstance = [StorageHelper]::new($this.SubscriptionContext.SubscriptionId, $azskRGName, $azskLocation, $storageAccountName);
			$StorageAccountInstance.CreateStorageContainerIfNotExists([Constants]::AttestationDataContainerName)
			$StorageAccountInstance.CreateStorageContainerIfNotExists([Constants]::CAScanOutputLogsContainerName)
			$StorageAccountInstance.CreateStorageContainerIfNotExists([Constants]::CAScanProgressSnapshotsContainerName)						
		}
		catch
		{
			$this.CommandError($_);
		}		
		$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted validating all the required resources for AzSK.`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);

		return $messages;
	}

	[Void] Migrate()
	{		
		$mgrationScript = $this.LoadServerConfigFile("Migration.ps1")
		$SubscriptionContext = $this.SubscriptionContext
		$InvocationContext = $this.InvocationContext
		$AzureADAppName = $this.InvocationContext.BoundParameters["AADAppName"];
		Invoke-Expression $mgrationScript		
	}

	[MessageData[]] UpdateStorage([string] $filePath)
    {	
	   [MessageData[]] $messages = @();

		#Check for file path exist
		 if(-not (Test-Path -path $filePath))
		{  
			$this.PublishCustomException("Provided file path is empty, Please re-run the command with correct path.", [MessageType]::Error);
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
		$isSubscriptionCoreFile=$false;
		$erroredControls=@();
      
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
                    $resultGroup.Group | ForEach-Object{
					try
					{
					     $currentItem=$_
				    	 $matchedControlResult=$ResourceScanResult | Where-Object {		
	 	                   ($_.ControlID -eq $currentItem.ControlID -and (  ([Helpers]::CheckMember($currentItem, "ChildResourceName") -and $_.ChildResourceName -eq $currentItem.ChildResourceName) -or (-not([Helpers]::CheckMember($currentItem, "ChildResourceName")) -and -not([Helpers]::CheckMember($_, "ChildResourceName")))))
		                 }
									
					     if(($matchedControlResult|Measure-Object).Count -eq 1)
					     {
					      $matchedControlResult.UserComments=$currentItem.UserComments
					     }else
						 {
						  # throw error here
						  $this.PublishCustomMessage("Updation of User Comments failed for "+ "ControlID: "+$currentItem.ControlId+" ResourceName: "+$currentItem.ResourceName, [MessageType]::Warning);
						  $erroredControls+=$currentItem			 
						 }
				    }catch{
					$this.PublishCustomException($_);
					# Add this control list to error log file
				    $erroredControls+=$currentItem
					}		
                    }
                }
				$StorageReportJson =[LocalSubscriptionReport] $StorageReportJson
				$storageReportHelper.SetLocalSubscriptionScanReport($StorageReportJson);
				# If updation failed for any control, genearte error file
				if(($erroredControls | Measure-Object).Count -gt 0)
				{
				  $controlCSV = New-Object -TypeName WriteCSVData
		          $controlCSV.FileName = 'Errored_Controls'
			      $controlCSV.FileExtension = 'csv'
			      $controlCSV.FolderPath = ''
			      $controlCSV.MessageData = $erroredControls
			      $this.PublishAzSKRootEvent([AzSKRootEvent]::WriteCSV, $controlCSV);
				}
		
		return $messages;
    }
}
