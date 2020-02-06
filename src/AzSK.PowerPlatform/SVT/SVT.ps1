Set-StrictMode -Version Latest

function Get-AzSKPowerPlatformSecurityStatus
{
	<#
	.SYNOPSIS
	This command would help in validating the security controls for the Azure resources meeting the specified input criteria.
	.DESCRIPTION
	This command will execute the security controls and will validate their status as 'Success' or 'Failure' based on the security guidance. Refer https://aka.ms/azskossdocs for more information 
	
	.PARAMETER EnvironmentName
		Environment name for which the security evaluation has to be performed.

	.NOTES
	This command helps the application team to verify whether their Azure resources are compliant with the security guidance or not 

	.LINK
	https://aka.ms/azskossdocs 

	#>

	[OutputType([String])]
	Param
	(

		[string]		 
		[Parameter(Position = 0, Mandatory = $false, HelpMessage="EnvironmentName for which the security evaluation has to be performed.")]
		[ValidateNotNullOrEmpty()]
		[Alias("oz")]
		$EnvironmentName,

		[switch]
		[Parameter(HelpMessage="Scan all supported artificats present under the environment.")]
		[Alias("sa")]
		$ScanAllArtifacts
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
			#If envtName is not passed, use default environment.
			if ($EnvironmentName -eq $null)
			{
				$EnvironmentName = '~default'
			}
			$resolver = [SVTResourceResolver]::new($EnvironmentName,$ScanAllArtifacts);
			$secStatus = [ServicesSecurityStatus]::new($EnvironmentName, $PSCmdlet.MyInvocation, $resolver);
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