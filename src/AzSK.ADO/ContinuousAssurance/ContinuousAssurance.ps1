Set-StrictMode -Version Latest
function Install-AzSKADOContinuousAssurance 
{
	<#
	.SYNOPSIS
	This command would help in setting up Continuous Assurance feature of AzSK.ADO in your subscription
	.DESCRIPTION
	This command will create a resource group (Name: ADOScannerRG) which runs security scan on organization and projects which are specified during installation.
	Security scan results will be populated in Log Analytics workspace which is configured during installation. Also, detailed logs will be stored in storage account (Name: adoscannersayyMMddHHmmss format).  
	
	.PARAMETER SubscriptionId
		Subscription id in which CA setup needs to be done.
	.PARAMETER Location
		Location in which all resources need to be setup. 
	.PARAMETER ResourceGroupName
		Resource group name where CA setup need to be done. (Default : ADOScannerRG)
	.PARAMETER LAWSId
		Workspace ID of Log Analytics workspace where security scan results will be sent
	.PARAMETER LAWSSharedKey
		Shared key of Log Analytics workspace which is used to monitor security scan results.
	.PARAMETER AltLAWSId
		Alternate workspace ID of Log Analytics workspace where security scan results will be sent
	.PARAMETER AltLAWSSharedKey
		Alternate shared key of Log Analytics workspace which is used to monitor security scan results.
	.PARAMETER OrganizationName
		Organization name for which scan will be performed.
	.PARAMETER PATToken
		PAT token secure string for organization to be scanned.
	.PARAMETER ProjectName
		Project to be scanned within the organization.
	.PARAMETER ExtendedCommand
		Extended command to narrow down the scans.
	.PARAMETER ScanIntervalInHours
		Overrides the default scan interval (24hrs) with the custom provided value.
	.PARAMETER CreateLAWorkspace
		Switch to create and map new log analytics workspace with CA setup.
	.NOTES
	This command helps the application team to verify whether their ADO resources are compliant with the security guidance or not 


	#>
	Param(
		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage="Subscription id in which CA setup needs to be done.")]
        [string]
		[Alias("sid")]
		$SubscriptionId ,

		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage = "Organization name for which scan will be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("oz")]
		[string]
		$OrganizationName,

		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage = "Project to be scanned within the organization.")]
		[Alias("pns", "ProjectNames","pn")]
		[string]
		$ProjectName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "PAT token secure string for organization to be scanned.")]
		[ValidateNotNullOrEmpty()]
		[Alias("pat")]
		[System.Security.SecureString]
		$PATToken,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Resource group name where CA setup needs to be done")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("rgn")]
		$ResourceGroupName,       

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Location in which all resources need to be setup.")]
		[string]
		[ValidateNotNullOrEmpty()]
		[Alias("loc")]
		$Location, 

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
		
        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Alternate workspace ID of Log Analytics workspace which is used to monitor security scan results.")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("alwid","awid")]
		$AltLAWSId,

        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Alternate shared key of Log Analytics workspace which is used to monitor security scan results.")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("alwkey","awkey")]
		$AltLAWSSharedKey,

		[switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to create and map new Log Analytics workspace with CA setup.")]
		[Alias("cws")]
		$CreateLAWorkspace,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Use extended command to narrow down the target scan.")]
		[Alias("ex")]
		[string]
		$ExtendedCommand,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Overrides the default scan interval (24hrs) with the custom provided value.")]
		[Alias("si")]
		[int]
		$ScanIntervalInHours,

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
            if ($PATToken -eq $null)
            {
                $PATToken = Read-Host "Provide PAT for [$OrganizationName] org:" -AsSecureString
            }

			$resolver = [Resolver]::new($OrganizationName)

			$caAccount = [CAAutomation]::new($SubscriptionId, $Location,`
											$OrganizationName, $PATToken, $ResourceGroupName, $LAWSId,`
											$LAWSSharedKey, $AltLAWSId, $AltLAWSSharedKey, $ProjectName,`
											$ExtendedCommand,  $ScanIntervalInHours, $PSCmdlet.MyInvocation, $CreateLAWorkspace);
            
			return $caAccount.InvokeFunction($caAccount.InstallAzSKADOContinuousAssurance);
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
	This command will update configurations of existing AzSK.ADO CA setup in your subscription.
	Security scan results will be populated in Log Analytics workspace which is configured during installation. Also, detailed logs will be stored in storage account (Name: adoscannersayyMMddHHmmss format).  
	
	.PARAMETER SubscriptionId
		Subscription id in which CA setup is present.
	.PARAMETER ResourceGroupName
		Resource group name where CA setup is available (Default : ADOScannerRG).
	.PARAMETER LAWSId
		Workspace ID of Log Analytics workspace which is used to monitor security scan results.
	.PARAMETER LAWSSharedKey
		Shared key of Log Analytics workspace which is used to monitor security scan results.
	.PARAMETER AltLAWSId
		Alternate workspace ID of Log Analytics workspace where security scan results will be sent
	.PARAMETER AltLAWSSharedKey
		Alternate shared key of Log Analytics workspace which is used to monitor security scan results.
	.PARAMETER OrganizationName
		Organization name for which scan will be performed.
	.PARAMETER PATToken
		PAT token secure string for organization to be scanned.
	.PARAMETER ProjectName
		Project to be scanned within the organization.
	.PARAMETER ExtendedCommand
		Extended command to narrow down the target scan.
	.PARAMETER ScanIntervalInHours
		Overrides the default scan interval (24hrs) with the custom provided value.
	.PARAMETER ClearExtendedCommand
		Use to clear extended command.
	#>
	Param(
		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage="Subscription id in which CA setup is present.")]
        [string]
		[Alias("sid")]
		$SubscriptionId ,

		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage = "Orgnanization name for which scan will be performed.")]
		[Alias("oz")]
		[string]
		$OrganizationName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Project to be scanned within the organization.")]
		[Alias("pns", "ProjectNames", "pn")]
		[string]
		$ProjectName,
		
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "PAT token secure string for organization to be scanned.")]
		[Alias("pat")]
		[System.Security.SecureString]
		$PATToken,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Resource group name where CA setup is available. (Default : ADOScannerRG)")]
        [string]
		[Alias("rgn")]
		$ResourceGroupName,       

        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Workspace ID of Log Analytics workspace where security scan results will be populated.")]
        [string]
		[Alias("lwid","wid","WorkspaceId")]
		$LAWSId,

        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Shared key of Log Analytics workspace which is used to monitor security scan results.")]
        [string]
		[Alias("lwkey","wkey","SharedKey")]
		$LAWSSharedKey,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Alternate workspace ID of Log Analytics workspace which is used to monitor security scan results.")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("alwid","awid")]
		$AltLAWSId,

        [Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Alternate shared key of Log Analytics workspace which is used to monitor security scan results.")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("alwkey","awkey")]
		$AltLAWSSharedKey,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Use extended command to narrow down the scans.")]
		[Alias("ex")]
		[string]
		$ExtendedCommand,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Overrides the default scan interval (24hrs) with the custom provided value.")]
		[Alias("si")]
		[int]
		$ScanIntervalInHours,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Use to clear extended command.")]
		[Alias("cec")]
		[switch]
		$ClearExtendedCommand,

		#Dev-Test support params below this
		[string] $RsrcTimeStamp, 
		[string] $ContainerImageName, 
		[string] $ModuleEnv, 
		[bool] $UseDevTestImage, 
		[int] $TriggerNextScanInMin
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
			$resolver = [Resolver]::new($OrganizationName)
			$caAccount = [CAAutomation]::new($SubscriptionId, $OrganizationName, $PATToken, `
											$ResourceGroupName, $LAWSId, $LAWSSharedKey, `
											$AltLAWSId, $AltLAWSSharedKey, $ProjectName, $ExtendedCommand, `
											$RsrcTimeStamp, $ContainerImageName, $ModuleEnv, $UseDevTestImage, $TriggerNextScanInMin, `
											$ScanIntervalInHours, $ClearExtendedCommand, $PSCmdlet.MyInvocation);
            
			return $caAccount.InvokeFunction($caAccount.UpdateAzSKADOContinuousAssurance);
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
function Get-AzSKADOContinuousAssurance 
{
	<#
	.SYNOPSIS
	This command would help in getting details of Continuous Assurance Setup
		
	.PARAMETER SubscriptionId
		Subscription id in which CA setup is present.
	.PARAMETER OrganizationName
		Organization name for which CA is setup.
	.PARAMETER ResourceGroupName
		Resource group name where CA setup is available (Default : ADOScannerRG).
	.PARAMETER RsrcTimeStamp
		Timestamp of function app if multiple CA are setup in same resource group.
	#>
	Param(
		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage="Subscription id in which CA setup is present.")]
        [string]
		[Alias("sid")]
		$SubscriptionId ,
		
		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage = "Orgnanization name for which scan will be performed.")]
		[Alias("oz")]
		[string]
		$OrganizationName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Resource group name where CA setup is available. (Default : ADOScannerRG)")]
        [string]
		[Alias("rg")]
		$ResourceGroupName ,
		
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage="Timestamp of function app if multiple CA are setup in same resource group.")]
        [string]
		[Alias("rts")]
		$RsrcTimeStamp    

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
			$resolver = [Resolver]::new($OrganizationName)
			$caAccount = [CAAutomation]::new($SubscriptionId, $OrganizationName, $ResourceGroupName, $RsrcTimeStamp, $PSCmdlet.MyInvocation);
            
			return $caAccount.InvokeFunction($caAccount.GetAzSKADOContinuousAssurance);
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

