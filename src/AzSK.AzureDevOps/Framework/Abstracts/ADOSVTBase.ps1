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
				if($resourceType -ne "Organization" -or $this.ControlStateExt.GetProject())
				{
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

		if($this.ControlStateExt.InvocationContext.BoundParameters["AutoBugLog"]-and $this.CheckValidLog($ControlResults[0] ) ){
			#-and $this.CheckValidLog($ControlResults[0]
			#$r=$this.ControlStateExt.isMember("vssgp.Uy0xLTktMTU1MTM3NDI0NS0zOTk3MDI3NTMzLTcxODcyODc2OS0yOTE4MDQ2NDUzLTIyNzk3MDM4MzUtMC0wLTAtMC0x")
			
			
			if($this.CheckValidPath($this.ControlStateExt.InvocationContext.BoundParameters["AreaPath"],$this.ControlStateExt.InvocationContext.BoundParameters["IterationPath"],$ControlResults[0])){
			$this.AutoLogBug($ControlResults,$this.ControlStateExt.InvocationContext.BoundParameters["AutoBugLog"])
			}
			}
	}

	hidden [bool] CheckValidPath([string] $AreaPath,[string] $IterationPath,[SVTEventContext []] $ControlResult){
		$pathurl="https://dev.azure.com/{0}/{1}/_apis/wit/wiql?api-version=5.1" 
		$ProjectName=$null

		if($ControlResult.FeatureName -eq "Organization"){
			$ProjectName=$this.ControlStateExt.GetProject()
		}
		elseif($this.ResourceContext.ResourceTypeName -eq "Project"){
			$ProjectName=$this.ResourceContext.ResourceName
		}
		else{
			$ProjectName=$this.ResourceContext.ResourceGroupName
		}
		$pathurl="https://dev.azure.com/{0}/{1}/_apis/wit/wiql?api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $ProjectName
		
		if(!$AreaPath){
			if($this.ControlSettings.BugLogAreaPath -eq "Root"){
				$AreaPath=$ProjectName
			}
			else{
				$AreaPath=$this.ControlSettings.BugLogAreaPath
			}
		}
		if(!$IterationPath){
			if($this.ControlSettings.BugLogIterationPath -eq "Root"){
				$IterationPath=$ProjectName
			}
			else{
				$IterationPath=$this.ControlSettings.BugLogIterationPath
			}
		}
		$AreaPath=$AreaPath.Replace("\","\\")
		$IterationPath=$IterationPath.Replace("\","\\")
		$WIQL_query="Select [System.AreaPath], [System.IterationPath] From WorkItems WHERE [System.AreaPath]='$AreaPath' AND [System.IterationPath]='$IterationPath'"
		$body = @{ query = $WIQL_query }
		$bodyJson = @($body) | ConvertTo-Json
		
		try{
			$header = $this.GetAuthHeaderFromUriPatch($pathurl)
			$response = Invoke-RestMethod -Uri $pathurl -headers $header -Method Post -ContentType "application/json" -Body $bodyJson
			
		}
		catch{
			Write-Host "`nCould not log bug. Check your Area and Iteration Path" -ForegroundColor Red
			return $false;
			
		}
		

		

		return $true
	}

	hidden [void] AutoLogBug([SVTEventContext[]] $ControlResults,$flag){
	

		$ControlResults | ForEach-Object {
					
			$control = $_;
			if($flag -eq "All"){
				$check=$true
			}
			elseif ($flag -eq "BaselineControls") {
				$check=$this.CheckBaselineControl($control.ControlItem.ControlID)				
			}
			else{
				$check=$this.CheckPreviewBaselineControl($control.ControlItem.ControlID)
			}
			
			
			if (($control.ControlResults[0].VerificationResult -eq "Failed" -or $control.ControlResults[0].VerificationResult -eq "Verify") -and $check){
				$ProjectName=""
				
				if($this.ResourceContext.ResourceTypeName -eq "Project"){
					$ProjectName=$this.ResourceContext.ResourceName

				}
				elseif($this.ResourceContext.ResourceTypeName -eq "Organization"){
					$ProjectName=$this.ControlStateExt.GetProject()
					#$ProjectName="JuhiProject"
				}
				else{
					$ProjectName=$this.ResourceContext.ResourceGroupName

				}
				

				$this.PublishCustomMessage([Constants]::SingleDashLine + "`nDetermining bugs to log...`n");
				$Title="[ADOScanner] Control failure - {0} for resource {1} {2}"
				$Description="Control failure - {3} for resource {4} {5} </br></br> <b>Failure Details: </b> {0} </br></br> <b> Control Result: </b> {6} </br> </br> <b> Rationale:</b> {1} </br></br> <b> Recommendation:</b> {2}"
				
				
				$Title=$Title.Replace("{0}",$control.ControlItem.ControlID)
				$Title=$Title.Replace("{1}",$control.ResourceContext.ResourceTypeName)
				$Title=$Title.Replace("{2}",$control.ResourceContext.ResourceName)
				
				$Description=$Description.Replace("{0}",$control.ControlItem.Description)
				$Description=$Description.Replace("{1}",$control.ControlItem.Rationale)
				$Description=$Description.Replace("{2}",$control.ControlItem.Recommendation)
				$Description=$Description.Replace("{3}",$control.ControlItem.ControlID)
				$Description=$Description.Replace("{4}",$control.ResourceContext.ResourceTypeName)
				$Description=$Description.Replace("{5}",$control.ResourceContext.ResourceName)
				$Description=$Description.Replace("{6}",$control.ControlResults[0].VerificationResult)
				if($this.LogMessage($control)){
					$Description+="<hr></br><b>Some other details for your reference</b> </br><hr> {7} "
					$log=$this.LogMessage($control).Replace("\","\\")
					$Description=$Description.Replace("{7}",$log)
				}
				
				$History = "Default History"
				$Severity=$this.GetSeverity($control.ControlItem.ControlSeverity)
				$AssignedTo = $this.GetAssignee($control.ResourceContext.ResourceTypeName,$control.ResourceContext.ResourceName)
				
				if($this.ControlStateExt.InvocationContext.BoundParameters["AreaPath"] -ne $null){
					$AreaPath=$this.ControlStateExt.InvocationContext.BoundParameters["AreaPath"]
				}
				else{
					if($this.ControlSettings.BugLogAreaPath -eq "Root"){
						$AreaPath=$ProjectName
					}
					else{
						$AreaPath=$this.ControlSettings.BugLogAreaPath
					}
				}
				if($this.ControlStateExt.InvocationContext.BoundParameters["IterationPath"] -ne $null){
					$IterationPath=$this.ControlStateExt.InvocationContext.BoundParameters["IterationPath"]
				}
				else{
					if($this.ControlSettings.BugLogIterationPath -eq "Root"){
						$IterationPath=$ProjectName
					}
					else{
						$IterationPath=$this.ControlSettings.BugLogIterationPath
					}
				}
				$AreaPath=$AreaPath.Replace("\","\\")
				$IterationPath=$IterationPath.Replace("\","\\")
				$RepoSteps="abs"

				
				

				$this.AddWorkItem($Title, $Description, $History, $AssignedTo, $AreaPath, $IterationPath, $RepoSteps,$Severity,$ProjectName,$control)
				#$control.ControlResults.AddMessage("Auto bug logging",$this.LogMessage($control))

		}
	}

	}

	hidden [string] LogMessage([SVTEventContext[]] $ControlResult){
	$log=""
		$Messages=$ControlResult.ControlResults[0].Messages

		$Messages | ForEach-Object {
			if($_.Message){
				$log+="<b>$($_.Message)</b> </br></br>"
			}
			if($_.DataObject){
				$log+="<hr>"

					$logs=[Helpers]::ConvertObjectToString($_,$false)
					$logs=$logs.Replace("`"","'")
					
					$log+= "$($logs) </br></br>"
					
					
					
					
				
			}
		}
		$log.Replace("\","\\")

		return $log
	}

	hidden [bool] CheckValidLog([SVTEventContext[]] $ControlResult){
		switch -regex ($ControlResult.FeatureName){
			'Organization' {
				if(!($this.GetHostProject($ControlResult))){
					return $false
				}				
			}
			'Project' {
				if(!$this.ControlStateExt.GetControlStatePermission($ControlResult.FeatureName,$ControlResult.ResourceContext.ResourceName)){
					Write-Host "`nYou do not have permissions to log bugs. Make sure you are a Project Admin" -ForegroundColor Red
					return $false
				}
			}
			'AgentPool'{
				return $true
			}
		}
		return $true
	}

	hidden [string] GetHostProject([SVTEventContext[]] $ControlResult){
		$Project=$null
		if ($this.InvocationContext.BoundParameters["AttestationHostProjectName"]) 
		        	{
		        		if($this.ControlStateExt.GetControlStatePermission("Organization", ""))
		        		{ 
		        			$this.ControlStateExt.SetProjectInExtForOrg()	
		        		}
		        		else {
							Write-Host "Error: Could not configure host project for organization controls auto bug log.`nThis may be because: `n  (a) You may not have correct privilege (requires 'Project Collection Administrator').`n  (b) You are logged in using PAT (which is not supported for this currently)." -ForegroundColor Red
							return $Project
		        		}
					}
					if(!$this.ControlStateExt.GetControlStatePermission("Resource", "microsoftit") )
					{
					  Write-Host "Error: Auto bug logging denied.`nThis may be because: `n  (a) You are attempting to log bugs for areas you do not have RBAC permission to.`n  (b) You are logged in using PAT (currently not supported for organization and project control's bug logging)." -ForegroundColor Red
					  return $Project
					  
					}
					if(!$this.ControlStateExt.GetProject())
				    { 
						Write-Host "`nNo project defined to store bugs for organization-specific controls." -ForegroundColor Red
						Write-Host "Use the '-AttestationHostProjectName' parameter with this command to configure the project that will host bug logging details for organization level controls.`nRun 'Get-Help -Name Get-AzSKAzureDevOpsSecurityStatus -Full' for more info." -ForegroundColor Yellow
						return $Project
					}
					$Project=$this.ControlStateExt.GetProject()
					return $Project


	}

	hidden [string] GetAssignee([string] $ResourceType,[string] $resourceName){

		$Assignee="";
		switch -regex ($ResourceType) {
			'ServiceConnection' {
				$Assignee=$this.ResourceContext.ResourceDetails.createdBy.uniqueName

			}
			'AgentPool'{
				$apiurl="https://dev.azure.com/{0}/_apis/distributedtask/pools?poolName={1}&api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $resourceName
				$response=[WebRequestHelper]::InvokeGetWebRequest($apiurl)
				$Assignee=$response.createdBy.uniqueName

			}
			'Build'{
				$definitionId=($this.ResourceContext.ResourceDetails.ResourceLink -split "=")[1]
				$apiurl="https://dev.azure.com/{0}/{1}/_apis/build/builds?definitions={2}&api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $this.ResourceContext.ResourceGroupName ,$definitionId;
				$response=[WebRequestHelper]::InvokeGetWebRequest($apiurl)

				if([Helpers]::CheckMember($response,"requestedBy")){
					$Assignee=$response[0].requestedBy.uniqueName
				}
				
				else{
					$apiurl="https://dev.azure.com/{0}/{1}/_apis/build/definitions/{2}?api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $this.ResourceContext.ResourceGroupName ,$definitionId;
					$response=[WebRequestHelper]::InvokeGetWebRequest($apiurl)
					$Assignee=$response.authoredBy.uniqueName
				}


			}
			'Release'{
				$definitionId=($this.ResourceContext.ResourceId -split "definitions/")[1]
				$apiurl="https://vsrm.dev.azure.com/{0}/{1}/_apis/release/releases?definitionId={2}&api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $this.ResourceContext.ResourceGroupName ,$definitionId;
				$response=[WebRequestHelper]::InvokeGetWebRequest($apiurl)

				if([Helpers]::CheckMember($response,"modifiedBy")){
					$Assignee=$response[0].modifiedBy.uniqueName
				}
				
				else{
					$apiurl="https://vsrm.dev.azure.com/{0}/{1}/_apis/release/definitions/{2}?&api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $this.ResourceContext.ResourceGroupName ,$definitionId;
					$response=[WebRequestHelper]::InvokeGetWebRequest($apiurl)
					$Assignee=$response.createdBy.uniqueName
				}


			}
			'Organization'{
				$Assignee = [ContextHelper]::GetCurrentSessionUser();
			}
			'Project'{
				$Assignee = [ContextHelper]::GetCurrentSessionUser();

			}
		}
		return $Assignee;

	}

	hidden [string] GetSeverity([string] $ControlSeverity){
		$Severity=""
		switch -regex ($ControlSeverity) {
			'Critical'{
				$Severity="1 - Critical"
			}
			'High' {
				$Severity="2 - High"
			}
			'Medium'{
				$Severity="3 - Medium"
			}
			'Low'{
				$Severity="4 - Low"
			}

		}

		return $Severity
	}

	hidden [void] AddWorkItem([string] $Title, [string] $Description, [string] $History, [string] $AssignedTo, [string] $AreaPath, [string] $IterationPath, [string] $RepoSteps,[string]$Severity,[string]$ProjectName,[SVTEventContext[]] $control )
    {
		$workItem=$this.GetWorkItem($Title,$ProjectName)
        if (!$workItem) {
			$apiurl='https://dev.azure.com/{0}/{1}/_apis/wit/workitems/$bug?api-version=5.1' -f $($this.SubscriptionContext.SubscriptionName), $ProjectName;

			
            
			$post=@"

			[
				{
				  "op": "add",
				  "path": "/fields/System.Title",
				  "from": null,
				  "value": "$Title"
				},
				{
				  "op": "add",
				  "path": "/fields/Microsoft.VSTS.TCM.ReproSteps",
				  "from": null,
				  "value": "$Description"
				},
				{
					"op":"add",
					"path":"/fields/Microsoft.VSTS.Common.Severity",
					"from": null,
					"value":"$Severity"
				},
				{
					"op":"add",
					"path":"/fields/System.AssignedTo",
					"from": null,
					"value":"$AssignedTo"
				},
				{
					"op":"add",
					"path":"/fields/System.AreaPath",
					"from": null,
					"value":"$AreaPath"
				},
				{
					"op":"add",
					"path":"/fields/System.IterationPath",
					"from": null,
					"value":"$IterationPath"
				}
			  ]
"@

				
            
            try{
                $header = $this.GetAuthHeaderFromUriPatch($apiurl)
				$responseObj =  Invoke-RestMethod -Uri $apiurl -Method Post -ContentType "application/json-patch+json ; charset=utf-8" -Headers $header -Body $post
				#$responseObj = [WebRequestHelper]::InvokePostWebRequest($apiurl,$post);
				$control.ControlResults.AddMessage("New Bug",$responseObj.url)
				$this.PublishCustomMessage("`nBug has been logged with title: "+ $Title + "`n");
            }
            catch{
                Write-Host $_;
            }
		}
		else{
			$url=$workItem
			$response=[WebRequestHelper]::InvokeGetWebRequest($url);
			if($response[0].fields.'System.State' -eq "Resolved"){
				$url="https://dev.azure.com/{0}/{1}/_apis/wit/workitems/{2}?api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $ProjectName, $response[0].id
				$body=@"
				[
				{
				  "op": "add",
				  "path": "/fields/System.State",
				  "from": null,
				  "value": "Active"
				}
				]

"@
				try{
					$header = $this.GetAuthHeaderFromUriPatch($url)
					$responseObj =  Invoke-RestMethod -Uri $url -Method Patch -ContentType "application/json-patch+json ; charset=utf-8" -Headers $header -Body $body
					#$responseObj = [WebRequestHelper]::InvokePostWebRequest($apiurl,$post);
					$control.ControlResults.AddMessage("Resolved Bug",$url)

					$this.PublishCustomMessage("`nBug has been logged with title: "+ $Title + "`n");
				}
				catch{
					Write-Host $_;
				}


			}
			else{
				$control.ControlResults.AddMessage("Active Bug",$url)
			}



		}
	}
	

    hidden [string] GetWorkItem([string] $Title,[string] $ProjectName)
    {
		$apiurl='https://dev.azure.com/{0}/{1}/_apis/wit/wiql?api-version=5.1' -f $($this.SubscriptionContext.SubscriptionName), $ProjectName;
		$result=$null
		try{
			if($this.ControlSettings.ResolvedBugLogBehaviour -ne "Update Existing"){
				$WIQL_query = "Select [System.Id], [System.Title], [System.State] From WorkItems Where [System.WorkItemType] = 'Bug' AND [System.Title] EVER '"+ $Title +"' AND ([State] = 'New' OR [State] = 'Active') AND [System.TeamProject] ='"+ $ProjectName +"'"
			}
			else{
            $WIQL_query = "Select [System.Id], [System.Title], [System.State] From WorkItems Where [System.WorkItemType] = 'Bug' AND [System.Title] EVER '"+ $Title +"' AND ([State] = 'New' OR [State] = 'Active' OR [State]='Resolved') AND [System.TeamProject] ='"+ $ProjectName +"'"
			}
			$body = @{ query = $WIQL_query }
            $bodyJson = @($body) | ConvertTo-Json

            $header = $this.GetAuthHeaderFromUriPatch($apiurl)
            $response = Invoke-RestMethod -Uri $apiurl -headers $header -Method Post -ContentType "application/json" -Body $bodyJson
			#$response= [WebRequestHelper]::InvokePostWebRequest($apiurl,$bodyJson);
			if ($response -and $response.workItems.Count -gt 0) {
				$result=$response.workItems[0].url
                return $result;
            }
            else {
				
                return $result;
            }
        }
        catch{
            Write-Host $_;
            return $result;
        }
        
    }

    hidden [Hashtable] GetAuthHeaderFromUriPatch([string] $uri)
    {
        [System.Uri] $validatedUri = $null;
        if([System.Uri]::TryCreate($uri, [System.UriKind]::Absolute, [ref] $validatedUri))
        {

            $token = [ContextHelper]::GetAccessToken($validatedUri.GetLeftPart([System.UriPartial]::Authority));

            $user = ""
            $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$token)))
            return @{
                "Authorization"= ("Basic " + $base64AuthInfo)
            };
        }
        return @{};
    }
}
