
Set-StrictMode -Version Latest
class AzSKCfg: SVTBase
{

	AzSKCfg([string] $subscriptionId,[SVTResource] $svtResource):
        Base($subscriptionId,  $svtResource )
    {
       
    }
	hidden [ControlResult] CheckifCAPresent([ControlResult] $controlResult)
	{
		$AutomationAccount=[Constants]::AutomationAccount
		$AzSKRGName=[ConfigurationManager]::GetAzSKConfigData().AzSKRGName

		$caAutomationAccount = Get-AzureRmAutomationAccount -Name  $AutomationAccount -ResourceGroupName $AzSKRGName -ErrorAction SilentlyContinue
		if($caAutomationAccount)
		{
			
			$controlResult.AddMessage([VerificationResult]::Passed,
                                    [MessageData]::new("CA account '$($AutomationAccount)' is present in the subscription."));
        
		}
		else
		{
				$controlResult.AddMessage([VerificationResult]::Failed,
                                    [MessageData]::new("CA account '$($AutomationAccount)' is not present in the subscription."));
    
		}

	return $controlResult
	}

	hidden [ControlResult] CheckHealthofCA([ControlResult] $controlResult)
	{
		$HasGraphAPIAccess = [RoleAssignmentHelper]::HasGraphAccess();
		
		$AutomationAccount=[Constants]::AutomationAccount
		$AzSKRGName=[ConfigurationManager]::GetAzSKConfigData().AzSKRGName
		$AzSKRG = Get-AzureRmResourceGroup -Name $AzSKRGName -ErrorAction SilentlyContinue	
		$stepCount = 0;

		$caAutomationAccount = Get-AzureRmAutomationAccount -Name  $AutomationAccount -ResourceGroupName $AzSKRGName -ErrorAction SilentlyContinue
		if($caAutomationAccount)
		{
			#region: runbook version check
			$stepCount++
			$azskMinReqdRunbookVersion = [ConfigurationManager]::GetAzSKConfigData().AzSKCAMinReqdRunbookVersion
			$azskLatestCARunbookVersion = [ConfigurationManager]::GetAzSKConfigData().AzSKCARunbookVersion
			$azskCurrentCARunbookVersion = ""
			$RunbookVersionTagName="AzSKCARunbookVersion"
			if($null -ne $AzSKRG)
			{
				if(($AzSKRG.Tags | Measure-Object).Count -gt 0 -and $AzSKRG.Tags.ContainsKey($RunbookVersionTagName))
				{
					$azskCurrentCARunbookVersion = $AzSKRG.Tags[$RunbookVersionTagName]
				}
			}
			if(![string]::IsNullOrWhiteSpace($azskCurrentCARunbookVersion) -and ([System.Version]$azskCurrentCARunbookVersion -ge [System.Version]$azskMinReqdRunbookVersion))
			{
				if([System.Version]$azskCurrentCARunbookVersion -ne [System.Version]$azskLatestCARunbookVersion)
				{
						$controlResult.AddMessage([VerificationResult]::Failed,
									    [MessageData]::new("$($stepCount.ToString("00")):CA runbook is not current as per the required latest version. AzSK current runbook version is $([System.Version]$azskCurrentCARunbookVersion) and latest runbook version is $([System.Version]$azskLatestCARunbookVersion)."));
						return $controlResult

				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Passed,
									    [MessageData]::new("$($stepCount.ToString("00")): CA runbook is current as per the required latest version. AzSK current runbook version is $([System.Version]$azskCurrentCARunbookVersion)."));
										
				}
			}
			else
			{
					$controlResult.AddMessage([VerificationResult]::Failed,
									        [MessageData]::new("$($stepCount.ToString("00")): CA Runbook is too old."));
				return	$controlResult			
			}		
	
			#endregion
				
			#region: active schedule
				
			$stepCount++
			$RunbookName=[Constants]::RunbookName
			$activeSchedules = $this.GetActiveSchedules($RunbookName)
			if(($activeSchedules|Measure-Object).Count -eq 0)
			{
					
				$controlResult.AddMessage([VerificationResult]::Failed,
												[MessageData]::new("$($stepCount.ToString("00")): Runbook $($RunbookName) is not scheduled."));
				return	$controlResult			
					
			}		
			else 
			{
				$controlResult.AddMessage([VerificationResult]::Passed,
												[MessageData]::new("$($stepCount.ToString("00")): Active job schedule(s) found."));
			}
			#endregion

			if($HasGraphAPIAccess)
			{	
				#region: Check if service principal is configured and it has at least Security Reader access to subscription and contributor access to "AzSKRG", if either is missing display error message				
				$stepCount++
				$isPassed = $false
				$runAsConnection = $this.GetRunAsConnection()
				if($runAsConnection)
				{			
					$CAAADApplicationID = $runAsConnection.FieldDefinitionValues.ApplicationId
					$spObject = Get-AzureRmADServicePrincipal -ServicePrincipalName $CAAADApplicationID -ErrorAction SilentlyContinue
					$spName=""
					if($spObject){$spName = $spObject.DisplayName}
					$haveSubscriptionRBACAccess = $true;
					$haveRGRBACAccess = $true;
					$subRBACoutputs = @();			
					$haveSubscriptionRBACAccess = $this.CheckServicePrincipalSubscriptionAccess($CAAADApplicationID)
					$haveRGRBACAccess = $this.CheckServicePrincipalRGAccess($CAAADApplicationID)				
			
					if($haveSubscriptionRBACAccess -and $haveRGRBACAccess)
					{
						$controlResult.AddMessage([VerificationResult]::Passed,
													[MessageData]::new("$($stepCount.ToString("00")): RunAs Account is correctly set up."));
						$isPassed = $true
					}
					if(!$isPassed)
					{
						$controlResult.AddMessage([VerificationResult]::Failed,
													[MessageData]::new("$($stepCount.ToString("00")): Service principal account (Name: $($spName)) configured in RunAs Account  doesn't have required access ('Security Reader' and 'Reader' access on Subscription and/or Contributor access on Resource group AzSKRG).."));
						return	$controlResult			
					
					}
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Failed,
													[MessageData]::new("$($stepCount.ToString("00")): RunAs Account does not exist in automation account."));
					return	$controlResult			
				}
				#endregion
			
				#region:Check if certificate expiry is in near future(in next 1 month) or it's expired
				$stepCount++
				$certificateAssetName = "AzureRunAsCertificate"
		
				$runAsCertificate = Get-AzureRmAutomationCertificate -AutomationAccountName  $AutomationAccount `
				-Name $certificateAssetName `
				-ResourceGroupName $AzSKRGName -ErrorAction SilentlyContinue
		
				if($runAsCertificate)
				{
					$runAsConnection = $this.GetRunAsConnection();
					$ADapp = Get-AzureRmADApplication -ApplicationId $runAsConnection.FieldDefinitionValues.ApplicationId -ErrorAction SilentlyContinue
					if(($runAsCertificate.ExpiryTime.UtcDateTime - $(get-date).ToUniversalTime()).TotalDays -le 7)
					{
							$controlResult.AddMessage([VerificationResult]::Failed,
													[MessageData]::new("$($stepCount.ToString("00")): RunAs Certificate is going to expire within next 7 days. Expiry date: $($runAsCertificate.ExpiryTime)."));
						return	$controlResult			
					}
					elseif(($runAsCertificate.ExpiryTime - $(get-date)).TotalDays -gt 0 -and ($runAsCertificate.ExpiryTime - $(get-date)).TotalDays -le 30)
					{
							$controlResult.AddMessage([VerificationResult]::Verify,
													[MessageData]::new("$($stepCount.ToString("00")): RunAs Certificate is going to expire within next 30 days. Expiry date: $($runAsCertificate.ExpiryTime)."));
						return	$controlResult			
					}
					else
					{
							$controlResult.AddMessage([VerificationResult]::Passed,
													[MessageData]::new("$($stepCount.ToString("00")): RunAs Certificate is correctly set up."));
					}
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Failed,
													[MessageData]::new("$($stepCount.ToString("00")): RunAs Certificate does not exist in automation account."));
					return	$controlResult			
				}
				#endregion
			}
			else
			{
				$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
				$controlResult.AddMessage([VerificationResult]::Manual, "Not able to query Graph API. This has to be manually verified.");		
			}	
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Failed,
                            [MessageData]::new("CA account '$($AutomationAccount)' is not present in the subscription."));
		}
		return $controlResult
	}

	hidden [ControlResult] CheckifLatestModulePresent([ControlResult] $controlResult)
	{
		$AzSKModuleName= [Constants]::AzSKModuleName
		$currentModuleVersion= [Constants]::AzSKCurrentModuleVersion
		$serverVersion = [System.Version] ([ConfigurationManager]::GetAzSKConfigData().GetLatestAzSKVersion($AzSKModuleName));

		if($currentModuleVersion -ne $serverVersion)
				{
		
				$controlResult.AddMessage([VerificationResult]::Failed,
                                    [MessageData]::new("Latest AzSK module v.'$($serverVersion)' is not present. The version currently present is '$($currentModuleVersion)'"));
				}
				else
				{
				
				$controlResult.AddMessage([VerificationResult]::Passed,
                                    [MessageData]::new("Latest '$($AzSKModuleName)' module v.'$($currentModuleVersion)' is present"));	
				}
		return $controlResult
	}

	#Check if active schedules
	hidden [PSObject] GetActiveSchedules($runbookName)
	{
		
		$AutomationAccount=[Constants]::AutomationAccount
		$AzSKRGName=[ConfigurationManager]::GetAzSKConfigData().AzSKRGName
		$ScheduleName=[Constants]::ScheduleName
		$runbookSchedulesList = Get-AzureRmAutomationScheduledRunbook -ResourceGroupName $AzSKRGName `
		-AutomationAccountName  $AutomationAccount `
		-RunbookName $runbookName -ErrorAction Stop
		if($runbookSchedulesList)
		{
			$schedules = Get-AzureRmAutomationSchedule -ResourceGroupName $AzSKRGName `
			-AutomationAccountName  $AutomationAccount -Name $ScheduleName  | Where-Object{ $_.Name -eq $ScheduleName}
			$activeSchedule = $schedules | Where-Object{$_.IsEnabled -and `
			$_.Frequency -ne [Microsoft.Azure.Commands.Automation.Model.ScheduleFrequency]::Onetime -and `
			$_.ExpiryTime.UtcDateTime -gt $(get-date).ToUniversalTime()}

			return $activeSchedule
		}
		else
		{
			return $null
		}
	}
	
	hidden [PSObject] GetRunAsConnection()
	{
		
		$AutomationAccount=[Constants]::AutomationAccount
		$AzSKRGName=[ConfigurationManager]::GetAzSKConfigData().AzSKRGName
		$connectionAssetName=[Constants]::connectionAssetName
		$connection = Get-AzureRmAutomationConnection -AutomationAccountName  $AutomationAccount `
			-Name  $connectionAssetName -ResourceGroupName `
			$AzSKRGName -ErrorAction SilentlyContinue
		if((Get-Member -InputObject $connection -Name FieldDefinitionValues -MemberType Properties) -and $connection.FieldDefinitionValues.ContainsKey("ApplicationId"))
		{
			 $connection = $connection|Select-Object Name,Description,ConnectionTypeName,FieldDefinitionValues
			 return $connection
		}
		else
		{
			return $null
		}
	}

	hidden [bool] CheckServicePrincipalRGAccess($applicationId)
	{
		
		$AzSKRGName=[ConfigurationManager]::GetAzSKConfigData().AzSKRGName
		$spPermissions = Get-AzureRmRoleAssignment -serviceprincipalname $applicationId 
		#Check subscription access
		if(($spPermissions|Measure-Object).count -gt 0)
		{
			$haveRGAccess = ($spPermissions | Where-Object {$_.scope -eq (Get-AzureRmResourceGroup -Name $AzSKRGName).ResourceId -and $_.RoleDefinitionName -eq "Contributor"}|measure-object).count -gt 0
			return $haveRGAccess	
		}
		else
		{
			return $false
		}
	
	}
	hidden [bool] CheckServicePrincipalSubscriptionAccess($applicationId)
	{
		#fetch SP permissions
		$spPermissions = Get-AzureRmRoleAssignment -serviceprincipalname $applicationId 
		$currentContext = [Helpers]::GetCurrentRMContext();
		#Check subscription access
		if(($spPermissions|measure-object).count -gt 0)
		{
			$haveSubscriptionAccess = ($spPermissions | Where-Object {$_.scope -eq "/subscriptions/$($currentContext.Subscription.Id)" -and $_.RoleDefinitionName -eq "Security Reader"}|Measure-Object).count -gt 0
			return $haveSubscriptionAccess	
		}
		else
		{
			return $false
		}
	
	}
	
}
