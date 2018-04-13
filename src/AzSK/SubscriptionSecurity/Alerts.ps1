Set-StrictMode -Version Latest
function Set-AzSKAlerts 
{
	<#
	.SYNOPSIS
	This command would help in setting up the Alert rules for the all the critical actions across different Azure Resources under a given Subscription

	.DESCRIPTION
	This command can be used to setup alert rules for critical resource actions.

	.PARAMETER SubscriptionId
		Subscription id for which security alerts to be configured.
	.PARAMETER Tags
			Provide tag names for processing specific policies. Comma separated values are supported.
	.PARAMETER DoNotOpenOutputFolder
			Switch to specify whether to open output folder containing log report or not.
	.PARAMETER Force
			Switch to apply alerts configurations forcefully regardless of latest alerts already present on subscription.
	.PARAMETER SecurityContactEmails
			Provide a security contact email address. Recommended a mail enabled Security Group with receiving of external emails option turned ON.
	.PARAMETER SecurityPhoneNumbers
	        Provide a security contact international information phone number (for example, 425-1234567). Note that only the country code '1' is currently supported for SMS.
	.PARAMETER TargetResourceGroup
			Provide the ResourceGroup on which the AlertPackage must be configured
	.PARAMETER AlertResourceGroupLocation
	        Provide the location for alert ResourceGroup
	
	.LINK
	https://aka.ms/azskossdocs 
	#>

	Param(

		[string]
        [Parameter(Mandatory = $true, HelpMessage = "Subscription id for which security alerts to be configured.")]
		[ValidateNotNullOrEmpty()]
		$SubscriptionId,
		
		[string]
        [Parameter(Mandatory = $false, HelpMessage = "Provide a security contact email address. Recommended a mail enabled Security Group with receiving of external emails option turned ON.")]
		$SecurityContactEmails,

		[string]
        [Parameter(Mandatory = $false, HelpMessage = "Provide a security contact international information phone number (for example, 425-1234567). Note that only the country code '1' is currently supported for SMS.")]
		$SecurityPhoneNumbers,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Provide tag names for processing specific policies. Comma separated values are supported.")]
		$Tags,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Provide the ResourceGroup on which the AlertPackage has to be configured")]
		$TargetResourceGroup,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Provide the location for alert ResourceGroup")]
		$AlertResourceGroupLocation = "East US",
		
		[switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to apply alerts configurations forcefully regardless of latest alerts already present on subscription.")]
		$Force,

		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder containing log report or not.")]
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

			$alertObj = [Alerts]::new($SubscriptionId, $PSCmdlet.MyInvocation, $modifiedTags);
			if ($alertObj) 
			{
				return $alertObj.InvokeFunction($alertObj.SetAlerts, @($TargetResourceGroup, $SecurityContactEmails,$SecurityPhoneNumbers, $AlertResourceGroupLocation));				
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

function Remove-AzSKAlerts 
{
	
	<#

	.SYNOPSIS
	This command removes all the alert rules being set up by AzSK.

	.DESCRIPTION
	This command removes all the alert rules being set up by AzSK.

	.PARAMETER SubscriptionId
		Subscription ID of the Azure subscription in which organization policy store will be created.
	.PARAMETER Tags
			Provide tag names for processing specific policies. Comma separated values are supported.
	.PARAMETER AlertNames
			Provide the comma separated values of alert names
	.PARAMETER DeleteActionGroup
			Switch to specify whether to delete action group containing alert security contacts
	.PARAMETER DoNotOpenOutputFolder
			Switch to specify whether to open output folder containing all security evaluation report or not.
	
	.LINK
	https://aka.ms/azskossdocs 
	#>

	Param(

		[string]
        [Parameter(Mandatory = $true, HelpMessage = "Subscription id from which security alert rules to be removed.")]
		[ValidateNotNullOrEmpty()]
		$SubscriptionId,

		[string] 
		[Parameter(Mandatory = $true, ParameterSetName= "Tags", HelpMessage = "Provide tag names for processing specific policies. Comma separated values are supported.")]
		$Tags,

        [Parameter(ParameterSetName= "Alert Names", Mandatory = $true, HelpMessage = "Provide the comma separated values of alert names")]
        [string]
		$AlertNames,

		[switch]
		[Parameter(ParameterSetName= "Tags", Mandatory = $false, HelpMessage = "Switch to specify whether to delete action group containing alert security contacts")]
        $DeleteActionGroup,
		
		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder containing all security evaluation report or not.")]
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
			$alertObj = [Alerts]::new($SubscriptionId, $PSCmdlet.MyInvocation, $Tags);
			if ($alertObj) 
			{
				return $alertObj.InvokeFunction($alertObj.RemoveAlerts, @( $AlertNames, [bool] $DeleteActionGroup));
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
