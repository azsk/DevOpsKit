using namespace System.Management.Automation
Set-StrictMode -Version Latest 
class CCAutomation: CommandBase
{ 
	hidden [AutomationAccount] $AutomationAccount
	[string] $TargetSubscriptionIds = "";
	hidden [Runbook[]] $Runbooks = @()
	hidden [string] $RunbookName = "Continuous_Assurance_Runbook"
	hidden [RunbookSchedule[]] $RunbookSchedules = @()
	hidden [string] $ScheduleName = "CA_Scan_Schedule"
	hidden [Variable[]] $Variables = @()
	hidden [UserConfig] $UserConfig 
	hidden [PSObject] $OutputObject = @{}
	hidden [SelfSignedCertificate] $CertificateDetail = [SelfSignedCertificate]::new()
	hidden [Hashtable] $ReportStorageTags = @{}
	hidden [string] $ExceptionMsg = "There was an error while configuring Automation Account."
	hidden [boolean] $IsExistingADApp = $false
	hidden [boolean] $CleanupFlag = $true
	hidden [string] $GetCommandName = "Get-AzSKContinuousAssurance"
	hidden [string] $UpdateCommandName = "Update-AzSKContinuousAssurance"
	hidden [string] $RemoveCommandName = "Remove-AzSKContinuousAssurance"
	hidden [string] $InstallCommandName = "Install-AzSKContinuousAssurance"
	hidden [string] $CertificateAssetName = "AzureRunAsCertificate"
	hidden [string]	$ConnectionAssetName = "AzureRunAsConnection"
	hidden [string] $CAAADApplicationID = "";
	hidden [string] $CATargetSubsBlobName = [Constants]::CATargetSubsBlobName
	hidden [string] $CAScanOutputLogsContainerName = [Constants]::CAScanOutputLogsContainerName
	hidden [string] $CAMultiSubScanConfigContainerName = [Constants]::CAMultiSubScanConfigContainerName
	hidden [string] $AzSKCentralSPNFormatString = "AzSK_CA_SPNc_"
	hidden [string] $AzSKLocalSPNFormatString = "AzSK_CA_SPN_"
	hidden [string] $AzSKCATempFolderPath = ($env:temp + "\AzSKTemp\")
	[bool] $SkipTargetSubscriptionConfig = $false;
	[bool] $IsCentralScanModeOn = $false;
	[bool] $IsMultiCAModeOn = $false;
	[bool] $IsCustomAADAppName = $false;
	[bool] $ExhaustiveCheck = $false;
	[bool] $ScanOnDeployment = $false;
	[bool] $RemoveScanOnDeployment = $false;
	[CAReportsLocation] $LoggingOption = [CAReportsLocation]::CentralSub;
	[string] $MinReqdCARunbookVersion = "2.1709.0"
	[string] $RunbookVersionTagName = "AzSKCARunbookVersion"
	[int] $DefaultScanIntervalInHours = 24;

	CCAutomation(
		[string] $subscriptionId, `
		[InvocationInfo] $invocationContext, `
		[string] $automationAccountLocation, `
		[string] $automationAccountRGName, `
		[string] $automationAccountName, `
		[string] $resourceGroupNames, `
		[string] $azureADAppName, `
		[int] $scanIntervalInHours) : Base($subscriptionId, $invocationContext)
	{
		$this.DefaultScanIntervalInHours = [int]([ConfigurationManager]::GetAzSKConfigData().CAScanIntervalInHours);
		if([string]::IsNullOrWhiteSpace($scanIntervalInHours))
		{
			$scanIntervalInHours = $this.DefaultScanIntervalInHours;
		}
		
		$caAADAppName = $this.invocationContext.BoundParameters["AzureADAppName"];
	
		if(-not [string]::IsNullOrWhiteSpace($caAADAppName))
		{
			$this.IsCustomAADAppName = $true;
		}
	
		$this.AutomationAccount = [AutomationAccount]@{
			Name = ([UserSubscriptionDataHelper]::GetCAName());
			CoreResourceGroup = ([UserSubscriptionDataHelper]::GetUserSubscriptionRGName());
			ResourceGroup = $automationAccountRGName;
			Location = $automationAccountLocation;
			AzureADAppName = $azureADAppName;
			ScanIntervalInHours = $scanIntervalInHours;
		}
		if(-not [string]::IsNullOrWhiteSpace($automationAccountName))
		{
			$this.AutomationAccount.Name = $automationAccountName;
		}
		if([string]::IsNullOrWhiteSpace($automationAccountRGName))
		{
			$this.AutomationAccount.ResourceGroup = [UserSubscriptionDataHelper]::GetUserSubscriptionRGName();
		}
		if([string]::IsNullOrWhiteSpace($automationAccountLocation))
		{
			$this.AutomationAccount.Location = [UserSubscriptionDataHelper]::GetUserSubscriptionRGLocation();
		}
		if($this.AutomationAccount.ResourceGroup -ne $this.AutomationAccount.CoreResourceGroup)
		{
			$this.IsMultiCAModeOn = $true
			$this.CATargetSubsBlobName = "$($this.AutomationAccount.ResourceGroup)\$([Constants]::CATargetSubsBlobName)";
		}
		$this.UserConfig = [UserConfig]@{
			ResourceGroupNames = $resourceGroupNames
		}
		$this.DoNotOpenOutputFolder = $true;
	}

	CCAutomation(
		[string] $subscriptionId, `
		[InvocationInfo] $invocationContext) : Base($subscriptionId, $invocationContext)
	{
		$this.DefaultScanIntervalInHours = [int]([ConfigurationManager]::GetAzSKConfigData().CAScanIntervalInHours);
		$this.AutomationAccount = [AutomationAccount]@{
			Name = ([UserSubscriptionDataHelper]::GetCAName());
			CoreResourceGroup = ([UserSubscriptionDataHelper]::GetUserSubscriptionRGName());
			ResourceGroup = [UserSubscriptionDataHelper]::GetUserSubscriptionRGName();
		}
		$this.UserConfig = [UserConfig]::new();
		$this.DoNotOpenOutputFolder = $true;
	
		$caAADAppName = $this.invocationContext.BoundParameters["AzureADAppName"];
	
		if(-not [string]::IsNullOrWhiteSpace($caAADAppName))
		{
			$this.IsCustomAADAppName = $true;
		}
	}
	
	CCAutomation(
		[string] $subscriptionId, `
		[string] $automationAccountRGName, `
		[string] $automationAccountName, `
		[InvocationInfo] $invocationContext) : Base($subscriptionId, $invocationContext)
	{
		$this.DefaultScanIntervalInHours = [int]([ConfigurationManager]::GetAzSKConfigData().CAScanIntervalInHours);
		$this.AutomationAccount = [AutomationAccount]@{
			Name = ([UserSubscriptionDataHelper]::GetCAName());
			CoreResourceGroup = ([UserSubscriptionDataHelper]::GetUserSubscriptionRGName());
			ResourceGroup = $automationAccountRGName;
		}
		if(-not [string]::IsNullOrWhiteSpace($automationAccountName))
		{
			$this.AutomationAccount.Name = $automationAccountName;
		}
		if([string]::IsNullOrWhiteSpace($automationAccountRGName))
		{
			$this.AutomationAccount.ResourceGroup = [UserSubscriptionDataHelper]::GetUserSubscriptionRGName();
		}
		if($this.AutomationAccount.ResourceGroup -ne $this.AutomationAccount.CoreResourceGroup)
		{
			$this.IsMultiCAModeOn = $true
			$this.CATargetSubsBlobName = "$($this.AutomationAccount.ResourceGroup)\$([Constants]::CATargetSubsBlobName)";
		}
		$this.UserConfig = [UserConfig]::new();
		$this.DoNotOpenOutputFolder = $true;
	
		$caAADAppName = $this.invocationContext.BoundParameters["AzureADAppName"];
	
		if(-not [string]::IsNullOrWhiteSpace($caAADAppName))
		{
			$this.IsCustomAADAppName = $true;
		}
	}

	hidden [void] SetLAWSettings([string] $laWorkspaceId, [string] $lawSharedKey, [string] $altLAWorkspaceId, [string] $altLAWSharedKey)
	{
		if($this.UserConfig)
		{
			$this.UserConfig.LAWCredential = [LogAnalyticsCredential]@{
				LAWorkspaceId = $laWorkspaceId;
				LAWSharedKey = $lawSharedKey;
			};
			$this.UserConfig.AltLAWCredential = [LogAnalyticsCredential]@{
				LAWorkspaceId = $altLAWorkspaceId;
				LAWSharedKey = $altLAWSharedKey;
			};
		}		
	}

	hidden [void] SetWebhookSettings([string] $webhookUrl, [string] $authZHeaderName, [string] $authZHeaderValue)
	{
		if($this.UserConfig)
		{
			$this.UserConfig.WebhookDetails = [WebhookSetting]@{
				Url = $webhookUrl;
				AuthZHeaderName = $authZHeaderName;
				AuthZHeaderValue = $authZHeaderValue;
			};
		}	
	}

	hidden [void] RecoverCASPN()
	{
		$automationAcc = $this.GetCABasicResourceInstance()
		if($null -ne $automationAcc)
		{
			$runAsConnection = $this.GetRunAsConnection()
			$existingAppId = $runAsConnection.FieldDefinitionValues.ApplicationId
			$this.SetCASPNPermissions($existingAppId)
			if($this.IsMultiCAModeOn)
			{
                $this.SetSPNRGAccessIfNotAssigned($existingAppId, $this.AutomationAccount.ResourceGroup, "Contributor")
			}
		}
	}

	[void] SetAzSKInitiative()
	{
		try
		{
			$subARMPol = [ARMPolicy]::new($this.SubscriptionContext.SubscriptionId, $this.invocationContext, "", $false);
			$subARMPol.SetPolicyInitiative();
		}
		catch
		{
			#eat the exception if you are not able to set the initiative
		}
	}

	[MessageData[]] InstallAzSKContinuousAssurance()
    {
		[MessageData[]] $messages = @();
		try
		{
			#Validate if command is running from local policy folder
			$this.ValidateIfLocalPolicyIsEnabled()

			#SetAzSKInitiative
			$this.SetAzSKInitiative();

			#region :validation/RG creation
			if(!$this.IsCAInstallationValid())
			{
				$this.CleanupFlag = $false
				if($this.IsMultiCAModeOn)
				{
					throw ([SuppressedException]::new(("The specified resource group already contains an automation account. Please specify a different automation account and resource group combination."), [SuppressedExceptionType]::InvalidOperation))
				}
				else
				{
					throw ([SuppressedException]::new(("CA has been already setup in this subscription. If you need to change CA configuration, use 'Update-AzSKContinuousAssurance' command."), [SuppressedExceptionType]::InvalidOperation))
				}
			}
			else
			{
			    $this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nStarted setting up Automation Account for Continuous Assurance (CA)`r`n"+[Constants]::DoubleDashLine);
                
                #create AzSKRG resource group
                [Helpers]::CreateNewResourceGroupIfNotExists($this.AutomationAccount.CoreResourceGroup,$this.AutomationAccount.Location,$this.GetCurrentModuleVersion())
				
				#create RG given by user
				if($this.IsMultiCAModeOn)
				{
                    [Helpers]::CreateNewResourceGroupIfNotExists($this.AutomationAccount.ResourceGroup,$this.AutomationAccount.Location,$this.GetCurrentModuleVersion())
                }
			}
			
			#Return in case of Central and Multi CA Mode
			if($this.ScanOnDeployment -and ($this.IsMultiCAModeOn -or -$this.IsCentralScanModeOn))
			{
				$this.PublishCustomMessage("Error: Scan on Deployment feature is currently not supported for Central CA Mode.",[MessageType]::Warning)
				throw ([SuppressedException]::new(("Scan on Deployment not supported."), [SuppressedExceptionType]::InvalidOperation))
			}

			$this.UserConfig.StorageAccountRG = $this.AutomationAccount.CoreResourceGroup
			
			#endregion

			#region: Deploy empty Automation account
			$this.PublishCustomMessage("Creating Automation Account: [" + $this.AutomationAccount.Name + "]")
			$this.NewEmptyAutomationAccount()
			
			#endregion

			#region: Create SPN, Certificate
			$this.NewCCAzureRunAsAccount()
			#endregion 


			#region: Create/reuse existing storage account (Added this before creating variables since it's value is used in it)
			$existingStorage = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
			if(($existingStorage|Measure-Object).Count -gt 0)
			{
				$this.UserConfig.StorageAccountName = $existingStorage.Name
				$this.PublishCustomMessage("Preparing a storage account for storing reports from CA scans...`r`nFound existing AzSK storage account: ["+ $this.UserConfig.StorageAccountName +"]. This will be used to store reports from CA scans.")
			}
			else
			{
				#create new storage
				$this.UserConfig.StorageAccountName = ("azsk" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"))
				$this.PublishCustomMessage("Creating a storage account: ["+ $this.UserConfig.StorageAccountName +"] for storing reports from CA scans.")
				$newStorage = [Helpers]::NewAzskCompliantStorage($this.UserConfig.StorageAccountName,$this.UserConfig.StorageAccountRG, $this.AutomationAccount.Location) 
				if(!$newStorage)
				{
					$this.CleanupFlag = $true
					throw ([SuppressedException]::new(($this.ExceptionMsg + "Failed to create storage account."), [SuppressedExceptionType]::Generic))
				}  
				else
				{
					#apply tags
					$timestamp = $(get-date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
					$this.ReportStorageTags += @{
						"CreationTime"=$timestamp;
						"LastModified"=$timestamp
					}
					Set-AzStorageAccount -ResourceGroupName $newStorage.ResourceGroupName -Name $newStorage.StorageAccountName -Tag $this.ReportStorageTags -Force -ErrorAction SilentlyContinue
				} 
			}
			
			$this.OutputObject.StorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage() | Select-Object Name, ResourceGroupName, Sku, Tags
			
			#endregion			

			#region: Deploy Automation account items (runbooks, variables, schedules)
			$this.DeployCCAutomationAccountItems()
			#endregion

			#region: central scanning mode
			if($this.IsCentralScanModeOn)
			{
				$this.PublishCustomMessage("`nStarted configuring all the target subscriptions for central scanning mode...")				
				
				[CAScanModel[]] $scanObjects = @()

				#Add the current sub as scanning object
				$scanObject = [CAScanModel]::new($this.SubscriptionContext.SubscriptionId, $this.LoggingOption);
				$scanObjects += $scanObject;
				$caSubs = @();
				$tempCASubs = $this.ConvertToStringArray($this.TargetSubscriptionIds);
				$tempCASubs | ForEach-Object{
					if($_ -ne $this.SubscriptionContext.SubscriptionId -and $caSubs -notcontains $_)
					{
						$caSubs += $_;
					}
				}				
				$count = ($caSubs | Measure-Object).Count;
				$i = 0;
				$this.OutputObject.TargetSubs = @()
				$caSubs | ForEach-Object {
					$caSubId = $_;
					try
					{
						$out = "" | Select-Object CentralSubscriptionId, TargetSubscriptionId, StorageAccountName, LoggingOption
						$i = $i + 1
						$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`n[$i/$count] Configuring subscription for central scan: [$caSubId] `r`n"+[Constants]::DoubleDashLine);
						$out.CentralSubscriptionId = $this.SubscriptionContext.SubscriptionId;
						$out.TargetSubscriptionId = $caSubId;
						$out.StorageAccountName = $this.UserConfig.StorageAccountName;
						$out.LoggingOption = $this.LoggingOption.ToString();

						Set-AzContext -SubscriptionId $caSubId | Out-Null
						$existingStorage = $null;
						try
						{
							$existingStorage = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
						}
						catch
						{
							#eat exception if storage is not preset
						}

						if(-not $this.SkipTargetSubscriptionConfig)
						{
							if($this.LoggingOption -eq [CAReportsLocation]::IndividualSubs)
							{
								#region :create new resource group/check if RG exists. This is required for the CA SPN to read the attestation data. 
								if((Get-AzResourceGroup -Name $this.AutomationAccount.CoreResourceGroup -ErrorAction SilentlyContinue|Measure-Object).Count -eq 0)
								{
									$this.PublishCustomMessage("Creating AzSK RG...");
									[Helpers]::NewAzSKResourceGroup($this.AutomationAccount.CoreResourceGroup,$this.AutomationAccount.Location,$this.GetCurrentModuleVersion())
								}								
								#endregion

								#$this.PublishCustomMessage("Configuring permissions for AzSK CA SPN. This may take a few min...")
								#CAAADApplicaitonID is being set in the above call while setting the RunAsConnection
								
								$this.SetCASPNPermissions($this.CAAADApplicationID)					
							
								if(($existingStorage | Measure-Object).Count -gt 0)
								{
									$caStorageAccountName = $existingStorage.Name
									$this.PublishCustomMessage("Preparing a storage account for storing reports from CA scans...`r`nFound existing AzSK storage account: [$caStorageAccountName]. This will be used to store reports from CA scans.")
									$out.StorageAccountName = $caStorageAccountName;
								}
								else
								{
									#create new storage
									$caStorageAccountName = ("azsk" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"))
									$this.PublishCustomMessage("Creating a storage account: [$caStorageAccountName] for storing reports from CA scans.")
									$newStorage = [Helpers]::NewAzskCompliantStorage($caStorageAccountName,$this.UserConfig.StorageAccountRG, $this.AutomationAccount.Location) 
									if(!$newStorage)
									{
										$this.CleanupFlag = $true
										throw ([SuppressedException]::new(($this.ExceptionMsg + "Failed to create storage account."), [SuppressedExceptionType]::Generic))
									}  
									else
									{
										#apply tags
										$timestamp = $(get-date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
										$this.ReportStorageTags += @{
											"AzSKFeature" = "ContinuousAssuranceStorage";
											"CreationTime"=$timestamp;
											"LastModified"=$timestamp
										}
										[Helpers]::SetResourceTags($newStorage.Id, $this.ReportStorageTags, $false, $true);
									} 
									$out.StorageAccountName = $caStorageAccountName;
								}
							}
							else
							{
								if(($existingStorage | Measure-Object).Count -gt 0)
								{
									$caStorageAccountName = $existingStorage.Name
									$this.PublishCustomMessage("Preparing a storage account for storing reports from CA scans...`r`nFound existing AzSK storage account: [$caStorageAccountName]. This will be used to store reports from CA scans.")
									$out.StorageAccountName = $caStorageAccountName;
									$this.SetCASPNPermissions($this.CAAADApplicationID)
								}
								else
								{
									$this.PublishCustomMessage("Configuring permissions for AzSK CA SPN. This may take a few min...")
									$this.SetSPNSubscriptionAccessIfNotAssigned($this.CAAADApplicationID)

								}
							}
						}	
						$this.OutputObject.TargetSubs += $out
						$scanObject = [CAScanModel]::new($caSubId, $this.LoggingOption);
						$scanObjects += $scanObject;
						$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`n[$i/$count] Completed configuring subscription for central scan: [$caSubId] `r`n"+[Constants]::DoubleDashLine);

						# Added Security centre provider registration to avoid error while running SSCore command in CA
						[SecurityCenterHelper]::RegisterResourceProviderNoException();
					}
					catch
					{
						$this.PublishCustomMessage("Failed to setup scan for $caSubId");
						$this.PublishException($_)
					}
				}
				#set context back to central sub
				Set-AzContext -SubscriptionId $this.SubscriptionContext.SubscriptionId | Out-Null			
				#region: Create Scan objects			
                $fileName = "$($this.AzSKCATempFolderPath)\$($this.CATargetSubsBlobName)"

				if(-not (Split-Path -Parent $fileName | Test-Path))
				{
					mkdir -Path $(Split-Path -Parent $fileName) -Force
				}
				
				[Helpers]::ConvertToJsonCustom($scanObjects) | Out-File $fileName -Force
						
				$caStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
				$this.UserConfig.StorageAccountName = $caStorageAccount.Name
				$keys = Get-AzStorageAccountKey -ResourceGroupName $this.UserConfig.StorageAccountRG  -Name $this.UserConfig.StorageAccountName
				$currentContext = New-AzStorageContext -StorageAccountName $this.UserConfig.StorageAccountName -StorageAccountKey $keys[0].Value -Protocol Https
				try
				{
					Get-AzStorageContainer -Name $this.CAMultiSubScanConfigContainerName -Context $currentContext -ErrorAction Stop | Out-Null
				}
				catch
				{
					New-AzStorageContainer -Name $this.CAMultiSubScanConfigContainerName -Context $currentContext | Out-Null
				}
				#endregion

				#Save the scan objects in blob stoage#
				[AzHelper]::UploadStorageBlobContent($fileName, $this.CATargetSubsBlobName, $this.CAMultiSubScanConfigContainerName, $currentContext)
				#Set-AzStorageBlobContent -File $fileName -Blob $this.CATargetSubsBlobName -Container $this.CAMultiSubScanConfigContainerName -BlobType Block -Context $currentContext -Force
			}

			#endregion

			# Added Security centre provider registration to avoid error while running SSCore command in CA
			[SecurityCenterHelper]::RegisterResourceProviderNoException();

			#update version tag
			$this.SetRunbookVersionTag()

			#successfully installed
			$this.CleanupFlag = $false
			$this.PublishCustomMessage([Constants]::SingleDashLine + "`r`nCompleted setup phase-1 for AzSK Continuous Assurance.`r`n" +
				"Setup phase-2 has been triggered and will continue automatically in the background. This involves loading all PS modules CA requires to run, scheduling runbook, etc. This phase may take up to 2 hours to complete.`r`n" +
				"You can check the overall status of installation using the '$($this.GetCommandName)' command 2 hours after running '$($this.InstallCommandName)' command.`r`n" +
				"Once phase-2 setup completes, your subscription and resources (from the specified resource groups) will be scanned periodically by CA. All security control evaluation results will be sent to the Log Analytics workspace specified during CA installation.`r`n" +
				"You may subsequently update any of the parameters specified during installation using the '$($this.UpdateCommandName)' command. If you specified '*' for resource groups, new resource groups will be automatically picked up for scanning.`r`n" +
				"You should use the AzSK Monitoring solution to monitor your subscription and resource health status.`r`n",[MessageType]::Update)
			$messages += [MessageData]::new("The following resources were created in resource group: [" + $this.AutomationAccount.ResourceGroup + "] as part of Continuous Assurance", $this.OutputObject)
		}
		catch
		{
			$this.PublishException($_)

			#cleanup if exception occurs
			if($this.CleanupFlag)
			{
				$this.PublishCustomMessage("Error occurred. Rolling back the changes.", [MessageType]::error)
				if(![string]::IsNullOrWhiteSpace($this.AutomationAccount.ResourceGroup))
				{
					$account = $this.GetCADetailedResourceInstance()
					if(($account|Measure-Object).Count -gt 0)
					{
						$account | Remove-AzAutomationAccount -Force -ErrorAction SilentlyContinue
					}
				}
				#clean AD App only if AD App was newly created
				if(![string]::IsNullOrWhiteSpace($this.AutomationAccount.AzureADAppName) -and !$this.IsCustomAADAppName)
				{
					$adApplication = Get-AzADApplication -DisplayNameStartWith $this.AutomationAccount.AzureADAppName -ErrorAction SilentlyContinue | Where-Object -Property DisplayName -eq $this.AutomationAccount.AzureADAppName
					if($adApplication)
					{
						Remove-AzADApplication -ObjectId $adApplication.ObjectId -Force -ErrorAction Stop
					}
				}
			}
			throw ([SuppressedException]::new(("Continuous Assurance setup not completed."), [SuppressedExceptionType]::Generic))
		}

		return $messages;
	}

	[MessageData[]] UpdateAzSKContinuousAssurance($fixRuntimeAccount, $newRuntimeAccount, $renewCertificate, $fixModules)
	{
		[MessageData[]] $messages = @();
		try
		{
			#Validate if command is running with local policy
			$this.ValidateIfLocalPolicyIsEnabled()

			#SetAzSKInitiative
			$this.SetAzSKInitiative();

            #Always assign permissions if CA is in central scan mode
            if($this.IsCentralScanModeOn)
            {
                $fixRuntimeAccount = $true
            }
			#region :Check if automation account is compatible for update
			$existingAccount = $this.GetCABasicResourceInstance()
			$automationTags = @()
			if(($existingAccount|Measure-Object).Count -eq 0)
			{
				throw ([SuppressedException]::new(("Continuous Assurance(CA) is not configured in this subscription. Please install using '" + $this.InstallCommandName + "' command with required parameters."), [SuppressedExceptionType]::InvalidOperation))
			}
			else
			{
				$automationTags = $existingAccount.Tags
			}

			#Return in case of Central and Multi CA Mode
			if($this.ScanOnDeployment -and ($this.IsMultiCAModeOn -or -$this.IsCentralScanModeOn))
			{
				$this.PublishCustomMessage("Error: Scan on Deployment feature is currently not supported for Central CA Mode.", [MessageType]::Warning)
				throw ([SuppressedException]::new(("Scan on Deployment not supported."), [SuppressedExceptionType]::InvalidOperation))
			}

			$this.AutomationAccount.Location = $existingAccount.Location
			#endregion

			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nUpdating your AzSK Continuous Assurance setup...`r`n" + [Constants]::DoubleDashLine);
		
			#region cleanup older assets
			$this.CleanUpOlderAssets();
			#endregion

			#region: Check AzureRM.Automation/AzureRm.Profile and its dependent modules health
			if($fixModules)
			{
				$this.PublishCustomMessage("Inspecting modules present in the CA automation account…")
				try
				{
					$this.FixCAModules()
				}
				catch
				{
					$this.PublishCustomMessage("Error occurred while ...")
				}
			}
			#endregion
		
			#region :Remove existing and create new AzureRunAsConnection if AzureADAppName param is passed else fix RunAsAccount if issue is found
			$caAccountError = $false;
			if(![string]::IsNullOrWhiteSpace($this.AutomationAccount.AzureADAppName))
			{
				$this.NewCCAzureRunAsAccount()
			}
            elseif($newRuntimeAccount)
            {
                $this.NewCCAzureRunAsAccount($newRuntimeAccount)
            }
			else
			{
				if($renewCertificate)
				{
					$runAsConnection = $this.GetRunAsConnection();
					#create new certificate if certificate is deleted or expired 
					if($runAsConnection)
					{
						$this.PublishCustomMessage("Trying to renew certificate in the CA Automation Account...")
						try
						{
                            $this.UpdateCCAzureRunAsAccount()
							$this.PublishCustomMessage("Successfully renewed certificate (new expiry date: $((Get-Date).AddMonths(6).AddDays(1).ToString("yyyy-MM-dd"))) in the CA Automation Account.")
							$this.IsExistingADApp = $true
						}
						catch
						{
							$this.PublishCustomMessage("WARNING:  Could not renew certificate for the currently configured SPN (App Id: $($runAsConnection.FieldDefinitionValues.ApplicationId)). You may not have 'Owner' permission on it. `r`n" `
								+ "You can either get the owner of the above SPN to run this command or run command '$($this.UpdateCommandName) -SubscriptionId <SubscriptionId> -NewRuntimeAccount'.", [MessageType]::Warning)
						}
					}
					else
					{
						if(!$fixRuntimeAccount)
						{
							$this.PublishCustomMessage("WARNING: Runtime Account not found. To resolve this run command '$($this.UpdateCommandName) -SubscriptionId <SubscriptionId> -FixRuntimeAccount' after completion of current command execution.", [MessageType]::Warning)
							$caAccountError = $true;
						}
					}
				}
				else
				{
					#check cert expiry 
					$runAsCertificate = Get-AzAutomationCertificate -AutomationAccountName $this.AutomationAccount.Name `
						-Name $this.CertificateAssetName `
						-ResourceGroupName $this.AutomationAccount.ResourceGroup -ErrorAction SilentlyContinue

					if($runAsCertificate)
					{
						$expiryDuration = $runAsCertificate.ExpiryTime.UtcDateTime - $(get-date).ToUniversalTime()
						
						if($expiryDuration.TotalMinutes -lt 0)
						{
							$this.PublishCustomMessage("CA Certificate expiry date: [$($runAsCertificate.ExpiryTime.ToString("yyyy-MM-dd"))]")
							$this.PublishCustomMessage("WARNING: CA Certificate has expired. To renew please run command '$($this.UpdateCommandName) -SubscriptionId <SubscriptionId> -RenewCertificate' after completion of the current command.", [MessageType]::Warning)
							$caAccountError = $true
						}
						elseif($expiryDuration.TotalDays -ge 0 -and $expiryDuration.TotalDays -le 30)
						{
							$this.PublishCustomMessage("CA Certificate expiry date: [$($runAsCertificate.ExpiryTime.ToString("yyyy-MM-dd"))]")
							$this.PublishCustomMessage("WARNING: CA Certificate is going to expire within the next 30 days. To avoid disruption due to credential expiry, please run command '$($this.UpdateCommandName) -SubscriptionId <SubscriptionId> -RenewCertificate' after completion of the current command.", [MessageType]::Warning)
						}
					}
					else
					{
						$this.PublishCustomMessage("WARNING: CA certificate not found. To resolve this please run command '$($this.UpdateCommandName) -SubscriptionId <SubscriptionId> -RenewCertificate' after completion of current command execution.", [MessageType]::Warning)
						$caAccountError = $true
					}
					$runAsConnection = $this.GetRunAsConnection();
					if(!$runAsConnection -and !$fixRuntimeAccount)
					{
						$this.PublishCustomMessage("WARNING: Runtime Account not found. To resolve this run command '$($this.UpdateCommandName) -SubscriptionId <SubscriptionId> -FixRuntimeAccount' after completion of current command execution.", [MessageType]::Warning)
						$caAccountError = $true;
					}
				}
				if($fixRuntimeAccount)
				{
					$runAsConnection = $this.GetRunAsConnection();
					if($runAsConnection)
					{
						$existingAppId = $runAsConnection.FieldDefinitionValues.ApplicationId
						$this.CAAADApplicationID = $existingAppId;
						$adApp = Get-AzADApplication -ApplicationId $existingAppId -ErrorAction SilentlyContinue
						if($this.IsCentralScanModeOn)
						{
							if(-not ($null -ne $adApp -and $adApp.DisplayName -like "$($this.AzSKCentralSPNFormatString)*"))
							{
								#Null out the ADApp if it is in central scan mode mode and the spn is not in central format
								$adApp = $null
							}
						}
						$servicePrincipal = Get-AzADServicePrincipal -ServicePrincipalName $existingAppId -ErrorAction SilentlyContinue
						if($adApp -and $servicePrincipal)
						{
							$this.SetCASPNPermissions($this.CAAADApplicationID)
			                if($this.IsMultiCAModeOn)
			                {
                                $this.SetSPNRGAccessIfNotAssigned($existingAppId,$this.AutomationAccount.ResourceGroup, "Contributor")
			                }
						}
						else
						{
							$this.NewCCAzureRunAsAccount()
						}						
					}
					else
					{
						$this.NewCCAzureRunAsAccount()
					}
				}
			}
			if($caAccountError -eq $true)
			{
				throw ([SuppressedException]::new(("`n`rFailed to update CA. Please rerun the '$($this.UpdateCommandName)' command with above mentioned parameters."), [SuppressedExceptionType]::Generic))
			}
			#endregion  
		
			#region: create storage account if not present and update same in variable#

			$this.OutputObject.Variables = @()  #This is added to initialize variables 		
			$newStorageName = [string]::Empty
		
			#Check if storage exists
			$existingStorage = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
			if(($existingStorage|Measure-Object).Count -gt 0)
			{
				$this.PublishCustomMessage("Found existing AzSK storage account: [" + $existingStorage.Name + "]")
				$this.UserConfig.StorageAccountName = $existingStorage.Name
				#make storage compliant to azsk
				$this.ResolveStorageCompliance($existingStorage.Name, $existingStorage.ResourceId, $this.AutomationAccount.CoreResourceGroup, $this.CAScanOutputLogsContainerName)
			
				#update storage account variable
				$storageVariable = $this.GetReportsStorageAccountNameVariable()
				if($null -eq $storageVariable -or ($null -ne $storageVariable -and $storageVariable.Value.Trim() -ne $existingStorage.Name))
				{
					$varStorageName = [Variable]@{
						Name = "ReportsStorageAccountName";
						Value = $existingStorage.Name;
						IsEncrypted = $false;					
						Description ="Name of Storage Account where CA scan reports will be stored"
					}
					$this.UpdateVariable($varStorageName)
				}	
			}
			else
			{
				#create default storage
				$newStorageName = ("azsk" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"))				
				$this.PublishCustomMessage("Creating Storage Account: [$newStorageName] for storing reports from CA scans.")
				$this.UserConfig.StorageAccountName = $newStorageName
				$newStorage = [Helpers]::NewAzskCompliantStorage($newStorageName, $this.AutomationAccount.CoreResourceGroup, $existingAccount.Location) 
				if(!$newStorage)
				{
					throw ([SuppressedException]::new(($this.ExceptionMsg + "Failed to create storage account."), [SuppressedExceptionType]::Generic))
				}   
				else
				{
					#apply tags
					$timestamp = $(get-date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
					$this.ReportStorageTags += @{
						"CreationTime"=$timestamp;
						"LastModified"=$timestamp
					}
					Set-AzStorageAccount -ResourceGroupName $newStorage.ResourceGroupName -Name $newStorage.StorageAccountName -Tag $this.ReportStorageTags -Force -ErrorAction SilentlyContinue
				}
			
				#update storage account variable with new value
				$varStorageName = [Variable]@{
					Name = "ReportsStorageAccountName";
					Value = $newStorage.StorageAccountName;
					IsEncrypted = $false;
					Description ="Name of Storage Account where CA scan reports will be stored"
				}
				$this.UpdateVariable($varStorageName)
				$this.OutputObject.StorageAccountName = $newStorageName 
			}
		
			#endregion

			#region :update user configurable variables (Log Analytics workspace details and App RGs) which are present in params
            if($null -ne $this.UserConfig -and $null -ne $this.UserConfig.LAWCredential)
			{
                #LAWSettings
                if(![string]::IsNullOrWhiteSpace($this.UserConfig.LAWCredential.LAWorkspaceId) -xor ![string]::IsNullOrWhiteSpace($this.UserConfig.LAWCredential.LAWSharedKey))
				{
				    $this.PublishCustomMessage("Warning: Log Analytics workspace settings are either incomplete or invalid. To configure Log Analytics workspace in CA, please rerun this command with 'LAWorkspaceId' and 'LAWSharedKey' parameters.", [MessageType]::Warning)
				}
				elseif(![string]::IsNullOrWhiteSpace($this.UserConfig.LAWCredential.LAWorkspaceId) -and ![string]::IsNullOrWhiteSpace($this.UserConfig.LAWCredential.LAWSharedKey))
				{
				    $varLAWorkspaceId = [Variable]@{
			    	    Name = "OMSWorkspaceId";
			    	    Value = $this.UserConfig.LAWCredential.LAWorkspaceId;
			    	    IsEncrypted = $false;
			    	    Description ="Log Analytics Workspace Id"
			        }
			        $this.UpdateVariable($varLAWorkspaceId)
			        $this.PublishCustomMessage("Updating variable: [" + $varLAWorkspaceId.Name + "]")

                    $varLAWSharedKey = [Variable]@{
			             Name = "OMSSharedKey";
			             Value = $this.UserConfig.LAWCredential.LAWSharedKey;
			             IsEncrypted = $false;
			             Description ="Log Analytics Workspace Shared Key"
			        }
			        $this.UpdateVariable($varLAWSharedKey)
			        $this.PublishCustomMessage("Updating variable: [" + $varLAWSharedKey.Name + "]")
				}
				
				#AltLAWSettings
				if(![string]::IsNullOrWhiteSpace($this.UserConfig.AltLAWCredential.LAWorkspaceId) -xor ![string]::IsNullOrWhiteSpace($this.UserConfig.AltLAWCredential.LAWSharedKey))
                {
                    $this.PublishCustomMessage("Warning: Alt Log Analytics workspace settings are either incomplete or invalid. To configure Alt Log Analytics workspace in CA, please rerun this command with 'AltLAWorkspaceId' and 'AltLAWSharedKey' parameters.", [MessageType]::Warning)
                }
                elseif(![string]::IsNullOrWhiteSpace($this.UserConfig.AltLAWCredential.LAWorkspaceId) -and ![string]::IsNullOrWhiteSpace($this.UserConfig.AltLAWCredential.LAWSharedKey))
                {
		        	$varAltLAWorkspaceId = [Variable]@{
		        		Name = "AltOMSWorkspaceId";
		        		Value = $this.UserConfig.AltLAWCredential.LAWorkspaceId;
		        		IsEncrypted = $false;
		        		Description ="Alternate Log Analytics Workspace Id"
		        	}
		        	$this.UpdateVariable($varAltLAWorkspaceId)
		        	$this.PublishCustomMessage("Updating variable: [" + $varAltLAWorkspaceId.Name + "]")

		        	$varAltLAWSharedKey = [Variable]@{
		        		Name = "AltOMSSharedKey";
		        		Value = $this.UserConfig.AltLAWCredential.LAWSharedKey;
		        		IsEncrypted = $false;
		        		Description ="Alternate Log Analytics Workspace Shared Key"
		        	}
		        	$this.UpdateVariable($varAltLAWSharedKey)
		        	$this.PublishCustomMessage("Updating variable: [" + $varAltLAWSharedKey.Name + "]")
                }
            }
            
			#Webhook settings
			if($null -ne $this.UserConfig -and $null -ne $this.UserConfig.WebhookDetails -and -not [string]::IsNullOrWhiteSpace($this.UserConfig.WebhookDetails.Url))
			{
				$varWebhookUrl = [Variable]@{
					Name = "WebhookUrl";
					Value = $this.UserConfig.WebhookDetails.Url;
					IsEncrypted = $false;
					Description ="Webhook Url"
				}
				$this.UpdateVariable($varWebhookUrl)
				$this.PublishCustomMessage("Updating variable: [" + $varWebhookUrl.Name + "]")
			}
			if($null -ne $this.UserConfig -and $null -ne $this.UserConfig.WebhookDetails `
				-and -not [string]::IsNullOrWhiteSpace($this.UserConfig.WebhookDetails.AuthZHeaderName) `
				-and -not [string]::IsNullOrWhiteSpace($this.UserConfig.WebhookDetails.AuthZHeaderValue))
			{
				$varWebhookAuthZHeaderName = [Variable]@{
					Name = "WebhookAuthZHeaderName";
					Value = $this.UserConfig.WebhookDetails.AuthZHeaderName;
					IsEncrypted = $false;
					Description ="Webhook AuthZ header name"
				}
				$this.UpdateVariable($varWebhookAuthZHeaderName)
				$this.PublishCustomMessage("Updating variable: [" + $varWebhookAuthZHeaderName.Name + "]")

				$varWebhookAuthZHeaderValue = [Variable]@{
					Name = "WebhookAuthZHeaderValue";
					Value = $this.UserConfig.WebhookDetails.AuthZHeaderValue;
					IsEncrypted = $true;
					Description ="Webhook AuthZ header value"
				}
				$this.UpdateVariable($varWebhookAuthZHeaderValue)
				$this.PublishCustomMessage("Updating variable: [" + $varWebhookAuthZHeaderValue.Name + "]")				
			}

			if($null -ne $this.UserConfig -and ![string]::IsNullOrWhiteSpace($this.UserConfig.ResourceGroupNames))
			{
				$varAppRG = [Variable]@{
					Name = "AppResourceGroupNames";
					Value = $this.UserConfig.ResourceGroupNames;
					IsEncrypted = $false;
					Description ="Comma separated values of the different resource groups that has to be scanned"
				}
				$this.UpdateVariable($varAppRG)
				$this.PublishCustomMessage("Updating variable: [" + $varAppRG.Name + "]")
			}
			else
			{
				$appRGs = $this.GetAppRGs()
				if($null -eq $appRGs -or ($null -ne $appRGs -and $appRGs.Value.Trim() -eq [string]::Empty))
				{
					$this.PublishCustomMessage("WARNING: The resource groups to be scanned by CA are not correctly set up. You can use the 'AppResourceGroupNames' parameter with this command to do so.", [MessageType]::Warning)
				}
			}
			#endregion

			#region: Update CA target subs in central scan mode
			if($this.IsCentralScanModeOn)
			{
				try
				{
					$this.PublishCustomMessage("`nStarted updating all the target subscriptions for central scanning mode...")

					[CAScanModel[]] $existingScanObjects = @()
					#Add the current sub as scanning object					
					
                    $fileName = "$($this.AzSKCATempFolderPath)\$($this.CATargetSubsBlobName)"

				    if(-not (Split-Path -Parent $fileName | Test-Path))
				    {
					    mkdir -Path $(Split-Path -Parent $fileName) -Force
				    }
					$keys = Get-AzStorageAccountKey -ResourceGroupName $this.AutomationAccount.CoreResourceGroup -Name $this.UserConfig.StorageAccountName
					$currentContext = New-AzStorageContext -StorageAccountName $this.UserConfig.StorageAccountName -StorageAccountKey $keys[0].Value -Protocol Https
					$caScanDataBlobObject = Get-AzStorageBlob -Container $this.CAMultiSubScanConfigContainerName -Blob $this.CATargetSubsBlobName -Context $currentContext -ErrorAction SilentlyContinue
					$caScanDataBlobContent = $null;
					if($null -ne $caScanDataBlobObject)
					{
						$caScanDataBlobContentObject = [AzHelper]::GetStorageBlobContent($this.AzSKCATempFolderPath, $this.CATargetSubsBlobName, $this.CATargetSubsBlobName, $this.CAMultiSubScanConfigContainerName, $currentContext)
						#$caScanDataBlobContentObject = Get-AzStorageBlobContent -Container $this.CAMultiSubScanConfigContainerName -Blob $this.CATargetSubsBlobName -Context $currentContext -Destination $($this.AzSKCATempFolderPath) -Force
						$caScanDataBlobContent = Get-ChildItem -Path "$($this.AzSKCATempFolderPath)\$($this.CATargetSubsBlobName)" -Force | Get-Content | ConvertFrom-Json
					}

					if(($caScanDataBlobContent | Measure-Object).Count -gt 0)
					{
						$caScanDataBlobContent | ForEach-Object {
							$CAScanDataInstance = $_;							
							$scanObject = [CAScanModel]::new($CAScanDataInstance.SubscriptionId, $CAScanDataInstance.LoggingOption);
							$existingScanObjects += $scanObject;
						}						
					}
				
					$caSubs = @();
					$tempCASubs = $this.ConvertToStringArray($this.TargetSubscriptionIds);
					$tempCASubs | ForEach-Object{
						if($_ -ne $this.SubscriptionContext.SubscriptionId -and $caSubs -notcontains $_)
						{
							$caSubs += $_;
						}
					}			

					$count = ($caSubs | Measure-Object).Count;
					$i = 0;
					$this.OutputObject.TargetSubs = @()
					$caSubs | ForEach-Object {
						try
						{
							$out = "" | Select-Object CentralSubscriptionId, TargetSubscriptionId, StorageAccountName, LoggingOption
							$i = $i + 1
							$caSubId = $_;
							$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`n[$i/$count] Configuring subscription for central scan: [$caSubId] `r`n" + [Constants]::DoubleDashLine);
							$out.CentralSubscriptionId = $this.SubscriptionContext.SubscriptionId;
							$out.TargetSubscriptionId = $caSubId;
							$out.LoggingOption = $this.LoggingOption.ToString();
							$out.StorageAccountName = $this.UserConfig.StorageAccountName;	
							
							Set-AzContext -SubscriptionId $caSubId | Out-Null
							$existingStorage = $null;
							try
							{
								$existingStorage = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
							}
							catch
							{
								#eat exception if storage is not preset
							}

							if(-not $this.SkipTargetSubscriptionConfig)
							{
								if($this.LoggingOption -eq [CAReportsLocation]::IndividualSubs)
								{
									#create new resource group/check if RG exists# 
				
									[Helpers]::CreateNewResourceGroupIfNotExists($this.AutomationAccount.CoreResourceGroup, $this.AutomationAccount.Location, $this.GetCurrentModuleVersion())			
									
									#recheck permissions
									$this.PublishCustomMessage("Checking SPN (AAD app id: $($this.CAAADApplicationID)) permissions on target subscriptions...")
									$this.SetCASPNPermissions($this.CAAADApplicationID)	
																						
									#region: Create/reuse existing storage account (Added this before creating variables since it's value is used in it)				
									$newStorageName = [string]::Empty
									#Check if storage exists
									
									if(($existingStorage|Measure-Object).Count -gt 0)
									{
										$this.PublishCustomMessage("Found existing AzSK storage account: [" + $existingStorage.Name + "]")
										#make storage compliant to azsk
										$this.ResolveStorageCompliance($existingStorage.Name, $existingStorage.ResourceId, $this.AutomationAccount.CoreResourceGroup, $this.CAScanOutputLogsContainerName)
										$out.StorageAccountName = $existingStorage.Name;
									}
									else
									{
										#create default storage
										$newStorageName = ("azsk" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"))
										$this.PublishCustomMessage("Creating Storage Account: [$newStorageName] for storing reports from CA scans.")
										$newStorage = [Helpers]::NewAzskCompliantStorage($newStorageName, $this.AutomationAccount.CoreResourceGroup, $existingAccount.Location) 
										if(!$newStorage)
										{
											throw ([SuppressedException]::new(($this.ExceptionMsg + "Failed to create storage account."), [SuppressedExceptionType]::Generic))
										}   
										else
										{
											#apply tags
											$timestamp = $(get-date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
											$this.ReportStorageTags += @{
												"CreationTime" = $timestamp;
												"LastModified" = $timestamp
											}
											Set-AzStorageAccount -ResourceGroupName $newStorage.ResourceGroupName -Name $newStorage.StorageAccountName -Tag $this.ReportStorageTags -Force -ErrorAction SilentlyContinue
										}
										$out.StorageAccountName = $newStorageName;
									}	
									try
									{
										$targetStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
										$this.OutputObject.StorageAccount = $targetStorageAccount | Select-Object Name, ResourceGroupName, Sku, Tags
									}
									catch
									{
										#eat exception if storage account is not found										
									}
									#endregion
								}
								else
								{
									#recheck permissions
									if(($existingStorage|Measure-Object).Count -gt 0)
									{
										$this.PublishCustomMessage("Found existing AzSK storage account: [" + $existingStorage.Name + "]")
										#make storage compliant to AzSK
										$this.ResolveStorageCompliance($existingStorage.Name, $existingStorage.ResourceId, $this.AutomationAccount.CoreResourceGroup, $this.CAScanOutputLogsContainerName)
										$out.StorageAccountName = $existingStorage.Name;
										$this.SetCASPNPermissions($this.CAAADApplicationID)
									}
									else
									{
										$this.PublishCustomMessage("Checking SPN (AAD app id: $($this.CAAADApplicationID)) permissions on target subscriptions...")
										$this.PublishCustomMessage("Configuring permissions for AzSK CA SPN. This may take a few min...")
										$this.SetSPNSubscriptionAccessIfNotAssigned($this.CAAADApplicationID)
									}
								}
							}

							$this.OutputObject.TargetSubs += $out
							$matchingScanObjects = $existingScanObjects | Where-Object {$_.SubscriptionId -eq $caSubId};
							if(($matchingScanObjects | Measure-Object).Count -gt 0)
							{
								$matchingScanObjects[0].LoggingOption = $this.LoggingOption;
							}
							else
							{
								$scanObject = [CAScanModel]::new($caSubId, $this.LoggingOption);
								$existingScanObjects += $scanObject;
							}
							
							$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`n[$i/$count] Completed configuring subscription for central scan: [$caSubId] `r`n" + [Constants]::DoubleDashLine);

							# Added Security centre provider registration to avoid error while running SSCore command in CA
							[SecurityCenterHelper]::RegisterResourceProviderNoException();
						}
						catch
						{
							$this.PublishCustomMessage("Failed to setup scan for $($this.SubscriptionContext.SubscriptionId)");
							$this.PublishException($_)
						}					
					}						
				}
				catch
				{
					$this.PublishException($_)
				}
				finally
				{
					#setting the context back to the parent subscription
					Set-AzContext -SubscriptionId $this.SubscriptionContext.SubscriptionId | Out-Null	
				}

				#add if the host subscription is not there in the current scanobjects 
				$matchingScanObjects = $existingScanObjects | Where-Object {$_.SubscriptionId -eq $this.SubscriptionContext.SubscriptionId};
				if(($matchingScanObjects | Measure-Object).Count -gt 0)
				{
					$matchingScanObjects[0].LoggingOption = $this.LoggingOption;
				}
				else
				{
					$scanObject = [CAScanModel]::new($this.SubscriptionContext.SubscriptionId, $this.LoggingOption);
					$existingScanObjects += $scanObject;
				}

				$fileName = "$($this.AzSKCATempFolderPath)\$($this.CATargetSubsBlobName)"

				if(-not (Split-Path -Parent $fileName | Test-Path))
				{
					mkdir -Path $(Split-Path -Parent $fileName) -Force
				}
				[Helpers]::ConvertToJsonCustom($existingScanObjects) | Out-File $fileName -Force
			
				$caStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
				$keys = Get-AzStorageAccountKey -ResourceGroupName $this.AutomationAccount.CoreResourceGroup  -Name $caStorageAccount.Name
				$currentContext = New-AzStorageContext -StorageAccountName $caStorageAccount.Name -StorageAccountKey $keys[0].Value -Protocol Https
				try
				{
					Get-AzStorageContainer -Name $this.CAMultiSubScanConfigContainerName -Context $currentContext -ErrorAction Stop | Out-Null
				}
				catch
				{
					New-AzStorageContainer -Name $this.CAMultiSubScanConfigContainerName -Context $currentContext | Out-Null
				}

				#Save the scan objects in blob stoage#
				[AzHelper]::UploadStorageBlobContent($fileName, $this.CATargetSubsBlobName, $this.CAMultiSubScanConfigContainerName, $currentContext)
				#Set-AzStorageBlobContent -File $fileName -Blob $this.CATargetSubsBlobName -Container $this.CAMultiSubScanConfigContainerName -BlobType Block -Context $currentContext -Force
			}
			#endregion		

			#region: update runbook & schedule
		
			#unlink CA main runbook from existing schedules
			$scheduledRunbooks = Get-AzAutomationScheduledRunbook -AutomationAccountName $this.AutomationAccount.Name `
				-ResourceGroupName $this.AutomationAccount.ResourceGroup | Where-Object {$_.RunbookName -eq $this.RunbookName}

			if(($scheduledRunbooks|Measure-Object).Count -gt 0)
			{
				#check if runbook exists to unlink schedules
			
				$scheduledRunbooks | ForEach-Object {
					UnRegister-AzAutomationScheduledRunbook -RunbookName $_.RunbookName -ScheduleName $_.ScheduleName `
						-ResourceGroupName $_.ResourceGroupName `
						-AutomationAccountName $_.AutomationAccountName -ErrorAction Stop -Force | Out-Null
				};
			}

			#Update required runbooks (remove + recreate runbook)
			$existingRunbooks = Get-AzAutomationRunbook -AutomationAccountName $this.AutomationAccount.Name `
				-ResourceGroupName $this.AutomationAccount.ResourceGroup
				
			#Update main runbook and alert runbook by default
			$runbooksToUpdate = @($this.RunbookName, [Constants]::AlertRunbookName)

			#update resource creation runbook only if switch is passed
			if($this.ScanOnDeployment -and -not $this.IsMultiCAModeOn -and -not $this.IsCentralScanModeOn)
			{
				$runbooksToUpdate += [Constants]::Alert_ResourceCreation_Runbook
			}

			$filteredRunbooksToUpdate = $existingRunbooks | Where-Object { $runbooksToUpdate -icontains $_.Name } 
			
			#remove existing and create new runbook
			if(($filteredRunbooksToUpdate|Measure-Object).Count -gt 0)
			{
				$filteredRunbooksToUpdate | Remove-AzAutomationRunbook -Force -ErrorAction SilentlyContinue
			}
			
			$this.NewCCRunbook()

			#Install resource creation runbook only for default stand-alone CA
			if($this.ScanOnDeployment -and -not $this.IsMultiCAModeOn -and -not $this.IsCentralScanModeOn)
			{
				$this.SetResourceCreationScan()
			}
			
			$this.SetAzSKAlertMonitoringRunbook($false)
		  
			#relink existing schedules with runbook
			if(($scheduledRunbooks|Measure-Object).Count -gt 0)
			{
				$scheduledRunbooks | ForEach-Object {
					Register-AzAutomationScheduledRunbook -RunbookName $this.RunbookName -ScheduleName $_.ScheduleName `
						-ResourceGroupName $_.ResourceGroupName `
						-AutomationAccountName $_.AutomationAccountName -ErrorAction Stop | Out-Null
				};
			}

			#initialize with 0 when the value is not passed. It would be set to default value while creating the schedule
			if([string]::IsNullOrWhiteSpace($this.AutomationAccount.ScanIntervalInHours))
			{
				$this.AutomationAccount.ScanIntervalInHours = 0;
			}
			$activeSchedules = $this.GetActiveSchedules($this.RunbookName)
			if(($activeSchedules|Measure-Object).Count -eq 0 -or $this.AutomationAccount.ScanIntervalInHours -ne 0)
			{
				#create default schedule 
				$this.NewCCSchedules()
			}
			#endregion
		
			#region :update CA Account tags

			$lastModifiedTimestamp = $(get-date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
			if($automationTags.ContainsKey("LastModified"))
			{
				$automationTags["LastModified"] = $lastModifiedTimestamp;
			}
			else
			{
				$automationTags.Add("LastModified", $lastModifiedTimestamp)
			}
			if($automationTags.ContainsKey("AzSKVersion"))
			{
				$automationTags["AzSKVersion"] = $this.GetCurrentModuleVersion();
			}
			else
			{
				$automationTags.Add("AzSKVersion",$this.GetCurrentModuleVersion())
			}
            $resourceInstance = $this.GetCABasicResourceInstance()
            if($resourceInstance)
            {
			    [Helpers]::SetResourceTags($resourceInstance.ResourceId, $automationTags, $false, $true);
            }
		
			#endregion

			#Added Security centre provider registration to avoid error while running SSCore command in CA
			[SecurityCenterHelper]::RegisterResourceProviderNoException();

			#update version tag
			$this.SetRunbookVersionTag()
		
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted updates to the Continuous Assurance setup`r`n", [MessageType]::Update)
			$messages += [MessageData]::new("The following resources/automation account assets were updated in your subscription by this command", $this.OutputObject)
		}
		catch
		{
			$this.PublishException($_)
		}
		return $messages;
	}

	[void] CleanUpOlderAssets()
	{
		#cleanup older schedules 
		Get-AzAutomationSchedule -ResourceGroupName $this.AutomationAccount.ResourceGroup -AutomationAccountName $this.AutomationAccount.Name | Where-Object { $_.Name -eq "Scan_Schedule" -or $_.Name -eq "Next_Run_Schedule"} | Remove-AzAutomationSchedule -Force
	}

	[MessageData[]] FormatGetCACheckMessage($checkCount, $description, $resultStatus, $resultMsg, $detailedMsg, $summaryTable)
	{
		[MessageData[]] $returnMsg = @();
		$messageType = $Null
		$commonFailMsg = [Constants]::SingleDashLine + "`r`nFound that AzSK Continuous Assurance (CA) is not correctly setup or functioning properly.`r`nReview the failed check and follow the remedy suggested. If it does not work, please file a support request after reviewing the FAQ.`r`n" + [Constants]::SingleDashLine;

		$newMsg = [MessageData]::new("Check $($checkCount.ToString("00")): $description", [MessageType]::Info)
		$this.PublishCustomMessage($newMsg)
		$returnMsg += $newMsg

		switch($resultStatus)
		{
			"OK" {$messageType = [MessageType]::Update}
			"Failed" {$messageType = [MessageType]::Error}
			"Skipped" {$messageType = [MessageType]::Warning}
			"Unhealthy" {$messageType = [MessageType]::Warning}
			"Warning" {$messageType = [MessageType]::Warning}
		}

		$newMsg = [MessageData]::new("Status:   $resultStatus. $resultMsg", $messageType)
		$returnMsg += $newMsg
		$this.PublishCustomMessage($newMsg);

		$this.PublishCustomMessage([MessageData]::new([Constants]::SingleDashLine));
		$returnMsg += [MessageData]::new([Constants]::SingleDashLine);
		if($null -ne $detailedMsg)
		{
			$returnMsg += $detailedMsg
		}
		if($summaryTable.Count -gt 0)
		{
			$summaryTable | ForEach-Object{
				$this.PublishCustomMessage($_)
			}
			$returnMsg += $summaryTable;		
		}
		if($resultStatus -eq "Failed")
		{
			$this.PublishCustomMessage([MessageData]::new("$commonFailMsg", [MessageType]::Warning))
			$returnMsg += $commonFailMsg
		}
		return $returnMsg
	}

	[MessageData[]] FormatGetCACheckMessage($checkCount, $description, $resultStatus, $resultMsg, $detailedMsg)
	{
		return ($this.FormatGetCACheckMessage($checkCount, $description, $resultStatus, $resultMsg, $detailedMsg, @()))
	}

	[MessageData[]] GetAzSKContinuousAssurance()
	{
		[MessageData[]] $messages = @();
		$stepCount = 0;
		$checkDescription = ""
		$resultMsg = ""
		$detailedMsg = $null
		$resultStatus = ""
		$shouldReturn = $false

		$currentMessage = [MessageData]::new([Constants]::DoubleDashLine + "`r`nStarted validating your AzSK Continuous Assurance (CA) setup...`r`n" + [Constants]::DoubleDashLine);
		$messages += $currentMessage;
		$this.PublishCustomMessage($currentMessage);
		
		#region:Step 1: Check if Automation Account with name "AzSKContinuousAssurance" exists in "AzSKRG", if no then display error message and quit, if yes proceed further
		$stepCount++
		$checkDescription = "Presence of CA Automation Account."
		$caAutomationAccount = $this.GetCADetailedResourceInstance()
		if($caAutomationAccount)
		{
			$caInstalledTimeInterval = ($(get-date).ToUniversalTime() - $caAutomationAccount.CreationTime.UtcDateTime).TotalMinutes
			$detailedMsg = "Interval between CA creation time and current time (in minutes): $caInstalledTimeInterval minutes."

			if($caInstalledTimeInterval -lt 120)
			{
				$resultMsg = "Please run this command after 2 hours of CA installation."
				$resultStatus = "Failed"
				$shouldReturn = $true		
			}
			else
			{
				$resultMsg = "Found the CA Automation Account: [$($caAutomationAccount.AutomationAccountName)]."
				$resultStatus = "OK"
			}
		}
		else
		{
			$resultMsg = "CA Automation Account: [$($this.AutomationAccount.Name)] is missing.`r`nPlease run command '$($this.InstallCommandName)'."
			$resultStatus = "Failed"			
			$shouldReturn = $true
		}
		$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg))
		if($shouldReturn)
		{
			return $messages
		}
		$detailedMsg = $Null
		#endregion
		
		#region: Display summary
		$noValueMsg = "NULL"
		$caSummaryTable = @{
			"AutomationAccountName" = $noValueMsg;
			"AppResourceGroupNames" = $noValueMsg;
			"OMSWorkspaceId" = $noValueMsg;
			"AltOMSWorkspaceId" = $noValueMsg;
			"LAWorkspaceId" = $noValueMsg;
			"AltLAWorkspaceId" = $noValueMsg;
			"WebhookUrl" = $noValueMsg;
			"AzureADAppID" = $noValueMsg;
			"AzureADAppName" = $noValueMsg;
			"CertificateExpiry" = $noValueMsg;
			"Runbooks" = $noValueMsg;
			"Schedules" = $noValueMsg;
			"RunbookVersion" = $noValueMsg;
			"AzSKReportsStorageAccountName" = $noValueMsg
		}
		$centralCASummaryTable = @{
			"TargetSubscriptionIds" = $noValueMsg;
		}
		$caOverallSummary = @()
		#Fetch automation account components
		$laWsId = $this.GetLogAnalyticsWorkspaceId()		
		$altLAWsId = $this.GetAltLogAnalyticsWorkspaceId()
		$webhookUrl = $this.GetWebhookURL()
		$appRGs = $this.GetAppRGs()
		$runbook = Get-AzAutomationRunbook -AutomationAccountName $this.AutomationAccount.Name `
			-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name $this.RunbookName -ErrorAction SilentlyContinue
		$activeSchedules = $this.GetActiveSchedules($this.RunbookName)
		$runAsConnection = $this.GetRunAsConnection()
		$runAsCertificate = Get-AzAutomationCertificate -AutomationAccountName $this.AutomationAccount.Name `
			-Name $this.CertificateAssetName `
			-ResourceGroupName $this.AutomationAccount.ResourceGroup -ErrorAction SilentlyContinue
		$reportsStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
		$azskCurrentCARunbookVersion = ""       
		$azskRG = Get-AzResourceGroup $this.AutomationAccount.CoreResourceGroup -ErrorAction SilentlyContinue
		if($null -ne $azskRG)
		{
			if(($azskRG.Tags | Measure-Object).Count -gt 0 -and $azskRG.Tags.ContainsKey($this.RunbookVersionTagName))
			{
				$azskCurrentCARunbookVersion = $azskRG.Tags[$this.RunbookVersionTagName]
			}
		}
		$azskLatestCARunbookVersion = [ConfigurationManager]::GetAzSKConfigData().AzSKCARunbookVersion
		
		$caSummaryTable.Item("AutomationAccountName") = $caAutomationAccount.AutomationAccountName
		if($laWsId)
		{
			$caSummaryTable.Item("OMSWorkspaceId") = $laWsId.Value
			$caSummaryTable.Item("LAWorkspaceId") = $laWsId.Value
		}

		if($altLAWsId)
		{
			$caSummaryTable.Item("AltOMSWorkspaceId") = $altLAWsId.Value
			$caSummaryTable.Item("AltLAWorkspaceId") = $altLAWsId.Value
		}

		if($webhookUrl)
		{
			$caSummaryTable.Item("WebhookUrl") = $webhookUrl.Value
		}

		if($appRGs)
		{
			$caSummaryTable.Item("AppResourceGroupNames") = $appRGs.Value	
		}

		$caSummaryTable.Item("Runbooks") = $runbook.Name -join ","
		#get schedules
		$scheduleList = @()
        if(($activeSchedules | Measure-Object).Count -gt 0)
        {
		    $activeSchedules|ForEach-Object{
		    	$scheduleList += ($_.Name + " (Frequency: " + $_.Interval + " " + $_.Frequency + ")")
		    }
            $caSummaryTable.Item("Schedules") = $scheduleList -join ","
        }

        if($runAsConnection)
        {
            $caSummaryTable.Item("AzureADAppID") = $runAsConnection.FieldDefinitionValues["ApplicationId"]
		    
            #find AD App name
		    $adApp = Get-AzADApplication -ApplicationId $runAsConnection.FieldDefinitionValues.ApplicationId -ErrorAction SilentlyContinue		
		    if($adApp)
		    {
		    	$caSummaryTable.Item("AzureADAppName") = $adApp.DisplayName
		    }
        }
        if($runAsCertificate)
        {
		    $caSummaryTable.Item("CertificateExpiry") = $runAsCertificate.ExpiryTime
        }

        if($reportsStorageAccount)
        {
		    $caSummaryTable.Item("AzSKReportsStorageAccountName") = $reportsStorageAccount.Name
		}
		
		$caSummaryTable.Item("RunbookVersion") = "Current version: [$azskCurrentCARunbookVersion] Latest version: [$azskLatestCARunbookVersion]"
		$caSummaryTable = $caSummaryTable.GetEnumerator() | Sort-Object -Property Name | Format-Table -AutoSize -Wrap | Out-String		
		$caOverallSummary += [MessageData]::new("Summary of CA configuration:", $caSummaryTable);
		$caOverallSummary += ([MessageData]::new([Constants]::SingleDashLine));
		if(![string]::IsNullOrWhiteSpace($this.TargetSubscriptionIds))
		{
			$centralCASummaryTable.Item("TargetSubscriptionIds") = $this.TargetSubscriptionIds	
			$caOverallSummary += ([MessageData]::new("Summary of central CA configuration:", $centralCASummaryTable));
			$caOverallSummary += ([MessageData]::new([Constants]::SingleDashLine));		
		}
		#endregion
		
		#region:Step 1.1: Check if the runbook version is recent
		$stepCount++

		$checkDescription = "Checking CA Runbook version."		
		$azskMinReqdRunbookVersion = [ConfigurationManager]::GetAzSKConfigData().AzSKCAMinReqdRunbookVersion
		if([string]::IsNullOrWhiteSpace($azskMinReqdRunbookVersion))
		{
			#If the value is empty, take the default version from the module code
			$azskMinReqdRunbookVersion = $this.MinReqdCARunbookVersion
		}
	
		if(![string]::IsNullOrWhiteSpace($azskCurrentCARunbookVersion) -and ([System.Version]$azskCurrentCARunbookVersion -ge [System.Version]$azskMinReqdRunbookVersion))
		{
			if([System.Version]$azskCurrentCARunbookVersion -ne [System.Version]$azskLatestCARunbookVersion)
			{
				$detailedMsg  = "AzSK current runbook version $([System.Version]$azskCurrentCARunbookVersion) and latest runbook version $([System.Version]$azskLatestCARunbookVersion)";
				$resultMsg  = "CA runbook is not current as per the required latest version. It is always recommended to update your runbook to the latest version possible by running the command: 'Update-AzSKContinuousAssurance -SubscriptionId <subId>'"
				$resultStatus = "Unhealthy"
			}
			else
			{
				$resultMsg = "CA runbook is healthy."
				$resultStatus = "OK"
			}
		}
		else
		{
			$resultMsg = "CA Runbook is too old.`r`nRun command 'Update-AzSKContinuousAssurance -SubscriptionId <subId>'."
			$resultStatus = "Failed"
			$shouldReturn = $true
		}	
		if($shouldReturn)
		{
			$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg, $caOverallSummary))		
			return $messages
		}
		else 
		{
			$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg))
		}
		$detailedMsg = $Null		
		#endregion

		#region:Step 2: Check if AzSK module is in available state in Assets. If no, then display error message
		$stepCount++
		$azskAutomationModuleList = Get-AzAutomationModule -AutomationAccountName $this.AutomationAccount.Name -ResourceGroupName $this.AutomationAccount.ResourceGroup 
		if(($azskAutomationModuleList | Measure-Object).Count -gt 0)
		{
			#Check the state of AzSK Module
			$azskModuleName = $this.GetModuleName().ToUpper()
			$checkDescription = "Inspecting CA module: [$azskModuleName]."
			$azskAutomationModule = $azskAutomationModuleList | Where-Object { $_.Name -eq $azskModuleName -and ($_.ProvisioningState -eq "Succeeded" -or $_.ProvisioningState -eq "Created")} 
			if(($azskAutomationModule | Measure-Object).Count -gt 0)
			{
				$azskModuleWithVersion = Get-AzAutomationModule -AutomationAccountName $this.AutomationAccount.Name `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup `
					-Name $azskModuleName
				$serverVersion = [System.Version] ([ConfigurationManager]::GetAzSKConfigData().GetLatestAzSKVersion($azskModuleName));
				if($azskModuleWithVersion.Version -ne $serverVersion)
				{
					$resultStatus = "Warning"
					$resultMsg = "CA is not running latest $azskModuleName version."
				}
				else
				{
					$resultMsg = "CA is running latest $azskModuleName version."
					$resultStatus = "OK"
				}
			}
			else
			{
				$failMsg = "$azskModuleName module is not available in automation account."
				$resolveMsg = "To resolve this please run command '$($this.RemoveCommandName)' followed by '$($this.InstallCommandName)'."
				$resultMsg = "$failMsg`r`n$resolveMsg"
				$resultStatus = "Failed"
				$shouldReturn = $true
			}
			if($shouldReturn)
			{
				$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg, $caOverallSummary))		
				return $messages
			}
			else 
			{
				$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg))
			}
			$detailedMsg = $Null
			#region: Step 3: Check the state of Azure Modules
			$stepCount++
			$checkDescription = "Inspecting CA Azure modules."
			if($this.ExhaustiveCheck)
			{				
				$azureAutomationModuleList = $azskAutomationModuleList | Where-Object { $_.Name -like "Azure*" -and $_.ProvisioningState -ne "Succeeded" -and $_.ProvisioningState -ne "Created"} 
				if(($azureAutomationModuleList | Measure-Object).Count -gt 0)
				{
					$missingModulesList = $azureAutomationModuleList.Name -join ","
					$failMsg = "One or more Azure module(s) are missing given below.`r`n$missingModulesList"
					$resolveMsg = "To resolve this please run command '$($this.RemoveCommandName)' command followed by '$($this.InstallCommandName)'."
					$resultMsg = "$failMsg`r`n$resolveMsg"
					$resultStatus = "Failed"
					$shouldReturn = $true				
				}
				else
				{	
					$resultMsg = ""	
					$resultStatus = "OK"
				}
			}
			else
			{
				$resultStatus = "Skipped"
				$resultMsg = "Use -ExhaustiveCheck option to include this."
			}
			if($shouldReturn)
			{
				$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg, $caOverallSummary))		
				return $messages
			}
			else 
			{
				$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg))
			}
			$detailedMsg = $Null				
			#endregion

			#region: Step 4: Check if all the dependent modules are loaded
			$stepCount++			
			$checkDescription = "Inspecting CA module: $($azskModuleName)'s dependent modules. This may take a few min..."
			if($this.ExhaustiveCheck)
			{
				$azskModuleWithVersion = Get-AzAutomationModule -AutomationAccountName $this.AutomationAccount.Name `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup `
					-Name $azskModuleName
				$azskServerModules = $this.GetDependentModules($azskModuleName,$azskModuleWithVersion.Version)
				$missingModules = @()
				$azskServerModules | ForEach-Object {
					$azskServerModule = $_.Name
					$automationModule = $azskAutomationModuleList | Where-Object { $_.Name -eq $azskServerModule -and ($_.ProvisioningState -eq "Succeeded" -or $_.ProvisioningState -eq "Created") } 
					if(($automationModule | Measure-Object).Count -eq 0)
					{
						$missingModules += $_.Name
					}	
				}
				if($missingModules.Count -gt 0)
				{
					$missingModulesString = $missingModules -join ","
					$detailedMsg = [MessageData]::new("Missing modules in the automation account:", $missingModules);					
					$resolveMsg = "To resolve this please run command '$($this.RemoveCommandName)' followed by '$($this.InstallCommandName)'."
					$failMsg = "One or more dependent module(s) are missing given below.`r`n$missingModulesString"			
					$resultMsg = "$failMsg`r`n$resolveMsg"
					$resultStatus = "Failed"
					$shouldReturn = $true	
				}
				else
				{
					$resultStatus = "OK"
					$resultMsg = "CA modules are correctly set up."
				}
			}
			else
			{
				$resultStatus = "Skipped"
				$resultMsg = "Use -ExhaustiveCheck option to include this."
			}
			if($shouldReturn)
			{
				$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg, $caOverallSummary))		
				return $messages
			}
			else 
			{
				$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg))
			}
			$detailedMsg = $Null							
			#endregion
		}
		else
		{			
			#this will never occur as default modules will be always there in automation account
		}
		#endregion

		#region: check if the subscription is running in the central scan mode

		$caSubs = @();
		[CAScanModel[]] $scanObjects = @();
		if(($reportsStorageAccount | Measure-Object).Count -eq 1)
		{
			$fileName = "$($this.AzSKCATempFolderPath)\$($this.CATargetSubsBlobName)"

			if(-not (Split-Path -Parent $fileName | Test-Path))
			{
				mkdir -Path $(Split-Path -Parent $fileName) -Force
			}
			$keys = Get-AzStorageAccountKey -ResourceGroupName $this.AutomationAccount.CoreResourceGroup -Name $reportsStorageAccount.Name
			$currentContext = New-AzStorageContext -StorageAccountName $reportsStorageAccount.Name -StorageAccountKey $keys[0].Value -Protocol Https
			$caScanDataBlobObject = Get-AzStorageBlob -Container $this.CAMultiSubScanConfigContainerName -Blob $this.CATargetSubsBlobName -Context $currentContext -ErrorAction SilentlyContinue 
			if($null -ne $caScanDataBlobObject)
			{
				$this.IsCentralScanModeOn = $true;
				$caScanDataBlobContentObject = [AzHelper]::GetStorageBlobContent($($this.AzSKCATempFolderPath), $this.CATargetSubsBlobName, $this.CATargetSubsBlobName, $this.CAMultiSubScanConfigContainerName, $currentContext)
				$caScanDataBlobContentObject = Get-AzStorageBlobContent -Container $this.CAMultiSubScanConfigContainerName -Blob $this.CATargetSubsBlobName -Context $currentContext -Destination $($this.AzSKCATempFolderPath) -Force
				$caScanDataBlobContent = Get-ChildItem -Path "$($this.AzSKCATempFolderPath)\$($this.CATargetSubsBlobName)" -Force | Get-Content | ConvertFrom-Json

				#create the active snapshot from the ca scan objects					
				$this.TargetSubscriptionIds = ""
				if(($caScanDataBlobContent | Measure-Object).Count -gt 0)
				{
					$caScanDataBlobContent | ForEach-Object {
						$CAScanDataInstance = $_;
						$scanObject = [CAScanModel]::new($CAScanDataInstance.SubscriptionId, $CAScanDataInstance.LoggingOption);
						$scanObjects += $scanObject;
						$caSubs += $CAScanDataInstance.SubscriptionId 
						$this.TargetSubscriptionIds = $this.TargetSubscriptionIds + "," + $CAScanDataInstance.SubscriptionId 							
					}
					$this.TargetSubscriptionIds = $this.TargetSubscriptionIds.SubString(1)
				}
			}
			#add the central sub if it is not being added as part of the scanobjects in the above step
			if(-not $caSubs.Contains($this.SubscriptionContext.SubscriptionId))
			{
				$caSubs += $this.SubscriptionContext.SubscriptionId;
				$scanObject = [CAScanModel]::new($this.SubscriptionContext.SubscriptionId, $this.LoggingOption);
				$scanObjects += $scanObject;
			}
		}

		#endregion

		#region: Step 5: Check if service principal is configured and it has 'Reader' access to subscription and 'Contributor' access to "AzSKRG". If either is missing display error message.
		$stepCount++
		$isPassed = $false
		$checkDescription = "Inspecting CA RunAs Account."
		if($runAsConnection)
		{			
			$this.CAAADApplicationID = $runAsConnection.FieldDefinitionValues.ApplicationId
			$spObject = Get-AzADServicePrincipal -ServicePrincipalName $this.CAAADApplicationID -ErrorAction SilentlyContinue
			$spName=""
			if($spObject)
			{
				$spName = $spObject.DisplayName
			}
			$haveSubscriptionRBACAccess = $true;
			$haveRGRBACAccess = $true;
			$haveAARGAccess = $true;
			$subRBACOutputs = @();
			$subStorageAccount = $null;
			if($this.IsCentralScanModeOn -and $this.ExhaustiveCheck)
			{			
				try
				{					
					$caSubs | ForEach-Object {
						try
						{
							$subRBACOutput = "" | Select-Object TargetSubscriptionId, HasSubscriptionCARBACAccess, HasRGCARBACAccess , HasRequiredAccessPermissions, IsStoragePresent 
							$subRBACOutput.TargetSubscriptionId = $_;
							Set-AzContext -SubscriptionId $subRBACOutput.TargetSubscriptionId | Out-Null
							try
							{
								$subStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
							}
							catch
							{
								#eat exception when storage is not present								
							}
							
							if($null -ne $subStorageAccount)
							{
								$subRBACOutput.HasRGCARBACAccess = $this.CheckServicePrincipalRGAccess($this.CAAADApplicationID);
								$subRBACOutput.IsStoragePresent = $true;
							}
							else
							{
								$subRBACOutput.HasRGCARBACAccess = $true;
								$subRBACOutput.IsStoragePresent = $false;
							}
							$subRBACOutput.HasSubscriptionCARBACAccess = $this.CheckSPSubscriptionAccess($this.CAAADApplicationID);
							$subRBACOutput.HasRequiredAccessPermissions = $true;
							$haveSubscriptionRBACAccess = $haveSubscriptionRBACAccess -and $subRBACOutput.HasSubscriptionCARBACAccess
							$haveRGRBACAccess = $haveRGRBACAccess -and $subRBACOutput.HasRGCARBACAccess
						}
						catch
						{
							$this.PublishCustomMessage("Failed to get the SPN permission details $($this.SubscriptionContext.SubscriptionId)");
							$subRBACOutput.HasSubscriptionCARBACAccess = $false;
							$subRBACOutput.HasRGCARBACAccess = $false;
							$subRBACOutput.HasRequiredAccessPermissions = $false;
							$haveSubscriptionRBACAccess = $false;
							$haveRGRBACAccess = $false;
							$this.PublishException($_)
						}
						$subRBACOutputs += $subRBACOutput;
					}
				}
				catch
				{
					$this.PublishException($_)
					$haveSubscriptionRBACAccess = $false;
					$haveRGRBACAccess = $false;
				}
				finally
				{
					#setting the context back to the parent subscription
					Set-AzContext -SubscriptionId $this.SubscriptionContext.SubscriptionId | Out-Null	
				}
				
				$detailedMsg = [MessageData]::new("TargetSubscriptions RBAC permissions data", $subRBACOutputs);
			}
			else
			{
				if($this.IsCentralScanModeOn -and !$this.ExhaustiveCheck)
				{
					$resultMsg = "Skipped the check for SPN access permissions on individual subscriptions. Use -ExhaustiveCheck option to include this."
					$resultStatus = "Warning"
				}
				#check permissions on core resource group
				$haveSubscriptionRBACAccess = $this.CheckSPSubscriptionAccess($this.CAAADApplicationID)
				$haveRGRBACAccess = $this.CheckServicePrincipalRGAccess($this.CAAADApplicationID)			
			}
			if($this.IsMultiCAModeOn)	
			{
				$haveAARGAccess = $this.CheckServicePrincipalRGAccess($this.CAAADApplicationID, $this.AutomationAccount.ResourceGroup, "Contributor")
			}
			
			if($haveSubscriptionRBACAccess -and $haveRGRBACAccess -and $haveAARGAccess)
			{
				$resultMsg = "RunAs Account is correctly set up."
				$resultStatus = "OK"
				$isPassed = $true
			}
			
			if(!$isPassed)
			{
				$failMsg = "Service principal account (Name: $($spName)) configured in RunAs Account  doesn't have required access ('Reader' access on Subscription and/or 'Contributor' access on resource group containing CA automation account)."
				$resolveMsg = "To resolve this you can provide required access to service principal manually from portal or run command '$($this.UpdateCommandName) -SubscriptionId <SubscriptionId> -FixRuntimeAccount."
				$resultMsg = "$failMsg`r`n$resolveMsg"
				$resultStatus = "Failed"
				$shouldReturn = $true
			}
		}
		else
		{
			$failMsg = "RunAs Account does not exist in automation account."
			$resolveMsg = "To resolve this run command '$($this.updateCommandName) -SubscriptionId <SubscriptionId> -FixRuntimeAccount'."
			$resultMsg = "$failMsg`r`n$resolveMsg"			
			$resultStatus = "Failed"
			$shouldReturn = $true			
		}
		if($shouldReturn)
		{
			$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg, $caOverallSummary))		
			return $messages
		}
		else 
		{
			$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg))
		}
		$detailedMsg = $Null				
		#endregion

		#region: step 6: Check if certificate expiry is in near future(in next 1 month) or it's expired
		$stepcount++
		$resolveMsg = "To resolve this please run command '$($this.UpdateCommandName) -SubscriptionId <SubscriptionId> -RenewCertificate'."
		$checkDescription = "Inspecting CA RunAs Certificate."

		if($runAsCertificate)
		{
			$detailedMsg = [MessageData]::new("CA certificate expiry date: [$($runAsCertificate.ExpiryTime.ToString("yyyy-MM-dd"))]");

			$adApp = Get-AzADApplication -ApplicationId $runAsConnection.FieldDefinitionValues.ApplicationId -ErrorAction SilentlyContinue
			if(($runAsCertificate.ExpiryTime.UtcDateTime - $(get-date).ToUniversalTime()).TotalMinutes -lt 0)
			{
				
				$failMsg = "CA Certificate is expired on $($runAsCertificate.ExpiryTime.ToString("yyyy-MM-dd")). CA SPN: [$($adApp.DisplayName)]"
				$resultMsg = "$failMsg`r`n$resolveMsg"			
				$resultStatus = "Failed"
				$shouldReturn = $true				
			}
			elseif(($runAsCertificate.ExpiryTime - $(get-date)).TotalDays -gt 0 -and ($runAsCertificate.ExpiryTime - $(get-date)).TotalDays -le 30)
			{
				$resolveMsg = "To avoid CA disruption due to credential expiry, please run command '$($this.UpdateCommandName) -RenewCertificate'."
				$failMsg = "CA Certificate is going to expire within next 30 days. Expiry date: [$($runAsCertificate.ExpiryTime.ToString("yyyy-MM-dd"))]. CA SPN: [$($adApp.DisplayName)]"
				$resultMsg = "$failMsg`r`n$resolveMsg"			
				$resultStatus = "Warning"
			}
			else
			{
				$resultMsg = "CA Certificate is correctly set up."
				$resultStatus = "OK"
			}
		}
		else
		{
			$failMsg = "CA Certificate does not exist in automation account."
			$resultMsg = "$failMsg`r`n$resolveMsg"			
			$resultStatus = "Failed"
			$shouldReturn = $true		
		}
		if($shouldReturn)
		{
			$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg, $caOverallSummary))		
			return $messages
		}
		else 
		{
			$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg))
		}
		$detailedMsg = $Null
		#endregion
				
		#region: Step 7: Check if reports storage account exists, if no then display error message
		$stepCount++
		$checkDescription = "Inspecting AzSK reports storage account."		
		$isStoragePresent = $true;
		$centralStorageAccountName = $reportsStorageAccount.Name;
		$targetSubStorageAccounts = @()
		if($this.IsCentralScanModeOn)
		{
			try
			{
				if(-not [string]::IsNullOrWhiteSpace($this.TargetSubscriptionIds))
				{
					$scanObjects | ForEach-Object {
						try
						{
							$targetSubStorageAccount = "" | Select-Object TargetSubscriptionId, StorageAccountName, LoggingOption, CentralStorageAccountName
							$targetSubStorageAccount.TargetSubscriptionId = $_.SubscriptionId;
							$targetSubStorageAccount.LoggingOption = $_.LoggingOption;
							$targetSubStorageAccount.CentralStorageAccountName = $centralStorageAccountName
							Set-AzContext -SubscriptionId $targetSubStorageAccount.TargetSubscriptionId  | Out-Null
							$reportsStorageAccount = $null;
							try
							{
								$reportsStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
							}
							catch
							{
								#eat exception in the case of no storage account found
							}
							if(($reportsStorageAccount | Measure-Object).Count -le 0)
							{
								if($_.LoggingOption -eq [CAReportsLocation]::IndividualSubs)
								{
									$isStoragePresent = $false
									$targetSubStorageAccount.StorageAccountName = "NotPresent";	
								}
							}
							else
							{								
								$targetSubStorageAccount.StorageAccountName = $reportsStorageAccount.Name;
							}
							$targetSubStorageAccounts += $targetSubStorageAccount;
						}
						catch
						{							
							$currentMessage = [MessageData]::new("Failed to fetch the storage account details $($this.SubscriptionContext.SubscriptionId)");
							$messages += $currentMessage;
							$this.PublishCustomMessage($currentMessage);
							$this.PublishException($_)
						}
					}
				}
			}
			catch
			{
				$this.PublishException($_)
				$isStoragePresent = $false
			}
			finally
			{
				#setting the context back to the parent subscription
				Set-AzContext -SubscriptionId $this.SubscriptionContext.SubscriptionId | Out-Null	
			}
			$detailedMsg = [MessageData]::new("Target Subscriptions storage account configuration:", $targetSubStorageAccounts);
		}
		else
		{
			$reportsStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage();
			if(($reportsStorageAccount|Measure-Object).Count -ne 1)
			{
				$isStoragePresent = $false;
			}
		}
		$resolveMsg = "To resolve this please run command '$($this.UpdateCommandName) -SubscriptionId <SubscriptionId>'."
		if($isStoragePresent)
		{
			#check if CA variable has correct value of storage account name
			$storageVariable = $this.GetReportsStorageAccountNameVariable()
			if($null -eq $storageVariable -or ($null -ne $storageVariable -and $storageVariable.Value.Trim() -eq [string]::Empty))
			{
				$failMsg = "One of the variable asset value is not correctly set up in CA Automation Account."
				$resultMsg  = "$failMsg`r`n$resolveMsg"
				$resultStatus = "Failed"
				$shouldReturn = $true
			}
			else 
			{
				$resultMsg = "AzSK reports storage account is correctly set up."
				$resultStatus = "OK"				
			}
			
		}
		else
		{
			$failMsg = "AzSK reports storage account does not exist."
			$resultMsg = "$failMsg`r`n$resolveMsg"
			$resultStatus = "Failed"
			$shouldReturn = $true
		}
		if($shouldReturn)
			{
				$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg, $caOverallSummary))		
				return $messages
			}
			else 
			{
				$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg))
			}
		$detailedMsg = $Null	
		#endregion
		
		#region: Step 8: Check App RG value in variables, if it's empty, display error message (this will not validate RGs)
		$stepCount++
		$resolveMsg = "To resolve this please run command '$($this.UpdateCommandName) -SubscriptionId <SubscriptionId> -ResourceGroupNames <AppResourceGroupNames>'."
		$checkDescription = "Inspecting configured App resource groups to be scanned by CA."
		if($null -eq $appRGs -or ($null -ne $appRGs -and $appRGs.Value.Trim() -eq [string]::Empty))
		{
			$failMsg = "The resource groups to be scanned by CA are not correctly set up."
			$resultMsg = "$failMsg`r`n$resolveMsg"
			$resultStatus = "Failed"
			$shouldReturn = $true
		}		
		else
		{
			$resultMsg = "The resource groups to be scanned by CA are correctly set up."
			$resultStatus = "OK"
		}
		if($shouldReturn)
		{
			$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg, $caOverallSummary))		
			return $messages
		}
		else 
		{
			$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg))
		}
		$detailedMsg = $Null
		#endregion	
		
		#region: Step 9: Check Log Analytics workspace configuration values in variables, if it's empty then display error message (this will not validate Log Analytics credentials)
		$stepCount++	
		$checkDescription = "Inspecting Log Analytics workspace configuration."        
		$isLogAnalyticsSettingSetup = !([string]::IsNullOrEmpty($laWsId)) -and $this.IsLAWorkspaceKeyVariableAvailable()
		$isAltLogAnalyticsSettingSetup = !([string]::IsNullOrEmpty($altLAWsId)) -and $this.IsAltLAWorkspaceKeyVariableAvailable()
		
        if(!$isLogAnalyticsSettingSetup -and !$isAltLogAnalyticsSettingSetup)
		{
			$failMsg = "Log Analytics workspace setting is not set up."			
			$resolveMsg = "To resolve this please run command '$($this.UpdateCommandName) -SubscriptionId <SubscriptionId> -LAWorkspaceId <LAWorkspaceId> -LAWSharedKey <LAWSharedKey>'."
			$resultMsg += "$failMsg`r`n$resolveMsg"
			$resultStatus = "Warning"
			$shouldReturn = $false
		}
		
		if($resultStatus -ne "Warning" )
		{
			$resultStatus = "OK"
			$resultMsg = ""				
		}
		if($shouldReturn)
		{
			$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg, $caOverallSummary))		
			return $messages 
		}
		else 
		{
			$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg))
		}
		$detailedMsg = $null

		#endregion
		
		#region: Step 10: Check if runbook exists
		$stepCount++
		$checkDescription = "Inspecting automation runbook."
		if(!$runbook)
		{
			$failMsg = "CA Runbook does not exist."
			$resolveMsg = "To resolve this run command '$($this.UpdateCommandName) -SubscriptionId <SubscriptionId>'."
			$resultMsg = "$failMsg`r`n$resolveMsg"
			$resultStatus = "Failed"
			$shouldReturn = $true
		}	
		else 
		{
			$resultMsg = "Runbook found."
			$resultStatus = "OK"
		}	
		if($shouldReturn)
		{
			$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg, $caOverallSummary))		
			return $messages
		}
		else 
		{
			$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg))
		}
		$detailedMsg = $Null	
		#endregion

		#region: Step 11: There should be an active schedule
		$stepCount++		
		$checkDescription = "Inspecting CA job schedules."
		if(($activeSchedules|Measure-Object).Count -eq 0)
		{
			$failMsg = "Runbook is not scheduled."			
			$resolveMsg = "To resolve this please run command '$($this.UpdateCommandName) -SubscriptionId <SubscriptionId>'."
			$resultMsg = "$failMsg`r`n$resolveMsg"
			$resultStatus = "Failed"
			$shouldReturn = $true
		}		
		else 
		{
			$resultMsg = "Active job schedule(s) found."
			$resultStatus = "OK"
		}
		$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg, $caOverallSummary))				
		if($shouldReturn)
		{
			return $messages
		}
		$detailedMsg = $Null	
		#endregion	

		#region: Step 12: Check if last job is not successful or job hasn't run in last 2 days
		$stepCount++		
		$recentJobs = Get-AzAutomationJob -ResourceGroupName $this.AutomationAccount.ResourceGroup `
			-AutomationAccountName $this.AutomationAccount.Name `
			-RunbookName $this.RunbookName | 
		Sort-Object LastModifiedTime -Descending |
		Select-Object -First 10
		if(($recentJobs|Measure-Object).Count -gt 0)
		{
			$lastJob = $recentJobs[0]
			if(($(get-date).ToUniversalTime() - $lastJob.LastModifiedTime.UtcDateTime).TotalHours -gt 48)
			{
				$checkDescription = "Inspecting CA executed jobs."
				$failMsg = "The CA scanning automation runbook (job) has not run in the last 48 hours. In normal functioning, CA scans run once every $($this.DefaultScanIntervalInHours) hours by default."
				$resolveMsg = "Please contact AzSK support team for a resolution."
				$resultMsg = "$failMsg`r`n$resolveMsg"
				$resultStatus = "Failed"
				$shouldReturn = $true
				$messages += ($this.FormatGetCACheckMessage($stepCount, $checkDescription, $resultStatus, $resultMsg, $detailedMsg, $caOverallSummary))	
			}
			else 
			{
				#display job summary
				$jobSummary = $recentJobs | Format-Table Status, @{Label="Duration (in Minutes)"; Expression={[math]::Round(($_.EndTime - $_.StartTime).TotalMinutes)}} | Out-String
				$messages += [MessageData]::new("Summary of recent jobs ($($this.RunbookName)):", $jobSummary);	
			}
		}	
		else
		{
			$messages += [MessageData]::new("Job history not found.");
		}
		
		#endregion

		if($this.ExhaustiveCheck)
		{			
			$currentMessage = [MessageData]::new("`r`nAzSK Continuous Assurance (CA) setup is in a healthy state on your subscription.`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
			$messages += $currentMessage;
			$this.PublishCustomMessage($currentMessage);
		}
		else
		{
			$currentMessage = [MessageData]::new("`r`nNo issues found in quick scan of AzSK Continuous Assurance (CA) setup. If you are still seeing problems with your CA setup, consider running with -ExhaustiveCheck flag for a deeper diagnosis.`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);	
			$messages += $currentMessage;
			$this.PublishCustomMessage($currentMessage);			
		}		
		return $messages
	}

	[bool] CheckAzSKContinuousAssurance()
	{
		[bool] $isHealthy = $true;
		try
		{
			#region:Step 1: Check if Automation Account with name "AzSKContinuousAssurance" exists in "AzSKRG", if no then display error message and quit, if yes proceed further
			$caAutomationAccount = $this.GetCABasicResourceInstance()
			if(($caAutomationAccount | Measure-Object).Count -le 0)
			{
				$isHealthy = $false;
				$currentMessage = [MessageData]::new("WARNING: Your subscription is not setup for Continuous Assurance monitoring. Your current org policy requires that you setup Continuous Assurance for all subscriptions.`nPlease request the subscription owner to set this up using instructions that were circulated for your org.", [MessageType]::Warning);
				$this.PublishCustomMessage($currentMessage);
			}
			#endregion
	
			#region:Step 1.1: Check if the runbook version is recent
			if($isHealthy)
			{
				$azskMinReqdRunbookVersion = [ConfigurationManager]::GetAzSKConfigData().AzSKCAMinReqdRunbookVersion
				if([string]::IsNullOrWhiteSpace($azskMinReqdRunbookVersion))
				{
					#If the value is empty, take the default version from the module code
					$azskMinReqdRunbookVersion = $this.MinReqdCARunbookVersion
				}
				$azskLatestCARunbookVersion = [ConfigurationManager]::GetAzSKConfigData().AzSKCARunbookVersion
				$azskCurrentCARunbookVersion = ""
				$azskRG = Get-AzResourceGroup $this.AutomationAccount.CoreResourceGroup -ErrorAction SilentlyContinue
				if($null -ne $azskRG)
				{
					if(($azskRG.Tags | Measure-Object).Count -gt 0 -and $azskRG.Tags.ContainsKey($this.RunbookVersionTagName))
					{
						$azskCurrentCARunbookVersion = $azskRG.Tags[$this.RunbookVersionTagName]
					}
				}
				#for older runbook there wont be any version tag it is considered as too old or less than the min required version it is considered too old
				if((![string]::IsNullOrWhiteSpace($azskCurrentCARunbookVersion) -and ([System.Version]$azskCurrentCARunbookVersion -lt [System.Version]$azskMinReqdRunbookVersion)) -or [string]::IsNullOrWhiteSpace($azskCurrentCARunbookVersion))
				{
					$isHealthy = $false
					$currentMessage = [MessageData]::new("WARNING: The runbook used by Continuous Assurance for this subscription is too old.`r`nPlease run command 'Update-AzSKContinuousAssurance -SubscriptionId <subId>'.", [MessageType]::Warning);
					$this.PublishCustomMessage($currentMessage);					
				}
			}
			#endregion
		}
		catch
		{
			$isHealthy = $false;
			$this.PublishCustomMessage("Not able to validate continuous assurance status for this subscription", [MessageType]::Error);
			$this.PublishException($_)
		}
		return $isHealthy;
	}

	[MessageData[]] RemoveAzSKContinuousAssurance($deleteStorageReports, $force)
	{
		[MessageData[]] $messages = @();
		$isCentralScanModeEnabled = $false;
		$this.PublishCustomMessage("This command will delete resources in your subscription which were installed by AzSK Continuous Assurance", [MessageType]::Warning);
		$messages += [MessageData]::new("This command will delete resources in your subscription which were installed by AzSK Continuous Assurance", [MessageType]::Warning);
		$runAsConnection = $null;
				
		#filter accounts with old/new name
		$existingAutomationAccount = $this.GetCADetailedResourceInstance()

		#region: check if central scanning mode is enabled on this subscription
		$caScanDataBlobContent = $null;
		$reportsStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage();
		[CAScanModel[]] $scanObjects = @()
		$caSubs = @();
		
		if(($reportsStorageAccount | Measure-Object).Count -eq 1)
		{
			$fileName = "$($this.AzSKCATempFolderPath)\$($this.CATargetSubsBlobName)"

			if(-not (Split-Path -Parent $fileName | Test-Path))
			{
				mkdir -Path $(Split-Path -Parent $fileName) -Force
			}
			$keys = Get-AzStorageAccountKey -ResourceGroupName $this.AutomationAccount.CoreResourceGroup -Name $reportsStorageAccount.Name
			$currentContext = New-AzStorageContext -StorageAccountName $reportsStorageAccount.Name -StorageAccountKey $keys[0].Value -Protocol Https
			$caScanDataBlobObject = Get-AzStorageBlob -Container $this.CAMultiSubScanConfigContainerName -Blob $this.CATargetSubsBlobName -Context $currentContext -ErrorAction SilentlyContinue 
			if($null -ne $caScanDataBlobObject)
			{
				$caScanDataBlobContentObject = [AzHelper]::GetStorageBlobContent($($this.AzSKCATempFolderPath), $this.CATargetSubsBlobName, $this.CATargetSubsBlobName, $this.CAMultiSubScanConfigContainerName, $currentContext)
				#$caScanDataBlobContentObject = Get-AzStorageBlobContent -Container $this.CAMultiSubScanConfigContainerName -Blob $this.CATargetSubsBlobName -Context $currentContext -Destination $($this.AzSKCATempFolderPath) -Force
				$caScanDataBlobContent = Get-ChildItem -Path "$($this.AzSKCATempFolderPath)\$($this.CATargetSubsBlobName)" -Force | Get-Content | ConvertFrom-Json
			}
		}
		if(($caScanDataBlobContent | Measure-Object).Count -gt 0)
		{
			$isCentralScanModeEnabled = $true;
			#if user has passed the targetsubscriptionIds then we need to just remove the stuff from the target subs only.
			$caScanDataBlobContent | ForEach-Object {
				$CAScanDataInstance = $_;							
				$scanObject = [CAScanModel]::new($CAScanDataInstance.SubscriptionId, $CAScanDataInstance.LoggingOption);
				$scanObjects += $scanObject;
			}
		}
		#endregion

		#throw error if perview switch is not passed are not passed and central mode is on
		if(-not $this.IsCentralScanModeOn -and $isCentralScanModeEnabled)
		{
			throw ([SuppressedException]::new("Central mode is on for this subscription. You need to pass 'CentralScanMode' switch to perform any modifications.", [SuppressedExceptionType]::InvalidArgument))
		}

		$isAutomationAccountRemoved = $false;
		
		if(-not $this.IsCentralScanModeOn -or [string]::IsNullOrWhiteSpace($this.TargetSubscriptionIds))
		{			
			if($existingAutomationAccount)
			{
				$existingAutomationAccount | ForEach-Object{
					#Initialize variables for confirmation pop ups
					$title = "Confirm"
					$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "This means Yes"
					$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "This means No"
					$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
					#below is hack for removing error due to strict mode - host variable is not assigned in the method 
					$host = $host
					# Ask for confirmation only if force switch is not present
					# Set the default value as false
					$result = 1
					if(!$force)
					{
						$accountConfirmMsg = "Are you sure you want to delete Continuous Assurance Automation Account '$($_.AutomationAccountName)'"
						# user confirmation 
						$result = $host.ui.PromptForChoice($title, $accountConfirmMsg, $options, 1)
					}
					if($result -eq 0 -or $force)
					{
						$runAsConnection = $this.GetRunAsConnection()
						#user selected yes
						Remove-AzAutomationAccount -ResourceGroupName $_.ResourceGroupName -name $_.AutomationAccountName -Force -ErrorAction stop
						$messages += [MessageData]::new("Removed Automation Account: [$($_.AutomationAccountName)] from resource group: [$($this.AutomationAccount.ResourceGroup)]")
						$this.PublishCustomMessage("Removed Automation Account: [$($_.AutomationAccountName)] from resource group: [$($this.AutomationAccount.ResourceGroup)]")
						$isAutomationAccountRemoved = $true;
						#remove version in AzSKRG
						$this.RemoveRunbookVersionTag()
					}
					else
					{
						#user selected no
						$messages += [MessageData]::new("You have chosen not to delete Automation Account: [$($_.AutomationAccountName)]")
						$this.PublishCustomMessage("You have chosen not to delete Automation Account: [$($_.AutomationAccountName)]")
					}
				}
			}
		}		

		if($this.IsCentralScanModeOn)
		{
			#user has passed the 'CentralScanMode' switch. This would clean up the logs storage containers across all the target subscriptions.
			if(($scanObjects | Measure-Object).Count -gt 0)
			{
				if($null -eq $runAsConnection)
				{
					$runAsConnection = $this.GetRunAsConnection()
				}
				if($runAsConnection)
				{			
					$this.CAAADApplicationID = $runAsConnection.FieldDefinitionValues.ApplicationId
				}
				if([string]::IsNullOrWhiteSpace($this.TargetSubscriptionIds))
				{
					$finalTargetSubs = $null;
					$toBeDeletedTargetSubs = $scanObjects;
				}
				else
				{
					$caSubs = @();
					$tempCASubs = $this.ConvertToStringArray($this.TargetSubscriptionIds);
					$tempCASubs | ForEach-Object{
						if($_ -ne $this.SubscriptionContext.SubscriptionId -and $caSubs -notcontains $_)
						{
							$caSubs += $_;
						}
					}			
					$finalTargetSubs = $scanObjects | Where-Object {$caSubs -notcontains $_.SubscriptionId};
					$toBeDeletedTargetSubs = $scanObjects | Where-Object {$caSubs -contains $_.SubscriptionId};
				}
				$this.DeleteResourcesFromTargetSubs($finalTargetSubs, $toBeDeletedTargetSubs, $this.CAAADApplicationID, $deleteStorageReports)
			}
			else
			{
				$this.PublishCustomMessage("No central scanning configuration found")
			}
		}
		elseif($deleteStorageReports)
		{
			$this.RemoveStorageReports($force);
		}	
			
		#DeleteStorageReports switch is present but no storage account found
		if($null -eq $existingAutomationAccount)
		{
			$messages += [MessageData]::new("Continuous Assurance (CA) is not configured in this subscription")
			$this.PublishCustomMessage("Continuous Assurance (CA) is not configured in this subscription")
		}
		return $messages
	}	

	[void] SetResourceCreationScan()
	{
		$alert = [Alerts]::new($this.SubscriptionContext.SubscriptionId, $this.invocationContext,"Mandatory");
		$actionGroupResourceId = $alert.SetupAlertActionGroup();
		$alert = [Alerts]::new($this.SubscriptionContext.SubscriptionId, $this.invocationContext, "Deployment,CICD");
		$alert.SetAlerts($actionGroupResourceId);
	}

	[void] ClearResourceofDeploymentScan()
	{
		Remove-AzAutomationRunbook -AutomationAccountName ($this.AutomationAccount.Name) -Name ([Constants]::Alert_ResourceCreation_Runbook) -ResourceGroupName $this.AutomationAccount.CoreResourceGroup -Force -ErrorAction SilentlyContinue
		$alert = [Alerts]::new($this.SubscriptionContext.SubscriptionId, $this.invocationContext, "Deployment,CICD");
		$alert.RemoveAlerts("WebHookForResourceCreationAlerts", $false);
		Remove-AzResource -ResourceType "Microsoft.Insights/actiongroups" -ResourceGroupName "AzSKRG" -Name ([Constants]::ResourceDeploymentActionGroupName) -Force
	}

	[void] SetAzSKAlertMonitoringRunbook($force)
	{
		[MessageData[]] $messages = @();

		try
		{
			$isAlertMonitoringEnabled = [ConfigurationManager]::GetAzSKConfigData().IsAlertMonitoringEnabled
			if($isAlertMonitoringEnabled)
			{
				if($force)
				{
					$this.NewAlertRunbook();
				}
				$alert = [Alerts]::new($this.SubscriptionContext.SubscriptionId, $this.invocationContext, "Mandatory");
				$alert.UpdateActionGroupWebhookUri([string]::Empty,"Alert");
			}
			#Left Else Block
		}
		catch
		{
			$this.PublishException($_)
		}
	}

	[void] RemoveAzSKAlertMonitoringWebhook($force)
	{
	    try
		{
			[MessageData[]] $messages = @();
			$alert = [Alerts]::new($this.SubscriptionContext.SubscriptionId, $this.invocationContext, "Mandatory");
			$alert.RemoveActionGroupWebhookUri();
		}
		catch
		{
			$this.PublishException($_)
		}
	}

	hidden [void] DeleteResourcesFromTargetSubs([CAScanModel[]] $finalTargetSubs, [CAScanModel[]] $toBeDeletedTargetSubs, [string] $caAADCentralSPN, [bool] $deleteStorageReports)
	{
		$this.PublishCustomMessage("Un-registering the subscriptions $($this.TargetSubscriptionIds) from central scan mode")
		$centralLogsDelete = $false;
		$toBeDeletedTargetSubs | Foreach-Object {
			$targetSub = $_;

			$this.PublishCustomMessage("Started for subscription: $($targetSub.SubscriptionId)");
			$messages += [MessageData]::new("Started for subscription: $($targetSub.SubscriptionId)");

			try
			{
				Set-AzContext -SubscriptionId $targetSub.SubscriptionId | Out-Null
				#step 1: Remove any permissions related to SPN in the target sub
				if(-not [string]::IsNullOrWhiteSpace($caAADCentralSPN))
				{
					$status = $this.RemoveServicePrincipalAccess($caAADCentralSPN);
					if(-not $status)
					{
						$this.PublishCustomMessage("Failed to get the SPN permission details $($targetSub.SubscriptionId)");
						$messages += [MessageData]::new("Failed to get the SPN permission details $($targetSub.SubscriptionId)");
					}
					else
					{
						$this.PublishCustomMessage("Removed central scanning CA SPN: $caAADCentralSPN");
						$messages += [MessageData]::new("Removed central scanning CA SPN: $caAADCentralSPN");
					}
				}
				else
				{
					$this.PublishCustomMessage("Couldnot find RunAs account for the AzSK automation account in subscription: $($targetSub.SubscriptionId)");
					$messages += [MessageData]::new("Couldnot find RunAs account for the AzSK automation account in subscription: $($targetSub.SubscriptionId)");
				}

				#step 2: Remove storage reports if delete reports switch is turned on
				if($deleteStorageReports)
				{
					$title = "Confirm"
					$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "This means Yes"
					$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "This means No"
					$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
					#below is hack for removing error due to strict mode - host variable is not assigned in the method 
					$host = $host
					$result = 1
					if(!$force)
					{
						$accountConfirmMsg = "Are you sure you want to delete CA execution logs?'"
						# user confirmation 
						$result = $host.ui.PromptForChoice($title, $accountConfirmMsg, $options, 1)
					}
					if($result -eq 0 -or $force)
					{
						#user selected yes
						if($targetSub.LoggingOption -ne  [CAReportsLocation]::CentralSub)
						{
							$this.PublishCustomMessage("Started cleaning up AzSK scan log reports from subscription: $($targetSub.SubscriptionId)")
							$messages += [MessageData]::new("Started cleaning up AzSK scan log reports from subscription: $($targetSub.SubscriptionId)")
							$this.RemoveStorageReports($true);					
						}
						else
						{
							$centralLogsDelete = $true;
						}
					}
					else
					{
						#user selected no
						$messages += [MessageData]::new("You have chosen not to delete CA execution logs")
						$this.PublishCustomMessage("You have chosen not to delete CA execution logs")
					}					
				}
			}
			catch
			{
				$this.PublishException($_)
			}
			finally
			{
				#setting the context back to the parent subscription
				Set-AzContext -SubscriptionId $this.SubscriptionContext.SubscriptionId | Out-Null	
			}
			if($centralLogsDelete)
			{
				$this.RemoveStorageReports($true);
			}
		}

		#region: remove the scanobject from the storage account
		$reportsStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage();
		$keys = Get-AzStorageAccountKey -ResourceGroupName $this.AutomationAccount.CoreResourceGroup -Name $reportsStorageAccount.Name
		$currentContext = New-AzStorageContext -StorageAccountName $reportsStorageAccount.Name -StorageAccountKey $keys[0].Value -Protocol Https

		#Persist only if there are more than one scan object. Count greater than 1 as to check if there are any other subscription apart from the central one
		if(($finalTargetSubs | Measure-Object).Count -gt 1)
		{
			$fileName = "$($this.AzSKCATempFolderPath)\$($this.CATargetSubsBlobName)"

			if(-not (Split-Path -Parent $fileName | Test-Path))
			{
				mkdir -Path $(Split-Path -Parent $fileName) -Force
			}
			[Helpers]::ConvertToJsonCustom($finalTargetSubs) | Out-File $fileName -Force							

			#get the scanobjects container
			try
			{
				Get-AzStorageContainer -Name $this.CAMultiSubScanConfigContainerName -Context $currentContext -ErrorAction Stop | Out-Null
			}
			catch
			{
				New-AzStorageContainer -Name $this.CAMultiSubScanConfigContainerName -Context $currentContext | Out-Null
			}
			
			#Save the scan objects in blob stoage#
			[AzHelper]::UploadStorageBlobContent($fileName, $this.CATargetSubsBlobName, $this.CAMultiSubScanConfigContainerName, $currentContext)
			#Set-AzStorageBlobContent -File $fileName -Blob $this.CATargetSubsBlobName -Container $this.CAMultiSubScanConfigContainerName -BlobType Block -Context $currentContext -Force
		}
		else
		{
			#Remove the scan objects container
			Remove-AzStorageContainer -Name $this.CAMultiSubScanConfigContainerName -Context $currentContext -Force
		}
		#endregion
	}

	hidden [void] RemoveStorageReports($force)
	{
		$existingStorage = $null;
		try
		{
			$existingStorage = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
		}
		catch
		{
			#eat exception in the case of no storage account found
		}

		if(($existingStorage | Measure-Object).Count -gt 0)
		{
			$keys = Get-AzStorageAccountKey -ResourceGroupName $existingStorage.ResourceGroupName -Name $existingStorage.Name 
			$storageContext = New-AzStorageContext -StorageAccountName $existingStorage.Name -StorageAccountKey $keys[0].Value -Protocol Https
			$existingContainer = Get-AzStorageContainer -Name $this.CAScanOutputLogsContainerName -Context $storageContext -ErrorAction SilentlyContinue
						
			if($existingContainer)
			{
				#Initialize variables for confirmation pop ups
				$title = "Confirm"
				$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "This means Yes"
				$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "This means No"
				$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
				#below is hack for removing error due to strict mode - host variable is not assigned in the method 
				$host = $host
				# Ask for confirmation only if force switch is not present
				$result = 0
				if(!$force)
				{
					#user confirmation before deleting container
					$storageConfirmMsg = "Are you sure you want to delete '$($this.CAScanOutputLogsContainerName)' container in storage account '$($existingStorage.Name)' which contains security scan logs/reports ?"
					$result = $host.ui.PromptForChoice($title, $storageConfirmMsg, $options, 1)
				}
				if($result -eq 0)
				{
					#user selected yes			
					$existingContainer | Remove-AzStorageContainer -Force -ErrorAction SilentlyContinue
					if((Get-AzStorageContainer -Name $this.CAScanOutputLogsContainerName -Context $storageContext -ErrorAction SilentlyContinue|Measure-Object).Count -eq 0)
					{
						#deleted successfully in confirmation box
						$messages += [MessageData]::new("Removed container: [$($this.CAScanOutputLogsContainerName)] from storage account: [$($existingStorage.Name)]")
						$this.PublishCustomMessage("Removed container: [$($this.CAScanOutputLogsContainerName)] from storage account: [$($existingStorage.Name)]")
					}
					else
					{
						#error occurred
						$messages += [MessageData]::new("Error occurred while removing container: [$($this.CAScanOutputLogsContainerName)] from storage account: [$($existingStorage.Name)]. Please check your access permissions and try again.")
						$this.PublishCustomMessage("Error occurred while removing container: [$($this.CAScanOutputLogsContainerName)] from storage account: [$($existingStorage.Name)]. Please check your access permissions and try again.")
					}
				}
				#user selected no in confirmation box
				else
				{
					$messages += [MessageData]::new("You have chosen not to delete container: [$($this.CAScanOutputLogsContainerName)] from storage account: [$($existingStorage.Name)]")
					$this.PublishCustomMessage("You have chosen not to delete container: [$($this.CAScanOutputLogsContainerName)] from storage account: [$($existingStorage.Name)]")
				}
			}
		}
		else
		{
			$this.PublishCustomMessage("AzSK reports storage account doesn't exist in resource group: [$($this.AutomationAccount.CoreResourceGroup)]")
		}
	}

	hidden [bool] RemoveServicePrincipalAccess([string] $caAADSPN)
	{
		#fetch SP permissions
		try
		{
			Get-AzRoleAssignment -serviceprincipalname $caAADSPN | Remove-AzRoleAssignment
		}
		catch
		{
			return $false;
		}
		return $true;		
	}
	
	#region: Internal functions for install/update CA

	hidden [PSObject] GetCABasicResourceInstance()
	{
        if(($null -ne $this.AutomationAccount) -and ($null -eq $this.AutomationAccount.BasicResourceInstance))
        {
            $this.AutomationAccount.BasicResourceInstance = Get-AzResource -ResourceGroupName $this.AutomationAccount.ResourceGroup -Name $this.AutomationAccount.Name -ErrorAction SilentlyContinue
        }
		return $this.AutomationAccount.BasicResourceInstance
	}

    hidden [PSObject] GetCADetailedResourceInstance()
	{
        if(($null -ne $this.AutomationAccount) -and ($null -eq $this.AutomationAccount.DetailedResourceInstance))
        {
            $this.AutomationAccount.DetailedResourceInstance = Get-AzAutomationAccount -ResourceGroupName $this.AutomationAccount.ResourceGroup -Name $this.AutomationAccount.Name -ErrorAction SilentlyContinue
        }
		return $this.AutomationAccount.DetailedResourceInstance
	}

	hidden [bool] IsCAInstallationValid()
	{
		$isValid = $true
		$automationResources = Get-AzResource -ResourceGroupName $this.AutomationAccount.ResourceGroup -ResourceType "Microsoft.Automation/automationAccounts"
		if(($automationResources|Measure-Object).Count)
		{
			$isValid = $false
		}
		return $isValid
	}

	hidden [void] DeployCCAutomationAccountItems()
	{				
		#Create CA scan runbook
		$this.NewCCRunbook()

		#Create CA alerts runbook
		$this.SetAzSKAlertMonitoringRunbook($false)

		if($this.ScanOnDeployment -and -not $this.IsMultiCAModeOn -and -not $this.IsCentralScanModeOn)
		{
			$this.SetResourceCreationScan()
		}

		#$this.PublishCustomMessage("Linking schedule - ["+$this.ScheduleName+"] to the runbook")
		$this.NewCCSchedules()

		#$this.PublishCustomMessage("Creating variables")
		$this.NewCCVariables()
	}

	hidden [void] NewEmptyAutomationAccount()
	{
		#region :check if resource provider is registered
		[Helpers]::RegisterResourceProviderIfNotRegistered("Microsoft.Automation");
		#endregion

		#Add tags
		$timestamp = $(get-date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
		$this.AutomationAccount.AccountTags += @{
			"AzSKFeature" = "ContinuousAssurance";
			"AzSKVersion"=$this.GetCurrentModuleVersion();
			"CreationTime"=$timestamp;
			"LastModified"=$timestamp
		}

		$this.OutputObject.AutomationAccount  = New-AzAutomationAccount -ResourceGroupName $this.AutomationAccount.ResourceGroup `
			-Name $this.AutomationAccount.Name -Location $this.AutomationAccount.Location `
			-Plan Basic -Tags $this.AutomationAccount.AccountTags -ErrorAction Stop | Select-Object AutomationAccountName, Location, Plan, ResourceGroupName, State, Tags
	}

	hidden [void] NewCCRunbook()
	{
		$CCRunbook = [Runbook]@{
			Name = $this.RunbookName;
            Type = "PowerShell";
			Description = "This runbook is responsible for running subscription health scan and resource scans (SVTs). It also keeps all modules up to date.";
			LogProgress = $false;
			LogVerbose = $false;
			Key="Continuous_Assurance_Runbook"
        }	
		
		if($this.ScanOnDeployment -and -not $this.IsMultiCAModeOn -and -not $this.IsCentralScanModeOn)
		{
		  $ResourceAddition_Runbooks = [Runbook]@{
			  Name = "Continuous_Assurance_ScanOnTrigger_Runbook";
			  Type = "PowerShell";
			  Description = "This runbook will be triggered on Resource Addition.";
			  LogProgress = $false;
			  LogVerbose = $false;
			  Key="Continuous_Assurance_ScanOnTrigger_Runbook"
			}
			$this.Runbooks += @($CCRunbook,$ResourceAddition_Runbooks)
		}
		else
		{
			$this.Runbooks += @($CCRunbook)
		}

		$isAlertMonitoringEnabled = [ConfigurationManager]::GetAzSKConfigData().IsAlertMonitoringEnabled
		if($isAlertMonitoringEnabled)
		{
			$InsightAlertRunbook = [Runbook]@{
				Name = "Alert_Runbook";
				Type = "PowerShell";
				Description = "This runbook will be triggered on InsightAlerts.";
				LogProgress = $false;
				LogVerbose = $false;
				Key="Insight_Alerts_Runbook"
			}
			
			$this.Runbooks += @($InsightAlertRunbook)
		}

		$this.Runbooks | ForEach-Object{
			$this.PublishCustomMessage("Updating runbook: [$($_.Name)]")
			$filePath = $this.AddConfigValues($_.Name+".ps1");
			
			Import-AzAutomationRunbook -Name $_.Name -Description $_.Description -Type $_.Type `
				-Path $filePath `
				-LogProgress $_.LogProgress -LogVerbose $_.LogVerbose `
				-AutomationAccountName $this.AutomationAccount.Name `
				-ResourceGroupName $this.AutomationAccount.ResourceGroup -Published -ErrorAction Stop
			
			#cleanup
			Remove-Item -Path $filePath -Force
		}
		$this.OutputObject.Runbooks = $this.Runbooks | Select-Object Name, Description, Type
	}

	hidden [void] NewAlertRunbook()
	{
		$InsightAlertRunbook = [Runbook]@{
			Name = "Alert_Runbook";
            Type = "PowerShell";
			Description = "This runbook will be triggered on InsightAlerts.";
			LogProgress = $false;
			LogVerbose = $false;
			Key="Insight_Alerts_Runbook"
        }
		$this.Runbooks += @($InsightAlertRunbook)

		$this.Runbooks | ForEach-Object{		
			$filePath = $this.AddConfigValues($_.Name+".ps1");
			
			Import-AzAutomationRunbook -Name $_.Name -Description $_.Description -Type $_.Type `
				-Path $filePath `
				-LogProgress $_.LogProgress -LogVerbose $_.LogVerbose `
				-AutomationAccountName $this.AutomationAccount.Name `
				-ResourceGroupName $this.AutomationAccount.ResourceGroup -Published -ErrorAction Stop
			
			#cleanup
			Remove-Item -Path $filePath -Force
		}
		$this.OutputObject.Runbooks = $this.Runbooks | Select-Object Name, Description, Type
	}

	hidden [void] NewCCSchedules()
	{
		$ScanSchedule = $null
		if($this.AutomationAccount.ScanIntervalInHours -eq 0)
		{
			$this.AutomationAccount.ScanIntervalInHours = $this.DefaultScanIntervalInHours;
		}
		if($this.RunbookSchedules.count -eq 0)
		{
			$ScanSchedule = [RunbookSchedule]@{
				Name = $this.ScheduleName;
				Frequency = [ScheduleFrequency]::Hour;
				Interval = $this.AutomationAccount.ScanIntervalInHours;
				Description = "Scheduling job to scan subscription and app resource groups";
				StartTime = ([System.DateTime]::Now.AddMinutes(10));
				LinkedRubooks = @($this.RunbookName);
				Key = "CA_Scan_Schedule"
			}
			$this.RunbookSchedules += @($ScanSchedule)
		}

		$this.RunbookSchedules | ForEach-Object{
			$scheduleName = $_.Name

			#remove existing schedule if exists
			if((Get-AzAutomationSchedule -Name $scheduleName `
				-ResourceGroupName $this.AutomationAccount.ResourceGroup `
				-AutomationAccountName $this.AutomationAccount.Name `
				-ErrorAction SilentlyContinue|Measure-Object).Count -gt 0)
			{
				Remove-AzAutomationSchedule -Name $scheduleName `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup `
					-AutomationAccountName $this.AutomationAccount.Name -Force `
					-ErrorAction Stop
			}
			#create new schedule
			New-AzAutomationSchedule -AutomationAccountName $this.AutomationAccount.Name -Name $scheduleName `
				-ResourceGroupName $this.AutomationAccount.ResourceGroup -StartTime $_.StartTime `
				-Description $_.Description -HourInterval $_.Interval -ErrorAction Stop
			
			$_.LinkedRubooks | ForEach-Object{
				Register-AzAutomationScheduledRunbook -RunbookName $_ -ScheduleName $scheduleName `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup `
					-AutomationAccountName $this.AutomationAccount.Name -ErrorAction Stop
			}
		}
		$this.OutputObject.Schedules = @()
		$this.RunbookSchedules | ForEach-Object{
			$this.OutputObject.Schedules += @{"Name"=$_.Name;"Frequency"=$_.Frequency;"Interval"=$_.Interval;"Description"=$_.Description}
		}
	}

	hidden [void] NewCCVariables()
	{	
		$varAppRG = [Variable]@{
			Name = [Constants]::AppResourceGroupNames;
			Value = $this.UserConfig.ResourceGroupNames;
			IsEncrypted = $false;
			Description ="Comma separated list of resource groups that have to be scanned ( '*' implies all resource groups present in the subscription at the time of scanning)."
        }

		$varStorageName = [Variable]@{
			Name = [Constants]::ReportsStorageAccountName;
			Value = $this.UserConfig.StorageAccountName;
			IsEncrypted = $false;					
			Description ="Name of storage account where CA scan reports will be stored"
        }

		#LAWSettings
		$varOMSWorkspaceId = [Variable]@{
			Name = [Constants]::OMSWorkspaceId;
			Value = $this.UserConfig.LAWCredential.LAWorkspaceId;
			IsEncrypted = $false;
			Description ="Log Analytics Workspace Id"
        }
		$varOMSSharedKey = [Variable]@{
			Name = [Constants]::OMSSharedKey;
			Value = $this.UserConfig.LAWCredential.LAWSharedKey;
			IsEncrypted = $false;
			Description ="Log Analytics Workspace Shared Key"
        }
		$varLAWorkspaceId = [Variable]@{
			Name = [Constants]::LAWorkspaceId;
			Value = $this.UserConfig.LAWCredential.LAWorkspaceId;
			IsEncrypted = $false;
			Description ="Log Analytics Workspace Id"
        }
		$varLAWSharedKey = [Variable]@{
			Name = [Constants]::LAWSharedKey;
			Value = $this.UserConfig.LAWCredential.LAWSharedKey;
			IsEncrypted = $false;
			Description ="Log Analytics Workspace Shared Key"
        }

		$this.Variables += @($varAppRG, $varOMSWorkspaceId, $varOMSSharedKey, $varLAWorkspaceId, $varLAWSharedKey, $varStorageName)

		#AltLAWSettings
		if($null -ne $this.UserConfig.AltLAWCredential -and -not [string]::IsNullOrWhiteSpace($this.UserConfig.AltLAWCredential.LAWorkspaceId) -and -not [string]::IsNullOrWhiteSpace($this.UserConfig.AltLAWCredential.LAWSharedKey))
		{
			$varAltOMSWorkspaceId = [Variable]@{
				Name = [Constants]::AltOMSWorkspaceId;
				Value = $this.UserConfig.AltLAWCredential.LAWorkspaceId;
				IsEncrypted = $false;
				Description ="Alternate Log Analytics Workspace Id"
			}
			$varAltOMSSharedKey = [Variable]@{
				Name = [Constants]::AltOMSSharedKey;
				Value = $this.UserConfig.AltLAWCredential.LAWSharedKey;
				IsEncrypted = $false;
				Description ="Alternate Log Analytics Workspace Shared Key"
			}
			$varAltLAWorkspaceId = [Variable]@{
				Name = [Constants]::AltLAWorkspaceId;
				Value = $this.UserConfig.AltLAWCredential.LAWorkspaceId;
				IsEncrypted = $false;
				Description ="Alternate Log Analytics Workspace Id"
			}
			$varAltLAWSharedKey = [Variable]@{
				Name = [Constants]::AltLAWSharedKey;
				Value = $this.UserConfig.AltLAWCredential.LAWSharedKey;
				IsEncrypted = $false;
				Description ="Alternate Log Analytics Workspace Shared Key"
			}
			$this.Variables += @($varAltOMSWorkspaceId, $varAltOMSSharedKey, $varAltLAWorkspaceId, $varAltLAWSharedKey)
		}

		#Webhook settings
		if($null -ne $this.UserConfig.WebhookDetails -and -not [string]::IsNullOrWhiteSpace($this.UserConfig.WebhookDetails.Url))
		{
			$varWebhookUrl = [Variable]@{
				Name = [Constants]::WebhookUrl;
				Value = $this.UserConfig.WebhookDetails.Url;
				IsEncrypted = $false;
				Description ="Webhook Url"
			}
			$this.Variables += @($varWebhookUrl)
		}
		if($null -ne $this.UserConfig.WebhookDetails -and -not [string]::IsNullOrWhiteSpace($this.UserConfig.WebhookDetails.AuthZHeaderName) `
			-and -not [string]::IsNullOrWhiteSpace($this.UserConfig.WebhookDetails.AuthZHeaderValue))
		{
			$varWebhookAuthZHeaderName = [Variable]@{
				Name = [Constants]::WebhookAuthZHeaderName;
				Value = $this.UserConfig.WebhookDetails.AuthZHeaderName;
				IsEncrypted = $false;
				Description ="Webhook AuthZ header name"
			}
			$varWebhookAuthZHeaderValue = [Variable]@{
				Name = [Constants]::WebhookAuthZHeaderValue;
				Value = $this.UserConfig.WebhookDetails.AuthZHeaderValue;
				IsEncrypted = $true;
				Description ="Webhook AuthZ header value"
			}
			$this.Variables += @($varWebhookAuthZHeaderName, $varWebhookAuthZHeaderValue)
		}
		#UpdateToLatestVersion flag
        <#$varUpdateToLatestFlag = [Variable]@{
				Name = [Constants]::UpdateToLatestVersion;
				Value = [ConfigurationManager]::GetAzSKConfigData().UpdateToLatestVersion
				IsEncrypted = $false;
				Description ="CA will download latest available AzSK module from PSGallery if specified value is 'True'"
			}	#>

		$this.Variables|ForEach-Object{
			New-AzAutomationVariable -Name $_.Name -Encrypted $_.IsEncrypted `
				-Description $_.Description -Value $_.Value `
				-ResourceGroupName $this.AutomationAccount.ResourceGroup `
				-AutomationAccountName $this.AutomationAccount.Name -ErrorAction Stop
		}
		$this.OutputObject.Variables = $this.Variables | Select-Object Name, Description
	}
	
	hidden [void] NewCCAzureRunAsAccount($newRuntimeAccount)
	{		
		#Handle the case when user hasn't specified the AAD App name for CA.
        $azskADAppName = ""
        $spnReused = $false
        $appID = ""
        try
		{	
            $azskSPNFormatString = $this.AzSKLocalSPNFormatString
            if($this.IsCentralScanModeOn)
            {
				$azskSPNFormatString = $this.AzSKCentralSPNFormatString				
			}
			
			if(![string]::IsNullOrWhiteSpace($this.AutomationAccount.AzureADAppName))
            {
                $azskADAppName = $this.AutomationAccount.AzureADAppName
            }
            elseif($newRuntimeAccount)
            {
                $azskADAppName = ($azskSPNFormatString + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"))	
            }
            else
            {
				$subscriptionScope = "/subscriptions/{0}" -f $this.SubscriptionContext.SubscriptionId
                
                $azskRoleAssignments = Get-AzRoleAssignment -Scope $subscriptionScope -RoleDefinitionName Reader | Where-Object { $_.DisplayName -like "$($azskSPNFormatString)*" }
				$assignmentCount = ($azskRoleAssignments | Measure-Object).Count
			    if($assignmentCount -gt 0)
			    {				
				    $this.PublishCustomMessage("Configuring the runtime account for CA...")
				    $this.PublishCustomMessage("Found $assignmentCount previously setup runtime accounts for AzSK CA. Checking if one of them can be reused...")
				    foreach($azskRoleAssignment  in $azskRoleAssignments)
				    {	
					    try
					    {
						    $this.PublishCustomMessage("Trying account: [" + $azskRoleAssignment.DisplayName + "]")
                            #get aad app id from service principal object detail
                            $aadApplication = $null
                            $spDetail = Get-AzADServicePrincipal -ObjectId $azskRoleAssignment.ObjectId
                            if($spDetail)
                            {
                                $aadApplication = Get-AzADApplication -ApplicationId $spDetail.ApplicationId
                            }
                            else
                            {
								throw;
							}
							#SP not found, continue to next SP
		                    if($aadApplication)
		                    {
								$this.SetCAAzureRunAsAccount($azskRoleAssignment.DisplayName,$aadApplication.ApplicationId)
							}
                            $spnReused = $true
                            $appID = $aadApplication.ApplicationId
                            $this.PublishCustomMessage("You have 'Owner' permission on [$($azskRoleAssignment.DisplayName)]. Configuring CA with this SPN.")
                            break;
						    #set this flag to identify whether clean up AD App is needed in case of exception 
						    #$this.IsExistingADApp = $true
					    }	
					    catch
					    {
						    #left blank intentionally to continue checking next SP
						}
					}
			    }
			    #Compute the new AAD CA App name. As there was no pre-configured CA AAD App on this subscription or didn't have the permission to update the existing AAD app
                if(!$spnReused)
                {
                    $azskADAppName = ($azskSPNFormatString + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"))	
				}
			}
            if(!$spnReused)
            {
                $appID = $this.CreateServicePrincipalIfNotExists($azskADAppName)
	            $this.SetCAAzureRunAsAccount($azskADAppName,$appID)
            }
            #assign SPN permissions
            $this.SetCASPNPermissions($appID)
            if($this.IsMultiCAModeOn)
            {
	            $haveAARGAccess = $this.CheckServicePrincipalRGAccess($appID, $this.AutomationAccount.ResourceGroup, "Contributor")
	            if(!$haveAARGAccess)
	            {
		            $this.SetServicePrincipalRGAccess($appID, $this.AutomationAccount.ResourceGroup, "Contributor")
	            }
            }
			$this.PublishCustomMessage("Successfully configured AzSK CA Automation Account with SPN.")
		}
		catch
		{
			$this.PublishCustomMessage("There was an error while setting up the AzSK CA SPN")
			throw ($_)
		}
	}

    hidden [void] NewCCAzureRunAsAccount()
    {
       #by default NewRuntimeAccount = false, reuse the SPN if found
       $this.NewCCAzureRunAsAccount($false)
    }

	hidden [void] UpdateCCAzureRunAsAccount()
	{
		try
		{
			#fetch existing AD App used in connection
			$appID = ""
			$connection = Get-AzAutomationConnection -AutomationAccountName $this.AutomationAccount.Name `
				-ResourceGroupName  $this.AutomationAccount.ResourceGroup -Name $this.ConnectionAssetName -ErrorAction Stop
		
			$appID = $connection.FieldDefinitionValues.ApplicationId
			$azskADAppName = (Get-AzADApplication -ApplicationId $connection.FieldDefinitionValues.ApplicationId -ErrorAction stop).DisplayName		
			$this.CAAADApplicationID = $appID;
			
			$this.SetCAAzureRunAsAccount($azskADAppName, $appID)

            #assign SPN permissions
            $this.SetCASPNPermissions($appID)
            if($this.IsMultiCAModeOn)
            {
	            $haveAARGAccess = $this.CheckServicePrincipalRGAccess($appID, $this.AutomationAccount.ResourceGroup, "Contributor")
	            if(!$haveAARGAccess)
	            {
		            $this.SetServicePrincipalRGAccess($appID, $this.AutomationAccount.ResourceGroup, "Contributor")
	            }
			}
		}	
		catch
		{
			$this.PublishCustomMessage("There was an error while setting up the AzSK CA SPN")
			throw ($_)
		}	
	}
	
    hidden [string] CreateServicePrincipalIfNotExists([string] $azskADAppName)
    {
		$aadApplication = Get-AzADApplication -DisplayNameStartWith $azskADAppName | Where-Object -Property DisplayName -eq $azskADAppName
		if(($aadApplication | measure-object).Count -gt 1)
		{
			$this.PublishCustomMessage("Found more than one AAD applications with name: [$azskADAppName] in the directory. Can't reuse AAD app.")
			throw;
		}
		elseif(($aadApplication | measure-object).Count -eq 1)
		{
			$this.PublishCustomMessage("Found AAD application in the directory: [$azskADAppName]")

			#set this flag to identify whether clean up AD App is needed in case of exception 
			$this.IsExistingADApp = $true
		}
		else
		{
			$this.PublishCustomMessage("Creating new AAD application: [$azskADAppName]. This may take a few min...")
				
			#create new AAD App
			$aadApplication = New-AzADApplication -DisplayName $azskADAppName `
				-HomePage ("https://" + $azskADAppName) `
				-IdentifierUris ("https://" + $azskADAppName) -ErrorAction Stop
				
			Start-Sleep -Seconds 30

			#create new SP
			$this.PublishCustomMessage("Creating new service principal (SPN) for the AAD application. This will be used as the runtime account for AzSK CA")
			New-AzADServicePrincipal -ApplicationId $aadApplication.ApplicationId -ErrorAction Stop | Out-Null   
				
			Start-Sleep -Seconds 30                         
		}
        return $aadApplication.ApplicationId
    }

    hidden [void] SetCAAzureRunAsAccount([string] $azskADAppName, [string] $appId)
    {
        $pfxFilePath = $null
		$thumbPrint = $null
        try
        {
            #create new self-signed certificate 
            $this.PublishCustomMessage("Generating new credential for AzSK CA SPN")
		    $selfsignedCertificate = [ActiveDirectoryHelper]::NewSelfSignedCertificate($azskADAppName, $this.CertificateDetail.CertStartDate, $this.CertificateDetail.CertEndDate, $this.CertificateDetail.Provider)
			
		    #create password
			     
		    $secureCertPassword = [Helpers]::NewSecurePassword()

		    $pfxFilePath = $env:TEMP+ "\temp.pfx"
		    Export-PfxCertificate -Cert $selfsignedCertificate -Password $secureCertPassword -FilePath $pfxFilePath | Out-Null 
		    $publicCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(, $selfsignedCertificate.GetRawCertData())
			
            try
            {
                #Authenticating AAD App service principal with newly created certificate credential  
		        [ActiveDirectoryHelper]::UpdateADAppCredential($appId, $publicCert, $this.CertificateDetail.CredStartDate, $this.CertificateDetail.CredEndDate, "False")
            }
            catch
            {
                $this.PublishCustomMessage("There was an error while updating its credentials. You may not have 'Owner' permission on it.");
			    throw;
            }
        
		    $thumbPrint =  $publicCert.thumbPrint
        
            #remove existing certificate if exists
		    $this.RemoveCCAzureRunAsCertificateIfExists()

		    #create certificate asset 
		    $newCertificateAsset = $this.NewCCCertificate($pfxFilePath, $secureCertPassword)

		    # Remove existing connection
		    $this.RemoveCCAzureRunAsConnectionIfExists()
		
		    # Create a Automation connection asset named AzureRunAsConnection in the Automation account. This connection uses the updated service principal.
		    $newConnectionAsset = $this.NewCCConnection($appId, $thumbPrint)
        
            $this.CAAADApplicationID = $appId;

            $this.OutputObject.AzureRunAsConnection = $newConnectionAsset |  Select-Object Name, Description, ConnectionTypeName
            $this.OutputObject.AzureRunAsCertificate = $newCertificateAsset | Select-Object Name, Description, CreationTime, ExpiryTime, LastModifiedTime
    	}
        finally
        {
            #cleanup pfx file 
			if($pfxFilePath)
			{
				Remove-Item -Path $pfxFilePath -Force -ErrorAction SilentlyContinue
			}

			#cleanup certificate
			$CertStore = New-Object System.Security.Cryptography.X509Certificates.X509Store([System.Security.Cryptography.X509Certificates.StoreName]::My, [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser)
			$CertStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
			if($thumbPrint)
			{
				$tempCert = $CertStore.Certificates.Find("FindByThumbprint", $thumbPrint, $FALSE)
				if($tempCert)
				{
					$CertStore.Remove($tempCert[0]) 
				}
			}
        }     
    }
    
    hidden [void] SetCASPNPermissions([string] $appId)
    {
		$this.PublishCustomMessage("Configuring permissions for AzSK CA SPN. This may take a few min...")
		$this.SetSPNSubscriptionAccessIfNotAssigned($appId)
        $this.SetSPNRGAccessIfNotAssigned($appId)
    }
    
	hidden [string] AddConfigValues([string] $fileName)
	{
		$outputFilePath = "$Env:LOCALAPPDATA\$fileName";

		$ccRunbook = $this.LoadServerConfigFile($fileName)
		#append escape character (`) before '$' symbol
		$policyStoreUrl	= [ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl.Replace('$',"``$")		
		$coreSetupSrcUrl = [ConfigurationManager]::GetAzSKConfigData().CASetupRunbookURL.Replace('$',"``$")
		$azskCARunbookVersion = [ConfigurationManager]::GetAzSKConfigData().AzSKCARunbookVersion
		$telemetryKey = ""
		$azureEnv = [ConfigurationManager]::GetAzSKSettings().AzureEnvironment
		$managementUri =[WebRequestHelper]::GetServiceManagementUrl() 
		if([RemoteReportHelper]::IsAIOrgTelemetryEnabled())
		{
			$telemetryKey = [RemoteReportHelper]::GetAIOrgTelemetryKey()
		}
		$ccRunbook | Foreach-Object {
			$temp1 = $_ -replace "\[#automationAccountRG#\]", $this.AutomationAccount.ResourceGroup;
			$temp2 = $temp1 -replace "\[#automationAccountName#\]", $this.AutomationAccount.Name;
			$temp3 = $temp2 -replace "\[#OnlinePolicyStoreUrl#\]", $policyStoreUrl;
			$temp4 = $temp3 -replace "\[#CoreSetupSrcUrl#\]", $coreSetupSrcUrl;
			$temp5 = $temp4 -replace "\[#EnableAADAuthForOnlinePolicyStore#\]", $this.ConvertBooleanToString([ConfigurationManager]::GetAzSKSettings().EnableAADAuthForOnlinePolicyStore);
			$temp6 = $temp5 -replace "\[#UpdateToLatestVersion#]", $this.ConvertBooleanToString([ConfigurationManager]::GetAzSKConfigData().UpdateToLatestVersion);
			$temp7 = $temp6 -replace "\[#telemetryKey#\]", $telemetryKey;
			$temp8 = $temp7 -replace "\[#AzureEnvironment#\]", $azureEnv;
			$temp9 = $temp8 -replace "\[#ManagementUri#\]", $managementUri;
			$temp9 -replace "\[#runbookVersion#\]", $azskCARunbookVersion;
		}  | Out-File $outputFilePath
		
		return $outputFilePath
	}
	hidden [string] ConvertBooleanToString($boolValue)
	{
		switch($boolValue)
		{
			"true"{
				return "true"
			}
            "false"{
				return "false"
			}
		}
		return "false" #adding this to prevent error all path doesn't return value"
	}
	
	hidden [void] UpdateVariable($variableObject)
	{	
		#remove existing and create new variable
		$existingVariable = Get-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name -ResourceGroupName $this.AutomationAccount.ResourceGroup -Name $variableObject.Name -ErrorAction SilentlyContinue
		if(($existingVariable | Measure-Object).Count -gt 0)
		{
			$existingVariable | Remove-AzAutomationVariable -ErrorAction Stop
		}
		$newVariable = New-AzAutomationVariable -Name $variableObject.Name `
			-Description $variableObject.Description`
			-Encrypted $variableObject.IsEncrypted `
			-Value $variableObject.Value `
			-ResourceGroupName $this.AutomationAccount.ResourceGroup `
			-AutomationAccountName $this.AutomationAccount.Name -ErrorAction Stop 
		
		$this.OutputObject.Variables += ($newVariable | Select-Object Name, Description, Value) 
	}

	hidden [void] RemoveCCAzureRunAsConnectionIfExists()
	{
		#remove existing azurerunasconnection
		if((Get-AzAutomationConnection -Name $this.ConnectionAssetName -ResourceGroupName $this.AutomationAccount.ResourceGroup `
			-AutomationAccountName $this.AutomationAccount.Name -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
		{
			Remove-AzAutomationConnection -ResourceGroupName $this.AutomationAccount.ResourceGroup`
				-AutomationAccountName $this.AutomationAccount.Name -Name $this.ConnectionAssetName -Force -ErrorAction Stop
		}
	}

	hidden [void] RemoveCCAzureRunAsCertificateIfExists()
	{
		#remove existing certificate
		$isCertPresent = Get-AzAutomationCertificate -ResourceGroupName $this.AutomationAccount.ResourceGroup `
			-AutomationAccountName $this.AutomationAccount.Name -Name $this.CertificateAssetName -ErrorAction SilentlyContinue
		if($isCertPresent)
		{
			Remove-AzAutomationCertificate -ResourceGroupName $this.AutomationAccount.ResourceGroup `
				-AutomationAccountName $this.AutomationAccount.Name -Name $this.CertificateAssetName -ErrorAction SilentlyContinue
		}
	}
	
	hidden [PSObject] NewCCConnection($appId, $thumbPrint)
	{
		$tenantId = (Get-AzContext -ErrorAction Stop).Tenant.Id
		$connectionFieldValues = @{
			"ApplicationId" = $appID;
			"TenantId" = $tenantId;
			"CertificateThumbprint" = $thumbPrint;
			"SubscriptionId" = $this.SubscriptionContext.SubscriptionId
		}
		
		$newConnectionAsset = New-AzAutomationConnection -ResourceGroupName $this.AutomationAccount.ResourceGroup `
			-AutomationAccountName  $this.AutomationAccount.Name -Name $this.ConnectionAssetName -ConnectionTypeName AzureServicePrincipal `
			-ConnectionFieldValues $connectionFieldValues -Description "This connection authenticates runbook with service principal" -ErrorAction Stop

		return $newConnectionAsset
	}

	hidden [PSObject] NewCCCertificate($pfxFilePath, [Security.SecureString] $secureCertPassword)
	{
		$newCertificateAsset = New-AzAutomationCertificate -ResourceGroupName $this.AutomationAccount.ResourceGroup -AutomationAccountName $this.AutomationAccount.Name `
			-Path $pfxFilePath -Name $this.CertificateAssetName -Password $secureCertPassword -ErrorAction Stop

		return $newCertificateAsset
	}
	
	hidden [void] UploadModule($moduleName, $moduleVersion)
	{
		$this.PublishCustomMessage("Could not find required module: [$moduleName] version: [$moduleVersion]. Adding it. This may take a few min...")
		$searchResult = $this.SearchModule($moduleName, $moduleVersion)
		if($searchResult)
		{
			$moduleName = $SearchResult.title.'#text' # get correct casing for the Module name
			$packageDetails = Invoke-RestMethod -Method Get -UseBasicParsing -Uri $searchResult.id  
			$moduleVersion = $packageDetails.entry.properties.version
		
			#Build the content URL for the nuget package
			$publicPSGalleryUrl = [ConfigurationManager]::GetAzSKConfigData().PublicPSGalleryUrl
			$azskPSGalleryUrl = [ConfigurationManager]::GetAzSKConfigData().AzSKRepoURL
			$moduleContentUrl = "$publicPSGalleryUrl/api/v2/package/$moduleName/$moduleVersion"
         
			if($moduleName -imatch "AzSK*")
			{
				$moduleContentUrl = "$azskPSGalleryUrl/api/v2/package/$moduleName/$moduleVersion"
			}

			# Find the actual blob storage location of the Module
			do {
				$actualUrl = $moduleContentUrl
				$moduleContentUrl = (Invoke-WebRequest -Uri $moduleContentUrl -MaximumRedirection 0 -UseBasicParsing -ErrorAction Ignore).Headers.Location 
			} while(!$moduleContentUrl.Contains(".nupkg"))

			$automationModule = New-AzAutomationModule `
				-ResourceGroupName $this.AutomationAccount.ResourceGroup `
				-AutomationAccountName $this.AutomationAccount.Name `
				-Name $moduleName `
				-ContentLink $actualUrl

			$this.OutputObject.Modules += ($automationModule | Select-Object Name)
			$automationModule = Get-AzAutomationModule -ResourceGroupName $this.AutomationAccount.ResourceGroup -AutomationAccountName $this.AutomationAccount.Name -Name $moduleName

			while(
				$automationModule.ProvisioningState -ne "Created" -and
				$automationModule.ProvisioningState -ne "Succeeded" -and
				$automationModule.ProvisioningState -ne "Failed"
			)
			{
				#Module is in extracting state
				Start-Sleep -Seconds 120
				$automationModule = $automationModule | Get-AzAutomationModule
			}                
		}
	}

	hidden [PSObject] SearchModule($moduleName, $moduleVersion)
	{
		$url = [string]::Empty
		$PSGalleryUrlComputed = [ConfigurationManager]::GetAzSKConfigData().PublicPSGalleryUrl
		
		if($moduleName -imatch "AzSK*")
		{
			$PSGalleryUrlComputed = [ConfigurationManager]::GetAzSKConfigData().AzSKRepoURL
		}

		if([string]::IsNullOrWhiteSpace($moduleVersion))
		{
			$queryString = "`$filter=IsLatestVersion&searchTerm=%27$ModuleName%27&includePrerelease=false&`$skip=0&`$top=40&`$orderby=Version%20desc"
		}
		else
		{
			$queryString = "searchTerm=%27$ModuleName%27&includePrerelease=false&`$filter=Version%20eq%20%27$ModuleVersion%27"
		}	
		$url = "$PSGalleryUrlComputed/api/v2/Search()?$queryString"
		$searchResult = Invoke-RestMethod -Method Get -Uri $url -UseBasicParsing
    
		if(!$searchResult) 
		{
			throw "Could not find module $moduleName"         
		}
		else
		{
			$searchResult = $searchResult | Where-Object -FilterScript {
					return $_.title.'#text' -eq $moduleName
			}  
			#filter for module version
			if(![string]::IsNullOrWhiteSpace($moduleVersion)) {
					$searchResult = $searchResult | Where-Object -FilterScript {
						return $_.properties.version -eq $moduleVersion
				}
			}
			return $searchResult
		}
	}

	hidden [PSObject] CheckCAModuleHealth($moduleName, $azskVersion)
	{
		$moduleVersion = [string]::Empty
		$azskDependentModules = @()
		$outputObj = New-Object PSObject
		Add-Member -InputObject $outputObj -MemberType NoteProperty -Name isModuleValid -Value $false
		Add-Member -InputObject $outputObj -MemberType NoteProperty -Name moduleVersion -Value ""
		$azskModule = $this.GetModuleName();
		
		#get existing module details
		$existingModule = Get-AzAutomationModule -AutomationAccountName $this.AutomationAccount.Name `
			-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name $moduleName `
			| Where-Object {($_.IsGlobal -ne $true) -and ($_.ProvisioningState -eq "Succeeded" -or $_.ProvisioningState -eq "Created")}
		
		#Get required module version
		if([string]::IsNullOrWhiteSpace($azskVersion))
		{
			$azskModuleWithVersion = Get-AzAutomationModule -AutomationAccountName $this.AutomationAccount.Name `
				-ResourceGroupName $this.AutomationAccount.ResourceGroup `
				-Name $azskModule
			if(($azskModuleWithVersion|Measure-Object).Count -ne 0)
			{
				$azskVersion = $azskModuleWithVersion.Version;
			}
		}
		
		if(-not [string]::IsNullOrWhiteSpace($azskVersion))
		{
			$azskDependentModules += $this.GetDependentModules($azskModule, $azskVersion)
		}
		else
		{
			$azskDependentModules += $this.GetDependentModules($azskModule, $null)
		}
		$requiredModule = $azskDependentModules | Where-Object{$_.Name -eq $moduleName}

		#check if module is not in intended state
		$outputObj.moduleVersion = $requiredModule.Version
		if(($existingModule|Measure-Object).Count -eq 0 -or [System.Version]($existingModule.Version) -ne $outputObj.moduleVersion)
		{
			$outputObj.isModuleValid = $false
		}
		else
		{
			$outputObj.isModuleValid = $true
		}
		return $outputObj			
	}
	
	hidden [void] ConvertToGlobalModule($moduleName)
	{
		$azskModule=$this.GetModuleName().ToUpper()
		$moduleVersion=[string]::Empty

		$existingModule = Get-AzAutomationModule -AutomationAccountName $this.AutomationAccount.Name `
			-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name $moduleName `
			| Where-Object {$_.IsGlobal -ne $true}

		if(($existingModule|Measure-Object).Count -ne 0)
		{
			#remove module, hence it will be converted to global module
			Remove-AzAutomationModule -AutomationAccountName $this.AutomationAccount.Name `
				-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name $moduleName -Force -ErrorAction Stop | Out-Null
		}
	} 
	
	hidden [PSObject] GetDependentModules($moduleName, $moduleVersion)
	{
		$tempHashTable = @{}
		$dependentModuleList = @()
		
		$searchResult = $this.SearchModule($moduleName,$moduleVersion)
		$packageDetails = Invoke-RestMethod -Method Get -UseBasicParsing -Uri $searchResult.id
        $dependencies = $packageDetails.entry.properties.dependencies
        if($dependencies)
        {
            $dependencies = $dependencies.Split("|")
            # parse dependencies, which are in the format: Module1name:[Module1version]:|Module2name:[Module2version]
            for($index=0;($index -lt $dependencies.count) -and (![string]::IsNullOrWhiteSpace($dependencies[$index]));$index++)
			{
                $dependentModuleDetail = $dependencies[$index].Split(":")
				$dependentModuleName = $dependentModuleDetail[0]
				$dependentModuleVersion = $dependentModuleDetail[1].Replace('[','').Replace(']','').Split(',')[0]
				#Add dependent module to the result list
                if(!$tempHashTable.Contains($dependentModuleName))
                {
                    $tempHashTable += @{
						$dependentModuleName = $dependentModuleVersion
					}
                }
            }
			$tempHashTable.Keys|ForEach-Object{
				$newModule = New-Object PSCustomObject
				$newModule | Add-Member -type NoteProperty -name Name -Value ($_)
				$newModule | Add-Member -type NoteProperty -name Version -Value ($tempHashTable.Item($_))
				$dependentModuleList += $newModule
			}
        }
		return $dependentModuleList
	}

	hidden [void] FixCAModules()
	{
		$automationModuleName = "Az.Automation"
		$storageModuleName = "Az.Storage"
        $profileModuleName = "Az.Accounts"
		$dependentModules = @()
		$this.OutputObject.Modules = @() 
		
		#get the dependent modules as per server config
		$azskModuleName = $this.GetModuleName();
		$serverVersion = [System.Version] ([ConfigurationManager]::GetAzSKConfigData().GetLatestAzSKVersion($azskModuleName));

		#Check if module is in intended state
		#check whether automation module is in healthy and required version state. Since profile is dependent of Automation module, it will also get checked as  part of automation module
		$automationModuleResult = $this.CheckCAModuleHealth($automationModuleName, $serverVersion)
		$dependentModules = $this.GetDependentModules($automationModuleName, $automationModuleResult.moduleVersion)
		
		#check health of dependent modules and fix if unhealthy
		$dependentModules|ForEach-Object{
			$currentModuleName = $_.Name
            $this.PublishCustomMessage("Inspecting CA module: [$currentModuleName]")
			$dependentModuleResult = $this.CheckCAModuleHealth($currentModuleName, $serverVersion)
			#dependent module is not in expected state
			if($dependentModuleResult.isModuleValid -ne $true)
			{
				#convert storage module to global module first to upload dependent modules successfully
				$this.ConvertToGlobalModule($storageModuleName)
				$this.UploadModule($_.Name, $dependentModuleResult.moduleVersion)
			}
			else
			{
				$this.PublishCustomMessage("Found module: [$currentModuleName]")
			}
		}
		$storageModuleResult = $this.CheckCAModuleHealth($storageModuleName, $serverVersion)
		if($storageModuleResult.isModuleValid -ne $true)
		{
			$this.UploadModule($storageModuleName, $storageModuleResult.moduleVersion)
		}
		if($automationModuleResult.isModuleValid -ne $true)
		{
			$this.UploadModule($automationModuleName, $automationModuleResult.moduleVersion)
		}

        #remove AzSK/AzureRm modules so that runbook can fix all the modules
		$deleteModuleList = Get-AzAutomationModule -ResourceGroupName $this.AutomationAccount.ResourceGroup -AutomationAccountName $this.AutomationAccount.Name  -ErrorAction SilentlyContinue | `
			Where-Object {$_.Name -eq "Az.*" -or $_.Name -ilike 'azsk*'} 
        
        if(($deleteModuleList | Measure-Object).Count -gt 0)
        {
            $deleteModuleList | ForEach-Object{
                $this.PublishCustomMessage("Deleting module: [$($_.Name)] from the account...")   
                Remove-AzAutomationModule -Name $deleteModuleList.Name -AutomationAccountName $this.AutomationAccount.Name -ResourceGroupName $this.AutomationAccount.ResourceGroup -Force -ErrorAction SilentlyContinue
			}
			$this.PublishCustomMessage("Required modules will be imported automatically when the next CA scan commences.")
		}
		
		#start the runbook once the modules are fixed and runbook will try to complete the scan
		Start-AzAutomationRunbook -Name $this.RunbookName -ResourceGroupName $this.AutomationAccount.ResourceGroup -AutomationAccountName $this.AutomationAccount.Name -ErrorAction SilentlyContinue | Out-Null		 
	}
	
	hidden [void] ResolveStorageCompliance($storageName, $resourceId, $resourceGroup, $containerName)
	{
		$controlSettings = $this.LoadServerConfigFile("ControlSettings.json");
	    $storageObject = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageName -ErrorAction Stop
	    $keys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageName 
	    $currentContext = New-AzStorageContext -StorageAccountName $storageName -StorageAccountKey $keys[0].Value -Protocol Https
	
		#Azure_Storage_AuthN_Dont_Allow_Anonymous
		$keys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageName		
		$storageContext = New-AzStorageContext -StorageAccountName $storageName -StorageAccountKey $keys[0].Value -Protocol Https
		$existingContainer = Get-AzStorageContainer -Name $containerName -Context $storageContext -ErrorAction SilentlyContinue
		if($existingContainer)
		{
			Set-AzStorageContainerAcl -Name  $containerName -Permission 'Off' -Context $currentContext 
		}
		
		$storageSku = [Constants]::NewStorageSku
	    Set-AzStorageAccount -Name $storageName  -ResourceGroupName $resourceGroup -SkuName $storageSku
	    
		#Azure_Storage_Audit_AuthN_Requests
	    $currentContext = $storageObject.Context
	    Set-AzStorageServiceLoggingProperty -ServiceType Blob -LoggingOperations All -Context $currentContext -RetentionDays 365 -PassThru
	    Set-AzStorageServiceMetricsProperty -MetricsType Hour -ServiceType Blob -Context $currentContext -MetricsLevel ServiceAndApi -RetentionDays 365 -PassThru
	    
		#Azure_Storage_DP_Encrypt_In_Transit
	    Set-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageName -EnableHttpsTrafficOnly $true
	}

	hidden [bool] CheckStorageMetricAlertConfiguration([PSObject[]] $metricSettings, [string] $resourceGroup, [string] $extendedResourceName)
	{
		$result = $false;
		if($metricSettings -and $metricSettings.Count -ne 0)
		{
			$resourceId = $extendedResourceName;
			$resourceIdMessageString = "";
			if(-not [string]::IsNullOrWhiteSpace($extendedResourceName))
			{
				$resourceIdMessageString = "for nested resource [$extendedResourceName]";
			}

			$resourceAlerts = (Get-AzAlertRule -ResourceGroup $resourceGroup -Name "*" -WarningAction SilentlyContinue) | 
								Where-Object { $_.Condition -and $_.Condition.DataSource } |
								Where-Object { $_.Condition.DataSource.ResourceUri -eq $resourceId }; 
			 		
			$nonConfiguredMetrices = @();
			$misconfiguredMetrices = @();

			$metricSettings	| 
			ForEach-Object {
				$currentMetric = $_;
				$matchedMetrices = @();
				$matchedMetrices += $resourceAlerts | 
									Where-Object { $_.Condition.DataSource.MetricName -eq $currentMetric.Condition.DataSource.MetricName }

				if($matchedMetrices.Count -eq 0)
				{
					$nonConfiguredMetrices += $currentMetric;
				}
				else
				{
					$misConfigured = @();
					$misConfigured += $matchedMetrices | Where-Object { -not [Helpers]::CompareObject($currentMetric, $_) };

					if($misConfigured.Count -eq $matchedMetrices.Count)
					{
						$misconfiguredMetrices += $misConfigured;
					}
				}
			}

			if($nonConfiguredMetrices.Count -eq 0 -and $misconfiguredMetrices.Count -eq 0)
			{
				$result = $true; 
			}
		}
		else
		{
			throw [System.ArgumentException] ("The argument 'metricSettings' is null or empty");
		}
		return $result;
	}
	#endregion

	#region: Internal functions for Get-CA

	#get recent job
	hidden [PSObject] GetLastJob($runbookName)
	{
		$lastJob = Get-AzAutomationJob -ResourceGroupName $this.AutomationAccount.ResourceGroup `
			-AutomationAccountName $this.AutomationAccount.Name `
			-RunbookName $runbookName | 
			Sort-Object LastModifiedTime -Descending | 
			Select-Object -First 1
		
		return $lastJob
	}

	#Check if active schedules
	hidden [PSObject] GetActiveSchedules($runbookName)
	{
		$runbookSchedulesList = Get-AzAutomationScheduledRunbook -ResourceGroupName $this.AutomationAccount.ResourceGroup `
			-AutomationAccountName $this.AutomationAccount.Name `
			-RunbookName $runbookName -ErrorAction Stop

		if($runbookSchedulesList)
		{
			$schedules = Get-AzAutomationSchedule -ResourceGroupName $this.AutomationAccount.ResourceGroup `
				-AutomationAccountName $this.AutomationAccount.Name -Name $this.ScheduleName  | Where-Object{ $_.Name -eq $this.ScheduleName}

			$activeSchedule = $schedules | Where-Object{$_.IsEnabled -and `
				$_.Frequency -ne [Microsoft.Azure.Commands.Automation.Model.ScheduleFrequency]::Onetime -and `
				$_.ExpiryTime.UtcDateTime -gt $(get-date).ToUniversalTime()}

			return $activeSchedule
		}
		else
		{
			return $null
		}
	}

	#get Log Analytics WorkspaceId
	hidden [PSObject] GetLogAnalyticsWorkspaceId()
	{
		#$logAnalyticsWorkspaceId = Get-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
		#	-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "LAWorkspaceId" -ErrorAction SilentlyContinue
		$logAnalyticsWorkspaceId = Get-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
			-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "OMSWorkspaceId" -ErrorAction SilentlyContinue
		if($logAnalyticsWorkspaceId -and ($null -ne $logAnalyticsWorkspaceId.Value))
		{
			return $logAnalyticsWorkspaceId | Select-Object Description, Name, Value
		}
		else
		{
			return $null
		}
	}

	#get Alt Log Analytics WorkspaceId
	hidden [PSObject] GetAltLogAnalyticsWorkspaceId()
	{
		#$altLogAnalyticsWorkspaceId = Get-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
		#	-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "AltLAWorkspaceId" -ErrorAction SilentlyContinue
		$altLogAnalyticsWorkspaceId = Get-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
			-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "AltOMSWorkspaceId" -ErrorAction SilentlyContinue
		if($altLogAnalyticsWorkspaceId -and ($null -ne $altLogAnalyticsWorkspaceId.Value))
		{
			return $altLogAnalyticsWorkspaceId | Select-Object Description, Name, Value
		}
		else
		{
			return $null
		}
	}

	#get Webhook URL
	hidden [PSObject] GetWebhookURL()
	{
		$webhookUrl = Get-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
			-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "WebhookUrl" -ErrorAction SilentlyContinue
		if($webhookUrl -and ($null -ne $webhookUrl.Value))
		{
			return $webhookUrl | Select-Object Description, Name, Value
		}
		else
		{
			return $null
		}
	}

	#Check if Log Analytics Workspace SharedKey is present
	hidden [boolean] IsLAWorkspaceKeyVariableAvailable()
	{
		#$lawSharedKey = Get-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
		#	-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "LAWSharedKey" -ErrorAction SilentlyContinue
		$lawSharedKey = Get-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
			-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "OMSSharedKey" -ErrorAction SilentlyContinue
		if($lawSharedKey)
		{
			return $true
		}
		else
		{
			return $false
		}
	}

	#Check if Alt Log Analytics Workspace SharedKey is present
	hidden [boolean] IsAltLAWorkspaceKeyVariableAvailable()
	{
		#$altLAWSharedKey = Get-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
		#	-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "AltLAWSharedKey" -ErrorAction SilentlyContinue
		$altLAWSharedKey = Get-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
			-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "AltOMSSharedKey" -ErrorAction SilentlyContinue
		if($altLAWSharedKey)
		{
			return $true
		}
		else
		{
			return $false
		}
	}

	#get reports storage value from variable
	hidden [PSObject] GetReportsStorageAccountNameVariable()
	{
		$storageVariable = Get-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
			-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "ReportsStorageAccountName" -ErrorAction SilentlyContinue
		if($storageVariable -and ($null -ne $storageVariable.Value))
		{
			return $storageVariable|Select-Object Description, Name, Value
		}
		else
		{
			return $null
		}
	}

	#get App RGs
	hidden [PSObject] GetAppRGs()
	{
		$appRGs = Get-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
			-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "AppResourceGroupNames" -ErrorAction SilentlyContinue

		if($appRGs -and ($null -ne $appRGs.Value))
		{
			return $appRGs|Select-Object Description, Name, Value
		}
		else
		{
			return $null
		}
	}

	#get connection
	hidden [PSObject] GetRunAsConnection()
	{
		$connection = Get-AzAutomationConnection -AutomationAccountName $this.AutomationAccount.Name `
			-Name $this.ConnectionAssetName -ResourceGroupName `
			$this.AutomationAccount.ResourceGroup -ErrorAction SilentlyContinue

		if((Get-Member -InputObject $connection -Name FieldDefinitionValues -MemberType Properties) -and $connection.FieldDefinitionValues.ContainsKey("ApplicationId"))
		{
			 $connection = $connection|Select-Object Name, Description, ConnectionTypeName, FieldDefinitionValues
			 return $connection
		}
		else
		{
			return $null
		}
	}
	#endregion

	#region: Common internal functions
	hidden [PSObject] CheckContinuousAssuranceStorage()
	{	
		#Check from name
		$existingStorage = Get-AzResource -ResourceGroupName $this.AutomationAccount.CoreResourceGroup -Name "*azsk*" -ResourceType "Microsoft.Storage/storageAccounts"
		if(($existingStorage|Measure-Object).Count -gt 1)
		{
			throw ([SuppressedException]::new(("Multiple storage accounts found in resource group: [$($this.AutomationAccount.CoreResourceGroup)]. This is not expected. Please contact support team."), [SuppressedExceptionType]::InvalidOperation))
		}
		return $existingStorage
	}

	hidden [bool] CheckSPSubscriptionAccess($applicationId)
	{
		#fetch SP permissions
		$spPermissions = Get-AzRoleAssignment -serviceprincipalname $applicationId
		$currentContext = Get-AzContext
		$haveSubscriptionAccess = $false
		#Check subscription access
		if(($spPermissions|measure-object).count -gt 0)
		{
			$haveSubscriptionAccess = ($spPermissions | Where-Object {$_.scope -eq "/subscriptions/$($currentContext.Subscription.Id)" -and $_.RoleDefinitionName -eq "Reader"} | Measure-Object).count -gt 0
			if(($spPermissions | Where-Object {$_.scope -eq "/subscriptions/$($currentContext.Subscription.Id)" -and $_.RoleDefinitionName -eq "Contributor"} | Measure-Object).count -gt 0)
			{
				$this.PublishCustomMessage("WARNING: Service principal (Name: $($spPermissions[0].DisplayName)) configured as the CA RunAs Account has 'Contributor' access. This is not recommended.`r`nCA only requires 'Reader' permission at subscription scope for the RunAs account/SPN.", [MessageType]::Warning);
				$haveSubscriptionAccess = $true;
			}
			if(($spPermissions | Where-Object {$_.scope -eq "/subscriptions/$($currentContext.Subscription.Id)" -and $_.RoleDefinitionName -eq "Owner"} | Measure-Object).count -gt 0)
			{
				$this.PublishCustomMessage("WARNING: Service principal (Name: $($spPermissions[0].DisplayName)) configured as the CA RunAs Account has 'Owner' access. This is not recommended.`r`nCA only requires 'Reader' permission at subscription scope for the RunAs account/SPN.", [MessageType]::Warning);
				$haveSubscriptionAccess = $true;
			}
			return $haveSubscriptionAccess	
		}
		else
		{
			return $false
		}
	}

	hidden [bool] CheckServicePrincipalRGAccess($applicationId)
	{
		return $this.CheckServicePrincipalRGAccess($applicationId, $this.AutomationAccount.CoreResourceGroup, "Contributor");			
	}

	hidden [bool] CheckServicePrincipalRGAccess($applicationId, $rgName, $roleName)
	{
		$spPermissions = Get-AzRoleAssignment -ServicePrincipalName $applicationId
		$haveRGAccess = $false

		#Check subscription access
		if(($spPermissions | Measure-Object).count -gt 0)
		{
			$haveRGAccess = ($spPermissions | Where-Object {$_.scope -eq (Get-AzResourceGroup -Name $rgName).ResourceId -and $_.RoleDefinitionName -eq $roleName } | measure-object).count -gt 0
		}
		return $haveRGAccess
	}

	hidden [void] SetServicePrincipalRGAccess($applicationId)
	{
		$this.SetServicePrincipalRGAccess($applicationId, $this.AutomationAccount.CoreResourceGroup, "Contributor");		
	}

	hidden [void] SetServicePrincipalRGAccess($applicationId, $rgName, $roleName)
	{
		$spnContributorRole = $null
		$this.PublishCustomMessage("Adding SPN to [$roleName] role at [$rgName] resource group scope...")
		$retryCount = 0;

		while($null -eq $spnContributorRole -and $retryCount -le 6)
		{
			#Assign RBAC to SPN - contributor at RG
			$resourceGroup = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
			New-AzRoleAssignment -Scope $resourceGroup.ResourceId -RoleDefinitionName $roleName -ServicePrincipalName $applicationId -ErrorAction SilentlyContinue | Out-Null
			Start-Sleep -Seconds 10

			$spnContributorRole = Get-AzRoleAssignment -ServicePrincipalName $applicationId `
				-Scope $resourceGroup.ResourceId `
				-RoleDefinitionName $roleName `
				-ErrorAction SilentlyContinue

			$retryCount++;
		}
		if($null -eq $spnContributorRole -and $retryCount -gt 6)
		{
			throw ([SuppressedException]::new(("SPN permission could not be set"), [SuppressedExceptionType]::InvalidOperation))
		}
	}

	hidden [void] SetSPSubscriptionReaderAccess($applicationId)
	{
		$spnReaderRole = $null
		$this.PublishCustomMessage("Adding SPN to [Reader] role at [Subscription] scope...")
		$context = Get-AzContext
		$retryCount = 0;
		While($null -eq $spnReaderRole -and $retryCount -le 6)
		{
			#Assign RBAC to SPN - Reader at subscription level 
			New-AzRoleAssignment -RoleDefinitionName 'Reader' -ServicePrincipalName $applicationId -ErrorAction SilentlyContinue | Out-Null
			Start-Sleep -Seconds 10

			$spnReaderRole = Get-AzRoleAssignment -ServicePrincipalName $applicationId `
				-Scope "/subscriptions/$($context.Subscription.Id)" `
				-RoleDefinitionName 'Reader' -ErrorAction SilentlyContinue

			$retryCount++;
		}
		if($null -eq $spnReaderRole -and $retryCount -gt 6)
		{
			throw ([SuppressedException]::new(("SPN permission could not be set"), [SuppressedExceptionType]::InvalidOperation))
		}
	}

    hidden [void] SetSPNSubscriptionAccessIfNotAssigned($applicationId)
	{
        #check SP permissions
		$haveSubscriptionAccess = $this.CheckSPSubscriptionAccess($applicationId)
		#assign SP permissions
		if(!$haveSubscriptionAccess)
		{
			$this.SetSPSubscriptionReaderAccess($applicationId)
		} 
	}
	
    hidden [void] SetSPNRGAccessIfNotAssigned($applicationId)
	{
        $this.SetSPNRGAccessIfNotAssigned($applicationId, $this.AutomationAccount.CoreResourceGroup, "Contributor");
	}
	
    hidden [void] SetSPNRGAccessIfNotAssigned($applicationId, $rgName, $roleName)
	{
		$haveRGAccess = $this.CheckServicePrincipalRGAccess($applicationId, $rgName, $roleName)
        if(!$haveRGAccess)
		{
			$this.SetServicePrincipalRGAccess($applicationId, $rgName, $roleName)
		}
	}
	
	hidden [void] SetRunbookVersionTag()
	{
		#update version in AzSKRG 
		$azskRGName = $this.AutomationAccount.CoreResourceGroup;
		$version = [ConfigurationManager]::GetAzSKConfigData().AzSKCARunbookVersion;
		[Helpers]::SetResourceGroupTags($azskRGName, @{ $($this.RunbookVersionTagName) = $version}, $false)
	}

	hidden [void] RemoveRunbookVersionTag()
	{
		#remove version in AzSKRG 
		$azskRGName = $this.AutomationAccount.CoreResourceGroup;
		$version = [ConfigurationManager]::GetAzSKConfigData().AzSKCARunbookVersion;
		[Helpers]::SetResourceGroupTags($azskRGName, @{$($this.RunbookVersionTagName) = $version}, $true)
	}
	#endregion

	#region: Remove configured setting from CA
	hidden [void] RemoveLAWSettings()
	{
		$logAnalyticsWorkspaceId = $this.GetLogAnalyticsWorkspaceId()
		try
		{
			if($null -ne $logAnalyticsWorkspaceId)
			{			
				$this.PublishCustomMessage("Removing Log Analytics workspace settings... ");
				Remove-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "OMSWorkspaceId" -ErrorAction SilentlyContinue
				Remove-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "OMSSharedKey" -ErrorAction SilentlyContinue
				Remove-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "LAWorkspaceId" -ErrorAction SilentlyContinue
				Remove-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "LAWSharedKey" -ErrorAction SilentlyContinue		
				$this.PublishCustomMessage("Completed")
			}
			else
			{
				$this.PublishCustomMessage("Unable to find Log Analytics workspace Id for current Automation Account ")
			}
		}
		catch
		{
			$this.PublishCustomMessage("Unable to remove Log Analytics workspace settings.")
		}
	}
	hidden [void] RemoveAltLAWSettings()
	{
		$altLogAnalyticsWorkspaceId = $this.GetAltLogAnalyticsWorkspaceId();
		try
		{
			if($null -ne $altLogAnalyticsWorkspaceId)
			{
				$this.PublishCustomMessage("Removing Alt Log analytics workspace settings... ");
				Remove-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "AltOMSWorkspaceId" -ErrorAction SilentlyContinue
				Remove-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "AltOMSSharedKey" -ErrorAction SilentlyContinue
				Remove-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "AltLAWorkspaceId" -ErrorAction SilentlyContinue
				Remove-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "AltLAWSharedKey" -ErrorAction SilentlyContinue
				$this.PublishCustomMessage("Completed")
			}
			else
			{
				$this.PublishCustomMessage("Unable to find Alt Log Analytics workspace Id for current Automation Account ")

			}
		}
		catch
		{
			$this.PublishCustomMessage("Unable to remove Alt Log Analytics workspace settings.")
		}
	}

	hidden [void] RemoveWebhookSettings()
	{
		$webhookUrl=$this.GetWebhookURL()
		try
		{
			if($null -ne $webhookUrl)
			{
				$this.PublishCustomMessage("Removing Webhook settings... ")
				Remove-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "WebhookUrl" -ErrorAction SilentlyContinue			
				Remove-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "WebhookAuthZHeaderName" -ErrorAction SilentlyContinue		
				Remove-AzAutomationVariable -AutomationAccountName $this.AutomationAccount.Name `
					-ResourceGroupName $this.AutomationAccount.ResourceGroup -Name "WebhookAuthZHeaderValue" -ErrorAction SilentlyContinue		
				$this.PublishCustomMessage("Completed")
			}
			else
			{
				$this.PublishCustomMessage("Unable to find webhook url for current Automation Account ")
			}
		}
		catch
		{
			$this.PublishCustomMessage("Unable to remove Webhook settings.")
		}
	}

	#Validate if Org policy local debuging is on
	[void] ValidateIfLocalPolicyIsEnabled()
	{
		if(Test-Path $([ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl))
		{
			throw ([SuppressedException]::new(("Currently command is running with local policy folder ($([ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl)). Please run command with online policy store url."), [SuppressedExceptionType]::Generic))
		}	  
	}
	#endregion
}

class CAScanModel
{
	CAScanModel()
	{
		$this.Frequency = "Day";
		$this.Interval = "1";
		$this.StartTime = [System.DateTime]::Now.AddMinutes(60);
	}

	CAScanModel($subscriptionId, $loggingOption)
	{
		$this.SubscriptionId = $subscriptionId;
		$this.LoggingOption = $loggingOption;
	}
	[string] $SubscriptionId;
	[string] $Frequency;
	[string] $Interval;
	[DateTime] $StartTime;
	[CAReportsLocation] $LoggingOption
}