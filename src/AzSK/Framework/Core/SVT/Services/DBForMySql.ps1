Set-StrictMode -Version Latest
class DBForMySql: AzSVTBase
{
  hidden [PSObject[]] $MySqlFirewallDetails = $null;
  
	hidden [PSObject] $ResourceObject;
    DBForMySql([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
	   
		$this.GetResourceObject();
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
      
      #Fetching ssl Object
      $ssl_option = $this.ResourceObject.properties.sslEnforcement
      #checking ssl is enabled or disabled
      if($ssl_option -eq 'Enabled')
      {
        $controlResult.AddMessage([VerificationResult]::Passed, "SSL connection is enabled.");
      }
      else 
      {
        $controlResult.AddMessage([VerificationResult]::Failed, "SSL connection is disabled.");
      }
      #return
      return $controlResult
    }

	
    hidden [ControlResult] CheckMySQLServerVnetRules([ControlResult] $controlResult)
    {
      $ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()	
      $AccessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
      $header = "Bearer " + $AccessToken
      $headers = @{"Authorization"=$header;"Content-Type"="application/json";}
      $uri=[system.string]::Format($ResourceAppIdURI+"/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforMySQL/servers/{2}/virtualNetworkRules/VnetRule?api-version=2017-12-01",$this.SubscriptionContext.SubscriptionId,$this.ResourceContext.ResourceGroupName,$this.ResourceContext.ResourceName)      
      try

      {
        $response = [WebRequestHelper]::InvokeWebRequest( $uri, $headers); 
      }

      catch
      {
        $controlResult.AddMessage([VerificationResult]::Manual, "Add message.");
      }
      return $controlResult

    }

    hidden [ControlResult] CheckMySQLServerATP([ControlResult] $controlResult)
    {
      $ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()	
      $AccessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
      $header = "Bearer " + $AccessToken
      $headers = @{"Authorization"=$header;"Content-Type"="application/json";}
      $uri=[system.string]::Format($ResourceAppIdURI+"/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforMySQL/servers/{2}/securityAlertPolicies/Default?api-version=2017-12-01",$this.SubscriptionContext.SubscriptionId,$this.ResourceContext.ResourceGroupName,$this.ResourceContext.ResourceName)      
      try

      {
        $response = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $headers, $null); 
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
        $controlResult.AddMessage([VerificationResult]::Verify, "Add message.");
      }
      return $controlResult

    }

}
