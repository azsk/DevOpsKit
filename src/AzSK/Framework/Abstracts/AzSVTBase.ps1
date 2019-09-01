class AzSVTBase: SVTBase{

	hidden [ControlStateExtension] $ControlStateExt;

    AzSVTBase()
	{

	}

	AzSVTBase([string] $subscriptionId):
		Base($subscriptionId)
	{
		$this.CreateInstance();
	}
	AzSVTBase([string] $subscriptionId, [SVTResource] $svtResource):
	Base($subscriptionId)
	{		
		$this.CreateInstance($svtResource);
	}
	 #Create instance for subscription scan 
	 hidden [void] CreateInstance()
	 {
		 [Helpers]::AbstractClass($this, [SVTBase]);
 
		 $this.LoadSvtConfig([SVTMapping]::SubscriptionMapping.JsonFileName);
		 $this.ResourceId = $this.SubscriptionContext.Scope;	
	 }
   
	#Add PreviewBaselineControls
	hidden [bool] CheckBaselineControl($controlId)
	{
		if(($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings,"BaselineControls.ResourceTypeControlIdMappingList"))
		{
		  $baselineControl = $this.ControlSettings.BaselineControls.ResourceTypeControlIdMappingList | Where-Object {$_.ControlIds -contains $controlId}
		   if(($baselineControl | Measure-Object).Count -gt 0 )
			{
				return $true
			}
		}

		if(($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings,"BaselineControls.SubscriptionControlIdList"))
		{
		  $baselineControl = $this.ControlSettings.BaselineControls.SubscriptionControlIdList | Where-Object {$_ -eq $controlId}
		   if(($baselineControl | Measure-Object).Count -gt 0 )
			{
				return $true
			}
		}
		return $false
	}
	hidden [bool] CheckPreviewBaselineControl($controlId)
	{
		if(($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings,"PreviewBaselineControls.ResourceTypeControlIdMappingList"))
		{
		  $PreviewBaselineControls = $this.ControlSettings.PreviewBaselineControls.ResourceTypeControlIdMappingList | Where-Object {$_.ControlIds -contains $controlId}
		   if(($PreviewBaselineControls | Measure-Object).Count -gt 0 )
			{
				return $true
			}
		}

		if(($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings,"PreviewBaselineControls.SubscriptionControlIdList"))
		{
		  $PreviewBaselineControls = $this.ControlSettings.PreviewBaselineControls.SubscriptionControlIdList | Where-Object {$_ -eq $controlId}
		   if(($PreviewBaselineControls | Measure-Object).Count -gt 0 )
			{
				return $true
			}
		}
		return $false
	}

	hidden [void] GetResourceId()
    {

		try {
			if ([FeatureFlightingManager]::GetFeatureStatus("EnableResourceGroupTagTelemetry","*") -eq $true -and $this.ResourceId -and $this.ResourceContext -and $this.ResourceTags.Count -eq 0) {
				
					$tags = (Get-AzResourceGroup -Name $this.ResourceContext.ResourceGroupName).Tags
					if( $tags -and ($tags | Measure-Object).Count -gt 0)
					{
						$this.ResourceTags = $tags
					}			
			}   
		} catch {
			# flow shouldn't break if there are errors in fetching tags eg. locked resource groups. <TODO: Add exception telemetry>
		}
    }

    hidden [ControlResult] CheckPolicyCompliance([ControlItem] $controlItem, [ControlResult] $controlResult)
	{
		$initiativeName = [ConfigurationManager]::GetAzSKConfigData().AzSKInitiativeName
		$defnResourceId = $this.ResourceId + $controlItem.PolicyDefnResourceIdSuffix
		$policyState = Get-AzPolicyState -ResourceId $defnResourceId -Filter "PolicyDefinitionId eq '/providers/microsoft.authorization/policydefinitions/$($controlItem.PolicyDefinitionGuid)' and PolicySetDefinitionName eq '$initiativeName'"
		if($policyState)
        {
            $policyStateObject = $policyState | Select-Object ResourceId, PolicyAssignmentId, PolicyDefinitionId, PolicyAssignmentScope, PolicyDefinitionAction, PolicySetDefinitionName, IsCompliant
		    if($policyState.IsCompliant)
            {
			    $controlResult.AddMessage([VerificationResult]::Passed,
										    [MessageData]::new("Policy compliance data:", $policyStateObject));
            }
		    else
            { 
			    #$controlResult.EnableFixControl = $true;
			    $controlResult.AddMessage([VerificationResult]::Failed,
										    [MessageData]::new("Policy compliance data:", $policyStateObject));
            }
            return $controlResult;
        }
        return $null;
    }
	# Policy compliance methods end
	hidden [ControlResult] CheckDiagnosticsSettings([ControlResult] $controlResult)
	{
		$diagnostics = $Null
		try
		{
			$diagnostics = Get-AzDiagnosticSetting -ResourceId $this.ResourceId -ErrorAction Stop -WarningAction SilentlyContinue
		}
		catch
		{
			if([Helpers]::CheckMember($_.Exception, "Response") -and ($_.Exception).Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "Diagnostics setting is disabled for resource - [$($this.ResourceContext.ResourceName)].");
				return $controlResult
			}
			else
			{
				$this.PublishException($_);
			}
		}
		if($Null -ne $diagnostics -and ($diagnostics.Logs | Measure-Object).Count -ne 0)
		{
			$nonCompliantLogs = $diagnostics.Logs |
								Where-Object { -not ($_.Enabled -and
											($_.RetentionPolicy.Days -eq $this.ControlSettings.Diagnostics_RetentionPeriod_Forever -or
											$_.RetentionPolicy.Days -ge $this.ControlSettings.Diagnostics_RetentionPeriod_Min))};

			$selectedDiagnosticsProps = $diagnostics | Select-Object -Property Logs, Metrics, StorageAccountId, EventHubName, Name;

			if(($nonCompliantLogs | Measure-Object).Count -eq 0)
			{
				$controlResult.AddMessage([VerificationResult]::Passed,
					"Diagnostics settings are correctly configured for resource - [$($this.ResourceContext.ResourceName)]",
					$selectedDiagnosticsProps);
			}
			else
			{
				$failStateDiagnostics = $nonCompliantLogs | Select-Object -Property Logs, Metrics, StorageAccountId, EventHubName, Name;
				$controlResult.SetStateData("Non compliant resources are:", $failStateDiagnostics);
				$controlResult.AddMessage([VerificationResult]::Failed,
					"Diagnostics settings are either disabled OR not retaining logs for at least $($this.ControlSettings.Diagnostics_RetentionPeriod_Min) days for resource - [$($this.ResourceContext.ResourceName)]",
					$selectedDiagnosticsProps);
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Failed, "Diagnostics setting is disabled for resource - [$($this.ResourceContext.ResourceName)].");
		}

		return $controlResult;
	}

	hidden [ControlResult] CheckRBACAccess([ControlResult] $controlResult)
	{
		$accessList = [RoleAssignmentHelper]::GetAzSKRoleAssignmentByScope($this.ResourceId, $false, $true);
		return $this.CheckRBACAccess($controlResult, $accessList)
	}

	hidden [ControlResult] CheckRBACAccess([ControlResult] $controlResult, [PSObject] $accessList)
	{
		$resourceAccessList = $accessList | Where-Object { $_.Scope -eq $this.ResourceId };

        $controlResult.VerificationResult = [VerificationResult]::Verify;

		if(($resourceAccessList | Measure-Object).Count -ne 0)
        {
			$controlResult.SetStateData("Identities having RBAC access at resource level", ($resourceAccessList | Select-Object -Property ObjectId,RoleDefinitionId,RoleDefinitionName,Scope));

            $controlResult.AddMessage("Validate that the following identities have explicitly provided with RBAC access to resource - [$($this.ResourceContext.ResourceName)]");
            $controlResult.AddMessage([MessageData]::new($this.CreateRBACCountMessage($resourceAccessList), $resourceAccessList));
        }
        else
        {
            $controlResult.AddMessage("No identities have been explicitly provided with RBAC access to resource - [$($this.ResourceContext.ResourceName)]");
        }

        $inheritedAccessList = $accessList | Where-Object { $_.Scope -ne $this.ResourceId };

		if(($inheritedAccessList | Measure-Object).Count -ne 0)
        {
            $controlResult.AddMessage("Note: " + $this.CreateRBACCountMessage($inheritedAccessList) + " have inherited RBAC access to resource. It's good practice to keep the RBAC access to minimum.");
        }
        else
        {
            $controlResult.AddMessage("No identities have inherited RBAC access to resource");
        }

		return $controlResult;
	}

	hidden [string] CreateRBACCountMessage([array] $resourceAccessList)
	{
		$nonNullObjectTypes = $resourceAccessList | Where-Object { -not [string]::IsNullOrEmpty($_.ObjectType) };
		if(($nonNullObjectTypes | Measure-Object).Count -eq 0)
		{
			return "$($resourceAccessList.Count) identities";
		}
		else
		{
			$countBreakupString = [string]::Join(", ",
									($nonNullObjectTypes |
										Group-Object -Property ObjectType -NoElement |
										ForEach-Object { "$($_.Name): $($_.Count)" }
									));
			return "$($resourceAccessList.Count) identities ($countBreakupString)";
		}
	}

	hidden [bool] CheckMetricAlertConfiguration([PSObject[]] $metricSettings, [ControlResult] $controlResult, [string] $extendedResourceName)
	{
		$result = $false;
		if($metricSettings -and $metricSettings.Count -ne 0)
		{
			$resId = $this.ResourceId + $extendedResourceName;
			$resIdMessageString = "";
			if(-not [string]::IsNullOrWhiteSpace($extendedResourceName))
			{
				$resIdMessageString = "for nested resource [$extendedResourceName]";
			}

			$resourceAlerts = @()
            # get classic alerts
			$resourceAlerts += (Get-AzAlertRule -ResourceGroup $this.ResourceContext.ResourceGroupName -WarningAction SilentlyContinue) |
								Where-Object { $_.Condition -and $_.Condition.DataSource } |
								Where-Object { $_.Condition.DataSource.ResourceUri -eq $resId };

			# get non-classic alerts
            try
            {
                $apiURL = "https://management.azure.com/subscriptions/{0}/providers/Microsoft.Insights/metricAlerts?api-version=2018-03-01&`$filter=targetResource eq '{1}'" -f $($this.SubscriptionContext.SubscriptionId), $resId
				$v2Alerts = [WebRequestHelper]::InvokeGetWebRequest($apiURL) 
                if(($v2Alerts | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($v2Alerts[0],"id"))
                {
                    $v2Alerts |  ForEach-Object {
						if([Helpers]::CheckMember($_,"properties"))
						{
    
							$alert = '{
                                  "Condition":  {
                                                    "DataSource":  {
                                                                       "MetricName":  ""
                                                                   },
                                                    "OperatorProperty":  "",
                                                    "Threshold": "" ,
                                                    "TimeAggregation":  "",
                                                    "WindowSize":  ""
                                                },
                                  "Actions"  :  null,
                                  "Description" : "",
                                  "IsEnabled":  "",
                                  "Name" : "",
								  "Type" : "",
								  "AlertType" : "V2Alert"
                            }' | ConvertFrom-Json
							if([Helpers]::CheckMember($_,"properties.criteria.allOf"))
							{
								$alert.Condition.DataSource.MetricName = $_.properties.criteria.allOf.metricName
								$alert.Condition.OperatorProperty = $_.properties.criteria.allOf.operator
								$alert.Condition.Threshold = [int] $_.properties.criteria.allOf.threshold
								$alert.Condition.TimeAggregation = $_.properties.criteria.allOf.timeAggregation
							}
							$alert.Condition.WindowSize = ([Xml.XmlConvert]::ToTimeSpan("$($_.properties.windowSize)")).ToString()
							$alert.Actions = [System.Collections.Generic.List[Microsoft.Azure.Management.Monitor.Models.RuleAction]]::new()
							if([Helpers]::CheckMember($_.properties,"Actions.actionGroupId"))
							{
								$actionGroupTemp = $_.properties.Actions.actionGroupId.Split("/")
								$actionGroup = Get-AzActionGroup -ResourceGroupName $actionGroupTemp[4] -Name $actionGroupTemp[-1] -WarningAction SilentlyContinue
								if($actionGroup.EmailReceivers.Status -eq [Microsoft.Azure.Management.Monitor.Models.ReceiverStatus]::Enabled)
								{
									if([Helpers]::CheckMember($actionGroup,"EmailReceivers.EmailAddress"))
									{
										$alert.Actions.Add($(New-AzAlertRuleEmail -SendToServiceOwner -CustomEmail $actionGroup.EmailReceivers.EmailAddress  -WarningAction SilentlyContinue));
									}
									else
									{
										$alert.Actions.Add($(New-AzAlertRuleEmail -SendToServiceOwner -WarningAction SilentlyContinue));
									}	
								}
							}				
							$alert.Description = $_.properties.description
							$alert.IsEnabled = $_.properties.enabled
							$alert.Name = $_.name
							$alert.Type = $_.type
                            if(($alert|Measure-Object).Count -gt 0)
                            {
                               $resourceAlerts += $alert 
                            }
						}
                    }
                }   
            }
            catch
            {
                $this.PublishException($_);
            }

			$nonConfiguredMetrices = @();
			$misConfiguredMetrices = @();

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
					#$controlResult.AddMessage("Metric object", $matchedMetrices);
					$matchedMetrices | ForEach-Object {
						if([Helpers]::CompareObject($currentMetric, $_))
						{
							#$this.ControlSettings.MetricAlert.Actions
							if(($_.Actions.GetType().GetMembers() | Where-Object { $_.MemberType -eq [System.Reflection.MemberTypes]::Property -and $_.Name -eq "Count" } | Measure-Object).Count -ne 0)
							{
								$isActionConfigured = $false;
								foreach ($action in $_.Actions) {
									if([Helpers]::CompareObject($this.ControlSettings.MetricAlert.Actions, $action))
									{
										$isActionConfigured = $true;
										break;
									}
								}

								if(-not $isActionConfigured)
								{
									$misConfigured += $_;
								}
							}
							else
							{
								if(-not [Helpers]::CompareObject($this.ControlSettings.MetricAlert.Actions, $_.Actions))
								{
									$misConfigured += $_;
								}
							}
						}
						else
						{
							$misConfigured += $_;
						}
					};

					if($misConfigured.Count -eq $matchedMetrices.Count)
					{
						$misConfiguredMetrices += $misConfigured;
					}
				}
			}

			$controlResult.AddMessage("Following metric alerts must be configured $resIdMessageString with settings mentioned below:", $metricSettings);
			$controlResult.VerificationResult = [VerificationResult]::Failed;

			if($nonConfiguredMetrices.Count -ne 0)
			{
				$controlResult.AddMessage("Following metric alerts are not configured $($resIdMessageString):", $nonConfiguredMetrices);
			}

			if($misConfiguredMetrices.Count -ne 0)
			{
				$controlResult.AddMessage("Following metric alerts are not correctly configured $resIdMessageString. Please update the metric settings in order to comply.", $misConfiguredMetrices);
			}

			if($nonConfiguredMetrices.Count -eq 0 -and $misConfiguredMetrices.Count -eq 0)
			{
				$result = $true;
				$controlResult.AddMessage([VerificationResult]::Passed , "All mandatory metric alerts are correctly configured $resIdMessageString.");
			}
		}
		else
		{
			throw [System.ArgumentException] ("The argument 'metricSettings' is null or empty");
		}

		return $result;
	}
    
	hidden [void] GetDataFromSubscriptionReport($singleControlResult)
    {   
    try
     {
         $azskConfig = [ConfigurationManager]::GetAzSKConfigData();	
         $settingStoreComplianceSummaryInUserSubscriptions = [ConfigurationManager]::GetAzSKSettings().StoreComplianceSummaryInUserSubscriptions;
         #return if feature is turned off at server config
         if(-not $azskConfig.StoreComplianceSummaryInUserSubscriptions -and -not $settingStoreComplianceSummaryInUserSubscriptions) {return;}

            if(($this.ComplianceStateData | Measure-Object).Count -gt 0)
         {
             $ResourceData = @();
             $PersistedControlScanResult=@();								
         
             #$ResourceScanResult=$ResourceData.ResourceScanResult
             [ControlResult[]] $controlsResults = @();
             $singleControlResult.ControlResults | ForEach-Object {
                 $currentControl=$_
                 $partsToHash = $singleControlResult.ControlItem.Id;
                 if(-not [string]::IsNullOrWhiteSpace($currentControl.ChildResourceName))
                 {
                     $partsToHash = $partsToHash + ":" + $currentControl.ChildResourceName;
                 }
                 $rowKey = [Helpers]::ComputeHash($partsToHash.ToLower());

                 $matchedControlResult = $this.ComplianceStateData | Where-Object { $_.RowKey -eq $rowKey}

                 # initialize default values
                 $currentControl.FirstScannedOn = [DateTime]::UtcNow
                 if($currentControl.ActualVerificationResult -ne [VerificationResult]::Passed)
                 {
                     $currentControl.FirstFailedOn = [DateTime]::UtcNow
                 }
                 if($null -ne $matchedControlResult -and ($matchedControlResult | Measure-Object).Count -gt 0)
                 {
                     $currentControl.UserComments = $matchedControlResult.UserComments
                     $currentControl.FirstFailedOn = [datetime] $matchedControlResult.FirstFailedOn
                     $currentControl.FirstScannedOn = [datetime] $matchedControlResult.FirstScannedOn						
                 }

                 $scanFromDays = [System.DateTime]::UtcNow.Subtract($currentControl.FirstScannedOn)

                 $currentControl.MaximumAllowedGraceDays = $this.CalculateGraceInDays($singleControlResult);

                 # Setting isControlInGrace Flag		
                 if($scanFromDays.Days -le $currentControl.MaximumAllowedGraceDays)
                 {
                     $currentControl.IsControlInGrace = $true
                 }
                 else
                 {
                     $currentControl.IsControlInGrace = $false
                 }
                 
                 $controlsResults+=$currentControl
             }
             $singleControlResult.ControlResults=$controlsResults 
         }
     }
     catch
     {
       $this.PublishException($_);
     }
    }

	hidden [void] UpdateControlStates([SVTEventContext[]] $ControlResults)
	{
		if($null -ne $this.ControlStateExt -and $this.ControlStateExt.HasControlStateWriteAccessPermissions() -and ($ControlResults | Measure-Object).Count -gt 0 -and ($this.ResourceState | Measure-Object).Count -gt 0)
		{
			$effectiveResourceStates = @();
			if(($this.DirtyResourceStates | Measure-Object).Count -gt 0)
			{
				$this.ResourceState | ForEach-Object {
					$controlState = $_;
					if(($this.DirtyResourceStates | Where-Object { $_.InternalId -eq $controlState.InternalId -and $_.ChildResourceName -eq $controlState.ChildResourceName } | Measure-Object).Count -eq 0)
					{
						$effectiveResourceStates += $controlState;
					}
				}
			}
			else
			{
				#If no dirty states found then no action needed.
				return;
			}

			#get the uniqueid from the first control result. Here we can take first as it would come here for each resource.
			$id = $ControlResults[0].GetUniqueId();

			$this.ControlStateExt.SetControlState($id, $effectiveResourceStates, $true)
		}
	}

	hidden [ControlState[]] GetResourceState()
	{
		if($null -eq $this.ResourceState)
		{
			$this.ResourceState = @();
			if($this.ControlStateExt -and $this.ControlStateExt.HasControlStateReadAccessPermissions())
			{
				$resourceStates = $this.ControlStateExt.GetControlState($this.ResourceId)
				if($null -ne $resourceStates)
				{
					$this.ResourceState += $resourceStates
				}
				else
				{
					return $null;
				}				
			}
		}

		return $this.ResourceState;
	}

	hidden [void] PostProcessData([SVTEventContext] $eventContext)
	{
		$tempHasRequiredAccess = $true;
		$controlState = @();
		$controlStateValue = @();
		try
		{
			# Get policy compliance if org-level flag is enabled and policy is found 
			#TODO: set flag in a variable once and reuse it
			
			if([FeatureFlightingManager]::GetFeatureStatus("EnableAzurePolicyBasedScan",$($this.SubscriptionContext.SubscriptionId)) -eq $true)
			{
				if(-not [string]::IsNullOrWhiteSpace($eventContext.ControlItem.PolicyDefinitionGuid))
				{
					#create default controlresult
					$policyScanResult = $this.CreateControlResult($eventContext.ControlItem.FixControl);
					#update default controlresult with policy compliance state
					$policyScanResult = $this.CheckPolicyCompliance($eventContext.ControlItem, $policyScanResult);
					#todo: currently excluding child controls
					if($eventContext.ControlResults.Count -eq 1 -and $Null -ne $policyScanResult)
					{
						$finalScanResult = $this.ComputeFinalScanResult($eventContext.ControlResults[0],$policyScanResult)
						$eventContext.ControlResults[0] = $finalScanResult
					}
				}
			}
			
			$this.GetDataFromSubscriptionReport($eventContext);

			$resourceStates = $this.GetResourceState()			
			if(($resourceStates | Measure-Object).Count -ne 0)
			{
				$controlStateValue += $resourceStates | Where-Object { $_.InternalId -eq $eventContext.ControlItem.Id };
				$controlStateValue | ForEach-Object {
					$currentControlStateValue = $_;
					if($null -ne $currentControlStateValue)
					{
						if($this.IsStateActive($eventContext, $currentControlStateValue))
						{
							$controlState += $currentControlStateValue;
						}
						else
						{
							#add to the dirty state list so that it can be removed later
							$this.DirtyResourceStates += $currentControlStateValue;
						}
					}
				}
			}
			elseif($null -eq $resourceStates)
			{
				$tempHasRequiredAccess = $false;
			}
		}
		catch
		{
			$this.EvaluationError($_);
		}

		$eventContext.ControlResults |
		ForEach-Object {
			try
			{
				$currentItem = $_;
				# Copy the current result to Actual Result field
				$currentItem.ActualVerificationResult = $currentItem.VerificationResult;

				#Logic to append the control result with the permissions metadata
				[SessionContext] $sc = $currentItem.CurrentSessionContext;
				$sc.Permissions.HasAttestationWritePermissions = $this.ControlStateExt.HasControlStateWriteAccessPermissions();
				$sc.Permissions.HasAttestationReadPermissions = $this.ControlStateExt.HasControlStateReadAccessPermissions();
				# marking the required access as false if there was any error reading the attestation data
				$sc.Permissions.HasRequiredAccess = $sc.Permissions.HasRequiredAccess -and $tempHasRequiredAccess;

				# Disable the fix control feature
				if(-not $this.GenerateFixScript)
				{
					$currentItem.EnableFixControl = $false;
				}

				if($currentItem.StateManagement.CurrentStateData -and $currentItem.StateManagement.CurrentStateData.DataObject -and $eventContext.ControlItem.DataObjectProperties)
				{
					$currentItem.StateManagement.CurrentStateData.DataObject = [Helpers]::SelectMembers($currentItem.StateManagement.CurrentStateData.DataObject, $eventContext.ControlItem.DataObjectProperties);
				}

				if($controlState.Count -ne 0)
				{
					# Process the state if its available
					$childResourceState = $controlState | Where-Object { $_.ChildResourceName -eq  $currentItem.ChildResourceName } | Select-Object -First 1;
					if($childResourceState)
					{
						# Skip passed ones from State Management
						if($currentItem.ActualVerificationResult -ne [VerificationResult]::Passed)
						{
							#compare the states
							if(($childResourceState.ActualVerificationResult -eq $currentItem.ActualVerificationResult) -and $childResourceState.State)
							{
								$currentItem.StateManagement.AttestedStateData = $childResourceState.State;

								# Compare dataobject property of State
								if($null -ne $childResourceState.State.DataObject)
								{
									if($currentItem.StateManagement.CurrentStateData -and $null -ne $currentItem.StateManagement.CurrentStateData.DataObject)
									{
										$currentStateDataObject = [JsonHelper]::ConvertToJsonCustom($currentItem.StateManagement.CurrentStateData.DataObject) | ConvertFrom-Json

										try
										{
											# Objects match, change result based on attestation status
											if($eventContext.ControlItem.AttestComparisionType -and $eventContext.ControlItem.AttestComparisionType -eq [ComparisionType]::NumLesserOrEqual)
											{
												if([Helpers]::CompareObject($childResourceState.State.DataObject, $currentStateDataObject, $true,$eventContext.ControlItem.AttestComparisionType))
												{
													$this.ModifyControlResult($currentItem, $childResourceState);
												}
												
											}
											else
											{
												if([Helpers]::CompareObject($childResourceState.State.DataObject, $currentStateDataObject, $true))
												{
														$this.ModifyControlResult($currentItem, $childResourceState);
												}
											}
										}
										catch
										{
											$this.EvaluationError($_);
										}
									}
								}
								else
								{
									if($currentItem.StateManagement.CurrentStateData)
									{
										if($null -eq $currentItem.StateManagement.CurrentStateData.DataObject)
										{
											# No object is persisted, change result based on attestation status
											$this.ModifyControlResult($currentItem, $childResourceState);
										}
									}
									else
									{
										# No object is persisted, change result based on attestation status
										$this.ModifyControlResult($currentItem, $childResourceState);
									}
								}
							}
						}
						else
						{
							#add to the dirty state list so that it can be removed later
							$this.DirtyResourceStates += $childResourceState
						}
					}
				}
			}
			catch
			{
				$this.EvaluationError($_);
			}
		};
	}

		# State Machine implementation of modifying verification result
		hidden [void] ModifyControlResult([ControlResult] $controlResult, [ControlState] $controlState)
		{
			# No action required if Attestation status is None OR verification result is Passed
			if($controlState.AttestationStatus -ne [AttestationStatus]::None -or $controlResult.VerificationResult -ne [VerificationResult]::Passed)
			{
				$controlResult.AttestationStatus = $controlState.AttestationStatus;
				$controlResult.VerificationResult = [Helpers]::EvaluateVerificationResult($controlResult.VerificationResult, $controlState.AttestationStatus);
			}
		}

			#Function to validate attestation data expiry validation
	hidden [bool] IsStateActive([SVTEventContext] $eventcontext,[ControlState] $controlState)
	{
		try
		{
			$expiryIndays = $this.CalculateExpirationInDays([SVTEventContext] $eventcontext,[ControlState] $controlState);
			#Validate if expiry period is passed
			#Added a condition so as to expire attested controls that were in 'Error' state.
			if(($expiryIndays -ne -1 -and $controlState.State.AttestedDate.AddDays($expiryIndays) -lt [DateTime]::UtcNow) -or ($controlState.ActualVerificationResult -eq [VerificationResult]::Error))
			{
				return $false
			}
			else
			{
				$controlState.State.ExpiryDate = ($controlState.State.AttestedDate.AddDays($expiryIndays)).ToString("MM/dd/yyyy");
				return $true
			}
		}
		catch
		{
			#if any exception occurs while getting/validating expiry period, return true.
			$this.EvaluationError($_);
			return $true
		}
	}

	hidden [int] CalculateExpirationInDays([SVTEventContext] $eventcontext,[ControlState] $controlState)
	{
		try
		{
			#For exempt controls, either the no. of days for expiry were provided at the time of attestation or a default of 6 motnhs was already considered,
			#therefore skipping this flow and calculating days directly using the expiry date already saved.
			if($controlState.AttestationStatus -ne [AttestationStatus]::ApprovedException)
			{
				#Get controls expiry period. Default value is zero
				$controlAttestationExpiry = $eventcontext.controlItem.AttestationExpiryPeriodInDays
				$controlSeverity = $eventcontext.controlItem.ControlSeverity
				$controlSeverityExpiryPeriod = 0
				$defaultAttestationExpiryInDays = [Constants]::DefaultControlExpiryInDays;
				$expiryInDays=-1;
	
				if(($eventcontext.ControlResults |Measure-Object).Count -gt 0)	
				{
					$isControlInGrace=$eventcontext.ControlResults.IsControlInGrace;
				}
				else
				{
					$isControlInGrace=$true;
				}
				if([Helpers]::CheckMember($this.ControlSettings,"AttestationExpiryPeriodInDays") `
						-and [Helpers]::CheckMember($this.ControlSettings.AttestationExpiryPeriodInDays,"Default") `
						-and $this.ControlSettings.AttestationExpiryPeriodInDays.Default -gt 0)
				{
					$defaultAttestationExpiryInDays = $this.ControlSettings.AttestationExpiryPeriodInDays.Default
				}			
				#Expiry in the case of WillFixLater or StateConfirmed/Recurring Attestation state will be based on Control Severity.
				if($controlState.AttestationStatus -eq [AttestationStatus]::NotAnIssue -or $controlState.AttestationStatus -eq [AttestationStatus]::NotApplicable)
				{
					$expiryInDays=$defaultAttestationExpiryInDays;
				}
				else
				{
					# Expire WillFixLater if GracePeriod has expired
					if(-not($isControlInGrace) -and $controlState.AttestationStatus -eq [AttestationStatus]::WillFixLater)
					{
						$expiryInDays=0;
					}
					else
					{
						if($controlAttestationExpiry -ne 0)
						{
							$expiryInDays = $controlAttestationExpiry
						}
						elseif([Helpers]::CheckMember($this.ControlSettings,"AttestationExpiryPeriodInDays"))
						{
							$controlsev = $this.ControlSettings.ControlSeverity.PSobject.Properties | Where-Object Value -eq $controlSeverity | Select-Object -First 1
							$controlSeverity = $controlsev.name									
							#Check if control severity has expiry period
							if([Helpers]::CheckMember($this.ControlSettings.AttestationExpiryPeriodInDays.ControlSeverity,$controlSeverity) )
							{
								$expiryInDays = $this.ControlSettings.AttestationExpiryPeriodInDays.ControlSeverity.$controlSeverity
							}
							#If control item and severity does not contain expiry period, assign default value
							else
							{
								$expiryInDays = $defaultAttestationExpiryInDays
							}
						}
						#Return -1 when expiry is not defined
						else
						{
							$expiryInDays = -1
						}
					}
				}				
			}
			else
			{				
				#Calculating the expiry in days for exempt controls
				
				$expiryDate = [DateTime]$controlState.State.ExpiryDate
				#Adding 1 explicitly to the days since the differnce below excludes the expiryDate and that also needs to be taken into account.
				$expiryInDays = ($expiryDate - $controlState.State.AttestedDate).Days + 1
			}								
		}
		catch
		{
			#if any exception occurs while getting/validating expiry period, return -1.
			$this.EvaluationError($_);
			$expiryInDays = -1
		}
		return $expiryInDays
	}

	[SVTEventContext[]] FetchStateOfAllControls()
    {
        [SVTEventContext[]] $resourceSecurityResult = @();
        if (-not $this.ValidateMaintenanceState()) {
			if($this.GetApplicableControls().Count -eq 0)
			{
				$this.PublishCustomMessage("No security controls match the input criteria specified", [MessageType]::Warning);
			}
			else
			{
				$this.EvaluationStarted();
				$resourceSecurityResult += $this.GetControlsStateResult();
				if(($resourceSecurityResult | Measure-Object).Count -gt 0)
				{
					$this.EvaluationCompleted($resourceSecurityResult);
				}
			}
        }
        return $resourceSecurityResult;
	}

	hidden [SVTEventContext[]] GetControlsStateResult()
    {
        [SVTEventContext[]] $automatedControlsResult = @();
		$this.DirtyResourceStates = @();
        try
        {
            $this.GetApplicableControls() |
            ForEach-Object {
                $eventContext = $this.FetchControlState($_);
				#filter controls if there is no state found
				if($eventContext)
				{
					$eventContext.ControlResults = $eventContext.ControlResults | Where-Object{$_.AttestationStatus -ne [AttestationStatus]::None}
					if($eventContext.ControlResults)
					{
						$automatedControlsResult += $eventContext;
					}
				}
            };
        }
        catch
        {
            $this.EvaluationError($_);
        }

        return $automatedControlsResult;
	}

	hidden [SVTEventContext] FetchControlState([ControlItem] $controlItem)
    {
		[SVTEventContext] $singleControlResult = $this.CreateSVTEventContextObject();
        $singleControlResult.ControlItem = $controlItem;

		$controlState = @();
		$controlStateValue = @();
		try
		{
			$resourceStates = $this.GetResourceState();
			if(($resourceStates | Measure-Object).Count -ne 0)
			{
				$controlStateValue += $resourceStates | Where-Object { $_.InternalId -eq $singleControlResult.ControlItem.Id };
				$controlStateValue | ForEach-Object {
					$currentControlStateValue = $_;
					if($null -ne $currentControlStateValue)
					{
						#assign expiry date
						$expiryIndays = $this.CalculateExpirationInDays($singleControlResult,$currentControlStateValue);
						if($expiryIndays -ne -1)
						{
							$currentControlStateValue.State.ExpiryDate = ($currentControlStateValue.State.AttestedDate.AddDays($expiryIndays)).ToString("MM/dd/yyyy");
						}
						$controlState += $currentControlStateValue;
					}
				}
			}
		}
		catch
		{
			$this.EvaluationError($_);
		}
		if(($controlState|Measure-Object).Count -gt 0)
		{
			$this.ControlStarted($singleControlResult);
			if($controlItem.Enabled -eq $false)
			{
				$this.ControlDisabled($singleControlResult);
			}
			else
			{
				$controlResult = $this.CreateControlResult($controlItem.FixControl);
				$singleControlResult.ControlResults += $controlResult;          
				$singleControlResult.ControlResults | 
				ForEach-Object {
					try
					{
						$currentItem = $_;

						if($controlState.Count -ne 0)
						{
							# Process the state if it's available
							$childResourceState = $controlState | Where-Object { $_.ChildResourceName -eq  $currentItem.ChildResourceName } | Select-Object -First 1;
							if($childResourceState)
							{
								$currentItem.StateManagement.AttestedStateData = $childResourceState.State;
								$currentItem.AttestationStatus = $childResourceState.AttestationStatus;
								$currentItem.ActualVerificationResult = $childResourceState.ActualVerificationResult;
								$currentItem.VerificationResult = [VerificationResult]::NotScanned
							}
						}
					}
					catch
					{
						$this.EvaluationError($_);
					}
				};

			}
			$this.ControlCompleted($singleControlResult);
		}

        return $singleControlResult;
	}

	hidden [void] GetManualSecurityStatusExt($arg)
	{
		$this.PostProcessData($arg);
	}

	hidden [void] RunControlExt($singleControlResult)
	{
		$this.PostProcessData($singleControlResult);
	}

	hidden [void] EvaluateAllControlsExt($resourceSecurityResult)
	{
		$this.PostEvaluationCompleted($resourceSecurityResult);
	}

	hidden [void] PostEvaluationCompleted([SVTEventContext[]] $ControlResults)
	{
	    # If ResourceType is Databricks, reverting security protocol 
		if([Helpers]::CheckMember($this.ResourceContext, "ResourceType") -and $this.ResourceContext.ResourceType -eq "Microsoft.Databricks/workspaces")
		{
		  [Net.ServicePointManager]::SecurityProtocol = $this.currentSecurityProtocol 
		}
		
		$this.UpdateControlStates($ControlResults);
	}
}