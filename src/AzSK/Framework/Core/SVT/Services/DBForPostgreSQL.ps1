#using namespace Microsoft.Azure.Commands.AppService.Models
Set-StrictMode -Version Latest
class DBForPostgreSQL: AzSVTBase
{
    hidden [PSObject] $ResourceObject;
    hidden [PSObject] $PostgreSQLFirewallRules;
     
    DBForPostgreSQL([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId, $svtResource)
    {
		  $this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
      if (-not $this.ResourceObject) {
        $this.ResourceObject = Get-AzResource -ResourceId $this.ResourceId
        if(-not $this.ResourceObject)
        {
            throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
        }
      }

      return $this.ResourceObject;
    }    

    hidden [ControlResult] CheckPostgreSQLSSLConnection([ControlResult] $controlResult)
    {
      
      #Fetching ssl Object
      $ssl_option = $this.ResourceObject.properties.sslEnforcement
      #checking ssl is enabled or disabled
      if($ssl_option -eq 'Enabled')
      {
        $controlResult.AddMessage([VerificationResult]::Passed, "SSL enforcement is enabled");
      }
      else 
      {
        $controlResult.AddMessage([VerificationResult]::Failed, "SSL enforcement is disabled");
      }
      #return
      return $controlResult
    }

    [PSObject] GetFirewallRules()
    {
        if ($null -eq $this.PostgreSQLFirewallRules)
        {
             # List firewall rules for Azure Database for PostgreSQL
            $ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()	
            $uri=[system.string]::Format($ResourceAppIdURI+"/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforPostgreSQL/servers/{2}/firewallRules?api-version=2017-12-01",$this.SubscriptionContext.SubscriptionId,$this.ResourceContext.ResourceGroupName,$this.ResourceContext.ResourceName)
            try
            {
                $this.PostgreSQLFirewallRules = [WebRequestHelper]::InvokeGetWebRequest($uri);
            }
            catch
            {
                $this.PostgreSQLFirewallRules = 'error'
            }
        }
        return $this.PostgreSQLFirewallRules
    }

    hidden [ControlResult] CheckPostgreSQLFirewallIpRange([ControlResult] $controlResult)
    {
     
      $firewallRules = $this.GetFirewallRules()
      if ($firewallRules -eq 'error')
      {
        $controlResult.AddMessage([VerificationResult]::Manual, "Unable to get firewall rules for - [$($this.ResourceContext.ResourceName)]");
      }
      else
      {
        if([Helpers]::CheckMember($firewallRules,"id"))
        {
          $firewallRulesForAzure = $firewallRules | Where-Object { $_.name -ne "AllowAllWindowsAzureIps" }
          if(($firewallRulesForAzure | Measure-Object ).Count -eq 0)
          {
            $controlResult.AddMessage([VerificationResult]::Passed, "No custom firewall rules found.");
            return $controlResult
          }

          $controlResult.AddMessage([MessageData]::new("Current firewall settings for - ["+ $this.ResourceContext.ResourceName +"]",
                                                        $firewallRulesForAzure));

          $anyToAnyRule =  $firewallRulesForAzure | Where-Object { $_.properties.StartIpAddress -eq $this.ControlSettings.IPRangeStartIP -and $_.properties.EndIpAddress -eq  $this.ControlSettings.IPRangeEndIP}
          if (($anyToAnyRule | Measure-Object).Count -gt 0)
          {
              $controlResult.AddMessage([VerificationResult]::Failed,
                                          [MessageData]::new("Firewall rule covering all IPs (Start IP address: $($this.ControlSettings.IPRangeStartIP) To End IP Address: $($this.ControlSettings.IPRangeEndIP)) is defined."));
          }
          else
          {
              $controlResult.VerificationResult = [VerificationResult]::Verify
          }
          $controlResult.SetStateData("Firewall IP addresses", $firewallRules);
        }
        else
        {
          $controlResult.AddMessage([VerificationResult]::Passed, "No custom firewall rules found.");  
        }
          
      }

      return $controlResult;
    }

    hidden [ControlResult] CheckPostgreSQLFirewallAccessAzureService([ControlResult] $controlResult)
    {
        $firewallRules = $this.GetFirewallRules()
        if ($firewallRules -eq 'error')
        {
          $controlResult.AddMessage([VerificationResult]::Manual, "Unable to get firewall rules for - [$($this.ResourceContext.ResourceName)]");
        }
        else
        {
          if([Helpers]::CheckMember($firewallRules, "id"))
          {
            $firewallRulesForAzure = $firewallRules | Where-Object { $_.name -eq "AllowAllWindowsAzureIps" }
            if(($firewallRulesForAzure | Measure-Object ).Count -gt 0)
            {
              $controlResult.AddMessage([VerificationResult]::Verify,
                                          [MessageData]::new("'Allow access to Azure services' is turned 'ON'. This option configures the firewall to allow all connections from Azure including connections from the subscriptions of other customers."));
            }	
            else
            {
              $controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("'Allow access to Azure services' is turned 'OFF'"));
            }
          }
          else
          {
            $controlResult.AddMessage([VerificationResult]::Passed, "No custom firewall rules found.");
          }   
        }
      return $controlResult
    }

    # This is a verify control. As the backup is by default enabled, the customer must verify backup settings from a BC-DR standpoint.
    hidden [ControlResult] CheckPostgreSQLBCDRStatus([ControlResult] $controlResult)
    {
      $backupSettings = @{ 
                            "backupRetentionDays" = $this.ResourceObject.properties.storageProfile.backupRetentionDays;
                            "geoRedundantBackup" =  $this.ResourceObject.properties.storageProfile.geoRedundantBackup
                         }

      $controlResult.AddMessage([VerificationResult]::Verify, "Verify that the critical business data in the PostgreSQL server has been backed up from a BC-DR standpoint.",$backupSettings);
      $controlResult.SetStateData("Backup setting:", $backupSettings);

      return $controlResult;
    }

    hidden [ControlResult] CheckPostgreSQLATPSetting([ControlResult] $controlResult)
    {
      $securityAlertPolicies = ""
      # Get advanced threat protection settings for Azure Database of PostgreSQL
      $ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()	
      $uri=[system.string]::Format($ResourceAppIdURI+"/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforPostgreSQL/servers/{2}/securityAlertPolicies/Default?api-version=2017-12-01",$this.SubscriptionContext.SubscriptionId,$this.ResourceContext.ResourceGroupName,$this.ResourceContext.ResourceName)

      try
      {
        $securityAlertPolicies = [WebRequestHelper]::InvokeGetWebRequest($uri);
      }
      catch
      {
        $controlResult.AddMessage([VerificationResult]::Manual, "Unable to get Advanced Threat Protection setting for - [$($this.ResourceContext.ResourceName)]");
      }
      if([Helpers]::CheckMember($securityAlertPolicies,"properties.state") -and [Helpers]::CheckMember($securityAlertPolicies.properties,"emailAccountAdmins", $false))
      {
        if(($securityAlertPolicies.properties.state -eq 'Enabled') -and ($securityAlertPolicies.properties.emailAccountAdmins -eq 'true')) 
        {
          $controlResult.AddMessage([VerificationResult]::Passed, "'Advanced Threat Protection; is enabled");
        }
        else
        {
          $result = @{ 'securityAlertPolicies' = @{'State' = $securityAlertPolicies.properties.state; 'emailAccountAdmins' = $securityAlertPolicies.properties.emailAccountAdmins }}
          $controlResult.AddMessage([VerificationResult]::Failed, "Either Advanced Threat Protection or the option to 'send email notification to admins and subscription owners' is disabled.", $result);
          $controlResult.SetStateData("Advanced Threat Protection setting:", $result);
        }
      }
      else
      {
        $controlResult.AddMessage([VerificationResult]::Manual, "Unable to get Advanced Threat Protection setting for - [$($this.ResourceContext.ResourceName)]");
      }
      return $controlResult;
    }

    hidden [ControlResult] CheckPostgreSQLVnetRules([ControlResult] $controlResult)
    {
      $virtualNetworkRules = ''
      # Get virtual network rules for Azure Database of PostgreSQL
      $ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()	
      $uri=[system.string]::Format($ResourceAppIdURI+"/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforPostgreSQL/servers/{2}/virtualNetworkRules?api-version=2017-12-01",$this.SubscriptionContext.SubscriptionId,$this.ResourceContext.ResourceGroupName,$this.ResourceContext.ResourceName)      

      try
      {
        $virtualNetworkRules = [WebRequestHelper]::InvokeGetWebRequest($uri);
      }
      catch
      {
        $controlResult.AddMessage([VerificationResult]::Manual, "Unable to fetch details of functions.");
      }
      if ([Helpers]::CheckMember($virtualNetworkRules,"id")) {
            
        $vnetRules = $virtualNetworkRules | ForEach-Object {
            @{ 'name'="$($_.name)"; 'id'="$($_.id)"; 'virtualNetworkSubnetId'="$($_.properties.virtualNetworkSubnetId)" }
        }
        $controlResult.AddMessage([VerificationResult]::Manual, "The enabled virtual network rules are:",$vnetRules);
        $controlResult.SetStateData("Configured virtual network rules:", $vnetRules);
      }
      else
      {
          $controlResult.AddMessage([VerificationResult]::Verify, "There are no virtual network rules enabled for '$($this.ResourceContext.ResourceName)' server. Consider using virtual network rules for improved isolation.");
      }
      
      return $controlResult
    }

    # This function checks for a specific category of log.
    # We have created this custom function since log category based filter is not available in the default 'CheckDiagnosticsSettings' function.
    hidden [ControlResult] CheckPostgreSQLDiagnosticsSettings([ControlResult] $controlResult) {
      $diagnostics = $Null
      try
      {
        $diagnostics = Get-AzDiagnosticSetting -ResourceId $this.ResourceId -ErrorAction Stop -WarningAction SilentlyContinue
      }
      catch
      {
        if([Helpers]::CheckMember($_.Exception, "Response") -and ($_.Exception).Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound)
        {
          $controlResult.AddMessage([VerificationResult]::Failed, "Diagnostics setting is disabled for resource - [$($this.ResourceContext.ResourceName)].");
          return $controlResult
        }
        else
        {
          $this.PublishException($_);
        }
      }
      if($Null -ne $diagnostics -and ($diagnostics.Logs | Measure-Object).Count -ne 0)
      {
        $nonCompliantLogs = $diagnostics.Logs | Where-Object {$_.Category -eq 'PostgreSQLLogs'} |
                  Where-Object { -not ($_.Enabled -and
                        ($_.RetentionPolicy.Days -eq $this.ControlSettings.Diagnostics_RetentionPeriod_Forever -or
                        $_.RetentionPolicy.Days -ge $this.ControlSettings.Diagnostics_RetentionPeriod_Min))};

        $selectedDiagnosticsProps = $diagnostics | Select-Object -Property @{ Name = "Logs"; Expression = {$_.Logs |  Where-Object {$_.Category -eq 'PostgreSQLLogs'}}}, StorageAccountId, EventHubName, Name;

        if(($nonCompliantLogs | Measure-Object).Count -eq 0)
        {
          $controlResult.AddMessage([VerificationResult]::Passed,
            "Diagnostics settings are correctly configured for resource - [$($this.ResourceContext.ResourceName)]",
            $selectedDiagnosticsProps);
        }
        else
        {
          $failStateDiagnostics = $nonCompliantLogs | Select-Object -Property @{ Name = "Logs"; Expression = {$_.Logs |  Where-Object {$_.Category -eq 'PostgreSQLLogs'}}}, StorageAccountId, EventHubName, Name;
          $controlResult.SetStateData("Non compliant resources are:", $failStateDiagnostics);
          $controlResult.AddMessage([VerificationResult]::Failed,
            "Diagnostics settings are either disabled OR not retaining logs for at least $($this.ControlSettings.Diagnostics_RetentionPeriod_Min) days for resource - [$($this.ResourceContext.ResourceName)]",
            $selectedDiagnosticsProps);
        }
      }
      else
      {
        $controlResult.AddMessage([VerificationResult]::Failed, "Diagnostics setting is disabled for resource - [$($this.ResourceContext.ResourceName)].");
      }
      return $controlResult
    }

    hidden [ControlResult] CheckPostgreSQLConnectionThrottlingServerParameter([ControlResult] $controlResult) {
        $status = '';
        $status = $this.CheckServerParameters("connection_throttling")
        if ($status -eq "ON")
        { 
            $controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("Connection throttling for $($this.ResourceContext.ResourceName) is turned ON."));
        }
        elseif ($status -eq "OFF")
        {
            $controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Connection throttling for $($this.ResourceContext.ResourceName) is turned OFF."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Manual, [MessageData]::new("Unable to validate control. Please verify from portal, 'connection-throttling' is ON or OFF."));
        }
        return $controlResult
    }

    hidden [string] CheckServerParameters([string] $parameterName)
    {
        $status = '';
        # Get postgreSQL server parameter
        $ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()
        $uri = [system.string]::Format($ResourceAppIdURI + "subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforPostgreSQL/servers/{2}/configurations/{3}?api-version=2017-12-01", $this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName, $parameterName)
        $response = $null;
        try
        { 	
          $response = [WebRequestHelper]::InvokeGetWebRequest($uri);
        } 
        catch
        { 
          $response = $null;
        }  	  
        if (($null -ne $response) -and (($response | Measure-Object).Count -gt 0))
        {
          if (([Helpers]::CheckMember($response[0], "properties.value")) -and ($response.properties.value -eq "ON")) {
              $status = 'ON'
          }
          else {
              $status = 'OFF'
          }
        }
        else {
          $status = 'error'
        }
        return $status
    }

    hidden [ControlResult] CheckPostgreSQLLoggingParameters([ControlResult] $controlResult) {
        $statusLogConnections = '';
        $statusLogDisconnections = '';
        $statusLogConnections = $this.CheckServerParameters("log_connections")
        $statusLogDisconnections = $this.CheckServerParameters("log_disconnections")
        $message = "'log_connections' for $($this.ResourceContext.ResourceName) is turned " + $statusLogConnections + "." 
        $message += "`n'log_disconnections' for $($this.ResourceContext.ResourceName) is turned " + $statusLogDisconnections + "."
        if (($statusLogConnections -eq "ON") -and ($statusLogDisconnections -eq "ON"))
        { 
          $controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new($message));
        }
        elseif (($statusLogConnections -eq "OFF") -or ($statusLogDisconnections -eq "OFF"))
        {
          $controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new($message));
          $controlResult.SetStateData("Log server parameters", @{ 'log_connections' = $statusLogConnections; "log_disconnections" = $statusLogDisconnections});
        }
        else
        {
          $controlResult.AddMessage([VerificationResult]::Manual, [MessageData]::new("Unable to validate control.Please verify from portal values for log_connections and log_disconnections."));
        }
        return $controlResult
    }

}
