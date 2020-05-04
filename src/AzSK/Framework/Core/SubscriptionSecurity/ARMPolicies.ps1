using namespace System.Management.Automation
Set-StrictMode -Version Latest 

# Class to implement Subscription ARM Policy controls 
class ARMPolicy: AzCommandBase
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
		$isPolicyInitiativeEnabled = [FeatureFlightingManager]::GetFeatureStatus("EnableSetupOfAzurePolicyInitiative",$($this.SubscriptionContext.SubscriptionId)) -or `
									 [FeatureFlightingManager]::GetFeatureStatus("CheckMissingAzurePolicyDefinition",$($this.SubscriptionContext.SubscriptionId))
		if($isPolicyInitiativeEnabled)
		{
			$this.SubPolicyInitiative = [PolicyInitiative] $this.LoadServerConfigFile("Subscription.Initiative.json"); 
		}
		$this.FilterTags = $this.ConvertToStringArray($tags);
		$this.UpdateInitiative = $updateInitiative;
	}

	hidden [PSObject[]] GetApplicableARMPolicies()
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
		[ResourceHelper]::RegisterResourceProviderIfNotRegistered([ARMPolicy]::PolicyProviderNamespace);
		[MessageData[]] $messages = @();
		$this.RemoveDeprecatedPolicies();
		if(($this.ARMPolicyObj.Policies | Measure-Object).Count -ne 0)
		{
			if($this.GetApplicableARMPolicies() -ne 0)
			{
				$startMessage = [MessageData]::new("Processing AzSK ARM policies. Total policies: $($this.GetApplicableARMPolicies().Count)");
				$messages += $startMessage;
				$this.PublishCustomMessage($startMessage);
				
				$disabledPolicies = $this.GetApplicableARMPolicies() | Where-Object { -not $_.Enabled };
				if(($disabledPolicies | Measure-Object).Count -ne 0)
				{
					$disabledMessage = "Found ARM policies which are disabled. Total disabled policies: $($disabledPolicies.Count)";
					$messages += [MessageData]::new($disabledMessage, $disabledPolicies);
					$this.PublishCustomMessage($disabledMessage, [MessageType]::Warning);
				}

				$enabledPolicies = @();
				$enabledPolicies += $this.GetApplicableARMPolicies() | Where-Object { $_.Enabled };
				if($enabledPolicies.Count -ne 0)
				{
					$messages += [MessageData]::new([Constants]::SingleDashLine + "`r`nAdding following ARM policies to the subscription. Total policies: $($enabledPolicies.Count)", $enabledPolicies);                                            								
					$armPoliciesDefns = @{};
					$errorCount = 0;
					[MessageData[]] $resultMessages = @();
					$enabledPolicies | ForEach-Object {
						$policyName = $_.PolicyDefinitionName;
						$armPolicy = $null;
						try {
							$armPolicy = Get-AzPolicyDefinition -Name $policyName -ErrorAction Stop
							try{
						    $temp = $_;		
							$armpolicyassignment = Get-AzPolicyAssignment -Name $policyName
							if($null -eq $armpolicyassignment)
							{
								$armPoliciesDefns.Add($temp,$armPolicy);
							}
							}
							catch{
							$armPoliciesDefns.Add($temp,$armPolicy);
							}
						}
						catch {
							#eat the exception if the policy is not found
						}
						if($null -eq $armPolicy)
						{
							# Add ARM policy
							try
							{
								$armPolicy = New-AzPolicyDefinition -Name $policyName -Description $_.Description -Policy ([string]$_.PolicyDefinition) -ErrorAction Stop
								$armPoliciesDefns.Add($_,$armPolicy);
							}
							catch
							{
								$messages += [MessageData]::new("Error while adding ARM policy [$policyName] to the subscription", $_, [MessageType]::Error);
                                $errorCount += 1;
							}
						}							
					};
					if($errorCount -eq $enabledPolicies.Count )
					{
						$resultMessages += [MessageData]::new("No AzSK ARM policies were added to the subscription due to some error. See the log file for details.`r`n" + [Constants]::SingleDashLine, [MessageType]::Error);
					}
					elseif($errorCount -gt 0)
					{
						$resultMessages += [MessageData]::new("$errorCount/$($enabledPolicies.Count) ARM policy(ies) have not been added to the subscription. See the log file for details.", [MessageType]::Error);
					}
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
								New-AzPolicyAssignment -Name $policyName -PolicyDefinition $armPolicyDefn  -Scope $armPolicy.Scope -ErrorAction Stop | Out-Null
							}
							catch
							{
								$messages += [MessageData]::new("Error while adding ARM policy [$policyName] to the subscription", $armPolicy, [MessageType]::Error);
								$errorCount += 1;
							}
							$this.CommandProgress($enabledPolicies.Count, $currentCount, 2);
						};
					}
					if($errorCount -eq 0)
					{
						#setting the version tag at AzSKRG
						$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
						[ResourceGroupHelper]::SetResourceGroupTags($azskRGName,@{[Constants]::ARMPolicyConfigVersionTagName=$this.ARMPolicyObj.Version}, $false)
					
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
					$PolicyDefn = Get-AzPolicyDefinition -Name $PolicyName -ErrorAction SilentlyContinue
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
					$tassignment = Get-AzPolicyAssignment -PolicyDefinitionId $defn.policyDefinitionId  -ErrorAction SilentlyContinue
					if($null -ne $tassignment)
					{
						$assignments += $tassignment;
					}
				}
				if(($assignments | Measure-Object).Count -gt 0)
				{
					$assignments | ForEach-Object {
						$assigment = $_;
						Remove-AzPolicyAssignment -Scope $assigment.properties.scope -Name $assigment.Name -ErrorAction SilentlyContinue
					}						
					Start-Sleep -Seconds 15
				}				
				$DeprecatedPolicyDefns | ForEach-Object {
					try
					{
						$defn = $_;
						Remove-AzPolicyDefinition -Id $defn.PolicyDefinitionId -Force -ErrorAction SilentlyContinue		
					}
					catch
					{
						#todo eat the exception as it might throw error if it is being used in any of initiatives
					}
				}															
			}																	
		}
	}

	[void] RemoveDeprecatedDefinitions()
	{
		if ($null -ne $this.SubPolicyInitiative -and ($this.SubPolicyInitiative.DeprecatedDefinitions | Measure-Object).Count -gt 0)
		{
			$retainDefinitions = @()
			$isInitiativeResetSuccessful= $true;
			$this.SubPolicyInitiative.DeprecatedDefinitions = $this.SubPolicyInitiative.DeprecatedDefinitions.Replace("{0}", $($this.SubscriptionContext.SubscriptionId)) 
			$InitiativeName = $this.SubPolicyInitiative.Name;
			$Initiative = Get-AzPolicySetDefinition -Name $InitiativeName -ErrorAction SilentlyContinue
			# Remove deprecated definitions from initiative
			if ($null -ne $Initiative)
			{
				$retainDefinitions = $initiative.Properties.policyDefinitions | Where-Object { $_.policyDefinitionId -notin $this.SubPolicyInitiative.DeprecatedDefinitions } | Select-Object policyDefinitionId, parameters
				$retainDefinitions = $($retainDefinitions | ConvertTo-Json -depth 10 | Out-String)
				try
				{
					Set-AzPolicySetDefinition -Name $initiativeName -PolicyDefinition $retainDefinitions -ErrorAction Stop | Out-Null	
				}
				catch
				{
					$isInitiativeResetSuccessful = $false
				}
			}
			Start-Sleep -Seconds 15
			if ($isInitiativeResetSuccessful) {
				$this.SubPolicyInitiative.DeprecatedDefinitions | ForEach-Object {
					$definitionId = $_
					Remove-AzPolicyDefinition -Id $definitionId -Force -ErrorAction SilentlyContinue
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
				$deprecatedInitiative = Get-AzPolicySetDefinition -Name $depInitiative -ErrorAction SilentlyContinue
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
					$tassignment = Get-AzPolicyAssignment -PolicyDefinitionId $depInitiative.PolicySetDefinitionId -ErrorAction SilentlyContinue
					if(($tassignment | Measure-Object).Count -gt 0)
					{
						$assignments += $tassignment
					}
					if(($assignments | Measure-Object).Count -gt 0)					
					{
						$assignments | ForEach-Object {						
							$assignment = $_;
							Remove-AzPolicyAssignment -Scope $assignment.Scope -Name $assignment.Name -Force -ErrorAction SilentlyContinue
						}
					}
				}

				Start-Sleep -Seconds 15
				$deprecatedInitiatives | ForEach-Object {
					$depInitiative = $_;
					Remove-AzPolicySetDefinition -Name $depInitiative.Name -Force -ErrorAction SilentlyContinue					
				}
			}		
		}
	}

	[MessageData[]] RemoveARMPolicies()
    {	
		[MessageData[]] $messages = @();
		if(($this.ARMPolicyObj.Policies | Measure-Object).Count -ne 0)
		{
			if($this.GetApplicableARMPolicies() -ne 0)
			{
				$startMessage = [MessageData]::new("Processing ARM policies. Tags:[$([string]::Join(",", $this.FilterTags))]. Total policies: $($this.GetApplicableARMPolicies().Count)");
				$messages += $startMessage;
				$this.PublishCustomMessage($startMessage);
				$this.PublishCustomMessage("Note: Removing ARM policies can take few minutes depending on number of policies to be processed...", [MessageType]::Warning);				

				$disabledPolicies = $this.GetApplicableARMPolicies() | Where-Object { -not $_.Enabled };
				if(($disabledPolicies | Measure-Object).Count -ne 0)
				{
					$disabledMessage = "Found ARM policies which are disabled and will not be removed. Total disabled policies: $($disabledPolicies.Count)";
					$messages += [MessageData]::new($disabledMessage, $disabledPolicies);
					$this.PublishCustomMessage($disabledMessage, [MessageType]::Warning);
				}

				$currentPolicies = @();
				$currentPolicies += Get-AzPolicyAssignment | Select-Object -Property Name | Select-Object -ExpandProperty Name
	
				$enabledPolicies = @();
				if($currentPolicies.Count -ne 0)
				{
					$enabledPolicies += $this.GetApplicableARMPolicies() | Where-Object { $_.Enabled -and $currentPolicies -contains $_.policyDefinitionName };
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
							Remove-AzPolicyAssignment -Name $_.PolicyDefinitionName -Scope $_.Scope -ErrorAction Stop | Out-Null
							Start-Sleep -Seconds 15
							Remove-AzPolicyDefinition -Name $_.PolicyDefinitionName -Force -ErrorAction Stop | Out-Null           
						}
						catch
						{
							$messages += [MessageData]::new("Error while removing ARM policy [$policyName] from the subscription", $_, [MessageType]::Error);
							$errorCount += 1;
						}

						
					};

					[MessageData[]] $resultMessages = @();
					if($errorCount -eq 0)
					{
						#removing the version tag at AzSKRG
						$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
						[ResourceGroupHelper]::SetResourceGroupTags($azskRGName,@{[Constants]::ARMPolicyConfigVersionTagName=$this.ARMPolicyObj.Version}, $true)
						
						$this.CommandProgress($enabledPolicies.Count, $currentCount, 2);
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
					[ResourceGroupHelper]::SetResourceGroupTags($azskRGName,@{[Constants]::ARMPolicyConfigVersionTagName=$this.ARMPolicyObj.Version}, $true)
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

		$policies = Get-AzPolicyDefinition
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

		$policyAssignments = Get-AzPolicyAssignment -Scope $scope

		$filteredPolicies | ForEach-Object {
			try{
				$policy = $_;
				$subPolicyAssignments = @();
				$subPolicyAssignments += $policyAssignments | Where-Object { $_.properties.policyDefinitionId -eq $policy.PolicyDefinitionId }
				if(($subPolicyAssignments | Measure-Object).Count -gt 0)
				{
					$subPolicyAssignments | ForEach-Object {
						Remove-AzPolicyAssignment -Name $_.Name -Scope $_.properties.scope -ErrorAction Stop | Out-Null
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
				Remove-AzPolicyDefinition -Id $policy.PolicyDefinitionId -Force -ErrorAction Stop | Out-Null
			}
			catch
			{
				$this.PublishException($_);
			}
		}
	}	    

	[void] CreateCustomDefinitions()
	{ 
		# Read custom definitions from PolicyDefinitions.json
		$subscriptionId = $this.SubscriptionContext.SubscriptionId
		$scope = "/subscriptions/$($this.SubscriptionContext.SubscriptionId)"		
		$policyDefinitionsDetails = [ConfigurationHelper]::LoadServerConfigFile("PolicyDefinitions.json", $true, [ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl, [ConfigurationManager]::GetAzSKSettings().EnableAADAuthForOnlinePolicyStore)
		if ($policyDefinitionsDetails -and [Helpers]::CheckMember($policyDefinitionsDetails, "CustomDefinitions"))
		{
			$policyDefinitionsDetails.CustomDefinitions | ForEach-Object {
				# Fetch feature wise controls
				$_.Controls | ForEach-Object {

					# 1. Read defintion name and description
					$policyObj = "" | Select-Object ControlId, Description, DefinitionName, PolicyRule, Parameters
					$policyObj.ControlId = $_.ControlId
					$policyObj.Description = $_.Description
					$policyObj.DefinitionName = $_.CustomDefinitionName	# Here internal control id should be used as definition name eg., AppService240		

					# 2. Fetch policy definitions rules and parameter
					$policyContent = $_.PolicyDefinition;
					if ($policyContent | Get-Member -Name policyRule)
					{
						$policyRule = ($policyContent.policyRule | ConvertTo-Json -Depth 10).ToString()
						$policyObj.PolicyRule = $policyRule
					}

					if ($policyContent | Get-Member -Name parameters)
					{
						$parameters = ($policyContent.parameters | ConvertTo-Json -Depth 10).ToString()
						$policyObj.Parameters = $parameters
					}

					# 3. Create definition
					if (-not [String]::IsNullOrEmpty($Scope) -and -not [String]::IsNullOrEmpty($policyObj.PolicyRule) -and -not [String]::IsNullOrEmpty($policyObj.DefinitionName))
					{
						
						try
						{
							if (-not [String]::IsNullOrEmpty($policyObj.Parameters))
							{
								New-AzPolicyDefinition -Mode All -Name $policyObj.DefinitionName `
									-DisplayName $policyObj.ControlId `
									-Description $policyObj.Description `
									-Policy $policyObj.PolicyRule `
									-Parameter $policyObj.Parameters `
									-SubscriptionId $SubscriptionId `
									-ErrorAction Stop | Out-Null
							}
							else
							{
								New-AzPolicyDefinition -Mode All -Name $policyObj.DefinitionName `
									-DisplayName $policyObj.ControlId `
									-Description $policyObj.Description `
									-Policy $policyObj.PolicyRule `
									-SubscriptionId $SubscriptionId `
									-ErrorAction Stop | Out-Null
							}
						}
						catch
						{
							#eat exception if definition fails to get created to avoid breaking code flow.
						}
					}

				}#foreach end
			}#foreach end
		}		
	}

	[MessageData[]] UpdateCustomDefinitionsList()
	{
		[MessageData[]] $messages = @();
		if ($null -ne $this.SubPolicyInitiative.CustomPolicies)
		{
			$successfullyCreatedDefinitions = @()
			$failedToReadDefinitionDetails = @()
			$this.SubPolicyInitiative.CustomPolicies |
			ForEach-Object {
				$_.policyDefinitionId = $_.policyDefinitionId.Replace("{0}", $this.SubscriptionContext.SubscriptionId)
				if (-not [String]::IsNullOrEmpty($_.policyDefinitionId))
				{
					try
					{
						$definition = Get-AzPolicyDefinition -Id "$($_.policyDefinitionId)" -ErrorAction Stop
						if ($definition)
						{
							$successfullyCreatedDefinitions += $_
						}
						else
						{
							$failedToReadDefinitionDetails += $_
						}
					}
					catch
					{
						#eat exception if failure occur while reading definition details
					}
				}		
			} #foreach end
			

			# Updating custom policies with the list of existing definition
			if ($successfullyCreatedDefinitions)
			{
				$messages += [MessageData]::new([Constants]::SingleDashLine + "`r`nAdding following policy definitions to the subscription. Total policies: $($($successfullyCreatedDefinitions | Measure-Object).Count)", $successfullyCreatedDefinitions);
				$this.SubPolicyInitiative.CustomPolicies = $successfullyCreatedDefinitions
			}
			if ($failedToReadDefinitionDetails)
			{
				$messages += [MessageData]::new([Constants]::SingleDashLine + "`r`nFailed to add following policy definitions to the subscription. Total policies: $($($failedToReadDefinitionDetails | Measure-Object).Count)", $failedToReadDefinitionDetails);
			}
		}
		return $messages
	}

	[MessageData[]] SetPolicyInitiative()
	{	
		[MessageData[]] $messages = @();
		#$isPolicyInitiativeEnabled = [ConfigurationManager]::GetAzSKConfigData().EnableAzurePolicyBasedScan;
		$isPolicyInitiativeEnabled = [FeatureFlightingManager]::GetFeatureStatus("EnableSetupOfAzurePolicyInitiative",$($this.SubscriptionContext.SubscriptionId))
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
						$initiative = Get-AzPolicySetDefinition -Name $initiativeName -ErrorAction SilentlyContinue;
						if(($initiative|Measure-Object).Count -gt 0)
						{
							$initiativeAssignment = Get-AzPolicyAssignment -PolicyDefinitionId $initiative.PolicySetDefinitionId
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
						$this.PublishCustomMessage("Creating custom definitions...", [MessageType]::Update);
						if([FeatureFlightingManager]::GetFeatureStatus("EnableSetupOfCustomPolicyDefinitions", $($this.SubscriptionContext.SubscriptionId)) -eq $true)
						{
							try
							{
								$this.RemoveDeprecatedDefinitions();
								$this.CreateCustomDefinitions();
								$messages += $this.UpdateCustomDefinitionsList()
								$PolicyDefnitions = @()
								$PolicyDefnitions += $this.SubPolicyInitiative.Policies
								if($this.SubPolicyInitiative.CustomPolicies)
								{
									$PolicyDefnitions += $this.SubPolicyInitiative.CustomPolicies
								}
								$PolicyDefnitions = $PolicyDefnitions | ConvertTo-Json -depth 10 | Out-String
							}
							# If error occurs while execution of custom policies, continue with built-in policies normal flow
							catch
							{
								$PolicyDefnitions = $this.SubPolicyInitiative.Policies | ConvertTo-Json -depth 10 | Out-String
							}							
						}
						else
						{
							$PolicyDefnitions = $this.SubPolicyInitiative.Policies | ConvertTo-Json -depth 10 | Out-String
						}	
						New-AzPolicySetDefinition -Name $initiativeName -DisplayName $this.SubPolicyInitiative.DisplayName -Description $this.SubPolicyInitiative.Description -PolicyDefinition $PolicyDefnitions | Out-Null
						Start-Sleep -Seconds 15
						
					}
					else {
						$this.PublishCustomMessage("Updating AzSK Initiative...", [MessageType]::Update);
						$this.PublishCustomMessage("Updating custom definitions...", [MessageType]::Update);
						if([FeatureFlightingManager]::GetFeatureStatus("EnableSetupOfCustomPolicyDefinitions", $($this.SubscriptionContext.SubscriptionId)) -eq $true)
						{
							try
							{
								$PolicyDefnitions = @()
								$this.RemoveDeprecatedDefinitions();
								$this.CreateCustomDefinitions();
								$messages += $this.UpdateCustomDefinitionsList()
								$PolicyDefnitions += $this.SubPolicyInitiative.Policies
								if($this.SubPolicyInitiative.CustomPolicies)
								{
									$PolicyDefnitions += $this.SubPolicyInitiative.CustomPolicies
								}
								$PolicyDefnitions = $PolicyDefnitions | ConvertTo-Json -depth 10 | Out-String
							}
							# If error occurs while execution of custom policies, continue with built-in policies normal flow
							catch
							{
								$PolicyDefnitions = $this.SubPolicyInitiative.Policies | ConvertTo-Json -depth 10 | Out-String
							}
						}
						else
						{
							$PolicyDefnitions = $this.SubPolicyInitiative.Policies | ConvertTo-Json -depth 10 | Out-String
						}						
						Set-AzPolicySetDefinition -Name $this.SubPolicyInitiative.Name -DisplayName $this.SubPolicyInitiative.DisplayName -Description $this.SubPolicyInitiative.Description -PolicyDefinition $PolicyDefnitions | Out-Null
						Start-Sleep -Seconds 15						
					}
	
					if($null -eq $initiativeAssignment)
					{
						$setDefnObj = Get-AzPolicySetDefinition -Name $initiativeName -ErrorAction SilentlyContinue;
						New-AzPolicyAssignment -Name $assignmentName -DisplayName $assignmentDisplayName -Scope $scope -PolicySetDefinition $setDefnObj 
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
		$enabledPolicies = $this.GetApplicableARMPolicies() | Where-Object { $_.Enabled };
		if($null -ne $this.ARMPolicyObj -and ($enabledPolicies | Measure-Object).Count -gt 0)
		{
			$RequiredPolicyDefns = @();			
			$enabledPolicies | ForEach-Object {
				$Policy = $_;
				try
				{
					$PolicyDefn = Get-AzPolicyDefinition -Name $Policy.policyDefinitionName -ErrorAction Stop
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
					$tassignment = Get-AzPolicyAssignment -PolicyDefinitionId $defn.policyDefinitionId  -ErrorAction SilentlyContinue
					if($null -eq $tassignment)
					{
						$NonCompliantObjects += ("Policy :[" + $defn.Name + "]");
					}
				}																		
			}	
		}

		$isPolicyInitiativeEnabled = [FeatureFlightingManager]::GetFeatureStatus("CheckMissingAzurePolicyDefinition",$($this.SubscriptionContext.SubscriptionId))
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
						$initiative = Get-AzPolicySetDefinition -Name $initiativeName -ErrorAction SilentlyContinue;
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
	[PSObject[]] $CustomPolicies;
	[string[]] $DeprecatedDefinitions;
}
