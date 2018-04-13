using namespace System.Management.Automation
Set-StrictMode -Version Latest 

# Class to implement Subscription ARM Policy controls 
class ARMPolicy: CommandBase
{    
	hidden [ARMPolicyModel] $ARMPolicyObj = $null;
	
	hidden [PSObject[]] $ApplicableARMPolicies = $null;
	#hidden [PSObject[]] $PolicyAssignments = $null;

	ARMPolicy([string] $subscriptionId, [InvocationInfo] $invocationContext, [string] $tags): 
        Base($subscriptionId, $invocationContext)
    { 
		$this.ARMPolicyObj = [ARMPolicyModel] $this.LoadServerConfigFile("Subscription.ARMPolicies.json"); 
		$this.FilterTags = $this.ConvertToStringArray($tags);
	}

	hidden [PSObject[]] GetApplicableARMPolices()
	{
		if($null -eq $this.ApplicableARMPolicies)
		{
			$this.ApplicableARMPolicies = @();

			$subscriptionId = $this.SubscriptionContext.SubscriptionId;
			if(($this.FilterTags | Measure-Object).Count -ne 0)
			{
				$this.ARMPolicyObj.Policies | 
					ForEach-Object {
						$currentItem = $_;
						if(($currentItem.Tags | Where-Object { $this.FilterTags -Contains $_ } | Measure-Object).Count -ne 0)
						{
							# Resolve the value of SubscriptionId
							$currentItem.Scope = $global:ExecutionContext.InvokeCommand.ExpandString($currentItem.Scope);
							if([string]::IsNullOrWhiteSpace($currentItem.Scope))
							{
								$currentItem.Scope = "/subscriptions/$subscriptionId"
							}

							$this.ApplicableARMPolicies  += $currentItem;
						}
					}
			}
		}
			
		return $this.ApplicableARMPolicies;
	}

	[MessageData[]] SetARMPolicies()
    {
		[MessageData[]] $messages = @();
		if($this.Force -or -not ($this.IsLatestVersionConfiguredOnSub($this.ARMPolicyObj.Version,[Constants]::ARMPolicyConfigVersionTagName,"ARMPolicy")))
		{
			if(($this.ARMPolicyObj.Policies | Measure-Object).Count -ne 0)
			{
				if($this.GetApplicableARMPolices() -ne 0)
				{
					$startMessage = [MessageData]::new("Processing AzSK ARM policies. Total policies: $($this.GetApplicableARMPolices().Count)");
					$messages += $startMessage;
					$this.PublishCustomMessage($startMessage);
					$this.PublishCustomMessage("Note: Configuring ARM policies can take about 2-3 min...", [MessageType]::Warning);				

					$disabledPolicies = $this.GetApplicableARMPolices() | Where-Object { -not $_.Enabled };
					if(($disabledPolicies | Measure-Object).Count -ne 0)
					{
						$disabledMessage = "Found ARM policies which are disabled. Total disabled policies: $($disabledPolicies.Count)";
						$messages += [MessageData]::new($disabledMessage, $disabledPolicies);
						$this.PublishCustomMessage($disabledMessage, [MessageType]::Warning);
					}

					$enabledPolicies = @();
					$enabledPolicies += $this.GetApplicableARMPolices() | Where-Object { $_.Enabled };
					if($enabledPolicies.Count -ne 0)
					{
						$messages += [MessageData]::new([Constants]::SingleDashLine + "`r`nAdding following ARM policies to the subscription. Total policies: $($enabledPolicies.Count)", $enabledPolicies);                                            
					
						[Helpers]::RegisterResourceProviderIfNotRegistered("Microsoft.Scheduler");

						
						$armPoliciesDefns = @{};
						$enabledPolicies | ForEach-Object {
							$policyName = $_.PolicyDefinitionName;
							# Add ARM policy
							try
							{
								$armPolicy = New-AzureRmPolicyDefinition -Name $_.PolicyDefinitionName -Description $_.Description -Policy ([string]$_.PolicyDefinition) -ErrorAction Stop
								$armPoliciesDefns.Add($_,$armPolicy);
							}
							catch
							{
								$messages += [MessageData]::new("Error while adding ARM policy [$policyName] to the subscription", $_, [MessageType]::Error);
							}							
						};

						Start-Sleep -Seconds 15
						$errorCount = 0;
						$currentCount = 0;
						$armPoliciesDefns.Keys | ForEach-Object {
							$armPolicy = $_;
							$armPolicyDefn = $armPoliciesDefns[$_];
							$policyName = $armPolicy.PolicyDefinitionName;
							$currentCount += 1;
							# Add ARM policy
							try
							{								
								New-AzureRmPolicyAssignment -Name $policyName -PolicyDefinition $armPolicyDefn  -Scope $armPolicy.Scope -ErrorAction Stop | Out-Null
							}
							catch
							{
								$messages += [MessageData]::new("Error while adding ARM policy [$policyName] to the subscription", $armPolicy, [MessageType]::Error);
								$errorCount += 1;
							}
							$this.CommandProgress($enabledPolicies.Count, $currentCount, 2);
						};

						[MessageData[]] $resultMessages = @();
						if($errorCount -eq 0)
						{
							#setting the version tag at AzSKRG
							$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
							[Helpers]::SetResourceGroupTags($azskRGName,@{[Constants]::ARMPolicyConfigVersionTagName=$this.ARMPolicyObj.Version}, $false)
						
						$resultMessages += [MessageData]::new("All AzSK ARM policies have been added to the subscription successfully`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
						}
						elseif($errorCount -eq $enabledPolicies.Count)
						{
							$resultMessages += [MessageData]::new("No AzSK ARM policies were added to the subscription due to an error. Please add the ARM policies manually.`r`n" + [Constants]::SingleDashLine, [MessageType]::Error);
						}
						else
						{
							$resultMessages += [MessageData]::new("$errorCount/$($enabledPolicies.Count) ARM policy(ies) have not been added to the subscription. Please add the ARM policies manually or contact AzSK support team.", [MessageType]::Error);
							$resultMessages += [MessageData]::new("$($enabledPolicies.Count - $errorCount)/$($enabledPolicies.Count) ARM policy(ies) have been added to the subscription successfully`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
						}

						$messages += $resultMessages;
						$this.PublishCustomMessage($resultMessages);
					}
				}
				else
				{
					$this.PublishCustomMessage("No ARM policies have been found that matches the specified tags. Tags:[$([string]::Join(",", $this.FilterTags))].", [MessageType]::Warning);
				}
			}
			else
			{
				$this.PublishCustomMessage("No ARM policies found in the ARM policy file", [MessageType]::Warning);
			}
		}
		return $messages;
    }

	[MessageData[]] RemoveARMPolicies()
    {	
		[MessageData[]] $messages = @();
		if(($this.ARMPolicyObj.Policies | Measure-Object).Count -ne 0)
		{
			if($this.GetApplicableARMPolices() -ne 0)
			{
				$startMessage = [MessageData]::new("Processing ARM policies. Tags:[$([string]::Join(",", $this.FilterTags))]. Total policies: $($this.GetApplicableARMPolices().Count)");
				$messages += $startMessage;
				$this.PublishCustomMessage($startMessage);
				$this.PublishCustomMessage("Note: Removing ARM policies can take few minutes depending on number of policies to be processed...", [MessageType]::Warning);				

				$disabledPolicies = $this.GetApplicableARMPolices() | Where-Object { -not $_.Enabled };
				if(($disabledPolicies | Measure-Object).Count -ne 0)
				{
					$disabledMessage = "Found ARM policies which are disabled and will not be removed. Total disabled policies: $($disabledPolicies.Count)";
					$messages += [MessageData]::new($disabledMessage, $disabledPolicies);
					$this.PublishCustomMessage($disabledMessage, [MessageType]::Warning);
				}

				$currentPolicies = @();
				$currentPolicies += Get-AzureRmPolicyAssignment | Select-Object -Property Name | Select-Object -ExpandProperty Name
	
				$enabledPolicies = @();
				if($currentPolicies.Count -ne 0)
				{
					$enabledPolicies += $this.GetApplicableARMPolices() | Where-Object { $_.Enabled -and $currentPolicies -contains $_.policyDefinitionName };
				}
				
				if($enabledPolicies.Count -ne 0)
				{
					$messages += [MessageData]::new([Constants]::SingleDashLine + "`r`nRemoving following ARM policies from the subscription. Total policies: $($enabledPolicies.Count)", $enabledPolicies);                                            

					$errorCount = 0;
					$currentCount = 0;
					$enabledPolicies | ForEach-Object {
						$policyName = $_.PolicyDefinitionName;
						$currentCount += 1;
						# Remove ARM policy
						try
						{
							Remove-AzureRmPolicyAssignment -Name $_.PolicyDefinitionName -Scope $_.Scope -ErrorAction Stop | Out-Null
							Start-Sleep -Seconds 15
							Remove-AzureRmPolicyDefinition -Name $_.PolicyDefinitionName -Force -ErrorAction Stop | Out-Null           
						}
						catch
						{
							$messages += [MessageData]::new("Error while removing ARM policy [$policyName] from the subscription", $_, [MessageType]::Error);
							$errorCount += 1;
						}

						$this.CommandProgress($enabledPolicies.Count, $currentCount, 2);
					};

					[MessageData[]] $resultMessages = @();
					if($errorCount -eq 0)
					{
						#removing the version tag at AzSKRG
						$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
						[Helpers]::SetResourceGroupTags($azskRGName,@{[Constants]::ARMPolicyConfigVersionTagName=$this.ARMPolicyObj.Version}, $true)
						
						$resultMessages += [MessageData]::new("All ARM policies have been removed from the subscription successfully`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
					}
					elseif($errorCount -eq $enabledPolicies.Count)
					{
						$resultMessages += [MessageData]::new("No ARM policies have been removed from the subscription due to error occurred. Please remove the ARM policies manually.`r`n" + [Constants]::SingleDashLine, [MessageType]::Error);
					}
					else
					{
						$resultMessages += [MessageData]::new("$errorCount/$($enabledPolicies.Count) ARM policy(ies) have not been removed from the subscription. Please remove the ARM policies manually or contact AzSK support team.", [MessageType]::Error);
						$resultMessages += [MessageData]::new("$($enabledPolicies.Count - $errorCount)/$($enabledPolicies.Count) ARM policy(ies) have been removed from the subscription successfully`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
					}
					$messages += $resultMessages;
					$this.PublishCustomMessage($resultMessages);
				}
				else
				{
					$noPolicyMessage = [MessageData]::new("No ARM policies have been configured by AzSK on the subscription. No ARM policies have been removed. ", [MessageType]::Warning);
					$messages += $noPolicyMessage;
					$this.PublishCustomMessage($noPolicyMessage);
					$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
					[Helpers]::SetResourceGroupTags($azskRGName,@{[Constants]::ARMPolicyConfigVersionTagName=$this.ARMPolicyObj.Version}, $true)
				}
			}
			else
			{
				$this.PublishCustomMessage("No ARM policies have been found that matches the specified tags. Tags:[$([string]::Join(",", $this.FilterTags))].", [MessageType]::Warning);
			}
		}
		else
		{
			$this.PublishCustomMessage("No ARM policies found in the ARM policy file", [MessageType]::Warning);
		}
		return $messages;
    }

	[void] RemoveARMPolicies([string] $PolicyPrefix, [string] $scope)
    {	
		[MessageData[]] $messages = @();

		$policies = Get-AzureRmPolicyDefinition
		if(($policies | Measure-Object).Count -le 0)
		{
			#return if no policies are found
			return;
		}

		$filteredPolicies = $policies | Where-Object { $_.Name -like "$PolicyPrefix*" }
		if(($filteredPolicies |Measure-Object).Count -le 0)
		{
			#return if no policies are found matching the prefix
			return;
		}

		$policyAssignments = Get-AzureRmPolicyAssignment -Scope $scope

		$filteredPolicies | ForEach-Object {
			try{
				$policy = $_;
				$subPolicyAssignments = @();
				$subPolicyAssignments += $policyAssignments | Where-Object { $_.properties.policyDefinitionId -eq $policy.PolicyDefinitionId }
				if(($subPolicyAssignments | Measure-Object).Count -gt 0)
				{
					$subPolicyAssignments | ForEach-Object {
						Remove-AzureRmPolicyAssignment -Name $_.Name -Scope $_.properties.scope -ErrorAction Stop | Out-Null
					}
				}						
			}
			catch
			{
				$this.PublishException($_);
			}
		}

		Start-Sleep -Seconds 15
		$filteredPolicies | ForEach-Object {
			try{
				$policy = $_;
				Remove-AzureRmPolicyDefinition -Id $policy.PolicyDefinitionId -Force -ErrorAction Stop | Out-Null
			}
			catch
			{
				$this.PublishException($_);
			}
		}
	}	    
}

class ARMPolicyModel
{
	[string] $Version
	[PSObject[]] $Policies
}
