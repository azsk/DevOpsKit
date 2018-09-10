Set-StrictMode -Version Latest
function Set-AzSKOMSSettings
{
	<#
	.SYNOPSIS
	This command would help in updating the OMS configuration settings under the current powershell session.
	.DESCRIPTION
	This command will update the OMS settings under the current powershell session. This also remembers the current settings and use them in the subsequent sessions.
	
	.PARAMETER OMSWorkspaceID
		Workspace ID of your OMS instance. Control scan results get pushed to this instance.
	.PARAMETER OMSSharedKey
		Shared key of your OMS instance.
	.PARAMETER AltOMSWorkspaceID
		Alternate workspaceId of your OMS instance. Control scan results get pushed to this instance.
	.PARAMETER AltOMSSharedKey
		Workspace shared key of your alternate OMS instance.
	.PARAMETER Source
		Provide the source of OMS Events. (e. g. CA,CICD,SDL)
	.PARAMETER Disable
		Use -Disable option to clean the OMS setting under the current instance.		

	.LINK
	https://aka.ms/azskossdocs 

	#>
	param(
        
		[Parameter(Mandatory = $false, HelpMessage="Workspace ID of your OMS instance. Control scan results get pushed to this instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("owid")]
        $OMSWorkspaceID,

        [Parameter(Mandatory = $false, HelpMessage="Shared key of your OMS instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("okey")]
        $OMSSharedKey,

		[Parameter(Mandatory = $false, HelpMessage="Alternate Workspace ID of your OMS instance. Control scan results get pushed to this instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("aowid")]
        $AltOMSWorkspaceID,

        [Parameter(Mandatory = $false, HelpMessage="Shared key of your alternate OMS instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("aokey")]
        $AltOMSSharedKey,

		[Parameter(Mandatory = $false, HelpMessage="Provide the source of OMS Events.(e.g. CC,CICD,SDL)", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("so")]
        $Source,

        [Parameter(Mandatory = $true, HelpMessage="Use -Disable option to clean the OMS setting under the current instance.", ParameterSetName = "Disable")]
        [switch]
		[Alias("dsbl")]
        $Disable

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
			$appSettings = [ConfigurationManager]::GetLocalAzSKSettings();
			if(-not $Disable) 
			{
				if(-not [string]::IsNullOrWhiteSpace($OMSWorkspaceID) -and -not [string]::IsNullOrWhiteSpace($OMSSharedKey))
				{
					$appSettings.OMSWorkspaceId = $OMSWorkspaceID
					$appSettings.OMSSharedKey = $OMSSharedKey
				}
				elseif(([string]::IsNullOrWhiteSpace($OMSWorkspaceID) -and -not [string]::IsNullOrWhiteSpace($OMSSharedKey)) `
						-and (-not [string]::IsNullOrWhiteSpace($OMSWorkspaceID) -and [string]::IsNullOrWhiteSpace($OMSSharedKey)))
				{					
					[EventBase]::PublishGenericCustomMessage("You need to send both the OMSWorkspaceId and OMSSharedKey", [MessageType]::Error);
					return;
				}
				if(-not [string]::IsNullOrWhiteSpace($AltOMSWorkspaceID) -and -not [string]::IsNullOrWhiteSpace($AltOMSSharedKey))
				{
					$appSettings.AltOMSWorkspaceId = $AltOMSWorkspaceID
					$appSettings.AltOMSSharedKey = $AltOMSSharedKey
				}
				elseif(([string]::IsNullOrWhiteSpace($AltOMSWorkspaceID) -and -not [string]::IsNullOrWhiteSpace($AltOMSSharedKey)) `
						-and (-not [string]::IsNullOrWhiteSpace($AltOMSWorkspaceID) -and [string]::IsNullOrWhiteSpace($AltOMSSharedKey)))
				{					
					[EventBase]::PublishGenericCustomMessage("You need to send both the AltOMSWorkspaceId and AltOMSSharedKey", [MessageType]::Error);
					return;
				}
			}
			else {
				$appSettings.OMSWorkspaceId = ""
				$appSettings.OMSSharedKey = ""
				$appSettings.AltOMSWorkspaceId = ""
				$appSettings.AltOMSSharedKey = ""
			}
			if(-not [string]::IsNullOrWhiteSpace($Source))
			{				
				$appSettings.OMSSource = $Source
			}
			else
			{
				$appSettings.OMSSource = "SDL"
			}
			$appSettings.OMSType = "AzSK"
			[ConfigurationManager]::UpdateAzSKSettings($appSettings);
			[EventBase]::PublishGenericCustomMessage([Constants]::SingleDashLine + "`r`nWe have added new queries for the OMS solution. These will help reflect the aggregate control pass/fail status more accurately. Please go here to get them:  https://aka.ms/devopskit/omsqueries `r`n",[MessageType]::Warning);
			[EventBase]::PublishGenericCustomMessage("Successfully changed policy settings");
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

function Install-AzSKOMSSolution
{
	<#

	.SYNOPSIS
	This command would help in creating security dashboard in OMS

	.DESCRIPTION
	This command would help in creating security dashboard in OMS

	.PARAMETER OMSSubscriptionId
		Id of subscription hosting OMS workspace
	.PARAMETER OMSResourceGroup
		Resource group hosting OMS workspace
	.PARAMETER OMSWorkspaceId
		Workspace ID of the OMS workspace name which will be used for monitoring.
	.PARAMETER ViewName
		Provide the custom name for your DevOps Kit security view.
	.PARAMETER ValidateOnly
		Provide this debug switch to validate the deployment. It is a predeployment check which validates all the provided params.
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder.
	.EXAMPLE
    
	.NOTES
	This command helps the application team to check compliance of Azure Subscriptions with the AzSK security guidance.  

	.LINK
	https://aka.ms/azskossdocs

	#>
    param(
        [Parameter(ParameterSetName="NewModel", HelpMessage="Id of subscription hosting OMS workspace", Mandatory = $true)]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("omssubid","omssid")]
		$OMSSubscriptionId,  
				
		[Parameter(ParameterSetName="NewModel", HelpMessage="Resource group hosting OMS workspace", Mandatory = $true)]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("omsrg")]
		$OMSResourceGroup, 

		[Parameter(ParameterSetName="NewModel", HelpMessage="Workspace ID of the OMS workspace name which will be used for monitoring.", Mandatory = $true)]
        [string]
		[Alias("owid")]
		[ValidateNotNullOrEmpty()]
		$OMSWorkspaceId, 
		
		[Parameter(ParameterSetName="NewModel", HelpMessage="Provide the custom name for your devopskit security view", Mandatory = $false)]
        [string]
		[Alias("vname")]
		$ViewName = "SecurityCompliance", 
                		
		[switch]
		[Alias("vonly")]
		[Parameter(Mandatory = $False, HelpMessage="Provide this debug switch to validate the deployment. It is a predeployment check which validates all the provided params.")]
		$ValidateOnly,
		
		[switch]
		[Alias("dnof")]
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
			$OMSMonitoringInstance = [OMSMonitoring]::new($OMSSubscriptionId, $OMSResourceGroup, $OMSWorkspaceId, $PSCmdlet.MyInvocation);
			$OMSMonitoringInstance.InvokeFunction($OMSMonitoringInstance.ConfigureOMS, @($ViewName, $ValidateOnly));
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
