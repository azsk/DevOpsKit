Set-StrictMode -Version Latest 
class RedisCache: SVTBase
{       
    hidden [PSObject] $ResourceObject;

    RedisCache([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
                 Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
        $this.GetResourceObject();
    }

    RedisCache([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject =   Get-AzureRmRedisCache -Name $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName -ErrorAction Stop
                                                         
            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }

	 hidden [ControlResult] CheckRedisCacheFirewallIPAddressRange([ControlResult] $controlResult)
     {
		 #check for applicable sku
		 $RDBBackupSkuMappingCheck = $this.ControlSettings.RedisCache.FirewallApplicableSku | Where-Object { $_ -eq $this.ResourceObject.Sku } | Select-Object -First 1;
		 if(-not $RDBBackupSkuMappingCheck)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("Firewall settings are not supported for Sku Tier - [$($this.ResourceObject.Sku)]")); 
			    return $controlResult; 
		  }

		 #PowerShell Get command is provided for Firewall setting. Using Rest API to get firewall details
		 $uri    = [string]::Format("{0}{1}/firewallRules?api-version=2016-04-01",[WebRequestHelper]::AzureManagementUri,$this.ResourceObject.Id)
         $result = [WebRequestHelper]::InvokeGetWebRequest($uri)
		 
		 if($null -ne $result){
			 #Filtering web request response and getting only required details
			 $firewallDtls = $result | Select-Object name , @{Label="StartIp"; Expression={$_.properties.startIp}} , @{Label="EndIp"; Expression={$_.properties.endIp} } | Where-Object { $null -ne $_.StartIp -and  $null -ne $_.endIp }
		     
			 $controlResult.SetStateData("Redis cache firewall rules", $result);
			 
			 if(($firewallDtls | Measure-Object ).Count -gt 0){
					$controlResult.AddMessage([MessageData]::new("Current firewall settings for - ["+ $this.ResourceContext.ResourceName +"]", 
																 $firewallDtls));

				    #Check for any to any firewall rule.
					$anyToAnyRule =  $firewallDtls | Where-Object { $_.StartIp -eq $this.ControlSettings.IPRangeStartIP -and $_.EndIp -eq  $this.ControlSettings.IPRangeEndIP}
					if (($anyToAnyRule | Measure-Object).Count -gt 0){
						$controlResult.AddMessage([VerificationResult]::Failed, 
												  [MessageData]::new("Firewall rule covering all IPs (Start IP address: $($this.ControlSettings.IPRangeStartIP) To End IP Address: $($this.ControlSettings.IPRangeEndIP)) is defined."));
					}
					else {
						$controlResult.VerificationResult = [VerificationResult]::Verify
					}
				}
				else
				{
					$controlResult.AddMessage([VerificationResult]::Verify, "Firewall rules are not defined");
				}
		 }
		 else
		 {
			   $controlResult.AddMessage("Unable to get Firewall settings for - ["+ $this.ResourceContext.ResourceName +"]");
		 }
		 
		 
		 return  $controlResult
	 }

	hidden [ControlResult] CheckRedisCacheRDBBackup([ControlResult] $controlResult)
     {
		 #check for applicable sku
		 $RDBBackupSkuMappingCheck = $this.ControlSettings.RedisCache.RDBBackApplicableSku | Where-Object { $_ -eq $this.ResourceObject.Sku } | Select-Object -First 1;
		 if(-not $RDBBackupSkuMappingCheck)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, [MessageData]::new("RDB Backup are not supported for Sku Tier - [$($this.ResourceObject.Sku)]")); 
			    return $controlResult; 
		  }

		 if($null -ne $this.ResourceObject.RedisConfiguration){  
			 if(($this.ResourceObject.RedisConfiguration.Keys.Contains('rdb-backup-enabled')) -and ($this.ResourceObject.RedisConfiguration.'rdb-backup-enabled' -eq $true)){
				 $controlResult.AddMessage([VerificationResult]::Passed, "RDB Backup is enabled");
			 }
			 else{
				 $controlResult.AddMessage([VerificationResult]::Failed, "RDB Backup is not enabled");
			 }
		 }
		 else{
			  $controlResult.AddMessage("Unable to get RDB backup details for - [$($this.ResourceContext.ResourceName)]"); 
		 }

		 return  $controlResult
		}

	hidden [ControlResult] CheckRedisCacheSSLConfig([ControlResult] $controlResult)
     {
		 if($null -ne $this.ResourceObject.EnableNonSslPort){
			 if($this.ResourceObject.EnableNonSslPort -eq $false){
				 $controlResult.AddMessage([VerificationResult]::Passed, "Non-SSL port is not enabled");
			 }
			 else{
				 $controlResult.EnableFixControl = $true;
				 $controlResult.AddMessage([VerificationResult]::Failed, "Non-SSL port is enabled");
			 }
		 }
		 else{
			  $controlResult.AddMessage("Unable to get SSL Configuration details for - [$($this.ResourceContext.ResourceName)]"); 
		 }
		 return  $controlResult
	 }
}
