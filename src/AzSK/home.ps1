$CurrentValue =  (Get-Item -Path $PSScriptRoot).Parent.FullName
$modulePath = "C:\Users\AKALETI\Desktop\dedbug\DevOpsKit-develop\src\AzSK\AzSKStaging.psd1";

$Error.Clear()

Import-Module $modulePath
#Import-Module AzSKStaging

###############################################################################################

#<#DontCheckin
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
#>

#ica -sid "254ad434-e2e6-45c0-a32b-34bf24cb7479" -tsids "abb5301a-22a4-41f9-9e5f-99badff261f8" -rgns '*' -aargn 'bynacarg3' -aan 'bynacaan3' -owid 'sad' -okey 'asdasd' -csm
#gss -sid '254ad434-e2e6-45c0-a32b-34bf24cb7479' -cid 'Azure_Subscription_Config_ARM_Policy' #-ControlsToAttest All # 
#Get-AzSKControlsStatus -SubscriptionId 'abb5301a-22a4-41f9-9e5f-99badff261f8' -resourcegroupnames wave2rg -ubc
#grs -sid 'abb5301a-22a4-41f9-9e5f-99badff261f8' -rgns 'azskrg' #-ResourceT4ypeName Storage -ExcludeTags "AzSKCfgControl" #-cid 'Azure_Storage_AuthN_Dont_Allow_Anonymous' #-rn 'testbynaorgdt1' -as NotAnIssue -jt 'not an issue' -cta All
#Set-AzSKUserPreference -DisablePersistScanReportInSubscription
#grs -sid 'abb5301a-22a4-41f9-9e5f-99badff261f8' -ResourceTypeName RedisCache #-rn 'azsdkdemosql' #-cids 'Azure_SQLDatabase_DP_Enable_TDE'
#Get-AzSKAzureServicesSecurityStatus -SubscriptionId 'abb5301a-22a4-41f9-9e5f-99badff261f8' -ResourceNames wave2cdn -cids Azure_CDN_DP_Enable_Https #-ControlsToAttest AlreadyAttested 
#gss -sid 'abb5301a-22a4-41f9-9e5f-99badff261f8' -ubc
#Get-AzSKControlsStatus -subscriptionid '0e265216-bc29-40b0-8759-07d7cb75497f' #-usebaselinecontrols
#gai -subscriptionid '0e265216-bc29-40b0-8759-07d7cb75497f' -infotype ComplianceInfo
#grs -sid "abb5301a-22a4-41f9-9e5f-99badff261f8" -rgns "ak-rg" -rn "w-app1" -cid "Azure_AppService_DP_Website_Load_Certificates_Not_All" -cta 'All'
#grs -sid '0e265216-bc29-40b0-8759-07d7cb75497f' -rgns "AzSKRG" 
#Get-AzSKSubscriptionSecurityStatus -sid "abb5301a-22a4-41f9-9e5f-99badff261f8" 
Get-AzSKARMTemplateSecurityStatus -ARMTemplatePath 'C:\Users\AKALETI\Documents\My Received Files\template.json' -Preview
#Update-AzSKPersistedState -SubscriptionId '254ad434-e2e6-45c0-a32b-34bf24cb7479' -FilePath 'C:\Users\sbyna\AppData\Local\Microsoft\AzSKStagingLogs\Sub_MSFT-Security Reference Architecture-04\20180711_215827_GSS\SecurityReport-20180711_215827.csv' -StateType UserComments
#Get-AzSKAzureServicesSecurityStatus -SubscriptionId "abb5301a-22a4-41f9-9e5f-99badff261f8" -ResourceNames "teststoragelcactn"
