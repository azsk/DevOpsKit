Set-StrictMode -Version Latest
function Install-AzSKAzureDevOpsContinuousAssurance 
{
	<#
	.SYNOPSIS
	This command would help in installing Automation Account in your subscription to setup Continuous Assurance feature of AzSK 
	.DESCRIPTION
	This command will install an Automation Account (Name: AzSKContinuousAssurance) which runs security scan on subscription and resource groups which are specified during installation.
	Security scan results will be populated in Log Analytics workspace which is configured during installation. Also, detailed logs will be stored in storage account (Name: azskyyyyMMddHHmmss format).  
	
	.PARAMETER SubscriptionId
		Subscription id in which Automation Account needs to be installed.
	.PARAMETER Location
		Location in which all resources need to be setup.
	.PARAMETER ResourceGroupName
		Resource group name where CA setup need to be done.
	.PARAMETER LAWSId
		Workspace ID of Log Analytics workspace where security scan results will be sent
	.PARAMETER LAWSSharedKey
		Shared key of Log Analytics workspace which is used to monitor security scan results.
	.PARAMETER OrganizationName
		Orgnanization name for which scan will be performed.
	.PARAMETER PATTokenSecureString
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
		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage="Id of the subscription in which Automation Account needs to be installed.")]
        [string]
		[Alias("sid")]
		$SubscriptionId ,

		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage="Location in which all resources need to be setup.")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("loc")]
		$Location , 

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Resource group name where CA setup need to be done")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("rgn")]
		$ResourceGroupName ,       

        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Workspace ID of Log Analytics workspace where security scan results will be populated.")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("lwid","wid","OMSWorkspaceId")]
		$LAWSId,

        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Shared key of Log Analytics workspace which is used to monitor security scan results.")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("lwkey","wkey","OMSSharedKey")]
		$LAWSSharedKey,

		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage = "Orgnanization name for which scan will be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("oz")]
		[string]
		$OrganizationName,

		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage = "PAT token secure string for organization to be scanned.")]
		[ValidateNotNullOrEmpty()]
		[Alias("pat")]
		[string]
		$PATTokenSecureString,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Project names to be scanned within the organization. If not provided then all projects will be scanned.")]
		[Alias("pns")]
		[string]
		$ProjectNames,
		
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Use extended command to narrow down the scans.")]
		[Alias("ex")]
		[string]
		$ExtendedCommand,

		[switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to create and map new log analytics workspace with CA setup.")]
		[Alias("cws")]
		$CreateWorkspace,

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
			$caAccount = [CAAutomation]::new($SubscriptionId, $Location,`
				$OrganizationName, $PATTokenSecureString, $ResourceGroupName, $LAWSId,`
				$LAWSSharedKey, $ProjectNames, $ExtendedCommand, $CreateWorkspace);

			return $caAccount.InstallAzSKContinuousAssurance();
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
