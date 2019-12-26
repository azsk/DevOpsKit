Set-StrictMode -Version Latest

. $PSScriptRoot\Framework\Framework.ps1

@("$PSScriptRoot\SVT") |
    ForEach-Object {
    (Get-ChildItem -Path $_ -Recurse -File -Include "*.ps1") |
        ForEach-Object {
        . $_.FullName
    }
}

function Set-AzSKAzureDevOpsPolicySettings {
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

$FrameworkPath = $PSScriptRoot

. $FrameworkPath\Framework\Helpers\AliasHelper.ps1
