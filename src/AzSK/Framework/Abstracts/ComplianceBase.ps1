using namespace Microsoft.Azure.Management.Storage.Models
Set-StrictMode -Version Latest
class ComplianceBase
{ 
    [SubscriptionContext] $SubscriptionContext;
    hidden [StorageHelper] $azskStorageInstance = $null;
    hidden [string] $ComplianceTableName = [Constants]::ComplianceReportTableName;

    ComplianceBase([SubscriptionContext] $subscriptionContext)
    {
        $this.SubscriptionContext = $subscriptionContext
    }
    [StorageHelper] GetStorageHelperInstance()
    {
        if($null -eq $this.azskStorageInstance)
        {
            $azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
            $azskStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
            if($azskStorageAccount)
            {
                $this.azskStorageInstance = [StorageHelper]::new($this.SubscriptionContext.subscriptionId, $azskRGName,$azskStorageAccount.Location, $azskStorageAccount.Name, [Kind]::StorageV2);
            }	
        }
        if($null -eq $this.azskStorageInstance)
        {
            return $Null
        }
        else
        {
            return $this.azskStorageInstance
        }
    }

    hidden CreateComplianceStateTableIfNotExists()
    {
        if([UserSubscriptionDataHelper]::IsUserSubStorageUpgraded() -eq $False)
        {
            [UserSubscriptionDataHelper]::UpgradeBlobToV2Storage()
        }
        $azskRGName = [UserSubscriptionDataHelper]::GetUserSubscriptionRGName()
        $azskStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
        if($azskStorageAccount)
        {
            $this.azskStorageInstance = [StorageHelper]::new($this.SubscriptionContext.subscriptionId, $azskRGName,$azskStorageAccount.Location, $azskStorageAccount.Name, [Kind]::StorageV2);
            $this.azskStorageInstance.CreateTableIfNotExists([Constants]::ComplianceReportTableName);		
        }	
    } 


}