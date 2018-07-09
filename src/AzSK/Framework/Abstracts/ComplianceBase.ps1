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

    hidden  [Hashtable] InsertEntitiesToTable(
		[PSObject[]]$Data,
		[string] $StorageAccountName,
        [string] $TableName,
        [string] $Uri,
		[string] $SharedKey,
		[string] $xmsdate,
        [string] $Boundary
        )
	{
        $changeset = "changeset_$([guid]::NewGuid().ToString())"
        $contentBody = ""
        $miniDataTemplate = @'
--{0}
Content-Type: application/http
Content-Transfer-Encoding: binary

POST https://{1}.table.core.windows.net/{2}() HTTP/1.1
Accept: application/json;odata=minimalmetadata
Content-Type: application/json
Prefer: return-no-content
DataServiceVersion: 3.0

{3}
        
'@
        $template = @'
--{0}
Content-Type: multipart/mixed; boundary={1}

{2}
--{1}--
--{0}--
'@
        $data | ForEach-Object{
            $row =  $_;
            $contentBody = $contentBody + ($miniDataTemplate -f $changeset, $StorageAccountName, $TableName, ($row | ConvertTo-Json -Depth 10))
        }
        
        $requestBody = $template -f $Boundary, $changeset, $contentBody

        $headers = @{"x-ms-date"=$xmsdate;"Authorization"="SharedKey $sharedKey";"x-ms-version"="2018-03-28"}

        return Invoke-WebRequest -Uri $Uri `
                                    -Method Post `
                                    -ContentType "multipart/mixed; boundary=$boundary" `
                                    -Body $requestBody `
                                    -Headers $headers
        
        
    }

}
