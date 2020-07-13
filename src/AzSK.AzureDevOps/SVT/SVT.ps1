Set-StrictMode -Version Latest

function Get-AzSKAzureDevOpsSecurityStatus
{
	<#
	.SYNOPSIS
	This command would help in validating the security controls for the Azure resources meeting the specified input criteria.
	.DESCRIPTION
	This command will execute the security controls and will validate their status as 'Success' or 'Failure' based on the security guidance. Refer https://aka.ms/azskossdocs for more information 
	
	.PARAMETER OrganizationName
		Organization name for which the security evaluation has to be performed.
	
	.PARAMETER ProjectNames
		Project name for which the security evaluation has to be performed.

	.PARAMETER BuildNames
		Build name for which the security evaluation has to be performed.

	.PARAMETER ReleaseNames
		Release name for which the security evaluation has to be performed.

	.PARAMETER AgentPoolNames
	   Agent name for which the security evaluation has to be performed.	

	.NOTES
	This command helps the application team to verify whether their Azure resources are compliant with the security guidance or not 

	.LINK
	https://aka.ms/azskossdocs 

	#>

	[OutputType([String])]
	Param
	(

		[string]		 
		[Parameter(Position = 0, Mandatory = $true, HelpMessage="OrganizationName for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("oz")]
		$OrganizationName,

		[string]
		[Parameter( HelpMessage="Project names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("pn")]
		$ProjectNames,

		[string]
		[Parameter(HelpMessage="Build names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("bn")]
		$BuildNames,

		[string]
		[Parameter(HelpMessage="Release names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("rn")]
		$ReleaseNames,

		[string]
		[Parameter(HelpMessage="Agent Pool names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("ap")]
		$AgentPoolNames,

		
		[string]
		[Parameter(HelpMessage="Service connection names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("sc")]
		$ServiceConnectionNames,

		[switch]
		[Parameter(HelpMessage="Scan all supported artificats present under organization like build, release, projects etc.")]
		[Alias("sa")]
		$ScanAllArtifacts,

		[string] 
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Alias("BulkAttestControlId","cids","bacid")]
		[AllowEmptyString()]
		$ControlIds,

		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("ubc")]
		$UseBaselineControls,

		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("upbc")]
		$UsePreviewBaselineControls,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage="Specify the severity of controls to be scanned. Example `"High, Medium`"")]
		[Alias("ControlSeverity")]
		$Severity,

		[int]
		[Parameter(Mandatory = $false, HelpMessage="Max # of objects to check. Default is 0 which means scan all.")]
		[Alias("mo")]
		$MaxObj = 0,

		[System.Security.SecureString]
		[Parameter(HelpMessage="Token to run scan in non-interactive mode")]
		[Alias("tk")]
		$PATToken,

		[ResourceTypeName]
		[Alias("rtn")]
		$ResourceTypeName = [ResourceTypeName]::All,

        [switch]
        [Parameter(Mandatory = $false)]
		[Alias("upc")]
		$UsePartialCommits,	

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("dnof")]
		$DoNotOpenOutputFolder,

		[ValidateSet("All","AlreadyAttested","NotAttested","None")]
        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Using this switch,  AzSK.AzureDevOps enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Using this switch,  AzSK.AzureDevOps enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Using this switch,  AzSK.AzureDevOps enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
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

		[ValidateSet("NotAnIssue", "WillNotFix", "WillFixLater","NotApplicable","StateConfirmed","ApprovedException")] 
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Attester must select one of the attestation reasons (NotAnIssue, WillNotFix, WillFixLater, NotApplicable, StateConfirmed(if valid for the control))")]
		[Alias("as")]
		$AttestationStatus = [AttestationStatus]::None,
		
		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("aex")]
		$AddException,

		[string]
		[Parameter(HelpMessage="Project name to store attestation details for organization-specific controls.")]
		[ValidateNotNullOrEmpty()]
		[Alias("atp")]
		$AttestationHostProjectName,


		[ValidateSet("All","BaselineControls","PreviewBaselineControls")]
		[Parameter(Mandatory = $false)]
		[Alias("abl")]		
		[string] $AutoBugLog="All",		

		[string]
		[Parameter(Mandatory=$false)]
		[Alias("apt")]
		$AreaPath,

		[string]
		[Parameter(Mandatory=$false)]
		[Alias("ipt")]
		$IterationPath,

		[switch]
		[Parameter(HelpMessage="Allow long running scan.")]
		[Alias("als")]
		$AllowLongRunningScan



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
				$resolver = [SVTResourceResolver]::new($OrganizationName,$ProjectNames,$BuildNames,$ReleaseNames,$AgentPoolNames, $ServiceConnectionNames, $MaxObj, $ScanAllArtifacts, $PATToken,$ResourceTypeName, $AllowLongRunningScan);
			    $secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			    if ($secStatus) 
			    {	
					if ($null -ne $secStatus.Resolver.SVTResources) {
							
					$secStatus.ControlIdString = $ControlIds;
					$secStatus.Severity = $Severity;
					$secStatus.UseBaselineControls = $UseBaselineControls;
					$secStatus.UsePreviewBaselineControls = $UsePreviewBaselineControls;

					#build the attestation options object
				    [AttestationOptions] $attestationOptions = [AttestationOptions]::new();
				    $attestationOptions.AttestControls = $ControlsToAttest				
				    $attestationOptions.JustificationText = $JustificationText
				    $attestationOptions.AttestationStatus = $AttestationStatus
				    $attestationOptions.IsBulkClearModeOn = $BulkClear
				    $attestationOptions.IsExemptModeOn = $AddException
				    $secStatus.AttestationOptions = $attestationOptions;	

					return $secStatus.EvaluateControlStatus();
					}
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



function Get-AzSKAzureDevOpsOrgSecurityStatus
{
	<#
	.SYNOPSIS
	This command would help in validating the security controls for the Azure DevOps Org.
	.DESCRIPTION
	This command will execute the security controls and will validate their status as 'Success' or 'Failure' based on the security guidance. Refer https://aka.ms/azskossdocs for more information 
	
	.PARAMETER OrganizationName
		Organization name for which the security evaluation has to be performed.
	
	.PARAMETER PATToken
		Token to run scan in non-interactive mode.
	
	.PARAMETER DoNotOpenOutputFolder
		Do not auto-open output folder after scan completion. This parameter is used in non-interactive console.	

	.NOTES
	This command helps the Org Owner to verify whether their Azure DevOps Org is compliant with the security guidance or not 

	.LINK
	https://aka.ms/azskossdocs 

	#>

	[OutputType([String])]
	Param
	(

		[string]		 
		[Parameter(Position = 0, Mandatory = $true, HelpMessage="OrganizationName for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("oz")]
		$OrganizationName,

		[string] 
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Alias("BulkAttestControlId","cids","bacid")]
		[AllowEmptyString()]
		$ControlIds,

		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("ubc")]
		$UseBaselineControls,

		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("upbc")]
		$UsePreviewBaselineControls,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage="Specify the severity of controls to be scanned. Example `"High, Medium`"")]
		[Alias("ControlSeverity")]
		$Severity,

		[System.Security.SecureString]
		[Parameter(HelpMessage="Token to run scan in non-interactive mode")]
		[Alias("tk")]
		$PATToken,

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("dnof")]
		$DoNotOpenOutputFolder,

		[ValidateSet("All","AlreadyAttested","NotAttested","None")]
        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Using this switch,  AzSK.AzureDevOps enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Using this switch,  AzSK.AzureDevOps enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Using this switch,  AzSK.AzureDevOps enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
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

		[ValidateSet("NotAnIssue", "WillNotFix", "WillFixLater","NotApplicable","StateConfirmed","ApprovedException")] 
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Attester must select one of the attestation reasons (NotAnIssue, WillNotFix, WillFixLater, NotApplicable, StateConfirmed(if valid for the control))")]
		[Alias("as")]
		$AttestationStatus = [AttestationStatus]::None,
		
		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("aex")]
		$AddException,


		[ValidateSet("All","BaselineControls","PreviewBaselineControls")]
		[Parameter(Mandatory = $false)]
		[Alias("abl")]
		$AutoBugLog,

		

		[string]
		[Parameter(Mandatory=$false)]
		[Alias("arp")]
		$AreaPath,

		[string]
		[Parameter(Mandatory=$false)]
		[Alias("itp")]
		$IterationPath,

		[switch]
		[Parameter(HelpMessage = "Allow long running scan.")]
		[Alias("als")]
		$AllowLongRunningScan


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
			$resolver = [SVTResourceResolver]::new($OrganizationName,$null,$null,$null,$null,$null,$null,$PATToken,[ResourceTypeName]::Organization, $AllowLongRunningScan);
			$secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{		
				if ($null -ne $secStatus.Resolver.SVTResources) {
				    $secStatus.ControlIdString = $ControlIds;
					$secStatus.Severity = $Severity;
					$secStatus.UseBaselineControls = $UseBaselineControls;
					$secStatus.UsePreviewBaselineControls = $UsePreviewBaselineControls;

					#build the attestation options object
				    [AttestationOptions] $attestationOptions = [AttestationOptions]::new();
				    $attestationOptions.AttestControls = $ControlsToAttest				
				    $attestationOptions.JustificationText = $JustificationText
				    $attestationOptions.AttestationStatus = $AttestationStatus
				    $attestationOptions.IsBulkClearModeOn = $BulkClear
				    $attestationOptions.IsExemptModeOn = $AddException
				    $secStatus.AttestationOptions = $attestationOptions;	

				return $secStatus.EvaluateControlStatus();
				}
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

function Get-AzSKAzureDevOpsProjectSecurityStatus
{
	<#
	.SYNOPSIS
	This command would help in validating the security controls for the Azure DevOps Org.
	.DESCRIPTION
	This command will execute the security controls and will validate their status as 'Success' or 'Failure' based on the security guidance. Refer https://aka.ms/azskossdocs for more information 
	
	.PARAMETER OrganizationName
		Organization name for which the security evaluation has to be performed.
	
	.PARAMETER ProjectNames
		Project names for which the security evaluation has to be performed.
	
	.PARAMETER PATToken
		Token to run scan in non-interactive mode.
	
	.PARAMETER DoNotOpenOutputFolder
		Do not auto open output folder after scan completion. This parameter is used in non-interactive console.	

	.NOTES
	This command helps the Org Owner to verify whether their Azure DevOps Org is compliant with the security guidance or not 

	.LINK
	https://aka.ms/azskossdocs 

	#>

	[OutputType([String])]
	Param
	(

		[string]		 
		[Parameter(Position = 0, Mandatory = $true, HelpMessage="OrganizationName for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("oz")]
		$OrganizationName,

		[string]
		[Parameter(Position = 1, Mandatory = $true, HelpMessage="Project names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("pn")]
		$ProjectNames,

		[string] 
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Alias("BulkAttestControlId","cids","bacid")]
		[AllowEmptyString()]
		$ControlIds,

		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("ubc")]
		$UseBaselineControls,

		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("upbc")]
		$UsePreviewBaselineControls,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage="Specify the severity of controls to be scanned. Example `"High, Medium`"")]
		[Alias("ControlSeverity")]
		$Severity,

		[System.Security.SecureString]
		[Parameter(HelpMessage="Token to run scan in non-interactive mode")]
		[Alias("tk")]
		$PATToken,

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("dnof")]
		$DoNotOpenOutputFolder,

		[ValidateSet("All","AlreadyAttested","NotAttested","None")]
        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Using this switch, AzSK.AzureDevOps enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Using this switch, AzSK.AzureDevOps enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Using this switch, AzSK.AzureDevOps enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
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

		[ValidateSet("NotAnIssue", "WillNotFix", "WillFixLater","NotApplicable","StateConfirmed","ApprovedException")] 
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Attester must select one of the attestation reasons (NotAnIssue, WillNotFix, WillFixLater, NotApplicable, StateConfirmed(if valid for the control))")]
		[Alias("as")]
		$AttestationStatus = [AttestationStatus]::None,
		
		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("aex")]
		$AddException,


		[ValidateSet("All","BaselineControls","PreviewBaselineControls")]
		[Parameter(Mandatory = $false)]
		[Alias("abl")]
		$AutoBugLog,

		

		[string]
		[Parameter(Mandatory=$false)]
		[Alias("arp")]
		$AreaPath,

		[string]
		[Parameter(Mandatory=$false)]
		[Alias("itp")]
		$IterationPath,

		[switch]
		[Parameter(HelpMessage="Allow long running scan.")]
		[Alias("als")]
		$AllowLongRunningScan


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
			$resolver = [SVTResourceResolver]::new($OrganizationName,$ProjectNames,$null,$null,$null,$null,$null,$PATToken,[ResourceTypeName]::Project, $AllowLongRunningScan);
			$secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{		
				if ($null -ne $secStatus.Resolver.SVTResources) {
				    $secStatus.ControlIdString = $ControlIds;
					$secStatus.Severity = $Severity;
					$secStatus.UseBaselineControls = $UseBaselineControls;
					$secStatus.UsePreviewBaselineControls = $UsePreviewBaselineControls;

					#build the attestation options object
				    [AttestationOptions] $attestationOptions = [AttestationOptions]::new();
				    $attestationOptions.AttestControls = $ControlsToAttest				
				    $attestationOptions.JustificationText = $JustificationText
				    $attestationOptions.AttestationStatus = $AttestationStatus
				    $attestationOptions.IsBulkClearModeOn = $BulkClear
				    $attestationOptions.IsExemptModeOn = $AddException
				    $secStatus.AttestationOptions = $attestationOptions;	

				return $secStatus.EvaluateControlStatus();
				}
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

function Get-AzSKAzureDevOpsBuildSecurityStatus
{
	<#
	.SYNOPSIS
	This command would help in validating the security controls for the Azure DevOps Org.
	.DESCRIPTION
	This command will execute the security controls and will validate their status as 'Success' or 'Failure' based on the security guidance. Refer https://aka.ms/azskossdocs for more information 
	
	.PARAMETER OrganizationName
		Organization name for which the security evaluation has to be performed.
	
	.PARAMETER ProjectNames
		Project names for which the security evaluation has to be performed.
	
	.PARAMETER PATToken
		Token to run scan in non-interactive mode.
	
	.PARAMETER DoNotOpenOutputFolder
		Do not auto open output folder after scan completion. This parameter is used in non-interactive console.	

	.NOTES
	This command helps the Org Owner to verify whether their Azure DevOps Org is compliant with the security guidance or not 

	.LINK
	https://aka.ms/azskossdocs 

	#>

	[OutputType([String])]
	Param
	(

		[string]		 
		[Parameter(Position = 0, Mandatory = $true, HelpMessage="OrganizationName for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("oz")]
		$OrganizationName,

		[string]
		[Parameter(Position = 1, Mandatory = $true, HelpMessage="Project names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("pn")]
		$ProjectNames,

		[string]
		[Parameter(Position = 2, Mandatory = $true,HelpMessage="Build names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("bn")]
		$BuildNames,

		[string] 
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Alias("BulkAttestControlId","cids","bacid")]
		[AllowEmptyString()]
		$ControlIds,

		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("ubc")]
		$UseBaselineControls,

		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("upbc")]
		$UsePreviewBaselineControls,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage="Specify the severity of controls to be scanned. Example `"High, Medium`"")]
		[Alias("ControlSeverity")]
		$Severity,

		[System.Security.SecureString]
		[Parameter(HelpMessage="Token to run scan in non-interactive mode")]
		[Alias("tk")]
		$PATToken,

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("dnof")]
		$DoNotOpenOutputFolder,


		[ValidateSet("All","BaselineControls","PreviewBaselineControls")]
		[Parameter(Mandatory = $false)]
		[Alias("abl")]
		$AutoBugLog,

		

		[string]
		[Parameter(Mandatory=$false)]
		[Alias("arp")]
		$AreaPath,

		[string]
		[Parameter(Mandatory=$false)]
		[Alias("itp")]
		$IterationPath,

		[switch]
		[Parameter(HelpMessage="Allow long running scan.")]
		[Alias("als")]
		$AllowLongRunningScan


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
			$resolver = [SVTResourceResolver]::new($OrganizationName,$ProjectNames,$BuildNames,$null,$null,$null,$null,$PATToken,[ResourceTypeName]::Build, $AllowLongRunningScan);
			$secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{	
				if ($null -ne $secStatus.Resolver.SVTResources) {	
				$secStatus.ControlIdString = $ControlIds;
					$secStatus.Severity = $Severity;
					$secStatus.UseBaselineControls = $UseBaselineControls;
					$secStatus.UsePreviewBaselineControls = $UsePreviewBaselineControls;

				return $secStatus.EvaluateControlStatus();
				}
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

function Get-AzSKAzureDevOpsReleaseSecurityStatus
{
	<#
	.SYNOPSIS
	This command would help in validating the security controls for the Azure DevOps Org.
	.DESCRIPTION
	This command will execute the security controls and will validate their status as 'Success' or 'Failure' based on the security guidance. Refer https://aka.ms/azskossdocs for more information 
	
	.PARAMETER OrganizationName
		Organization name for which the security evaluation has to be performed.
	
	.PARAMETER ProjectNames
		Project names for which the security evaluation has to be performed.
	
	.PARAMETER ReleaseNames
		Release names for which the security evaluation has to be performed.
	
	.PARAMETER PATToken
		Token to run scan in non-interactive mode.
	
	.PARAMETER DoNotOpenOutputFolder
		Do not auto open output folder after scan completion. This parameter is used in non-interactive console.	

	.NOTES
	This command helps the Org Owner to verify whether their Azure DevOps Org is compliant with the security guidance or not 

	.LINK
	https://aka.ms/azskossdocs 

	#>

	[OutputType([String])]
	Param
	(

		[string]		 
		[Parameter(Position = 0, Mandatory = $true, HelpMessage="OrganizationName for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("oz")]
		$OrganizationName,

		[string]
		[Parameter(Position = 1, Mandatory = $true, HelpMessage="Project names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("pn")]
		$ProjectNames,

		[string]
		[Parameter(Position = 2, Mandatory = $true, HelpMessage="Release names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("rn")]
		$ReleaseNames,

		[string] 
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Alias("BulkAttestControlId","cids","bacid")]
		[AllowEmptyString()]
		$ControlIds,

		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("ubc")]
		$UseBaselineControls,

		[switch]
		[Parameter(Mandatory = $false)]
		[Alias("upbc")]
		$UsePreviewBaselineControls,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage="Specify the severity of controls to be scanned. Example `"High, Medium`"")]
		[Alias("ControlSeverity")]
		$Severity,

		[System.Security.SecureString]
		[Parameter(HelpMessage="Token to run scan in non-interactive mode")]
		[Alias("tk")]
		$PATToken,

		[switch]
        [Parameter(Mandatory = $false)]
		[Alias("dnof")]
		$DoNotOpenOutputFolder,


		[ValidateSet("All","BaselineControls","PreviewBaselineControls")]
		[Parameter(Mandatory = $false)]
		[Alias("abl")]
		$AutoBugLog,

		

		[string]
		[Parameter(Mandatory=$false)]
		[Alias("arp")]
		$AreaPath,

		[string]
		[Parameter(Mandatory=$false)]
		[Alias("itp")]
		$IterationPath,

		[switch]
		[Parameter(HelpMessage="Allow long running scan.")]
		[Alias("als")]
		$AllowLongRunningScan



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
			$resolver = [SVTResourceResolver]::new($OrganizationName,$ProjectNames,$null,$ReleaseNames,$null,$null,$null,$PATToken,[ResourceTypeName]::Release, $AllowLongRunningScan);
			$secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{	
				if ($null -ne $secStatus.Resolver.SVTResources) {		
				$secStatus.ControlIdString = $ControlIds;
					$secStatus.Severity = $Severity;
					$secStatus.UseBaselineControls = $UseBaselineControls;
					$secStatus.UsePreviewBaselineControls = $UsePreviewBaselineControls;
					
				return $secStatus.EvaluateControlStatus();
				}
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