using namespace Microsoft.Azure.Commands.Management.Storage.Models
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
            [EventBase]::PublishCustomMessage("Failed to upgrade storage [$StorageName].");
        }
        else
        {
            return $this.azskStorageInstance
        }
    }

    hidden CreateComplianceStateTableIfNotExists
    {
        if([Helpers]::IsUserSubStorageUpgraded() -eq $False)
        {
            $storage = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()    
            [Helpers]::UpgradeBlobToV2Storage($storage.Name,$storage.ResourceGroupName)
        }
        $azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
        $azskStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
        if($azskStorageAccount)
        {
            $this.azskStorageInstance = [StorageHelper]::new($this.SubscriptionContext.subscriptionId, $azskRGName,$azskStorageAccount.Location, $azskStorageAccount.Name, [Kind]::StorageV2);
            $this.azskStorageInstance.CreateTableIfNotExists([Constants]::ComplianceReportContainerName);		
        }	
    } 


}