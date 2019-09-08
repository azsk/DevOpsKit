Set-StrictMode -Version Latest
class DBForMySql: AzSVTBase
{
  hidden [PSObject[]] $MySqlFirewallDetails = $null;
  hidden [PSObject] $ResourceAppIdURI = $null;
  hidden [PSObject] $AccessToken = $null;
  hidden [PSObject] $header = $null;
  hidden [PSObject] $headers = $null;
 	hidden [PSObject] $ResourceObject;
    DBForMySql([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
	   
    $this.GetResourceObject();
    $this.ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()	 
    $this.AccessToken = [ContextHelper]::GetAccessToken($this.ResourceAppIdURI)
    $this.header = "Bearer " + $this.AccessToken
    $this.headers = @{"Authorization"=$this.header;"Content-Type"="application/json";}
	}
	
    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject =  Get-AzResource -ResourceId $this.ResourceContext.ResourceId

            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }

	hidden [ControlResult] CheckMySQLSSLConnection([ControlResult] $controlResult)
    {
      try{
        #Fetching ssl Object
        $ssl_option = $this.ResourceObject.properties.sslEnforcement

        #checking ssl is enabled or disabled
        if($ssl_option.ToLower() -eq 'enabled')
        {
          $controlResult.AddMessage([VerificationResult]::Passed, "SSL connection is enabled.");
        }
        else 
        {
          $controlResult.AddMessage([VerificationResult]::Failed, "SSL connection is disabled.");
        }
      }
      catch{

      }
      #return
      return $controlResult
    }

    hidden [ControlResult] CheckMySQLBCDRStatus([ControlResult] $controlResult)
    {
      try{
        if([Helpers]::CheckMember($this.ResourceObject, "StorageProfile.backupRetentionDays")){
          $backupDays = $this.ResourceObject.properties.StorageProfile.backupRetentionDays

          #checking ssl is enabled or disabled
          if($backupDays -eq 35)
          {
            $controlResult.AddMessage([VerificationResult]::Passed, "Backup is enabled.");
          }
          else 
          {
            $controlResult.AddMessage([VerificationResult]::Failed, "Backup is disabled.");
          }
        }
        else{
          $controlResult.AddMessage([VerificationResult]::Failed, "Backup is disabled.");
        }
        
      }
      catch{

      }
      #return
      return $controlResult
    }
	
    hidden [ControlResult] CheckMySQLServerVnetRules([ControlResult] $controlResult)
    {
      $uri=[system.string]::Format($this.ResourceAppIdURI+"/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforMySQL/servers/{2}/virtualNetworkRules/VnetRule?api-version=2017-12-01",$this.SubscriptionContext.SubscriptionId,$this.ResourceContext.ResourceGroupName,$this.ResourceContext.ResourceName)      
      try

      {
        $response = [WebRequestHelper]::InvokeWebRequest( $uri, $this.headers); 
      }

      catch
      {
        $controlResult.AddMessage([VerificationResult]::Manual, "Add message.");
      }
      return $controlResult

    }

    hidden [ControlResult] CheckMySQLServerATP([ControlResult] $controlResult)
    {
      $uri=[system.string]::Format($this.ResourceAppIdURI+"/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforMySQL/servers/{2}/securityAlertPolicies/Default?api-version=2017-12-01",$this.SubscriptionContext.SubscriptionId,$this.ResourceContext.ResourceGroupName,$this.ResourceContext.ResourceName)      
      try

      {
        $response = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $this.headers, $null); 
        if([Helpers]::CheckMember($response[0], "properties.state")){
          if($response[0].properties.state.ToLower() -eq "enabled"){
            $controlResult.AddMessage([VerificationResult]::Passed, "Advanced threat protection is enabled.");
          }
          else{
            $controlResult.AddMessage([VerificationResult]::Failed, "Advanced threat protection is disabled.");
          }
        }
      }

      catch
      {
        $controlResult.AddMessage(($_.Exception).Message);
      }
      return $controlResult

    }

    hidden [ControlResult] CheckMySQLFirewallAccessAzureService([ControlResult] $controlResult)
    {
      $uri=[system.string]::Format($this.ResourceAppIdURI+"/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforMySQL/servers/{2}/firewallRules/AllowAllWindowsAzureIps?api-version=2017-12-01",$this.SubscriptionContext.SubscriptionId,$this.ResourceContext.ResourceGroupName,$this.ResourceContext.ResourceName)      
      try
      {
        $response = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $this.headers, $null); 
        if($null -ne $response){
          if([Helpers]::CheckMember($response[0], "name")){
            if($response[0].name.ToLower() -eq "allowallwindowsazureips"){
              $controlResult.AddMessage([VerificationResult]::Verify, "Setting 'Allow Access to Azure Services' is enabled. Please verify if your scenario really requires it.");
            }
            else{
              $controlResult.AddMessage([VerificationResult]::Passed, "Setting 'Allow Access to Azure Services' is disabled.");
            }
          }
        }
        else{
          $controlResult.AddMessage([VerificationResult]::Passed, "Setting 'Allow Access to Azure Services' is disabled.");
        }
      }
      catch
      {
        if(([Helpers]::CheckMember($_.Exception,"ExceptionType") -and  ($_.Exception).ExceptionType.ToString().ToLower() -eq "invalidoperation")){
          $controlResult.AddMessage([VerificationResult]::Passed, "Setting 'Allow Access to Azure Services' is disabled.");
        }    
      }
      return $controlResult
    }

}
