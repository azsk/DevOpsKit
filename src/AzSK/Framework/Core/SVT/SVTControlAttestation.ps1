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
		$this.controlStateExtension.Initialize($true)
	}

	[AttestationStatus] GetAttestationValue([string] $AttestationCode)
	{
		switch($AttestationCode.ToUpper())
		{
			"1" { return [AttestationStatus]::NotAnIssue;}
			"2" { return [AttestationStatus]::WillNotFix;}
			"3" { return [AttestationStatus]::WillFixLater;}
			"4" { return [AttestationStatus]::NotApplicable;}
			"9" { 
					$this.abortProcess = $true;
					return [AttestationStatus]::None;
				}			
			Default { return [AttestationStatus]::None;}
		}
		return [AttestationStatus]::None
	}

	[ControlState] ComputeEffectiveControlState([ControlState] $controlState, [ControlSeverity] $ControlSeverity, [bool] $isSubscriptionControl, [SVTEventContext] $controlItem, [ControlResult] $controlResult)
	{
		Write-Host "$([Constants]::SingleDashLine)" -ForegroundColor Cyan
		Write-Host "ControlId            : $($controlState.ControlId)`nControlSeverity      : $ControlSeverity`nDescription          : $($controlItem.ControlItem.Description)`nCurrentControlStatus : $($controlState.ActualVerificationResult)`n"		
		if(-not $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess)
		{
			Write-Host "Skipping attestation process for this control. You do not have required permissions to evaluate this control." -ForegroundColor Yellow
			Write-Host ([Constants]::CoAdminElevatePermissionMsg) -ForegroundColor Yellow
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
			Write-Host "$([Helpers]::ConvertToPson($tempCurrentStateObject.DataObject))"
		}

		if($isPrevAttested -and ($this.AttestControlsChoice -eq [AttestControls]::All -or $this.AttestControlsChoice -eq [AttestControls]::AlreadyAttested))
		{
			#Compute the effective attestation status for support backward compatibility
			$tempAttestationStatus = $controlState.AttestationStatus
			if($controlState.AttestationStatus -eq [AttestationStatus]::NotFixed)
			{
				$tempAttestationStatus = [AttestationStatus]::WillNotFix;
			}
			if(-not $this.isControlAttestable()){
				while($userChoice -ne '0' -and $userChoice -ne '1' -and $userChoice -ne '2' -and $userChoice -ne '9' )
				{
					Write-Host "Existing attestation details:" -ForegroundColor Cyan
					Write-Host "Attestation Status: $tempAttestationStatus`nVerificationResult: $($controlState.EffectiveVerificationResult)`nAttested By       : $($controlState.State.AttestedBy)`nJustification     : $($controlState.State.Justification)`n"
					Write-Host "Please select an action from below: `n[0]: Skip`n[1]: Attest`n[2]: Clear Attestation" -ForegroundColor Cyan
					$userChoice = Read-Host "User Choice"
					$userChoice = $userChoice.Trim();
				}
			}
			else
			{
				Write-Host "Existing attestation details:" -ForegroundColor Cyan
				Write-Host "Attestation Status: $tempAttestationStatus`nVerificationResult: $($controlState.EffectiveVerificationResult)`nAttested By       : $($controlState.State.AttestedBy)`nJustification     : $($controlState.State.Justification)`n"
				Write-Host "This control can no longer be attested as you have exceed the 90 days attestation policy." -ForegroundColor Cyan
				return $null
			}
		}
		else
		{
			while($userChoice -ne '0' -and $userChoice -ne '1' -and $userChoice -ne '9' )
			{
				Write-Host "Please select an action from below: `n[0]: Skip`n[1]: Attest" -ForegroundColor Cyan
				$userChoice = Read-Host "User Choice"
				$userChoice = $userChoice.Trim();
			}
		}
		$Justification=""
		$Attestationstate=""
		$message = ""
		[String[]]$applicableAttestation = Compare-Object -ReferenceObject ([AttestationStatus].GetEnumNames()) -DifferenceObject $controlItem.ControlItem.InvalidAttestationStates -PassThru | Where-Object {$_.SideIndicator -EQ "<="} | Where-Object {$_ -notin @("None","NotFixed")}
		$applicableAttestation | ForEach-Object { $message += "`n[{0}] {1}" -f ($applicableAttestation.IndexOf($_)+1),$_ }
		$attestationHashtable = @{
			"NotAnIssue" = "1";
			"WillNotFix" = "2";
			"WillFixLater" = "3";
			"NotApplicable" = "4"
		}
		switch ($userChoice.ToUpper()){
			"0" #None
			{				
							
			}
			"1" #Attest
			{
				$attestationState = -1
				while($attestationState -notin 0..($applicableAttestation.Count) -and $attestationState -ne 9 )
				{
					Write-Host "`nPlease select an attestation status from below: `n[0]: Skip$message" -ForegroundColor Cyan
					$attestationState = Read-Host "User Choice"
				}
				if($attestationState -ne 0 -and $attestationState -ne 9){
					$attestationState = $attestationHashtable.($applicableAttestation.GetValue($attestationState-1))
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

				$controlState.State.AttestedBy = [Helpers]::GetCurrentSessionUser();
				$controlState.State.AttestedDate = [DateTime]::UtcNow;
				$controlState.State.Justification = $Justification				
				
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

	[ControlState] ComputeEffectiveControlStateInBulkMode([ControlState] $controlState, [ControlSeverity] $ControlSeverity, [bool] $isSubscriptionControl, [SVTEventContext] $controlItem, [ControlResult] $controlResult)
	{
		Write-Host "$([Constants]::SingleDashLine)" -ForegroundColor Cyan		
		Write-Host "ControlId            : $($controlState.ControlId)`nControlSeverity      : $ControlSeverity`nDescription          : $($controlItem.ControlItem.Description)`nCurrentControlStatus : $($controlState.ActualVerificationResult)`n"
		if(-not $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess)
		{
			Write-Host "Skipping attestation process for this control. You do not have required permissions to evaluate this control." -ForegroundColor Yellow
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
		
		$controlState.AttestationStatus = $this.attestOptions.AttestationStatus;
		$controlState.EffectiveVerificationResult = [Helpers]::EvaluateVerificationResult($controlState.ActualVerificationResult,$controlState.AttestationStatus);
				
		if($null -ne $controlResult.StateManagement -and $null -ne $controlResult.StateManagement.CurrentStateData)
		{
			$controlState.State = $controlResult.StateManagement.CurrentStateData;
		}

		if($null -eq $controlState.State)
		{
			$controlState.State = [StateData]::new();
		}
		$this.dirtyCommitState = $true
		$controlState.State.AttestedBy = [Helpers]::GetCurrentSessionUser();
		$controlState.State.AttestedDate = [DateTime]::UtcNow;
		$controlState.State.Justification = $this.attestOptions.JustificationText				
				
		return $controlState;
	}
	
	[void] StartControlAttestation()
	{
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
								if($controlResult.ActualVerificationResult -ne [VerificationResult]::Passed)
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
								
									[ControlState] $controlState = [ControlState]::new($controlId,$controlItem.ControlItem.Id,$controlResult.ChildResourceName,$controlStatus,"1.0");
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
			$this.controlStateExtension.CleanTempFolder();
		}

	}	

	[bool] isControlAttestable()
	{
		return $false;
	}
}
