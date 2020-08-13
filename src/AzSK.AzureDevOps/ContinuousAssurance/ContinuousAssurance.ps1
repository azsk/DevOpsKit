Set-StrictMode -Version Latest
function Install-AzSKADOContinuousAssurance 
{
	<#
	.SYNOPSIS
	This command would help in setting up Continuous Assurance feature of AzSK.AzureDevOps in your subscription
	.DESCRIPTION
	This command will create a resource group (Name: ADOScannerRG) which runs security scan on organization and projects which are specified during installation.
	Security scan results will be populated in Log Analytics workspace which is configured during installation. Also, detailed logs will be stored in storage account (Name: adoscannersayyMMddHHmmss format).  
	
	.PARAMETER SubscriptionId
		Subscription id in which CA setup needs to be done.
	.PARAMETER Location
		Location in which all resources need to be setup. 
	.PARAMETER ResourceGroupName
		Resource group name where CA setup need to be done. (Default : ADOSCannerRG)
	.PARAMETER LAWSId
		Workspace ID of Log Analytics workspace where security scan results will be sent
	.PARAMETER LAWSSharedKey
		Shared key of Log Analytics workspace which is used to monitor security scan results.
	.PARAMETER OrganizationName
		Orgnanization name for which scan will be performed.
	.PARAMETER PATToken
		PAT token secure string for organization to be scanned.
	.PARAMETER ProjectNames
		Project names to be scanned within the organization. If not provided then all projects will be scanned.
	.PARAMETER ExtendedCommand
		Extended command to narrow down the scans.
	.PARAMETER CreateWorkspace
		Switch to create and map new log analytics workspace with CA setup.
	.NOTES
	This command helps the application team to verify whether their AzureDevOps resources are compliant with the security guidance or not 


	#>
	Param(
		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage="Subscription id in which CA setup needs to be done.")]
        [string]
		[Alias("sid")]
		$SubscriptionId ,

		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage="Location in which all resources need to be setup.")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("loc")]
		$Location , 

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Resource group name where CA setup needs to be done")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("rgn")]
		$ResourceGroupName ,       

        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Workspace ID of Log Analytics workspace which is used to monitor security scan results.")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("lwid","wid")]
		$LAWSId,

        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Shared key of Log Analytics workspace which is used to monitor security scan results.")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("lwkey","wkey")]
		$LAWSSharedKey,

		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage = "Organization name for which scan will be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("oz")]
		[string]
		$OrganizationName,

		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage = "PAT token secure string for organization to be scanned.")]
		[ValidateNotNullOrEmpty()]
		[Alias("pat")]
		[System.Security.SecureString]
		$PATToken,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "List of projects to be scanned within the organization. If not provided, then all projects will be scanned.")]
		[Alias("pns")]
		[string]
		$ProjectNames,
		
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Use extended command to narrow down the target scan.")]
		[Alias("ex")]
		[string]
		$ExtendedCommand,

		[switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to create and map new Log Analytics workspace with CA setup.")]
		[Alias("cws")]
		$CreateLAWorkspace,

		[switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder or not.")]
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
			$resolver = [Resolver]::new($SubscriptionId,$PATToken)
			$caAccount = [CAAutomation]::new($SubscriptionId, $Location,`
				$OrganizationName, $PATToken, $ResourceGroupName, $LAWSId,`
				$LAWSSharedKey, $ProjectNames, $ExtendedCommand, $PSCmdlet.MyInvocation, $CreateLAWorkspace);
            
			return $caAccount.InvokeFunction($caAccount.InstallAzSKContinuousAssurance);
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

function Update-AzSKADOContinuousAssurance 
{
	<#
	.SYNOPSIS
	This command would help in updating user configurable properties of Continuous Assurance in your subscription
	.DESCRIPTION
	This command will update configurations of existing AzSK.AzureDevOps CA setup in your subscription.
	Security scan results will be populated in Log Analytics workspace which is configured during installation. Also, detailed logs will be stored in storage account (Name: adoscannersayyMMddHHmmss format).  
	
	.PARAMETER SubscriptionId
		Subscription id in which CA setup is present.
	.PARAMETER ResourceGroupName
		Resource group name where CA setup is available (Default : ADOScannerRG).
	.PARAMETER LAWSId
		Workspace ID of Log Analytics workspace which is used to monitor security scan results.
	.PARAMETER LAWSSharedKey
		Shared key of Log Analytics workspace which is used to monitor security scan results.
	.PARAMETER OrganizationName
		Organization name for which scan will be performed.
	.PARAMETER PATToken
		PAT token secure string for organization to be scanned.
	.PARAMETER ProjectNames
		List of projects to be scanned within the organization.
	.PARAMETER ExtendedCommand
		Extended command to narrow down the target scan.

	#>
	Param(
		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage="Subscription id in which CA setup is present.")]
        [string]
		[Alias("sid")]
		$SubscriptionId ,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Resource group name where CA setup is available. (Default : ADOSCannerRG)")]
        [string]
		[Alias("rgn")]
		$ResourceGroupName ,       

        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Workspace ID of Log Analytics workspace where security scan results will be populated.")]
        [string]
		[Alias("lwid","wid","OMSWorkspaceId")]
		$LAWSId,

        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Shared key of Log Analytics workspace which is used to monitor security scan results.")]
        [string]
		[Alias("lwkey","wkey","OMSSharedKey")]
		$LAWSSharedKey,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Orgnanization name for which scan will be performed.")]
		[Alias("oz")]
		[string]
		$OrganizationName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "PAT token secure string for organization to be scanned.")]
		[Alias("pat")]
		[System.Security.SecureString]
		$PATToken,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Project names to be scanned within the organization. If not provided then all projects will be scanned.")]
		[Alias("pns")]
		[string]
		$ProjectNames,
		
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Use extended command to narrow down the scans.")]
		[Alias("ex")]
		[string]
		$ExtendedCommand

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
			if ([string]::IsNullOrEmpty($PATToken))
			{
				$resolver = [Resolver]::new($SubscriptionId)
				$caAccount = [CAAutomation]::new($SubscriptionId,$OrganizationName, $null, $ResourceGroupName, $LAWSId,	$LAWSSharedKey, $ProjectNames, $ExtendedCommand, $PSCmdlet.MyInvocation);
			}
			else
			{
				$resolver = [Resolver]::new($SubscriptionId,$PATToken)
				$caAccount = [CAAutomation]::new($SubscriptionId,$OrganizationName, $PATToken, $ResourceGroupName, $LAWSId,	$LAWSSharedKey, $ProjectNames, $ExtendedCommand, $PSCmdlet.MyInvocation);
			}
            
			return $caAccount.InvokeFunction($caAccount.UpdateAzSKContinuousAssurance);
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
