
Set-StrictMode -Version Latest

. $PSScriptRoot\Framework\Framework.ps1

@("$PSScriptRoot\SVT") |
    ForEach-Object {
    (Get-ChildItem -Path $_ -Recurse -File -Include "*.ps1") |
        ForEach-Object {
        . $_.FullName
    }
}

function Set-AzSKAADPolicySettings {
    <#
	.SYNOPSIS
	This command would help to set online policy store URL.
	.DESCRIPTION
	This command would help to set online policy store URL.

	.PARAMETER ScannerToolPath
		Provide the credential scanner tool path
	.PARAMETER ScannerToolName
		Provide the credential scanner tool name.
	
	.LINK
	https://aka.ms/azskossdocs

	#>
    Param(
        [Parameter(Mandatory = $false, HelpMessage = "Provide scanner tool path")]
        [string]
		[Alias("stp")]
        $ScannerToolPath,

        [Parameter(Mandatory = $false, HelpMessage = "Provide scanner tool name")]
        [string]
		[Alias("stn")]
        $ScannerToolName

    )
    Begin {
        [CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
        [ListenerHelper]::RegisterListeners();
    }
    Process {
        try {

			$azskSettings = [ConfigurationManager]::GetLocalAzSKSettings();
            if($ScannerToolPath -and $ScannerToolName)
            {
                $azskSettings.ScanToolPath = $ScannerToolPath
                $azskSettings.ScanToolName = $ScannerToolName
            }
            
            [ConfigurationManager]::UpdateAzSKSettings($azskSettings);            
            [EventBase]::PublishGenericCustomMessage("Successfully configured policy settings. `nStart a fresh PS console/session to ensure any policy updates are (re-)loaded.", [MessageType]::Warning);
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }
    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }
}

function Set-AzSKLocalAIOrgTelemetrySettings {
    <#
	.SYNOPSIS
	This command would help to set local control telemetry settings.
	.DESCRIPTION
	This command would help to set local control telemetry settings.

	.PARAMETER LocalAIOrgTelemetryKey
		Provide local telemetry key.
	.PARAMETER EnableLocalAIOrgTelemetry
		Enables local control telemetry.
	.LINK
	https://aka.ms/azskossdocs

	#>
    Param(
        [Parameter(Mandatory = $true, HelpMessage = "Provide the local control telemetry key")]
        [string]
		[Alias("lotk")]
        $LocalAIOrgTelemetryKey,

        [Parameter(Mandatory = $true, HelpMessage = "Provide the flag to enable local control telemetry")]
        [bool]
		[Alias("elot")]
        $EnableLocalAIOrgTelemetry
    )
    Begin {
        [CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
        [ListenerHelper]::RegisterListeners();
    }
    Process {
        try { 
            $azskSettings = [ConfigurationManager]::GetLocalAzSKSettings();
            $azskSettings.LocalControlTelemetryKey = $LocalAIOrgTelemetryKey
            $azskSettings.LocalEnableControlTelemetry = $EnableLocalAIOrgTelemetry
            [ConfigurationManager]::UpdateAzSKSettings($azskSettings);
            [EventBase]::PublishGenericCustomMessage("Successfully set control telemetry settings");
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }
    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }
}

function Set-AzSKUsageTelemetryLevel {
    <#
	.SYNOPSIS
	This command would help to set telemetry level.
	.DESCRIPTION
	This command would help to set telemetry level.

	.PARAMETER Level
		Provide the telemetry level
	.LINK
	https://aka.ms/azskossdocs

	#>
    Param(
        [Parameter(Mandatory = $true, HelpMessage = "Provide the telemetry level")]
        [ValidateSet("None", "Anonymous")]
        [string]
		[Alias("lvl")]
        $Level
    )
    Begin {
        [CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
        [ListenerHelper]::RegisterListeners();
    }
    Process {
        try {
            $azskSettings = [ConfigurationManager]::GetLocalAzSKSettings();
            $azskSettings.UsageTelemetryLevel = $Level
            [ConfigurationManager]::UpdateAzSKSettings($azskSettings);
            [EventBase]::PublishGenericCustomMessage("Successfully set usage telemetry level");
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }
    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }
}

function Set-AzSKMonitoringSettings
{
	<#
	.SYNOPSIS
	This command would help in updating the Log Analytics configuration settings under the current powershell session.
	.DESCRIPTION
	This command will update the Log Analytics settings under the current powershell session. This also remembers the current settings and use them in the subsequent sessions.
	
	.PARAMETER OMSWorkspaceID
		Workspace ID of your Log Analytics instance. Control scan results get pushed to this instance.
	.PARAMETER OMSSharedKey
		Shared key of your Log Analytics instance.
	.PARAMETER AltOMSWorkspaceID
		Workspace ID of your alternate Log Analytics instance. Control scan results get pushed to this instance.
	.PARAMETER AltOMSSharedKey
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
		[Alias("owid","wid","WorkspaceID")]
        $OMSWorkspaceID,

        [Parameter(Mandatory = $false, HelpMessage="Shared key of your Log Analytics instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("okey","wkey","SharedKey")]
        $OMSSharedKey,

		[Parameter(Mandatory = $false, HelpMessage="Workspace ID of your alternate Log Analytics instance. Control scan results get pushed to this instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("aowid","awid","AltWorkspaceID")]
        $AltOMSWorkspaceID,

        [Parameter(Mandatory = $false, HelpMessage="Shared key of your alternate Log Analytics instance.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("aokey","awkey","AltSharedKey")]
        $AltOMSSharedKey,

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
			$appSettings.OMSType = [OMSHelper]::DefaultOMSType
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

function Set-AzSKPrivacyNoticeResponse {
    <#
	.SYNOPSIS
	This command would help to set user preferences for EULA and Privacy.
	.DESCRIPTION
	This command would help to set user preferences for EULA and Privacy.

	.PARAMETER AcceptPrivacyNotice
		Provide the flag to suppress the Privacy notice prompt and submit the acceptance. (Yes/No)

	.LINK
	https://aka.ms/azskossdocs

	#>
    Param
    (
        [Parameter(Mandatory = $true, HelpMessage = "Provide the flag to suppress the Privacy notice prompt and submit the acceptance. (Yes/No)")]
        [string]
        [ValidateSet("Yes", "No")]
		[Alias("apn")]
        $AcceptPrivacyNotice
    )
    Begin {
        [CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
        [ListenerHelper]::RegisterListeners();
    }
    Process {
        try {
            $azskSettings = [ConfigurationManager]::GetLocalAzSKSettings();

            if ($AcceptPrivacyNotice -eq "yes") {
                $azskSettings.PrivacyNoticeAccepted = $true
                $azskSettings.UsageTelemetryLevel = "Anonymous"
            }

            if ($AcceptPrivacyNotice -eq "no") {
                $azskSettings.PrivacyNoticeAccepted = $false
                $azskSettings.UsageTelemetryLevel = "None"
            }
            [ConfigurationManager]::UpdateAzSKSettings($azskSettings)
            [EventBase]::PublishGenericCustomMessage("Successfully updated privacy settings.");
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }

    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }
}

function Clear-AzSKSessionState {

    Write-Host "Clearing AzSK session state..." -ForegroundColor Yellow
    [ConfigOverride]::ClearConfigInstance()
    Write-Host "Session state cleared." -ForegroundColor Yellow

}

. $PSScriptRoot\Framework\Helpers\AliasHelper.ps1
