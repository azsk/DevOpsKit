<#
.Description
# Extended base class for all classes being called from PS commands
# Provides functionality to fire important events at command call
#>

using namespace System.Management.Automation
Set-StrictMode -Version Latest
class CommandBaseExt: AzSKRoot {

	#Region: Properties
	[bool] $IsLocalComplianceStoreEnabled = $false
	#EndRegion

	#Region: Constructor 
    CommandBaseExt([string] $subscriptionId, [InvocationInfo] $invocationContext): Base($subscriptionId) {

		[Helpers]::AbstractClass($this, [CommandBaseExt]);
		
		if (-not $invocationContext) {
            throw [System.ArgumentException] ("The argument 'invocationContext' is null. Pass the `$PSCmdlet.MyInvocation from PowerShell command.");
        }	
		
        #<TODO Framework: Optimize force parameter from root location>
        $this.InvocationContext = $invocationContext;
		$force = $false
		if($null -ne $invocationContext.BoundParameters["Force"])
		{
			$force = $invocationContext.BoundParameters["Force"];
		}

		#Validate if command is getting run with correct Org Policy
		$IsTagSettingRequired = $this.ValidateOrgPolicyOnSubscription($force)
		
		#Validate if policy url token is getting expired 
		$onlinePolicyStoreUrl = [ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl
		
		if([Helpers]::IsSASTokenUpdateRequired($onlinePolicyStoreUrl))
		{
			#Check if CA Setup Runbook URL token is valid and update it with local policy token
			$CASetupRunbookUrl = [ConfigurationManager]::GetAzSKConfigData().CASetupRunbookURL
			if(-not [Helpers]::IsSASTokenUpdateRequired($CASetupRunbookUrl))
			{
				[ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl = [Helpers]::GetUriWithUpdatedSASToken($onlinePolicyStoreUrl,$CASetupRunbookUrl)				
				[AzSKSettings]::Update([ConfigurationManager]::GetAzSKSettings())
			}
			else
			{
				[EventBase]::PublishGenericCustomMessage("Org policy settings is getting expired. Please run installer(IWR) command to update with latest policy. ", [MessageType]::Warning);
			}
		}

		 #Validate if command has AzSK component write permission
		$commandMetadata= $this.GetCommandMetadata()
		if(([Helpers]::CheckMember($commandMetadata,"HasAzSKComponentWritePermission")) -and  $commandMetadata.HasAzSKComponentWritePermission -and ($IsTagSettingRequired -or $force))
		{
			#If command is running with Org-neutral Policy or switch Org policy, Set Org Policy tag on subscription
			$this.SetOrgPolicyTag($force)
		}	

		$azskConfigComplianceFlag = [ConfigurationManager]::GetAzSKConfigData().StoreComplianceSummaryInUserSubscriptions;	
        $localSettingComplianceFlag = [ConfigurationManager]::GetAzSKSettings().StoreComplianceSummaryInUserSubscriptions;
        #return if feature is turned off at server config
        if($azskConfigComplianceFlag -or $localSettingComplianceFlag) 
		{
			$this.IsLocalComplianceStoreEnabled = $true
		}     
		#clear azsk storage instance
		[StorageHelper]::AzSKStorageHelperInstance = $null;

    }
	#EndRegion

	#Function to validate Org policy on subscription based on tag present on "AzSKRG" resource group
	[bool] ValidateOrgPolicyOnSubscription([bool] $Force)
	{
		$AzSKConfigData = [ConfigurationManager]::GetAzSKConfigData()
		$tagsOnSub =  [ResourceGroupHelper]::GetResourceGroupTags($AzSKConfigData.AzSKRGName)
		$IsTagSettingRequired = $false
		$commandMetadata= $this.GetCommandMetadata()
		if(([Helpers]::CheckMember($commandMetadata,"IsOrgPolicyMandatory")) -and  $commandMetadata.IsOrgPolicyMandatory)
		{
			if($tagsOnSub)
			{
				$SubOrgTag= $tagsOnSub.GetEnumerator() | Where-Object {$_.Name -like "AzSKOrgName*"}
				
				if(($SubOrgTag | Measure-Object).Count -gt 0)
				{
					$OrgName =$SubOrgTag.Name.Split("_")[1]		
					if(-not [string]::IsNullOrWhiteSpace($OrgName) -and  $OrgName -ne $AzSKConfigData.PolicyOrgName)
					{
						if($AzSKConfigData.PolicyOrgName -eq "org-neutral")
						{
							throw [SuppressedException]::new("The current subscription has been configured with DevOps kit policy for the '$OrgName' Org, However the DevOps kit command is running with a different ('$($AzSKConfigData.PolicyOrgName)') Org policy. `nPlease review FAQ at: https://aka.ms/devopskit/orgpolicy/faq and correct this condition depending upon which context(manual,CICD,CA scan) you are seeing this error. If FAQ does not help to resolve the issue, please contact your Org policy Owner ($($SubOrgTag.Value)).",[SuppressedExceptionType]::Generic)
							
						}
						else
						{	
							if(-not $Force)
							{
								$this.PublishCustomMessage("Warning: The current subscription has been configured with DevOps kit policy for the '$OrgName' Org, However the DevOps kit command is running with a different ('$($AzSKConfigData.PolicyOrgName)') Org policy. `nPlease review FAQ at: https://aka.ms/devopskit/orgpolicy/faq and correct this condition depending upon which context(manual,CICD,CA scan) you are seeing this error. If FAQ does not help to resolve the issue, please contact your Org policy Owner ($($SubOrgTag.Value)).",[MessageType]::Warning);
								$IsTagSettingRequired = $false
							}					
						}
					}              
				}
				elseif($AzSKConfigData.PolicyOrgName -ne "org-neutral"){				
					$IsTagSettingRequired =$true			
				}			 
			}
			else {
				$IsTagSettingRequired = $true
			}
		}
		return $IsTagSettingRequired	
	}

	#Function to set Org policy tag
	[void] SetOrgPolicyTag([bool] $Force)
	{
		try
		{
			$AzSKConfigData = [ConfigurationManager]::GetAzSKConfigData()
			$tagsOnSub =  [ResourceGroupHelper]::GetResourceGroupTags($AzSKConfigData.AzSKRGName) 
			if($tagsOnSub)
			{
				$SubOrgTag= $tagsOnSub.GetEnumerator() | Where-Object {$_.Name -like "AzSKOrgName*"}			
				if(
                    (($SubOrgTag | Measure-Object).Count -eq 0 -and $AzSKConfigData.PolicyOrgName -ne "org-neutral") -or 
                    (($SubOrgTag | Measure-Object).Count -gt 0 -and $AzSKConfigData.PolicyOrgName -ne "org-neutral" -and $AzSKConfigData.PolicyOrgName -ne $SubOrgTag.Value -and $Force))
				{
					if(($SubOrgTag | Measure-Object).Count -gt 0)
					{
						$SubOrgTag | ForEach-Object{
							[ResourceGroupHelper]::SetResourceGroupTags($AzSKConfigData.AzSKRGName,@{$_.Name=$_.Value}, $true)               
						}
					}
					$TagName = [Constants]::OrgPolicyTagPrefix +$AzSKConfigData.PolicyOrgName
					$SupportMail = $AzSKConfigData.SupportDL
					if(-not [string]::IsNullOrWhiteSpace($SupportMail) -and  [Constants]::SupportDL -eq $SupportMail)
					{
						$SupportMail = "Not Available"
					}   
					[ResourceGroupHelper]::SetResourceGroupTags($AzSKConfigData.AzSKRGName,@{$TagName=$SupportMail}, $false)                
									
				}
                					
			}
		}
		catch{
			# Exception occurred during setting tag. This is kept blank intentionaly to avoid flow break
		}
	}
}
