Set-StrictMode -Version Latest

function Get-AzSKARMTemplateSecurityStatus
{
	<#
	.SYNOPSIS
	This command would help in evaluating the ARM Templates for security issues
	.DESCRIPTION
	This command would help in evaluating the ARM Templates for security issues
	
	.PARAMETER ARMTemplatePath
		Path to ARM Template file or folder

    .PARAMETER Preview
		To use Preview feature

    .PARAMETER Recurse
		Gets the ARM Temaplates in the specified locations and in all child folders of the locations	

	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder containing all security evaluation report or not

    .PARAMETER ExcludeFiles
		Comma-separated list of JSON files to be excluded from scan

    .PARAMETER SkipControlsFromFile
		Path to file containing list of controls to skip

	.LINK
	https://aka.ms/azskossdocs 

	#>
	Param(
        [Parameter(Mandatory = $true, HelpMessage = "Path to ARM Template file or folder")]
        [string]        
		[Alias("atp")]
        $ARMTemplatePath,

		[Parameter(Mandatory = $false, HelpMessage = "Gets the ARM Temaplates in the specified locations and in all child folders of the locations")]
        [switch]  
		[Alias("rcs")]
        $Recurse,

		[Parameter(Mandatory = $true, HelpMessage = "To use Preview feature")]
        [switch]       
		[Alias("prv")]
        $Preview,

		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder containing all security evaluation report or not")]
		[Alias("dnof")]
		$DoNotOpenOutputFolder,

		[Parameter(Mandatory = $false, HelpMessage = "Comma-separated list of JSON files to be excluded from scan")]
        [string]  
		[Alias("ef")]
        $ExcludeFiles,

		[Parameter(Mandatory = $false, HelpMessage = "Path to file containing list of controls to skip")]
        [string]  
		[Alias("scf")]
        $SkipControlsFromFile
    )

	Begin
	{
	    [AIOrgTelemetryHelper]::PublishARMCheckerEvent("ARMChecker Command Started",@{}, $null)
	}

	Process
	{
		try 
		{
			$armStatus = [ARMCheckerStatus]::new($PSCmdlet.MyInvocation);
			if ($armStatus) 
			{
				return $armStatus.EvaluateStatus($ARMTemplatePath, $Recurse,$SkipControlsFromFile,$ExcludeFiles);				
			}    
		}
		catch 
		{
			$formattedMessage = [Helpers]::ConvertObjectToString($_, $false);		
			Write-Host $formattedMessage -ForegroundColor Red
		    [AIOrgTelemetryHelper]::PublishARMCheckerEvent("ARMChecker Command Error",@{"Exception"=$_}, $null)
		}  
	}
	End
	{
		
	}
}

