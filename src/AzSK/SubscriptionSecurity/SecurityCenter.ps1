Set-StrictMode -Version Latest

function Set-AzSKAzureSecurityCenterPolicies 
{
	<#
	.SYNOPSIS
	This command would help in setting up the Security Center policies for a Subscription

	.DESCRIPTION
	This command would help in setting up the Security Center policies for a Subscription

	.PARAMETER SubscriptionId
		Subscription id for which the security evaluation has to be performed.
	.PARAMETER SecurityContactEmails
			Provide a security contact email address or addresses separated by a comma. Recommended a mail enabled Security Group with receiving of external emails option turned ON.
	.PARAMETER DoNotOpenOutputFolder
			Switch to specify whether to open output folder containing all security evaluation report or not.
	.PARAMETER SecurityPhoneNumber
			Provide a security contact international information phone number including the country code (for example, +1-425-1234567)
	.PARAMETER EnableOptionalPolicies
			Switch to specify whether to set the optional ASC policies.
	


	.LINK
	https://aka.ms/azskossdocs 
	#>

	[OutputType([String])]
	Param
	(
		[string]
        [Parameter(Mandatory = $true, HelpMessage = "Subscription id for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("sid", "HostSubscriptionId", "hsid","s")]
		$SubscriptionId,

		[string]
        [Parameter(Mandatory = $false, HelpMessage = "Provide a security contact email address or addresses separated by a comma. Recommended a mail enabled Security Group with receiving of external emails option turned ON.")]
		[Alias("scemail")]
		$SecurityContactEmails,

		[string]
        [Parameter(Mandatory = $false, HelpMessage = "Provide a security contact international information phone number including the country code (for example, +1-425-1234567)")]
		[Alias("scphone")]
		$SecurityPhoneNumber,

		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder containing all security evaluation report or not.")]
		[Alias("dnof")]
		$DoNotOpenOutputFolder,

		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to set the optional ASC policies.")]
		[Alias("eop","OptionalPolicies")]
		$EnableOptionalPolicies,

        [switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to set Standard Prcing tier for ASC.")]
		[Alias("sats")]
		$SetASCTierToStandard
    )

	Begin
	{
		[CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
		[AzListenerHelper]::RegisterListeners();
	}

	Process
	{
		try 
		{
			$secCenter = [SecurityCenterStatus]::new($SubscriptionId, $PSCmdlet.MyInvocation);
			if ($secCenter) 
			{
				$setOptionalPolicy = $false;

				if ($EnableOptionalPolicies){
					$setOptionalPolicy = $true;
				} 

				$updateSecurityContacts = $false;
				if(-not [string]::IsNullOrWhiteSpace($SecurityPhoneNumber) -or -not [string]::IsNullOrWhiteSpace($SecurityContactEmails))
				{
					$secCenter.SecurityContactEmails = $SecurityContactEmails;
					$secCenter.SecurityPhoneNumber = $SecurityPhoneNumber;
					$updateSecurityContacts =$true;
					
				}
				
				
				
				return $secCenter.SetPolicies($updateSecurityContacts,$setOptionalPolicy,$SetASCTierToStandard);
			}
		}
		catch 
		{
			[EventBase]::PublishGenericException($_);
		}  
	}

	End
	{
		[AzListenerHelper]::UnregisterListeners();
	}
}
