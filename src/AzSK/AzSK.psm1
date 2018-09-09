Set-StrictMode -Version Latest
Write-Host "Importing AzureRM modules. This may take a while..." -ForegroundColor Yellow
Import-Module AzureRM.Profile -RequiredVersion 5.5.1

. $PSScriptRoot\Framework\Framework.ps1

@("$PSScriptRoot\SVT", "$PSScriptRoot\AlertMonitoring", "$PSScriptRoot\SubscriptionSecurity", "$PSScriptRoot\ContinuousAssurance" , "$PSScriptRoot\AzSKInfo", "$PSScriptRoot\PolicySetup", "$PSScriptRoot\ARMChecker") |
    ForEach-Object {
    (Get-ChildItem -Path $_ -Recurse -File -Include "*.ps1") |
        ForEach-Object {
        . $_.FullName
    }
}
#create aliases
function Get-AzSKAccessToken {
    <#
	.SYNOPSIS
	This command would help in generating the access token from the current login context for the specified resource URI.
	.DESCRIPTION
	This command would help in generating the access token from the current login context for the specified resource URI.

	.PARAMETER ResourceAppIdURI
		Provide the Resource App ID URI
	.PARAMETER TenantId
		Current logged in user tenant id.

	.LINK
	https://aka.ms/azskossdocs

	#>
    Param(
        [Parameter(Mandatory = $true, HelpMessage = "Provide the Resource App ID URI")]
        [string]
		[Alias("rau")]
        $ResourceAppIdURI,

        [Parameter(Mandatory = $false, HelpMessage = "Current logged in user tenant id.")]
        [string]
		[Alias("ti")]
        $TenantId
    )
	Begin 
	{
		[CommandHelper]::BeginCommand($MyInvocation);
	}
	Process 
	{
		try 
		{
			[Helpers]::GetAccessToken($ResourceAppIdURI, $TenantId);		
		}
		catch 
		{
	        [EventBase]::PublishGenericException($_);
        }
	} 
}

function Get-AzSKSupportedResourceTypes {
    <#
	.SYNOPSIS
	This command would list all the resource types of Azure Services which are currently supported by AzSK
	.DESCRIPTION
	This command would list all the resource types of Azure Services which are currently supported by AzSK

	.LINK
	https://aka.ms/azskossdocs

	#>
    Param()
	Begin 
	{
        [CommandHelper]::BeginCommand($MyInvocation);
    }
	Process 
	{
		try 
		{
			[SVTMapping]::Mapping | Select-Object -Property ResourceTypeName, ResourceType | Sort-Object -Property ResourceTypeName;
		}
		catch 
		{
            [EventBase]::PublishGenericException($_);
        }
	}
}

function Set-AzSKPolicySettings {
    <#
	.SYNOPSIS
	This command would help to set online policy store URL.
	.DESCRIPTION
	This command would help to set online policy store URL.

	.PARAMETER OnlinePolicyStoreURL
		Provide the online policy URL
	.PARAMETER DisableOnlinePolicy
		Flag to disable online policy.
	.PARAMETER EnableAADAuthForOnlinePolicyStore
		Enables AAD authentication for online policy store.
	.PARAMETER EnableOnlinePolicy
		Provide the flag to enable online policy
	.PARAMETER AutoUpdateCommand
			Provide org install URL
	.PARAMETER AutoUpdate
			Toggle the auto-update feature
	
	.LINK
	https://aka.ms/azskossdocs

	#>
    Param(
        [Parameter(Mandatory = $false, HelpMessage = "Provide the Online Policy Store URI")]
        [Alias("LocalOrgPolicyFolderPath")]
        [string]
		[Alias("opu")]
        $OnlinePolicyStoreUrl,

        [Parameter(Mandatory = $false, HelpMessage = "Provide the flag to enable online policy")]
        [switch]
		[Alias("eop")]
        $EnableOnlinePolicy,

        [Parameter(Mandatory = $false, HelpMessage = "Provide the flag to disable online policy")]
        [switch]
		[Alias("dop")]
        $DisableOnlinePolicy,

        [Parameter(Mandatory = $false, HelpMessage = "Provide the flag to enable auth for online policy")]
        [switch]
		[Alias("eaop")]
        $EnableAADAuthForOnlinePolicyStore,

        [Parameter(Mandatory = $false, HelpMessage = "Provide org install URL")]
        [string]
		[Alias("auc")]
        $AutoUpdateCommand,

        [Parameter(Mandatory = $false, ParameterSetName = "AutoUpdatePolicy", HelpMessage = "Toggle the auto-update feature")]
        [ValidateSet("On", "Off", "NotSet")]
		[Alias("au")]
        $AutoUpdate,

		[Parameter(Mandatory = $true, ParameterSetName = "CACentralMode")]
		[switch]
        $EnableCentralScanMode
    )
    Begin {
        [CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
        [ListenerHelper]::RegisterListeners();
    }
    Process {
        try {

			$azskSettings = [ConfigurationManager]::GetLocalAzSKSettings();
            if (-not [string]::IsNullOrWhiteSpace($OnlinePolicyStoreUrl)) {
                try {
                    $url = [System.Net.WebRequest]::Create($OnlinePolicyStoreUrl)
                }
                catch {
                    [EventBase]::PublishGenericCustomMessage("Enter valid URL : $OnlinePolicyStoreUrl", [MessageType]::Error);
                    return
                }

                $azskSettings.OnlinePolicyStoreUrl = $OnlinePolicyStoreUrl

                if ($EnableAADAuthForOnlinePolicyStore) {
                    $azskSettings.EnableAADAuthForOnlinePolicyStore = $true
                }
                else {
                    $azskSettings.EnableAADAuthForOnlinePolicyStore = $false
                }
            }

            if ($EnableAADAuthForOnlinePolicyStore) {
                $azskSettings.EnableAADAuthForOnlinePolicyStore = $true
            }

            if ($DisableOnlinePolicy) {
                $azskSettings.UseOnlinePolicyStore = $false
            }

            if ($EnableOnlinePolicy) {
                $azskSettings.UseOnlinePolicyStore = $true
            }

            if (-not [string]::IsNullOrWhiteSpace($AutoUpdateCommand)) {
                $azskSettings.AutoUpdateCommand = $AutoUpdateCommand;
            }

            if ($AutoUpdate) {
                $azskSettings.AutoUpdateSwitch = $AutoUpdate
            }
			if($EnableCentralScanMode)
			{
				 $azskSettings.IsCentralScanModeOn = $EnableCentralScanMode
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

function Set-AzSKUserPreference {
    <#
	.SYNOPSIS
	This command would help to set user preferences for AzSK.
	.DESCRIPTION
	This command would help to set user preferences for AzSK.

	.PARAMETER OutputFolderPath
    Provide the custom folder path for output files generated from AzSK
	.PARAMETER ResetOutputFolderPath
    Reset the output folder path to default value
    .PARAMETER DoNotOpenOutputFolder
    Switch to specify whether to open output folder.
	.LINK
	https://aka.ms/azskossdocs

	#>
    Param
    (
        [Parameter(Mandatory = $true, ParameterSetName = "Set OutputFolderPath", HelpMessage = "Provide the custom folder path for output files generated from AzSK")]
        [string]
		[Alias("ofp")]
        $OutputFolderPath,

        [Parameter(Mandatory = $true, ParameterSetName = "Reset OutputFolderPath", HelpMessage = "Reset the output folder path to default value")]
        [switch]
		[Alias("rofp")]
        $ResetOutputFolderPath,

        [switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder.")]
		[Alias("dnof")]
        $DoNotOpenOutputFolder,

        [switch]
        [Parameter(Mandatory = $true, ParameterSetName = "EnableComplianceStorage", HelpMessage = "Switch to enable storage of compliance report data at subscription.")]
        [Alias("scus")]
		$StoreComplianceSummaryInUserSubscriptions,

        [switch]
        [Parameter(Mandatory = $false, ParameterSetName = "DisableComplianceStorage", HelpMessage = "Switch to disable storage of compliance report data at subscription.")]
        [Alias("dcsus")]
		$DisableComplianceSummaryStorageInUserSubscriptions
    )
    Begin {
        [CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
        [ListenerHelper]::RegisterListeners();
    }
    Process {
        try {
            $azskSettings = [ConfigurationManager]::GetLocalAzSKSettings();
            if ($ResetOutputFolderPath) {
                
                $azskSettings.OutputFolderPath = "";
                [EventBase]::PublishGenericCustomMessage("Output folder path has been reset successfully");
            }
            elseif (-not [string]::IsNullOrWhiteSpace($OutputFolderPath)) {
                if (Test-Path -Path $OutputFolderPath) {                    
                    $azskSettings.OutputFolderPath = $OutputFolderPath;
                    [EventBase]::PublishGenericCustomMessage("Output folder path has been changed successfully");
                }
                else {
                    [EventBase]::PublishGenericCustomMessage("The specified path does not exist", [MessageType]::Error);
                }
            }
            
            if($StoreComplianceSummaryInUserSubscriptions)
            {
                $azskSettings.StoreComplianceSummaryInUserSubscriptions = $true;
            }
            if($DisableComplianceSummaryStorageInUserSubscriptions)
            {
                $azskSettings.StoreComplianceSummaryInUserSubscriptions = $false;
            }
            
            [ConfigurationManager]::UpdateAzSKSettings($azskSettings);
            [EventBase]::PublishGenericCustomMessage("Successfully set user preference");
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }
    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }
}

function Send-AzSKInternalData {
    <#
	.SYNOPSIS
	This command is for internal use. Not recommended to run until advised by support team.
	.DESCRIPTION
	This command is for internal use. Not recommended to run until advised by support team.

	.PARAMETER SubscriptionId
		Subscription id for which the data to be sent.

	.LINK
	https://aka.ms/azskossdocs

	#>
    Param
    (
        [string]
        [Parameter(Mandatory = $true, HelpMessage="Subscription id for which the data to be sent.")]
        [ValidateNotNullOrEmpty()]
		[Alias("sid","s")]
        $SubscriptionId
    )
    Begin {
        [CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
        [ListenerHelper]::RegisterListeners();
    }
    Process {
        try {
            $resolver = [SVTResourceResolver]::new($SubscriptionId);
            $secStatus = [ServicesSecurityStatus]::new($SubscriptionId, $PSCmdlet.MyInvocation, $resolver);
            if ($secStatus) {				
			return $secStatus.InvokeFunction($secStatus.ComputeApplicableControls)               
            }
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
    Write-Host "Completed." -ForegroundColor Yellow

}

. $PSScriptRoot\Framework\Helpers\AliasHelper.ps1
