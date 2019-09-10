Set-StrictMode -Version Latest
class DBForMySql: AzSVTBase {
    hidden [PSObject[]] $MySqlFirewallDetails = $null;
    hidden [PSObject] $ResourceAppIdURI = $null;
    hidden [PSObject] $AccessToken = $null;
    hidden [PSObject] $header = $null;
    hidden [PSObject] $headers = $null;
    hidden [PSObject] $ResourceObject;
    hidden [PSObject] $MySQLFirewallRules;
    DBForMySql([string] $subscriptionId, [SVTResource] $svtResource): 
    Base($subscriptionId, $svtResource) { 
	   
        $this.GetResourceObject();
        $this.ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()	 
        $this.AccessToken = [ContextHelper]::GetAccessToken($this.ResourceAppIdURI)
        $this.header = "Bearer " + $this.AccessToken
        $this.headers = @{"Authorization" = $this.header; "Content-Type" = "application/json"; }
    }
	
    hidden [PSObject] GetResourceObject() {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzResource -ResourceId $this.ResourceContext.ResourceId

            if (-not $this.ResourceObject) {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }

    hidden [ControlResult] CheckMySQLSSLConnection([ControlResult] $controlResult) {
        try {
            #Fetching ssl Object
            $ssl_option = $this.ResourceObject.properties.sslEnforcement
        }
        catch {
            $ssl_option = 'error'
        }
        #checking ssl is enabled or disabled
        if ($ssl_option -eq 'error') {
            $controlResult.AddMessage([VerificationResult]::Manual, "Unable to get SSL details for - [$($this.ResourceContext.ResourceName)]");
        }
        else {
            if ($ssl_option.ToLower() -eq 'enabled') {
                $controlResult.AddMessage([VerificationResult]::Passed, "SSL connection is enabled.");
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Failed, "SSL connection is disabled.");
            }
        }
    
        #return
        return $controlResult
    }

    hidden [ControlResult] CheckMySQLBCDRStatus([ControlResult] $controlResult) {
        #fetching backup details
        $backupSettings = @{ 
            "backupRetentionDays" = $this.ResourceObject.properties.storageProfile.backupRetentionDays;
            "geoRedundantBackup"  = $this.ResourceObject.properties.storageProfile.geoRedundantBackup
        }

        $controlResult.AddMessage([VerificationResult]::Verify, "Verify that the critical business data in the MySQL server has been backed up from a BC-DR standpoint.", $backupSettings);
        $controlResult.SetStateData("Backup setting:", $backupSettings);

        return $controlResult;
    }
	
    hidden [ControlResult] CheckMySQLServerVnetRules([ControlResult] $controlResult) {
        $virtualNetworkRules = ''
        $uri = [system.string]::Format($this.ResourceAppIdURI + "/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforMySQL/servers/{2}/virtualNetworkRules/?api-version=2017-12-01", $this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName)      
      
        try {
            $virtualNetworkRules = [WebRequestHelper]::InvokeGetWebRequest($uri);
        }
        catch {
            $controlResult.AddMessage([VerificationResult]::Manual, "Unable to fetch details of functions.");
        }
        if ([Helpers]::CheckMember($virtualNetworkRules, "id")) {   
            $vnetRules = $virtualNetworkRules | ForEach-Object {
                @{ 'name' = "$($_.name)"; 'id' = "$($_.id)"; 'virtualNetworkSubnetId' = "$($_.properties.virtualNetworkSubnetId)" }
            }
            $controlResult.AddMessage([VerificationResult]::Passed, "The enabled virtual network rules are:", $vnetRules);
            $controlResult.SetStateData("Configured virtual network rules:", $vnetRules);
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Verify, "There are no virtual network rules enabled for '$($this.ResourceContext.ResourceName)' server. Consider using virtual network rules for improved isolation.");
        }
      
        return $controlResult
    
    }

    hidden [ControlResult] CheckMySQLServerATP([ControlResult] $controlResult) {
        $uri = [system.string]::Format($this.ResourceAppIdURI + "/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforMySQL/servers/{2}/securityAlertPolicies/Default?api-version=2017-12-01", $this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName)      
        try {
            $response = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $this.headers, $null); 
            if ([Helpers]::CheckMember($response[0], "properties.state")) {
                if ($response[0].properties.state.ToLower() -eq "enabled") {
                    $controlResult.AddMessage([VerificationResult]::Passed, "Advanced threat protection is enabled.");
                }
                else {
                    $controlResult.AddMessage([VerificationResult]::Failed, "Advanced threat protection is disabled.");
                }
            }
        }

        catch {
            $controlResult.AddMessage(($_.Exception).Message);
        }
        return $controlResult

    }

    hidden [ControlResult] CheckMySQLFirewallAccessAzureService([ControlResult] $controlResult) {
        $uri = [system.string]::Format($this.ResourceAppIdURI + "/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforMySQL/servers/{2}/firewallRules/AllowAllWindowsAzureIps?api-version=2017-12-01", $this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName)      
        try {
            $response = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $this.headers, $null); 
            if ($null -ne $response) {
                if ([Helpers]::CheckMember($response[0], "name")) {
                    if ($response[0].name.ToLower() -eq "allowallwindowsazureips") {
                        $controlResult.AddMessage([VerificationResult]::Verify, "Setting 'Allow Access to Azure Services' is enabled. Please verify if your scenario really requires it.");
                    }
                    else {
                        $controlResult.AddMessage([VerificationResult]::Passed, "Setting 'Allow Access to Azure Services' is disabled.");
                    }
                }
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed, "Setting 'Allow Access to Azure Services' is disabled.");
            }
        }
        catch { 
            #API call throws an exception when allow Access to Azure Service is disabled
            if (([Helpers]::CheckMember($_.Exception, "ExceptionType") -and ($_.Exception).ExceptionType.ToString().ToLower() -eq "invalidoperation")) {
                $controlResult.AddMessage([VerificationResult]::Passed, "Setting 'Allow Access to Azure Services' is disabled.");
            } 
            else {
              $controlResult.AddMessage([VerificationResult]::Manual, "Enable to verify setting 'Allow Access to Azure Services'.");
            }   
        }
        return $controlResult
    }
   
    [PSObject] GetFirewallRules() {
        if ($null -eq $this.MySQLFirewallRules) {
            $uri = [system.string]::Format($this.ResourceAppIdURI + "/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforMySQL/servers/{2}/firewallRules?api-version=2017-12-01", $this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName) 
            try {
                $this.MySQLFirewallRules = [WebRequestHelper]::InvokeGetWebRequest($uri);
            }
            catch {
                $this.MySQLFirewallRules = 'error'
            }
        }
        return $this.MySQLFirewallRules
    }

    hidden [ControlResult] CheckMySQLFirewallIpRange([ControlResult] $controlResult) {
        $firewallRules = $this.GetFirewallRules()
        if ($firewallRules -eq 'error') {
            $controlResult.AddMessage([VerificationResult]::Manual, "Unable to get firewall rules for - [$($this.ResourceContext.ResourceName)]");
        }
        else {
            if ([Helpers]::CheckMember($firewallRules, "id")) {
                $firewallRulesForAzure = $firewallRules | Where-Object { $_.name -ne "AllowAllWindowsAzureIps" }
                if (($firewallRulesForAzure | Measure-Object ).Count -eq 0) {
                    $controlResult.AddMessage([VerificationResult]::Passed, "No custom firewall rules found.");
                    return $controlResult
                }

                $controlResult.AddMessage([MessageData]::new("Current firewall settings for - [" + $this.ResourceContext.ResourceName + "]",
                        $firewallRulesForAzure));

                $anyToAnyRule = $firewallRulesForAzure | Where-Object { $_.properties.StartIpAddress -eq $this.ControlSettings.IPRangeStartIP -and $_.properties.EndIpAddress -eq $this.ControlSettings.IPRangeEndIP }
                if (($anyToAnyRule | Measure-Object).Count -gt 0) {
                    $controlResult.AddMessage([VerificationResult]::Failed,
                        [MessageData]::new("Firewall rule covering all IPs (Start IP address: $($this.ControlSettings.IPRangeStartIP) To End IP Address: $($this.ControlSettings.IPRangeEndIP)) is defined."));
                }
                else {
                    $controlResult.VerificationResult = [VerificationResult]::Verify
                }
                $controlResult.SetStateData("Firewall IP addresses", $firewallRules);
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed, "No custom firewall rules found.");  
            }
          
        }

        return $controlResult;
    }

   


}
