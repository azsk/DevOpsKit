Set-StrictMode -Version Latest
function Get-AzSKInfo
{
	
	<#
	.SYNOPSIS
	This command would help users to get details of various components of AzSK.
	
	.DESCRIPTION
	This command will fetch details of AzSK components and help user to provide details of different component using single command. Refer https://aka.ms/azskossdocs for more information 
	
	.PARAMETER InfoType
		InfoType for which type of information required by user.
	.PARAMETER SubscriptionId
		Subscription id for which the security evaluation has to be performed.
	.PARAMETER ResourceGroupNames
		ResourceGroups for which the security evaluation has to be performed. Comma separated values are supported. Wildcards are not permitted. By default, the command gets all resources in the subscription.
	.PARAMETER ResourceType
		Gets only resources of the specified resource type. Wildcards are not permitted. e.g.: Microsoft.KeyVault/vaults. Run command 'Get-AzSKSupportedResourceTypes' to get the list of supported types.
	.PARAMETER ResourceTypeName
		Friendly name of resource type. e.g.: KeyVault. Run command 'Get-AzSKSupportedResourceTypes' to get the list of supported values.
	.PARAMETER ResourceNames
		Gets a resource with the specified name. Comma separated values are supported. Wildcards/like searches are not permitted. By default, the command gets all resources in the subscription.
	.PARAMETER Tag
		The tag filter for Azure resource. The expected format is @{tagName1=$null} or @{tagName = 'tagValue'; tagName2='value1'}.
	.PARAMETER TagName
		The name of the tag to query for Azure resource.
	.PARAMETER TagValue
		The value of the tag to query for Azure resource.
	.PARAMETER FilterTags
		Comma separated tags to filter the security controls. e.g.: RBAC, SOX, AuthN etc.
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder containing all security evaluation report or not.
	.PARAMETER UseBaselineControls
		This switch would scan only for baseline controls defined at org level
	.PARAMETER ControlIds
		Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.
	.PARAMETER ControlSeverity
			Select one of the control severity (Critical, High, Low, Medium)
	.PARAMETER ControlIdContains
			The list of control ids for which fixes should be applied.

	.NOTES
	This command helps the application team to verify whether their Azure resources are compliant with the security guidance or not 

	.LINK
	https://aka.ms/azskossdocs 

	#>
	Param(
		[Parameter(Mandatory = $false)]
		[ValidateSet("SubscriptionInfo", "ControlInfo", "HostInfo" , "AttestationInfo", "ComplianceInfo")] 
		$InfoType,

		[ResourceTypeName]
		$ResourceTypeName = [ResourceTypeName]::All,

		[string]
        $ResourceType,

		[string]
        $ControlIds,

		[switch]
        $UseBaselineControls,

		[string]
        $FilterTags,

		[string]
        $SubscriptionId,

		[string]
        $ResourceGroupNames,

		[string]
		[Alias("ResourceName")]
		$ResourceNames,

		[ValidateSet("Critical", "High", "Medium" , "Low")] 
		$ControlSeverity,

		[string]
		$ControlIdContains,

		[switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder.")]
		$DoNotOpenOutputFolder
    )

	Begin
	{
		[CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
		[ListenerHelper]::RegisterListeners();
	}

	Process
	{
		try 
		{
			if ([string]::IsNullOrEmpty($SubscriptionId))
			{
				if((-not [string]::IsNullOrEmpty($InfoType)) -and ($InfoType.ToString() -eq 'AttestationInfo' -or $InfoType.ToString() -eq 'ComplianceInfo'))
				{
					$SubscriptionId = Read-Host "SubscriptionId"
					$SubscriptionId = $SubscriptionId.Trim()
				}
				else
				{
					$SubscriptionId = [Constants]::BlankSubscriptionId
				}
			}

			if(-not [string]::IsNullOrEmpty($InfoType))
			{
				switch ($InfoType.ToString()) 
				{
					SubscriptionInfo 
					{
						$basicInfo = [BasicInfo]::new($SubscriptionId, $PSCmdlet.MyInvocation);
						if ($basicInfo) 
						{
							return $basicInfo.InvokeFunction($basicInfo.GetBasicInfo);
						}
					}
					ControlInfo 
					{
						If($PSCmdlet.MyInvocation.BoundParameters["Verbose"] -and $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent)
						{
							$Full = $true
						}
						else
						{
							$Full = $false
						}

						$controlsInfo = [ControlsInfo]::new($SubscriptionId, $PSCmdlet.MyInvocation, $ResourceTypeName, $ResourceType, $ControlIds, $UseBaselineControls, $FilterTags, $Full, $ControlSeverity, $ControlIdContains);
						if ($controlsInfo) 
						{
							return $controlsInfo.InvokeFunction($controlsInfo.GetControlDetails);
						}
					}
					HostInfo 
					{
						$environmentInfo = [EnvironmentInfo]::new($SubscriptionId, $PSCmdlet.MyInvocation);
						if ($environmentInfo) 
						{
							return $environmentInfo.InvokeFunction($environmentInfo.GetEnvironmentInfo);
						}
					}
					AttestationInfo
					{
						if([string]::IsNullOrWhiteSpace($ResourceType) -and [string]::IsNullOrWhiteSpace($ResourceTypeName))
						{
							$ResourceTypeName = [ResourceTypeName]::All
						}
						$resolver = [SVTResourceResolver]::new($SubscriptionId, $ResourceGroupNames, $ResourceNames, $ResourceType, $ResourceTypeName);			

						$attestationReport = [SVTStatusReport]::new($SubscriptionId, $PSCmdlet.MyInvocation, $resolver);
						if ($attestationReport) 
						{
							$attestationReport.ControlIdString = $ControlIds;

							[AttestationOptions] $attestationOptions = [AttestationOptions]::new();
							#$attestationOptions.AttestationStatus = $AttestationStatus
							$attestationReport.AttestationOptions = $attestationOptions;		
							return  ([CommandBase]$attestationReport).InvokeFunction($attestationReport.FetchAttestationInfo);	
						}     
					}
					ComplianceInfo
					{
						If($PSCmdlet.MyInvocation.BoundParameters["Verbose"] -and $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent)
						{
							$Full = $true
						}
						else
						{
							$Full = $false
						}
						$complianceInfo = [ComplianceInfo]::new($SubscriptionId, $PSCmdlet.MyInvocation, $Full);
						if ($complianceInfo) 
						{
							return $complianceInfo.InvokeFunction($complianceInfo.GetComplianceInfo);
						}
					}
					Default
					{
						Write-Host $([Constants]::DefaultInfoCmdMsg)
					}
				}
			}
			else
			{
				Write-Host $([Constants]::DefaultInfoCmdMsg)
			}
		}
		catch 
		{
			[EventBase]::PublishGenericException($_);
		}  
	}

	End
	{
		[ListenerHelper]::UnregisterListeners();
	}
}
function Update-AzSKPersistedState 
{	
	<#
	.SYNOPSIS
	This command helps in updating security state stored by DevOps Kit.

	.DESCRIPTION
	This command helps in updating security state stored by DevOps Kit.
	
	.PARAMETER SubscriptionId
		Subscription id for which DevOps Kit state has to be updated.
	.PARAMETER StateType
		This represents the specific type of DevOps Kit state that has to be updated.
	.PARAMETER FilePath
		Path to file containing list of controls for which state has to be updated.	
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder containing all security evaluation report or not.

	.LINK
	https://aka.ms/azskossdocs 
	#>
	Param(

		[string]
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Subscription id for which DevOps Kit state has to be updated.", ParameterSetName = "Default")]
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Subscription id for which DevOps Kit state has to be updated.", ParameterSetName = "UserComments")]
		[ValidateNotNullOrEmpty()]
		[Alias("sid")]
		$SubscriptionId,

		[string]
		[Parameter(Mandatory = $false, HelpMessage = "Path to file containing list of controls for which state has to be updated.", ParameterSetName = "UserComments")]
		$FilePath,

		[ValidateSet("UserComments")]
		[Parameter(Mandatory = $true, HelpMessage = "This represents the specific type of DevOps Kit state that has to be updated.", ParameterSetName = "UserComments")]
		$StateType,
	
		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder containing all security evaluation report or not.", ParameterSetName = "Default")]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder containing all security evaluation report or not.", ParameterSetName = "UserComments")]
		$DoNotOpenOutputFolder
    )

	Begin
	{
		[CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
		[ListenerHelper]::RegisterListeners();
	}

	Process
	{
		try 
		{
			$persistedStateInfo = [PersistedStateInfo]::new($SubscriptionId, $PSCmdlet.MyInvocation);
			if ($persistedStateInfo -and $StateType -eq "UserComments") 
			{
				return $persistedStateInfo.InvokeFunction($persistedStateInfo.UpdatePersistedState,@($FilePath));
			}
		}
		catch 
		{
			[EventBase]::PublishGenericException($_);
		}  		
	}

	End
	{
		[ListenerHelper]::UnregisterListeners();
	}
}



function Get-AzSKSecurityRecommendationReport 
{	
	[OutputType([String])]
	Param
	(

		[string]
        [Parameter(Position = 0, Mandatory = $true, HelpMessage="Subscription id for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("sid", "s")]
		$SubscriptionId,

        [string]
        [Parameter(Mandatory = $true, ParameterSetName = "ResourceGroupName")]
		[Alias("rgn")]
		$ResourceGroupName,

		[string[]]		
        [Parameter(Mandatory = $true, ParameterSetName = "Categories")]
		$Categories,
        
        [Parameter(Mandatory = $true, ParameterSetName = "ResourceTypeNames")]
		[ResourceTypeName[]]
		[Alias("rtns")]
		$ResourceTypeNames
    )

	Begin
	{
		[CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
		[ListenerHelper]::RegisterListeners();
	}

	Process
	{
	try 
		{
			$SecurityRecommendationsReport = [SecurityRecommendationsReport]::new($SubscriptionId, $PSCmdlet.MyInvocation);
			if ($SecurityRecommendationsReport) 
			{
				return $SecurityRecommendationsReport.InvokeFunction($SecurityRecommendationsReport.GenerateReport,@($ResourceGroupName, $ResourceTypeNames,$Categories));
			}
		}
		catch 
		{
			[EventBase]::PublishGenericException($_);
		}  
	}

	End
	{
		[ListenerHelper]::UnregisterListeners();
	}
}

