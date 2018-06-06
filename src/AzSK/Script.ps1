#$CurrentValue =  (Get-Item -Path $PSScriptRoot).Parent.FullName
$modulePath = "C:\Users\v-zhgup\source\repos\DevOpsKit4\src\AzSK\AzSKStaging.psd1";
$Error.Clear()
#$azurerm = @(Get-Module AzureRM -ListAvailable)
#if($azurerm -ne $null){
#	$check = ($azurerm | Where-Object {$_.Version -EQ "5.2.0"})		
#	if(-not $check){
#		Install-Module -Name AzureRM -Scope CurrentUser -AllowClobber -Repository PSGallery -Force
#	}
#}
#else{
#	Install-Module -Name AzureRM -Scope CurrentUser -AllowClobber -Repository PSGallery -Force
#}
Import-Module $modulePath 

$userLogin = $true;
if ($userLogin) {
    $loginFilePath = $Env:LOCALAPPDATA + "\Microsoft\AzSKLogs\AzureRMProfile4.0.json";
    $fileExists = Test-Path -Path $loginFilePath
    if ($fileExists) {
        try {
            Import-AzureRmContext -Path $loginFilePath
        }
        catch {
            $fileExists = $false
            Remove-Item -Path $loginFilePath
        }
    }

    if (-not $fileExists) {
        try {
			if(-not (Test-Path -Path ($Env:LOCALAPPDATA + "\Microsoft\AzSKLogs")))
			{
				mkdir -Path ($Env:LOCALAPPDATA + "\Microsoft\AzSKLogs") -Force | Out-Null
			}
            Add-AzureRmAccount #-SubscriptionId = "<SubscriptionId>"
            Add-Content -Path $loginFilePath -Value ""
            Clear-Content -Path $loginFilePath
            Save-AzureRmContext -Path $loginFilePath -Force
        }
        catch {
            Remove-Item -Path $loginFilePath
        }
    }
}
else {
    #Login with service principal goes here

}


Get-AzSKAzureServicesSecurityStatus -SubscriptionId 254ad434-e2e6-45c0-a32b-34bf24cb7479  -ResourceName azsktestcdn -ControlId Azure_CDN_DP_Enable_Https -ControlsToAttest All #-ControlIDs "Azure_Subscription_AuthZ_Remove_Deprecated_Accounts, Azure_SQLDatabase_DP_Enable_TDE, Azure_SQLDatabase_AuthZ_Use_AAD_Admin"   #-AttestControls All #-ResourceName "AzSKdemosql" -ResourceGroupNames "AzSKDemoDataRG" 
#Get-DevAzSKAzureServicesSecurityStatus -SubscriptionId $SubscriptionId -ResourceGroupNames "Common-CentralIndia-RG" -ResourceTypeName SQLDatabase -AttestControls None -ControlIDs "Azure_SQLDatabase_AuthZ_Configure_IP_Range" 
#Get-AzSKAzureServicesSecurityStatus -SubscriptionId 254ad434-e2e6-45c0-a32b-34bf24cb7479       -ResourceTypeName CDN  -BulkAttestControlId Azure_CDN_DP_Enable_Https -AttestationStatus NotAnIssue  -ControlsToattest All  -JustificationText Test 
# Display all errors
$Error | Group-Object -Property CategoryInfo
Stop-Process -Name PowerShellToolsProcessHost
