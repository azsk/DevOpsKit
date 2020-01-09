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
		Organization name for which the security evaluation has to be performed.

	.PARAMETER BuildNames
		Organization name for which the security evaluation has to be performed.

	.PARAMETER ReleaseNames
		Organization name for which the security evaluation has to be performed.

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
		[Parameter(HelpMessage="Release names for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("ap")]
		$AgentPoolNames,

		[switch]
		[Parameter(HelpMessage="Scan all supported artificats present under organization like build, release, projects etc.")]
		[Alias("sa")]
		$ScanAllArtifacts,

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
			$AzSK = Get-Module | Where-Object { $_.Name -eq 'AzSK' };
			if (!$AzSK) {
				$resolver = [SVTResourceResolver]::new($OrganizationName,$ProjectNames,$BuildNames,$ReleaseNames,$AgentPoolNames,$ScanAllArtifacts,$PATToken,$ResourceTypeName);
			    $secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			    if ($secStatus) 
			    {		
			    	return $secStatus.EvaluateControlStatus();
			    }  
			}
			else {
				Write-Error "Please make sure you have imported only the AzSK.AzureDevOps module in the PS session. It seems that there are other AzSK modules also present in PS session memory. Please run the command in the new session.";
				[ListenerHelper]::UnregisterListeners();
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
		 $AzSK = Get-Module | Where-Object { $_.Name -eq 'AzSK' };
		 if (!$AzSK) {
			$resolver = [SVTResourceResolver]::new($OrganizationName,$null,$null,$null,$null,$null,$PATToken,[ResourceTypeName]::Organization);
			$secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{		
				return $secStatus.EvaluateControlStatus();
			}
		 }
		 else {
		 	Write-Error "Please make sure you have imported only the AzSK.AzureDevOps module in the PS session. It seems that there are other AzSK modules also present in PS session memory. Please run the command in the new session.";
		 	[ListenerHelper]::UnregisterListeners();
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
		 $AzSK = Get-Module | Where-Object { $_.Name -eq 'AzSK' };
		 if (!$AzSK) {
			$resolver = [SVTResourceResolver]::new($OrganizationName,$ProjectNames,$null,$null,$null,$null,$PATToken,[ResourceTypeName]::Project);
			$secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{		
				return $secStatus.EvaluateControlStatus();
			}
		 }
		 else {
		 	Write-Error "Please make sure you have imported only the AzSK.AzureDevOps module in the PS session. It seems that there are other AzSK modules also present in PS session memory. Please run the command in the new session.";
		 	[ListenerHelper]::UnregisterListeners();
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
		 $AzSK = Get-Module | Where-Object { $_.Name -eq 'AzSK' };
		 if (!$AzSK) {
			$resolver = [SVTResourceResolver]::new($OrganizationName,$ProjectNames,$BuildNames,$null,$null,$null,$PATToken,[ResourceTypeName]::Build);
			$secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{		
				return $secStatus.EvaluateControlStatus();
			} 
		 }
		 else {
		 	Write-Error "Please make sure you have imported only the AzSK.AzureDevOps module in the PS session. It seems that there are other AzSK modules also present in PS session memory. Please run the command in the new session.";
		 	[ListenerHelper]::UnregisterListeners();
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
		 $AzSK = Get-Module | Where-Object { $_.Name -eq 'AzSK' };
		 if (!$AzSK) {
			$resolver = [SVTResourceResolver]::new($OrganizationName,$ProjectNames,$null,$ReleaseNames,$null,$null,$PATToken,[ResourceTypeName]::Release);
			$secStatus = [ServicesSecurityStatus]::new($OrganizationName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{		
				return $secStatus.EvaluateControlStatus();
			}
		 }
		 else {
		 	Write-Error "Please make sure you have imported only the AzSK.AzureDevOps module in the PS session. It seems that there are other AzSK modules also present in PS session memory. Please run the command in the new session.";
		 	[ListenerHelper]::UnregisterListeners();
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