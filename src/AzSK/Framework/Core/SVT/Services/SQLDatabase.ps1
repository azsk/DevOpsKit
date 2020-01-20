using namespace Microsoft.Azure.Commands.Sql.Auditing.Model
using namespace Microsoft.Azure.Commands.Sql.ServerUpgrade.Model
using namespace Microsoft.Azure.Commands.Sql.TransparentDataEncryption.Model
using namespace Microsoft.Azure.Commands.Sql.ThreatDetection.Model

Set-StrictMode -Version Latest
class SQLDatabase: AzSVTBase
{
    hidden [PSObject] $ResourceObject;
    hidden [PSObject[]] $SqlDatabases = $null;
	hidden [PSObject[]] $SqlFirewallDetails = $null;

	SQLDatabase([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId, $svtResource)
    {
        $this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject =   $this.ResourceContext.ResourceDetails

            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }

	[ControlItem[]] ApplyServiceFilters([ControlItem[]] $controls)
	{
		if(-not $this.SqlDatabases)
		{
			try
			{
				$this.SqlDatabases = @();
				$this.SqlDatabases += Get-AzSqlDatabase -ResourceGroupName $this.ResourceContext.ResourceGroupName -ServerName $this.ResourceContext.ResourceName -ErrorAction Stop |
								Where-Object { $_.DatabaseName -ne "master" }
				$this.ChildResourceNames = @();
				$this.SqlDatabases | ForEach-Object {
					$this.ChildResourceNames += $_.DatabaseName;
				}
			}
			catch
			{
				$this.EvaluationError($_);
			}
		}

		$result = @();

		# Filter control if there are no databases
        if($this.SqlDatabases.Count -eq 0)
        {
			$result += $controls | Where-Object { $_.Tags -notcontains "SqlDatabase" };
		}
		else
		{
			$result += $controls;
		}

		return $result;
	}

    <#hidden [ControlResult] CheckSqlServerVersionUpgrade([ControlResult] $controlResult)
    {
        $upgradeStatus = Get-AzSqlServerUpgrade -ResourceGroupName  $this.ResourceContext.ResourceGroupName -ServerName $this.ResourceContext.ResourceName -ErrorAction Stop

        $controlResult.AddMessage([MessageData]::new("Current status of SQL Database server upgrade -",
			                                         $upgradeStatus));

        if ($upgradeStatus.Status -eq [ServerUpgradeStatus]::Completed)
        {
            $controlResult.VerificationResult = [VerificationResult]::Passed
        }
        else
        {
            $controlResult.VerificationResult = [VerificationResult]::Failed
        }

        return $controlResult;
    }#>

    hidden [ControlResult] CheckSqlServerAuditing([ControlResult] $controlResult)
    {
		$serverAudit = $null
		try
		{
			$serverAudit = Get-AzSqlServerAudit -ResourceGroupName $this.ResourceContext.ResourceGroupName -ServerName $this.ResourceContext.ResourceName -ErrorAction Stop	
			$controlResult.AddMessage([MessageData]::new("Current audit status for SQL server [$($this.ResourceContext.ResourceName)]:", $serverAudit))
		}
		catch
		{
			# This block is the catch execption when the storage configured for audit is not found. It either does not exist, associated with a different subscription or you do not have the appropriate credentials to access it.
			$controlResult.AddMessage("$($_.Exception.Message)")
			$controlResult.VerificationResult = [VerificationResult]::Verify;
		}
        
		if($null -ne $serverAudit){
				$isCompliant = (($serverAudit.BlobStorageTargetState -eq [AuditStateType]::Enabled) `
                               -and ($serverAudit.RetentionInDays -eq $this.ControlSettings.SqlServer.AuditRetentionPeriod_Min -or $serverAudit.RetentionInDays -eq $this.ControlSettings.SqlServer.AuditRetentionPeriod_Forever))

				if ($isCompliant){
				   		$controlResult.VerificationResult = [VerificationResult]::Passed
				}elseif (($serverAudit.EventHubTargetState -eq [AuditStateType]::Enabled) -or ($serverAudit.LogAnalyticsTargetState -eq [AuditStateType]::Enabled)) {
					#Mark control as 'Verify' if Audit settings other than Storage is enabled as in such case log retention data is not available
					$controlResult.AddMessage([VerificationResult]::Verify,
												"Please verify that audit logs are retained for at least $($this.ControlSettings.SqlServer.AuditRetentionPeriod_Min) days for SQL server - [$($this.ResourceContext.ResourceName)]");
				}
				else{
						$controlResult.EnableFixControl = $true;
						$controlResult.AddMessage([VerificationResult]::Failed,
					                              "Audit settings are either disabled OR not retaining logs for at least $($this.ControlSettings.SqlServer.AuditRetentionPeriod_Min) days for SQL server - [$($this.ResourceContext.ResourceName)]");
				}

		}
		else{
			$controlResult.AddMessage("Unable to get audit details for SQL server [$($this.ResourceContext.ResourceName)].");
		}

        return $controlResult;
    }

	hidden [ControlResult[]] CheckSqlDatabaseTDE([ControlResult] $controlResult)
    {
		[string[]] $enabledDB = @()
		[string[]] $disabledDB = @()
		[string[]] $errorDB = @()

        if(($this.SqlDatabases | Measure-Object ).Count -eq 0)
        {
            $controlResult.AddMessage([MessageData]::new("No database found on SQL Server - ["+ $this.ResourceContext.ResourceName +"]"));
            #Since there is no database found we are passing this control
            $controlResult.VerificationResult = [VerificationResult]::Passed;
        }
        else
        {
			$atleastOneFailed = $false
            $this.SqlDatabases | ForEach-Object {
				$dbName = $_.DatabaseName;
				try {
					$tdeStatus = Get-AzSqlDatabaseTransparentDataEncryption `
					-ResourceGroupName $this.ResourceContext.ResourceGroupName `
					-ServerName $this.ResourceContext.ResourceName `
					-DatabaseName $dbName `
					-ErrorAction Stop

					if($tdeStatus.State -eq [TransparentDataEncryptionStateType]::Enabled){
						$enabledDB += $_.DatabaseName
					}
					else
					{
						$disabledDB += $_.DatabaseName
						$atleastOneFailed = $true
					}
				}
				catch {
					$atleastOneFailed = $true
					$errorDB += $dbName
				}
				
			} #End of ForEach-Object

			if(($enabledDB | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([MessageData]::new("TDE enabled for following databases on SQL Server - ["+ $this.ResourceContext.ResourceName +"]",($enabledDB)));
			}
			if(($disabledDB | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([MessageData]::new("TDE disabled for following databases on SQL Server - ["+ $this.ResourceContext.ResourceName +"]",($disabledDB)));
				$controlResult.EnableFixControl = $true
				
			}
			if(($errorDB | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([MessageData]::new("TDE is in error state for following databases on SQL Server - ["+ $this.ResourceContext.ResourceName +"]",($errorDB)));
			}

			if($atleastOneFailed) {
				$controlResult.VerificationResult = [VerificationResult]::Failed;
				
				$DatabaseTDEFailed = New-Object -TypeName PSObject 
				$DatabaseTDEFailed | Add-Member -NotePropertyName DisabledDB -NotePropertyValue $disabledDB
				$DatabaseTDEFailed | Add-Member -NotePropertyName ErrorDB -NotePropertyValue $errorDB
				
				$controlResult.SetStateData("TDE Failed for following databases", ($DatabaseTDEFailed));
			}else{
				$controlResult.VerificationResult = [VerificationResult]::Passed;
			}
        }
        return  $controlResult;
    }

    hidden [ControlResult] CheckSqlServerADAdmin([ControlResult] $controlResult)
    {
        $adAdmin = Get-AzSqlServerActiveDirectoryAdministrator -ResourceGroup $this.ResourceContext.ResourceGroupName -Server $this.ResourceContext.ResourceName.ToLower() -ErrorAction Stop

        $controlResult.AddMessage([MessageData]::new("Current status of Active Directory Admin for ["+ $this.ResourceContext.ResourceName +"] is"));

        if(($adAdmin | Measure-Object).Count -gt 0){
                $controlResult.VerificationResult = [VerificationResult]::Passed
                $controlResult.AddMessage([MessageData]::new("Active Directory admins are assigned on SQL Server - ["+ $this.ResourceContext.ResourceName +"]",
                                                            ($adAdmin)));
        }
        else{
            $controlResult.VerificationResult = [VerificationResult]::Failed
            $controlResult.AddMessage([MessageData]::new("No Active Directory admin is assigned on SQL Server - ["+ $this.ResourceContext.ResourceName +"]"));
			$controlResult.EnableFixControl = $true;
        }
        return $controlResult
    }

    hidden [ControlResult] CheckSqlServerThreatDetection([ControlResult] $controlResult)
    {
        $isCompliant = $false
		$serverAudit = $null
		#First check if the server auditing is enabled, without which TD does not work
		try
		{
			$serverAudit = Get-AzSqlServerAudit -ResourceGroupName $this.ResourceContext.ResourceGroupName -ServerName $this.ResourceContext.ResourceName.ToLower() -ErrorAction Stop
		}
		catch
		{
			$controlResult.AddMessage("$($_.Exception.Message)")
			$controlResult.AddMessage([VerificationResult]::Verify, "");
		}
	    
		if($null -ne $serverAudit){
			#Check if Audit is Enabled 
				if(($serverAudit.BlobStorageTargetState -eq [AuditStateType]::Enabled) -or ($serverAudit.EventHubTargetState -eq [AuditStateType]::Enabled) -or ($serverAudit.LogAnalyticsTargetState -eq [AuditStateType]::Enabled)){
					# TODO: We are temporarily suppressing the alias deprecation warning message given by the below Az.SQL cmdlet.
						$serverThreat = Get-AzSqlServerAdvancedThreatProtectionSettings `
									-ResourceGroupName $this.ResourceContext.ResourceGroupName `
									-ServerName $this.ResourceContext.ResourceName.ToLower() `
									-ErrorAction Stop -WarningAction SilentlyContinue

						$controlResult.AddMessage([MessageData]::new("Current threat detection status for SQL server ["+ $this.ResourceContext.ResourceName +"] is",
															($serverThreat)));

						$excludedTypeCount = ($serverThreat.ExcludedDetectionTypes | Measure-Object ).Count

						if($excludedTypeCount -gt 0){
							$controlResult.AddMessage([MessageData]::new("All the required audit event types are not enabled for SQL Server - ["+ $this.ResourceContext.ResourceName +"]"));
						}

						$isCompliant =  (($serverThreat.ThreatDetectionState -eq [ThreatDetectionStateType]::Enabled) `
									-and ($excludedTypeCount -eq 0) `
									-and (($serverThreat.EmailAdmins  -eq $True) -or ($null -ne $serverThreat.NotificationRecipientsEmails)))
						if ($isCompliant) {
							$controlResult.VerificationResult = [VerificationResult]::Passed
						}
						else{
							$controlResult.EnableFixControl = $true;
							$controlResult.VerificationResult = [VerificationResult]::Failed
						}
							return $controlResult
						}
				else{
					$controlResult.EnableFixControl = $true;
					$controlResult.AddMessage([VerificationResult]::Failed, "Auditing is not enabled for SQL server ["+ $this.ResourceContext.ResourceName +"]. Threat detection requires auditing enabled.");
					return $controlResult
				}
		}
		else{
			$controlResult.AddMessage("Unable to get audit details for SQL server [$($this.ResourceContext.ResourceName)]. Threat detection requires auditing enabled.");
			return $controlResult
		}

	}

    hidden [ControlResult] CheckSqlDatabaseFirewallEnabled([ControlResult] $controlResult)
    {
        $firewallDtls = $this.GetSqlServerFirewallRules()
        if(($firewallDtls | Measure-Object ).Count -gt 0){
			$controlResult.AddMessage("Firewall is enabled for [$($this.ResourceContext.ResourceName)].");
            $controlResult.VerificationResult = [VerificationResult]::Passed
        }
        else{
			$controlResult.AddMessage("Firewall is not enabled for [$($this.ResourceContext.ResourceName)].");
            $controlResult.VerificationResult = [VerificationResult]::Failed
        }
        return $controlResult
    }

    hidden [ControlResult] CheckSqlDatabaseFirewallIPAddressRange([ControlResult] $controlResult)
    {
        #Current function will check firewall ip address ranges, if firewall is enabled. When it is enabled, it allows any traffic from services within your Azure subscription to pass through.
        #Default record will be there with Start IP address as 0.0.0.0 and End Ip address as 0.0.0.0
		$firewallDtls = $this.GetSqlServerFirewallRules()
		if(($firewallDtls | Measure-Object ).Count -gt 0)
		{
			$firewallDtlsForAzure = $firewallDtls | Where-Object { $_.FirewallRuleName -ne "AllowAllWindowsAzureIps" }
			if(($firewallDtlsForAzure | Measure-Object ).Count -eq 0)
			{
				$controlResult.AddMessage([VerificationResult]::Passed, "No custom firewall rules found.");
				return $controlResult
			}

            $controlResult.AddMessage([MessageData]::new("Current firewall settings for - ["+ $this.ResourceContext.ResourceName +"]",
                                                            $firewallDtlsForAzure));

			$anyToAnyRule =  $firewallDtlsForAzure | Where-Object { $_.StartIpAddress -eq $this.ControlSettings.IPRangeStartIP -and $_.EndIpAddress -eq  $this.ControlSettings.IPRangeEndIP}
			if (($anyToAnyRule | Measure-Object).Count -gt 0)
			{
                $controlResult.AddMessage([VerificationResult]::Failed,
                                            [MessageData]::new("Firewall rule covering all IPs (Start IP address: $($this.ControlSettings.IPRangeStartIP) To End IP Address: $($this.ControlSettings.IPRangeEndIP)) is defined."));
            }
            else
			{
                $controlResult.VerificationResult = [VerificationResult]::Verify
            }
			$controlResult.SetStateData("Firewall IP addresses", $firewallDtls);
        }
        else
		{
            $controlResult.AddMessage([VerificationResult]::Passed, "No custom firewall rules found.");
        }
		return $controlResult
    }

	hidden [ControlResult] CheckSqlServerFirewallAccessAzureService([ControlResult] $controlResult)
    {
		$firewallDtls = $this.GetSqlServerFirewallRules()
		if(($firewallDtls | Measure-Object ).Count -gt 0)
		{
			$firewallDtls = $firewallDtls | Where-Object { $_.FirewallRuleName -eq "AllowAllWindowsAzureIps" }
			if(($firewallDtls | Measure-Object ).Count -gt 0)
			{
				$controlResult.AddMessage([VerificationResult]::Verify,
                                            [MessageData]::new("Azure services are allowed to access the server ["+ $this.ResourceContext.ResourceName +"]"));
			}	
			else
			{
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("Azure services are not allowed to access the server ["+ $this.ResourceContext.ResourceName +"]"));
			}
        }
        else
		{
            $controlResult.AddMessage([VerificationResult]::Passed, "No custom firewall rules found.");
        }
		return $controlResult
    }

	hidden [ControlResult[]]  CheckSqlServerDataMaskingPolicy([ControlResult] $controlResult)
	{
		
		[string[]] $enabledDB = @()
		[string[]] $disabledDB = @()
		[string[]] $errorDB = @()
        
		if(($this.SqlDatabases | Measure-Object ).Count -eq 0)
        {
            $controlResult.AddMessage([MessageData]::new("No database found on SQL Server  ["+ $this.ResourceContext.ResourceName +"]"));
            #Passing the status as there is no database found on the SQL Server
            $controlResult.VerificationResult = [VerificationResult]::Passed;
        }
        else
        {
			$atleastOneFailed = $false

            $this.SqlDatabases |
			ForEach-Object {
				$dbName = $_.DatabaseName;
				try
				{
					$dbMaskingPolicy = Get-AzSqlDatabaseDataMaskingPolicy `
									-ResourceGroupName $this.ResourceContext.ResourceGroupName `
									-ServerName $this.ResourceContext.ResourceName `
									-DatabaseName $dbName

					if($null -ne $dbMaskingPolicy){

						 if($dbMaskingPolicy.DataMaskingState -eq 'Enabled'){
								$atleastOneFailed = $true
								$enabledDB += $dbName
							}
							else
							{
								$disabledDB += $_.DatabaseName
							}
						}
						else{
							$disabledDB += $_.DatabaseName
						}
					}
					catch {
						$errorDB += $dbName
					}
				}

			if(($enabledDB | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([MessageData]::new("Database masking is enabled for following databases on SQL Server - ["+ $this.ResourceContext.ResourceName +"]",($enabledDB)));
			}
			if(($disabledDB | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([MessageData]::new("Database masking is disabled for following databases on SQL Server - ["+ $this.ResourceContext.ResourceName +"]",($disabledDB)));
			}
			if(($errorDB | Measure-Object).Count -gt 0)
			{
				$controlResult.AddMessage([MessageData]::new("Database masking is in error state for following databases on SQL Server - ["+ $this.ResourceContext.ResourceName +"]",($errorDB)));
			}

			if($atleastOneFailed) {
				$controlResult.VerificationResult = [VerificationResult]::Verify;
			}
			else{
				$controlResult.VerificationResult = [VerificationResult]::Manual;
			}

			$DatamaskingState = New-Object -TypeName PSObject 
			$DatamaskingState | Add-Member -NotePropertyName EnabledDB -NotePropertyValue $enabledDB
			$DatamaskingState | Add-Member -NotePropertyName DisabledDB -NotePropertyValue $disabledDB
			$DatamaskingState | Add-Member -NotePropertyName ErrorDB -NotePropertyValue $errorDB

			$controlResult.SetStateData("Data masking state for database is", ($DatamaskingState));
        }

		return $controlResult;
	}

	hidden 	[PSObject[]] GetSqlServerFirewallRules()
	{
		if ($null -eq $this.SqlFirewallDetails) {
            $this.SqlFirewallDetails = Get-AzSqlServerFirewallRule -ResourceGroupName $this.ResourceContext.ResourceGroupName  -ServerName $this.ResourceContext.ResourceName
        }
        return $this.SqlFirewallDetails;
	}
	
}
