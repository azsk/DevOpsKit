Set-StrictMode -Version Latest
class SVTBase: AzSKRoot
{
	hidden [string] $ResourceId = ""
    [ResourceContext] $ResourceContext = $null;
    hidden [SVTConfig] $SVTConfig
    hidden [PSObject] $ControlSettings

	hidden [ControlStateExtension] $ControlStateExt;
	
	hidden [ControlState[]] $ResourceState;
	hidden [ControlState[]] $DirtyResourceStates;

    hidden [ControlItem[]] $ApplicableControls = $null;
	hidden [ControlItem[]] $FeatureApplicableControls = $null;
	[string[]] $ChildResourceNames = $null;
	[System.Net.SecurityProtocolType] $currentSecurityProtocol;
	[string[]] $FilterTags = @();
	[string[]] $ExcludeTags = @();
	[string[]] $ControlIds = @();
	[bool] $GenerateFixScript = $false;
	[bool] $IncludeUserComments = $false;
	[string] $PartialScanIdentifier = [string]::Empty
	[ComplianceStateTableEntity[]] $ComplianceStateData = @();
	[PSObject[]] $ChildSvtObjects = @();
    SVTBase([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId)
    {		
		$this.CreateInstance($svtResource);
    }

	SVTBase([string] $subscriptionId):
        Base($subscriptionId)
    {
		$this.CreateInstance();
    }

	SVTBase([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName):
        Base($subscriptionId)
    {
		$this.CreateInstance([SVTResource]@{
			ResourceGroupName = $resourceGroupName;
            ResourceName = $resourceName;
		});
    }
	hidden [void] CreateInstance()
	{
		[Helpers]::AbstractClass($this, [SVTBase]);

        $this.LoadSvtConfig([SVTMapping]::SubscriptionMapping.JsonFileName);
	}

	hidden [void] CreateInstance([SVTResource] $svtResource)
	{
		[Helpers]::AbstractClass($this, [SVTBase]);

		if(-not $svtResource)
		{
			throw [System.ArgumentException] ("The argument 'svtResource' is null");
		}

		if([string]::IsNullOrEmpty($svtResource.ResourceGroupName))
		{
			throw [System.ArgumentException] ("The argument 'ResourceGroupName' is null or empty");
		}

		if([string]::IsNullOrEmpty($svtResource.ResourceName))
		{
			throw [System.ArgumentException] ("The argument 'ResourceName' is null or empty");
		}

		if(-not $svtResource.ResourceTypeMapping)
		{
			$svtResource.ResourceTypeMapping = [SVTMapping]::Mapping |
										Where-Object { $_.ClassName -eq $this.GetType().Name } |
										Select-Object -First 1
		}

        if (-not $svtResource.ResourceTypeMapping)
		{
            throw [System.ArgumentException] ("No ResourceTypeMapping found");
        }

        if ([string]::IsNullOrEmpty($svtResource.ResourceTypeMapping.JsonFileName))
		{
            throw [System.ArgumentException] ("JSON file name is null or empty");
        }

		$this.ResourceId = $svtResource.ResourceId;

        $this.LoadSvtConfig($svtResource.ResourceTypeMapping.JsonFileName);

        $this.ResourceContext = [ResourceContext]@{
            ResourceGroupName = $svtResource.ResourceGroupName;
            ResourceName = $svtResource.ResourceName;
            ResourceType = $svtResource.ResourceTypeMapping.ResourceType;
            ResourceTypeName = $svtResource.ResourceTypeMapping.ResourceTypeName;
        };
		$this.ResourceContext.ResourceId = $this.GetResourceId();
	}

    hidden [void] LoadSvtConfig([string] $controlsJsonFileName)
    {
        $this.ControlSettings = $this.LoadServerConfigFile("ControlSettings.json");

        if (-not $this.SVTConfig) {
            $this.SVTConfig =  [ConfigurationManager]::GetSVTConfig($controlsJsonFileName);
			
            $this.SVTConfig.Controls | Foreach-Object {

                $_.Description = $global:ExecutionContext.InvokeCommand.ExpandString($_.Description)
                $_.Recommendation = $global:ExecutionContext.InvokeCommand.ExpandString($_.Recommendation)
				if(-not [string]::IsNullOrEmpty($_.MethodName))
				{
					$_.MethodName = $_.MethodName.Trim();
				}
				if($this.CheckBaselineControl($_.ControlID))
				{
					$_.IsBaselineControl = $true
				}
            }
        }
    }

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

	hidden [string] GetResourceId()
    {
		if ([string]::IsNullOrEmpty($this.ResourceId))
		{
			if($this.ResourceContext)
			{
           		$resource = Get-AzureRmResource -Name $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName

				if($resource)
				{
					$this.ResourceId = $resource.ResourceId;
				}
				else
				{
					throw [SuppressedException] "Unable to find the Azure resource - [ResourceType: $($this.ResourceContext.ResourceType)] [ResourceGroupName: $($this.ResourceContext.ResourceGroupName)] [ResourceName: $($this.ResourceContext.ResourceName)]"
				}
			}
			else
			{
				$this.ResourceId = $this.SubscriptionContext.Scope;
			}
		}

		return $this.ResourceId;
    }

    [bool] ValidateMaintenanceState()
    {
        if ($this.SVTConfig.IsMaintenanceMode) {
            $this.PublishCustomMessage(([ConfigurationManager]::GetAzSKConfigData().MaintenanceMessage -f $this.SVTConfig.FeatureName), [MessageType]::Warning);
        }
        return $this.SVTConfig.IsMaintenanceMode;
    }

    hidden [ControlResult] CreateControlResult([string] $childResourceName, [VerificationResult] $verificationResult)
    {
        [ControlResult] $control = [ControlResult]@{
            VerificationResult = $verificationResult;
        };

        if(-not [string]::IsNullOrEmpty($childResourceName))
        {
            $control.ChildResourceName = $childResourceName;
        }

		[SessionContext] $sc = [SessionContext]::new();
		$sc.IsLatestPSModule = $this.RunningLatestPSModule;
		$control.CurrentSessionContext = $sc;

        return $control;
    }

    [ControlResult] CreateControlResult()
    {
        return $this.CreateControlResult("", [VerificationResult]::Manual);
    }

	hidden [ControlResult] CreateControlResult([FixControl] $fixControl)
    {
        $control = $this.CreateControlResult();
		if($this.GenerateFixScript -and $fixControl -and $fixControl.Parameters -and ($fixControl.Parameters | Get-Member -MemberType Properties | Measure-Object).Count -ne 0)
		{
			$control.FixControlParameters = $fixControl.Parameters | Select-Object -Property *;
		}
		return $control;
    }

	[ControlResult] CreateControlResult([string] $childResourceName)
    {
        return $this.CreateControlResult($childResourceName, [VerificationResult]::Manual);
    }

	[ControlResult] CreateChildControlResult([string] $childResourceName, [ControlResult] $controlResult)
    {
        $control = $this.CreateControlResult($childResourceName, [VerificationResult]::Manual);
		if($controlResult.FixControlParameters -and ($controlResult.FixControlParameters | Get-Member -MemberType Properties | Measure-Object).Count -ne 0)
		{
			$control.FixControlParameters = $controlResult.FixControlParameters | Select-Object -Property *;
		}
		return $control;
    }

	hidden [SVTEventContext] CreateSVTEventContextObject()
	{
		return [SVTEventContext]@{
			FeatureName = $this.SVTConfig.FeatureName;
			Metadata = [Metadata]@{
				Reference = $this.SVTConfig.Reference;
			};

            SubscriptionContext = $this.SubscriptionContext;
            ResourceContext = $this.ResourceContext;
			PartialScanIdentifier = $this.PartialScanIdentifier
			
        };
	}

    hidden [SVTEventContext] CreateErrorEventContext([System.Management.Automation.ErrorRecord] $exception)
    {
        [SVTEventContext] $arg = $this.CreateSVTEventContextObject();
        $arg.ExceptionMessage = $exception;

        return $arg;
    }

    hidden [void] ControlStarted([SVTEventContext] $arg)
    {
        $this.PublishEvent([SVTEvent]::ControlStarted, $arg);
    }

    hidden [void] ControlDisabled([SVTEventContext] $arg)
    {
        $this.PublishEvent([SVTEvent]::ControlDisabled, $arg);
    }

    hidden [void] ControlCompleted([SVTEventContext] $arg)
    {
        $this.PublishEvent([SVTEvent]::ControlCompleted, $arg);
    }

    hidden [void] ControlError([ControlItem] $controlItem, [System.Management.Automation.ErrorRecord] $exception)
    {
        $arg = $this.CreateErrorEventContext($exception);
        $arg.ControlItem = $controlItem;
        $this.PublishEvent([SVTEvent]::ControlError, $arg);
    }

    hidden [void] EvaluationCompleted([SVTEventContext[]] $arguments)
    {
        $this.PublishEvent([SVTEvent]::EvaluationCompleted, $arguments);
    }

    hidden [void] EvaluationStarted()
    {
        $this.PublishEvent([SVTEvent]::EvaluationStarted, $this.CreateSVTEventContextObject());
	}
	
    hidden [void] EvaluationError([System.Management.Automation.ErrorRecord] $exception)
    {
        $this.PublishEvent([SVTEvent]::EvaluationError, $this.CreateErrorEventContext($exception));
    }

    [SVTEventContext[]] EvaluateAllControls()
    {
        [SVTEventContext[]] $resourceSecurityResult = @();
        if (-not $this.ValidateMaintenanceState()) {
			if($this.GetApplicableControls().Count -eq 0)
			{
				if($this.ResourceContext)
				{
					$this.PublishCustomMessage("No controls have been found to evaluate for Resource [$($this.ResourceContext.ResourceName)]", [MessageType]::Warning);
					$this.PublishCustomMessage("$([Constants]::SingleDashLine)");
				}
				else
				{
					$this.PublishCustomMessage("No controls have been found to evaluate for Subscription", [MessageType]::Warning);
				}
			}
			else
			{
				$this.PostTelemetry();
				$this.EvaluationStarted();	
				$resourceSecurityResult += $this.GetAutomatedSecurityStatus();
				$resourceSecurityResult += $this.GetManualSecurityStatus();			
				$this.PostEvaluationCompleted($resourceSecurityResult);
				$this.EvaluationCompleted($resourceSecurityResult);
			}
        }
        return $resourceSecurityResult;
	}

	

	[SVTEventContext[]] ComputeApplicableControlsWithContext()
    {
        [SVTEventContext[]] $contexts = @();
        if (-not $this.ValidateMaintenanceState()) {
			$controls = $this.GetApplicableControls();
			if($controls.Count -gt 0)
			{
				foreach($control in $controls) {
					[SVTEventContext] $singleControlResult = $this.CreateSVTEventContextObject();
					$singleControlResult.ControlItem = $control;
					$contexts += $singleControlResult;
				}
			}
        }
        return $contexts;
	}
	[void] PostTelemetry()
	{
	    # Setting the protocol for databricks
		if([Helpers]::CheckMember($this.ResourceContext, "ResourceType") -and $this.ResourceContext.ResourceType -eq "Microsoft.Databricks/workspaces")
		{
			$this.currentSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
			[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		}
		$this.PostFeatureControlTelemetry()
	}
	[void] PostFeatureControlTelemetry()
	{
		#todo add check for latest module version
		if($this.RunningLatestPSModule -and ($this.FeatureApplicableControls | Measure-Object).Count -gt 0)
		{
			[CustomData] $customData = [CustomData]::new();
			$customData.Name = "FeatureControlTelemetry";
			$ResourceObject = "" | Select ResourceContext, Controls, ChildResourceNames;
			$ResourceObject.ResourceContext = $this.ResourceContext;
			$ResourceObject.Controls = $this.FeatureApplicableControls;
			$ResourceObject.ChildResourceNames = $this.ChildResourceNames;
			$customData.Value = $ResourceObject;
			$this.PublishCustomData($customData);		
		}
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
				$this.EvaluationCompleted($resourceSecurityResult);
			}
        }
        return $resourceSecurityResult;
	}

	[ControlItem[]] ApplyServiceFilters([ControlItem[]] $controls)
	{
		return $controls;
	}

	hidden [ControlItem[]] GetApplicableControls()
	{
		#Lazy load the list of the applicable controls
		if($null -eq $this.ApplicableControls)
		{
			$this.ApplicableControls = @();
			$this.FeatureApplicableControls = @();
			$filterControlsById = @();
			$filteredControls = @();

			#Apply service filters based on default set of controls
			$this.FeatureApplicableControls += $this.ApplyServiceFilters($this.SVTConfig.Controls);

			if($this.ControlIds.Count -ne 0)
			{
				$filterControlsById += $this.FeatureApplicableControls | Where-Object { $this.ControlIds -Contains $_.ControlId };
			}
			else
			{
				$filterControlsById += $this.FeatureApplicableControls
			}

			if(($this.FilterTags | Measure-Object).Count -ne 0 -or ($this.ExcludeTags | Measure-Object).Count -ne 0)
			{
				if(($filterControlsById | Measure-Object).Count -gt 0){
				$filterControlsById | ForEach-Object {
					Set-Variable -Name control -Value $_ -Scope Local
					Set-Variable -Name filterMatch -Value $false -Scope Local
					Set-Variable -Name excludeMatch -Value $false -Scope Local
					$control.Tags | ForEach-Object {
						Set-Variable -Name cTag -Value $_ -Scope Local

						if(($this.FilterTags | Measure-Object).Count -ne 0 `
							-and ($this.FilterTags | Where-Object { $_ -like $cTag} | Measure-Object).Count -ne 0)
						{
							$filterMatch = $true
						}
						elseif(($this.FilterTags | Measure-Object).Count -eq 0)
						{
							$filterMatch = $true
						}
						if(($this.ExcludeTags | Measure-Object).Count -ne 0 `
							-and ($this.ExcludeTags | Where-Object { $_ -like $cTag} | Measure-Object).Count -ne 0)
						{
							$excludeMatch = $true
						}
					}

					if(($filterMatch  -and -not $excludeMatch) `
							-or (-not $filterMatch -and -not $excludeMatch))
					{
						$filteredControls += $control
					}
				}
				}
			}
			else
			{
				$filteredControls += $filterControlsById;
			}
			$this.ApplicableControls = $filteredControls;
			#this filtering has been done as the first step it self;
			#$this.ApplicableControls += $this.ApplyServiceFilters($filteredControls);
			
		}
		return $this.ApplicableControls;
	}

    hidden [SVTEventContext[]] GetManualSecurityStatus()
    {
        [SVTEventContext[]] $manualControlsResult = @();
        try
        {
            $this.GetApplicableControls() | Where-Object { $_.Automated -eq "No" -and $_.Enabled -eq $true } |
            ForEach-Object {
                $controlItem = $_;
				[SVTEventContext] $arg = $this.CreateSVTEventContextObject();

				$arg.ControlItem = $controlItem;
				[ControlResult] $control = [ControlResult]@{
					VerificationResult = [VerificationResult]::Manual;
				};

				[SessionContext] $sc = [SessionContext]::new();
				$sc.IsLatestPSModule = $this.RunningLatestPSModule;
				$control.CurrentSessionContext = $sc;

				$arg.ControlResults += $control
				
				$this.PostProcessData($arg);

                $manualControlsResult += $arg;
            }
        }
        catch
        {
            $this.EvaluationError($_);
        }

        return $manualControlsResult;
    }

    hidden [SVTEventContext[]] GetAutomatedSecurityStatus()
    {
        [SVTEventContext[]] $automatedControlsResult = @();
		$this.DirtyResourceStates = @();
        try
        {
            $this.GetApplicableControls() | Where-Object { $_.Automated -ne "No" -and (-not [string]::IsNullOrEmpty($_.MethodName)) } |
            ForEach-Object {
				$eventContext = $this.RunControl($_);
				if($null -ne $eventContext -and $eventcontext.ControlResults.Length -gt 0)
				{
					$automatedControlsResult += $eventContext;
				}
            };
        }
        catch
        {
            $this.EvaluationError($_);
        }

        return $automatedControlsResult;
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
    hidden [SVTEventContext] RunControl([ControlItem] $controlItem)
    {
		[SVTEventContext] $singleControlResult = $this.CreateSVTEventContextObject();
        $singleControlResult.ControlItem = $controlItem;

        $this.ControlStarted($singleControlResult);
		if($controlItem.Enabled -eq $false)
        {
            $this.ControlDisabled($singleControlResult);
        }
        else
        {
			$azskScanResult = $this.CreateControlResult($controlItem.FixControl);
            try
            {
                $methodName = $controlItem.MethodName;
				#$this.CurrentControlItem = $controlItem;
				$singleControlResult.ControlResults += $this.$methodName($azskScanResult);
            }
            catch
            {
				$azskScanResult.VerificationResult = [VerificationResult]::Error				
				$azskScanResult.AddError($_);
				$singleControlResult.ControlResults += $azskScanResult
                $this.ControlError($controlItem, $_);
			}
			$this.PostProcessData($singleControlResult);

			# Check for the control which requires elevated permission to modify 'Recommendation' so that user can know it is actually automated if they have the right permission
			if($singleControlResult.ControlItem.Automated -eq "Yes")
			{
				$singleControlResult.ControlResults |
					ForEach-Object {
					$currentItem = $_;
					if($_.VerificationResult -eq [VerificationResult]::Manual -and $singleControlResult.ControlItem.Tags.Contains([Constants]::OwnerAccessTagName))
					{
						$singleControlResult.ControlItem.Recommendation = [Constants]::RequireOwnerPermMessage + $singleControlResult.ControlItem.Recommendation
					}
				}
			}
        }

		$this.ControlCompleted($singleControlResult);

        return $singleControlResult;
    }
	
	# Policy compliance methods begin
	hidden [ControlResult] ComputeFinalScanResult([ControlResult] $azskScanResult, [ControlResult] $policyScanResult)
	{
		if($policyScanResult.VerificationResult -ne [VerificationResult]::Failed -and $azskScanResult.VerificationResult -ne [VerificationResult]::Passed)
		{
			return $azskScanResult
		}
		else
		{
			return $policyScanResult;
		}
	}
	hidden [ControlResult] CheckPolicyCompliance([ControlItem] $controlItem, [ControlResult] $controlResult)
	{
		$initiativeName = [ConfigurationManager]::GetAzSKConfigData().AzSKInitiativeName
		$defnResourceId = $this.GetResourceId() + $controlItem.PolicyDefnResourceIdSuffix
		$policyState = Get-AzureRmPolicyState -ResourceId $defnResourceId -Filter "PolicyDefinitionId eq '/providers/microsoft.authorization/policydefinitions/$($controlItem.PolicyDefinitionGuid)' and PolicySetDefinitionName eq '$initiativeName'"
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
						$expiryIndays=$this.CalculateExpirationInDays($singleControlResult,$currentControlStateValue);
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
	hidden [void] PostEvaluationCompleted([SVTEventContext[]] $ControlResults)
	{
	    # If ResourceType is Databricks, reverting security protocol 
		if([Helpers]::CheckMember($this.ResourceContext, "ResourceType") -and $this.ResourceContext.ResourceType -eq "Microsoft.Databricks/workspaces")
		{
		  [Net.ServicePointManager]::SecurityProtocol = $this.currentSecurityProtocol 
		}
		$this.UpdateControlStates($ControlResults);
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

	hidden [void] PostProcessData([SVTEventContext] $eventContext)
	{
		$tempHasRequiredAccess = $true;
		$controlState = @();
		$controlStateValue = @();
		try
		{
			# Get policy compliance if org-level flag is enabled and policy is found 
			#TODO: set flag in a variable once and reuse it
			
			if([ConfigurationManager]::GetAzSKConfigData().EnableAzurePolicyBasedScan -eq $true)
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
										$currentStateDataObject = [Helpers]::ConvertToJsonCustom($currentItem.StateManagement.CurrentStateData.DataObject) | ConvertFrom-Json

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

	hidden [ControlState[]] GetResourceState()
	{
		if($null -eq $this.ResourceState)
		{
			$this.ResourceState = @();
			if($this.ControlStateExt -and $this.ControlStateExt.HasControlStateReadAccessPermissions())
			{
				$resourceStates = $this.ControlStateExt.GetControlState($this.GetResourceId())
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

	#Function to validate attestation data expiry validation
	hidden [bool] IsStateActive([SVTEventContext] $eventcontext,[ControlState] $controlState)
	{
		try
		{
			$expiryIndays = $this.CalculateExpirationInDays([SVTEventContext] $eventcontext,[ControlState] $controlState);
			#Validate if expiry period is passed
			if($expiryIndays -ne -1 -and $controlState.State.AttestedDate.AddDays($expiryIndays) -lt [DateTime]::UtcNow)
			{
				return $false
			}
			else
			{
			    $controlState.State.ExpiryDate = ($controlState.State.AttestedDate.AddDays($expiryIndays)).ToString("MM/dd/yyyy");
				return $true
			}
		}
		catch{
			#if any exception occurs while getting/validating expiry period, return true.
			$this.EvaluationError($_);
			return $true
		}
	}

	hidden [int] CalculateExpirationInDays([SVTEventContext] $eventcontext,[ControlState] $controlState)
	{
		try
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
		catch{
			#if any exception occurs while getting/validating expiry period, return -1.
			$this.EvaluationError($_);
			$expiryInDays = -1
		}
		return $expiryInDays
	}

	hidden [ControlResult] CheckDiagnosticsSettings([ControlResult] $controlResult)
	{
		$diagnostics = $Null
		try
		{
			$diagnostics = Get-AzureRmDiagnosticSetting -ResourceId $this.GetResourceId() -ErrorAction Stop -WarningAction SilentlyContinue
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
											$_.RetentionPolicy.Days -eq $this.ControlSettings.Diagnostics_RetentionPeriod_Min))};

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
		$accessList = [RoleAssignmentHelper]::GetAzSKRoleAssignmentByScope($this.GetResourceId(), $false, $true);

		return $this.CheckRBACAccess($controlResult, $accessList)
	}

	hidden [ControlResult] CheckRBACAccess([ControlResult] $controlResult, [PSObject] $accessList)
	{
		$resourceAccessList = $accessList | Where-Object { $_.Scope -eq $this.GetResourceId() };

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

        $inheritedAccessList = $accessList | Where-Object { $_.Scope -ne $this.GetResourceId() };

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
			$resId = $this.GetResourceId() + $extendedResourceName;
			$resIdMessageString = "";
			if(-not [string]::IsNullOrWhiteSpace($extendedResourceName))
			{
				$resIdMessageString = "for nested resource [$extendedResourceName]";
			}

			$resourceAlerts = (Get-AzureRmAlertRule -ResourceGroup $this.ResourceContext.ResourceGroupName -WarningAction SilentlyContinue) |
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

	hidden AddResourceMetadata([PSObject] $metadataObj)
	{

		[hashtable] $resourceMetadata = New-Object -TypeName Hashtable;
		$metadataObj.psobject.properties |
			ForEach-Object {
				$resourceMetadata.Add($_.name, $_.value)
			}

		$this.ResourceContext.ResourceMetadata = $resourceMetadata

	}


	hidden [SVTResource] CreateSVTResource([string] $ConnectionResourceId,[string] $ResourceGroupName, [string] $ConnectionResourceName, [string] $ResourceType, [string] $Location, [string] $MappingName)
	{
		$svtResource = [SVTResource]::new();
		$svtResource.ResourceId = $ConnectionResourceId; 
		$svtResource.ResourceGroupName = $ResourceGroupName;
		$svtResource.ResourceName = $ConnectionResourceName
		$svtResource.ResourceType = $ResourceType; # 
		$svtResource.Location = $Location;
		$svtResource.ResourceTypeMapping = ([SVTMapping]::Mapping |
						Where-Object { $_.ResourceTypeName -eq $MappingName } |
						Select-Object -First 1);

		return $svtResource;
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


	[int] hidden CalculateGraceInDays([SVTEventContext] $context)
	{
		
		$controlResult=$context.ControlResults;
		$computedGraceDays=15;
		$ControlBasedGraceExpiryInDays=0;
		$currentControlItem=$context.controlItem;
		$controlSeverity=$currentControlItem.ControlSeverity;
		if([Helpers]::CheckMember($this.ControlSettings,"NewControlGracePeriodInDays"))
		{
			$computedGraceDays=$this.ControlSettings.NewControlGracePeriodInDays.ControlSeverity.$ControlSeverity;
		}
		if($null -ne $currentControlItem.GraceExpiryDate)
		{
			if($currentControlItem.GraceExpiryDate -gt [DateTime]::UtcNow )
			{
				$ControlBasedGraceExpiryInDays=$currentControlItem.GraceExpiryDate.Subtract($controlResult.FirstScannedOn).Days
				if($ControlBasedGraceExpiryInDays -gt $computedGraceDays)
				{
					$computedGraceDays = $ControlBasedGraceExpiryInDays
				}
			}			
		}

	  return $computedGraceDays;
	}	
}
