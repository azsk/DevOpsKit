Import-Module 'D:\repository\DevOpsKit1909\svt\src\AzSK\AzSKStaging.psd1'

grs -subscriptionid 'abb5301a-22a4-41f9-9e5f-99badff261f8' -resourcegroupname 'MySqlDemo' -resourcename 'etsmysqlserver' -controlid 'Azure_DBforMySQL_NetSec_Configure_VNet_Rules'
#Get-AzDiagnosticSetting -ResourceId "subscriptions/abb5301a-22a4-41f9-9e5f-99badff261f8/resourceGroups/MySqlDemo/providers/Microsoft.DBforMySQL/servers/etsmysqlserver" 
#Get-AzResource -Name 'etsmysqlserver'