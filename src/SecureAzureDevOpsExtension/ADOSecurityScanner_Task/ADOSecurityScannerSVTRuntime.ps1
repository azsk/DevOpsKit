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

$PreviewBaseLine = Get-VstsTaskVariable -Name -UPBC
$Severity = Get-VstsTaskVariable -Name Severity
$MaxObject = Get-VstsTaskVariable -Name -mo

$varPrjName = Get-VstsTaskVariable -Name system.teamProject;
$varBuildId = Get-VstsTaskVariable -Name system.definitionId;

$extensionName = "ADOSecurityScanner"
$publisherName = "ADOScanner"
$AzSKModuleName = Get-VstsTaskVariable -Name ModuleName
$AzSKExtendedCommand = Get-VstsTaskVariable -Name "ExtendedCommand"

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

	$scanCommand = "Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token "

    if(-not [string]::IsNullOrEmpty($ProjectNames))
    {
		$scanCommand += "-ProjectNames ""$ProjectNames"" ";    
    }
    
	if(-not [string]::IsNullOrEmpty($BuildNames))
	{
		$scanCommand += "-BuildNames ""$BuildNames"" ";
	}
	
	if(-not [string]::IsNullOrEmpty($ReleaseNames))
	{
		$scanCommand += "-ReleaseNames ""$ReleaseNames"" ";
	}

	if(-not [string]::IsNullOrEmpty($ServiceConnectionNames))
	{
		$scanCommand += "-ServiceConnectionNames ""$ServiceConnectionNames"" ";
	}

	if(-not [string]::IsNullOrEmpty($AgentPoolNames))
	{
		$scanCommand += "-AgentPoolNames ""$AgentPoolNames"" ";
	}

	if(-not [string]::IsNullOrEmpty($PreviewBaseLine))
	{
		$scanCommand += "-UPBC ";
	}
	if(-not [string]::IsNullOrEmpty($Severity))
	{
		$scanCommand += "-Severity ""$Severity"" ";
	}
	if(-not [string]::IsNullOrEmpty($MaxObject))
	{
		$scanCommand += "-mo ""$MaxObject"" ";
	}
	if($BaseLine)
	{
		$scanCommand += "-UBC ";
	}

	if(-not [string]::IsNullOrWhiteSpace($AzSKExtendedCommand))
	{
		$scanCommand += $AzSKExtendedCommand
	}

	$scanCommand
	
	$ReportFolderPath;

	if($BaseLine -eq $true)
	{
		if($BuildNames)
		{
		    if ($BuildNames -and $ReleaseNames -and $ServiceConnectionNames -and $AgentPoolNames) {
		    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -BuildNames $BuildNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -AgentPoolNames $AgentPoolNames -Severity $Severity -ubc	
		    }
		    elseif ($BuildNames -and $ReleaseNames -and $ServiceConnectionNames) {
		    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -BuildNames $BuildNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -Severity $Severity -ubc	
		    }
		    elseif ($BuildNames -and $ReleaseNames) {
		    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -BuildNames $BuildNames -ReleaseNames $ReleaseNames -Severity $Severity -ubc	
		    }
		    else{
		    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -BuildNames $BuildNames -Severity $Severity -ubc	
		    }
	    }
	    elseif($ReleaseNames)
	  	{
	  	    if ($ReleaseNames -and $ServiceConnectionNames -and $AgentPoolNames) {
	  	    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -AgentPoolNames $AgentPoolNames -Severity $Severity -ubc	
	  	    }
	  	    elseif ($ReleaseNames -and $ServiceConnectionNames) {
	  	    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -Severity $Severity -ubc	
	  	    }
	  	    else{
	  	    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -ReleaseNames $ReleaseNames -Severity $Severity -ubc	
	  	    }
	    }
	    elseif($ServiceConnectionNames)
	  	{
	  	    if ($ServiceConnectionNames -and $AgentPoolNames) {
	  	    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -ServiceConnectionNames $ServiceConnectionNames -AgentPoolNames $AgentPoolNames -Severity $Severity -ubc	
	  	    }
	  	    else
	  	    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -ServiceConnectionNames $ServiceConnectionNames -Severity $Severity -ubc	
	  	    }
	    }
	    else
	    {
	  	    $ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -Severity $Severity -ubc	
	    }
	}
	else
	{
		if($BuildNames)
		{
		    if ($BuildNames -and $ReleaseNames -and $ServiceConnectionNames -and $AgentPoolNames) {
		    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -BuildNames $BuildNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -AgentPoolNames $AgentPoolNames -Severity $Severity	
		    }
		    elseif ($BuildNames -and $ReleaseNames -and $ServiceConnectionNames) {
		    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -BuildNames $BuildNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -Severity $Severity	
		    }
		    elseif ($BuildNames -and $ReleaseNames) {
		    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -BuildNames $BuildNames -ReleaseNames $ReleaseNames -Severity $Severity	
		    }
		    else{
		    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -BuildNames $BuildNames -Severity $Severity 	
		    }
	    }
	    elseif($ReleaseNames)
	  	{
	  	    if ($ReleaseNames -and $ServiceConnectionNames -and $AgentPoolNames) {
	  	    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -AgentPoolNames $AgentPoolNames -Severity $Severity	
	  	    }
	  	    elseif ($ReleaseNames -and $ServiceConnectionNames) {
	  	    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -ReleaseNames $ReleaseNames -ServiceConnectionNames $ServiceConnectionNames -Severity $Severity	
	  	    }
	  	    else{
	  	    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -ReleaseNames $ReleaseNames -Severity $Severity	
	  	    }
	    }
	    elseif($ServiceConnectionNames)
	  	{
	  	    if ($ServiceConnectionNames -and $AgentPoolNames) {
	  	    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -ServiceConnectionNames $ServiceConnectionNames -AgentPoolNames $AgentPoolNames -Severity $Severity	
	  	    }
	  	    else
	  	    	$ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -ServiceConnectionNames $ServiceConnectionNames -Severity $Severity	
	  	    }
	    }
	    else
	    {
	  	    $ReportFolderPath = Get-AzSKAzureDevOpsSecurityStatus -OrganizationName $OrgName -DoNotOpenOutputFolder -PATToken $token -ProjectNames $ProjectNames -Severity $Severity	
	    }
	}
 
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
			$user = ""
			$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$plaintoken)))
			$uri = "https://extmgmt.dev.azure.com/$OrgName/_apis/extensionmanagement/installedextensions/$publisherName/$extensionName/Data/Scopes/Default/Current/Collections/MyCollection/Documents?api-version=5.1-preview.1";
			
			#Write-Host $uri    
			$scanResultId = $varPrjName + "_BuildId_" + $varBuildId + "_" + $(get-date -f dd-MM-yyyy-HH-mm-ss)
			#Write-Host $scanResultId  
			$body = @{"id" = "$scanResultId"; "__etag" = -1; "value"= $SVTResult;} | ConvertTo-Json

			#Write-Host $body
			try {
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