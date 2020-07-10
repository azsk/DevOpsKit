<#
.Description
# Extended base class for all classes being called from PS commands
# Provides functionality to fire important events at command call
#>

using namespace System.Management.Automation
Set-StrictMode -Version Latest
class AzCommandBase: CommandBase {

	#Region: Properties
	[bool] $IsLocalComplianceStoreEnabled = $false
	[bool] $IsComplianceStateCachingEnabled = $false
	#EndRegion

	#Region: Constructor 
    AzCommandBase([string] $subscriptionId, [InvocationInfo] $invocationContext): Base($subscriptionId, $invocationContext) {

		[Helpers]::AbstractClass($this, [AzCommandBase]);

		#Validate if command is getting run with correct Org Policy
		$IsTagSettingRequired = $this.ValidateOrgPolicyOnSubscription($this.Force)
		
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
		if(([Helpers]::CheckMember($commandMetadata,"HasAzSKComponentWritePermission")) -and  $commandMetadata.HasAzSKComponentWritePermission -and ($IsTagSettingRequired -or $this.Force))
		{
			#If command is running with Org-neutral Policy or switch Org policy, Set Org Policy tag on subscription
			$this.SetOrgPolicyTag($this.Force)
		}	

		$azskConfigComplianceFlag = [ConfigurationManager]::GetAzSKConfigData().StoreComplianceSummaryInUserSubscriptions;	
        $localSettingComplianceFlag = [ConfigurationManager]::GetAzSKSettings().StoreComplianceSummaryInUserSubscriptions;
        #return if feature is turned off at server config
        if($azskConfigComplianceFlag -or $localSettingComplianceFlag) 
		{
			$this.IsLocalComplianceStoreEnabled = $true
		}
		$this.IsComplianceStateCachingEnabled = $this.ValidateComplianceStateCaching();     
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
						if($AzSKConfigData.PolicyOrgName -eq [Constants]::OrgNameOSS)
						{
							throw [SuppressedException]::new(([Constants]::PolicyMismatchMsgOSS -f $OrgName, $AzSKConfigData.PolicyOrgName, $SubOrgTag.Value),[SuppressedExceptionType]::Generic)
							
						}
						else
						{	
							if(-not $Force)
							{
								if ($AzSKConfigData.PolicyOrgName -eq [Constants]::OrgNameCSEO) 
								{
									$this.PublishCustomMessage(([Constants]::PolicyMismatchMsgCSE -f $SubOrgTag.Value), [MessageType]::Warning);
								}
								else 
								{
									$this.PublishCustomMessage(([Constants]::PolicyMismatchMsg -f $OrgName, $AzSKConfigData.PolicyOrgName, $SubOrgTag.Value), [MessageType]::Warning);
								}
								$IsTagSettingRequired = $false
							}					
						}
					}              
				}
				elseif($AzSKConfigData.PolicyOrgName -ne [Constants]::OrgNameOSS){				
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

	#Function to check if ComplianceStateCaching tag is present on "AzSKRG" resource group
	#if this tag is missing, Compliance state table will not be used to store/fetch compliance data(default case)
	[bool] ValidateComplianceStateCaching()
	{
		$AzSKConfigData = [ConfigurationManager]::GetAzSKConfigData()
		$tagsOnRG =  [ResourceGroupHelper]::GetResourceGroupTags($AzSKConfigData.AzSKRGName)
		# if 
		if($tagsOnRG)
		{
			$ComplianceCacheTag = $tagsOnRG.GetEnumerator() | Where-Object {$_.Name -like "ComplianceStateCaching*"}
			if(($ComplianceCacheTag | Measure-Object).Count -gt 0)
			{
				$ComplianceCacheTagValue =$ComplianceCacheTag.Value		
				if(-not [string]::IsNullOrWhiteSpace($ComplianceCacheTagValue) -and  $ComplianceCacheTagValue -eq "true")
				{
					return $true
				}
			}			
		}
		return $false
	}
}