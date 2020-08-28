Set-StrictMode -Version Latest
function Set-AzSKADOMonitoringSettings
{
	<#
	.SYNOPSIS
	This command would help in updating the Log Analytics configuration settings under the current powershell session.
	.DESCRIPTION
	This command will update the Log Analytics settings under the current powershell session. This also remembers the current settings and use them in the subsequent sessions.
	
	.PARAMETER LAWSId
		Workspace ID of your Log Analytics instance. Control scan results get pushed to this instance.
	.PARAMETER LAWSSharedKey
		Shared key of your Log Analytics instance.
	.PARAMETER AltLAWSId
		Workspace ID of your alternate Log Analytics instance. Control scan results get pushed to this instance.
	.PARAMETER AltLAWSSharedKey
		Workspace shared key of your alternate Log Analytics instance.
	.PARAMETER Source
		Provide the source of Log Analytics Events. (e. g. CA,CICD,SDL)
	.PARAMETER Disable
		Use -Disable option to clean the Log Analytics setting under the current instance.		

	.LINK
	https://aka.ms/azskossdocs 

	#>
	[Alias("Set-AzSKMonitoringSettings")]
	param(
        
		[Parameter(Mandatory = $false, HelpMessage="Workspace ID of your Log Analytics instance. Control scan results get pushed to this instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("wid","WorkspaceId")]
        $LAWSId,

        [Parameter(Mandatory = $false, HelpMessage="Shared key of your Log Analytics instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("wkey","SharedKey")]
        $LAWSSharedKey,

		[Parameter(Mandatory = $false, HelpMessage="Workspace ID of your alternate Log Analytics instance. Control scan results get pushed to this instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("awid","AltWorkspaceId")]
        $AltLAWSId,

        [Parameter(Mandatory = $false, HelpMessage="Shared key of your alternate Log Analytics instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("awkey", "AltSharedKey")]
        $AltLAWSSharedKey,

		[Parameter(Mandatory = $false, HelpMessage="Provide the source of Log Analytics Events.(e.g. CA,CICD,SDL)", ParameterSetName = "Setup")]
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
				if(-not [string]::IsNullOrWhiteSpace($LAWSId) -and -not [string]::IsNullOrWhiteSpace($LAWSSharedKey))
				{
					$appSettings.LAWSId = $LAWSId
					$appSettings.LAWSSharedKey = $LAWSSharedKey
				}
				elseif(([string]::IsNullOrWhiteSpace($LAWSId) -and -not [string]::IsNullOrWhiteSpace($LAWSSharedKey)) `
						-and (-not [string]::IsNullOrWhiteSpace($LAWSId) -and [string]::IsNullOrWhiteSpace($LAWSSharedKey)))
				{					
					[EventBase]::PublishGenericCustomMessage("You need to send both the LAWSId and LAWSSharedKey", [MessageType]::Error);
					return;
				}
				if(-not [string]::IsNullOrWhiteSpace($AltLAWSId) -and -not [string]::IsNullOrWhiteSpace($AltLAWSSharedKey))
				{
					$appSettings.AltLAWSId = $AltLAWSId
					$appSettings.AltLAWSSharedKey = $AltLAWSSharedKey
				}
				elseif(([string]::IsNullOrWhiteSpace($AltLAWSId) -and -not [string]::IsNullOrWhiteSpace($AltLAWSSharedKey)) `
						-and (-not [string]::IsNullOrWhiteSpace($AltLAWSId) -and [string]::IsNullOrWhiteSpace($AltLAWSSharedKey)))
				{					
					[EventBase]::PublishGenericCustomMessage("You need to send both the AltLAWSId and AltLAWSSharedKey", [MessageType]::Error);
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
		
			$appSettings.LAType = "AzSK_ADO"
			[ConfigurationManager]::UpdateAzSKSettings($appSettings);
			[ConfigOverride]::ClearConfigInstance()
			#[EventBase]::PublishGenericCustomMessage([Constants]::SingleDashLine + "`r`nWe have added new queries for the Monitoring solution. These will help reflect the aggregate control pass/fail status more accurately. Please go here to get them:  https://aka.ms/devopskit/omsqueries `r`n",[MessageType]::Warning);
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

function Install-AzSKADOMonitoringSolution
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
	.PARAMETER LAWSId
		Workspace ID of the Log Analytics workspace which will be used for monitoring.
	.PARAMETER ViewName
		Provide the custom name for your DevOps Kit security view.
	.PARAMETER ValidateOnly
		Provide this debug switch to validate the deployment. It is a predeployment check which validates all the provided params.
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder.
	.EXAMPLE
    
	.NOTES
	This command helps the application team to check compliance of ADO against security standards.  

	.LINK
	https://aka.ms/azskossdocs

	#>
	[Alias("Install-AzSKMonitoringSolution")]
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
		[Alias("wid","OMSWorkspaceId","WorkspaceId")]
		[ValidateNotNullOrEmpty()]
		$LAWSId, 
		
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
		$DoNotOpenOutputFolder,

		[ValidateSet("View", "Workbook")] 
        [Parameter(Mandatory = $false, HelpMessage="Provide the type of dashboard to be created in Log Analytics.")]
		[Alias("dt")]
		$DashboardType = [DashboardType]::View
		
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
			$DeployWorkbook = $false
			if($DashboardType -eq [DashboardType]::Workbook){
				$DeployWorkbook = $true
			}
			$monitoringInstance = [LogAnalyticsMonitoring]::new($LAWSSubscriptionId, $LAWSResourceGroup, $LAWSId, $PSCmdlet.MyInvocation, $ViewName, $DeployWorkbook);
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
