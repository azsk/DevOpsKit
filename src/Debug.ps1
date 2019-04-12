$modulePath = [System.IO.Path]::Combine("C:\Users\v-tashuk\source\Repos\DevOpsKit1807\src\", "AzSK\AzSKStaging.psd1");
#Remove-Module $modulePath 
Import-Module $modulePath 
#GRS -SubscriptionId $env:Sub02 -ResourceGroupNames "azsk-sfc-rg" -ResourceNames azzsk-sf -ControlIds "Azure_ServiceFabric_DP_Set_Property_ClusterProtectionLevel" #-ControlsToAttest All
#GRS -SubscriptionId $env:Sub02 -ResourceTypeName Databricks -ControlIds Azure_Databricks_NetSec_Justify_VNet_Peering
#GRS -SubscriptionId $env:Sub02 -ResourceGroupNames azsk-kube-rg -ResourceNames azsk-kube-tashuk-rbac -ControlIds "Azure_KubernetesService_Deploy_Use_Latest_Version"
#Set-AzSKAlerts -SubscriptionId $env:sub02 -SecurityContactEmails "v-tashuk@microsoft.com" -Force
#GRS -SubscriptionId $env:Sub02 -ResourceGroupNames azsk-sfc-rg -ResourceNames azzsk-sf -ControlIds "Azure_ServiceFabric_DP_Dont_Expose_Reverse_Proxy_Port"
#GRS -SubscriptionId $env:Sub02 -ResourceGroupNames azsksfrg-mnode -ResourceNames azsksf-multinode -ControlIds "Azure_ServiceFabric_DP_Dont_Expose_Reverse_Proxy_Port"
#GRS -SubscriptionId $env:Sub02 -ResourceGroupNames RiniTestRG -ResourceNames testvm2 -ControlIds "Azure_VirtualMachine_SI_Install_GuestConfig_Extension" -ControlsToAttest all
Get-AzSKARMTemplateSecurityStatus -ARMTemplatePath "D:\DSRE_Notify\TestARMChecker\ARMCheckerDrive" -ParameterFilePath "D:\DSRE_Notify\TestARMChecker\ARMCheckerDrive" -recurse
#Get-AzSKARMTemplateSecurityStatus -ARMTemplatePath  "D:\DSRE_Notify\TestARMChecker\ARMCheckerDrive"  -ParameterFilePath "D:\DSRE_Notify\TestARMChecker\ARMCheckerDrive" -recurse -ExcludeFiles "*parameters*"
