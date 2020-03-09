class AzSVTBase: SVTBase{

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

	<# TODO: Remove this block if new logic for policy complaince is working seemlessly
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
	#>

	hidden [void] CheckPolicyCompliance([ControlItem] $controlItem, [ControlResult] $controlResult)
	{
		try
		{
			$controlResult.PolicyState = [PolicyState]::new()
			$initiativeName = [ConfigurationManager]::GetAzSKConfigData().AzSKInitiativeName
			$securityCenterInitiativeName = [ConfigurationManager]::GetAzSKConfigData().AzSKSecurityCenterInitiativeName.Replace("{0}", $this.SubscriptionContext.SubscriptionId)
			$defnResourceId = $this.ResourceId + $controlItem.PolicyDefnResourceIdSuffix
			$policyState = Get-AzPolicyState -ResourceId $defnResourceId -Filter "((PolicyDefinitionId eq '/providers/microsoft.authorization/policydefinitions/$($controlItem.PolicyDefinitionGuid)') or (PolicyDefinitionId eq '/subscriptions/$($this.SubscriptionContext.SubscriptionId)/providers/microsoft.authorization/policydefinitions/$($controlItem.PolicyDefinitionGuid)')) and (PolicySetDefinitionName eq '$initiativeName' or PolicySetDefinitionName eq '$securityCenterInitiativeName')" -ErrorAction Stop
			if ($policyState)
			{
				$groupResultByComplianceState = $policyState | Group-Object -Property ComplianceState
				if (($groupResultByComplianceState | Measure-Object).Count -eq 1)
				{
					# Select first when multiple assignment are found for the same definition at subscription scope
					$policyState = $policyState | Select-Object -First 1
					$policyStateObject = $policyState | Select-Object ResourceId, PolicyAssignmentId, PolicyAssignmentScope, PolicyDefinitionAction, IsCompliant
					if ($policyState.IsCompliant)
					{
						$controlResult.PolicyState.PolicyVerificationResult = [PolicyVerificationResult]::Passed;
						$controlResult.PolicyState.DataObject = $policyStateObject;
					}
					else
					{
						$controlResult.PolicyState.PolicyVerificationResult = [PolicyVerificationResult]::Failed;
						$controlResult.PolicyState.DataObject = $policyStateObject;
					}

				}
				else
				{
					$policyStateObject = @()
					$policyState | ForEach-Object {
						$AssignmentDetails = "" | Select-Object PolicyAssignmentId, PolicyAssignmentScope, PolicyDefinitionAction, IsCompliant, Parameters
						$assignmentdetails.PolicyAssignmentId = $_.PolicyAssignmentId
						$assignmentdetails.PolicyAssignmentScope = $_.PolicyAssignmentScope
						$assignmentdetails.PolicyDefinitionAction = $_.PolicyDefinitionAction
						$assignmentdetails.IsCompliant = $_.IsCompliant

						$assignment = Get-AzPolicyAssignment -Id $($_.PolicyAssignmentId) -ErrorAction SilentlyContinue
						if ($assignment)
						{
							$assignmentdetails.Parameters = $assignment.parameters
						}
						
						$policyStateObject += $assignmentdetails
						
					}

					# Mark policy verification result as Verify if control is found to be both compliance and non-compliant
					$controlResult.PolicyState.PolicyVerificationResult = [PolicyVerificationResult]::Verify
					$controlResult.PolicyState.DataObject = $policyStateObject;
					
				}
			}
			else
			{
				#Check if definition is created in portal for this respective control
				$definition = Get-AzPolicyDefinition -Name $($controlItem.PolicyDefinitionGuid) -ErrorAction Stop
				# TODO: Move this to a common place, where it is called only once
				$initiative = @()
				$initiative += Get-AzPolicySetDefinition -Name $initiativeName -ErrorAction Stop
				$initiative += Get-AzPolicySetDefinition -Name $securityCenterInitiativeName -ErrorAction Stop
				# Definition is present, and compliance result not found
				if ($definition)
				{
					# Definition is present, and is added to the initiative
					if ($initiative.Properties.policyDefinitions.policyDefinitionId -contains $definition.PolicyDefinitionId)
					{
						# TODO: Move this to a common place, where it is called only once
						$assignment = Get-AzPolicyAssignment -PolicyDefinitionId $($initiative.PolicySetDefinitionId) -ErrorAction Stop
						# Assignment is present; compliance state not found for this resource
						if ($assignment)
						{
							$controlResult.PolicyState.PolicyVerificationResult = [PolicyVerificationResult]::NoResponse
						}
						# Assignment not found
						else
						{
							$controlResult.PolicyState.PolicyVerificationResult = [PolicyVerificationResult]::AssignmentNotFound
						}
					}
					# Definition is present, and is not added to the initiative
					else
					{
						$controlResult.PolicyState.PolicyVerificationResult = [PolicyVerificationResult]::DefinitionNotInInitiative
					}
					
				}
				# Definition is not present
				else
				{
					$controlResult.PolicyState.PolicyVerificationResult = [PolicyVerificationResult]::DefinitionNotFound
				}
			}
		}
		catch
		{
			$controlResult.PolicyState.PolicyVerificationResult = [PolicyVerificationResult]::Error
			if ([Helpers]::CheckMember($_, "Exception.Message"))
			{
				$ErrorDetails = "" | Select-Object OuterMessage
				$ErrorDetails.OuterMessage = $_.Exception.Message
 				$controlResult.PolicyState.DataObject = $ErrorDetails
			}
			else
			{
				$ErrorDetails = "" | Select-Object StackTrace
				$ErrorDetails.StackTrace = $_
 				$controlResult.PolicyState.DataObject = $ErrorDetails
			}
		}
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
			$resIdMessageString = "";
			if(-not [string]::IsNullOrWhiteSpace($extendedResourceName))
			{
				$resIdMessageString = "for nested resource [$extendedResourceName]";
			}

			$resourceGrpAlerts = @()
			$resourceAlerts = @()
			$resourceGrpAlerts += Get-AzMetricAlertRuleV2 -ResourceGroup $this.ResourceContext.ResourceGroupName -WarningAction SilentlyContinue
			$resourceAlerts += $resourceGrpAlerts |  Where-Object { ($_.Scopes -eq $this.ResourceId) -and ( $_.Enabled -eq '$true' ) }
			 
			$alertsConfiguration = @();
			$nonConfiguredMetrices = @();
			$misConfiguredMetrices = @();

			$metricSettings	|
			ForEach-Object {
				$currentMetric = $_;
				$matchedMetrices = @();
				$alertsConfiguration = @();
				$matchedMetrices += $resourceAlerts |
									Where-Object { ($_.Criteria.MetricName -eq $currentMetric.Condition.DataSource.MetricName) }

				if($matchedMetrices.Count -eq 0)
				{
					$nonConfiguredMetrices += $currentMetric;
				}
				else
				{
					$misConfigured = @();

					$matchedMetrices | ForEach-Object {
						if (($_.Criteria | Measure-Object).Count -gt 0 ) {

						   $condition = New-Object -TypeName PSObject

						   Add-Member -InputObject $condition -Name "OperatorProperty" -MemberType NoteProperty -Value $_.Criteria.OperatorProperty
						   Add-Member -InputObject $condition -Name "Threshold" -MemberType NoteProperty -Value $_.Criteria.Threshold
						   Add-Member -InputObject $condition -Name "TimeAggregation" -MemberType NoteProperty -Value $_.Criteria.TimeAggregation
						   Add-Member -InputObject $condition -Name "WindowSize" -MemberType NoteProperty -Value  $_.WindowSize.ToString()
						   $obj= [PSCustomObject]@{MetricName = $_.Criteria.MetricName}
						   Add-Member -InputObject $condition -Name "DataSource" -MemberType NoteProperty -Value $obj
								
						   $alert = New-Object -TypeName PSObject		
						   Add-Member -InputObject $alert -Name "Condition" -MemberType NoteProperty -Value $condition

						   $actions=@();
						   if([Helpers]::CheckMember($_,"Actions.actionGroupId"))
						   {
							   $_.Actions | ForEach-Object {
								   $actionGroupTemp = $_.actionGroupId.Split("/")
								   $actionGroup = Get-AzActionGroup -ResourceGroupName $actionGroupTemp[4] -Name $actionGroupTemp[-1] -WarningAction SilentlyContinue
								   if([Helpers]::CheckMember($actionGroup,"EmailReceivers.Status"))
								   {
									   if($actionGroup.EmailReceivers.Status -eq [Microsoft.Azure.Management.Monitor.Models.ReceiverStatus]::Enabled)
									   {
										   if([Helpers]::CheckMember($actionGroup,"EmailReceivers.EmailAddress"))
										   {
											$actions += $actionGroup
										   }
									   }
								   }	
							   }
						   }		
						   Add-Member -InputObject $alert -Name "Actions" -MemberType NoteProperty -Value $actions
						   Add-Member -InputObject $alert -Name "AlertName" -MemberType NoteProperty -Value $_.Name
						   Add-Member -InputObject $alert -Name "AlertType" -MemberType NoteProperty -Value $_.Type
   
						   if(($alert|Measure-Object).Count -gt 0)
							{
								$alertsConfiguration += $alert 
							}
					   }
				   }
				}

				if(($alertsConfiguration|Measure-Object).Count -gt 0)
				{
					$alertsConfiguration | ForEach-Object {
						if([Helpers]::CompareObject($currentMetric.Condition, $_.Condition))
						{
							$isActionConfigured = $false;
							if (($_.Actions | Measure-Object).Count -gt 0 ) {
								$isActionConfigured = $true;
							}
							if(-not $isActionConfigured)
							{
								$misConfigured += $_.Condition;
							}
						}
						else
						{
							$misConfigured += $_.Condition
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

}