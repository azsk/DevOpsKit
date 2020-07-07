class ADOSVTBase: SVTBase {

	hidden [ControlStateExtension] $ControlStateExt;

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
 
		$this.LoadSvtConfig([SVTMapping]::SubscriptionMapping.JsonFileName);
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

		if (($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings, "BaselineControls.SubscriptionControlIdList")) {
			$baselineControl = $this.ControlSettings.BaselineControls.SubscriptionControlIdList | Where-Object { $_ -eq $controlId }
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

		if (($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings, "PreviewBaselineControls.SubscriptionControlIdList")) {
			$PreviewBaselineControls = $this.ControlSettings.PreviewBaselineControls.SubscriptionControlIdList | Where-Object { $_ -eq $controlId }
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

	hidden [ControlState[]] GetResourceState() {
		if ($null -eq $this.ResourceState) {
			$this.ResourceState = @();
			if ($this.ControlStateExt -and $this.ControlStateExt.HasControlStateReadAccessPermissions()) {
				$resourceType = "";
				if ($this.ResourceContext) {
					$resourceType = $this.ResourceContext.ResourceTypeName
				}
				#Fetch control state for organization only if project is configured for org spesific control attestation (Check for Organization only, for other resource go inside without project check).
				if ($resourceType -ne "Organization" -or $this.ControlStateExt.GetProject()) {
					$resourceStates = $this.ControlStateExt.GetControlState($this.ResourceId, $resourceType, $this.ResourceContext.ResourceName, $this.ResourceContext.ResourceGroupName)
					if ($null -ne $resourceStates) {
						$this.ResourceState += $resourceStates
					}
				}
				else {
					return $null;
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
			$resourceStates = $this.GetResourceState()			
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

	hidden [SVTEventContext] FetchControlState([ControlItem] $controlItem) {
		[SVTEventContext] $singleControlResult = $this.CreateSVTEventContextObject();
		$singleControlResult.ControlItem = $controlItem;

		$controlState = @();
		$controlStateValue = @();
		try {
			$resourceStates = $this.GetResourceState();
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
			$this.ControlStarted($singleControlResult);
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
			$this.ControlCompleted($singleControlResult);
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
		# If ResourceType is Databricks, reverting security protocol 
		if ([Helpers]::CheckMember($this.ResourceContext, "ResourceType") -and $this.ResourceContext.ResourceType -eq "Microsoft.Databricks/workspaces") {
			[Net.ServicePointManager]::SecurityProtocol = $this.currentSecurityProtocol 
		}
		
		$this.UpdateControlStates($ControlResults);
		#check if autobuglog flag is provided and if the logging behaviour is valid for the current resource type
		if ($this.ControlStateExt.InvocationContext.BoundParameters["AutoBugLog"] -and $this.CheckValidLog($ControlResults[0])) {
			#check if area and iteration path are valid, if not skip the bug logging for this resource
			if ($this.ControlStateExt.CheckValidPath()) {
				$this.AutoLogBug($ControlResults, $this.ControlStateExt.InvocationContext.BoundParameters["AutoBugLog"])
			}
		}
	}

	#function to log bugs in ADO
	
	hidden [void] AutoLogBug([SVTEventContext[]] $ControlResults, [string] $BugLogParameterValue) {
		#Obtain the project name according to the current resource type
		$ProjectName = $this.ControlStateExt.GetProject()

		#Obtain project id that will be used by hash based searching of work item
		$ProjectId = $null
		if ($this.ResourceContext.ResourceTypeName -eq "Project" -or $this.ResourceContext.ResourceTypeName -eq "Organization" -or $this.ResourceContext.ResourceTypeName -eq "ServiceConnection" -or $this.ResourceContext.ResourceTypeName -eq "Release") {
			$apiURL = "https://dev.azure.com/{0}/_apis/projects/{1}?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName), $($ProjectName);
			$projectObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
			$ProjectId = $projectObj.id
		}
		if ($this.ResourceContext.ResourceTypeName -eq "AgentPool") {
			$ProjectId = ($ControlResults[0].ResourceContext.ResourceId -split ("resources/"))[1].Split("_")[0]
		}
		elseif ($this.ResourceContext.ResourceTypeName -eq "Build") {
			$ProjectId = ($ControlResults[0].ResourceContext.ResourceId -split ("com/"))[1].Split("/")[0]
		}

		#Obtain the assignee for the current resource, will be same for all the control failures for this particular resource
		$AssignedTo = $this.GetAssignee($ControlResults[0].ResourceContext.ResourceTypeName, $ControlResults[0].ResourceContext.ResourceName)
		
		#Obtain area and iteration paths
		if ($this.ControlStateExt.InvocationContext.BoundParameters["AreaPath"] -ne $null) {
			$AreaPath = $this.ControlStateExt.InvocationContext.BoundParameters["AreaPath"]
		}
		else {
			if ($this.ControlSettings.BugLogAreaPath -eq "Root") {
				$AreaPath = $ProjectName
			}
			else {
				$AreaPath = $this.ControlSettings.BugLogAreaPath
			}
		}
		if ($this.ControlStateExt.InvocationContext.BoundParameters["IterationPath"] -ne $null) {
			$IterationPath = $this.ControlStateExt.InvocationContext.BoundParameters["IterationPath"]
		}
		else {
			if ($this.ControlSettings.BugLogIterationPath -eq "Root") {
				$IterationPath = $ProjectName
			}
			else {
				$IterationPath = $this.ControlSettings.BugLogIterationPath
			}
		}
		$AreaPath = $AreaPath.Replace("\", "\\")
		$IterationPath = $IterationPath.Replace("\", "\\")

		
		#Loop through all the control results for the current resource
		$ControlResults | ForEach-Object {			
					
			$control = $_;

			#filter controls on basis of whether they are baseline or not depending on the value given in autobuglog flag
			if ($BugLogParameterValue -eq "All") {
				$check = $true
			}
			elseif ($BugLogParameterValue -eq "BaselineControls") {
				$check = $this.CheckBaselineControl($control.ControlItem.ControlID)				
			}
			else {
				$check = $this.CheckPreviewBaselineControl($control.ControlItem.ControlID)
			}
			
			
			if (($control.ControlResults[0].VerificationResult -eq "Failed" -or $control.ControlResults[0].VerificationResult -eq "Verify") -and $check) {
				
				#compute hash of control Id and resource Id	
				$hash = $this.GetHash($control.ControlItem.Id, $control.ResourceContext.ResourceId)
				$workItem = $this.GetWorkItemByHash($hash, $ProjectName, $ProjectId)
				if ($workItem[0].results.count -eq 1) {
					$this.FindActiveAndResolvedBugs($ProjectName,$control,$workItem,$AssignedTo)
				}
				else{		


				$this.PublishCustomMessage([Constants]::SingleDashLine + "`nDetermining bugs to log...`n");

				#filling the bug template
				$Title = "[ADOScanner] Control failure - {0} for resource {1} {2}"
				$Description = "Control failure - {3} for resource {4} {5} </br></br> <b>Failure Details: </b> {0} </br></br> <b> Control Result: </b> {6} </br> </br> <b> Rationale:</b> {1} </br></br> <b> Recommendation:</b> {2}"
			
				$Title = $Title.Replace("{0}", $control.ControlItem.ControlID)
				$Title = $Title.Replace("{1}", $control.ResourceContext.ResourceTypeName)
				$Title = $Title.Replace("{2}", $control.ResourceContext.ResourceName)
				
				$Description = $Description.Replace("{0}", $control.ControlItem.Description)
				$Description = $Description.Replace("{1}", $control.ControlItem.Rationale)
				$Description = $Description.Replace("{2}", $control.ControlItem.Recommendation)
				$Description = $Description.Replace("{3}", $control.ControlItem.ControlID)
				$Description = $Description.Replace("{4}", $control.ResourceContext.ResourceTypeName)
				$Description = $Description.Replace("{5}", $control.ResourceContext.ResourceName)
				$Description = $Description.Replace("{6}", $control.ControlResults[0].VerificationResult)
				$Description = $Description.Replace("'", "\'")
				
				#check and append any detailed log and state data for the control failure
				if ($this.LogMessage($control)) {
					$Description += "<hr></br><b>Some other details for your reference</b> </br><hr> {7} "
					$log = $this.LogMessage($control).Replace("\", "\\")
					$Description = $Description.Replace("{7}", $log)
					
				}				
				
				$Severity = $this.GetSeverity($control.ControlItem.ControlSeverity)		
					
				
				#function to attempt bug logging
				$this.AddWorkItem($Title, $Description, $AssignedTo, $AreaPath, $IterationPath, $Severity, $ProjectName, $control, $hash, $ProjectId)

			}
		}
		}

	}

	#function to check any detailed log and state data for the control failure
	hidden [string] LogMessage([SVTEventContext[]] $ControlResult) {
		$log = ""
		$Messages = $ControlResult.ControlResults[0].Messages

		$Messages | ForEach-Object {
			if ($_.Message) {
				$log += "<b>$($_.Message)</b> </br></br>"
			}
			if ($_.DataObject) {
				$log += "<hr>"

				$stateData = [Helpers]::ConvertObjectToString($_, $false)
				$stateData = $stateData.Replace("@{", "@{</br>")
				$stateData = $stateData.Replace("@(", "@(</br>")
				$stateData = $stateData.Replace(";", ";</br>")
				$stateData = $stateData.Replace("},", "</br>},</br>")
				$stateData = $stateData.Replace(");", "</br>});</br>")
					
				$log += "$($stateData) </br></br>"	
					
				
			}
		}
		$log = $log.Replace("\", "\\")	

		return $log
	}


	#function to check if the bug can be logged for the current resource type
	hidden [bool] CheckValidLog([SVTEventContext[]] $ControlResult) {
		switch -regex ($ControlResult.FeatureName) {
			'Organization' {
				if (!($this.GetHostProject($ControlResult))) {
					return $false
				}				
			}
			'Project' {
				if (!$this.ControlStateExt.GetControlStatePermission($ControlResult.FeatureName, $ControlResult.ResourceContext.ResourceName)) {
					Write-Host "`nAuto Bug Logging denied due to insufficient permission. Make sure you are a Project Admin. " -ForegroundColor Red
					return $false
				}
			}
		}
		return $true
	}


	#function to retrive the attestation host project for organization level control failures
	hidden [string] GetHostProject([SVTEventContext[]] $ControlResult) {
		$Project = $null
		if ($this.InvocationContext.BoundParameters["AttestationHostProjectName"]) {
			if ($this.ControlStateExt.GetControlStatePermission("Organization", "")) { 
				$this.ControlStateExt.SetProjectInExtForOrg()	
			}
			else {
				Write-Host "Error: Could not configure host project for organization controls auto bug log.`nThis may be because: `n  (a) You may not have correct privilege (requires 'Project Collection Administrator').`n  (b) You are logged in using PAT (which is not supported for this currently)." -ForegroundColor Red
				return $Project
			}
		}
		if (!$this.ControlStateExt.GetControlStatePermission("Resource", "microsoftit") ) {
			Write-Host "Error: Auto bug logging denied.`nThis may be because: `n  (a) You are attempting to log bugs for areas you do not have RBAC permission to.`n  (b) You are logged in using PAT (currently not supported for organization and project control's bug logging)." -ForegroundColor Red
			return $Project
					  
		}
		if (!$this.ControlStateExt.GetProject()) { 
			Write-Host "`nNo project defined to store bugs for organization-specific controls." -ForegroundColor Red
			Write-Host "Use the '-AttestationHostProjectName' parameter with this command to configure the project that will host bug logging details for organization level controls.`nRun 'Get-Help -Name Get-AzSKAzureDevOpsSecurityStatus -Full' for more info." -ForegroundColor Yellow
			return $Project
		}
		$Project = $this.ControlStateExt.GetProject()
		return $Project


	}

	#function to retrieve the person to whom the bug will be assigned

	hidden [string] GetAssignee([string] $ResourceType, [string] $resourceName) {

		$Assignee = "";
		switch -regex ($ResourceType) {
			#assign to the creator of service connection
			'ServiceConnection' {
				$Assignee = $this.ResourceContext.ResourceDetails.createdBy.uniqueName
			}
			#assign to the creator of agent pool
			'AgentPool' {
				$apiurl = "https://dev.azure.com/{0}/_apis/distributedtask/pools?poolName={1}&api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $resourceName
				try {
					$response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
					$Assignee = $response.createdBy.uniqueName
	
				}
				catch {
					$Assignee = [ContextHelper]::GetCurrentSessionUser();
				}

			}
			#assign to the person who recently triggered the build pipeline, or if the pipeline is empty assign it to the creator
			'Build' {
				$definitionId = ($this.ResourceContext.ResourceDetails.ResourceLink -split "=")[1]

				try {
					$apiurl = "https://dev.azure.com/{0}/{1}/_apis/build/builds?definitions={2}&api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $this.ResourceContext.ResourceGroupName , $definitionId;
				
					$response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
	
					if ([Helpers]::CheckMember($response, "requestedBy")) {
						$Assignee = $response[0].requestedBy.uniqueName
					}
					else {
						$apiurl = "https://dev.azure.com/{0}/{1}/_apis/build/definitions/{2}?api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $this.ResourceContext.ResourceGroupName , $definitionId;
						$response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
						$Assignee = $response.authoredBy.uniqueName
					}
				}
				catch {
					$Assignee = [ContextHelper]::GetCurrentSessionUser();
				}	
				
			}
			#assign to the person who recently triggered the release pipeline, or if the pipeline is empty assign it to the creator
			'Release' {
				$definitionId = ($this.ResourceContext.ResourceId -split "definitions/")[1]
				try {
					$apiurl = "https://vsrm.dev.azure.com/{0}/{1}/_apis/release/releases?definitionId={2}&api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $this.ResourceContext.ResourceGroupName , $definitionId;
					$response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
	
					if ([Helpers]::CheckMember($response, "modifiedBy")) {
						$Assignee = $response[0].modifiedBy.uniqueName
					}
					
					else {
						$apiurl = "https://vsrm.dev.azure.com/{0}/{1}/_apis/release/definitions/{2}?&api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $this.ResourceContext.ResourceGroupName , $definitionId;
						$response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
						$Assignee = $response.createdBy.uniqueName
					}
				}
				catch {
					$Assignee = [ContextHelper]::GetCurrentSessionUser();
				}
				


			}
			#assign to the person running the scan
			'Organization' {
				$Assignee = [ContextHelper]::GetCurrentSessionUser();
			}
			'Project' {
				$Assignee = [ContextHelper]::GetCurrentSessionUser();

			}
		}
		return $Assignee;

	}

	#function to map severity of the control item
	hidden [string] GetSeverity([string] $ControlSeverity) {
		$Severity = ""
		switch -regex ($ControlSeverity) {
			'Critical' {
				$Severity = "1 - Critical"
			}
			'High' {
				$Severity = "2 - High"
			}
			'Medium' {
				$Severity = "3 - Medium"
			}
			'Low' {
				$Severity = "4 - Low"
			}

		}

		return $Severity
	}

	#function to find active bugs and reactivate resolved bugs
	hidden [void] FindActiveAndResolvedBugs([string]$ProjectName, [SVTEventContext[]] $control, [object] $workItem, [string] $AssignedTo){
		
		
			$state = ($workItem[0].results.values.fields | where { $_.name -eq "State" })
			$id = ($workItem[0].results.values.fields | where { $_.name -eq "ID" }).value

			$bugUrl = "https://{0}.visualstudio.com/{1}/_workitems/edit/{2}" -f $($this.SubscriptionContext.SubscriptionName), $ProjectName , $id

			
			if ($state.value -eq "Resolved") {
				$url = "https://dev.azure.com/{0}/{1}/_apis/wit/workitems/{2}?api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $ProjectName, $id
				$body = @"

				[
				{
				  'op': 'add',
				  'path': '/fields/System.State',
				  'from': null,
				  'value': 'Active'
				},
				{
				 "op":"add",
				 "path":"/fields/Microsoft.VSTS.Common.ResolvedReason",
				 "value":""
				},
				{
					'op':'add',
					'path':'/fields/System.AssignedTo',
					'from': null,
					'value':'$AssignedTo'
				}
				]
"@
					$header = $this.GetAuthHeaderFromUriPatch($url)
					
				try {
					$responseObj = Invoke-RestMethod -Uri $url -Method Patch -ContentType "application/json-patch+json ; charset=utf-8" -Headers $header -Body $body
					$control.ControlResults.AddMessage("Resolved Bug", $bugUrl)

				}
				catch {
					if ($_.ErrorDetails.Message -like '*System.AssignedTo*') {
						$body = $body | ConvertFrom-Json
						$body[2].value = "";
						$body = $body | ConvertTo-Json
						try {
							$responseObj = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json-patch+json ; charset=utf-8" -Headers $header -Body $body
							$bugUrl = "https://{0}.visualstudio.com/_workitems/edit/{1}" -f $($this.SubscriptionContext.SubscriptionName), $responseObj.id
							$control.ControlResults.AddMessage("Resolved Bug", $bugUrl)
						}
						catch {
							Write-Host "Could not reactivate the bug" -ForegroundColor Red
						}
					}
					else{
						Write-Host "Could not reactivate the bug" -ForegroundColor Red

					}
				}


			}
			else {
				$control.ControlResults.AddMessage("Active Bug", $bugUrl)
			}
		
	}

	#function to log new bugs, find active and resolved bugs

	hidden [void] AddWorkItem([string] $Title, [string] $Description, [string] $AssignedTo, [string] $AreaPath, [string] $IterationPath, [string]$Severity, [string]$ProjectName, [SVTEventContext[]] $control, [string] $hash, [string] $ProjectId ) {
		
		
		#logging new bugs
		
			$apiurl = 'https://dev.azure.com/{0}/{1}/_apis/wit/workitems/$bug?api-version=5.1' -f $($this.SubscriptionContext.SubscriptionName), $ProjectName;

			$hashString = "ADOScanID: " + $hash.Substring(0, 12)
            
			$post = @"
			[
				{
				  'op': 'add',
				  'path': '/fields/System.Title',
				  'from': null,
				  'value': '$Title'
				},
				{
				  'op': 'add',
				  'path': '/fields/Microsoft.VSTS.TCM.ReproSteps',
				  'from': null,
				  'value': '$Description'
				},
				{
					'op':'add',
					'path':'/fields/Microsoft.VSTS.Common.Severity',
					'from': null,
					'value':'$Severity'
				},
				{
					'op':'add',
					'path':'/fields/System.AreaPath',
					'from': null,
					'value':'$AreaPath'
				},
				{
					'op':'add',
					'path':'/fields/System.IterationPath',
					'from': null,
					'value':'$IterationPath'
				},
				{
					'op':'add',
					'path':'/fields/System.Tags',
					'from': null,
					'value':'$hashString'
				},
				{
					'op':'add',
					'path':'/fields/System.AssignedTo',
					'from': null,
					'value':'$AssignedTo'
				}
			  ]
"@

			<#,
			  {
				  'op':'add',
				  'path':'/fields/System.AssignedTo',
				  'from': null,
				  'value':'$AssignedTo'
			  }#>
			$responseObj = $null
			$header = $this.GetAuthHeaderFromUriPatch($apiurl)

			try {
				$responseObj = Invoke-RestMethod -Uri $apiurl -Method Post -ContentType "application/json-patch+json ; charset=utf-8" -Headers $header -Body $post
				$bugUrl = "https://{0}.visualstudio.com/_workitems/edit/{1}" -f $($this.SubscriptionContext.SubscriptionName), $responseObj.id
				$control.ControlResults.AddMessage("New Bug", $bugUrl)
				$this.PublishCustomMessage("`nLogged a new bug `n");
			}
			catch {
				#handle assignee users who are not part of org any more
				if ($_.ErrorDetails.Message -like '*System.AssignedTo*') {
					$post = $post | ConvertFrom-Json
					$post[6].value = "";
					$post = $post | ConvertTo-Json
					try {
						$responseObj = Invoke-RestMethod -Uri $apiurl -Method Post -ContentType "application/json-patch+json ; charset=utf-8" -Headers $header -Body $post
						$bugUrl = "https://{0}.visualstudio.com/_workitems/edit/{1}" -f $($this.SubscriptionContext.SubscriptionName), $responseObj.id
						$control.ControlResults.AddMessage("New Bug", $bugUrl)
						$this.PublishCustomMessage("`nLogged a new bug `n");
					}
					catch {
						Write-Host "Could not log the bug" -ForegroundColor Red
					}


				}
				#handle the case wherein due to global search area/ iteration paths from different projects passed the checkvalidpath function
				elseif ($_.ErrorDetails.Message -like '*Invalid Area/Iteration id*') {
					Write-Host "Please verify the area and iteration path. They should belong to the same Project area." -ForegroundColor Red
				}
				else{
					Write-Host "Could not log the bug" -ForegroundColor Red
				}
			}
		
		
	}

	#function to search for existing bugs based on the hash

	hidden [object] GetWorkItemByHash([string] $hash, [string] $ProjectName, [string] $ProjectId) {
		
		$url = "https://{0}.almsearch.visualstudio.com/{1}/_apis/search/workItemQueryResults?api-version=5.1-preview" -f $($this.SubscriptionContext.SubscriptionName), $ProjectName;

		if ($this.ControlSettings.ResolvedBugLogBehaviour -ne "ReactiveOldBug") {
			$body = '{"searchText":"{0}","skipResults":0,"takeResults":25,"sortOptions":[],"summarizedHitCountsNeeded":true,"searchFilters":{"Projects":["{1}"],"Work Item Types":["Bug"],"States":["New,"Active"]},"filters":[],"includeSuggestions":false}' | ConvertFrom-Json
		}
		else {
			$body = '{"searchText":"{0}","skipResults":0,"takeResults":25,"sortOptions":[],"summarizedHitCountsNeeded":true,"searchFilters":{"Projects":["{1}"],"Work Item Types":["Bug"],"States":["Active","New","Resolved"]},"filters":[],"includeSuggestions":false}' | ConvertFrom-Json
		}
		$body.searchText = "Tags:ADOScanID: " + $hash.Substring(0, 12)
		$body.searchFilters.Projects = $ProjectName

		$response = [WebRequestHelper]:: InvokePostWebRequest($url, $body)
		
		return  $response

	}
	

	hidden [string] GetHash([string] $ControlId, [string] $ResourceId) {
		$hashString = $null
		$stringToHash = "#{0}#{1}"
		$stringToHash = $stringToHash.Replace("{0}", $ControlId)
		$stringToHash = $stringToHash.Replace("{1}", $ResourceId)
		$hashString=[Helpers]::ComputeHash($stringToHash)
		return $hashString
	}

	

	hidden [Hashtable] GetAuthHeaderFromUriPatch([string] $uri) {
		[System.Uri] $validatedUri = $null;
		if ([System.Uri]::TryCreate($uri, [System.UriKind]::Absolute, [ref] $validatedUri)) {

			$token = [ContextHelper]::GetAccessToken($validatedUri.GetLeftPart([System.UriPartial]::Authority));

			$user = ""
			$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user, $token)))
			return @{
				"Authorization" = ("Basic " + $base64AuthInfo)
			};
		}
		return @{};
	}
}
