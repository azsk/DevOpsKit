Set-StrictMode -Version Latest
function Set-AzSKSubscriptionSecurity 
{
	<#
	.SYNOPSIS
	This command would help in setting up the all the critical subscription security packages

	.DESCRIPTION
	This command would help in setting up the all the critical subscription security packages
	
	.PARAMETER SubscriptionId
		Subscription id for which subscription security configuration has to be set.
	.PARAMETER Tags
			Provide tag names for processing specific policies. Comma separated values are supported.
	.PARAMETER DoNotOpenOutputFolder
			Switch to specify whether to open output folder containing all security evaluation report or not.
	.PARAMETER Force
			Switch to apply subscription security configurations forcefully regardless of latest updates already present on subscription.
	.PARAMETER SecurityContactEmails
			Provide a security contact email address or addresses separated by a comma. Recommended a mail enabled Security Group with receiving of external emails option turned ON.
	.PARAMETER SecurityPhoneNumber
	        Provide a security contact international information phone number including the country code (for example, +1-425-1234567)
	.PARAMETER TargetResourceGroup
			Provide the ResourceGroup on which the AlertPackage has to be configured
	.PARAMETER AlertResourceGroupLocation
	        Provide the location for alert ResourceGroup 
	
	.LINK
	https://aka.ms/azskossdocs 
	#>
	Param(

		[string]
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Subscription id for which subscription security configuration has to be set.")]
		[ValidateNotNullOrEmpty()]
		[Alias("sid", "HostSubscriptionId", "hsid","s")]
		$SubscriptionId,
		
		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Provide tag names for processing specific policies. Comma separated values are supported.")]
		$Tags,

		[string]
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Provide a security contact email address or addresses separated by a comma. Recommended a mail enabled Security Group with receiving of external emails option turned ON.")]
		[Alias("eml")]
		$SecurityContactEmails,

		[string]
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Provide a security contact international information phone number including the country code (for example, +1-425-1234567)")]
		[Alias("pn")]
		$SecurityPhoneNumber,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Provide the ResourceGroup on which the AlertPackage has to be configured")]
		[Alias("trg")]
		$TargetResourceGroup,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Provide the location for alert ResourceGroup")]
		[Alias("argl")]
		$AlertResourceGroupLocation = "East US",
		
		[switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to apply subscription security configurations forcefully regardless of latest updates already present on subscription.")]
		[Alias("f")]
		$Force,

		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder containing all security evaluation report or not.")]
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
			# Adding all mandatory tags 
			$modifiedTags = [string]::Join(",", [ConfigurationManager]::GetAzSKConfigData().SubscriptionMandatoryTags);
			if(-not [string]::IsNullOrWhiteSpace($Tags))
			{
				$modifiedTags = $modifiedTags + "," +$Tags;
			}

			$subSec = [SubscriptionSecurity]::new($SubscriptionId, $PSCmdlet.MyInvocation, $modifiedTags);
			if ($subSec) 
			{
				return $subSec.InvokeFunction($subSec.SetSubscriptionSecurity, @($SecurityContactEmails, $SecurityPhoneNumber, $TargetResourceGroup, $AlertResourceGroupLocation));
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

function Remove-AzSKSubscriptionSecurity 
{
	<#
	.SYNOPSIS
	This command would help in cleaning up the AzSK Subscription Security package for a Subscription

	.DESCRIPTION
	This command would help in cleaning up the AzSK Subscription Security package for a Subscription
	
	.PARAMETER SubscriptionId
		Subscription ID of the Azure subscription in which organization policy store will be created.
	.PARAMETER Tags
			Provide tag names for processing specific policies. Comma separated values are supported.
	.PARAMETER DoNotOpenOutputFolder
			Switch to specify whether to open output folder containing all security evaluation report or not.
	.PARAMETER Force
			Switch to apply subscription security configurations forcefully regardless of latest updates already present on subscription.
	.PARAMETER DeleteResourceGroup
			Switch to specify whether to delete resource group containing all alerts or not
	.PARAMETER AlertNames
	        Provide the comma separated values of alert names
	
	.LINK
	https://aka.ms/azskossdocs 
	#>
	Param(

		[string]
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Subscription id for which the subscription security configuration has to be removed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("sid", "HostSubscriptionId", "hsid","s")]
		$SubscriptionId,

		[string] 
		[Parameter(Mandatory = $true, HelpMessage = "Provide tag names for processing specific policies. Comma separated values are supported.")]
		$Tags,

		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to delete resource group containing all alerts or not")]
		[Alias("drg")]
        $DeleteResourceGroup,

		[Parameter(Mandatory = $false, HelpMessage = "Provide the comma separated values of alert names")]
        [string]
		[Alias("aname")]
		$AlertNames,

		[switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to apply subscription security configurations forcefully regardless of latest updates already present on subscription.")]
		[Alias("f")]
		$Force,
		
		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder containing all security evaluation report or not.")]
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

			$subSec = [SubscriptionSecurity]::new($SubscriptionId, $PSCmdlet.MyInvocation, $Tags);
			if ($subSec) 
			{
				return $subSec.InvokeFunction($subSec.RemoveSubscriptionSecurity, @([bool] $DeleteResourceGroup, $AlertNames));
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

function Update-AzSKSubscriptionSecurity 
{
	
	<#
	.SYNOPSIS
	This command would help in updating all the critical AzSK packages which includes subscription security (RBAC, ARM Policies, Alerts, Security center configuration) and  Continuous Assurance (CA) automation runbook.

	.DESCRIPTION
	This command would help in updating all the critical AzSK packages which includes subscription security (RBAC, ARM Policies, Alerts, Security center configuration) and  Continuous Assurance (CA) automation runbook.
	
	.PARAMETER SubscriptionId
		Subscription id for which subscription security configuration has to be updated.
	.PARAMETER Force
		Switch to apply subscription security configuration updates forcefully regardless of latest updates already present on subscription.
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder containing all security evaluation report or not.

	.LINK
	https://aka.ms/azskossdocs 
	#>
	Param(

		[string]
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Subscription id for which subscription security configuration has to be updated.", ParameterSetName = "Default")]
		[ValidateNotNullOrEmpty()]
		[Alias("sid","HostSubscriptionId","hsid","s")]
		$SubscriptionId,

		[switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to apply subscription security configuration updates forcefully regardless of latest updates already present on subscription.", ParameterSetName = "Default")]
		[Alias("f")]
		$Force,
		
		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder containing all security evaluation report or not.", ParameterSetName = "Default")]
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
			$subSec = [SubscriptionSecurity]::new($SubscriptionId, $PSCmdlet.MyInvocation);
			if ($subSec) 
			{
				return $subSec.InvokeFunction($subSec.UpdateSubscriptionSecurity);
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
