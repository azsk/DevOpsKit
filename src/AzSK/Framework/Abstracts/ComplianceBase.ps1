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
        $this.GetStorageHelperInstance();
    }
    [StorageHelper] GetStorageHelperInstance()
    {
        if($null -eq $this.azskStorageInstance)
        {
            try {
                $azskStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage();
    
                if(($azskStorageAccount | Measure-Object).Count -eq 1 -and $azskStorageAccount.Kind -ne [Kind]::StorageV2)
                {
                    [UserSubscriptionDataHelper]::UpgradeBlobToV2Storage();
                }
                $azskRGName = [UserSubscriptionDataHelper]::GetUserSubscriptionRGName();     
                if($azskStorageAccount)
                {
                    $this.azskStorageInstance = [StorageHelper]::new($this.SubscriptionContext.subscriptionId, $azskRGName,$azskStorageAccount.Location, $azskStorageAccount.Name, [Kind]::StorageV2);
                    $this.azskStorageInstance.CreateTableIfNotExists([Constants]::ComplianceReportTableName);		
                }
            }
            catch {
                #eat this exception as the storage account would be null in the case of exception
            }
        }
        return $this.azskStorageInstance
    }

    hidden [bool] HaveRequiredPermissions()
    {
        if($null -eq $this.azskStorageInstance -or ($null -ne $this.azskStorageInstance -and $this.azskStorageInstance.HaveWritePermissions -eq 0))
        {
            return $false;
        }
        else {
            return $true;
        }
    }
}
