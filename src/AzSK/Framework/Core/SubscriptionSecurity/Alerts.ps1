using namespace System.Management.Automation
Set-StrictMode -Version Latest 

# Class to implement Subscription alert controls 
class Alerts: CommandBase
{    
	hidden [PSObject[]] $Policy = $null;
	
	hidden [PSObject[]] $ApplicableAlerts = $null;
	
	hidden [string] $TargetResourceGroup;
	hidden [string] $ResourceGroup ;
	hidden [string] $ResourceGroupLocation;
	hidden [PSObject] $AlertPolicyObj = $null
	hidden [string] $V1AlertRGName;
	hidden [string] $RunbookName=[Constants]::AlertRunbookName
	hidden [string] $Alert_ResourceCreation_Runbook=[Constants]::Alert_ResourceCreation_Runbook
	
	hidden [string] $AutomationWebhookName=[Constants]::AutomationWebhookName
	hidden [string] $AutomationAccountName=[Constants]::AutomationAccountName
	hidden [int] $WebhookExpiryInDays = [Constants]::AlertWebhookUriExpiryInDays
	Alerts([string] $subscriptionId, [InvocationInfo] $invocationContext, [string] $tags): 
        Base($subscriptionId, $invocationContext)
    {
		$this.V1AlertRGName = [OldConstants]::V1AlertRGName
		$this.ResourceGroup = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
		$this.AlertPolicyObj =  $this.LoadServerConfigFile("Subscription.InsARMAlerts.json");
		$this.FilterTags = $this.ConvertToStringArray($tags);
		$this.ResourceGroupLocation = [ConfigurationManager]::GetAzSKConfigData().AzSKLocation;
		$this.Policy = $this.AlertPolicyObj.AlertList 
	}

	hidden [PSObject[]] GetApplicableAlerts([string[]] $alertNames)
	{
		if($null -eq $this.ApplicableAlerts)
		{
			$this.ApplicableAlerts = @();

			if($alertNames -and $alertNames.Count -ne 0)
			{
				$this.ApplicableAlerts += $this.Policy | Where-Object { $alertNames -Contains $_.Name };
			}
			elseif(($this.FilterTags | Measure-Object).Count -ne 0)
			{
				$this.Policy |
					ForEach-Object {
						$currentResourceTypeItem = $_;
						$applicableAlert = @{ Name=$currentResourceTypeItem.Name;Description = $currentResourceTypeItem.Description; OperationNameList =@(); Enabled = $currentResourceTypeItem.Enabled }
						$currentResourceTypeItem.AlertOperationList | ForEach-Object{
						$currentItem = $_							
						if(($currentItem | Where-Object { $this.FilterTags -Contains $_.Tags  -and $_.Enabled -eq $true} | Measure-Object).Count -ne 0)
						{
							$applicableAlert.OperationNameList  += $currentItem.OperationName;
						}

					}
						if(($applicableAlert.OperationNameList | Measure-Object).Count -gt 0 )
						{
							$this.ApplicableAlerts += $applicableAlert
						}
					}
			}
		}
			
		return $this.ApplicableAlerts;
	}
	hidden [PSObject[]] GetApplicableAlerts()
	{
		return $this.GetApplicableAlerts(@());
	}

	[MessageData[]] RemoveAlerts([string] $alertNames, [bool] $DeleteActionGroup)
	{
		return $this.RemoveAlerts($this.ResourceGroup, $alertNames, $DeleteActionGroup)
	}

	[MessageData[]] RemoveAlerts([string] $rgName,  [string] $alertNames, [bool] $DeleteActionGroup)
    {
		[MessageData[]] $messages = @();

		# Check for existence of resource group

		$existingRG = Get-AzureRmResourceGroup -Name $rgName -ErrorAction SilentlyContinue
		if($existingRG)
		{
			$startMessage = [MessageData]::new("Found alerts resource group: $rgName");
			$messages += $startMessage;
			$this.PublishCustomMessage($startMessage);

			$alertNameArray = @();		
			if(-not [string]::IsNullOrWhiteSpace($alertNames))
			{
				$alertNameArray += $this.ConvertToStringArray($alertNames);
				if($alertNameArray.Count -eq 0)
				{
					throw ([SuppressedException]::new(("The argument 'alertNames' is null or empty"), [SuppressedExceptionType]::NullArgument))
				}
			}		
			$policyList=@();
		    if(($this.FilterTags|Measure-Object).Count -gt 0)
            {
			 ForEach($Tag in $this.FilterTags)
			 {
		       $policyList+= $this.Policy | Where-Object { $Tag -In $_.Tags }          
			 }	
			  $this.Policy=$policyList| Select-Object * -Unique	
			  $this.Policy |ForEach-Object { $alertNameArray+=$_.Name }
            }
            else
            {
              $policyList+= $this.Policy
              $this.Policy=$policyList| Select-Object * -Unique
            }

			# User wants to remove only specific alerts
			if(($this.Policy | Measure-Object).Count -ne 0)
			{
				if($this.GetApplicableAlerts($alertNameArray) -ne 0)
				{
					$startMessage = [MessageData]::new("Removing alerts. Tags:[$([string]::Join(",", $this.FilterTags))]. Total alerts: $($this.GetApplicableAlerts($alertNameArray).Count)");
					$messages += $startMessage;
					$this.PublishCustomMessage($startMessage);
					$this.PublishCustomMessage("Note: Removing alerts can take few minutes depending on number of alerts to be processed...", [MessageType]::Warning);				

					$disabledAlerts = $this.GetApplicableAlerts($alertNameArray) | Where-Object { -not $_.Enabled };
					if(($disabledAlerts | Measure-Object).Count -ne 0)
					{
						$disabledMessage = "Found alerts which are disabled and will not be removed. This is intentional. Total disabled alerts: $($disabledAlerts.Count)";
						$messages += [MessageData]::new($disabledMessage, $disabledAlerts);
						#$this.PublishCustomMessage($disabledMessage, [MessageType]::Warning);
					}

					$enabledAlerts = @();
					$enabledAlerts += $this.GetApplicableAlerts($alertNameArray) | Where-Object { $_.Enabled };
					if($enabledAlerts.Count -ne 0)
					{
						$messages += [MessageData]::new([Constants]::SingleDashLine + "`r`nRemoving following alerts from the subscription. Total alerts: $($enabledAlerts.Count)", $enabledAlerts);                                            

						$errorCount = 0;
						$currentCount = 0;
						$enabledAlerts | ForEach-Object {
							$alertName = $_.Name;
							$currentCount += 1;
							# Remove alert
							try
							{
								Remove-AzureRmResource -ResourceType "Microsoft.Insights/activityLogAlerts" -ResourceGroupName  $rgName -Name $alertName -Force
								#Remove-AzureRmAlertRule -ResourceGroup $this.ResourceGroup -Name $alertName -WarningAction SilentlyContinue      
							}
							catch
							{
								$messages += [MessageData]::new("Error while removing alert [$alertName] from the subscription", $_, [MessageType]::Error);
								$errorCount += 1;
							}

							$this.CommandProgress($enabledAlerts.Count, $currentCount, 20);
						};

						[MessageData[]] $resultMessages = @();
						if($errorCount -eq 0)
						{
							#setting the tag at AzSKRG
							[Helpers]::SetResourceGroupTags($rgName,@{[Constants]::AzSKAlertsVersionTagName=$this.AlertPolicyObj.Version}, $true)

							$resultMessages += [MessageData]::new("All alerts have been removed from the subscription successfully`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
							if($DeleteActionGroup)
							{
								Remove-AzureRmResource -ResourceType "Microsoft.Insights/actiongroups" -ResourceGroupName $rgName -Name $([Constants]::AlertActionGroupName) -Force
								Remove-AzureRmResource -ResourceType "Microsoft.Insights/actiongroups" -ResourceGroupName $rgName -Name $([Constants]::CriticalAlertActionGroupName) -ErrorAction SilentlyContinue -Force 
								$resultMessages += [MessageData]::new("Action Group have been removed from the subscription successfully`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
							}
								
						}
						elseif($errorCount -eq $enabledAlerts.Count)
						{
							$resultMessages += [MessageData]::new("No alerts have been removed from the subscription due to error occurred. Please add the alerts manually.`r`n" + [Constants]::SingleDashLine, [MessageType]::Error);
						}
						else
						{
							$resultMessages += [MessageData]::new("$errorCount/$($enabledAlerts.Count) alert(s) have not been removed from the subscription. Please remove the alerts manually.", [MessageType]::Error);
							$resultMessages += [MessageData]::new("$($enabledAlerts.Count - $errorCount)/$($enabledAlerts.Count) alert(s) have been removed from the subscription successfully`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
						}
						$messages += $resultMessages;
						$this.PublishCustomMessage($resultMessages);

					}
				}
				else
				{
					$this.PublishCustomMessage("No alerts have been found that matches the specified tags. Tags:[$([string]::Join(",", $this.FilterTags))].", [MessageType]::Warning);
				}
			}
			else
			{
				$this.PublishCustomMessage("No alerts found in the alert policy file", [MessageType]::Warning);
			}
		}
		else
		{
			$this.PublishCustomMessage("No configured alerts found in the subscription. Resource group not found: $rgName", [MessageType]::Warning);
		}
		return $messages;
    }	

	[MessageData[]] SetAlerts([string] $targetResourceGroup, [string] $securityContactEmails,[string] $SecurityPhoneNumbers, [string] $alertResourceGroupLocation, [PSObject] $emailReceivers, [PSObject] $smsReceivers, [string] $curWebhookUri)
    {
		$actionGroupResourceId = $null
		$criticalAlertActionGroupResourceId=$null
		$existingWebhookUri=$null
		[MessageData[]] $messages = @();
		$webhookUri = $curWebhookUri;
		#There is a possibility that if the Alerts are reconfigured, the existing webhook uri will get overwritten with the new setup. Need to take the current backup
		if([string]::IsNullOrWhiteSpace($webhookUri))
		{
			$webhookUri = $this.ComputeAlertRunbookWebhookUri("Alert");
		}		

		if(-not [string]::IsNullOrWhiteSpace($SecurityPhoneNumbers) -or $null -ne $smsReceivers)
		{
			if(-not $this.FilterTags.Contains("SMS"))
			{
				$this.FilterTags += "SMS"
			}
		}

		if($this.Force -or -not ($this.IsLatestVersionConfiguredOnSub($this.AlertPolicyObj.Version,[Constants]::AzSKAlertsVersionTagName,"Alerts")))
		{
			$allEmails = @();
			# Parameter validation
			if([string]::IsNullOrWhiteSpace($securityContactEmails))
			{
				#If security contact emails is blank check if old V1 alerts are configured and get email from alert resource
				#Check if V2 alert action group is present and assign existing action group resource Id
				$actionGroupResourceId = "";
				$curActionGroup = $this.GetAlertActionGroup($this.ResourceGroup, [Constants]::AlertActionGroupName)
				if($curActionGroup)
				{
					$actionGroupResourceId = $curActionGroup.ResourceId
				}

				$criticalAlertActionGroupResourceId = "";
				$curCriticalActionGroup = $this.GetAlertActionGroup($this.ResourceGroup, [Constants]::CriticalAlertActionGroupName)
				if($curCriticalActionGroup)
				{
					$criticalAlertActionGroupResourceId = $curCriticalActionGroup.ResourceId
				}

				if(($curActionGroup | Measure-Object).Count -eq 0 -and $null -eq $emailReceivers)
				{
					$this.PublishCustomMessage("'SecurityContactEmails' is required to configure alerts. Please set up alerts with cmdlet Set-AzSKAlerts. Run 'Get-Help Set-AzSKAlerts -full' for more help.", [MessageType]::Error);
					return $null;
				}			
			}
			else
			{
				$allEmails += $this.ConvertToStringArray($securityContactEmails);
				#Validate emails
				if((($allEmails | Measure-Object).Count -gt 0))
				{
					$invalidEmailList = [Helpers]::ValidateEmailList($allEmails)
					if(($invalidEmailList| Measure-Object).Count -gt 0)
					{
						 $this.PublishCustomMessage(("Please enter valid security contact email id(s): "+ [string]::Join(",", $invalidEmailList)) , [MessageType]::Error);
						 return $null
					}			
				}
			}


			if(-not [string]::IsNullOrWhiteSpace($alertResourceGroupLocation))
			{
				$this.ResourceGroupLocation = $alertResourceGroupLocation;
			}

		
			if(($this.Policy | Measure-Object).Count -ne 0)
			{
				$alertList = $this.GetApplicableAlerts();
				if($alertList -ne 0)
				{
					$criticalAlerts = $alertList 
					$startMessage = [MessageData]::new("Processing AzSK alerts. Total alert groups: $($criticalAlerts.Count)");
					$messages += $startMessage;
					$this.PublishCustomMessage($startMessage);
					$this.PublishCustomMessage("Note: Configuring alerts can take about 4-5 min...", [MessageType]::Warning);				

					$disabledAlerts = $criticalAlerts | Where-Object { -not $_.Enabled };
					if(($disabledAlerts | Measure-Object).Count -ne 0)
					{
						$disabledMessage = "Found alerts which are disabled. This is intentional. Total disabled alerts: $($disabledAlerts.Count)";
						$messages += [MessageData]::new($disabledMessage, $disabledAlerts);					
					}

					$enabledAlerts = @();
					$enabledAlerts += $criticalAlerts | Where-Object { $_.Enabled };
					if($enabledAlerts.Count -ne 0)
					{
						$messages += [MessageData]::new([Constants]::SingleDashLine + "`r`nAdding following alerts to the subscription. Total alerts: $($enabledAlerts.Count)", $enabledAlerts);                                            

						# Check if Resource Group exists
						$existingRG = Get-AzureRmResourceGroup -Name $this.ResourceGroup -ErrorAction SilentlyContinue
						if(-not $existingRG)
						{
							[Helpers]::NewAzSKResourceGroup($this.ResourceGroup,$this.ResourceGroupLocation,$this.GetCurrentModuleVersion())						
						}
						$messages += [MessageData]::new("All the alerts registered by this script will be placed in a resource group named: $($this.ResourceGroup)");
						$isTargetResourceGroup = -not [string]::IsNullOrWhiteSpace($targetResourceGroup);
						#if email address are provided, Create/edit the action group. This will not support append functionality. 
						if(($allEmails | Measure-Object).Count -gt 0 -or $null -ne $emailReceivers)
						{
						    $actionGroupResourceId = $this.SetupAlertActionGroup($allEmails,$SecurityPhoneNumbers,$emailReceivers)						
							if([string]::IsNullOrWhiteSpace($actionGroupResourceId))
							{
								$this.PublishCustomMessage("Not able to create alert action group. Validate detailed log for more details.", [MessageType]::Error);
								return $messages
							}
							if(-not [string]::IsNullOrWhiteSpace($SecurityPhoneNumbers) -or $null -ne $smsReceivers)
			                {
						    	$criticalAlertActionGroupResourceId = $this.SetupAlertActionGroup($SecurityPhoneNumbers, $smsReceivers)
							    if([string]::IsNullOrWhiteSpace($criticalAlertActionGroupResourceId))
							    {
							     	$this.PublishCustomMessage("Some SMS-based alerts could not be created. This may be because the phone number specified was not in the expected format. E.g., +1-425-882-8080.If you would like to receive SMS alerts, please rerun this command with the correct phone number format.", [MessageType]::Warning);
							    }
							}
						}
						try
						{
							$criticalAlertList = @()
							$alertArm =  $this.LoadServerConfigFile("Subscription.AlertARM.json");
							$alert = ($alertArm.resources | Select-Object -First 1).PSObject.Copy()
							$enabledAlerts | ForEach-Object {
								$alertObj =  [Helpers]::DeepCopy($alert)
								$alertObj.name = $_.Name
								$alertObj.properties.description = $_.Description								
								$alertObj.properties.condition.allOf[2].anyOf =@()
								$_.OperationNameList | ForEach-Object {
									$alertObj.properties.condition.allOf[2].anyOf += @{ field = "operationName"; equals =$_ }
								}
								if($isTargetResourceGroup)
								{
									$alertObj.properties.condition.allOf += @{field= "resourceGroup";equals= $targetResourceGroup}	
								}
								
								if($_.Name -eq "AzSK_Critical_Alert")
								{
								    if(-not [string]::IsNullOrWhiteSpace($criticalAlertActionGroupResourceId))
						         	{
								      $alertObj.properties.actions.actionGroups[0].actionGroupId = $criticalAlertActionGroupResourceId
									  $criticalAlertList += $alertObj
									}			
								}
								else
								{
								  $alertObj.properties.actions.actionGroups[0].actionGroupId = $actionGroupResourceId
								  $criticalAlertList += $alertObj
								}
								
								#$criticalAlertList += $alertObj
							}
							$alertArm.resources = $criticalAlertList 
							$armTemplatePath = [Constants]::AzSKTempFolderPath + "Subscription.AlertARM.json";
							$alertArm | ConvertTo-Json -Depth 100  | New-Item $armTemplatePath -Force | Out-Null
							$alertDeployment = New-AzureRmResourceGroupDeployment -Name "AzSKAlertsDeployment" -ResourceGroupName $this.ResourceGroup -TemplateFile $armTemplatePath  -ErrorAction Stop							
							Remove-Item $armTemplatePath  -ErrorAction SilentlyContinue
						}
						catch
						{
							$messages += [MessageData]::new("Error while deploying alerts to the subscription", $_, [MessageType]::Error);							
						}			

						[MessageData[]] $resultMessages = @();
						#Logic to validate if Alerts are configured.
						$configuredAlerts = @();		
						$configuredAlerts = Get-AzureRmResource -ResourceType "Microsoft.Insights/activityLogAlerts" -ResourceGroupName  $this.ResourceGroup 
						$actualConfiguredAlertsCount = ($configuredAlerts | Measure-Object).Count
						$notConfiguredAlertsCount = $enabledAlerts.Count - $actualConfiguredAlertsCount
						if( $actualConfiguredAlertsCount -ge  $enabledAlerts.Count)
						{
							#setting the tag at AzSKRG
							$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
							[Helpers]::SetResourceGroupTags($azskRGName,@{[Constants]::AzSKAlertsVersionTagName=$this.AlertPolicyObj.Version}, $false)

							#After successfully setting V2 alerts, clean V1 alert rules
											
							$resultMessages += [MessageData]::new("All AzSK alerts have been configured successfully.`r`n", [MessageType]::Update);
							#$this.UpdateActionGroupWebhookUri($existingWebhookUri);
						
						}					
						else
						{
							$resultMessages += [MessageData]::new("$notConfiguredAlertsCount/$($enabledAlerts.Count) alert group(s) have not been added to the subscription. Please rerun the command after resolving any errors from the log.", [MessageType]::Error);
							$resultMessages += [MessageData]::new("$actualConfiguredAlertsCount/$($enabledAlerts.Count) alert group(s) have been added to the subscription successfully`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
						}
					
						$messages += $resultMessages;
						$this.PublishCustomMessage($resultMessages);
					}
				}
				else
				{
					$this.PublishCustomMessage("No alerts have been found that matches the specified tags. Tags:[$([string]::Join(",", $this.FilterTags))].", [MessageType]::Warning);
				}
			}
			else
			{
				$this.PublishCustomMessage("No alerts found in the alert policy file", [MessageType]::Warning);
			}
		}
        $this.UpdateActionGroupWebhookUri($webhookUri,"Alert");
		return $messages;
    }

    [MessageData[]] SetAlerts([string] $actionGroupResourceId)
    {
		$existingWebhookUri=$null
		[MessageData[]] $messages = @();

		$webhookUri = $this.ComputeAlertRunbookWebhookUri("ResourceCreation");
		

		if(($this.Policy | Measure-Object).Count -ne 0)
		{
				$alertList = $this.GetApplicableAlerts();
				if($alertList -ne 0)
				{
					$criticalAlerts = $alertList 
					$startMessage = [MessageData]::new("Processing AzSK alerts. Total alert groups: $($criticalAlerts.Count)");
					$messages += $startMessage;
					$this.PublishCustomMessage($startMessage);
					$this.PublishCustomMessage("Note: Configuring alerts can take about 4-5 min...", [MessageType]::Warning);				

					$disabledAlerts = $criticalAlerts | Where-Object { -not $_.Enabled };
					if(($disabledAlerts | Measure-Object).Count -ne 0)
					{
						$disabledMessage = "Found alerts which are disabled. This is intentional. Total disabled alerts: $($disabledAlerts.Count)";
						$messages += [MessageData]::new($disabledMessage, $disabledAlerts);					
					}

					$enabledAlerts = @();
					$enabledAlerts += $criticalAlerts | Where-Object { $_.Enabled };
					if($enabledAlerts.Count -ne 0)
					{
						$messages += [MessageData]::new([Constants]::SingleDashLine + "`r`nAdding following alerts to the subscription. Total alerts: $($enabledAlerts.Count)", $enabledAlerts);                                            

						# Check if Resource Group exists
						$existingRG = Get-AzureRmResourceGroup -Name $this.ResourceGroup -ErrorAction SilentlyContinue
						if(-not $existingRG)
						{
							[Helpers]::NewAzSKResourceGroup($this.ResourceGroup,$this.ResourceGroupLocation,$this.GetCurrentModuleVersion())						
						}
						$messages += [MessageData]::new("All the alerts registered by this script will be placed in a resource group named: $($this.ResourceGroup)");


						try
						{
							$criticalAlertList = @()
							$alertArm =  $this.LoadServerConfigFile("Subscription.AlertARM.json");
							$alert = ($alertArm.resources | Select-Object -First 1).PSObject.Copy()
							$enabledAlerts | ForEach-Object {
								$alertObj =  [Helpers]::DeepCopy($alert)
								$alertObj.name = $_.Name
								$alertObj.properties.description = $_.Description								
								$alertObj.properties.condition.allOf[2].anyOf =@()
								$_.OperationNameList | ForEach-Object {
									$alertObj.properties.condition.allOf[2].anyOf += @{ field = "operationName"; equals =$_ }
								}
								
								$alertObj.properties.actions.actionGroups[0].actionGroupId = $actionGroupResourceId
								$criticalAlertList += $alertObj
								
								
								#$criticalAlertList += $alertObj
							}
							$alertArm.resources = $criticalAlertList 
							$armTemplatePath = [Constants]::AzSKTempFolderPath + "Subscription.AlertARM.json";
							$alertArm | ConvertTo-Json -Depth 100  | New-Item $armTemplatePath -Force | Out-Null
							$alertDeployment = New-AzureRmResourceGroupDeployment -Name "AzSKAlertsDeployment" -ResourceGroupName $this.ResourceGroup -TemplateFile $armTemplatePath  -ErrorAction Stop							
							Remove-Item $armTemplatePath  -ErrorAction SilentlyContinue
						}
						catch
						{
							$messages += [MessageData]::new("Error while deploying alerts to the subscription", $_, [MessageType]::Error);							
						}			

						[MessageData[]] $resultMessages = @();
						#Logic to validate if Alerts are configured.
						$configuredAlerts = @();		
						$configuredAlerts = Get-AzureRmResource -ResourceType "Microsoft.Insights/activityLogAlerts" -ResourceGroupName  $this.ResourceGroup 
						$actualConfiguredAlertsCount = ($configuredAlerts | Measure-Object).Count
						$notConfiguredAlertsCount = $enabledAlerts.Count - $actualConfiguredAlertsCount
						if( $actualConfiguredAlertsCount -ge  $enabledAlerts.Count)
						{
							#setting the tag at AzSKRG
							$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
							[Helpers]::SetResourceGroupTags($azskRGName,@{[Constants]::AzSKAlertsVersionTagName=$this.AlertPolicyObj.Version}, $false)

							#After successfully setting V2 alerts, clean V1 alert rules
											
							$resultMessages += [MessageData]::new("All AzSK alerts have been configured successfully.`r`n", [MessageType]::Update);
							#$this.UpdateActionGroupWebhookUri($existingWebhookUri);
						
						}					
						else
						{
							$resultMessages += [MessageData]::new("$notConfiguredAlertsCount/$($enabledAlerts.Count) alert group(s) have not been added to the subscription. Please rerun the command after resolving any errors from the log.", [MessageType]::Error);
							$resultMessages += [MessageData]::new("$actualConfiguredAlertsCount/$($enabledAlerts.Count) alert group(s) have been added to the subscription successfully`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
						}
					
						$messages += $resultMessages;
						$this.PublishCustomMessage($resultMessages);
					}
				}
				else
				{
					$this.PublishCustomMessage("No alerts have been found that matches the specified tags. Tags:[$([string]::Join(",", $this.FilterTags))].", [MessageType]::Warning);
				}
			}
		else
		{
			$this.PublishCustomMessage("No alerts found in the alert policy file", [MessageType]::Warning);
		}
		
        $this.UpdateActionGroupWebhookUri($webhookUri,"ResourceCreation");	

		return $messages;
    }

	[MessageData[]] SetAlerts()
    {
		[MessageData[]] $messages = @();
	
		return $this.SetAlerts($null,$null,$null,$null,$null,$null,$null);
		
		
	}

	[MessageData[]] SetAlerts([string] $targetResourceGroup, [string] $securityContactEmails, [string] $SecurityPhoneNumbers, [string] $alertResourceGroupLocation)
    {
		return $this.SetAlerts($targetResourceGroup,$securityContactEmails,$SecurityPhoneNumbers,$alertResourceGroupLocation, $null, $null, $null);
	}

	[MessageData[]] SetAlerts([PSObject] $emailReceivers, [PSObject] $smsReceivers, [string] $webhookUri)
	{
		return $this.SetAlerts($null, $null ,$null, $null, $emailReceivers, $smsReceivers, $webhookUri);
	}

	hidden [string] SetupAlertActionGroup([string[]] $securityContactEmails,[string] $SecurityPhoneNumbers, [PSObject] $CurEmailReceivers)
	{
		$actionGroupResourceId = $null
		try{
			#Get ARM template for action group
			$actionGroupArm = $this.LoadServerConfigFile("Subscription.AlertActionGroup.json");
			$actionGroupArmResource = $actionGroupArm.resources | Where-Object { $_.Name -eq $([Constants]::AlertActionGroupName) } 
			$emailReceivers = $actionGroupArmResource.properties.emailReceivers | Select-Object -first 1
			if(($securityContactEmails | Measure-Object).Count -gt 0)
			{
				$emailReceiversList = @();
				$Counter = 1;
				$securityContactEmails | ForEach-Object {
					$email = $emailReceivers.PsObject.Copy()
					$email.name = "SecurityContactEmail$Counter"
					$email.emailAddress = $_
					$emailReceiversList += $email  
					$Counter+=1
				}
				$actionGroupArmResource.properties.emailReceivers = $emailReceiversList
			}
			elseif(($CurEmailReceivers | Measure-Object).Count -gt 0)
			{
				$emailReceiversList = @();
				$CurEmailReceivers | ForEach-Object {
					$email = $emailReceivers.PsObject.Copy()
					$email.name = $_.name
					$email.emailAddress = $_.emailAddress
					$emailReceiversList += $email  
				}
				$actionGroupArmResource.properties.emailReceivers = $emailReceiversList;
			}

			$actionGroupArmResource.properties.PSObject.Properties.Remove('smsReceivers')		
			$armTemplatePath =[Constants]::AzSKTempFolderPath + "Subscription.AlertActionGroup.json"
			$actionGroupArm | ConvertTo-Json -Depth 100  | New-Item $armTemplatePath -Force
			$actionGroupResource = New-AzureRmResourceGroupDeployment -Name "AzSKAlertActionGroupDeployment" -ResourceGroupName $this.ResourceGroup -TemplateFile $armTemplatePath  -ErrorAction Stop
			$actionGroupId = $actionGroupResource.Outputs | Where-Object actionGroupId 
			$actionGroupResourceId = $actionGroupId.Values | Select-Object -ExpandProperty Value                      
			Remove-Item $armTemplatePath  -ErrorAction SilentlyContinue
		}
		catch
		{			
			$this.PublishException($_);
		}
		
		return 	$actionGroupResourceId
	}
	hidden [string] SetupAlertActionGroup([string] $SecurityPhoneNumbers, [PSObject] $CurSMSReceivers)
	{
		$actionGroupResourceId = $null
		try{
			#Get ARM template for action group
			$actionGroupArm = $this.LoadServerConfigFile("Subscription.AlertActionGroup.json");
			$actionGroupArmResource = $actionGroupArm.resources | Where-Object { $_.Name -eq $([Constants]::AlertActionGroupName) } 
			$actionGroupArmResourceOutput = $actionGroupArm.outputs.actionGroupId
			$actionGroupArmResource.name="AzSKCriticalAlertActionGroup"
			$actionGroupArmResourceOutput.value = $actionGroupArmResourceOutput.value.Replace($([Constants]::AlertActionGroupName),$([Constants]::CriticalAlertActionGroupName));
			$actionGroupArmResource.properties.PSObject.Properties.Remove('emailReceivers')
			if(-not [string]::IsNullOrWhiteSpace($SecurityPhoneNumbers))
			{
				$smsReceivers = $actionGroupArmResource.properties.smsReceivers | Select-Object -first 1
				$allPhoneNumbers = @();		
				$allPhoneNumbers += $this.ConvertToStringArray($SecurityPhoneNumbers);
				$Counter = 1;
				$smsReceiversList = @();
				    foreach($allPhoneNumber in $allPhoneNumbers ) {
					$phoneNumberDetails = $smsReceivers.PsObject.Copy()
					$phoneNumberDetails.name = "SecurityPhoneNumber$Counter"
					$startIndex=$allPhoneNumber.indexof("-")  
					if($startIndex -ne -1)
					{
					 $countryCode=$allPhoneNumber.substring(0,$startIndex) -replace '[^0-9]', ''
					 $phoneNumberDetails.countrycode= $countryCode
					}
					else
					{
					 return $actionGroupResourceId
					}
					$phoneNumber=$allPhoneNumber.substring($startIndex+1) -replace '[^0-9]', ''
					$phoneNumberDetails.phoneNumber = $phoneNumber
					$smsReceiversList += $phoneNumberDetails				
					$Counter+=1	    
				}
				$actionGroupArmResource.properties.smsReceivers = $smsReceiversList
			}
			elseif($null -ne $CurSMSReceivers)
			{
				$smsReceivers = $actionGroupArmResource.properties.smsReceivers | Select-Object -first 1
				$smsReceiversList = @();
				$CurSMSReceivers | ForEach-Object {
					$smsReceiver = $smsReceivers.PsObject.Copy()
					$smsReceiver.name = $_.name
					$smsReceiver.countrycode = $_.countrycode
					$smsReceiver.phoneNumber = $_.phoneNumber
					$smsReceiversList += $smsReceiver  
				}
				$actionGroupArmResource.properties.smsReceivers = $smsReceiversList;
			}
			else
			{
			  return $actionGroupResourceId
			}
			$armTemplatePath =[Constants]::AzSKTempFolderPath + "Subscription.AlertActionGroup.json"
			$actionGroupArm | ConvertTo-Json -Depth 100  | New-Item $armTemplatePath -Force
			$actionGroupResource = New-AzureRmResourceGroupDeployment -Name "AzSKAlertActionGroupDeployment" -ResourceGroupName $this.ResourceGroup -TemplateFile $armTemplatePath  -ErrorAction Stop
			$actionGroupId = $actionGroupResource.Outputs | Where-Object actionGroupId 
			$actionGroupResourceId = $actionGroupId.Values | Select-Object -ExpandProperty Value                      
			Remove-Item $armTemplatePath  -ErrorAction SilentlyContinue
		}
		catch
		{	
			#Eating up this error while action group is not setup we are showing user friendly message
			#$this.PublishException($_);
		}
		
		return 	$actionGroupResourceId
	}

	hidden [string] SetupAlertActionGroup()
	{
		$actionGroupResourceId = $null
		try{
			#Get ARM template for action group
			$actionGroupArm = $this.LoadServerConfigFile("Subscription.AlertActionGroup.json");
			$actionGroupArmResource = $actionGroupArm.resources | Where-Object { $_.Name -eq $([Constants]::AlertActionGroupName) } 
			$actionGroupArmResourceOutput = $actionGroupArm.outputs.actionGroupId
			$actionGroupArmResource.name="ResourceDeploymentActionGroup"
			$actionGroupArmResourceOutput.value = $actionGroupArmResourceOutput.value.Replace($([Constants]::AlertActionGroupName),$([Constants]::ResourceDeploymentActionGroupName));
			$actionGroupArmResource.properties.PSObject.Properties.Remove('emailReceivers')
            $actionGroupArmResource.properties.PSObject.Properties.Remove('smsReceivers')
			
			$armTemplatePath =[Constants]::AzSKTempFolderPath + "Subscription.AlertActionGroup.json"
			$actionGroupArm | ConvertTo-Json -Depth 100  | New-Item $armTemplatePath -Force
			$actionGroupResource = New-AzureRmResourceGroupDeployment -Name "AzSKAlertActionGroupDeployment" -ResourceGroupName $this.ResourceGroup -TemplateFile $armTemplatePath  -ErrorAction Stop
			$actionGroupId = $actionGroupResource.Outputs | Where-Object actionGroupId 
			$actionGroupResourceId = $actionGroupId.Values | Select-Object -ExpandProperty Value                      
			Remove-Item $armTemplatePath  -ErrorAction SilentlyContinue
		}
		catch
		{	
			#Eating up this error while action group is not setup we are showing user friendly message
			#$this.PublishException($_);
		}
		
		return 	$actionGroupResourceId
	}

	hidden [MessageData[]] CleanV1Alerts()
	{
		#Validate if V1(Old) Alert RG present 
		$messages = @();
		$existingRG = Get-AzureRmResourceGroup -Name $this.V1AlertRGName -ErrorAction SilentlyContinue
		if($existingRG)
		{
			# Remove all locks
			$messages += $this.RemoveAllResourceGroupLocks();
			$messages += [MessageData]::new("Found old deprecated alert resource group (AzSKAlertsRG). Removing all V1 AzSK configured alerts by removing deprecated resource group");
			Remove-AzureRmResourceGroup -Name $this.V1AlertRGName -Force
		}

		return $messages
	}

	hidden [MessageData[]] RemoveAllResourceGroupLocks()
	{
		$messages = @();
		#Remove Resource Lock on Resource Group if any
		$locks = @();
		$locks += Get-AzureRmResourceLock -ResourceGroupName $this.V1AlertRGName
		if($locks.Count -ne 0)
		{
			$messages += [MessageData]::new("Removing following existing resource group locks so that old alert RG can be removed.", $locks);

			$locks | ForEach-Object {
				Remove-AzureRmResourceLock -LockId $_.LockId -Force | Out-Null
			}
			Start-Sleep -Seconds 60
		}
		return $messages;
	}

	hidden [string] GetV1AlertSecurityEmailContact()
	{
		#Validate if V1(Old) Alert RG present 
		$existingRG = Get-AzureRmResourceGroup -Name $this.V1AlertRGName -ErrorAction SilentlyContinue
		$emailList  = [string]::Empty
		if($existingRG)
		{
			#Check if V1 alert resource is present
			$configuredAlerts = Get-AzureRmResource -ResourceGroup $this.V1AlertRGName -ResourceType 'microsoft.insights/alertrules' 
			if(($configuredAlerts | Measure-Object).Count -gt 0)
			{
				#Validate if command exists. As this command will soon get deprecated from AzureRM
				if (Get-Command "Get-AzureRmAlertRule" -errorAction SilentlyContinue)
				{
					$alertResourceDetails = $configuredAlerts | Select-Object -First 1
					$alertRuleDetails = Get-AzureRMAlertRule -ResourceGroup $this.V1AlertRGName -Name $alertResourceDetails.Name -WarningAction SilentlyContinue
					if($alertRuleDetails)
					{
						$emailList = [string]::Join(",",($alertRuleDetails.Actions | Select-Object @{N='EmailList';E={$_.CustomEmails}} ).EmailList)
						    
					}					    
				}				  
			}			
		}
		return $emailList 	
	}

	hidden [PSObject] GetAlertActionGroup($rgName, $actionGroupName)
	{
		#Validate if Alert RG present 
		$existingRG = Get-AzureRmResourceGroup -Name $rgName -ErrorAction SilentlyContinue
		if($existingRG)
		{
			$AGRSource = Find-AzureRmResource -ResourceType  microsoft.insights/actiongroups -ResourceGroupName $rgName -ResourceNameEquals $actionGroupName
			return $AGRSource;
		}
		else
		{
			return $null
		}	
	}
	hidden [string] ComputeAlertRunbookWebhookUri([string] $type)
	{
        $ActionGroup = ""
		if($type -eq "Alert")
		{
			$ActionGroup = [Constants]::AlertActionGroupName
		}
		elseif($type -eq "ResourceCreation")
		{
			$ActionGroup = [Constants]::ResourceDeploymentActionGroupName
		}

		$actionGroupResource = $this.GetAlertActionGroup($this.ResourceGroup, $ActionGroup);
		$existingWebhookUri = $null;
        if($null -eq $actionGroupResource)
        {			          
			$existingWebhookUri=$null;
		}
		else
		{ 
			  $existingActionGrp= Get-AzureRmResource -ResourceId $actionGroupResource.ResourceId
			  if(($existingActionGrp.Properties.webhookReceivers | Measure-Object).Count -gt 0)
			  {
				$webhookReceivers=$existingActionGrp.Properties.webhookReceivers | Select-Object -first 1
				$existingWebhookUri=$webhookReceivers.serviceUri;
			  }
			  else
			  {
			    $existingWebhookUri=$null;
			  }
		}
		return $existingWebhookUri
	}


	hidden [string] UpdateActionGroupWebhookUri([string] $existingWebhookUri,[string] $type)
	{
	 #pass webhook uri if exist n actiongrp(update SS cmd) or create a new webhook uri(install CA ,update CA)
		$ActionGroup = ""
		if($type -eq "Alert")
		{
			$ActionGroup = [Constants]::AlertActionGroupName
			$Alertname = "WebHookForMonitoringAlerts"
		}
		elseif($type -eq "ResourceCreation")
		{
			$ActionGroup = [Constants]::ResourceDeploymentActionGroupName
			$Alertname = "WebHookForResourceCreationAlerts"
		}
		else
		{
			$Alertname = ""
		}
		$actionGroupResourceId = $this.GetAlertActionGroup($this.ResourceGroup, $ActionGroup)
		$runBookResourceID= $this.GetAlertRunBookResourceId($type)
		#check for empty string
		if($null -ne $actionGroupResourceId -and (-not [string]::IsNullOrWhiteSpace($runBookResourceID)))
		{
			$existingActionGrp= Get-AzureRmResource -ResourceId $actionGroupResourceId.ResourceId
			$webhookReceiversList = @();
			if(-not [string]::IsNullOrWhiteSpace($existingWebhookUri))
			{
			$webhookUri=$existingWebhookUri;
			}
			else
			{
			$webhookUri=$this.GetAlertRunBookWebHookUri($type);
			}	
			$props = @{
					name = $Alertname
					serviceUri=$webhookUri
					}
			$object = new-object psobject -Property $props
			$webhookReceiversList += $object 
			$existingActionGrp.Properties.webhookReceivers=$webhookReceiversList
			$existingActionGrp | Set-AzureRmResource -Force

		}
		return [string]::Empty
	}
	hidden [string] RemoveActionGroupWebhookUri()
	{
	  $actionGroupResourceId = $this.GetAlertActionGroup($this.ResourceGroup, [Constants]::AlertActionGroupName)
	  $runBookResourceID= $this.GetAlertRunBookResourceId()

	  if($null -ne $actionGroupResourceId -and (-not [string]::IsNullOrWhiteSpace($runBookResourceID)))
	  {
	   try
	   {
	     $existingActionGrp= Get-AzureRmResource -ResourceId $actionGroupResourceId.ResourceId
         $webhookReceiversList = @();
         $existingActionGrp.Properties.webhookReceivers=$webhookReceiversList
         $existingActionGrp | Set-AzureRmResource -Force
		 #Remove Webhook from Automation Runbook as well
		 Remove-AzureRmAutomationWebhook -Name $this.AutomationWebhookName -ResourceGroup $this.ResourceGroup -AutomationAccountName $this.AutomationAccountName -ErrorAction SilentlyContinue
	   }
	   catch
	   {
		# It will retry, no need to break execution
	   }
	  }
	  return [string]::Empty
	}
	hidden [string] GetAlertRunbookResourceId([string] $type)
	{
		#Validate if Alert RG present $this.ResourceGroup
		$existingRG = Get-AzureRmResourceGroup -Name $this.ResourceGroup -ErrorAction SilentlyContinue
		if($existingRG)
		{
			$RunbookNamebyType = ""
			if($type -eq "Alert")
			{
				$RunbookNamebyType = $this.RunbookName
			}
			elseif($type -eq "ResourceCreation")
			{
				$RunbookNamebyType = $this.Alert_ResourceCreation_Runbook
			}
		     $resourceName=$this.AutomationAccountName+"/"+$RunbookNamebyType
			 $AlertRunBook = Find-AzureRmResource -ResourceType  "Microsoft.Automation/automationAccounts/runbooks" -ResourceGroupName $this.ResourceGroup -ResourceNameEquals $resourceName
			if($AlertRunBook )
			{
				return $AlertRunBook.ResourceId
			}
			else
			{
				return [string]::Empty
			}			
		}
		else
		{
			return [string]::Empty
		}	
	}
	hidden [string] GetAlertRunBookWebHookUri([string] $type)
	{    
	    try
		{
		$RunbookNamebyType = ""
        $Alertname = ""
		if($type -eq "Alert")
		{
			$RunbookNamebyType = $this.RunbookName
            $Alertname = "WebHookForMonitoringAlerts"
		}
		elseif($type -eq "ResourceCreation")
		{
			$RunbookNamebyType = $this.Alert_ResourceCreation_Runbook
            $Alertname = "WebHookForResourceCreationAlerts"
		}

	    $webhookExpiryDate=(Get-Date).AddDays($this.WebhookExpiryInDays)
		Remove-AzureRmAutomationWebhook -Name $Alertname -ResourceGroup $this.ResourceGroup -AutomationAccountName $this.AutomationAccountName -ErrorAction SilentlyContinue
		$Webhook = New-AzureRmAutomationWebhook -Name $Alertname -IsEnabled $True -ExpiryTime $webhookExpiryDate -RunbookName $RunbookNamebyType -ResourceGroup $this.ResourceGroup -AutomationAccountName $this.AutomationAccountName -Force
        $NewWebHookUri=$Webhook.WebhookURI
	    return $NewWebHookUri;		
		}
		catch{
		  $this.PublishException($_)
		  return [string]::Empty
		}
	}
}
