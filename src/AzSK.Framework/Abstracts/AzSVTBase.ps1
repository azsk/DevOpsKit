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

			$resourceAlerts = (Get-AzAlertRule -ResourceGroup $this.ResourceContext.ResourceGroupName -WarningAction SilentlyContinue) |
								Where-Object { $_.Condition -and $_.Condition.DataSource } |
								Where-Object { $_.Condition.DataSource.ResourceUri -eq $resId };

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

}