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
		File Names to exclude from scan

    .PARAMETER SkipControlsListFile
		Path to file containing list of controls to skip

	.LINK
	https://aka.ms/azskossdocs 

	#>
	Param(
        [Parameter(Mandatory = $true, HelpMessage = "Path to ARM Template file or folder")]
        [string]        
        $ARMTemplatePath,

		[Parameter(Mandatory = $false, HelpMessage = "Gets the ARM Temaplates in the specified locations and in all child folders of the locations")]
        [switch]        
        $Recurse,

		[Parameter(Mandatory = $true, HelpMessage = "To use Preview feature")]
        [switch]        
        $Preview,

		[switch]
        [Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder containing all security evaluation report or not")]
		$DoNotOpenOutputFolder,

		[Parameter(Mandatory = $false, HelpMessage = "File Names to exclude from scan")]
        [string]        
        $ExcludeFiles,

		[Parameter(Mandatory = $false, HelpMessage = "Path to file containing list of controls to skip")]
        [string]        
        $SkipControlsListFile
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
				return $armStatus.EvaluateStatus($ARMTemplatePath, $Recurse,$SkipControlsListFile,$ExcludeFiles);				
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

