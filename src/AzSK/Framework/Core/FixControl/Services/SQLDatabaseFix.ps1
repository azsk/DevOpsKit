using namespace Microsoft.Azure.Commands.Sql.Auditing.Model
using namespace Microsoft.Azure.Commands.Sql.ServerUpgrade.Model
using namespace Microsoft.Azure.Commands.Sql.TransparentDataEncryption.Model
using namespace Microsoft.Azure.Commands.Sql.ThreatDetection.Model

Set-StrictMode -Version Latest 

class SQLDatabaseFix: FixServicesBase
{       
    SQLDatabaseFix([string] $subscriptionId, [ResourceConfig] $resourceConfig, [string] $resourceGroupName): 
        Base($subscriptionId, $resourceConfig, $resourceGroupName) 
    { }
	
	[MessageData[]] FixADAdmin([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();

		if((Get-AzureRmSqlServerActiveDirectoryAdministrator -ResourceGroup $this.ResourceGroupName -Server $this.ResourceName | Measure-Object).Count -le 0)
		{
			$adAdmin = $parameters.ActiveDirectoryAdminEmailId;
			$detailedLogs += [MessageData]::new("Setting up Active Directory admin [$adAdmin] for server [$($this.ResourceName)]...");
			$adAdminResult = Set-AzureRmSqlServerActiveDirectoryAdministrator `
								-ResourceGroupName $this.ResourceGroupName `
								-ServerName $this.ResourceName `
								-DisplayName $adAdmin `
								-ErrorAction Stop

			$detailedLogs += [MessageData]::new("Active Directory admin has been set for server [$($this.ResourceName)]", $adAdminResult);
		}
		else
		{
			$detailedLogs += $this.PublishCustomMessage("Active Directory admin has already been set for server [$($this.ResourceName)]", [MessageType]::Update);
		}
		
		return $detailedLogs;
    }

	[MessageData[]] FixSqlDatabaseTDE([PSObject] $parameters, [string] $databaseName)
    {
		[MessageData[]] $detailedLogs = @();		
        $dbstatus = Get-AzureRmSqlDatabase -ResourceGroupName $this.ResourceGroupName -ServerName $this.ResourceName -DatabaseName $databaseName
        if($dbstatus.Status -eq 'Online')
        {
			$detailedLogs += [MessageData]::new("Enabling SQL TDE on database [$databaseName]...");
            $tdeStatus = Set-AzureRmSqlDatabaseTransparentDataEncryption `
                            -ResourceGroupName $this.ResourceGroupName `
                            -ServerName $this.ResourceName `
                            -DatabaseName $databaseName `
                            -State Enabled `
                            -ErrorAction Stop
	   		
			$detailedLogs += [MessageData]::new("SQL TDE has been enabled on database [$databaseName]", $tdeStatus);
        }
        else
        {
	   		$detailedLogs += $this.PublishCustomMessage("The database [$databaseName] is offline, run the script again when resource is online", [MessageType]::Warning);
        }
		return $detailedLogs;
    }

	[MessageData[]] EnableServerAuditingPolicy([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$storageAccountName = $parameters.StorageAccountName;
		$detailedLogs += [MessageData]::new("Setting up audit policy for server [$($this.ResourceName)] with storage account [$storageAccountName]...");
        Set-AzureRmSqlServerAuditing `
				-ResourceGroupName $this.ResourceGroupName `
				-ServerName $this.ResourceName `
				-StorageAccountName $storageAccountName `
				-State Enabled `
				-RetentionInDays 0 `
				-ErrorAction Stop

		$detailedLogs += [MessageData]::new("Audit policy has been set up for server [$($this.ResourceName)]");
		return $detailedLogs;
    }

	[MessageData[]] EnableDatabaseAuditingPolicy([PSObject] $parameters, [string] $databaseName)
    {
		[MessageData[]] $detailedLogs = @();
		$storageAccountName = $parameters.StorageAccountName;
		$detailedLogs += [MessageData]::new("Setting up audit policy for database [$databaseName] with storage account [$storageAccountName]...");
		
		Set-AzureRmSqlDatabaseAuditing `
				-ResourceGroupName $this.ResourceGroupName `
				-ServerName $this.ResourceName `
				-DatabaseName $databaseName `
				-StorageAccountName $storageAccountName `
				-State Enabled `
				-RetentionInDays 0 `
				-ErrorAction Stop

		$detailedLogs += [MessageData]::new("Audit policy has been set up for database [$databaseName]");
		return $detailedLogs;
    }

	[MessageData[]] EnableServerThreatDetection([PSObject] $parameters)
    {
		[MessageData[]] $detailedLogs = @();
		$storageAccountName = $parameters.StorageAccountName;
		$securityContactEmails = $parameters.SecurityContactEmails;
		$detailedLogs += [MessageData]::new("Setting up threat detection for server [$($this.ResourceName)] with storage account [$storageAccountName]...");

		# Check if audit is not enabled
		if(-not $this.IsServerAuditEnabled())
		{
			$detailedLogs += $this.EnableServerAuditingPolicy($parameters)
		}

        Set-AzureRmSqlServerThreatDetectionPolicy `
				-ResourceGroupName $this.ResourceGroupName `
				-ServerName $this.ResourceName `
				-StorageAccountName $storageAccountName `
				-EmailAdmins $true `
				-NotificationRecipientsEmails $securityContactEmails `
				-RetentionInDays 0 `
				-ErrorAction Stop

		$detailedLogs += [MessageData]::new("Threat detection has been set up for server [$($this.ResourceName)]");
		return $detailedLogs;
    }

	[MessageData[]] EnableDatabaseThreatDetection([PSObject] $parameters, [string] $databaseName)
    {
		[MessageData[]] $detailedLogs = @();
		$storageAccountName = $parameters.StorageAccountName;
		$securityContactEmails = $parameters.SecurityContactEmails;
		$detailedLogs += [MessageData]::new("Setting up threat detection for database [$databaseName] with storage account [$storageAccountName]...");
		
		# Check if audit is not enabled
		if(-not $this.IsDatabaseAuditEnabled($databaseName))
		{
			$detailedLogs += $this.EnableDatabaseAuditingPolicy($parameters, $databaseName);
		}

		Set-AzureRmSqlDatabaseThreatDetectionPolicy `
				-ResourceGroupName $this.ResourceGroupName `
				-ServerName $this.ResourceName `
				-DatabaseName $databaseName `
				-StorageAccountName $storageAccountName `
				-EmailAdmins $true `
				-NotificationRecipientsEmails $securityContactEmails `
				-RetentionInDays 0 `
				-ErrorAction Stop
		
		$detailedLogs += [MessageData]::new("Threat detection has been set up for database [$databaseName]");
		return $detailedLogs;
    }

	hidden [bool] IsServerAuditEnabled()
	{
		$result = $false;
        $serverAudit = Get-AzureRmSqlServerAuditing -ResourceGroupName $this.ResourceGroupName -ServerName $this.ResourceName; 
		$result = ($serverAudit -and $serverAudit.AuditState -eq [AuditStateType]::Enabled)
		return $result
	}

	hidden [bool] IsDatabaseAuditEnabled([string] $databaseName)
	{
		$result = $false;
        $dbAudit = Get-AzureRmSqlDatabaseAuditing -ResourceGroupName $this.ResourceGroupName -ServerName $this.ResourceName -DatabaseName $databaseName; 
		$result = ($dbAudit -and $dbAudit.AuditState -eq [AuditStateType]::Enabled)
		return $result
	}
}
