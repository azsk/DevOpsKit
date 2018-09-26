using namespace System.Management.Automation
Set-StrictMode -Version Latest 

# Class to implement Subscription ARM Policy controls 
class ARMPolicy: CommandBase
{    
	hidden [ARMPolicyModel] $ARMPolicyObj = $null;
	hidden [PolicyInitiative] $SubPolicyInitiative = $null;
	hidden [bool] $UpdateInitiative = $false;
	static [string] $PolicyProviderNamespace = "Microsoft.PolicyInsights";
	
	hidden [PSObject[]] $ApplicableARMPolicies = $null;
	#hidden [PSObject[]] $PolicyAssignments = $null;

	ARMPolicy([string] $subscriptionId, [InvocationInfo] $invocationContext, [string] $tags, [bool] $updateInitiative): 
        Base($subscriptionId, $invocationContext)
    { 
		$this.ARMPolicyObj = [ARMPolicyModel] $this.LoadServerConfigFile("Subscription.ARMPolicies.json"); 
		$isPolicyInitiativeEnabled = [ConfigurationManager]::GetAzSKConfigData().EnableAzurePolicyBasedScan;
		if($isPolicyInitiativeEnabled)
		{
			$this.SubPolicyInitiative = [PolicyInitiative] $this.LoadServerConfigFile("Subscription.Initiative.json"); 
		}
		$this.FilterTags = $this.ConvertToStringArray($tags);
		$this.UpdateInitiative = $updateInitiative;
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
			else
			{
				$this.ApplicableARMPolicies += $this.ARMPolicyObj.Policies
			}
		}
			
		return $this.ApplicableARMPolicies;
	}

	[MessageData[]] SetARMPolicies()
    {
		[Helpers]::RegisterResourceProviderIfNotRegistered([ARMPolicy]::PolicyProviderNamespace);
		[MessageData[]] $messages = @();
		$this.RemoveDeprecatedPolicies();
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
					$armPoliciesDefns = @{};
					$enabledPolicies | ForEach-Object {
						$policyName = $_.PolicyDefinitionName;
						$armPolicy = $null;
						try {
							$armPolicy = Get-AzureRmPolicyDefinition -Name $policyName -ErrorAction Stop
						}
						catch {
							#eat the exception if the policy is not found
						}
						if($null -eq $armPolicy)
						{
							# Add ARM policy
							try
							{
								$armPolicy = New-AzureRmPolicyDefinition -Name $policyName -Description $_.Description -Policy ([string]$_.PolicyDefinition) -ErrorAction Stop
								$armPoliciesDefns.Add($_,$armPolicy);
							}
							catch
							{
								$messages += [MessageData]::new("Error while adding ARM policy [$policyName] to the subscription", $_, [MessageType]::Error);
							}
						}							
					};
					$errorCount = 0;
					$currentCount = 0;
					if(($armPoliciesDefns.Keys | Measure-Object).Count -gt 0)
					{
						Start-Sleep -Seconds 15															
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
					}
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
		$messages += $this.SetPolicyInitiative();
		return $messages;
    }

	[void] RemoveDeprecatedPolicies()
	{
		if(($this.ARMPolicyObj.DeprecatedPolicies | Measure-Object).Count -gt 0)
		{
			$DeprecatedPolicyDefns = @();
			$this.ARMPolicyObj.DeprecatedPolicies | ForEach-Object {
				try
				{
					$PolicyName = $_;
					$PolicyDefn = Get-AzureRmPolicyDefinition -Name $PolicyName -ErrorAction SilentlyContinue
					if($null -ne $PolicyDefn)
					{
						$DeprecatedPolicyDefns += $PolicyDefn;
					}
				}
				catch
				{
					#eat this exception as silently continue is not working for this scenario
				}
			}
			if(($DeprecatedPolicyDefns | Measure-Object).Count -gt 0)
			{
				$assignments = @();
				$DeprecatedPolicyDefns | ForEach-Object {
					$defn = $_;
					$tassignment = Get-AzureRmPolicyAssignment -PolicyDefinitionId $defn.policyDefinitionId  -ErrorAction SilentlyContinue
					if($null -ne $tassignment)
					{
						$assignments += $tassignment;
					}
				}
				if(($assignments | Measure-Object).Count -gt 0)
				{
					$assignments | ForEach-Object {
						$assigment = $_;
						Remove-AzureRmPolicyAssignment -Scope $assigment.properties.scope -Name $assigment.Name -ErrorAction SilentlyContinue
					}						
					Start-Sleep -Seconds 15
				}				
				$DeprecatedPolicyDefns | ForEach-Object {
					try
					{
						$defn = $_;
						Remove-AzureRmPolicyDefinition -Id $defn.PolicyDefinitionId -Force -ErrorAction SilentlyContinue		
					}
					catch
					{
						#todo eat the exception as it might throw error if it is being used in any of initiatives
					}
				}															
			}																	
		}
	}

	[void] RemoveDeprecatedInitiatives()
	{
		if($null -ne $this.SubPolicyInitiative -and ($this.SubPolicyInitiative.DeprecatedInitiatives | Measure-Object).Count -gt 0)
		{
			$deprecatedInitiatives = @();
			$this.SubPolicyInitiative.DeprecatedInitiatives | ForEach-Object {
				$depInitiative = $_;
				$deprecatedInitiative = Get-AzureRmPolicySetDefinition -Name $depInitiative -ErrorAction SilentlyContinue
				if($null -ne $deprecatedInitiative)
				{
					$deprecatedInitiatives += $deprecatedInitiative;
				}				
			}
			if(($deprecatedInitiatives | Measure-Object).Count -gt 0)
			{
				$deprecatedInitiatives | ForEach-Object {
					$depInitiative = $_;
					$assignments = @();
					$tassignment = Get-AzureRmPolicyAssignment -PolicyDefinitionId $depInitiative.PolicySetDefinitionId -ErrorAction SilentlyContinue
					if(($tassignment | Measure-Object).Count -gt 0)
					{
						$assignments += $tassignment
					}
					if(($assignments | Measure-Object).Count -gt 0)					
					{
						$assignments | ForEach-Object {						
							$assignment = $_;
							Remove-AzureRmPolicyAssignment -Scope $assignment.Scope -Name $assignment.Name -Force -ErrorAction SilentlyContinue
						}
					}
				}

				Start-Sleep -Seconds 15
				$deprecatedInitiatives | ForEach-Object {
					$depInitiative = $_;
					Remove-AzureRmPolicySetDefinition -Name $depInitiative.Name -Force -ErrorAction SilentlyContinue					
				}
			}		
		}
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

	[MessageData[]] SetPolicyInitiative()
	{
		[MessageData[]] $messages = @();
		$isPolicyInitiativeEnabled = [ConfigurationManager]::GetAzSKConfigData().EnableAzurePolicyBasedScan;
		try{
			if($isPolicyInitiativeEnabled)
		{
			$initiativeName = [ConfigurationManager]::GetAzSKConfigData().AzSKInitiativeName
			if($null -ne $this.SubPolicyInitiative)
			{
				$this.RemoveDeprecatedInitiatives();
				if($this.SubPolicyInitiative.Name -eq $initiativeName -and ($this.SubPolicyInitiative.Policies | Measure-Object).Count -gt 0)
				{		
					$initiative = $null;
					$initiativeAssignment = $null
					try
					{			
						#check if initiative already exists
						$initiative = Get-AzureRmPolicySetDefinition -Name $initiativeName -ErrorAction SilentlyContinue;
						if(($initiative|Measure-Object).Count -gt 0)
						{
							$initiativeAssignment = Get-AzureRmPolicyAssignment -PolicyDefinitionId $initiative.PolicySetDefinitionId
						}
					}
					catch
					{
						#eat this exception as error action is not working
					}
					$assignmentName = $initiativeName + "-assignment"
					$assignmentDisplayName = $this.SubPolicyInitiative.DisplayName + " assignment"
					$scope = "/subscriptions/$($this.SubscriptionContext.SubscriptionId)"
					if($null -eq $initiative)
					{
						$this.PublishCustomMessage("Creating new AzSK Initiative...", [MessageType]::Update);		
						$PolicyDefnitions = $this.SubPolicyInitiative.Policies | ConvertTo-Json -depth 10 | Out-String
						New-AzureRmPolicySetDefinition -Name $initiativeName -DisplayName $this.SubPolicyInitiative.DisplayName -Description $this.SubPolicyInitiative.Description -PolicyDefinition $PolicyDefnitions | Out-Null
						Start-Sleep -Seconds 15
						
					}
					elseif($this.UpdateInitiative) {
						$this.PublishCustomMessage("Updating AzSK Initiative...", [MessageType]::Update);
						$PolicyDefnitions = $this.SubPolicyInitiative.Policies | ConvertTo-Json -depth 10 | Out-String
						Set-AzureRmPolicySetDefinition -Name $this.SubPolicyInitiative.Name -DisplayName $this.SubPolicyInitiative.DisplayName -Description $this.SubPolicyInitiative.Description -PolicyDefinition $PolicyDefnitions | Out-Null
						Start-Sleep -Seconds 15						
					}
					elseif($null -ne $initiative)
					{
						$this.PublishCustomMessage("Found existing AzSK Initiative.", [MessageType]::Update);	
					}	
					if($null -eq $initiativeAssignment)
					{
						$setDefnObj = Get-AzureRmPolicySetDefinition -Name $initiativeName -ErrorAction SilentlyContinue;
						New-AzureRmPolicyAssignment -Name $assignmentName -DisplayName $assignmentDisplayName -Scope $scope -PolicySetDefinition $setDefnObj 
					}
					#todo: CA permission update	if default CA			
				}				
			}
		}
		}
		catch
		{
			#eat up exception to allow this functionality to run in preview mode and not to hamper existing functionality
		}
		return $messages;
		
	}

	[string[]] ValidatePolicyConfiguration()
	{		
		$NonCompliantObjects = @();
		$enabledPolicies = $this.GetApplicableARMPolices() | Where-Object { $_.Enabled };
		if($null -ne $this.ARMPolicyObj -and ($enabledPolicies | Measure-Object).Count -gt 0)
		{
			$RequiredPolicyDefns = @();			
			$enabledPolicies | ForEach-Object {
				$Policy = $_;
				try
				{
					$PolicyDefn = Get-AzureRmPolicyDefinition -Name $Policy.policyDefinitionName -ErrorAction SilentlyContinue
					if($null -ne $PolicyDefn)
					{
						$RequiredPolicyDefns += $PolicyDefn;
					}
				}
				catch
				{
					$NonCompliantObjects += ("Policy :[" + $Policy.policyDefinitionName + "]");
					#eat this exception as silently continue is not working for this scenario
				}				
			}
			if(($RequiredPolicyDefns | Measure-Object).Count -gt 0)
			{
				$RequiredPolicyDefns | ForEach-Object {
					$defn = $_;
					$tassignment = Get-AzureRmPolicyAssignment -PolicyDefinitionId $defn.policyDefinitionId  -ErrorAction SilentlyContinue
					if($null -eq $tassignment)
					{
						$NonCompliantObjects += ("Policy :[" + $defn.Name + "]");
					}
				}																		
			}	
		}

		$isPolicyInitiativeEnabled = [ConfigurationManager]::GetAzSKConfigData().EnableAzurePolicyBasedScan;
		if($isPolicyInitiativeEnabled)
		{
			$initiativeName = [ConfigurationManager]::GetAzSKConfigData().AzSKInitiativeName		
			if($null -ne $this.SubPolicyInitiative)
			{				
				if($this.SubPolicyInitiative.Name -eq $initiativeName -and ($this.SubPolicyInitiative.Policies | Measure-Object).Count -gt 0)
				{		
					$initiative = $null;
					try
					{			
						$initiative = Get-AzureRmPolicySetDefinition -Name $initiativeName -ErrorAction SilentlyContinue;
					}
					catch
					{
						$NonCompliantObjects += ("Policy Initiative :[" + $initiativeName + "]");
						#eat this exception as error action is not working
					}
					if($null -ne $initiative)
					{
						$policyDefinitions = $initiative.Properties.policyDefinitions;
						$this.SubPolicyInitiative.Policies | ForEach-Object {
							$configuredPolicyDefn = $_;
							if(($policyDefinitions | Where-Object { $_.policyDefinitionId -eq $configuredPolicyDefn.policyDefinitionId} | Measure-Object).Count -le 0)
							{
								$NonCompliantObjects += ("Policy Initiative :[" + $initiativeName + "] -> Definition :[" + $_.policyDefinitionId + "]");
							}
						}
					}				
				}
			}
		}
		return ($NonCompliantObjects | Select-Object -Unique);
	}
}

class ARMPolicyModel
{
	[string] $Version
	[PSObject[]] $Policies
	[string[]] $DeprecatedPolicies
}

class PolicyInitiative 
{
	[string] $Version;
	[string] $Name;
	[string] $DisplayName;
	[string] $Description;
	[PSObject[]] $Policies;	
	[string[]] $DeprecatedInitiatives;
}
