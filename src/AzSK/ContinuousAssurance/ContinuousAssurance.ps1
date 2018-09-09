Set-StrictMode -Version Latest
function Install-AzSKContinuousAssurance 
{
	<#
	.SYNOPSIS
	This command would help in installing Automation Account in your subscription to setup Continuous Assurance feature of AzSK 
	.DESCRIPTION
	This command will install an Automation Account (Name: AzSKContinuousAssurance) which runs security scan on subscription and resource groups which are specified during installation.
	Security scan results will be populated in OMS which is configured during installation. Also, detailed logs will be stored in storage account (Name: azskyyyyMMddHHmmss format).  
	
	.PARAMETER SubscriptionId
		Subscription id in which Automation Account needs to be installed.
	.PARAMETER AutomationAccountLocation
		Location of resource group which contains Automation Account. This is optional. Default location is EastUS2.
	.PARAMETER AutomationAccountRGName
		Name of ResourceGroup where AutomationAccount will be installed.
	.PARAMETER AutomationAccountName
		Name of AutomationAccount. Default value is AzSKContinuousAssurance.
	.PARAMETER ResourceGroupNames
		Comma separated Application resource group names on which security scan should be performed by Automation Account.
	.PARAMETER OMSWorkspaceId
		Workspace ID of OMS where security scan results will be sent
	.PARAMETER OMSSharedKey
		Shared key of OMS which is used to monitor security scan results.
	.PARAMETER LoggingOption
		Gives the flexibility for the users to choose from central sub reports storage mode vs individual sub reports storage in CA Scaling scenario.
	.PARAMETER AzureADAppName
		Name for the Azure Active Directory (AD) Application that will be created in the subscription for running the runbook.
	.PARAMETER AltOMSWorkspaceId
		Alternate Workspace ID of OMS to monitor security scan results.
	.PARAMETER AltOMSSharedKey
		Shared key of Alternate OMS which is used to monitor security scan results.
	.PARAMETER WebhookUrl
		All the scan results shall be posted to this configured webhook.
	.PARAMETER WebhookAuthZHeaderName
		Name of the AuthZ header. (typically 'Authorization')
	.PARAMETER WebhookAuthZHeaderValue
		Value of the AuthZ header.
	.PARAMETER ScanIntervalInHours
		Overrides the default scan interval (24hrs) with the custom provided value.
	.PARAMETER LoggingOption
		This provides the capability to users to store the CA scan logs on central subscription or on individual subscriptions.
	.PARAMETER SkipTargetSubscriptionConfig
		It would skip all the required central scanning configuration on the targets subs. It is owners responsibility to get the target subs configured correctly.
	.PARAMETER TargetSubscriptionIds
		Comma separated values of target subscriptionIds that will be monitored through CA from a central subscription.
	.PARAMETER CentralScanMode
		This enables AzSK CA in central scanning mode. Use this switch along with TargetSubscriptionIds param to register target subscriptions in the central CA.
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder.
	.NOTES
	

	.LINK
	https://aka.ms/azskossdocs 

	#>
	Param(
		[Parameter(Position = 0, Mandatory = $true, ParameterSetName = "Default", HelpMessage="Id of the subscription in which Automation Account needs to be installed.")]
		[Parameter(Position = 0, Mandatory = $true, ParameterSetName = "CentralScanMode", HelpMessage="Id of the subscription in which Automation Account needs to be installed.")]
        [string]
		[Alias("sid", "HostSubscriptionId", "hsid")]
		$SubscriptionId ,

		[Parameter(Mandatory = $true, ParameterSetName = "CentralScanMode", HelpMessage="Comma separated values of target subscriptionIds that will be monitored through CA from a central subscription.")]
        [string]
		[Alias("tsids")]
		$TargetSubscriptionIds,

		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [string]
		[Alias("loc")]
		$AutomationAccountLocation,

		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [string]
		[Alias("aargn")]
		$AutomationAccountRGName,

		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [string]
		[Alias("aan")]
		$AutomationAccountName,

        [Parameter(Position = 1, Mandatory = $true, ParameterSetName = "CentralScanMode")]
        [Parameter(Position = 1, Mandatory = $true, ParameterSetName = "Default")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("rgns")]
		$ResourceGroupNames ,       

        [Parameter(Position = 2, Mandatory = $true, ParameterSetName = "CentralScanMode", HelpMessage="Workspace ID of OMS where security scan results will be populated.")]
        [Parameter(Position = 2, Mandatory = $true, ParameterSetName = "Default", HelpMessage="Workspace ID of OMS where security scan results will be populated.")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("owid")]
		$OMSWorkspaceId,

        [Parameter(Position = 3, Mandatory = $true, ParameterSetName = "CentralScanMode", HelpMessage="Shared key of OMS which is used to monitor security scan results.")]
        [Parameter(Position = 3, Mandatory = $true, ParameterSetName = "Default", HelpMessage="Shared key of OMS which is used to monitor security scan results.")]
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("okey")]
		$OMSSharedKey,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]
        [string]
		[Alias("aowid")]
		$AltOMSWorkspaceId,

        [Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]
        [string]
		[Alias("aokey")]
		$AltOMSSharedKey,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]
        [string]
		[Alias("wurl")]
		$WebhookUrl,

        [Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]
        [string]
		[Alias("whn")]
		$WebhookAuthZHeaderName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]
        [string]
		[Alias("whv")]
		$WebhookAuthZHeaderValue,


        [Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]		
        [Parameter(Mandatory = $false, ParameterSetName = "Default")]		
        [string]
		[ValidateNotNullOrEmpty()]
		[Alias("spn")]
        $AzureADAppName,

		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[CAReportsLocation]
		[Alias("lo")]
		$LoggingOption,

		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
        [Parameter(Mandatory = $false, ParameterSetName = "Default")]		
		[int]
		[Alias("si")]
		$ScanIntervalInHours,

		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[switch]
		[Alias("stsc")]
		$SkipTargetSubscriptionConfig,

		[Parameter(Mandatory = $true, ParameterSetName = "CentralScanMode", HelpMessage="This enables AzSK CA in central scanning mode. Use this switch along with TargetSubscriptionIds param to register target subscriptions in the central CA.")]
		[switch]
		[Alias("csm")]
		$CentralScanMode,

		[switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder or not.")]
		[Alias("dnof")]
		$DoNotOpenOutputFolder,

		[switch]
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Trigger scan on resource addition.")]
		[Alias("sod")]
		$ScanOnDeployment
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
			$isDefaultRGNameUsed = ![string]::IsNullOrWhiteSpace($AutomationAccountRGName) -and $AutomationAccountRGName -eq [UserSubscriptionDataHelper]::GetUserSubscriptionRGName()
			$isDefaultCANameUsed = ![string]::IsNullOrWhiteSpace($AutomationAccountName) -and $AutomationAccountName -eq [UserSubscriptionDataHelper]::GetCAName()
			$errMsg = ""
			if($isDefaultRGNameUsed)
			{
				$errMsg = "The specified 'AutomationAccountRGName' parameter value is reserved for toolkit use."
			}
			if($isDefaultCANameUsed)
			{
				$errMsg += "`r`nThe specified 'AutomationAccountName' parameter value is reserved for toolkit use."
			}
			if(![string]::IsNullOrWhiteSpace($errMsg))
			{
				$errMsg += "`r`nPlease use different (unique) names for CA account and/or resource group."
				throw ([SuppressedException]::new(($errMsg), [SuppressedExceptionType]::InvalidOperation))
			}
			$ccAccount = [CCAutomation]::new($SubscriptionId, $PSCmdlet.MyInvocation,`
				$AutomationAccountLocation, $AutomationAccountRGName, $AutomationAccountName, $ResourceGroupNames,`
				$AzureADAppName, $ScanIntervalInHours);
			#set the OMS settings
			$ccAccount.SetOMSSettings($OMSWorkspaceId, $OMSSharedKey, $AltOMSWorkspaceId, $AltOMSSharedKey);

			#set the Webhook settings
			$ccAccount.SetWebhookSettings($WebhookUrl, $WebhookAuthZHeaderName, $WebhookAuthZHeaderValue);
			

			if ($ccAccount) 
			{
				$ccAccount.ScanOnDeployment = $ScanOnDeployment;

				if($PSCmdlet.ParameterSetName -eq "CentralScanMode")
				{
					$ccAccount.IsCentralScanModeOn = $true;
					$ccAccount.TargetSubscriptionIds = $TargetSubscriptionIds;
					$ccAccount.SkipTargetSubscriptionConfig = $SkipTargetSubscriptionConfig;
					if($null -eq $LoggingOption)
					{
						$ccAccount.LoggingOption = [CAReportsLocation]::CentralSub;
					}
					else
					{
						$ccAccount.LoggingOption = $LoggingOption;
					}
				}

				
				return $ccAccount.InvokeFunction($ccAccount.InstallAzSKContinuousAssurance);
			}			
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

function Update-AzSKContinuousAssurance 
{
	<#
	.SYNOPSIS
	This command would help in updating user configurable properties of Continuous Assurance Automation Account in your subscription
	.DESCRIPTION
	This command is helpful if you want to update any of the following properties. 1. App Resource Groups 2. OMS Workspace ID 3. OMS Shared Key
	4. Connection in Run as Account 5. Update/Renew Certificate in Run as Account

	.PARAMETER SubscriptionId
		Subscription id in which Automation Account exists
	.PARAMETER ResourceGroupNames
		Comma separated Application resource group names on which security scan should be performed by Automation Account
	.PARAMETER AutomationAccountRGName
		Name of ResourceGroup where AutomationAccount will be installed.
	.PARAMETER AutomationAccountName
		Name of AutomationAccount. Default value is AzSKContinuousAssurance.
	.PARAMETER OMSWorkspaceId
		Workspace ID of OMS where security scan results will be populated
	.PARAMETER OMSSharedKey
		Shared key of OMS which is used to monitor security scan results
	.PARAMETER AzureADAppName
		Name for the Azure Active Directory (AD) Application that will be created to update automation account Connection in Run As Account for running the runbook
	.PARAMETER UpdateCertificate
		Switch to update certificate credential for AzureADApp SPN and upload the certificate to automation account.
	.PARAMETER TargetSubscriptionIds
		Comma separated values of targetsubscriptionIds that will get monitored from the central subscription through CA. Use this switch along with CentralScanMode switch.
	.PARAMETER AltOMSWorkspaceId
		Alternate Workspace ID of OMS to monitor security scan results
	.PARAMETER AltOMSSharedKey
		Shared key of Alternate OMS which is used to monitor security scan results
	.PARAMETER WebhookUrl
		All the scan results shall be posted to this configured webhook
	.PARAMETER WebhookAuthZHeaderName
		Name of the AuthZ header (typically 'Authorization')
	.PARAMETER WebhookAuthZHeaderValue
		Value of the AuthZ header
	.PARAMETER ScanIntervalInHours
		Overrides the default scan interval (24hrs) with the custom provided value 	
	.PARAMETER SkipTargetSubscriptionConfig
		It would skip all the required central scanning configuration on the targets subs. It is owners responsibility to get the target subs configured correctly	
	.PARAMETER LoggingOption
		This provides the capability to users to store the CA scan logs on central subscription or on individual subscriptions
	.PARAMETER CentralScanMode
		This switch is required to update AzSK CA running in central scanning mode.
	.PARAMETER FixRuntimeAccount
		Use this switch to fix CA runtime account in case of below issues. 1. Runtime account deleted (Permissions required: Subscription owner) 2. Runtime account permissions missing (Permissions required: Subscription owner and AD App owner) 3. Certificate deleted/expired (Permissions required: Subscription owner and AD App owner)
    .PARAMETER NewRuntimeAccount
		Use this switch to create new CA runtime account.
	.PARAMETER RenewCertificate
			 Renews certificate credential of CA SPN if the caller is Owner of the AAD Application (SPN). If the caller is not Owner, a new application is created with a corresponding SPN and a certificate owned by the caller. CA uses the updated credential going forward.
	.PARAMETER FixModules
			 Use this switch in case 'AzureRm.Automation' module extraction fails in CA Automation Account. 
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder.
	.NOTES
	

	.LINK
	https://aka.ms/azskossdocs 

	#>
	Param(
		[Parameter(Position = 0, Mandatory = $true, ParameterSetName = "Default", HelpMessage="Subscription id in which Automation Account exists")]
		[Parameter(Position = 0, Mandatory = $true, ParameterSetName = "CentralScanMode", HelpMessage="Subscription id in which Automation Account exists")]
		[Parameter(Position = 0, Mandatory = $true, ParameterSetName = "RemoveSettings", HelpMessage="Subscription id in which Automation Account exists")]
		[string]
		[Alias("sid", "HostSubscriptionId", "hsid")]
		$SubscriptionId,

		[Parameter(Mandatory = $true, ParameterSetName = "CentralScanMode", HelpMessage="Comma separated values of targetsubscriptionIds that will get monitored from the central subscription through CA. Use this switch along with CentralScanMode switch.")]
        [string]
		[Alias("tsids")]
		$TargetSubscriptionIds,
        
		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]
        [string]
		[Alias("rgns")]
		$ResourceGroupNames,

		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [string]
		[Alias("aargn")]
		$AutomationAccountRGName,

		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [string]
		[Alias("aan")]
		$AutomationAccountName,
		
		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]	
        [string]
		[Alias("owid")]
		$OMSWorkspaceId,

        [Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]
        [string]
		[Alias("okey")]
		$OMSSharedKey,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]
        [string]
		[Alias("aowid")]
		$AltOMSWorkspaceId,

        [Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]
        [string]
		[Alias("aokey")]
		$AltOMSSharedKey,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]
        [string]
		[Alias("wurl")]
		$WebhookUrl,

        [Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]
        [string]
		[Alias("whn")]
		$WebhookAuthZHeaderName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]
        [string]
		[Alias("whv")]
		$WebhookAuthZHeaderValue,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[ValidateNotNullOrEmpty()]
		[Alias("spn")]
		$AzureADAppName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
        [switch]
		[Alias("fra","ConfigureRuntimeAccount", "cra")]
		$FixRuntimeAccount,

        [Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
        [switch]
		[Alias("nra")]
		$NewRuntimeAccount,


		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
        [switch]
		[Alias("rc")]
		$RenewCertificate,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
        [switch]
		[Alias("fm")]
		$FixModules,

		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[CAReportsLocation]
		[Alias("lo")]
		$LoggingOption,

		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[int]
		[Alias("si")]
		$ScanIntervalInHours,

		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[switch]
		[Alias("stsc")]
		$SkipTargetSubscriptionConfig,

		[Parameter(Mandatory = $true, ParameterSetName = "CentralScanMode", HelpMessage="This switch is required to update AzSK CA running in central scanning mode.")]
		[switch]
		[Alias("csm")]
		$CentralScanMode,

		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder or not.")]
		[Alias("dnof")]
		$DoNotOpenOutputFolder,

		[Parameter(Mandatory = $true, ParameterSetName = "RemoveSettings", HelpMessage="This switch is used to clear setting for OMS,AltOMS or Webhook.")]
		[ValidateSet("OMSSettings","AltOMSSettings","WebhookSettings","ScanOnDeployment")]
		[Alias("rmv")]
		$Remove,

		[switch]
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Trigger scan on resource addition.")]
		[Alias("sod")]
		$ScanOnDeployment
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
				$ccAccount = [CCAutomation]::new($SubscriptionId, $PSCmdlet.MyInvocation, $null, $AutomationAccountRGName, $AutomationAccountName, `
				$ResourceGroupNames, $AzureADAppName, $ScanIntervalInHours);
			if($PSCmdlet.ParameterSetName -eq "RemoveSettings")
			{
				switch($Remove)
				{
					"OMSSettings" {
						return $ccAccount.InvokeFunction($ccAccount.RemoveOMSSettings);								 
						}
					"AltOMSSettings" {
						return $ccAccount.InvokeFunction($ccAccount.RemoveAltOMSSettings);
						}
					"WebhookSettings" {
						return $ccAccount.InvokeFunction($ccAccount.RemoveWebhookSettings);
						}
					"ScanOnDeployment" {
						return $ccAccount.InvokeFunction($ccAccount.ClearResourceofDeploymentScan);
						}
				}
					

			}
			else
			{
					#set the OMS settings
					$ccAccount.SetOMSSettings($OMSWorkspaceId, $OMSSharedKey, $AltOMSWorkspaceId, $AltOMSSharedKey);

			#set the Webhook settings
			$ccAccount.SetWebhookSettings($WebhookUrl, $WebhookAuthZHeaderName, $WebhookAuthZHeaderValue);

			if ($ccAccount) 
			{
				$ccAccount.ScanOnDeployment = $ScanOnDeployment;

					if($PSCmdlet.ParameterSetName -eq "CentralScanMode")
					{
						$ccAccount.IsCentralScanModeOn = $true;
						$ccAccount.TargetSubscriptionIds = $TargetSubscriptionIds;
						$ccAccount.SkipTargetSubscriptionConfig = $SkipTargetSubscriptionConfig;
						if($null -eq $LoggingOption)
						{
							$ccAccount.LoggingOption = [CAReportsLocation]::CentralSub;
						}
						else
						{
							$ccAccount.LoggingOption = $LoggingOption;
						}
					}
					return $ccAccount.InvokeFunction($ccAccount.UpdateAzSKContinuousAssurance,@($FixRuntimeAccount,$NewRuntimeAccount,$RenewCertificate,$FixModules));
				}
			}
			
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

function Get-AzSKContinuousAssurance 
{
	<#
	.SYNOPSIS
	This command would help in getting details of Continuous Assurance Automation Account in your subscription
	.DESCRIPTION

	.PARAMETER SubscriptionId
		Subscription id in which Automation Account exists
	.PARAMETER AutomationAccountRGName
		Name of ResourceGroup where AutomationAccount will be installed.
	.PARAMETER AutomationAccountName
		Name of AutomationAccount. Default value is AzSKContinuousAssurance.
	.PARAMETER ExhaustiveCheck
		By appending this switch it would check whether all the modules installed in central automation account are up to date. Only include if default diagnosis is not resulting in any issue.
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder.
	.LINK
	https://aka.ms/azskossdocs 

	#>
	Param(
		[Parameter(Position = 0, Mandatory = $true, HelpMessage="Subscription id for which the security evaluation has to be performed.")]
        [string]
		[Alias("sid","s","HostSubscriptionId", "hsid")]
		$SubscriptionId,

		[Parameter(Mandatory = $false)]
        [string]
		[Alias("aargn")]
		$AutomationAccountRGName,

		[Parameter(Mandatory = $false)]
        [string]
		[Alias("aan")]
		$AutomationAccountName,

		[Parameter(Mandatory = $false)]
		[switch]
		[Alias("ec")]
		$ExhaustiveCheck,

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
			$ccAccount = [CCAutomation]::new($SubscriptionId, $AutomationAccountRGName, $AutomationAccountName, $PSCmdlet.MyInvocation);

			if ($ccAccount) 
			{				
				$ccAccount.ExhaustiveCheck = $ExhaustiveCheck;
				return $ccAccount.InvokeFunction($ccAccount.GetAzSKContinuousAssurance);
			}
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

function Remove-AzSKContinuousAssurance 
{
	<#
	.SYNOPSIS
	This command would help in removing resources created by Continuous Assurance installation in your subscription
	.DESCRIPTION

	.PARAMETER SubscriptionId
		Subscription id in which Automation Account exists
	.PARAMETER AutomationAccountRGName
		Name of ResourceGroup where AutomationAccount will be installed.
	.PARAMETER AutomationAccountName
		Name of AutomationAccount. Default value is AzSKContinuousAssurance.
	.PARAMETER DeleteStorageReports
		Switch to specify whether security scan logs/reports stored in storage account also should be removed permanently.
	.PARAMETER TargetSubscriptionIds
		Comma separated values of subscriptionIds which would de-registered from the central scanning mode. Use this switch along with CentralScanMode switch.
	.PARAMETER Force
		Switch to force this cmdlet to remove CA resources
	.PARAMETER CentralScanMode
		This switch is required if AzSK CA is running in central scanning mode. 
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder.
	.LINK
	https://aka.ms/azskossdocs 

	#>
	Param(
		[Parameter(Position = 0, Mandatory = $true, ParameterSetName = "Default", HelpMessage="Subscription id in which Automation Account exists")]
		[Parameter(Position = 0, Mandatory = $true, ParameterSetName = "CentralScanMode", HelpMessage="Subscription id in which Automation Account exists")]
        [string]
		[Alias("sid", "HostSubscriptionId", "hsid")]
		$SubscriptionId,

		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [string]
		[Alias("aargn")]
		$AutomationAccountRGName,

		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [string]
		[Alias("aan")]
		$AutomationAccountName,
		
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
        [string]
		[Alias("tsids")]
		$TargetSubscriptionIds,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]		
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]
        [switch]
		[Alias("dsr")]
		$DeleteStorageReports,

		[Parameter(Mandatory = $true, ParameterSetName = "CentralScanMode", HelpMessage="This switch is required if AzSK CA is running in central scanning mode.")]
		[switch]
		[Alias("csm")]
		$CentralScanMode,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "CentralScanMode")]		
		[switch]
		[Alias("f")]
		$Force,

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
			$ccAccount = [CCAutomation]::new($SubscriptionId, $AutomationAccountRGName, $AutomationAccountName, $PSCmdlet.MyInvocation);

			if ($ccAccount) 
			{
				if($PSCmdlet.ParameterSetName -eq "CentralScanMode")
				{
					$ccAccount.IsCentralScanModeOn = $true;
					$ccAccount.TargetSubscriptionIds = $TargetSubscriptionIds;
				}
				
				return $ccAccount.InvokeFunction($ccAccount.RemoveAzSKContinuousAssurance,@($DeleteStorageReports, $Force));
			}
			
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

function Set-AzSKAlertMonitoring
{
	<#
	.SYNOPSIS
	This command would help in enabling real time alerts monitoring in your subscription
	.DESCRIPTION

	.PARAMETER SubscriptionId
		Subscription id in which Automation Account exists
	.PARAMETER AutomationAccountRGName
		Name of ResourceGroup where AutomationAccount will be installed.
	.PARAMETER AutomationAccountName
		Name of AutomationAccount. Default value is AzSKContinuousAssurance.
	.PARAMETER Force
		Switch to force this cmdlet to publish alert runbook
	.LINK
	https://aka.ms/azskossdocs 

	#>
	Param(
        [string]
		[Parameter(HelpMessage="Subscription id in which Automation Account exists")]
		[Alias("sid","HostSubscriptionId","hsid","s")]
		$SubscriptionId,

		[Parameter(Mandatory = $false)]
        [string]
		[Alias("aargn")]
		$AutomationAccountRGName,

		[Parameter(Mandatory = $false)]
        [string]
		[Alias("aan")]
		$AutomationAccountName,
		
		[switch]
		[Alias("f")]
		$Force	
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
			$ccAccount = [CCAutomation]::new($SubscriptionId, $AutomationAccountRGName, $AutomationAccountName, $PSCmdlet.MyInvocation);
			if ($ccAccount) 
			{
				return $ccAccount.InvokeFunction($ccAccount.SetAzSKAlertMonitoringRunbook,@($Force));
			}
			
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

function Remove-AzSKAlertMonitoring
{
	<#
	.SYNOPSIS
	This command would help in disabling real time alerts monitoring in your subscription
	.DESCRIPTION

	.PARAMETER SubscriptionId
		Subscription id in which Automation Account exists
	.PARAMETER AutomationAccountRGName
		Name of ResourceGroup where AutomationAccount will be installed.
	.PARAMETER AutomationAccountName
		Name of AutomationAccount. Default value is AzSKContinuousAssurance.
	.PARAMETER Force
		Switch to force this cmdlet to remove alert runbook
	.LINK
	https://aka.ms/azskossdocs 

	#>
	Param(
        [string]
		[Parameter(HelpMessage="Subscription id in which Automation Account exists")]
		[Alias("sid","HostSubscriptionId","hsid","s")]
		$SubscriptionId,

		[Parameter(Mandatory = $false)]
        [string]
		[Alias("aargn")]
		$AutomationAccountRGName,

		[Parameter(Mandatory = $false)]
        [string]
		[Alias("aan")]
		$AutomationAccountName,
		
		[switch]
		[Alias("f")]
		$Force	
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
			$ccAccount = [CCAutomation]::new($SubscriptionId, $AutomationAccountRGName, $AutomationAccountName, $PSCmdlet.MyInvocation);
			if ($ccAccount) 
			{			
				return $ccAccount.InvokeFunction($ccAccount.RemoveAzSKAlertMonitoringWebhook,@($Force));
			}
			
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

