Set-StrictMode -Version Latest

function Get-AzSKXSecurityStatus
{
	<#
	.SYNOPSIS
	This command would help in validating the security controls for the Azure resources meeting the specified input criteria.
	.DESCRIPTION
	This command will execute the security controls and will validate their status as 'Success' or 'Failure' based on the security guidance. Refer https://aka.ms/azskossdocs for more information 
	
	.PARAMETER OrganizationName
		Organization name for which the security evaluation has to be performed.

	.NOTES
	This command helps the application team to verify whether their Azure resources are compliant with the security guidance or not 

	.LINK
	https://aka.ms/azskossdocs 

	#>

	[OutputType([String])]
	Param
	(

		[string]		 
		[Parameter(Position = 0, Mandatory = $true, HelpMessage="OrganizationName for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("oz")]
		$SampleResourceName
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
			$resolver = [SVTResourceResolver]::new($SampleResourceName);
			$secStatus = [ServicesSecurityStatus]::new($SampleResourceName, $PSCmdlet.MyInvocation, $resolver);
			if ($secStatus) 
			{		
				return $secStatus.EvaluateControlStatus();
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