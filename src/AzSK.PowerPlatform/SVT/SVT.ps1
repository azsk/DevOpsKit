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
		[Parameter(Mandatory=$false, HelpMessage="Switch to indicate if scan should run as environment admin. (Default is user.)")]
		$Admin=$false,

		[switch]
		[Parameter( Mandatory = $false, HelpMessage="Scan all supported artificats present under the environment.")]
		[Alias("saa")]
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
			#TODO-PP: Need to move to post-login stage?
			if ([String]::IsNullOrEmpty($EnvironmentName))
			{
				$EnvironmentName = (Get-PowerAppEnvironment -Default).EnvironmentName #Can also use '~default'
			}
            $Script:AsAdmin = $false
			if ($Admin -eq $true) #Check that user has privilege to scan desired envt as admin
			{
				$adminEnvForUser = @(Get-AdminPowerAppEnvironment)

				$isAdminForThisEnv = ( (@($adminEnvForUser | ? {$_.Environmentname -match $EnvironmentName})).Count -eq 1)

				if ($isAdminForThisEnv)
				{
					$Script:AsAdmin = $Admin 
				}
				else 
				{
					Write-Warning("You do not have admin access to envt: $($EnvironmentName).`nScan will run as regular user.")
				}
			}
			$resolver = [SVTResourceResolver]::new($EnvironmentName, $Script:AsAdmin, $ScanAllArtifacts);
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