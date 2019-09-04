#using namespace Microsoft.Azure.Commands.AppService.Models
Set-StrictMode -Version Latest
class DBForPostgreSQL: AzSVTBase
{

    DBForPostgreSQL([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId, $svtResource)
    {
		  $this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
      if (-not $this.ResourceObject) {
        $this.ResourceObject = Get-AzResource -ResourceId $this.ResourceContext.ResourceId
        if(-not $this.ResourceObject)
        {
            throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
        }
      }

      return $this.ResourceObject;
    }

    hidden [ControlResult] CheckPSQLServerSSLConnection([ControlResult] $controlResult)
    {

      # Evaluate 
      $this.ResourceObject

      #Result
      $controlResult.AddMessage([VerificationResult]::Manual, "");

      #return
      return $controlResult
    }

    hidden [ControlResult] CheckPSQLServerVnetRules([ControlResult] $controlResult)
    {
      $ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()	
      $uri=[system.string]::Format($ResourceAppIdURI+"/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DBforPostgreSQL/servers/{2}/virtualNetworkRules?api-version=2017-12-01",$this.SubscriptionContext.SubscriptionId,$this.ResourceContext.ResourceGroupName,$this.ResourceContext.ResourceName)      

      try
      {
        $response = [WebRequestHelper]::InvokeGetWebRequest($uri);
      }
      catch
      {
        $controlResult.AddMessage([VerificationResult]::Manual, "Add message.");
      }

      return $controlResult
    }


}
