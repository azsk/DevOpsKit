Set-StrictMode -Version Latest
function Get-AzSKAzureServicesSecurityStatus 
{
	<#
	.SYNOPSIS
	This command would help in validating the security controls for the Azure resources meeting the specified input criteria.
	.DESCRIPTION
	This command will execute the security controls and will validate their status as 'Success' or 'Failure' based on the security guidance. Refer https://aka.ms/azskossdocs for more information 
	
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
	.PARAMETER ControlIds
		Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.
	.PARAMETER FilterTags
		Comma separated tags to filter the security controls. e.g.: RBAC, SOX, AuthN etc.
	.PARAMETER ExcludeTags
		Comma separated tags to exclude the security controls. e.g.: RBAC, SOX, AuthN etc.
	.PARAMETER AttestControls
		Enables users to attest controls with proper justification
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder containing all security evaluation report or not.
	.PARAMETER GeneratePDF
		Enables users to generate PDF file for reports.
	.PARAMETER UsePartialCommits
		This switch would partially save the scan status to the AzSK storage account. On the event of a failure, it tries to recover from the last snapshot. To use this feature, you need to have contributor role on the AzSK storage account.
	.PARAMETER UseBaselineControls
		This switch would scan only for baseline controls defined at org level
	.PARAMETER GenerateFixScript
		Switch to specify whether to generate script to fix the control or not.
	.PARAMETER ControlsToAttest
		Using this switch, AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.
	.PARAMETER BulkClear
		Use this option if you want to clear the attestation for multiple resources in bulk, for a specified controlId.
	.PARAMETER JustificationText
		Use this option to provide an apt justification with proper business reason.
	.PARAMETER AttestationStatus
		Attester must select one of the attestation reasons (NotAnIssue, WillNotFix, WillFixLater,NotApplicable,StateConfirmed)

	.NOTES
	This command helps the application team to verify whether their Azure resources are compliant with the security guidance or not 

	.LINK
	https://aka.ms/azskossdocs 

	#>
	[OutputType([String])]
	Param
	(

		[string]
        [Parameter(Position = 0, Mandatory = $true, HelpMessage="Subscription id for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("sid","s")]
		$SubscriptionId,

        [string]
        [Parameter(Position = 1,Mandatory = $false, ParameterSetName = "ResourceFilter")]
        [Parameter(Mandatory = $false, ParameterSetName = "BulkAttestation")]
        [Parameter(Mandatory = $false, ParameterSetName = "BulkAttestationClear")]
		[Alias("rgns")]
		$ResourceGroupNames,
        
        [string]
        [Parameter(Mandatory = $false, ParameterSetName = "ResourceFilter")]
		[Parameter(Mandatory = $false, ParameterSetName = "BulkAttestation")]
        [Parameter(Mandatory = $false, ParameterSetName = "BulkAttestationClear")]
		[Alias("rt")]
		$ResourceType,

		[Parameter(Mandatory = $false, ParameterSetName = "ResourceFilter")]
		[Parameter(Mandatory = $false, ParameterSetName = "BulkAttestation")]
        [Parameter(Mandatory = $false, ParameterSetName = "BulkAttestationClear")]
		[ResourceTypeName]
		[Alias("rtn")]
		$ResourceTypeName = [ResourceTypeName]::All,
        
        [string]
		[Parameter(Mandatory = $false, ParameterSetName = "ResourceFilter")]
		[Parameter(Mandatory = $false, ParameterSetName = "BulkAttestation")]
        [Parameter(Mandatory = $false, ParameterSetName = "BulkAttestationClear")]
		[Alias("ResourceName","rns")]
		$ResourceNames,
	
		[Hashtable] 
		[Parameter(Mandatory = $true, ParameterSetName = "TagHashset", HelpMessage='The tag filter for Azure resource. The expected format is @{tagName1=$null} or @{tagName = "tagValue"; tagName2="value1"}.')]
		$Tag,

        [string]
		[Parameter(Mandatory = $true, ParameterSetName = "TagName", HelpMessage="The name of the tag to query for Azure resource.")]
		[Alias("tgn")]
		$TagName,

        [string]
		[Parameter(Mandatory = $true, ParameterSetName = "TagName", HelpMessage="The value of the tag to query for Azure resource.")]
		[Alias("tgv")]
		$TagValue,

		[string] 
        [Parameter(Mandatory = $false, ParameterSetName = "ResourceFilter", HelpMessage="Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.")]
		[Parameter(Mandatory = $false, ParameterSetName = "TagHashset", HelpMessage="Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.")]
		[Alias("BulkAttestControlId","cids","bacid")]
		[AllowEmptyString()]
		$ControlIds,

		[string] 
		[Parameter(Mandatory = $false)]
		[Alias("ft")]
		$FilterTags,

		[string] 
		[Parameter(Mandatory = $false)]
		[Alias("xt")]
		$ExcludeTags,
        
		[ValidateSet("All","AlreadyAttested","NotAttested","None")]
        [Parameter(Mandatory = $false, ParameterSetName = "ResourceFilter", HelpMessage="Using this switch, AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $false, ParameterSetName = "TagHashset", HelpMessage="Using this switch, AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Using this switch, AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Using this switch, AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
		[Alias("AttestControls","cta")]
		$ControlsToAttest = [AttestControls]::None,

		[switch]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Use this option if you want to clear the attestation for multiple resources in bulk, for a specified controlId.")]
		[Alias("bc")]
		$BulkClear,

		[string] 
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Use this option to provide an apt justification with proper business reason.")]
		[Alias("jt")]
		$JustificationText,

		[ValidateSet("NotAnIssue", "WillNotFix", "WillFixLater","NotApplicable","StateConfirmed")] 
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Attester must select one of the attestation reasons (NotAnIssue, WillNotFix, WillFixLater, NotApplicable,StateConfirmed(if valid for the control))")]
		[Alias("as")]
		$AttestationStatus = [AttestationStatus]::None,

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("dnof")]
		$DoNotOpenOutputFolder,

		[GeneratePDF]
        [Parameter(Mandatory = $false)]
		[Alias("gpdf","pdf")]
		$GeneratePDF = [GeneratePDF]::None,

		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("ubc")]
		$UseBaselineControls,

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("upc")]
		$UsePartialCommits,		

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("gfs")]
		$GenerateFixScript,

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("iuc")]
		$IncludeUserComments
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
			$resolver = [SVTResourceResolver]::new($SubscriptionId, $ResourceGroupNames, $ResourceNames, $ResourceType, $ResourceTypeName);			
			$resolver.Tag = $Tag;
			$resolver.TagName = $TagName;
			$resolver.TagValue = $TagValue;			

			$secStatus = [ServicesSecurityStatus]::new($SubscriptionId, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{
				# Just copy all the tags without validation. Validation will be done internally
				$secStatus.FilterTags = $FilterTags;
				$secStatus.ExcludeTags = $ExcludeTags;
				$secStatus.ControlIdString = $ControlIds;
				$secStatus.GenerateFixScript = $GenerateFixScript;

				$secStatus.IncludeUserComments =$IncludeUserComments;

				[AttestationOptions] $attestationOptions = [AttestationOptions]::new();
				$attestationOptions.AttestControls = $ControlsToAttest				
				$attestationOptions.JustificationText = $JustificationText
				$attestationOptions.AttestationStatus = $AttestationStatus
				$attestationOptions.IsBulkClearModeOn = $BulkClear
				$secStatus.AttestationOptions = $attestationOptions;		

				return $secStatus.EvaluateControlStatus();
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

function Get-AzSKSubscriptionSecurityStatus
{
	<#
	.SYNOPSIS
	This command would help in validating the security controls for the Azure Subscription meeting the specified input criteria.
	.DESCRIPTION
	This command will execute the security controls and will validate their status as 'Success' or 'Failure' based on the security guidance. Refer https://aka.ms/azskossdocs for more information 
	
	.PARAMETER SubscriptionId
		Subscription id for which the security evaluation has to be performed.
	.PARAMETER ControlIds
		Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.
	.PARAMETER FilterTags
		Comma separated tags to filter the security controls. e.g.: RBAC, SOX, AuthN etc.
	.PARAMETER ExcludeTags
		Comma separated tags to exclude the security controls. e.g.: RBAC, SOX, AuthN etc.
	.PARAMETER AttestControls
		Enables users to attest controls with proper justification
	.PARAMETER BulkClear
		Enables users to clear the previous attestation per controlId basis in bulk mode
	.PARAMETER JustificationText
		Enables users to provide common justification for all the resources failing for a single controlId in the bulk attest mode
	.PARAMETER AttestationStatus
		Enables users to provide the attestation status for the failing control in bulk attest mode
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder containing all security evaluation report or not
	.PARAMETER GeneratePDF
		Enables users to generate PDF file for reports.
	.PARAMETER UseBaselineControls
		This switch would scan only for baseline controls defined at org level
	.PARAMETER GenerateFixScript
		Switch to specify whether to generate script to fix the control or not.
	.PARAMETER ControlsToAttest
		Using this switch,  AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.
    .PARAMETER IncludeUserComments
		Use this switch to display previously stored user comments for controls.
	.NOTES
	This command helps the application team to verify whether their Azure subscription are compliant with the security guidance or not 

	.LINK
	https://aka.ms/azskossdocs 

	#>
	[OutputType([String])]
	Param
	(
		[Parameter(Position = 0, Mandatory = $True, HelpMessage = "Subscription id for which the security evaluation has to be performed.")]
		[string]
		[ValidateNotNullOrEmpty()]
		[Alias("sid","s")]
		$SubscriptionId,
		
		[string] 
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.")]
		[Alias("BulkAttestControlId","cids","bacid")]		
		$ControlIds,
		
		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Comma separated tags to filter the security controls. e.g.: RBAC, SOX, AuthN etc.")]
		[Alias("ft")]
		$FilterTags,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Comma separated tags to exclude the security controls. e.g.: RBAC, SOX, AuthN etc.")]
		[Alias("xt")]
		$ExcludeTags,
		
		[ValidateSet("All","AlreadyAttested","NotAttested","None")]
        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Using this switch,  AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Using this switch,  AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Using this switch,  AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
		[Alias("AttestControls","cta")]
		$ControlsToAttest = [AttestControls]::None,

		[switch]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Use this option if you want to clear the attestation for multiple resources in bulk, for a specified controlId.")]
		[Alias("bc")]
		$BulkClear,

		[string] 
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Use this option to provide an apt justification with proper business reason.")]
		[Alias("jt")]
		$JustificationText,

		[ValidateSet("NotAnIssue", "WillNotFix", "WillFixLater","NotApplicable","StateConfirmed")] 
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Attester must select one of the attestation reasons (NotAnIssue, WillNotFix, WillFixLater, NotApplicable, StateConfirmed(if valid for the control))")]
		[Alias("as")]
		$AttestationStatus = [AttestationStatus]::None,
			
		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("dnof")]
		$DoNotOpenOutputFolder,
		
		[GeneratePDF]
        [Parameter(Mandatory = $false)]
		[Alias("gpdf","pdf")]
		$GeneratePDF = [GeneratePDF]::None,

		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("ubc")]
		$UseBaselineControls,

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("gfs")]
		$GenerateFixScript,

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("iuc")]
		$IncludeUserComments
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
			$sscore = [SubscriptionSecurityStatus]::new($SubscriptionId, $PSCmdlet.MyInvocation);
			if ($sscore) 
			{
				# Just copy all the tags without validation. Validation will be done internally
				$sscore.FilterTags = $FilterTags;
				$sscore.ExcludeTags = $ExcludeTags;
				$sscore.ControlIdString = $ControlIds;

                $sscore.IncludeUserComments =$IncludeUserComments;

				#build the attestation options object
				[AttestationOptions] $attestationOptions = [AttestationOptions]::new();
				$attestationOptions.AttestControls = $ControlsToAttest				
				$attestationOptions.JustificationText = $JustificationText
				$attestationOptions.AttestationStatus = $AttestationStatus
				$attestationOptions.IsBulkClearModeOn = $BulkClear
				$sscore.AttestationOptions = $attestationOptions;				
				
				$sscore.GenerateFixScript = $GenerateFixScript
				return $sscore.EvaluateControlStatus();
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

function Get-AzSKExpressRouteNetworkSecurityStatus
{
	<#
	.SYNOPSIS
	This command would help in validating the security controls for the ExpressRoute enabled VNet resources meeting the specified input criteria.
	.DESCRIPTION
	This command will execute the security controls and will validate their status as 'Success' or 'Failure' based on the security guidance. Refer https://aka.ms/azskossdocs for more information 
	
	.PARAMETER SubscriptionId
		Subscription id for which the security evaluation has to be performed.
	.PARAMETER ResourceGroupNames
		ResourceGroups which host ExpressRoute VNets. Comma separated values are supported. Wildcards are not permitted. By default, the command gets all resources in the subscription.
	.PARAMETER ResourceName
		ExpressRoute VNet resource name. Wildcards are not permitted. By default, the command gets all resources in the subscription.
	.PARAMETER FilterTags
		Comma separated tags to filter the security controls. e.g.: RBAC, SOX, AuthN etc.
	.PARAMETER ExcludeTags
		Comma separated tags to exclude the security controls. e.g.: RBAC, SOX, AuthN etc.
	.PARAMETER AttestControls
		Enables users to attest controls with proper justification
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder containing all security evaluation report or not.
	.PARAMETER GeneratePDF
		Enables users to generate PDF file for reports.
	.PARAMETER ControlIds
		Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.
	.PARAMETER ControlsToAttest
			Using this switch,  AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.
	.PARAMETER GenerateFixScript
			 Provide this option to automatically generate scripts that can be run to address the control failures

	.NOTES
	This command helps the application team to verify whether their ExpressRoute enabled VNets are compliant with the security guidance or not 

	.LINK
	https://aka.ms/azskossdocs 

	#>
	[OutputType([String])]
	Param(
		[string]
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Provide the subscription id for which the security report has to be generated")]
		[ValidateNotNullOrEmpty()]
		[Alias("sid","s")]
		$SubscriptionId,

        [string]
        [Parameter(Mandatory = $false, HelpMessage = "ResourceGroups which host ExpressRoute VNets. Comma separated values are supported. Wildcards are not permitted. By default, the command gets all resources in the subscription.")]
		[Alias("rgns")]
		$ResourceGroupNames,
        
        [string]
		[Parameter(Mandatory = $false, ParameterSetName = "ResourceFilter", HelpMessage = "ExpressRoute VNet resource name. Wildcards are not permitted. By default, the command gets all resources in the subscription.")]
		[Alias("rn")]
		$ResourceName,
	
		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.")]
		[Alias("cids")]
		$ControlIds,
		
		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Comma separated tags to filter the security controls. e.g.: RBAC, SOX, AuthN etc.")]
		[Alias("ft")]
		$FilterTags,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Comma separated tags to exclude the security controls. e.g.: RBAC, SOX, AuthN etc.")]
		[Alias("xt")]
		$ExcludeTags,		
                
		[ValidateSet("All","AlreadyAttested","NotAttested","None")]
		[AttestControls]
        [Parameter(Mandatory = $false, HelpMessage = "Enables users to attest controls with proper justification.")]
		[Alias("AttestControls","cta")]
		$ControlsToAttest = [AttestControls]::None,

		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder containing all security evaluation report or not.")]
		[Alias("dnof")]
		$DoNotOpenOutputFolder,

		[GeneratePDF]
        [Parameter(Mandatory = $false, HelpMessage = "Enables users to generate PDF file for reports.")]
		[Alias("gpdf","pdf")]
		$GeneratePDF  = [GeneratePDF]::None,
		
		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to generate script to fix the control or not.")]
		[Alias("gfs")]
		$GenerateFixScript
    )

	$erResourceGroups = $ResourceGroupNames;

	if([string]::IsNullOrEmpty($erResourceGroups))
    {
		$erResourceGroups = [ConfigurationManager]::GetAzSKConfigData().ERvNetResourceGroupNames
	}

	Get-AzSKAzureServicesSecurityStatus -SubscriptionId $SubscriptionId -ResourceGroupNames $erResourceGroups -ResourceName $ResourceName `
			-ResourceTypeName ([SVTMapping]::ERvNetTypeName) -ControlIds $ControlIds -FilterTags $FilterTags -ExcludeTags $ExcludeTags -DoNotOpenOutputFolder:$DoNotOpenOutputFolder -AttestControls $ControlsToAttest -GeneratePDF $GeneratePDF -GenerateFixScript:$GenerateFixScript
}

function Get-AzSKControlsStatus
{
	<#
	.SYNOPSIS
	This command would help in validating the security controls for the Azure resources meeting the specified input criteria.
	.DESCRIPTION
	This command will execute the security controls and will validate their status as 'Success' or 'Failure' based on the security guidance. Refer https://aka.ms/azskossdocs for more information 
	
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
	.PARAMETER ExcludeTags
		Comma separated tags to exclude the security controls. e.g.: RBAC, SOX, AuthN etc.
	.PARAMETER AttestControls
		Enables users to attest controls with proper justification
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder containing all security evaluation report or not.
	.PARAMETER GeneratePDF
		Enables users to generate PDF file for reports.
	.PARAMETER UsePartialCommits
		This switch would partially save the scan status to the AzSK storage account. On the event of a failure, it tries to recover from the last snapshot. To use this feature, you need to have contributor role on the AzSK storage account.
	.PARAMETER UseBaselineControls
		This switch would scan only for baseline controls defined at org level
	.PARAMETER GenerateFixScript
		Switch to specify whether to generate script to fix the control or not.
	.PARAMETER ControlIds
		Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.
	.PARAMETER ControlsToAttest
			Using this switch,  AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.
	.PARAMETER BulkClear
			Use this option if you want to clear the attestation for multiple resources in bulk, for a specified controlId.
	.PARAMETER JustificationText
			Use this option to provide an apt justification with proper business reason.
	.PARAMETER AttestationStatus
			Attester must select one of the attestation reasons (NotAnIssue, WillNotFix, WillFixLater,NotApplicable,StateConfirmed)

	.NOTES
	This command helps the application team to verify whether their Azure resources are compliant with the security guidance or not 

	.LINK
	https://aka.ms/azskossdocs 

	#>
	[OutputType([String])]
	Param
	(

		[string]
        [Parameter(Position = 0, Mandatory = $true, HelpMessage="Subscription id for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("sid","s")]
		$SubscriptionId,

        [string]
        [Parameter(Mandatory = $false, ParameterSetName = "ResourceFilter")]
		[Alias("rgns")]
		$ResourceGroupNames,
        
        [string]
        [Parameter(Mandatory = $false, ParameterSetName = "ResourceFilter")]
		[Alias("rt")]
		$ResourceType,

		[Parameter(Mandatory = $false, ParameterSetName = "ResourceFilter")]
		[ResourceTypeName]
		[Alias("rtn")]
		$ResourceTypeName = [ResourceTypeName]::All,
        
        [string]
		[Parameter(Mandatory = $false, ParameterSetName = "ResourceFilter")]
		[Alias("ResourceName","rns")]
		$ResourceNames,
	
		[Hashtable] 
		[Parameter(Mandatory = $true, ParameterSetName = "TagHashset", HelpMessage='The tag filter for Azure resource. The expected format is @{tagName1=$null} or @{tagName = "tagValue"; tagName2="value1"}.')]
		$Tag,

        [string]
		[Parameter(Mandatory = $true, ParameterSetName = "TagName", HelpMessage="The name of the tag to query for Azure resource.")]
		[Alias("tgn")]
		$TagName,

        [string]
		[Parameter(Mandatory = $true, ParameterSetName = "TagName", HelpMessage="The value of the tag to query for Azure resource.")]
		[Alias("tgv")]
		$TagValue,

		[string] 
        [Parameter(Mandatory = $false, ParameterSetName = "ResourceFilter", HelpMessage="Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.")]
		[Parameter(Mandatory = $false, ParameterSetName = "TagHashset", HelpMessage="Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Comma separated control ids to filter the security controls. e.g.: Azure_Subscription_AuthZ_Limit_Admin_Owner_Count, Azure_Storage_DP_Encrypt_At_Rest_Blob etc.")]
		[Alias("BulkAttestControlId","cids","bacid")]		
		$ControlIds,

		[string] 
		[Parameter(Mandatory = $false)]
		[Alias("ft")]
		$FilterTags,

		[string] 
		[Parameter(Mandatory = $false)]
		[Alias("xt")]
		$ExcludeTags,
                
		[ValidateSet("All","AlreadyAttested","NotAttested","None")] 
        [Parameter(Mandatory = $false, ParameterSetName = "ResourceFilter", HelpMessage="Using this switch,  AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $false, ParameterSetName = "TagHashset", HelpMessage="Using this switch,  AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Using this switch,  AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Using this switch,  AzSK enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
		[Alias("AttestControls","cta")]
		$ControlsToAttest = [AttestControls]::None,

		[switch]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Use this option if you want to clear the attestation for multiple resources in bulk, for a specified controlId.")]
		[Alias("bc")]
		$BulkClear,

		[string] 
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Use this option to provide an apt justification with proper business reason.")]
		[Alias("jt")]
		$JustificationText,

		[ValidateSet("NotAnIssue", "WillNotFix", "WillFixLater","NotApplicable","StateConfirmed")] 
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Attester must select one of the attestation reasons (NotAnIssue, WillNotFix, WillFixLater, NotApplicable, StateConfirmed(if valid for the control))")]
		[Alias("as")]
		$AttestationStatus = [AttestationStatus]::None,

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("dnof")]
		$DoNotOpenOutputFolder,

		[GeneratePDF]
        [Parameter(Mandatory = $false)]
		[Alias("gpdf","pdf")]
		$GeneratePDF  = [GeneratePDF]::None,

		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("ubc")]
		$UseBaselineControls,

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("upc")]
		$UsePartialCommits,		
		
		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("gfs")]
		$GenerateFixScript,

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("iuc")]
		$IncludeUserComments
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
			$resolver = [SVTResourceResolver]::new($SubscriptionId, $ResourceGroupNames, $ResourceNames, $ResourceType, $ResourceTypeName);						
			$resolver.Tag = $Tag;
			$resolver.TagName = $TagName;
			$resolver.TagValue = $TagValue;
		
			$controlReport = [SVTStatusReport]::new($SubscriptionId, $PSCmdlet.MyInvocation, $resolver);
			if ($controlReport) 
			{
				# Just copy all the tags without validation. Validation will be done internally
				$controlReport.FilterTags = $FilterTags;
				$controlReport.ExcludeTags = $ExcludeTags;
				$controlReport.ControlIdString = $ControlIds;
				$controlReport.GenerateFixScript = $GenerateFixScript;
				$controlReport.IncludeUserComments =$IncludeUserComments;

				#build the attestation options object
				[AttestationOptions] $attestationOptions = [AttestationOptions]::new();
				$attestationOptions.AttestControls = $ControlsToAttest				
				$attestationOptions.JustificationText = $JustificationText
				$attestationOptions.AttestationStatus = $AttestationStatus
				$attestationOptions.IsBulkClearModeOn = $BulkClear
				$controlReport.AttestationOptions = $attestationOptions;	

				return $controlReport.EvaluateControlStatus();
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
