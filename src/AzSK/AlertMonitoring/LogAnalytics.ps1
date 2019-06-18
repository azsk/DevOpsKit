Set-StrictMode -Version Latest
function Set-AzSKMonitoringSettings
{
	<#
	.SYNOPSIS
	This command would help in updating the Log Analytics configuration settings under the current powershell session.
	.DESCRIPTION
	This command will update the Log Analytics settings under the current powershell session. This also remembers the current settings and use them in the subsequent sessions.
	
	.PARAMETER WorkspaceId
		Workspace ID of your Log Analytics instance. Control scan results get pushed to this instance.
	.PARAMETER SharedKey
		Shared key of your Log Analytics instance.
	.PARAMETER AltWorkspaceId
		Workspace ID of your alternate Log Analytics instance. Control scan results get pushed to this instance.
	.PARAMETER AltSharedKey
		Workspace shared key of your alternate Log Analytics instance.
	.PARAMETER Source
		Provide the source of Log Analytics Events. (e. g. CA,CICD,SDL)
	.PARAMETER Disable
		Use -Disable option to clean the Log Analytics setting under the current instance.		

	.LINK
	https://aka.ms/azskossdocs 

	#>
	[Alias("Set-AzSKOMSSettings")]
	param(
        
		[Parameter(Mandatory = $false, HelpMessage="Workspace ID of your Log Analytics instance. Control scan results get pushed to this instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("wid","OMSWorkspaceID")]
        $WorkspaceId,

        [Parameter(Mandatory = $false, HelpMessage="Shared key of your Log Analytics instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("wkey","OMSSharedKey")]
        $SharedKey,

		[Parameter(Mandatory = $false, HelpMessage="Workspace ID of your alternate Log Analytics instance. Control scan results get pushed to this instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("awid","AltOMSWorkspaceID")]
        $AltWorkspaceId,

        [Parameter(Mandatory = $false, HelpMessage="Shared key of your alternate Log Analytics instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("awkey","AltOMSSharedKey")]
        $AltSharedKey,

		[Parameter(Mandatory = $false, HelpMessage="Provide the source of Log Analytics Events.(e.g. CC,CICD,SDL)", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("so")]
        $Source,

        [Parameter(Mandatory = $true, HelpMessage="Use -Disable option to clean the Log Analytics setting under the current instance.", ParameterSetName = "Disable")]
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
				if(-not [string]::IsNullOrWhiteSpace($WorkspaceId) -and -not [string]::IsNullOrWhiteSpace($SharedKey))
				{
					$appSettings.LAWSId = $WorkspaceId
					$appSettings.LAWSSharedKey = $SharedKey
				}
				elseif(([string]::IsNullOrWhiteSpace($WorkspaceId) -and -not [string]::IsNullOrWhiteSpace($SharedKey)) `
						-and (-not [string]::IsNullOrWhiteSpace($WorkspaceId) -and [string]::IsNullOrWhiteSpace($SharedKey)))
				{					
					[EventBase]::PublishGenericCustomMessage("You need to send both the WorkspaceId and SharedKey", [MessageType]::Error);
					return;
				}
				if(-not [string]::IsNullOrWhiteSpace($AltWorkspaceId) -and -not [string]::IsNullOrWhiteSpace($AltSharedKey))
				{
					$appSettings.AltLAWSId = $AltWorkspaceId
					$appSettings.AltLAWSSharedKey = $AltSharedKey
				}
				elseif(([string]::IsNullOrWhiteSpace($AltWorkspaceId) -and -not [string]::IsNullOrWhiteSpace($AltSharedKey)) `
						-and (-not [string]::IsNullOrWhiteSpace($AltWorkspaceId) -and [string]::IsNullOrWhiteSpace($AltSharedKey)))
				{					
					[EventBase]::PublishGenericCustomMessage("You need to send both the AltWorkspaceId and AltSharedKey", [MessageType]::Error);
					return;
				}
			}
			else {
				$appSettings.LAWSId = ""
				$appSettings.LAWSSharedKey = ""
				$appSettings.AltLAWSId = ""
				$appSettings.AltLAWSSharedKey = ""
			}
			if(-not [string]::IsNullOrWhiteSpace($Source))
			{				
				$appSettings.LASource = $Source
			}
			else
			{
				$appSettings.LASource = "SDL"
			}
			$appSettings.LAType = "AzSK"
			[ConfigurationManager]::UpdateAzSKSettings($appSettings);
			[EventBase]::PublishGenericCustomMessage([Constants]::SingleDashLine + "`r`nWe have added new queries for the Monitoring solution. These will help reflect the aggregate control pass/fail status more accurately. Please go here to get them:  https://aka.ms/devopskit/omsqueries `r`n",[MessageType]::Warning);
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

function Install-AzSKMonitoringSolution
{
	<#

	.SYNOPSIS
	This command would help in creating security dashboard in Log Analytics Workspace

	.DESCRIPTION
	This command would help in creating security dashboard in Log Analytics Workspace

	.PARAMETER LAWSSubscriptionId
		Id of subscription hosting Log Analytics workspace
	.PARAMETER LAWSResourceGroup
		Resource group hosting Log Analytics workspace
	.PARAMETER WorkspaceId
		Workspace ID of the Log Analytics workspace which will be used for monitoring.
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
	[Alias("Install-AzSKOMSSolution")]
    param(
        [Parameter(ParameterSetName="NewModel", HelpMessage="Id of subscription hosting Log Analytics workspace", Mandatory = $true)]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("lawssubid","lawssid","OMSSubscriptionId")]
		$LAWSSubscriptionId,  
				
		[Parameter(ParameterSetName="NewModel", HelpMessage="Resource group hosting Log Analytics workspace", Mandatory = $true)]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("lawsrg","OMSResourceGroup")]
		$LAWSResourceGroup, 

		[Parameter(ParameterSetName="NewModel", HelpMessage="Workspace ID of the Log Analytics workspace which will be used for monitoring.", Mandatory = $true)]
        [string]
		[Alias("wid","OMSWorkspaceId")]
		[ValidateNotNullOrEmpty()]
		$WorkspaceId, 
		
		[Parameter(ParameterSetName="NewModel", HelpMessage="Provide the custom name for your DevOps Kit security view", Mandatory = $false)]
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
			if($PSCmdlet.MyInvocation.InvocationName.ToUpper().Equals("INSTALL-AZSKOMSSOLUTION"))
			{
				Write-Host "WARNING: The command 'Install-AzSKOMSSolution' will soon be deprecated. It will be replaced by 'Install-AzSKMonitoringSolution'.`n" -ForegroundColor Yellow
			}
			$monitoringInstance = [LogAnalyticsMonitoring]::new($LAWSSubscriptionId, $LAWSResourceGroup, $WorkspaceId, $PSCmdlet.MyInvocation);
			$monitoringInstance.InvokeFunction($monitoringInstance.ConfigureLAWS, @($ViewName, $ValidateOnly));
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