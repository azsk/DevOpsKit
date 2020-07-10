<#
.Description
# SVTBase class for all service classes. 
# Provides functionality to create context object for resources, load controls for resource,
#>
Set-StrictMode -Version Latest
class SVTBase: AzSKRoot
{
	#Region: Properties
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
	#User input parameters for controls
	[string[]] $FilterTags = @();
	[string[]] $ExcludeTags = @();
	[string[]] $ControlIds = @();
	[string[]] $Severity = @();
	[string[]] $ExcludeControlIds = @();
	[hashtable] $ResourceTags = @{}
	[bool] $GenerateFixScript = $false;

	[bool] $IncludeUserComments = $false;
	[string] $PartialScanIdentifier = [string]::Empty
	[ComplianceStateTableEntity[]] $ComplianceStateData = @();
	[PSObject[]] $ChildSvtObjects = @();
	#EndRegion

	SVTBase([string] $subscriptionId):
        Base($subscriptionId)
    {		

	}
	SVTBase([string] $subscriptionId, [SVTResource] $svtResource):
	Base($subscriptionId, [SVTResource] $svtResource)
	{		
		$this.CreateInstance($svtResource);
	}


	#Create instance for resource scan
	hidden [void] CreateInstance([SVTResource] $svtResource)
	{
		[Helpers]::AbstractClass($this, [SVTBase]);

		#Region: validation for resource object 
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
		#EndRegion

		#<TODO Framework: ResourceTypeMapping is already part of svtResource and populated from Resolver. Below validation is redudant.
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
			ResourceId = $svtResource.ResourceId
			ResourceDetails = $svtResource.ResourceDetails
		};
		
		#<TODO Framework: Fetch resource group details from resolver itself>
		$this.ResourceContext.ResourceGroupTags = $this.ResourceTags;

	}

   	hidden [void] LoadSvtConfig([string] $controlsJsonFileName)
    {
        $this.ControlSettings = $this.LoadServerConfigFile("ControlSettings.json");

        if (-not $this.SVTConfig) {
            $this.SVTConfig =  [ConfigurationManager]::GetSVTConfig($controlsJsonFileName);
			
            $this.SVTConfig.Controls | Foreach-Object {

				#Expand description and recommendation string if any dynamic values defined field using control settings
                $_.Description = $global:ExecutionContext.InvokeCommand.ExpandString($_.Description)
                $_.Recommendation = $global:ExecutionContext.InvokeCommand.ExpandString($_.Recommendation)
				
				$ControlSeverity = $_.ControlSeverity
				#Check if ControlSeverity is customized/overridden using controlsettings configurations
                if([Helpers]::CheckMember($this.ControlSettings,"ControlSeverity.$ControlSeverity"))
                {
                    $_.ControlSeverity = $this.ControlSettings.ControlSeverity.$ControlSeverity
                }

				#<TODO Framework: Do we really need to trim method name as it is defined by developer>
				if(-not [string]::IsNullOrEmpty($_.MethodName))
				{
					$_.MethodName = $_.MethodName.Trim();
				}

				#Check if 
				if($this.CheckBaselineControl($_.ControlID))
				{
					$_.IsBaselineControl = $true
				}
				#AddPreviewBaselineFlag
				if($this.CheckPreviewBaselineControl($_.ControlID))
				{
					$_.IsPreviewBaselineControl = $true
				}
            }
        }
    }
	#stub to be used when Baseline configuration exists 
	hidden [bool] CheckBaselineControl($controlId)
	{
		return $false
	}
	#stub to be used when PreviewBaseline configuration exists 
	hidden [bool] CheckPreviewBaselineControl($controlId)
	{
		return $false
	}


	#Check if service is under mentainance and display maintenance warning message
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
			$ControlsApplicableForScan = @();
			$ControlsApplicableForScan = $this.GetApplicableControls();
			if($ControlsApplicableForScan.Count -eq 0)
			{
				if($this.ResourceContext)
				{
					$this.PublishCustomMessage("No controls have been found to evaluate for Resource [$($this.ResourceContext.ResourceName)]", [MessageType]::Warning);
					$this.PublishCustomMessage("$([Constants]::SingleDashLine)");
					# Marking resource scan completed status in ResourceScanTracker file if no controls found to be applicable
					# This will avoid scanning resource repetitively in case of CA and unblock further scan 
					if($this.invocationContext.BoundParameters["UsePartialCommits"])
					{
						[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
						$partialScanMngr.UpdateResourceStatus( $this.ResourceContext.ResourceId,"COMP");
					}					
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
				$EnabledApplicableControlForScan = @();	
				$EnabledApplicableControlForScan = $ControlsApplicableForScan | Where-Object {$_.Enabled -eq $true};
				# Marking resource scan completed status in ResourceScanTracker file if no controls found to be Enabled
				# This scenario has been observed in case of Org Policy overwriting Control jsons
				# This will avoid scanning resource repetitively in case of CA and unblock further scan  
				if($this.invocationContext.BoundParameters["UsePartialCommits"] -and $EnabledApplicableControlForScan -eq $null)
				{
					[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
					$partialScanMngr.UpdateResourceStatus( $this.ResourceContext.ResourceId,"COMP");
				}	
			}
        }
        return $resourceSecurityResult;
	}

	[SVTEventContext[]] RescanAndPostAttestationData()
    {
		[SVTEventContext[]] $resourceScanResult = @();
		[SVTEventContext[]] $stateResult = @();
		[ControlItem[]] $controlsToBeEvaluated = @();

		$this.PostTelemetry();
		#Publish event to display host message to indicate start of resource scan 
		$this.EvaluationStarted();	
		#Fetch attested controls list from Blob
		$stateResult = $this.GetControlsStateResult()
		If (($stateResult | Measure-Object).Count -gt 0 )
		{
			#Get controls list which were attested in last 24 hours
			$attestedControlsinBlob = $stateResult | Where-Object {$_.ControlResults.StateManagement.AttestedStateData.AttestedDate -gt ((Get-Date).AddDays(-1))}
			if (($attestedControlsinBlob | Measure-Object).Count -gt 0 )
			{
				$attestedControlsinBlob | ForEach-Object {
					$controlsToBeEvaluated += $_.ControlItem
				};
				$this.ApplicableControls = @($controlsToBeEvaluated);
				$resourceScanResult += $this.GetAutomatedSecurityStatus();
				$resourceScanResult += $this.GetManualSecurityStatus();

				$this.PostEvaluationCompleted($resourceScanResult);
				$this.EvaluationCompleted($resourceScanResult);
			}
			else {
				Write-Host "No attested control found.`n$([Constants]::SingleDashLine)" 
			}
		}
		else {
			Write-Host "No attested control found.`n$([Constants]::SingleDashLine)" 
		}
         return $resourceScanResult;
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
				if(($resourceSecurityResult | Measure-Object).Count -gt 0)
				{
					$this.EvaluationCompleted($resourceSecurityResult);
				}
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

			if($this.ExcludeControlIds.Count -ne 0)
			{
				$filterControlsById = $filterControlsById | Where-Object { $this.ExcludeControlIds -notcontains $_.ControlId };
			}

			#Filter controls based on filterstags and excludetags
			$filterTagsCount = ($this.FilterTags | Measure-Object).Count
            $excludeTagsCount = ($this.ExcludeTags | Measure-Object).Count

			#filters controls based on Severity
			if($this.Severity.Count -ne 0 -and ($filterControlsById | Measure-Object).Count -gt 0)
			{
				$filterControlsById = $filterControlsById | Where-Object {$_.ControlSeverity -in $this.Severity };				
			}

			
            $unfilteredControlsCount = ($filterControlsById | Measure-Object).Count

			if($unfilteredControlsCount -gt 0) #If we have any controls at this point...
            {
                #If FilterTags are specified, limit the candidate set to matching controls
                if ($filterTagsCount -gt 0)
                {
                    #Look at each candidate control's tags and see if there's a match in FilterTags
                    $filterControlsById | ForEach-Object {
                        Set-Variable -Name control -Value $_ -Scope Local
                        Set-Variable -Name filterMatch -Value $false -Scope Local
                        
						$filterMatch = $false
												
						$control.Tags | ForEach-Object {
													Set-Variable -Name cTag -Value $_ -Scope Local

													if( ($this.FilterTags | Where-Object { $_ -like $cTag} | Measure-Object).Count -ne 0)
													{
														$filterMatch = $true
													}
												}

                        #Add if this control has a tag that matches FilterTags 
                        if ($filterMatch) 
                        {
                            $filteredControls += $control
                        }   
                    }                     
                }
                else #No FilterTags specified, so all controls qualify
                {
                    $filteredControls = $filterControlsById
                }

                #Note: Candidate controls list is now in $filteredControls...we will use that to calculate $filteredControlsFinal
                $filteredControlsFinal = @()
                if ($excludeTagsCount -eq 0)
                {
                    #If exclude tags are not specified, then not much to do.
                    $filteredControlsFinal = $filteredControls
                }
                else 
                {
                    #ExludeTags _are_ specified, we need to check if candidate set has to be reduced...
                    
                    #Look at each candidate control's tags and see if there's a match in ExcludeTags
                    $filteredControls | ForEach-Object {
                        Set-Variable -Name control -Value $_ -Scope Local
                        Set-Variable -Name excludeMatch -Value $false -Scope Local
                        $excludeMatch = $false

                        $control.Tags | ForEach-Object {
                              Set-Variable -Name cTag -Value $_ -Scope Local

                              if(($this.ExcludeTags | Where-Object { $_ -like $cTag} | Measure-Object).Count -ne 0)
                              {
                                    $excludeMatch = $true
                              }
                        }
                        
                        #Add to final list if this control *does-not* have a tag that matches ExcludeTags
                        if (-not $excludeMatch) 
                        {
                            $filteredControlsFinal += $control
                        }   
					}
					$filteredControls = $filteredControlsFinal                
                } 
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
			if (!(Get-Variable AttestationValue -Scope Global))
			{
				$this.ControlStarted($singleControlResult);
			}
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
			
			if([FeatureFlightingManager]::GetFeatureStatus("EnableAzurePolicyBasedScan",$($this.SubscriptionContext.SubscriptionId)) -eq $true)
			{
				if(-not [string]::IsNullOrWhiteSpace($eventContext.ControlItem.PolicyDefinitionGuid))
				{
					
					#update with policy compliance state result; This result will be captured in AI telemetry data
					#todo: currently excluding child controls
					$policyScanResult = $this.CheckPolicyCompliance($eventContext.ControlItem, $eventContext.ControlResults[0]);

					#TODO: Remove this block if new logic of policy compliance check works as expected
					# This block can be reused if we want to replace control scanned result with policy complaince state
					<#
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
					#>				
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


								#region: Prevent attestation drift due to dev changes
								if ( ([FeatureFlightingManager]::GetFeatureStatus("PreventAttestationStateDrift", $($this.SubscriptionContext.SubscriptionId))))
								{
									# Check if drift is expected
									if ($eventContext.ControlItem.IsAttestationDriftExpected -eq $true)
									{
										if ($eventcontext.controlItem.OnAttestationDrift -and `
											(-not [String]::IsNullOrEmpty($eventcontext.controlItem.OnAttestationDrift.ApplyToVersionsUpto)))
										{							
											# Check if attested version is less than or equal to the last stable version (as specified in the control json file)
											if ([System.Version] $childResourceState.Version -le [System.Version] $eventcontext.controlItem.OnAttestationDrift.ApplyToVersionsUpto)
											{	
												# Check action to be taken on drift
												# Repect attestation if attested with older version
												if (($eventcontext.controlItem.OnAttestationDrift.ActionOnAttestationDrift -eq [ActionOnAttestationDrift]::RespectExistingAttestationExpiryPeriod) -or `
													($eventcontext.controlItem.OnAttestationDrift.ActionOnAttestationDrift -eq [ActionOnAttestationDrift]::OverrideAttestationExpiryPeriod))
												{
													$this.ModifyControlResult($currentItem, $childResourceState)
												}
												# Filter specific properties from state data object and compare result
												elseif ($eventcontext.controlItem.OnAttestationDrift.ActionOnAttestationDrift -eq [ActionOnAttestationDrift]::CheckOnlySelectPropertiesInDataObject)
												{
													#Filter select properties from dataobject
													if ($childResourceState.State -and $childResourceState.State.DataObject -and $eventContext.ControlItem.DataObjectProperties)
													{
														$childResourceState.State.DataObject = [Helpers]::SelectMembers($childResourceState.State.DataObject, $eventContext.ControlItem.DataObjectProperties);
													}

													# Compare dataobject property of State
													if ($null -ne $childResourceState.State.DataObject)
													{
														if ($currentItem.StateManagement.CurrentStateData -and $null -ne $currentItem.StateManagement.CurrentStateData.DataObject)
														{
															$currentStateDataObject = [JsonHelper]::ConvertToJsonCustom($currentItem.StateManagement.CurrentStateData.DataObject) | ConvertFrom-Json

															try
															{
																# Objects match, change result based on attestation status
																if ($eventContext.ControlItem.AttestComparisionType -and $eventContext.ControlItem.AttestComparisionType -eq [ComparisionType]::NumLesserOrEqual)
																{
																	if ([Helpers]::CompareObject($childResourceState.State.DataObject, $currentStateDataObject, $true, $eventContext.ControlItem.AttestComparisionType))
																	{
																		$this.ModifyControlResult($currentItem, $childResourceState);
																	}
																	
																}
																else
																{
																	if ([Helpers]::CompareObject($childResourceState.State.DataObject, $currentStateDataObject, $true))
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
												}
												# Don't fail attestation if current state data object is a subset of attested state data object
												elseif ($eventcontext.controlItem.OnAttestationDrift.ActionOnAttestationDrift -eq [ActionOnAttestationDrift]::CheckIfSubset)
												{
													# Compare dataobject property of State
													if ($null -ne $childResourceState.State.DataObject)
													{
														# Note: DataObjectProperties filter is not required here as the data object has already been filterd in above scan
														if ($currentItem.StateManagement.CurrentStateData -and $null -ne $currentItem.StateManagement.CurrentStateData.DataObject)
														{
															$currentStateDataObject = [JsonHelper]::ConvertToJsonCustom($currentItem.StateManagement.CurrentStateData.DataObject) | ConvertFrom-Json

															try
															{
																# Objects match, change result based on attestation status
																if ($eventContext.ControlItem.AttestComparisionType -and $eventContext.ControlItem.AttestComparisionType -eq [ComparisionType]::NumLesserOrEqual)
																{
																	if ([Helpers]::CompareObject($childResourceState.State.DataObject, $currentStateDataObject, $false, $eventContext.ControlItem.AttestComparisionType))
																	{
																		$this.ModifyControlResult($currentItem, $childResourceState);
																	}
														
																}
																else
																{
																	if ([Helpers]::CompareObject($childResourceState.State.DataObject, $currentStateDataObject, $false))
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
												}
											
											}

										}

									}
								}
								#endregion: Prevent attestation drift due to dev changes

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
				if (($controlState.AttestationStatus -eq "ApprovedException") -and [String]::IsNullOrEmpty($controlState.State.ExpiryDate)) {
                   $expiryDate = ($controlState.State.AttestedDate).AddDays($this.ControlSettings.DefaultAttestationPeriodForExemptControl)
                }
                else {
				    $expiryDate = [DateTime]$controlState.State.ExpiryDate
                }
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
		
		# Check if attestation drift is expected
		if ( ([FeatureFlightingManager]::GetFeatureStatus("PreventAttestationStateDrift", $($this.SubscriptionContext.SubscriptionId))))
		{
			if (($eventcontext.controlItem.IsAttestationDriftExpected -eq $true) -and ($expiryInDays -ne -1))
			{
				# Check action to be taken on drift for a specific control
				if ($eventcontext.controlItem.OnAttestationDrift -and `
					(-not [String]::IsNullOrEmpty($eventcontext.controlItem.OnAttestationDrift.ApplyToVersionsUpto)) -and `
					(-not [String]::IsNullOrEmpty($eventcontext.controlItem.OnAttestationDrift.OverrideAttestationExpiryInDays)) -and `
					($eventcontext.controlItem.OnAttestationDrift.ActionOnAttestationDrift -eq [ActionOnAttestationDrift]::OverrideAttestationExpiryPeriod))
				{
					# Check if attested version is less than or equal to the last stable version (as specified in the control json file)
					if ([System.Version] $controlState.Version -le [System.Version] $eventcontext.controlItem.OnAttestationDrift.ApplyToVersionsUpto)
					{
						# Change attestation expiry period if number of days left for control to expire is greater than custom attestation expiry period
						# This sets the attestation to expire before the original expiry period
						if ($expiryInDays -gt $eventcontext.controlItem.OnAttestationDrift.OverrideAttestationExpiryInDays)
						{
							$expiryInDays = $eventcontext.controlItem.OnAttestationDrift.OverrideAttestationExpiryInDays
						}
					}
					
				}
			}
		}

		return $expiryInDays
	}


	hidden AddResourceMetadata([PSObject] $metadataObj)
	{
		[hashtable] $resourceMetadata = New-Object -TypeName Hashtable;
			$metadataObj.psobject.properties |
				ForEach-Object {
					$resourceMetadata.Add($_.name, $_.value)
				}

		if([Helpers]::CheckMember($this.ControlSettings, 'AllowedResourceTypesForMetadataCapture') )
		{
			if( $this.ResourceContext.ResourceTypeName -in $this.ControlSettings.AllowedResourceTypesForMetadataCapture)
			{
				$this.ResourceContext.ResourceMetadata = $resourceMetadata
			}
			else
			{
				$this.ResourceContext.ResourceMetadata = $null
			}
		}
		else 
		{
			$this.ResourceContext.ResourceMetadata = $resourceMetadata
		}

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
  
	#stub to be used when ComplianceState 
	hidden [void] GetDataFromSubscriptionReport($singleControlResult)
   	{ 
		
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
            if([Helpers]::CheckMember($this.ControlSettings,"ControlSeverity"))
            {
                $controlsev = $this.ControlSettings.ControlSeverity.PSobject.Properties | Where-Object Value -eq $controlSeverity | Select-Object -First 1
                $controlSeverity = $controlsev.name
                $computedGraceDays=$this.ControlSettings.NewControlGracePeriodInDays.ControlSeverity.$ControlSeverity;
            }
            else
            {
                $computedGraceDays=$this.ControlSettings.NewControlGracePeriodInDays.ControlSeverity.$ControlSeverity;
            }
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
