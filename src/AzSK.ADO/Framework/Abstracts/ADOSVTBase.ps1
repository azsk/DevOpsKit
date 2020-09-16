class ADOSVTBase: SVTBase {

	hidden [ControlStateExtension] $ControlStateExt;
	hidden [AzSKSettings] $AzskSettings;
	ADOSVTBase() {

	}

	ADOSVTBase([string] $subscriptionId):
	Base($subscriptionId) {
		$this.CreateInstance();
	}
	ADOSVTBase([string] $subscriptionId, [SVTResource] $svtResource):
	Base($subscriptionId) {		
		$this.CreateInstance($svtResource);
	}
	#Create instance for organization scan 
	hidden [void] CreateInstance() {
		[Helpers]::AbstractClass($this, [SVTBase]);
		Write-Host -ForegroundColor Yellow "No mapping!? Do we use this .ctor?"
		#$this.LoadSvtConfig([SVTMapping]::SubscriptionMapping.JsonFileName);
		$this.ResourceId = $this.SubscriptionContext.Scope;	
	}
   
	#Add PreviewBaselineControls
	hidden [bool] CheckBaselineControl($controlId) {
		if (($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings, "BaselineControls.ResourceTypeControlIdMappingList")) {
			$baselineControl = $this.ControlSettings.BaselineControls.ResourceTypeControlIdMappingList | Where-Object { $_.ControlIds -contains $controlId }
			if (($baselineControl | Measure-Object).Count -gt 0 ) {
				return $true
			}
		}
		return $false
	}
	hidden [bool] CheckPreviewBaselineControl($controlId) {
		if (($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings, "PreviewBaselineControls.ResourceTypeControlIdMappingList")) {
			$PreviewBaselineControls = $this.ControlSettings.PreviewBaselineControls.ResourceTypeControlIdMappingList | Where-Object { $_.ControlIds -contains $controlId }
			if (($PreviewBaselineControls | Measure-Object).Count -gt 0 ) {
				return $true
			}
		}
		return $false
	}

	hidden [void] UpdateControlStates([SVTEventContext[]] $ControlResults) {
		if ($null -ne $this.ControlStateExt -and $this.ControlStateExt.HasControlStateWriteAccessPermissions() -and ($ControlResults | Measure-Object).Count -gt 0 -and ($this.ResourceState | Measure-Object).Count -gt 0) {
			$effectiveResourceStates = @();
			if (($this.DirtyResourceStates | Measure-Object).Count -gt 0) {
				$this.ResourceState | ForEach-Object {
					$controlState = $_;
					if (($this.DirtyResourceStates | Where-Object { $_.InternalId -eq $controlState.InternalId -and $_.ChildResourceName -eq $controlState.ChildResourceName } | Measure-Object).Count -eq 0) {
						$effectiveResourceStates += $controlState;
					}
				}
			}
			else {
				#If no dirty states found then no action needed.
				return;
			}

			#get the uniqueid from the first control result. Here we can take first as it would come here for each resource.
			$id = $ControlResults[0].GetUniqueId();
			$resourceType = $ControlResults[0].FeatureName
			$resourceName = $ControlResults[0].ResourceContext.ResourceName

			$this.ControlStateExt.SetControlState($id, $effectiveResourceStates, $true, $resourceType, $resourceName, $ControlResults[0].ResourceContext.ResourceGroupName)
		}
	}

	#isRescan parameter is added to check if method is called from rescan. state data is fetching for rescan
	hidden [ControlState[]] GetResourceState([bool] $isRescan = $false) {
		if ($null -eq $this.ResourceState) {
			$this.ResourceState = @();
			if ($this.ControlStateExt -and $this.ControlStateExt.HasControlStateReadAccessPermissions()) {
				$resourceType = "";
				if ($this.ResourceContext) {
					$resourceType = $this.ResourceContext.ResourceTypeName
				}
				#Fetch control state for organization only if project is configured for org spesific control attestation (Check for Organization only, for other resource go inside without project check).

				if($resourceType -ne "Organization" -or $this.ControlStateExt.GetProject())
				{
					$resourceStates = $this.ControlStateExt.GetControlState($this.ResourceId, $resourceType, $this.ResourceContext.ResourceName, $this.ResourceContext.ResourceGroupName, $isRescan)
					if ($null -ne $resourceStates) {
						$this.ResourceState += $resourceStates

					}
				}		
			}
		}

		return $this.ResourceState;
	}
	
	hidden [void] PostProcessData([SVTEventContext] $eventContext) {
		$tempHasRequiredAccess = $true;
		$controlState = @();
		$controlStateValue = @();
		try {
			$resourceStates = $this.GetResourceState($false)
			if (!$this.AzskSettings) {
				$this.AzskSettings = [ConfigurationManager]::GetLocalAzSKSettings();
			}	
			$enableOrgControlAttestation = $this.AzskSettings.EnableOrgControlAttestation

			if (($resourceStates | Measure-Object).Count -ne 0) {
				$controlStateValue += $resourceStates | Where-Object { $_.InternalId -eq $eventContext.ControlItem.Id };
				$controlStateValue | ForEach-Object {
					$currentControlStateValue = $_;
					if ($null -ne $currentControlStateValue) {
						if ($this.IsStateActive($eventContext, $currentControlStateValue)) {
							$controlState += $currentControlStateValue;
						}
						else {
							#add to the dirty state list so that it can be removed later
							$this.DirtyResourceStates += $currentControlStateValue;
						}
					}
				}
			}
			# If Project name is not configured in ext storage & policy project parameter is not used or attestation repo is not present in policy project, 
			# then 'IsOrgAttestationProjectFound' will be false so that HasRequiredAccess for org controls can be set as false
			elseif (($eventContext.FeatureName -eq "Organization" -and [ControlStateExtension]::IsOrgAttestationProjectFound -eq $false) -and ($enableOrgControlAttestation -eq $true)){
				$tempHasRequiredAccess = $false;
			}
			elseif ($null -eq $resourceStates) {
				$tempHasRequiredAccess = $false;
			}
		}
		catch {
			$this.EvaluationError($_);
		}

		$eventContext.ControlResults |
		ForEach-Object {
			try {
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
				if (-not $this.GenerateFixScript) {
					$currentItem.EnableFixControl = $false;
				}

				if ($currentItem.StateManagement.CurrentStateData -and $currentItem.StateManagement.CurrentStateData.DataObject -and $eventContext.ControlItem.DataObjectProperties) {
					$currentItem.StateManagement.CurrentStateData.DataObject = [Helpers]::SelectMembers($currentItem.StateManagement.CurrentStateData.DataObject, $eventContext.ControlItem.DataObjectProperties);
				}

				if ($controlState.Count -ne 0) {
					# Process the state if its available
					$childResourceState = $controlState | Where-Object { $_.ChildResourceName -eq $currentItem.ChildResourceName } | Select-Object -First 1;
					if ($childResourceState) {
						# Skip passed ones from State Management
						if ($currentItem.ActualVerificationResult -ne [VerificationResult]::Passed) {
							#compare the states
							if (($childResourceState.ActualVerificationResult -eq $currentItem.ActualVerificationResult) -and $childResourceState.State) {
				
								$currentItem.StateManagement.AttestedStateData = $childResourceState.State;

								# Compare dataobject property of State
								if ($null -ne $childResourceState.State.DataObject) {
									if ($currentItem.StateManagement.CurrentStateData -and $null -ne $currentItem.StateManagement.CurrentStateData.DataObject) {
										$currentStateDataObject = [JsonHelper]::ConvertToJsonCustom($currentItem.StateManagement.CurrentStateData.DataObject) | ConvertFrom-Json
										
										try {
											# Objects match, change result based on attestation status
											if ($eventContext.ControlItem.AttestComparisionType -and $eventContext.ControlItem.AttestComparisionType -eq [ComparisionType]::NumLesserOrEqual) {
												if ([Helpers]::CompareObject($childResourceState.State.DataObject, $currentStateDataObject, $true, $eventContext.ControlItem.AttestComparisionType)) {
													$this.ModifyControlResult($currentItem, $childResourceState);
												}
												
											}
											else {
												if ([Helpers]::CompareObject($childResourceState.State.DataObject, $currentStateDataObject, $true)) {
													$this.ModifyControlResult($currentItem, $childResourceState);
												}
											}
										}
										catch {
											$this.EvaluationError($_);
										}
									}
								}
								else {
									if ($currentItem.StateManagement.CurrentStateData) {
										if ($null -eq $currentItem.StateManagement.CurrentStateData.DataObject) {
											# No object is persisted, change result based on attestation status
											$this.ModifyControlResult($currentItem, $childResourceState);
										}
									}
									else {
										# No object is persisted, change result based on attestation status
										$this.ModifyControlResult($currentItem, $childResourceState);
									}
								}
							}
						}
						else {
							#add to the dirty state list so that it can be removed later
							$this.DirtyResourceStates += $childResourceState
						}
					}
				}
			}
			catch {
				$this.EvaluationError($_);
			}
		};
	}

	# State Machine implementation of modifying verification result
	hidden [void] ModifyControlResult([ControlResult] $controlResult, [ControlState] $controlState) {
		# No action required if Attestation status is None OR verification result is Passed
		if ($controlState.AttestationStatus -ne [AttestationStatus]::None -or $controlResult.VerificationResult -ne [VerificationResult]::Passed) {
			$controlResult.AttestationStatus = $controlState.AttestationStatus;
			$controlResult.VerificationResult = [Helpers]::EvaluateVerificationResult($controlResult.VerificationResult, $controlState.AttestationStatus);
		}
	}

	#Function to validate attestation data expiry validation
	hidden [bool] IsStateActive([SVTEventContext] $eventcontext, [ControlState] $controlState) {
		try {
			$expiryIndays = $this.CalculateExpirationInDays([SVTEventContext] $eventcontext, [ControlState] $controlState);
			#Validate if expiry period is passed
			#Added a condition so as to expire attested controls that were in 'Error' state.
			if (($expiryIndays -ne -1 -and $controlState.State.AttestedDate.AddDays($expiryIndays) -lt [DateTime]::UtcNow) -or ($controlState.ActualVerificationResult -eq [VerificationResult]::Error)) {
				return $false
			}
			else {
				$controlState.State.ExpiryDate = ($controlState.State.AttestedDate.AddDays($expiryIndays)).ToString("MM/dd/yyyy");
				return $true
			}
		}
		catch {
			#if any exception occurs while getting/validating expiry period, return true.
			$this.EvaluationError($_);
			return $true
		}
	}

	hidden [int] CalculateExpirationInDays([SVTEventContext] $eventcontext, [ControlState] $controlState) {
		try {
			#For exempt controls, either the no. of days for expiry were provided at the time of attestation or a default of 6 motnhs was already considered,
			#therefore skipping this flow and calculating days directly using the expiry date already saved.
			if ($controlState.AttestationStatus -ne [AttestationStatus]::ApprovedException) {
				#Get controls expiry period. Default value is zero
				$controlAttestationExpiry = $eventcontext.controlItem.AttestationExpiryPeriodInDays
				$controlSeverity = $eventcontext.controlItem.ControlSeverity
				$controlSeverityExpiryPeriod = 0
				$defaultAttestationExpiryInDays = [Constants]::DefaultControlExpiryInDays;
				$expiryInDays = -1;
	
				if (($eventcontext.ControlResults | Measure-Object).Count -gt 0) {
					$isControlInGrace = $eventcontext.ControlResults.IsControlInGrace;
				}
				else {
					$isControlInGrace = $true;
				}
				if ([Helpers]::CheckMember($this.ControlSettings, "AttestationExpiryPeriodInDays") `
						-and [Helpers]::CheckMember($this.ControlSettings.AttestationExpiryPeriodInDays, "Default") `
						-and $this.ControlSettings.AttestationExpiryPeriodInDays.Default -gt 0) {
					$defaultAttestationExpiryInDays = $this.ControlSettings.AttestationExpiryPeriodInDays.Default
				}			
				#Expiry in the case of WillFixLater or StateConfirmed/Recurring Attestation state will be based on Control Severity.
				if ($controlState.AttestationStatus -eq [AttestationStatus]::NotAnIssue -or $controlState.AttestationStatus -eq [AttestationStatus]::NotApplicable) {
					$expiryInDays = $defaultAttestationExpiryInDays;
				}
				else {
					# Expire WillFixLater if GracePeriod has expired
					if (-not($isControlInGrace) -and $controlState.AttestationStatus -eq [AttestationStatus]::WillFixLater) {
						$expiryInDays = 0;
					}
					else {
						if ($controlAttestationExpiry -ne 0) {
							$expiryInDays = $controlAttestationExpiry
						}
						elseif ([Helpers]::CheckMember($this.ControlSettings, "AttestationExpiryPeriodInDays")) {
							$controlsev = $this.ControlSettings.ControlSeverity.PSobject.Properties | Where-Object Value -eq $controlSeverity | Select-Object -First 1
							$controlSeverity = $controlsev.name									
							#Check if control severity has expiry period
							if ([Helpers]::CheckMember($this.ControlSettings.AttestationExpiryPeriodInDays.ControlSeverity, $controlSeverity) ) {
								$expiryInDays = $this.ControlSettings.AttestationExpiryPeriodInDays.ControlSeverity.$controlSeverity
							}
							#If control item and severity does not contain expiry period, assign default value
							else {
								$expiryInDays = $defaultAttestationExpiryInDays
							}
						}
						#Return -1 when expiry is not defined
						else {
							$expiryInDays = -1
						}
					}
				}				
			}
			else {				
				#Calculating the expiry in days for exempt controls
				
				$expiryDate = [DateTime]$controlState.State.ExpiryDate
				#Adding 1 explicitly to the days since the differnce below excludes the expiryDate and that also needs to be taken into account.
				$expiryInDays = ($expiryDate - $controlState.State.AttestedDate).Days + 1
			}								
		}
		catch {
			#if any exception occurs while getting/validating expiry period, return -1.
			$this.EvaluationError($_);
			$expiryInDays = -1
		}
		return $expiryInDays
	}

	[SVTEventContext[]] FetchStateOfAllControls() {
		[SVTEventContext[]] $resourceSecurityResult = @();
		if (-not $this.ValidateMaintenanceState()) {
			if ($this.GetApplicableControls().Count -eq 0) {
				$this.PublishCustomMessage("No security controls match the input criteria specified", [MessageType]::Warning);
			}
			else {
				$this.EvaluationStarted();
				$resourceSecurityResult += $this.GetControlsStateResult();
				if (($resourceSecurityResult | Measure-Object).Count -gt 0) {
					$this.EvaluationCompleted($resourceSecurityResult);
				}
			}
		}
		return $resourceSecurityResult;
	}

	hidden [SVTEventContext[]] GetControlsStateResult() {
		[SVTEventContext[]] $automatedControlsResult = @();
		$this.DirtyResourceStates = @();
		try {
			$this.GetApplicableControls() |
			ForEach-Object {
				$eventContext = $this.FetchControlState($_);
				#filter controls if there is no state found
				if ($eventContext) {
					$eventContext.ControlResults = $eventContext.ControlResults | Where-Object { $_.AttestationStatus -ne [AttestationStatus]::None }
					if ($eventContext.ControlResults) {
						$automatedControlsResult += $eventContext;
					}
				}
			};
		}
		catch {
			$this.EvaluationError($_);
		}

		return $automatedControlsResult;
	}
 #isRescan parameter is added to check if method is called from rescan. 
	hidden [SVTEventContext] FetchControlState([ControlItem] $controlItem, $isRescan = $false) {
		[SVTEventContext] $singleControlResult = $this.CreateSVTEventContextObject();
		$singleControlResult.ControlItem = $controlItem;

		$controlState = @();
		$controlStateValue = @();
		try {
			$resourceStates = $this.GetResourceState($isRescan);
			if (($resourceStates | Measure-Object).Count -ne 0) {
				$controlStateValue += $resourceStates | Where-Object { $_.InternalId -eq $singleControlResult.ControlItem.Id };
				$controlStateValue | ForEach-Object {
					$currentControlStateValue = $_;
					if ($null -ne $currentControlStateValue) {
						#assign expiry date
						$expiryIndays = $this.CalculateExpirationInDays($singleControlResult, $currentControlStateValue);
						if ($expiryIndays -ne -1) {
							$currentControlStateValue.State.ExpiryDate = ($currentControlStateValue.State.AttestedDate.AddDays($expiryIndays)).ToString("MM/dd/yyyy");
						}
						$controlState += $currentControlStateValue;
					}
				}
			}
		}
		catch {
			$this.EvaluationError($_);
		}
		if (($controlState | Measure-Object).Count -gt 0) {
		#Added check to resolve duplicate log issue in rescan
			if (!$isRescan) {
			   $this.ControlStarted($singleControlResult);
			}
			if ($controlItem.Enabled -eq $false) {
				$this.ControlDisabled($singleControlResult);
			}
			else {
				$controlResult = $this.CreateControlResult($controlItem.FixControl);
				$singleControlResult.ControlResults += $controlResult;          
				$singleControlResult.ControlResults | 
				ForEach-Object {
					try {
						$currentItem = $_;

						if ($controlState.Count -ne 0) {
							# Process the state if it's available
							$childResourceState = $controlState | Where-Object { $_.ChildResourceName -eq $currentItem.ChildResourceName } | Select-Object -First 1;
							if ($childResourceState) {
								$currentItem.StateManagement.AttestedStateData = $childResourceState.State;
								$currentItem.AttestationStatus = $childResourceState.AttestationStatus;
								$currentItem.ActualVerificationResult = $childResourceState.ActualVerificationResult;
								$currentItem.VerificationResult = [VerificationResult]::NotScanned
							}
						}
					}
					catch {
						$this.EvaluationError($_);
					}
				};

			}
			#Added check to resolve duplicate log issue in rescan
			if (!$isRescan) {
			   $this.ControlCompleted($singleControlResult);
			}
		}

		return $singleControlResult;
	}

	hidden [void] GetManualSecurityStatusExt($arg) {
		$this.PostProcessData($arg);
	}

	hidden [void] RunControlExt($singleControlResult) {
		$this.PostProcessData($singleControlResult);
	}

	hidden [void] EvaluateAllControlsExt($resourceSecurityResult) {
		$this.PostEvaluationCompleted($resourceSecurityResult);
	}

	hidden [void] PostEvaluationCompleted([SVTEventContext[]] $ControlResults) {		
		$this.UpdateControlStates($ControlResults);

		$BugLogParameterValue =$this.InvocationContext.BoundParameters["AutoBugLog"]
		#perform bug logging after control scans for the current resource
		if ($BugLogParameterValue) {
			$this.BugLoggingPostEvaluation($ControlResults,$BugLogParameterValue)
		}
	}
	
	#function to call AutoBugLog class for performing bug logging
	hidden [void] BugLoggingPostEvaluation([SVTEventContext []] $ControlResults,[string] $BugLogParameterValue){
		$AutoBugLog=[AutoBugLog]::new($this.SubscriptionContext,$this.InvocationContext,$ControlResults,$this.ControlStateExt);
		$AutoBugLog.LogBugInADO($ControlResults,$BugLogParameterValue)

	}

	
}
