Set-StrictMode -Version Latest
function Set-AzSKARMPolicies 
{
	<#

	.SYNOPSIS
	This command would help in setting up the AzSK ARM Policies for a Subscription

	.DESCRIPTION
	This command would help in setting up the AzSK ARM Policies for a Subscription

	.PARAMETER SubscriptionId
		Subscription id for which the security evaluation has to be performed.
	.PARAMETER Tags
			Provide tag names for processing specific policies. Comma separated values are supported.
	.PARAMETER DoNotOpenOutputFolder
			Switch to specify whether to open output folder containing all security evaluation report or not.
	.PARAMETER Force
			Switch to apply ARM policies forcefully regardless of latest policies already present on subscription.
	
	.PARAMETER SubscriptionId
		Subscription id for which the security evaluation has to be performed.
	.PARAMETER Tag
		Provide tag names for processing specific policies. Comma separated values are supported.
	.PARAMETER UpdateInitiative
		Provide -UpdateInitiative switch to update initiative with latest policies.
	.PARAMETER Force
		Switch to apply subscription security configuration forcefully regardless of latest updates already present on subscription.
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder containing all security evaluation report or not.

	.LINK
	https://aka.ms/azskossdocs 
	#>
	Param(

		[string]
        [Parameter(Mandatory = $true, HelpMessage = "Subscription id for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("sid", "HostSubscriptionId", "hsid","s")]
		$SubscriptionId,

		[string] 
		[Parameter(Mandatory = $false, HelpMessage = "Provide tag names for processing specific policies. Comma separated values are supported.")]
		$Tags,

		[switch] 
		[Parameter(Mandatory = $false, HelpMessage = "Provide -UpdateInitiative switch to update initiative with latest policies")]
		[Alias("ui")]
		$UpdateInitiative,
		
		[switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to apply ARM policies forcefully regardless of latest policies already present on subscription.")]
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
			$_updateInitiative = $false
			if($UpdateInitiative)
			{
				$_updateInitiative = $true
			}
			

			$armPolicy = [ARMPolicy]::new($SubscriptionId, $PSCmdlet.MyInvocation, $modifiedTags, $_updateInitiative);
			if ($armPolicy) 
			{
				return $armPolicy.InvokeFunction($armPolicy.SetARMPolicies);
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

function Remove-AzSKARMPolicies 
{
	<#

	.SYNOPSIS
	This command would remove ARM policies which was set up by AzSK

	.DESCRIPTION
	This command would remove ARM policies which was set up by AzSK

	.PARAMETER SubscriptionId
		Subscription ID of the Azure subscription in which organization policy store will be created.
	.PARAMETER Tags
			Provide tag names for processing specific policies. Comma separated values are supported.
	.PARAMETER DoNotOpenOutputFolder
			Switch to specify whether to open output folder containing all security evaluation report or not.
	
	.PARAMETER SubscriptionId
		Subscription id for which the subscription security configuration has to be removed.
	.PARAMETER Tag
		Provide tag names for processing specific policies. Comma separated values are supported.
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder containing all security evaluation report or not.

	.LINK
	https://aka.ms/azskossdocs 
	#>
	Param(

		[string]
        [Parameter(Mandatory = $true, HelpMessage = "Subscription id for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("sid", "HostSubscriptionId", "hsid","s")]
		$SubscriptionId,

		[string] 
		[Parameter(Mandatory = $true, HelpMessage = "Provide tag names for processing specific policies. Comma separated values are supported.")]
		$Tags,
		
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

			$armPolicy = [ARMPolicy]::new($SubscriptionId, $PSCmdlet.MyInvocation, $Tags, $false);
			if ($armPolicy) 
			{
				return $armPolicy.InvokeFunction($armPolicy.RemoveARMPolicies);
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
