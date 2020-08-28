Set-StrictMode -Version Latest

. $PSScriptRoot\Framework\Framework.ps1


#These are the topmost folder PS1 files that load 
@("$PSScriptRoot\SVT", "$PSScriptRoot\AlertMonitoring", "$PSScriptRoot\ContinuousAssurance","$PSScriptRoot\AzSKADOInfo") |
    ForEach-Object {
    (Get-ChildItem -Path $_ -Recurse -File -Include "*.ps1") |
        ForEach-Object {
        . $_.FullName
    }
}


function Set-AzSKADOPrivacyNoticeResponse {
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
    [Alias("Set-AzSKPrivacyNoticeResponse")]
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

function Clear-AzSKADOSessionState {

    Write-Host "Clearing $([Constants]::AzSKModuleName) session state..." -ForegroundColor Yellow
    [ConfigOverride]::ClearConfigInstance()
    Write-Host "Session state cleared." -ForegroundColor Yellow

}


function Set-AzSKADOPolicySettings {
    <#
	.SYNOPSIS
	This command would help to set online policy store URL.
	.DESCRIPTION
	This command would help to set online policy store URL.

	.PARAMETER AutoUpdateCommand
			Provide org install URL
	.PARAMETER AutoUpdate
            Toggle the auto-update feature
    #>
    [Alias("Set-AzSKPolicySettings")]
    Param(
        [Parameter(Mandatory = $false, HelpMessage = "Provide org install URL")]
        [string]
		[Alias("auc")]
        $AutoUpdateCommand,

        [Parameter(Mandatory = $false, ParameterSetName = "AutoUpdatePolicy", HelpMessage = "Toggle the auto-update feature")]
        [ValidateSet("On", "Off", "NotSet")]
		[Alias("au")]
        $AutoUpdate,

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
            
            if (-not [string]::IsNullOrWhiteSpace($AutoUpdateCommand)) 
            {
                $azskSettings.AutoUpdateCommand = $AutoUpdateCommand;
            }
            if ($AutoUpdate) 
            {
                $azskSettings.AutoUpdateSwitch = $AutoUpdate
            }

            if($ScannerToolPath -and $ScannerToolName)
            {
                $azskSettings.ScanToolPath = $ScannerToolPath
                $azskSettings.ScanToolName = $ScannerToolName
            }
            
            [ConfigurationManager]::UpdateAzSKSettings($azskSettings);
            [ConfigOverride]::ClearConfigInstance();            
            [EventBase]::PublishGenericCustomMessage("Successfully configured settings.", [MessageType]::Warning);
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }
    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }
}

#$FrameworkPath = $PSScriptRoot

. $FrameworkPath\Helpers\AliasHelper.ps1
