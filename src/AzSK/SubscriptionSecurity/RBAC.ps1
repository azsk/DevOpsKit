Set-StrictMode -Version Latest
function Set-AzSKSubscriptionRBAC 
{
	
	<#
	.SYNOPSIS
	This command sets up centrally-required RBAC for a given Subscription

	.DESCRIPTION
	This command sets up centrally-required RBAC for a given Subscription
	
	.PARAMETER SubscriptionId
		Subscription id for which the security evaluation has to be performed.
	.PARAMETER Tags
			Provide tag names for processing specific policies. Comma separated values are supported.
	.PARAMETER Force
			Switch to apply RBAC forcefully regardless of latest RBAC already present on subscription.
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
		[Parameter(Mandatory = $false, HelpMessage = "Switch to apply RBAC forcefully regardless of latest RBAC already present on subscription.")]
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

			$rbac = [RBAC]::new($SubscriptionId, $PSCmdlet.MyInvocation, $modifiedTags);
			if ($rbac) 
			{
				return $rbac.InvokeFunction($rbac.SetRBACAccounts);
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

function Remove-AzSKSubscriptionRBAC 
{
	
	<#

	.SYNOPSIS
	This command clears RBAC set up using the Set-AzSKSubscriptionRBAC command. It always removes any deprecated accounts on the subscription.

	.DESCRIPTION
	This command clears RBAC set up using the Set-AzSKSubscriptionRBAC command. It always removes any deprecated accounts on the subscription. Any required central accounts can be removed only if 'mandatory' tag is specified.
	
	.PARAMETER SubscriptionId
		Subscription ID of the Azure subscription in which organization policy store will be created.
	.PARAMETER Tags
			Provide tag names for processing specific policies. Comma separated values are supported.
	.PARAMETER DoNotOpenOutputFolder
			Switch to specify whether to open output folder containing all security evaluation report or not.
	.PARAMETER Force
			Switch to apply subscription security configurations forcefully regardless of latest updates already present on subscription.

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

			$rbac = [RBAC]::new($SubscriptionId, $PSCmdlet.MyInvocation, $Tags);
			if ($rbac) 
			{
				$rbac.Force = $true
				return $rbac.InvokeFunction($rbac.RemoveRBACAccounts);
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
