Set-StrictMode -Version Latest 
class ServiceConnection: SVTBase
{    
    hidden [PSObject] $ServiceEndpointsObj = $null;
    hidden [string] $SecurityNamespaceId;
    hidden [PSObject] $ProjectId;

    ServiceConnection([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    { 
        # Get project id
        $apiURL = "https://dev.azure.com/{0}/_apis/projects/{1}?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName), $($this.ResourceContext.ResourceGroupName);
        $projectObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $this.ProjectId = $projectObj.id

        # Get security namespace identifier of service endpoints.
        $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
        $securityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $this.SecurityNamespaceId = ($securityNamespacesObj | Where-Object { ($_.Name -eq "ServiceEndpoints")}).namespaceId

        # Get service connection details
        $apiURL = "https://dev.azure.com/{0}/{1}/_apis/serviceendpoint/endpoints?api-version=4.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName),$($this.ResourceContext.ResourceGroupName);
        $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $this.ServiceEndpointsObj = $responseObj

        if(($this.ServiceEndpointsObj | Measure-Object).Count -eq 0)
        {
            throw [SuppressedException] "Unable to find active service connection(s) under [$($this.ResourceContext.ResourceGroupName)] project."
        }
    }

    hidden [ControlResult] CheckServiceConnectionAccess([ControlResult] $controlResult)
	{
       $azureRMEndpoints = $this.ServiceEndpointsObj | Where-Object { $_.type -eq "azurerm" }
       
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
                  $subLevelSPNList += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName; AuthType="NotAvailable"}
                }
              }
            if($subLevelSPNList.Count -eq 0 )
            {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                            "All service endpoints are configured with RG level scope");
            }
            else {
                
                $subLevelSPNList = ($subLevelSPNList | Select-Object -Property @{Name="EndPointName"; Expression = {$_.EndPointName}},@{Name="Creator"; Expression = {$_.Creator}},@{Name="AuthType"; Expression = {$_.AuthType}})
                $controlResult.AddMessage([VerificationResult]::Failed,
                                            "Define RG level scope for below service endpoints", $subLevelSPNList );
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
       $classicEndpoints = $this.ServiceEndpointsObj | Where-Object { $_.type -eq "azure" }
       
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

        $azureRMEndpoints = $this.ServiceEndpointsObj | Where-Object { $_.type -eq "azurerm" }
       
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
                $keybasedSPNList += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName; AuthType= "Not Available"}
                }
            }

                if($keybasedSPNList.Count -eq 0 )
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,
                                                "All Service Endpoints are Cert based authenticated");
                }
                else {
                    $keybasedSPNList = ($keybasedSPNList | Select-Object -Property @{Name="EndPointName"; Expression = {$_.EndPointName}},@{Name="Creator"; Expression = {$_.Creator}},@{Name="AuthType"; Expression = {$_.AuthType}})
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

        $this.ServiceEndpointsObj | ForEach-Object{
  
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
        $failMsg = $null
        $inheritPermissionsEnabled = @()
        try
        {
            if(![string]::IsNullOrEmpty($this.SecurityNamespaceId) -and ![string]::IsNullOrEmpty($this.ProjectId))
            {
                $this.ServiceEndpointsObj | ForEach-Object{
                    $Endpoint = $_
                    $apiURL = "https://dev.azure.com/{0}/_apis/accesscontrollists/{1}?token=endpoints/{2}/{3}&api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName),$($this.SecurityNamespaceId),$($this.ProjectId),$($Endpoint.id);
                    $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                    if(($responseObj | Measure-Object).Count -eq 0)
                    {
                        $inheritPermissionsEnabled += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName; inheritPermissions="Unable to fetch permissions inheritance details." }
                    }
                    elseif([Helpers]::CheckMember($responseObj,"inheritPermissions") -and $responseObj.inheritPermissions -eq $true)
                    {
                        $inheritPermissionsEnabled += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName; inheritPermissions=$responseObj.inheritPermissions }
                    }     
                }

                if($inheritPermissionsEnabled.Count -eq 0)
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,"");
                }
                else
                {
                    $inheritPermissionsEnabled = $inheritPermissionsEnabled | Select-Object -Property @{Name="EndPointName"; Expression = {$_.EndPointName}},@{Name="Creator"; Expression = {$_.Creator}},@{Name="inheritPermissions"; Expression = {$_.inheritPermissions}}
                    $controlResult.AddMessage([VerificationResult]::Failed,"Found service connection(s) with inherit permissions turned ON.",$inheritPermissionsEnabled);
                    $controlResult.SetStateData("List of non-compliant service connections:", $inheritPermissionsEnabled);
                }
            }
            else
            {
                $failMsg = "One of the variables 'SecurityNamespaceId' and 'ProjectId' do not contain any string. "
            } 
        }
        catch {
            $failMsg = $_
        }
        
        if(![string]::IsNullOrEmpty($failMsg))
        {
            $controlResult.AddMessage([VerificationResult]::Manual,"Unable to fetch service connections details. $($failMsg)Please verify from portal that permission inheritance is turned OFF for all the service connections");
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckGlobalGroupsAddedToServiceConnections ([ControlResult] $controlResult)
	{
        # Any identity other than teams identity needs to be verified manually as it's details cannot be retrived using API
        $failMsg = $null
        $otherIdentities = @()
        $nonCompliantServiceConnection = @()
        try
        {
            if(![string]::IsNullOrEmpty($this.ProjectId))
            {
                $nonCompliantServiceConnection = $this.ServiceEndpointsObj | ForEach-Object{
                    $Endpoint = $_
                    $IsGlobalSecurityGroupPermitted = $false
                    $apiURL = "https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.serviceendpointrole/roleassignments/resources/{1}_{2}" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId),$($Endpoint.id);
                    $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                    if((($responseObj | Measure-Object).Count -gt 0) -and [Helpers]::CheckMember($responseObj,"identity"))
                    {
                        $nonCompliantIdentities = @()
                        $responseObj.identity | ForEach-Object {
                            $identity = $_
                            try
                            {
                                $apiURL = "https://vssps.dev.azure.com/e/Microsoft/_apis/Identities/{0}" -f $($identity.id)
                                $identityObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                                if(($identityObj | Measure-Object).Count -gt 0 ) {                        
                                    $IsGroup = [Helpers]::CheckMember($identityObj,"Properties.SchemaClassName") -and ($identityObj.Properties.SchemaClassName -eq "Group")
                                    $IsGlobalSecurityGroup = [Helpers]::CheckMember($identityObj,"Properties.ScopeName") -and `
                                                            (($identityObj.Properties.ScopeName -eq $($this.ResourceContext.ResourceGroupName)) -or ($identityObj.Properties.ScopeName -eq $($this.SubscriptionContext.SubscriptionName)))
                                    $IsWhitelisted = ($this.ControlSettings.ServiceConnection.WhitelistedGroupIdentities -contains $identityObj.Properties.Account)
                                    if($IsGroup -and $IsGlobalSecurityGroup -and (-not $IsWhitelisted))
                                    {
                                        $IsGlobalSecurityGroupPermitted = $true
                                        $nonCompliantIdentities += $identity
                                    }
                                }
                            }
                            catch
                            {
                                $otherIdentities += @{ ServiceConnectionName = $($Endpoint.name); Identity = $($identity)}
                            }
                        }
        
                        if($IsGlobalSecurityGroupPermitted -eq $true)
                        {
                            return @{ ServiceConnectionName = $($Endpoint.name); Identities = $($nonCompliantIdentities)}
                        }
                        
                        
                    }
                    else
                    {
                        return @{ ServiceConnectionName = $($Endpoint.name); Identities = "Unable to fetch permissions of this service connection."}
                    }
                    
                }

                if ((($nonCompliantServiceConnection | Measure-Object).Count -eq 0) -and (($otherIdentities| Measure-Object).Count -eq 0))
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,"");
                }
                elseif ((($nonCompliantServiceConnection | Measure-Object).Count -eq 0) -and (($otherIdentities| Measure-Object).Count -ne 0))
                {
                    #$otherIdentities = 
                    $otherIdentities = ($otherIdentities | Select-Object -Property @{Name="ServiceConnectionName"; Expression = {$_.ServiceConnectionName}},@{Name="Identity"; Expression = {$_.Identity}})
                    $controlResult.AddMessage([VerificationResult]::Verify , "Unable to verify identity type. Please validate that following identities do not grant access to unwarranted individuals.",$otherIdentities);
                    #$controlResult.SetStateData("List of unverified group identities:", $otherIdentities);
                }
                else
                {
                    #$nonCompliantServiceConnection = ($nonCompliantServiceConnection | Select-Object -Property @{Name="ServiceConnectionName"; Expression = {$_.ServiceConnectionName}},@{Name="Identity"; Expression = {$_.Identity}})
                    $controlResult.AddMessage([VerificationResult]::Failed,"Do not grant global security groups access to service connections. Granting elevated permissions to these groups can risk exposure of service connections to unwarranted individuals.");
                    $controlResult.AddMessage("List of service connections granting access to global security groups:",$nonCompliantServiceConnection)
                    #$controlResult.SetStateData("List of non-compliant service connections:", $nonCompliantServiceConnection);
                    if(($otherIdentities| Measure-Object).Count -ne 0)
                    {
                        $controlResult.AddMessage("Unable to verify identity type. Please validate that following identities do not grant access to unwarranted individuals.");
                        $controlResult.AddMessage($otherIdentities);
                    } 
                }
            }
            else
            {
                $failMsg = "The variables 'ProjectId' do not contain any string. "
            }
        }
        catch {
            $failMsg = $_
        }
        
        if(![string]::IsNullOrEmpty($failMsg))
        {
            $controlResult.AddMessage([VerificationResult]::Manual,"Unable to fetch service connections details. $($failMsg)Please verify from portal that you are not granting global security groups access to service connections");
        }
        return $controlResult;
    }
}