Set-StrictMode -Version Latest

function Get-AzSKADOSecurityStatus
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

	.PARAMETER DetailedScan
		Print detailed scan logs for controls.

	.NOTES
	This command helps the application team to verify whether their Azure resources are compliant with the security guidance or not 

	.LINK
	https://aka.ms/azskossdocs 

	#>

	[OutputType([String])]
	[Alias("Get-AzSKAzureDevOpsSecurityStatus")]
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
		[Alias("pns", "ProjectName", "pn")]
		$ProjectNames,

		[string]
		[Parameter(HelpMessage="Build names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("bns", "BuildName","bn")]
		$BuildNames,

		[string]
		[Parameter(HelpMessage="Release names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("rns", "ReleaseName","rn")]
		$ReleaseNames,

		[string]
		[Parameter(HelpMessage="Agent Pool names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("aps", "AgentPoolName","ap")]
		$AgentPoolNames,

		
		[string]
		[Parameter(HelpMessage="Service connection names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("sc", "ServiceConnectionName", "scs")]
		$ServiceConnectionNames,

		[string]
		[Parameter(HelpMessage="Variable group names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("vg", "VariableGroupName", "vgs")]
		$VariableGroupNames,

		[switch]
		[Parameter(HelpMessage="Scan all supported artificats present under organization like build, release, projects etc.")]
		[Alias("saa")]
		$ScanAllArtifacts,

		[string] 
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Comma separated control ids to filter the security controls. e.g.: ADO_Organization_AuthN_Use_AAD_Auth, ADO_Organization_SI_Review_InActive_Users etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Comma separated control ids to filter the security controls. e.g.: ADO_Organization_AuthN_Use_AAD_Auth, ADO_Organization_SI_Review_InActive_Users etc.")]
		[Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Comma separated control ids to filter the security controls. e.g.: ADO_Organization_AuthN_Use_AAD_Auth, ADO_Organization_SI_Review_InActive_Users etc.")]
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

		[switch]
		[Parameter(HelpMessage = "Switch to provide personal access token (PAT) using UI.")]
		[Alias("pfp")]
		$PromptForPAT,

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
        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Using this switch,  AzSK.ADO enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestation", HelpMessage="Using this switch,  AzSK.ADO enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
        [Parameter(Mandatory = $true, ParameterSetName = "BulkAttestationClear", HelpMessage="Using this switch,  AzSK.ADO enters 'attest' mode immediately after a scan is completed. This ensures that attestation is done on the basis of the most current control statuses.")]
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
		$AllowLongRunningScan,

		[string]
		[Parameter(Mandatory = $false, HelpMessage="Name of the project hosting organization policy with which the scan should run.")]
		[ValidateNotNullOrEmpty()]
		[Alias("pp")]
		$PolicyProject,

		[switch]
		[Parameter(HelpMessage="Print detailed scan logs for controls.")]
		[Alias("ds")]
		$DetailedScan,

		[string]
		[Parameter(HelpMessage="Service id for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("svid")]
		$ServiceId

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
			if($PromptForPAT -eq $true)
			{
				if($null -ne $PATToken)
				{	
					Write-Host "Parameters '-PromptForPAT' and '-PATToken' can not be used simultaneously in the scan command." -ForegroundColor Red
					return;
				}
				else 
				{
					$PATToken = Read-Host "Provide PAT for [$OrganizationName] org:" -AsSecureString	
				}
			
			}
			$resolver = [SVTResourceResolver]::new($OrganizationName,$ProjectNames,$BuildNames,$ReleaseNames,$AgentPoolNames, $ServiceConnectionNames, $VariableGroupNames, $MaxObj, $ScanAllArtifacts, $PATToken,$ResourceTypeName, $AllowLongRunningScan, $ServiceId);
			$secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{	
				if ($null -ne $secStatus.Resolver.SVTResources) {
							
					$secStatus.ControlIdString = $ControlIds;
					$secStatus.Severity = $Severity;
					$secStatus.UseBaselineControls = $UseBaselineControls;
					$secStatus.UsePreviewBaselineControls = $UsePreviewBaselineControls;

					$secStatus.FilterTags = $FilterTags;
					$secStatus.ExcludeTags = $ExcludeTags;

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
