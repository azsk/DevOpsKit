Set-StrictMode -Version Latest
#Import-Module AzureRM.Resources
#Import-Module AzureRM.KeyVault
#Import-Module AzureRM.Sql
#Import-Module AzureRM.Storage
#Import-Module AzureRM.DataLakeAnalytics
#Import-Module AzureRM.DataLakeStore
#Import-Module AzureRM.Network
#Import-Module AzureRM.Compute

Import-Module AzureRM.Profile -RequiredVersion 4.2.0  
Import-Module Azure.Storage -RequiredVersion 4.1.0
Import-Module AzureRM.AnalysisServices -RequiredVersion 0.6.2
Import-Module AzureRM.ApplicationInsights -RequiredVersion 0.1.1
Import-Module AzureRM.Automation -RequiredVersion 4.2.0
Import-Module AzureRM.Batch -RequiredVersion 4.0.4
Import-Module AzureRM.Cdn -RequiredVersion 4.1.0
Import-Module AzureRM.Compute -RequiredVersion 4.2.0
Import-Module AzureRM.DataFactories -RequiredVersion 4.1.0
Import-Module AzureRM.DataFactoryV2 -RequiredVersion 0.5.0
Import-Module AzureRM.DataLakeAnalytics -RequiredVersion 4.2.0
Import-Module AzureRM.DataLakeStore -RequiredVersion 5.1.0
Import-Module AzureRM.EventHub -RequiredVersion 0.5.1
Import-Module AzureRM.HDInsight -RequiredVersion 4.0.2
Import-Module AzureRM.Insights -RequiredVersion 4.0.1
Import-Module AzureRM.KeyVault -RequiredVersion 4.1.0
Import-Module AzureRM.LogicApp -RequiredVersion 4.0.1
Import-Module AzureRM.Network -RequiredVersion 5.1.0
Import-Module AzureRM.NotificationHubs -RequiredVersion 4.1.0
Import-Module AzureRM.OperationalInsights -RequiredVersion 4.1.0
Import-Module AzureRM.RedisCache -RequiredVersion 4.1.0
Import-Module AzureRM.Resources -RequiredVersion 5.2.0
Import-Module AzureRM.Scheduler -RequiredVersion 0.16.1
Import-Module AzureRM.ServiceBus -RequiredVersion 0.5.1
Import-Module AzureRM.ServiceFabric -RequiredVersion 0.3.1
Import-Module AzureRM.Sql -RequiredVersion 4.2.0
Import-Module AzureRM.Storage -RequiredVersion 4.2.0
Import-Module AzureRM.StreamAnalytics -RequiredVersion 4.0.2
Import-Module AzureRM.Tags -RequiredVersion 4.0.0
Import-Module AzureRM.TrafficManager -RequiredVersion 4.0.1
Import-Module AzureRM.Websites -RequiredVersion 4.1.0

. $PSScriptRoot\Framework\Framework.ps1

@("$PSScriptRoot\SVT", "$PSScriptRoot\AlertMonitoring", "$PSScriptRoot\SubscriptionSecurity", "$PSScriptRoot\ContinuousAssurance" , "$PSScriptRoot\MetadataInfo", "$PSScriptRoot\PolicySetup", "$PSScriptRoot\ARMChecker") |
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
        $ResourceAppIdURI,

        [Parameter(Mandatory = $false, HelpMessage = "Current logged in user tenant id.")]
        [string]
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
        [string]
        $OnlinePolicyStoreUrl,

        [Parameter(Mandatory = $false, HelpMessage = "Provide the flag to enable online policy")]
        [switch]
        $EnableOnlinePolicy,

        [Parameter(Mandatory = $false, HelpMessage = "Provide the flag to disable online policy")]
        [switch]
        $DisableOnlinePolicy,

        [Parameter(Mandatory = $false, HelpMessage = "Provide the flag to enable auth for online policy")]
        [switch]
        $EnableAADAuthForOnlinePolicyStore,

        [Parameter(Mandatory = $false, HelpMessage = "Provide org install URL")]
        [string]
        $AutoUpdateCommand,

        [Parameter(Mandatory = $false, ParameterSetName = "AutoUpdatePolicy", HelpMessage = "Toggle the auto-update feature")]
        [ValidateSet("On", "Off", "NotSet")]
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
        $LocalAIOrgTelemetryKey,

        [Parameter(Mandatory = $true, HelpMessage = "Provide the flag to enable local control telemetry")]
        [bool]
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
        $OutputFolderPath,

        [Parameter(Mandatory = $true, ParameterSetName = "Reset OutputFolderPath", HelpMessage = "Reset the output folder path to default value")]
        [switch]
        $ResetOutputFolderPath,

        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder.")]
		$DoNotOpenOutputFolder
    )
    Begin {
        [CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
        [ListenerHelper]::RegisterListeners();
    }
    Process {
        try {
            if ($ResetOutputFolderPath) {
                $azskSettings = [ConfigurationManager]::GetLocalAzSKSettings();
                $azskSettings.OutputFolderPath = "";
                [ConfigurationManager]::UpdateAzSKSettings($azskSettings);
                [EventBase]::PublishGenericCustomMessage("Output folder path has been reset successfully");
            }
            elseif (-not [string]::IsNullOrWhiteSpace($OutputFolderPath)) {
                if (Test-Path -Path $OutputFolderPath) {
                    $azskSettings = [ConfigurationManager]::GetLocalAzSKSettings();
                    $azskSettings.OutputFolderPath = $OutputFolderPath;
                    [ConfigurationManager]::UpdateAzSKSettings($azskSettings);
                    [EventBase]::PublishGenericCustomMessage("Output folder path has been changed successfully");
                }
                else {
                    [EventBase]::PublishGenericCustomMessage("The specified path does not exist", [MessageType]::Error);
                }
            }
            else {
                [EventBase]::PublishGenericCustomMessage("The specified path is null or empty", [MessageType]::Error);
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

function Clear-AzSKCache {
    [ConfigOverride]::ClearConfigInstance()
}

. $PSScriptRoot\Framework\Helpers\AliasHelper.ps1
