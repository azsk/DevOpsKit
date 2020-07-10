using namespace System.Management.Automation
Set-StrictMode -Version Latest 
class SVTControlAttestation 
{
	[SVTEventContext[]] $ControlResults = $null
	hidden [bool] $dirtyCommitState = $false;
	hidden [bool] $abortProcess = $false;
	hidden [ControlStateExtension] $controlStateExtension = $null;
	hidden [AttestControls] $AttestControlsChoice;
	hidden [bool] $bulkAttestMode = $false;
	[AttestationOptions] $attestOptions;
	hidden [PSObject] $ControlSettings ; 
	hidden [SubscriptionContext] $SubscriptionContext;
    hidden [InvocationInfo] $InvocationContext;

	SVTControlAttestation([SVTEventContext[]] $ctrlResults, [AttestationOptions] $attestationOptions, [SubscriptionContext] $subscriptionContext, [InvocationInfo] $invocationContext)
	{
		$this.SubscriptionContext = $subscriptionContext;
		$this.InvocationContext = $invocationContext;
		$this.ControlResults = $ctrlResults;
		$this.AttestControlsChoice = $attestationOptions.AttestControls;
		$this.attestOptions = $attestationOptions;
		$this.controlStateExtension = [ControlStateExtension]::new($this.SubscriptionContext, $this.InvocationContext)
		$this.controlStateExtension.UniqueRunId = $(Get-Date -format "yyyyMMdd_HHmmss");
		$this.controlStateExtension.Initialize($true)
		$this.ControlSettings=$ControlSettingsJson = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");
	}

	[AttestationStatus] GetAttestationValue([string] $AttestationCode)
	{
		switch($AttestationCode.ToUpper())
		{
			"1" { return [AttestationStatus]::NotAnIssue;}
			"2" { return [AttestationStatus]::WillNotFix;}
			"3" { return [AttestationStatus]::WillFixLater;}
			"4" { return [AttestationStatus]::ApprovedException;}
			"5" { return [AttestationStatus]::NotApplicable;}
			"6" { return [AttestationStatus]::StateConfirmed;}			
			"9" { 
					$this.abortProcess = $true;
					return [AttestationStatus]::None;
				}			
			Default { return [AttestationStatus]::None;}
		}
		return [AttestationStatus]::None
	}

	[ControlState] ComputeEffectiveControlState([ControlState] $controlState, [string] $ControlSeverity, [bool] $isSubscriptionControl, [SVTEventContext] $controlItem, [ControlResult] $controlResult)
	{
		Write-Host "$([Constants]::SingleDashLine)" -ForegroundColor Cyan
		Write-Host "ControlId            : $($controlState.ControlId)`nControlSeverity      : $ControlSeverity`nDescription          : $($controlItem.ControlItem.Description)`nCurrentControlStatus : $($controlState.ActualVerificationResult)`n"		
		if(-not $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess)
		{
			Write-Host "Skipping attestation process for this control. You do not have required permissions to evaluate this control. `nNote: If your permissions were elevated recently, please run the 'Disconnect-AzAccount' command to clear the Azure cache and try again." -ForegroundColor Yellow
			if($controlItem.ControlItem.Tags.Contains("KeySecretPermissions"))
			{
				Write-Host "(Please note that you must have access permissions to the keys & secrets in the key vault for successful attestation of this control)" -ForegroundColor Yellow
			}
			Write-Host ([Constants]::CoAdminElevatePermissionMsg) -ForegroundColor Yellow
			return $controlState;
		}
		if(-not $this.isControlAttestable($controlItem, $controlResult))
		{
			Write-Host "This control cannot be attested by policy. Please follow the steps in 'Recommendation' for the control in order to fix the control and minimize exposure to attacks." -ForegroundColor Yellow
			return $controlState;
		}
		$userChoice = ""
		$isPrevAttested = $false;
		if($controlResult.AttestationStatus -ne [AttestationStatus]::None)
		{
			$isPrevAttested = $true;
		}
		$tempCurrentStateObject = $null;
		if($null -ne $controlResult.StateManagement -and $null -ne $controlResult.StateManagement.CurrentStateData)
		{
			$tempCurrentStateObject  = $controlResult.StateManagement.CurrentStateData;
		}

		#display the current state only if the state object is not empty
		if($null -ne $tempCurrentStateObject -and $null -ne $tempCurrentStateObject.DataObject)
		{
			Write-Host "Configuration data to be attested:" -ForegroundColor Cyan
			Write-Host "$([JsonHelper]::ConvertToPson($tempCurrentStateObject.DataObject))"
		}

		if($isPrevAttested -and ($this.AttestControlsChoice -eq [AttestControls]::All -or $this.AttestControlsChoice -eq [AttestControls]::AlreadyAttested))
		{
			#Compute the effective attestation status for support backward compatibility
			$tempAttestationStatus = $controlState.AttestationStatus
			#ToDo: Check in DB if 'NotFixed' exists; Capture Timestamp; Remove following if condition code
			if($controlState.AttestationStatus -eq [AttestationStatus]::NotFixed)
			{
				$tempAttestationStatus = [AttestationStatus]::WillNotFix;
			}
			while($userChoice -ne '0' -and $userChoice -ne '1' -and $userChoice -ne '2' -and $userChoice -ne '9' )
			{
				Write-Host "Existing attestation details:" -ForegroundColor Cyan
				Write-Host "Attestation Status: $tempAttestationStatus`nVerificationResult: $($controlState.EffectiveVerificationResult)`nAttested By       : $($controlState.State.AttestedBy)`nJustification     : $($controlState.State.Justification)`n"
				Write-Host "Please select an action from below: `n[0]: Skip`n[1]: Attest`n[2]: Clear Attestation" -ForegroundColor Cyan
				$userChoice = Read-Host "User Choice"
				if(-not [string]::IsNullOrWhiteSpace($userChoice))
				{
					$userChoice = $userChoice.Trim();
				}
			}
		}
		else
		{
			while($userChoice -ne '0' -and $userChoice -ne '1' -and $userChoice -ne '9' )
			{
				Write-Host "Please select an action from below: `n[0]: Skip`n[1]: Attest" -ForegroundColor Cyan
				$userChoice = Read-Host "User Choice"
				if(-not [string]::IsNullOrWhiteSpace($userChoice))
				{
					$userChoice = $userChoice.Trim();
				}
			}
		}
		$Justification=""
		$Attestationstate=""
		$message = ""
		[PSObject] $ValidAttestationStatesHashTable = $this.ComputeEligibleAttestationStates($controlItem, $controlResult);
		[String[]]$ValidAttestationKey = @(0)
		#Sort attestation status based on key value
		if($null -ne $ValidAttestationStatesHashTable)
		{
			$ValidAttestationStatesHashTable | ForEach-Object {
				$message += "`n[{0}]: {1}" -f $_.Value,$_.Name;
				$ValidAttestationKey += $_.Value
			}
		}
		switch ($userChoice.ToUpper()){
			"0" #None
			{				
							
			}
			"1" #Attest
			{
				$attestationState = ""
				while($attestationState -notin [String[]]($ValidAttestationKey) -and $attestationState -ne '9' )
				{
					Write-Host "`nPlease select an attestation status from below: `n[0]: Skip$message" -ForegroundColor Cyan
					$attestationState = Read-Host "User Choice"
					$attestationState = $attestationState.Trim();
				}
				$attestValue = $this.GetAttestationValue($attestationState);
				if($attestValue -ne [AttestationStatus]::None)
				{
					$controlState.AttestationStatus = $attestValue;
				}
				elseif($this.abortProcess)
				{
					return $null;
				}
				elseif($attestValue -eq [AttestationStatus]::None)
				{
					return $controlState;
				}
				#In case when the user selects ApprovedException as the reason for attesting,
				#they'll be prompted to provide the number of days till that approval expires.
				$exceptionApprovalExpiryDate = ""
				if($controlState.AttestationStatus -eq [AttestationStatus]::ApprovedException)
				{
					#Write-Host "`nPlease provide the number of days for which the exception has been approved (max 180 days):" -ForegroundColor Cyan
					#$numberOfDays = Read-Host "No. of days (default 180)"
					if([string]::IsNullOrWhiteSpace($this.attestOptions.ApprovedExceptionExpiryDate))
					{
						Write-Host "To attest control using ApprovedException status add ApprovedExceptionExpiryDate parameter. Please provide this param in the command with mm/dd/yy date format. For example: -ApprovedExceptionExpiryDate '11/25/20'" -ForegroundColor Yellow;
						break;
					}
					else{
						try
						{					
							[datetime]$ExpiryDate = $this.attestOptions.ApprovedExceptionExpiryDate
							$maxAllowedExceptionApprovalExpiryDate = ([DateTime]::UtcNow).AddDays($this.ControlSettings.DefaultAttestationPeriodForExemptControl)	

							if(-not [string]::IsNullOrWhiteSpace($ExpiryDate))
							{
								#$controlItem.ControlItem.AttestationExpiryPeriodInDays = $numberOfDays.Trim()							
								$proposedExceptionApprovalExpiryDate = $ExpiryDate
								#([DateTime]::UtcNow).AddDays($numberOfDays)

								if($proposedExceptionApprovalExpiryDate -le [DateTime]::UtcNow) 
								{
									Write-Host "ExpiryDate should be greater than current date. To attest control using ApprovedException status add ApprovedExceptionExpiryDate parameter. Please provide this param in the command with mm/dd/yy date format. For example: -ApprovedExceptionExpiryDate '11/25/20'" -ForegroundColor Yellow;
									break;
								}
								elseif($proposedExceptionApprovalExpiryDate -gt $maxAllowedExceptionApprovalExpiryDate)
								{
									Write-Host "`nNote: The exception approval expiry will be set to 180 days from today.`n" -ForegroundColor Yellow
									$exceptionApprovalExpiryDate = $maxAllowedExceptionApprovalExpiryDate								
								}
								else
								{
									$exceptionApprovalExpiryDate = $proposedExceptionApprovalExpiryDate
								}
							}
							else
							{
								Write-Host "`nNote: The exception approval expiry will be set to 180 days from today.`n" -ForegroundColor Yellow
								$exceptionApprovalExpiryDate = $maxAllowedExceptionApprovalExpiryDate
							}
						}
						catch
						{
							Write-Host "`nThe date need to be in  mm/dd/yy format. For example: 11/25/20." -ForegroundColor Red
							throw $_.Exception
						}
					}
				}
				
				if($controlState.AttestationStatus -ne [AttestationStatus]::None)
				{
					$Justification = ""
					while([string]::IsNullOrWhiteSpace($Justification))
					{
						$Justification = Read-Host "Justification"
						try
						{
							$SanitizedJustification = [System.Text.UTF8Encoding]::ASCII.GetString([System.Text.UTF8Encoding]::ASCII.GetBytes($Justification));
							$Justification = $SanitizedJustification;
						}
						catch
						{ 
							# If the justification text is empty then prompting message again to provide justification text.
						}
						if([string]::IsNullOrWhiteSpace($Justification))
						{
							Write-Host "`nEmpty space or blank justification is not allowed."
						}
					}					
					$this.dirtyCommitState = $true
				}
				$controlState.EffectiveVerificationResult = [Helpers]::EvaluateVerificationResult($controlState.ActualVerificationResult,$controlState.AttestationStatus);
				
				$controlState.State = $tempCurrentStateObject

				if($null -eq $controlState.State)
				{
					$controlState.State = [StateData]::new();
				}

				$controlState.State.AttestedBy = [ContextHelper]::GetCurrentSessionUser();
				$controlState.State.AttestedDate = [DateTime]::UtcNow;
				$controlState.State.Justification = $Justification
				
				#In case of control exemption, calculating the exception approval(attestation) expiry date beforehand,
				#based on the days entered by the user (default 6 months)
				if($controlState.AttestationStatus -eq [AttestationStatus]::ApprovedException)
				{
					$controlState.State.ExpiryDate = $exceptionApprovalExpiryDate.ToString("MM/dd/yyyy");
				}
				break;
			}
			"2" #Clear Attestation
			{
				$this.dirtyCommitState = $true
				#Clears the control state. This overrides the previous attested controlstate.
				$controlState.State = $null;
				$controlState.EffectiveVerificationResult = $controlState.ActualVerificationResult
				$controlState.AttestationStatus = [AttestationStatus]::None
			}
			"9" #Abort
			{
				$this.abortProcess = $true;
				return $null;
			}
			Default
			{

			}
		}

		return $controlState;
	}

	[ControlState] ComputeEffectiveControlStateInBulkMode([ControlState] $controlState, [string] $ControlSeverity, [bool] $isSubscriptionControl, [SVTEventContext] $controlItem, [ControlResult] $controlResult)
	{
		Write-Host "$([Constants]::SingleDashLine)" -ForegroundColor Cyan		
		Write-Host "ControlId            : $($controlState.ControlId)`nControlSeverity      : $ControlSeverity`nDescription          : $($controlItem.ControlItem.Description)`nCurrentControlStatus : $($controlState.ActualVerificationResult)`n"
		if(-not $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess)
		{
			Write-Host "Skipping attestation process for this control. You do not have required permissions to evaluate this control. `nNote: If your permissions were elevated recently, please run the 'Disconnect-AzAccount' command to clear the Azure cache and try again." -ForegroundColor Yellow
			if($controlItem.ControlItem.Tags.Contains("KeySecretPermissions"))
			{
				Write-Host "(Please note that you must have access permissions to the keys & secrets in the key vault for successful attestation of this control)" -ForegroundColor Yellow
			}
			Write-Host ([Constants]::CoAdminElevatePermissionMsg) -ForegroundColor Yellow
			return $controlState;
		}
		$userChoice = ""
		if($null -ne $this.attestOptions -and $this.attestOptions.IsBulkClearModeOn)
		{
			if($controlState.AttestationStatus -ne [AttestationStatus]::None)
			{				
				$this.dirtyCommitState = $true
				#Compute the effective attestation status for support backward compatibility
				$tempAttestationStatus = $controlState.AttestationStatus
				if($controlState.AttestationStatus -eq [AttestationStatus]::NotFixed)
				{
					$tempAttestationStatus = [AttestationStatus]::WillNotFix;
				}
				Write-Host "Existing attestation details:" -ForegroundColor Cyan
				Write-Host "Attestation Status: $tempAttestationStatus`nVerificationResult: $($controlState.EffectiveVerificationResult)`nAttested By       : $($controlState.State.AttestedBy)`nJustification     : $($controlState.State.Justification)`n"
			}			
			#Clears the control state. This overrides the previous attested controlstate.
			$controlState.State = $null;
			$controlState.EffectiveVerificationResult = $controlState.ActualVerificationResult
			$controlState.AttestationStatus = [AttestationStatus]::None
			return $controlState;
		}
		$ValidAttestationStatesHashTable = $this.ComputeEligibleAttestationStates($controlItem, $controlResult);
		#Checking if control is attestable 
       
		if($this.isControlAttestable($controlItem, $controlResult))
		{	# Checking if the attestation state provided in command parameter is valid for the control
			if( $this.attestOptions.AttestationStatus -in $ValidAttestationStatesHashTable.Name)
			{
			
						$controlState.AttestationStatus = $this.attestOptions.AttestationStatus;
						$controlState.EffectiveVerificationResult = [Helpers]::EvaluateVerificationResult($controlState.ActualVerificationResult,$controlState.AttestationStatus);

				#In case when the user selects ApprovedException as the reason for attesting,
				#they'll be prompted to provide the number of days till that approval expires.
				$exceptionApprovalExpiryDate = ""
				if($controlState.AttestationStatus -eq "ApprovedException")
				{
					#Write-Host "`nPlease provide the number of days for which the exception has been approved (max 180 days):" -ForegroundColor Cyan
					#$numberOfDays = Read-Host "No. of days (default 180)"

					if([string]::IsNullOrWhiteSpace($this.attestOptions.ApprovedExceptionExpiryDate))
					{
						Write-Host "To attest control using ApprovedException status add ApprovedExceptionExpiryDate parameter. Please provide this param in the command with mm/dd/yy date format. For example: -ApprovedExceptionExpiryDate '11/25/20'" -ForegroundColor Yellow;
						break;
					}
					else{

						try
						{						
							[datetime]$ExpiryDate = $this.attestOptions.ApprovedExceptionExpiryDate
							$maxAllowedExceptionApprovalExpiryDate = ([DateTime]::UtcNow).AddDays($this.ControlSettings.DefaultAttestationPeriodForExemptControl)

							if(-not [string]::IsNullOrWhiteSpace($ExpiryDate))
							{
								#$controlItem.ControlItem.AttestationExpiryPeriodInDays = $numberOfDays.Trim()							
								$proposedExceptionApprovalExpiryDate = $ExpiryDate
								#([DateTime]::UtcNow).AddDays($numberOfDays)

								if($proposedExceptionApprovalExpiryDate -le [DateTime]::UtcNow) 
								{
									Write-Host "ExpiryDate should be greater than current date. To attest control using ApprovedException status add ApprovedExceptionExpiryDate parameter. Please provide this param in the command with mm/dd/yy date format. For example: -ApprovedExceptionExpiryDate '11/25/20'" -ForegroundColor Yellow;
									break;
								}
								elseif($proposedExceptionApprovalExpiryDate -gt $maxAllowedExceptionApprovalExpiryDate)
								{
									Write-Host "`nNote: The exception approval expiry will be set to 180 days from today.`n" -ForegroundColor Yellow
									$exceptionApprovalExpiryDate = $maxAllowedExceptionApprovalExpiryDate								
								}
								else
								{
									$exceptionApprovalExpiryDate = $proposedExceptionApprovalExpiryDate
								}
							}
							else
							{
								Write-Host "`nNote: The exception approval expiry will be set to 180 days from today.`n" -ForegroundColor Yellow
								$exceptionApprovalExpiryDate = $maxAllowedExceptionApprovalExpiryDate
							}
						}
						catch
						{
							Write-Host "`nThe date need to be in  mm/dd/yy format. For example: 11/25/20." -ForegroundColor Red
							throw $_.Exception
						}
					}
				}
				
						if($null -ne $controlResult.StateManagement -and $null -ne $controlResult.StateManagement.CurrentStateData)
						{
							$controlState.State = $controlResult.StateManagement.CurrentStateData;
						}

						if($null -eq $controlState.State)
						{
							$controlState.State = [StateData]::new();
						}
						$this.dirtyCommitState = $true
						$controlState.State.AttestedBy = [ContextHelper]::GetCurrentSessionUser();
						$controlState.State.AttestedDate = [DateTime]::UtcNow;
						$controlState.State.Justification = $this.attestOptions.JustificationText
						
				#In case of control exemption, calculating the exception approval(attestation) expiry date beforehand,
				#based on the days entered by the user (default 6 months)
				if($controlState.AttestationStatus -eq [AttestationStatus]::ApprovedException)
				{
					$controlState.State.ExpiryDate = $exceptionApprovalExpiryDate.ToString("MM/dd/yyyy");
				}
			}
			#if attestation state provided in command parameter is not valid for the control then print warning
			else
			{
				$outvalidSet=$ValidAttestationStatesHashTable.Name -join "," ;
				Write-Host "The chosen attestation state is not applicable to this control. Valid attestation choices are:  $outvalidSet" -ForegroundColor Yellow;
				return $controlState ;
			}
		}
		#If control is not attestable then print warning
		else
		{
			Write-Host "This control cannot be attested by policy. Please follow the steps in 'Recommendation' for the control in order to fix the control and minimize exposure to attacks." -ForegroundColor Yellow;
		}
		return $controlState;
	}
	
	[void] StartControlAttestation()
	{
	
		$Global:AttestationValue = $false
		try
		{
			#user provided justification text would be available only in bulk attestation mode.
			if($null -ne $this.attestOptions -and  (-not [string]::IsNullOrWhiteSpace($this.attestOptions.JustificationText) -or $this.attestOptions.IsBulkClearModeOn))
			{
				$this.bulkAttestMode = $true;				
					Write-Host "$([Constants]::SingleDashLine)" -ForegroundColor Yellow				
			}
			else
			{
				Write-Host ("$([Constants]::SingleDashLine)`nNote: Enter 9 during any stage to exit the attestation workflow. This will abort attestation process for the current resource and remaining resources.`n$([Constants]::SingleDashLine)") -ForegroundColor Yellow
			}
			
			if($null -eq $this.ControlResults)
			{
				Write-Host "No control results found." -ForegroundColor Yellow
			}
			$this.abortProcess = $false;
			#filtering the controls - Removing all the passed controls
			#Step1 Group By IDs		

			$filteredControlResults = @()
			$filteredControlResults += $this.ControlResults | Group-Object { $_.GetUniqueId() }

			if((($filteredControlResults | Measure-Object).Count -eq 1 -and ($filteredControlResults[0].Group | Measure-Object).Count -gt 0 -and $null -ne $filteredControlResults[0].Group[0].ResourceContext) `
				-or ($filteredControlResults | Measure-Object).Count -gt 1)
			{
				Write-Host "No. of candidate resources for the attestation: $($filteredControlResults.Count)" -ForegroundColor Cyan
			}
		
			#show warning if the keys count is greater than certain number.
			$counter = 0
			#start iterating resource after resource
			foreach($resource in  $filteredControlResults)
			{
				$resourceValueKey = $resource.Name
				$this.dirtyCommitState = $false;
				$resourceValue = $resource.Group;		
				$isSubscriptionScan = $false;
				$counter = $counter + 1
				if(($resourceValue | Measure-Object).Count -gt 0)
				{
					$SubscriptionId = $resourceValue[0].SubscriptionContext.SubscriptionId
					if($null -ne $resourceValue[0].ResourceContext)
					{
						$ResourceId = $resourceValue[0].ResourceContext.ResourceId
						Write-Host $([String]::Format([Constants]::ModuleAttestStartHeading, $resourceValue[0].FeatureName, $resourceValue[0].ResourceContext.ResourceGroupName, $resourceValue[0].ResourceContext.ResourceName, $counter, $filteredControlResults.Count)) -ForegroundColor Cyan
					}
					else
					{
						$isSubscriptionScan = $true;
						Write-Host $([String]::Format([Constants]::ModuleAttestStartHeadingSub, $resourceValue[0].FeatureName, $resourceValue[0].SubscriptionContext.SubscriptionName, $resourceValue[0].SubscriptionContext.SubscriptionId)) -ForegroundColor Cyan
					}	
					
					[ControlState[]] $resourceControlStates = @()
					$count = 0;
					[SVTEventContext[]] $filteredControlItems = @()
					$resourceValue | ForEach-Object { 
						$controlItem = $_;
						$matchedControlItem = $false;
						if(($controlItem.ControlResults | Measure-Object).Count -gt 0)
						{
							[ControlResult[]] $matchedControlResults = @();
							$controlItem.ControlResults | ForEach-Object {
								$controlResult = $_
								if($controlResult.ActualVerificationResult -ne [VerificationResult]::Passed -and $controlResult.ActualVerificationResult -ne [VerificationResult]::Error)
								{
									if($this.AttestControlsChoice -eq [AttestControls]::All)
									{
										$matchedControlItem = $true;
										$matchedControlResults += $controlResult;
										$count++;
									}
									elseif($this.AttestControlsChoice -eq [AttestControls]::AlreadyAttested -and $controlResult.AttestationStatus -ne [AttestationStatus]::None)
									{
										$matchedControlItem = $true;
										$matchedControlResults += $controlResult;
										$count++;
									}
									elseif($this.AttestControlsChoice -eq [AttestControls]::NotAttested -and  $controlResult.AttestationStatus -eq [AttestationStatus]::None)
									{
										$matchedControlItem = $true;
										$matchedControlResults += $controlResult;
										$count++;
									}									
								}
							}
						}
						if($matchedControlItem)
						{
							$controlItem.ControlResults = $matchedControlResults;
							$filteredControlItems += $controlItem;
						}
					}
					if($count -gt 0)
					{
						Write-Host "No. of controls that need to be attested: $count" -ForegroundColor Cyan

						 foreach( $controlItem in $filteredControlItems)
						 {
							$controlId = $controlItem.ControlItem.ControlID
							$controlSeverity = $controlItem.ControlItem.ControlSeverity
							$controlResult = $null;
							$controlStatus = "";
							$isPrevAttested = $false;
							if(($controlItem.ControlResults | Measure-Object).Count -gt 0)
							{								
								foreach( $controlResult in $controlItem.ControlResults)
								{
									$controlStatus = $controlResult.ActualVerificationResult;
									
									#Default attestation version is 1.0
									$Version = '1.0'
									if ( ([FeatureFlightingManager]::GetFeatureStatus("PreventAttestationStateDrift", $SubscriptionId)))
									{
										if ($this.InvocationContext)
										{
											$Version = [System.Version] ($this.InvocationContext.MyCommand.Version);
										}
									}
									[ControlState] $controlState = [ControlState]::new($controlId,$controlItem.ControlItem.Id,$controlResult.ChildResourceName,$controlStatus,$Version);
									if($null -ne $controlResult.StateManagement -and $null -ne $controlResult.StateManagement.AttestedStateData)
									{								
										$controlState.State = $controlResult.StateManagement.AttestedStateData
									}						
						
									$controlState.AttestationStatus = $controlResult.AttestationStatus
									$controlState.EffectiveVerificationResult = $controlResult.VerificationResult
									$controlState.HashId = [Helpers]::ComputeHash($resourceValueKey.ToLower());
									$controlState.ResourceId = $resourceValueKey;
									if($this.bulkAttestMode)
									{
										$controlState = $this.ComputeEffectiveControlStateInBulkMode($controlState, $controlSeverity, $isSubscriptionScan, $controlItem, $controlResult)										
									}
									else
									{
										$controlState = $this.ComputeEffectiveControlState($controlState, $controlSeverity, $isSubscriptionScan, $controlItem, $controlResult)										
									}									
									$resourceControlStates +=$controlState;
									if($this.abortProcess)
									{
										Write-Host "Aborted the attestation workflow." -ForegroundColor Yellow
										return;
									}
								}
							}
							Write-Host $([Constants]::SingleDashLine) -ForegroundColor Cyan
						}
					}
					else
					{
						Write-Host "No attestable controls found.`n$([Constants]::SingleDashLine)" -ForegroundColor Yellow
					}
					
					#remove the entries which doesn't have any state
					#$resourceControlStates = $resourceControlStates | Where-Object {$_.State}
					#persist the value back to state			
					if($this.dirtyCommitState)
					{
						if(($resourceControlStates | Measure-Object).Count -gt 0)
						{
							$Global:AttestationValue = $true
							Write-Host "Attestation summary for this resource:" -ForegroundColor Cyan
							$output = @()
							$resourceControlStates | ForEach-Object {
								$out = "" | Select-Object ControlId, EvaluatedResult, EffectiveResult, AttestationChoice
								$out.ControlId = $_.ControlId
								$out.EvaluatedResult = $_.ActualVerificationResult
								$out.EffectiveResult = $_.EffectiveVerificationResult
								$out.AttestationChoice = $_.AttestationStatus.ToString()
								$output += $out
							}
							Write-Host ($output | Format-Table ControlId, EvaluatedResult, EffectiveResult, AttestationChoice | Out-String) -ForegroundColor Cyan
						}

						Write-Host "Committing the attestation details for this resource..." -ForegroundColor Cyan
						$this.controlStateExtension.SetControlState($resourceValueKey, $resourceControlStates, $false)
						Write-Host "Commit succeeded." -ForegroundColor Cyan
					}
					
					if($null -ne $resourceValue[0].ResourceContext)
					{
						$ResourceId = $resourceValue[0].ResourceContext.ResourceId
						Write-Host $([String]::Format([Constants]::CompletedAttestAnalysis, $resourceValue[0].FeatureName, $resourceValue[0].ResourceContext.ResourceGroupName, $resourceValue[0].ResourceContext.ResourceName)) -ForegroundColor Cyan
					}
					else
					{
						$isSubscriptionScan = $true;
						Write-Host $([String]::Format([Constants]::CompletedAttestAnalysisSub, $resourceValue[0].FeatureName, $resourceValue[0].SubscriptionContext.SubscriptionName, $resourceValue[0].SubscriptionContext.SubscriptionId)) -ForegroundColor Cyan
					}	
				}
			
			}
		}
		finally
		{
			$folderPath = Join-Path $([Constants]::AzSKAppFolderPath) "Temp" | Join-Path -ChildPath $($this.controlStateExtension.UniqueRunId)
			[Helpers]::CleanupLocalFolder($folderPath);
		}
	}	

	[bool] isControlAttestable([SVTEventContext] $controlItem, [ControlResult] $controlResult)
	{
		# If None is found in array along with other attestation status, 'None' will get precedence.
		if(($controlItem.ControlItem.ValidAttestationStates | Measure-Object).Count -gt 0 -and ($controlItem.ControlItem.ValidAttestationStates | Where-Object { $_.Trim() -eq [AttestationStatus]::None } | Measure-Object).Count -gt 0)
	    { 
            return $false
        }
        else
        {
            return $true
        }
	}

	[PSObject] ComputeEligibleAttestationStates([SVTEventContext] $controlItem, [ControlResult] $controlResult)
	{
	    [System.Collections.ArrayList] $ValidAttestationStates = $null
	    #Default attestation state
	    if($null -ne $this.ControlSettings.DefaultValidAttestationStates){
			$ValidAttestationStates = $this.ControlSettings.DefaultValidAttestationStates | Select-Object -Unique
		}
	    #Additional attestation state
		if($null -ne $controlItem.ControlItem.ValidAttestationStates)
		{ 
			$ValidAttestationStates += $controlItem.ControlItem.ValidAttestationStates | Select-Object -Unique
		}
		$ValidAttestationStates = $ValidAttestationStates.Trim() | Select-Object -Unique
		#Allowing WillFixLater even if control is not grace
		#Changes for compliance table dependency removal
		#if control not in grace, disable WillFixLater option		
		# if(-not $controlResult.IsControlInGrace)
		# {
		#     if(($ValidAttestationStates | Where-Object { $_ -eq [AttestationStatus]::WillFixLater} | Measure-Object).Count -gt 0)
		#     {
		#         $ValidAttestationStates.Remove("WillFixLater")
		#     }
		# }
		$ValidAttestationStatesHashTable = [Constants]::AttestationStatusHashMap.GetEnumerator() | Where-Object { $_.Name -in $ValidAttestationStates } | Sort-Object value
		
		if($this.attestOptions.IsExemptModeOn)
		{
			$ValidAttestationStatesHashTable += [Constants]::AttestationStatusHashMap.GetEnumerator() | Where-Object { $_.Name -eq [AttestationStatus]::ApprovedException }
		}
		
		return $ValidAttestationStatesHashTable;
	}
}
