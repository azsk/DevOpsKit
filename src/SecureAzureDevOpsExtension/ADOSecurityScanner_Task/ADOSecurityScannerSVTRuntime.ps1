#Prod: 0f42e73b-1b51-41b9-8bd2-c1a864393316
#Test: 7ac3c631-6f16-453a-b8d7-5ec6e754e3ab
#Get VSTS input parameters values
$OrgName = Get-VstsInput -Name OrgName
$ProjectNames = Get-VstsInput -Name ProjectNames

$BuildNames = Get-VstsInput -Name BuildNames
$ReleaseNames = Get-VstsInput -Name ReleaseNames
$ServiceConnectionNames = Get-VstsInput -Name ServiceConnectionNames
$AgentPoolNames = Get-VstsInput -Name AgentPoolNames
$BaseLine = Get-VstsInput -Name isBaseline

$EnableLAWSLoggingVal = Get-VstsInput -Name EnableOMSLogging
$LAWSSharedKeyVal = Get-VstsTaskVariable -Name "LAWSSharedKey" -ErrorAction SilentlyContinue
$LAWSIdVal = Get-VstsTaskVariable -Name "LAWSId" -ErrorAction SilentlyContinue

$PreviewBaseLine = Get-VstsTaskVariable -Name -UPBC
$Severity = Get-VstsTaskVariable -Name Severity
$MaxObject = Get-VstsTaskVariable -Name -mo
$ResourceTypeName = Get-VstsTaskVariable -Name ResourceTypeName

$varPrjName = Get-VstsTaskVariable -Name system.teamProject;
$varBuildId = Get-VstsTaskVariable -Name system.definitionId;

$extensionName = "ADOSecurityScanner"
$publisherName = "azsdktm"
$AzSKModuleName = Get-VstsTaskVariable -Name ModuleName
$AzSKExtendedCommand = Get-VstsTaskVariable -Name "ExtendedCommand"
$AzSKPartialCommit = Get-VstsTaskVariable -Name "UsePartialCommit"
$JobId = Get-VstsTaskVariable -Name System.JobId
$CollectionUri = Get-VstsTaskVariable -Name System.CollectionUri

if(!$ResourceTypeName)
{
$ResourceTypeName = Get-VstsInput -Name ScanFilter
if($ResourceTypeName -eq "BuildReleaseSvcConnAgentPoolUser")
{
	$ResourceTypeName = "Build_Release_SvcConn_AgentPool_User"
}
}

#Log on to Azure with the CICD SPN
$serviceName = Get-VstsInput -Name AzureDevOpsConnectionName
$Endpoint = Get-VstsEndpoint -Name $serviceName -Require

$plaintoken =  $Endpoint.Auth.Parameters.apitoken
$token =  ConvertTo-SecureString $plaintoken -AsPlainText -Force

#Install NuGet Provider with minimum version 
Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Scope CurrentUser -Force | Out-Null

$ModuleName = "AzSK.AzureDevOps"
#Check if Beta/Preview version is enabled
if(-not [string]::IsNullOrWhiteSpace($AzSKModuleName))
{
	switch($AzSKModuleName.ToLower())
	{
		"azskpreview" {
			$ModuleName = "AzSKPreview.AzureDevOps";
			break;
		} 
		"azsk" {
			$ModuleName = "AzSK.AzureDevOps";
			break;
		}
		"azskstaging" {
			$ModuleName = "AzSKStaging.AzureDevOps"
			$isCanaryMode = $true;			
			break;
		}
	}
}

if($isCanaryMode)
{
	$NewRepoName = "AzSKStaging"
	$RepoUrl = "https://www.poshtestgallery.com/"
	$installationPolicy = "Trusted"

	Write-Host "Configuring $ModuleName repository..." -ForegroundColor Yellow
	$repository = @();
	$repository += Get-PSRepository -Name $NewRepoName -ErrorAction SilentlyContinue
	#Remove old repository names and server url different repo name
	if(($repository | Measure-Object).Count -gt 0)
	{
		$repository | ForEach-Object {
			Unregister-PSRepository -Name $_.Name
		}
	}
	$repositoryWithUrl = Get-PSRepository | Where-Object { $_.SourceLocation -eq $RepoUrl } 
	if($repositoryWithUrl)
	{
		Unregister-PSRepository -Name $repositoryWithUrl.Name
	}
	$RepoName = $NewRepoName
	Register-PSRepository -Name $RepoName -SourceLocation $RepoUrl -InstallationPolicy $installationPolicy
	Write-Host "Completed $ModuleName repository configuration." -ForegroundColor Green
}

if((GET-Command Install-Module).Parameters.ContainsKey("AllowClobber"))
{
	$AllowClobber = "-AllowClobber"
}

# Force parameter is required to skip user input during installation
$Force = "-Force"
#TODO:
#Write-Host "Configuring $AzSKModuleName " -ForegroundColor Yellow
Write-Host "Installing Module $ModuleName..." -ForegroundColor Yellow
if($isCanaryMode)
{
	$InstallCmd ="Install-Module $ModuleName -Scope CurrentUser -Repository $RepoName  $AllowClobber $Force | Out-Null"
}
else
{
	$InstallCmd ="Install-Module $ModuleName -Scope CurrentUser -Repository PSGallery  $AllowClobber $Force | Out-Null"
}

#Load the azsk module into memory
Invoke-Expression $InstallCmd 
Invoke-Expression "Import-Module $ModuleName" 

try {

	Set-AzSKPrivacyNoticeResponse -AcceptPrivacyNotice "yes"
	Set-AzSKMonitoringSettings -Source "CICD"


	If ($OrgName -match "https://")
	{ 
		$Uri = $OrgName.Substring(0,$OrgName.Length-1)
		$OrgName = $Uri -replace '.*\/'
	}
	$ReportFolderPath;

    if(-not [string]::IsNullOrWhiteSpace($EnableLAWSLoggingVal) -and $EnableLAWSLoggingVal -eq $true)
    {
		if([string]::IsNullOrWhiteSpace($LAWSIdVal))
		{
			$LAWSIdVal = Get-VstsTaskVariable -Name "OMSWorkspaceId"
			$LAWSIdVal = $LAWSIdVal.Trim();
		}
		if([string]::IsNullOrWhiteSpace($LAWSSharedKeyVal))
		{
			$LAWSSharedKeyVal = Get-VstsTaskVariable -Name "OMSSharedKey"
			$LAWSSharedKeyVal = $LAWSSharedKeyVal.Trim();
		}

        if(-not [string]::IsNullOrWhiteSpace($LAWSIdVal) -and -not [string]::IsNullOrWhiteSpace($LAWSSharedKeyVal))
        {
            Write-Host "Setting up Log Analytics workspace configuration..." -ForegroundColor Yellow
			Set-AzSKOMSSettings -OMSSharedKey $LAWSSharedKeyVal -OMSWorkspaceID $LAWSIdVal -Source "CICD"
			
			#clear session state
	        Clear-AzSKSessionState
        }
        else {
            Write-Host "Log Analytics workspace configuration is missing. Check variables..." -ForegroundColor Yellow
        }        
    }
    else {
            Write-Host "Log Analytics workspace logging is turned off." -ForegroundColor Yellow
    }    


	if($BaseLine -eq $true)
	{
		if($BuildNames)
		{
		    if ($BuildNames -and $ReleaseNames -and $ServiceConnectionNames -and $AgentPoolNames) {
		    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -BuildNames $BuildNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -AgentPoolNames $AgentPoolNames -ubc -ResourceTypeName $ResourceTypeName"	
		    }
		    elseif ($BuildNames -and $ReleaseNames -and $ServiceConnectionNames) {
		    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -BuildNames $BuildNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -ubc -ResourceTypeName $ResourceTypeName"	
		    }
		    elseif ($BuildNames -and $ReleaseNames) {
		    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -BuildNames $BuildNames -ReleaseNames $ReleaseNames -ubc -ResourceTypeName $ResourceTypeName"	
		    }
		    else{
		    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -BuildNames $BuildNames -ubc -ResourceTypeName $ResourceTypeName"
		    }
	    }
	    elseif($ReleaseNames)
	  	{
	  	    if ($ReleaseNames -and $ServiceConnectionNames -and $AgentPoolNames) {
	  	    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -AgentPoolNames $AgentPoolNames -ubc -ResourceTypeName $ResourceTypeName"
	  	    }
	  	    elseif ($ReleaseNames -and $ServiceConnectionNames) {
	  	    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -ubc -ResourceTypeName $ResourceTypeName"
	  	    }
	  	    else{
	  	    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -ReleaseNames $ReleaseNames -ubc -ResourceTypeName $ResourceTypeName"
	  	    }
	    }
	    elseif($ServiceConnectionNames)
	  	{
	  	    if ($ServiceConnectionNames -and $AgentPoolNames) {
	  	    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -ServiceConnectionNames $ServiceConnectionNames -AgentPoolNames $AgentPoolNames -ubc -ResourceTypeName $ResourceTypeName"
	  	    }
	  	    else{
	  	        $scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -ServiceConnectionNames $ServiceConnectionNames -ubc -ResourceTypeName $ResourceTypeName"
	  	    }
	    }
	    else
	    {
	  	    $scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -ubc -ResourceTypeName $ResourceTypeName"
	    }
	}
	else
	{
		if($BuildNames)
		{
		    if ($BuildNames -and $ReleaseNames -and $ServiceConnectionNames -and $AgentPoolNames) {
		    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -BuildNames $BuildNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -AgentPoolNames $AgentPoolNames -ResourceTypeName $ResourceTypeName"
		    }
		    elseif ($BuildNames -and $ReleaseNames -and $ServiceConnectionNames) {
		    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -BuildNames $BuildNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -ResourceTypeName $ResourceTypeName"
		    }
		    elseif ($BuildNames -and $ReleaseNames) {
		    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -BuildNames $BuildNames -ReleaseNames $ReleaseNames -ResourceTypeName $ResourceTypeName"
		    }
		    else{
		    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -BuildNames $BuildNames -ResourceTypeName $ResourceTypeName"
		    }
	    }
	    elseif($ReleaseNames)
	  	{
	  	    if ($ReleaseNames -and $ServiceConnectionNames -and $AgentPoolNames) {
	  	    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -AgentPoolNames $AgentPoolNames -ResourceTypeName $ResourceTypeName"
	  	    }
	  	    elseif ($ReleaseNames -and $ServiceConnectionNames) {
	  	    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -ResourceTypeName $ResourceTypeName"
	  	    }
	  	    else{
	  	    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -ReleaseNames $ReleaseNames -ResourceTypeName $ResourceTypeName"
	  	    }
	    }
	    elseif($ServiceConnectionNames)
	  	{
	  	    if ($ServiceConnectionNames -and $AgentPoolNames) {
	  	    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -ServiceConnectionNames $ServiceConnectionNames -AgentPoolNames $AgentPoolNames -ResourceTypeName $ResourceTypeName"
	  	    }
	  	    else{
	  	    	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -ServiceConnectionNames $ServiceConnectionNames -ResourceTypeName $ResourceTypeName"
	  	    }
	    }
	    else
	    {
	  	    $scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken `$token -ProjectNames $ProjectNames -ResourceTypeName $ResourceTypeName"
	    }
	}

	if(-not [string]::IsNullOrEmpty($Severity))
	{
		$scanCommand += "-Severity ""$Severity"" ";
	}

	if ($AzSKPartialCommit -eq $true)
	{
		$scanCommand += " -UPC "
		$CollectionUri = $CollectionUri.Substring(0,$CollectionUri.Length-1)
		$TaskOrg = $CollectionUri -replace '.*\/'
		$partialScanURI =  "https://extmgmt.dev.azure.com/{0}/_apis/extensionmanagement/installedextensions/ArvTestAzSK/ADOSecurityScanner/Data/Scopes/Default/Current/Collections/{1}/Documents/{2}?api-version=5.1-preview.1" -f $TaskOrg, $OrgName,  ("ResourceTrackerFile_" + $JobId)
		$env:PartialScanURI = $partialScanURI
	}
	
	$scanCommand
	$ReportFolderPath= Invoke-Expression $scanCommand
    $ArchiveFileName = "$env:SYSTEM_DEFAULTWORKINGDIRECTORY"+"\AzSKAzureDevOps_"+$(([System.DateTime]::UtcNow).ToString('hhmmss'))+ "Logs.zip"
	

	if(($null -ne $ReportFolderPath) -and (Test-Path $ReportFolderPath))
    {
		Compress-Archive -Path $ReportFolderPath -CompressionLevel Optimal -DestinationPath $ArchiveFileName
		Write-Host "##vso[task.uploadfile]$ArchiveFileName" 
		$SecurityReport = Get-ChildItem -Path $ReportFolderPath -Recurse -Include "SecurityReport*.csv"

		if($SecurityReport)
		{
			$SVTResult = Get-Content $SecurityReport | ConvertFrom-Csv
			Write-Host "Sending scan report to extension storage"
			try {
			    $user = ""
			    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$plaintoken)))
			    $uri = "https://extmgmt.dev.azure.com/$OrgName/_apis/extensionmanagement/installedextensions/$publisherName/$extensionName/Data/Scopes/Default/Current/Collections/MyCollection/Documents?api-version=5.1-preview.1";
				
				$definitionId = "";
				if($env:BUILD_BUILDID)
				{
                   $definitionId = "_BuildId_" + $env:BUILD_BUILDID + "_" 
				}
				else
				{
					$definitionId = "_ReleaseId_" + $env:RELEASE_DEFINITIONID + "_" 
				}
			    $scanResultId = $varPrjName + $definitionId + $(get-date -f dd-MM-yyyy-HH-mm-ss)
				Write-Host "Scan result will be save with id:" + $scanResultId
				$body = @{"id" = "$scanResultId"; "__etag" = -1; "value"= $SVTResult;} | ConvertTo-Json

			    $webRequestResult = Invoke-RestMethod -Uri $uri -Method Put -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $body
			    Write-Host "Completed sending scan report to extension storage"
			}
			catch {
			    Write-Error $_
			    throw
			}
		}
		else
		{
			Write-Host "Security report not found. Check if scan completed successfully"
		}
	}
	else
	{
		Write-Host "##vso[task.logissue type=error;]Could not perform ADO Security SVTs scan. Please check if task configurations are correct." 
	}
}
finally
{
    if(($null -ne $ReportFolderPath) -and (Test-Path $ReportFolderPath))
    {
        Write-Host "Cleaning logs from temp directory..." -ForegroundColor Yellow
        Remove-Item $ReportFolderPath*  -Force -Recurse
    }      
}