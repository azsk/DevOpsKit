Set-StrictMode -Version Latest 
class ServiceConnection: SVTBase
{    
    [PSObject] $ServiceEndPointsObj = $null
    [PSObject] $projectObj = $null
    ServiceConnection([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    { 
        # Get project id
        $apiURL = "https://dev.azure.com/{0}/_apis/projects/{1}?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName), $($this.ResourceContext.ResourceGroupName);
        $this.projectObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

        # Get service connection details
        $apiURL = "https://dev.azure.com/{0}/{1}/_apis/serviceendpoint/endpoints?api-version=4.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName),$($this.ResourceContext.ResourceGroupName);
        $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
	    $this.ServiceEndPointsObj = $responseObj
    }

    hidden [ControlResult] CheckServiceConnectionAccess([ControlResult] $controlResult)
	{
       $azureRMEndpoints = $this.ServiceEndPointsObj | Where-Object { $_.type -eq "azurerm" }
       
        if(($azureRMEndpoints | Measure-Object).Count -gt 0)
        {
            $subLevelSPNList = @()
            $azureRMEndpoints| ForEach-Object{
                $Endpoint = $_
                if([Helpers]::CheckMember($Endpoint, "data.scopeLevel") )
                {
                    if($Endpoint.data.scopeLevel -eq "Subscription")
                    {
                        $AuthType = ""
                        if([Helpers]::CheckMember($Endpoint,"authorization.parameters.authenticationType"))
                        {
                            $AuthType = $Endpoint.authorization.parameters.authenticationType
                        }
                        $subLevelSPNList  += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName; AuthType=$AuthType }
                    }                 
                }
                else
                {
                  $subLevelSPNList += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName}
                }
              }
            if($subLevelSPNList.Count -eq 0 )
            {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                            "All service endpoints are configured with RG level scope");
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                            "Define RG level scope for below service endpoints",$subLevelSPNList);
            }
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                            "No AzureRM Service Endpoints found");
        }
        
        return $controlResult;
    }

    hidden [ControlResult] CheckClassConnections([ControlResult] $controlResult)
	{
       $classicEndpoints = $this.ServiceEndPointsObj | Where-Object { $_.type -eq "azure" }
       
        if(($classicEndpoints | Measure-Object).Count -gt 0)
        {
                $classicConnectionList = @()
                $classicConnectionList  += $classicEndpoints | Select-Object @{Name="EndPointName"; Expression = {$_.Name}},@{Name="Creator"; Expression = {$_.createdBy.displayName}}
                $controlResult.AddMessage([VerificationResult]::Failed,
                                            "Found below classic service endpoints",$classicConnectionList);
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                            "No Classic Endpoints found");
        }
        return $controlResult;
    }


    hidden [ControlResult] CheckSPNAuthenticationCertificate([ControlResult] $controlResult)
	{

        $azureRMEndpoints = $this.ServiceEndPointsObj | Where-Object { $_.type -eq "azurerm" }
       
        if(($azureRMEndpoints | Measure-Object).Count -gt 0)
        {
            
            $keybasedSPNList = @()

            $azureRMEndpoints | ForEach-Object{
    
                $Endpoint = $_
            
                if([Helpers]::CheckMember($Endpoint, "authorization.parameters.authenticationType"))
                {
                    $keybasedSPNList += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName; AuthType=$Endpoint.authorization.parameters.authenticationType }
                }
                else
                {
                $keybasedSPNList += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName}
                }
            }

                if($keybasedSPNList.Count -eq 0 )
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,
                                                "All Service Endpoints are Cert based authenticated");
                }
                else {
                    $controlResult.AddMessage([VerificationResult]::Failed,
                                                "Below endpoints are used with secret based auth",$keybasedSPNList);
                }
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                                "No AzureRM Service Endpoints found");
            }
        return $controlResult;
    }


    hidden [ControlResult] CheckInactiveEndpoints([ControlResult] $controlResult)
	{

        $inactiveEnpoints = @()

        $this.ServiceEndPointsObj | ForEach-Object{
  
            $Endpoint = $_
            $apiURL = "https://dev.azure.com/organization/project/_apis/serviceendpoint/$($Endpoint.Id)/executionhistory/?api-version=4.1-preview.1" 
            $serverFileContent = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

            if($serverFileContent.Count -gt 0)
            {
                if([DateTime]$serverFileContent[0].value[0].data.startTime -gt (Get-Date).AddDays(-180))
                {
                    $inactiveEnpoints += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName; LastAccessDate=$serverFileContent[0].value[0].data.startTime }
                }                
            }
          }

        if($inactiveEnpoints.Count -eq 0 )
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "All Service Endpoints are Cert based authenticated");
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                        "Below endpoints are used with secret based auth",$inactiveEnpoints);
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckRBACInheritPermissions ([ControlResult] $controlResult)
	{
        $inheritPermissionsEnabled = @()
        # Get security namespace identifier of service endpoints.
        $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
        $securityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $securityNamespaceId = ($securityNamespacesObj | Where-Object { ($_.Name -eq "ServiceEndpoints")}).namespaceId

        
        $this.ServiceEndPointsObj | ForEach-Object{
            $Endpoint = $_
            $apiURL = "https://dev.azure.com/{0}/_apis/accesscontrollists/{1}?token=endpoints/{2}/{3}&api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName),$securityNamespaceId,$($this.projectObj.id),$($Endpoint.id);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            if($responseObj.inheritPermissions -eq $true)
            {
                $inheritPermissionsEnabled += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName; inheritPermissions=$responseObj.inheritPermissions }
            }
            
        }

        if($inheritPermissionsEnabled.Count -eq 0)
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"##");
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Failed,"##");
            $controlResult.SetStateData("##", $inheritPermissionsEnabled);
        }
        return $controlResult;
    }
}