#$modulePath = "C:\Users\mprabhu\source\repos\DevOpsKit\src\AzSK.AzureDevOps\AzSK.AzureDevOps.psd1"
#$modulePath = "C:\Users\mprabhu\source\repos\DevOpsKit\src\AzSK\AzSKStaging.psd1"
$modulePath = "C:\Users\mprabhu\source\repos\DevOpsKit\src\AzSK.AAD\AzSK.AAD.psd1"
import-Module $modulePath

#Get-AzSKInfo -InfoType ControlInfo -tenantId '254ad434-e2e6-45c0-a32b-34bf24cb7479'
#mprabhu11live: e60f12c0-e1dc-4be1-8d86-e979a5527830
#msft: 72f988bf-86f1-41af-91ab-2d7cd011db47  

#TODO: TenantID.
Get-AzSKAADSecurityStatus -TenantId e60f12c0-e1dc-4be1-8d86-e979a5527830

#Step 2 : Run Security Scan (mprabhu@ms)
<#Get-AzSKAzureDevOpsSecurityStatus -OrganizationName "safetitestvso" `
                                -ProjectNames "AzSDKDemoRepo" `
                                -BuildNames "AzSKDemo_CI" `
                                -ReleaseNames "AzSKDemo_CD" 
#>