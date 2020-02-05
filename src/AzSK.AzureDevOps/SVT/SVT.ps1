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
		[Parameter(Mandatory = $false, HelpMessage = "Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Alias("cids")]
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
		[Alias("dnof")]
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
				$resolver = [SVTResourceResolver]::new($OrganizationName,$ProjectNames,$BuildNames,$ReleaseNames,$AgentPoolNames, $ServiceConnectionNames, $MaxObj, $ScanAllArtifacts, $PATToken,$ResourceTypeName);
			    $secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			    if ($secStatus) 
			    {		
					$secStatus.ControlIdString = $ControlIds;
					$secStatus.Severity = $Severity;
					$secStatus.UseBaselineControls = $UseBaselineControls;
					$secStatus.UsePreviewBaselineControls = $UsePreviewBaselineControls;
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
		[Parameter(Mandatory = $false, HelpMessage = "Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Alias("cids")]
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
			$resolver = [SVTResourceResolver]::new($OrganizationName,$null,$null,$null,$null,$null,$PATToken,[ResourceTypeName]::Organization);
			$secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{		
				$secStatus.ControlIdString = $ControlIds;
					$secStatus.Severity = $Severity;
					$secStatus.UseBaselineControls = $UseBaselineControls;
					$secStatus.UsePreviewBaselineControls = $UsePreviewBaselineControls;

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
		[Parameter( HelpMessage="Project names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("pn")]
		$ProjectNames,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Alias("cids")]
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
			$resolver = [SVTResourceResolver]::new($OrganizationName,$ProjectNames,$null,$null,$null,$null,$PATToken,[ResourceTypeName]::Project);
			$secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{		
				$secStatus.ControlIdString = $ControlIds;
					$secStatus.Severity = $Severity;
					$secStatus.UseBaselineControls = $UseBaselineControls;
					$secStatus.UsePreviewBaselineControls = $UsePreviewBaselineControls;

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
		[Parameter(Mandatory = $false, HelpMessage = "Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Alias("cids")]
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
			$resolver = [SVTResourceResolver]::new($OrganizationName,$ProjectNames,$BuildNames,$null,$null,$null,$PATToken,[ResourceTypeName]::Build);
			$secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{		
				$secStatus.ControlIdString = $ControlIds;
					$secStatus.Severity = $Severity;
					$secStatus.UseBaselineControls = $UseBaselineControls;
					$secStatus.UsePreviewBaselineControls = $UsePreviewBaselineControls;

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
		[Parameter( HelpMessage="Project names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("pn")]
		$ProjectNames,

		[string]
		[Parameter(HelpMessage="Release names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("rn")]
		$ReleaseNames,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Comma separated control ids to filter the security controls. e.g.: AzureDevOps_Organization_AuthN_Use_AAD_Auth, AzureDevOps_Organization_SI_Review_InActive_Users etc.")]
		[Alias("cids")]
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
			$resolver = [SVTResourceResolver]::new($OrganizationName,$ProjectNames,$null,$ReleaseNames,$null,$null,$PATToken,[ResourceTypeName]::Release);
			$secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{		
				$secStatus.ControlIdString = $ControlIds;
					$secStatus.Severity = $Severity;
					$secStatus.UseBaselineControls = $UseBaselineControls;
					$secStatus.UsePreviewBaselineControls = $UsePreviewBaselineControls;
					
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