using namespace Microsoft.Azure.Commands.Resources.Models.Authorization
using namespace System.Management.Automation
Set-StrictMode -Version Latest 

# Class to implement Subscription RBAC controls 
class RBAC: CommandBase
{    
	hidden [SubscriptionRBAC] $Policy = $null;

	hidden [PSRoleAssignment[]] $RoleAssignments = $null;
	hidden [ActiveRBACAccount[]] $ApplicableActiveAccounts = $null;

	hidden [ActiveRBACAccount[]] $MissingActiveAccounts = $null;

	hidden [RBACAccountRoleMapping[]] $MatchedActiveAccounts = $null;
	hidden [RBACAccountRoleMapping[]] $MatchedDeprecatedAccounts = $null;

	RBAC([string] $subscriptionId, [InvocationInfo] $invocationContext, [string] $tags): 
        Base($subscriptionId, $invocationContext)
    { 
		$this.Policy = [SubscriptionRBAC] $this.LoadServerConfigFile("Subscription.RBAC.json"); 
		$this.FilterTags = $this.ConvertToStringArray($tags);
	}

	hidden [PSRoleAssignment[]] GetRoleAssignments()
	{
		if(-not $this.RoleAssignments)
		{
			$this.RoleAssignments = [RoleAssignmentHelper]::GetAzSKRoleAssignment($true, $true);
			#filter deleted user/group/spn assignments
			$deletedUserAssignments = $this.RoleAssignments | Where-Object{ [string]::IsNullOrWhiteSpace($_.DisplayName) -and [string]::IsNullOrWhiteSpace($_.SignInName) -and $_.ObjectType -eq 'Unknown'}
			if(($deletedUserAssignments | Measure-Object).Count -gt 0)
			{
				$this.RoleAssignments = $this.RoleAssignments | Where-Object{ $deletedUserAssignments.RoleAssignmentId -inotcontains $_.RoleAssignmentId }
			}
		}
		return $this.RoleAssignments;
	}
	
	hidden [ActiveRBACAccount[]] GetApplicableActiveAccounts()
	{
		if($null -eq $this.ApplicableActiveAccounts)
		{
			$this.ApplicableActiveAccounts = @();

			$subscriptionId = $this.SubscriptionContext.SubscriptionId;
			if(($this.FilterTags | Measure-Object).Count -ne 0)
			{
				$this.Policy.ValidActiveAccounts | 
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

							$this.ApplicableActiveAccounts  += $currentItem;
						}
					}
			}
		}
			
		return $this.ApplicableActiveAccounts;
	}
	
	hidden [void] LoadActiveAccountStatus()
	{
		$this.MissingActiveAccounts = @();
		$this.MatchedActiveAccounts = @();

		$this.GetApplicableActiveAccounts() | Where-Object { $_.Enabled } | 
			ForEach-Object { 
				$currentItem = $_;
				$matchedAccount = $this.GetRoleAssignments() | 
									Where-Object { 
										($_.ObjectId -eq $currentItem.ObjectId) -and 
										($_.Scope -eq $currentItem.Scope) -and 
										($_.RoleDefinitionName -eq $currentItem.RoleDefinitionName) 
									} | Select-Object -First 1
				if($matchedAccount)
				{
					$this.MatchedActiveAccounts += [RBACAccountRoleMapping]@{
							RoleAssignment = $matchedAccount;
							RBACAccount = $currentItem;
						};
				}
				else
				{
					$this.MissingActiveAccounts += $currentItem;
				}						
			};
	}

	hidden [void] LoadDeprecatedAccountStatus()
	{
		$this.MatchedDeprecatedAccounts =  @();
		
		$this.Policy.DeprecatedAccounts | Where-Object { $_.Enabled } | 
			ForEach-Object { 
				$currentItem = $_;
				$matchedAccounts = $this.GetRoleAssignments() | 
									Where-Object {  ($_.ObjectId -eq $currentItem.ObjectId) };

				if(($matchedAccounts | Measure-Object).Count -ne 0)
				{
					$matchedAccounts | ForEach-Object {
						$this.MatchedDeprecatedAccounts += [RBACAccountRoleMapping]@{
								RoleAssignment = $_;
								RBACAccount = $currentItem;
							};
					};
				}
			};
	}
	
	[MessageData[]] SetRBACAccounts()
    {	
		[MessageData[]] $messages = @();
		[MessageData[]] $resultMessages = @();
		[CCAutomation] $caAutomation = [CCAutomation]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext);
		$caAutomation.RecoverCASPN();
		if($this.Force -or -not ($this.IsLatestVersionConfiguredOnSub($this.Policy.ActiveCentralAccountsVersion,[Constants]::CentralRBACVersionTagName,"CentralRBAC")))
		{
			#setting the tag at AzSKRG
			$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
			[Helpers]::SetResourceGroupTags($azskRGName,@{"CentralRBACVersion"=$this.Policy.ActiveCentralAccountsVersion},$false)

			#set the tag on subscription based on server tag	
			# Set Active accounts
			$nonConfiguredActiveAccounts = $this.GetNonConfiguredActiveAccounts(([ref]$messages));
			if($nonConfiguredActiveAccounts.Count -ne 0)
			{
				$provisionAccounts = @();
				$provisionAccounts += $nonConfiguredActiveAccounts | Where-Object { $_.Type -eq [RBACAccountType]::Provision };

				if($provisionAccounts.Count -ne 0)
				{
					# Adding Central Accounts
					$messages += [MessageData]::new([Constants]::SingleDashLine + "`r`nAdding following active accounts to the subscription. Total accounts: $($provisionAccounts.Count)", $provisionAccounts);                                            
					$errorCount = 0;
					$currentCount = 0;
					$provisionAccounts | ForEach-Object {
						$accountName = $_.Name;
						$currentCount += 1;
						# Add account
						try
						{
							$this.PublishCustomMessage("Adding account [$accountName] to the subscription...");
							New-AzureRmRoleAssignment -ObjectId $_.ObjectId -Scope $_.Scope -RoleDefinitionName $_.RoleDefinitionName -ErrorAction Stop | Out-Null                                         
						}
						catch
						{
							$messages += [MessageData]::new("Error while adding account [$accountName] to the subscription", $_, [MessageType]::Error);
							$errorCount += 1;
						}

						$this.CommandProgress($provisionAccounts.Count, $currentCount, 5);
					};

				
					if($errorCount -eq 0)
					{
						$resultMessages += [MessageData]::new("All required active accounts have been added to the subscription successfully.`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
					}
					elseif($errorCount -eq $provisionAccounts.Count)
					{
						$resultMessages += [MessageData]::new("No accounts have been added due an error. Please add the accounts manually. You can find the specific account details in the log file.`r`n" + [Constants]::SingleDashLine, [MessageType]::Error);
					}
					else
					{
						$resultMessages += [MessageData]::new("$errorCount/$($provisionAccounts.Count) required active account(s) have not been added to the subscription. Please add the accounts manually. You can find the specific account details in the log file.", [MessageType]::Error);
						$resultMessages += [MessageData]::new("$($provisionAccounts.Count - $errorCount)/$($provisionAccounts.Count) required active account(s) have been added to the subscription successfully.`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
					}
				
					$messages += $resultMessages;
					$this.PublishCustomMessage($resultMessages);
				}

				$nonProvisionAccounts = @();
				$nonProvisionAccounts += $nonConfiguredActiveAccounts | Where-Object { $_.Type -ne [RBACAccountType]::Provision };

				if($nonProvisionAccounts.Count -ne 0)
				{
					$messageText = "Some accounts are not added to the subscription, since the account type is not set to 'Provision' in RBAC policy file. Total accounts: $($nonProvisionAccounts.Count)";
					$messages += [MessageData]::new($messageText, $nonProvisionAccounts);
					$this.PublishCustomMessage($messageText);
				}
			}
		}
		
		return $messages;
    }

	[ActiveRBACAccount[]] GetNonConfiguredActiveAccounts([ref]$messages)
	{
		if($this.Policy.ValidActiveAccounts.Count -ne 0)
		{
			if($this.GetApplicableActiveAccounts().Count -ne 0)
			{
				$startMessage = [MessageData]::new("Processing RBAC rules for adding central accounts. Tags: [$([string]::Join(",", $this.FilterTags))]. Total accounts: $($this.GetApplicableActiveAccounts().Count)");
				$messages.Value += $startMessage;
				$this.PublishCustomMessage($startMessage);
				
				$disabledAccounts = $this.GetApplicableActiveAccounts() | Where-Object { -not $_.Enabled };
				if(($disabledAccounts | Measure-Object).Count -ne 0)
				{
					$disabledMessage = "Found accounts which are disabled. Total disabled accounts: $($disabledAccounts.Count)";
					$messages.Value += [MessageData]::new($disabledMessage, $disabledAccounts);
					$this.PublishCustomMessage($disabledMessage, [MessageType]::Warning);
				}

				# Load all properties
				$this.LoadActiveAccountStatus();

				if($this.MatchedActiveAccounts.Count -ne 0)
				{
					$messages.Value += [MessageData]::new("Following accounts have correct RBAC configured. Total accounts: $($this.MatchedActiveAccounts.Count)", ($this.MatchedActiveAccounts | Select-Object -Property RoleAssignment));
				}
				
				if($this.MissingActiveAccounts.Count -ne 0)
				{
					$missingAccountsMessage = "Following accounts do not have correct RBAC configured. Total accounts: $($this.MissingActiveAccounts.Count)";

					$messages.Value += [MessageData]::new($missingAccountsMessage, $this.MissingActiveAccounts);
					$this.PublishCustomMessage($missingAccountsMessage);
				}
				else
				{
					$successMessage = [MessageData]::new("All required accounts are correctly configured");
					$messages.Value += $successMessage;
					$this.PublishCustomMessage($successMessage);
				}
				return $this.MissingActiveAccounts;					
			}
			else
			{
				if($this.FilterTags)
				{
					$this.PublishCustomMessage("No active accounts have been found that matches the specified tags. Tags: [$([string]::Join(",", $this.FilterTags))].", [MessageType]::Warning);
				}
				else
				{
					$this.PublishCustomMessage("No active accounts have been found that matches the specified tags.", [MessageType]::Warning);
				}
			}
		}
		else
		{
			$this.PublishCustomMessage("No active accounts found in the RBAC policy file", [MessageType]::Warning);
		}
		return @();
	}

	[RBACAccountRoleMapping[]] GetMatchedDeprecatedAccounts([ref]$messages)
	{
		if($this.Policy.DeprecatedAccounts -and $this.Policy.DeprecatedAccounts.Count -ne 0)
		{
			#$this.PublishCustomMessage("Found deprecated accounts in the RBAC policy file");
			
			$startMessage = [MessageData]::new("Processing RBAC rules for removing deprecated central accounts. Total accounts: $($this.Policy.DeprecatedAccounts.Count)");
			$messages.Value += $startMessage;
			#$this.PublishCustomMessage($startMessage);
				
			$disabledAccounts = $this.Policy.DeprecatedAccounts | Where-Object { -not $_.Enabled };
			if(($disabledAccounts | Measure-Object).Count -ne 0)
			{
				$disabledMessage = "Found accounts which are disabled. Total disabled accounts: $($disabledAccounts.Count)";
				$messages.Value += [MessageData]::new($disabledMessage, $disabledAccounts);
				$this.PublishCustomMessage($disabledMessage, [MessageType]::Warning);
			}

			# Load all properties
			$this.LoadDeprecatedAccountStatus();
							
			if($this.MatchedDeprecatedAccounts.Count -ne 0)
			{
				$messages.Value += [MessageData]::new("Following deprecated accounts must be removed from the subscription. Total accounts: $($this.MatchedDeprecatedAccounts.Count)", ($this.MatchedDeprecatedAccounts | Select-Object -Property RoleAssignment));
			}
			else
			{
				$resultMessage = [MessageData]::new("No deprecated accounts found on the subscription", [MessageType]::Warning);
				$messages.Value += $resultMessage;
				$this.PublishCustomMessage($resultMessage);
			}
			return $this.MatchedDeprecatedAccounts;					
		}
		else
		{
			$this.PublishCustomMessage("No deprecated accounts found in the RBAC policy file");
		}
		return @();
	}

	[MessageData[]] RemoveRBACAccounts()
    {	
		[MessageData[]] $messages = @();
		if($this.Force -or -not ($this.IsLatestVersionConfiguredOnSub($this.Policy.DeprecatedAccountsVersion,[Constants]::DeprecatedRBACVersionTagName,"DeprecatedRBAC")))
		{
			#setting the tag at AzSKRG
			$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
			[Helpers]::SetResourceGroupTags($azskRGName,@{[Constants]::DeprecatedRBACVersionTagName=$this.Policy.DeprecatedAccountsVersion}, $false)			

			if($this.Policy.ValidActiveAccounts.Count -ne 0)
			{
				if($this.GetApplicableActiveAccounts().Count -ne 0)
				{
					$startMessage = [MessageData]::new("Processing RBAC rules for removing central accounts. Tags: [$([string]::Join(",", $this.FilterTags))]. Total accounts: $($this.GetApplicableActiveAccounts().Count)");
					$messages += $startMessage;
					$this.PublishCustomMessage($startMessage);

					$disabledAccounts = $this.GetApplicableActiveAccounts() | Where-Object { -not $_.Enabled };
					if(($disabledAccounts | Measure-Object).Count -ne 0)
					{
						$disabledMessage = "Found accounts which are disabled. Total disabled accounts: $($disabledAccounts.Count)";
						$messages += [MessageData]::new($disabledMessage, $disabledAccounts);
						$this.PublishCustomMessage($disabledMessage, [MessageType]::Warning);
					}

					# Load all properties
					$this.LoadActiveAccountStatus();

					$messages += $this.RemoveRoleAssignments($this.MatchedActiveAccounts);
					[Helpers]::SetResourceGroupTags($azskRGName,@{[Constants]::CentralRBACVersionTagName=$this.Policy.ActiveCentralAccountsVersion}, $true)
				}
				else
				{
					if($this.FilterTags)
					{
						$this.PublishCustomMessage("No active accounts have been found that matches the specified tags. Tags:[$([string]::Join(",", $this.FilterTags))].", [MessageType]::Warning);
					}
					else
					{
						$this.PublishCustomMessage("No active accounts have been found that matches the specified tags.", [MessageType]::Warning);
					}
				}
			}
			else
			{
				$this.PublishCustomMessage("No active accounts found in the RBAC policy file", [MessageType]::Warning);
			}
				
			# Remove deprecated accounts
			$depAccounts = $this.GetMatchedDeprecatedAccounts(([ref]$messages));
			$messages += $this.RemoveRBACAccounts($depAccounts);
		}

		return $messages;
    }

	hidden [MessageData[]] RemoveRoleAssignments([RBACAccountRoleMapping[]] $rbacRoleMapping)
	{
		[MessageData[]] $messages = @();
		if($rbacRoleMapping.Count -ne 0)
		{
			$messages += [MessageData]::new("Total matching accounts found in the subscription: $($rbacRoleMapping.Count)");
			$provisionAccounts = @();
			$provisionAccounts += $rbacRoleMapping | Where-Object { $_.RBACAccount.Type -eq [RBACAccountType]::Provision };

			$messages += $this.RemoveRBACAccounts($provisionAccounts);

			$nonProvisionAccounts = @();
			$nonProvisionAccounts += $rbacRoleMapping | Where-Object { $_.RBACAccount.Type -ne [RBACAccountType]::Provision };

			if($nonProvisionAccounts.Count -ne 0)
			{
				$messageText = "Some accounts were not removed from the subscription, since the account type is not set to 'Provision' in RBAC policy file. Total accounts: $($nonProvisionAccounts.Count)";
				$messages += [MessageData]::new($messageText, ($nonProvisionAccounts | Select-Object -Property RoleAssignment));                                            
				#$this.PublishCustomMessage($messageText);
			}
		}
		return $messages;
	}

	hidden [MessageData[]] RemoveRBACAccounts([RBACAccountRoleMapping[]] $rbacRoleMapping)
	{
		[MessageData[]] $messages = @();
		if($rbacRoleMapping.Count -ne 0)
		{
			# Removing Central Accounts
			$messages += [MessageData]::new([Constants]::SingleDashLine + "`r`nRemoving following accounts from the subscription. Total accounts: $($rbacRoleMapping.Count)", ($rbacRoleMapping | Select-Object -Property RoleAssignment));
			$errorCount = 0;
			$currentCount = 0;
			$rbacRoleMapping | ForEach-Object {
				$accountName = $_.RoleAssignment.DisplayName;
				$currentCount += 1;
				if(-not [string]::IsNullOrWhiteSpace($_.RoleAssignment.SignInName))
				{
					$accountName += " ($($_.RoleAssignment.SignInName))";
				}
				# Remove account
				try
				{
					$this.PublishCustomMessage("Removing account [$accountName] from the subscription");
					Remove-AzureRmRoleAssignment -ObjectId $_.RoleAssignment.ObjectId -Scope $_.RoleAssignment.Scope -RoleDefinitionName $_.RoleAssignment.RoleDefinitionName -ErrorAction Stop | Out-Null                                         
				}
				catch
				{
					$messages += [MessageData]::new("Error while removing account [$accountName] from the subscription", $_, [MessageType]::Error);
					$errorCount += 1;
				}

				$this.CommandProgress($rbacRoleMapping.Count, $currentCount, 5);
			};

			[MessageData[]] $resultMessages = @();
			if($errorCount -eq 0)
			{
				$resultMessages += [MessageData]::new("All matched accounts have been removed from the subscription successfully`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
			}
			elseif($errorCount -eq $rbacRoleMapping.Count)
			{
				$resultMessages += [MessageData]::new("No accounts were removed due to an error. Please remove the accounts manually. You can find the specific account details in the log file.`r`n" + [Constants]::SingleDashLine, [MessageType]::Error);
			}
			else
			{
				$resultMessages += [MessageData]::new("$errorCount/$($rbacRoleMapping.Count) matched account(s) have not been removed from the subscription. Please remove the accounts manually.", [MessageType]::Error);
				$resultMessages += [MessageData]::new("$($rbacRoleMapping.Count - $errorCount)/$($rbacRoleMapping.Count) matched account(s) have been removed from the subscription successfully`r`n" + [Constants]::SingleDashLine, [MessageType]::Update);
			}

			$messages += $resultMessages;
			$this.PublishCustomMessage($resultMessages);
		}
		return $messages;
	}
}

class RBACAccountRoleMapping
{
	hidden [PSRoleAssignment] $RoleAssignment = $null;
	
	hidden [RBACAccount] $RBACAccount = $null;
}
