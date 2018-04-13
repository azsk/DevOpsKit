# version: 0.2.6

Param(
    [string] $OnlinePolicyStoreUrl = "#PolicyUrl#" ,
	[string] $RepoUrl = "https://www.powershellgallery.com",
	[string] $RepoName = "PSGallery",
    [string] $DocumentationUrl = "http://aka.ms/AzSKOSSDocs",
    [string] $ControlDetailsUrl = "http://aka.ms/AzSKOSSTCP",
    [string] $FAQUrl = "",
    [string] $SupportUrl = "",
	[string] $AutoUpdateCommand = "#AutoUpdateCommand#",
	[string] $AzSKConfigURL = "#AzSKConfigURL#",
    [Parameter(Mandatory = $False)]
	[switch] $UpdateToLatestVersion
)

[string] $OldModuleName = "#OldModuleName#"
[string] $OldAzSDKConfigURL = ""
[string] $ModuleName = "#ModuleName#"
[string] $OrgName = "#OrgName#"
[string] $SupportEmail = "azsksupext@microsoft.com"
[string] $PrerequsitePassed = "Prerequisite Passed";
[string] $PrerequsiteFailed = "Prerequisite Failed";
[string] $Version;

function WritePrerequsiteMessage([String] $Status, [string] $Message){
    switch ($Status) {
        Passed { 
            Write-Host "$($PrerequsitePassed): $Message" -ForegroundColor Green
        }
        Failed {
            Write-Host "$($PrerequsiteFailed): $Message" -ForegroundColor Red
        }
        Default {
        }
    }
}

function CheckPSVersion {
    $prerequsite = "PowerShell version needs to be 5.0 or above."
    if($PSVersionTable.PSVersion.Major -lt 5){
        WritePrerequsiteMessage Failed "$prerequsite Please update PowerShell version to 5.0. For more details contact us at $SupportEmail" 
        break
    }
    WritePrerequsiteMessage Passed $prerequsite
}

function CheckNugetPackageProvider {
    $minimumRequiredVersion = "2.8.5.208"
    $prerequsite = "PowerShell Nuget PackageProvider version needs to be $minimumRequiredVersion or above."
    $nugetProvider = Get-PackageProvider -Name "Nuget" -ForceBootstrap -ErrorAction SilentlyContinue
    if($null -eq $nugetProvider -or $nugetProvider.Version -lt $minimumRequiredVersion){
        WritePrerequsiteMessage Failed $prerequsite
        try {
            Write-Host "Installing Nuget PackageProvider..." -ForegroundColor Yellow
            Install-PackageProvider "NuGet" -MinimumVersion $minimumRequiredVersion -Force -Scope CurrentUser -ErrorAction Stop
            WritePrerequsiteMessage Passed $prerequsite
        }
        catch {
            Write-Host "Failed to install Nuget PackageProvider. Error:" $_ -ForegroundColor Red
            break
        }
    }else{
        WritePrerequsiteMessage Passed $prerequsite
    }
}

function BootstrapRepo {
    $repository = Get-PSRepository -Name $RepoName -ErrorAction SilentlyContinue
	
    #Remove old repository names and server url different repo name
    if($repository)
    {
        Write-Host "Found $ModuleName old repository. `nUnregistering $ModuleName old repository..." -ForegroundColor Yellow
        Unregister-PSRepository -Name $RepoName
        Write-Host "Completed $ModuleName old repository unregistration." -ForegroundColor Green
    } 
}

function CheckIfMultipleModulesLoaded
{
   #check if old module is loaded in same session
	$oldModule = Get-Module|Where-Object {$_.Name -like "$OldModuleName*"} | Select-Object -First 1
	if($oldModule)
	{	 
		$warningMsg = "Found older module ($OldModuleName) loaded in the PS session.`r`n"+
			"Stopping installation."
        $recommendationMsg = "Recommendation: Please start a fresh PS session and try again to avoid getting into this situation."
		Write-Host $warningMsg -ForegroundColor Red
		Write-Host $recommendationMsg -ForegroundColor Yellow
        
		#stop execution
        break
	}
}
function BootstrapSetup ($moduleName, $versionConfigUrl)
{
    Write-Host "Checking if a previous version of $moduleName is present on your machine..." -ForegroundColor Yellow
    $setupModule = Get-Module -Name $moduleName -ListAvailable
	$setupLatestModule = (Find-Module -Name $moduleName -Repository $RepoName)
	if((-not [string]::IsNullOrWhiteSpace($versionConfigUrl)) -and (-not $UpdateToLatestVersion))
    {
        $uri = $global:ExecutionContext.InvokeCommand.ExpandString($versionConfigUrl)
        [System.Uri] $validatedUri = $null;
        if([System.Uri]::TryCreate($uri, [System.UriKind]::Absolute, [ref] $validatedUri))
        {
            try
            {
                $serverFileContent = Invoke-RestMethod `
                                            -Method GET `
                                            -Uri $validatedUri `
                                            -UseBasicParsing

			    if($null -ne $serverFileContent)
			    {
				    if(-not [string]::IsNullOrWhiteSpace($serverFileContent.CurrentVersionForOrg))
				    {
					    $setupLatestModule = (Find-Module -Name $moduleName -Repository $RepoName -RequiredVersion $serverFileContent.CurrentVersionForOrg)
				    }
			    }
            }
            catch
            {
                # If unable to fetch server config file or module version property then continue and download latest version module.
            }
        }
    }

	$Global:Version = $setupLatestModule.Version
    
	#If module count is greater than 1 then filter module with current active directory
	if($null -ne $setupModule -and ($setupModule|Measure-Object).Count -gt 1  )
	{	 
         #$CurrentModulePath= (Get-Item -Path ($setupModule | Select-Object -First 1).ModuleBase).Parent.Parent.FullName
         #$setupModule = $setupModule |  Where-Object { $_.ModuleBase.Contains($CurrentModulePath)}
	 $setupModule = $setupModule | Where-Object { $_.ModuleBase -like '$($env:USERPROFILE)*'} | Sort-Object -Property Version -Descending | Select-Object -First 1
	}

	if($null -ne $setupModule -and $null -ne $setupLatestModule -and $setupModule.Version -eq $setupLatestModule.Version)
	{
	  Write-Host "Latest version of $moduleName already exists." -ForegroundColor Green
	  return
	}
	elseif($null -ne $setupModule)
    {
        #Module is present
		Write-Host "Found $moduleName version $($setupModule.Version) . Uninstalling it..." -ForegroundColor Yellow
        try 
        {
            $loadedModule = Get-Module -Name $moduleName
            if($loadedModule)
            {
                Write-Host "$moduleName version $($loadedModule.Version) is currently loaded in this PS session.`nPlease close this session (and any other active PS sessions) and rerun the setup command in a fresh session."  -ForegroundColor Red
                break
            }
            
            Uninstall-Module -Name $moduleName -AllVersions -Force -ErrorAction Stop			
        }
        catch 
        {
            Write-Host "Failed to remove previous version of $moduleName. Error:" $_ -ForegroundColor Red
            $moduleLocation = $setupModule.ModuleBase.Substring(0, $setupModule.ModuleBase.LastIndexOf($setupModule.Name))
            Write-Host "Tip: Close all the instances of PowerShell (includes ISE, Visual Studio (PMC), VS Code (Terminal), etc). Remove the folder '$setupModule' at '$moduleLocation' manually." -ForegroundColor Red
            break
        }
		Write-Host "Completed uninstallation." -ForegroundColor Green
    }
	if($null -eq $setupModule)
	{
		Write-Host "No previous version found." -ForegroundColor Green
	}
		
		try
		{ 
			Write-Host "Installing $moduleName version $($setupLatestModule.Version) . This may take a few minutes..." -ForegroundColor Yellow
			if((GET-Command Install-Module).Parameters.ContainsKey("AllowClobber"))
			{
				Install-Module $moduleName -Scope CurrentUser -Repository $RepoName -RequiredVersion $($setupLatestModule.Version) -AllowClobber -ErrorAction Stop 	
			}
			else
			{
				Install-Module $moduleName -Scope CurrentUser -Repository $RepoName -RequiredVersion $($setupLatestModule.Version) -Force -ErrorAction Stop 	
			}        
			Write-Host "Completed installation." -ForegroundColor Green
		}
		catch
		{
			Write-Host "Failed to install $moduleName. Error:" $_ -ForegroundColor Red
        
			break
		}
}


function BootstrapOrgPolicy{
    try
    {    	
        Write-Host "`nConfiguring $OrgName policy... " -ForegroundColor Yellow
        #Check for execution policy settings
        $executionPolicy = Get-ExecutionPolicy -Scope CurrentUser
        if(($executionPolicy -eq [Microsoft.PowerShell.ExecutionPolicy]::Restricted) -or ($executionPolicy -eq [Microsoft.PowerShell.ExecutionPolicy]::Undefined) -or ($executionPolicy -eq [Microsoft.PowerShell.ExecutionPolicy]::AllSigned))
        {
            Write-Host "Currently PowerShell execution policy is set to '$executionPolicy' mode. `n$ModuleName will need policy to be set to 'RemoteSigned'. `nSelect Y to change policy for current user [Y/N]: " -ForegroundColor Yellow -NoNewline
            $executionPolicyAns = Read-Host 

            if($executionPolicyAns.Trim().ToLower() -eq "y")
            {
                Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            }
            else {
                Write-Host "Not able to configure $OrgName policy. Please try re-running setup in new PS session or get support on $SupportUrl" -ForegroundColor Red
                break 
            }
        }
        
		Import-Module $ModuleName -RequiredVersion $Version -Force     
	    Set-AzSKPolicySettings -OnlinePolicyStoreUrl $OnlinePolicyStoreUrl -ErrorAction Stop
	    Write-Host "Completed $OrgName policy configuration." -ForegroundColor Green
	}
    catch
    {
        Write-Host "Failed to configure $OrgName policy. Error:" $_ -ForegroundColor Red
		if(-not [string]::IsNullOrWhiteSpace($FAQUrl))
		{
			Write-Host "Tip: Refer to the troubleshooting tips at: $DocumentationUrl, $FAQUrl" -ForegroundColor Red
		}
        break

    }
    

}

function RemoveOlderModule 
{
    Write-Host "Checking if a previous version of $OldModuleName is present on your machine..." -ForegroundColor Yellow
	$setupModules = @()
    $setupModules += Get-Module -Name $OldModuleName -ListAvailable

    #If module count is greater than 0 then filter module with current active directory
	if(($setupModules | Measure-Object).Count -gt 0  )
	{
		Write-Host "Found older versions of $OldModuleName. Uninstalling it..." -ForegroundColor Yellow
		try 
		{
			$loadedModule = Get-Module -Name $OldModuleName
			if($loadedModule)
			{
				Write-Host "$OldModuleName version $($loadedModule.Version) is currently loaded in this PS session.`nPlease close this session (and any other active PS sessions) and rerun the setup command in a fresh session."  -ForegroundColor Red
				break
			}
			Uninstall-Module -Name $OldModuleName -AllVersions -Force -ErrorAction Stop			
		}
		catch 
		{
			Write-Host "Failed to remove previous versions of $OldModuleName. Error:" $_ -ForegroundColor Red
			Write-Host "Tip: Close all the instances of PowerShell (includes ISE, Visual Studio (PMC), VS Code (Terminal), etc)."
			$setupModules | ForEach-Object{
				$setupModule = $_
				$moduleLocation = $setupModule.ModuleBase.Substring(0, $setupModule.ModuleBase.LastIndexOf($setupModule.Name))
				Write-Host "Remove the folder '$setupModule' at '$moduleLocation' manually."
			}
			break
		}
		Write-Host "Completed uninstallation." -ForegroundColor Green
	}
	elseif($setupModules -eq $null)
	{
        Write-Host "No previous version found." -ForegroundColor Green
	}
}

function BootstrapInstaller {
    #BootstrapRepo
    #BootstrapSetup -moduleName $OldModuleName -versionConfigUrl $OldAzSDKConfigURL -uninstallAll $true
	RemoveOlderModule
    BootstrapSetup -moduleName $ModuleName -versionConfigUrl $AzSKConfigURL
    BootstrapOrgPolicy

    Write-Host "`nThe Secure DevOps Kit for Azure is now ready for your use!" -ForegroundColor Green
    Write-Host "`nImportant links:" -ForegroundColor Green;
    Write-Host "`tDocumentation: " -NoNewline -ForegroundColor Green; Write-Host $DocumentationUrl -ForegroundColor Cyan 
    Write-Host "`tControl details: " -NoNewline -ForegroundColor Green; Write-Host $ControlDetailsUrl -ForegroundColor Cyan
	if(-not [string]::IsNullOrWhiteSpace($FAQUrl))
	{
		Write-Host "`tFAQs: " -NoNewline -ForegroundColor Green; Write-Host $FAQUrl -ForegroundColor Cyan 
	}

	if(-not [string]::IsNullOrWhiteSpace($SupportUrl))
	{
		Write-Host "`tSupport: " -NoNewline -ForegroundColor Green; Write-Host $SupportUrl -ForegroundColor Cyan
	}

}

function CheckPrerequsites {
    Write-Host "Checking Prerequisites... " -ForegroundColor Yellow
    CheckPSVersion
    CheckNugetPackageProvider
    CheckIfMultipleModulesLoaded
}

function Init {
    CheckPrerequsites
    BootstrapInstaller    
}

Init
