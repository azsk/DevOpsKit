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

        # Get service connection details https://dev.azure.com/{organization}/{project}/_admin/_services 
        $this.ServiceEndpointsObj = $this.ResourceContext.ResourceDetails

        if(($this.ServiceEndpointsObj | Measure-Object).Count -eq 0)
        {
            throw [SuppressedException] "Unable to find active service connection(s) under [$($this.ResourceContext.ResourceGroupName)] project."
        }
    }

    hidden [ControlResult] CheckServiceConnectionAccess([ControlResult] $controlResult)
	{
        $Endpoint = $this.ServiceEndpointsObj
        if([Helpers]::CheckMember($Endpoint, "data.scopeLevel") )
        {
            if($Endpoint.data.scopeLevel -eq "Subscription")
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        "Define RG level scope for below service endpoints");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Passed,
                                        "Service endpoints is configured with RG level scope");
            }
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Verify,
                                        "Service endpoint details not found. Verify connection access is scoped at RG level");
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckClassConnections([ControlResult] $controlResult)
	{
        if([Helpers]::CheckMember($this.ServiceEndpointsObj,"type"))
        {
            if($this.ServiceEndpointsObj.type -eq "azure")
            {
                    $controlResult.AddMessage([VerificationResult]::Failed,
                                                "Found below classic service endpoints");
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                                "No Classic Endpoint found");
            }
        }
        else{
            $controlResult.AddMessage([VerificationResult]::Manual,
                                                "Connection type not found");
        }
        return $controlResult;
    }


    hidden [ControlResult] CheckSPNAuthenticationCertificate([ControlResult] $controlResult)
	{
        $Endpoint = $this.ServiceEndpointsObj 
        if([Helpers]::CheckMember($Endpoint, "authorization.parameters.authenticationType"))
        {
            if( $Endpoint.authorization.parameters.authenticationType -eq "spnKey")
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        "Endpoint is used with secret based auth");
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                            "Service Endpoints is Cert based authenticated");
            }
        }
        return $controlResult;
    }


    hidden [ControlResult] CheckInactiveEndpoints([ControlResult] $controlResult)
	{

        $Endpoint = $this.ServiceEndpointsObj
        $apiURL = "https://dev.azure.com/organization/project/_apis/serviceendpoint/$($Endpoint.Id)/executionhistory/?api-version=4.1-preview.1"
        $serverFileContent = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

        if($serverFileContent.Count -gt 0)
        {
            if([DateTime]$serverFileContent[0].value[0].data.startTime -gt (Get-Date).AddDays(-180))
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                    "Endpoint used with secret based auth");
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,
                "Endpoint used with Cert based authenticated");
            }
        }
          
        return $controlResult;
    }

    hidden [ControlResult] CheckRBACInheritPermissions ([ControlResult] $controlResult)
	{
        $failMsg = $null
        try
        {
            $Endpoint = $this.ServiceEndpointsObj
            $apiURL = "https://dev.azure.com/{0}/_apis/accesscontrollists/{1}?token=endpoints/{2}/{3}&api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName),$($this.SecurityNamespaceId),$($this.ProjectId),$($Endpoint.id);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            if(($responseObj | Measure-Object).Count -eq 0)
            {
                $inheritPermissionsEnabled += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName; inheritPermissions="Unable to fetch permissions inheritance details." }
            }
            elseif([Helpers]::CheckMember($responseObj,"inheritPermissions") -and $responseObj.inheritPermissions -eq $true)
            {
                $controlResult.AddMessage([VerificationResult]::Failed,"Found service connection with inherit permissions turned ON.");
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,"");
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
        try
        {
            $Endpoint = $this.ServiceEndpointsObj
            $IsGlobalSecurityGroupPermitted = $false
            $apiURL = "https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.serviceendpointrole/roleassignments/resources/{1}_{2}" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId),$($Endpoint.id);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            $nonCompliantIdentities = @();
            if((($responseObj | Measure-Object).Count -gt 0) -and [Helpers]::CheckMember($responseObj,"identity"))
            {
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
                    $controlResult.AddMessage([VerificationResult]::Failed,"Do not grant global security groups access to service connections. Granting elevated permissions to these groups can risk exposure of service connections to unwarranted individuals.");
                    $controlResult.AddMessage("List of service connections granting access to global security groups:",$nonCompliantIdentities)
                }
                else{
                    $controlResult.AddMessage([VerificationResult]::Passed,"");
                }
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

    


    hidden [ControlResult] CheckBuildServiceAccountAccess([ControlResult] $controlResult)
	{
        # Any identity other than teams identity needs to be verified manually as it's details cannot be retrived using API
        $failMsg = $null
        try
        {
            $Endpoint = $this.ServiceEndpointsObj
            $IsGlobalSecurityGroupPermitted = $false
            $apiURL = "https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.serviceendpointrole/roleassignments/resources/{1}_{2}" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId),$($Endpoint.id);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            $nonCompliantIdentities = @();
            if((($responseObj | Measure-Object).Count -gt 0) -and [Helpers]::CheckMember($responseObj,"identity"))
            {
                $responseObj.identity | ForEach-Object {
                    $identity = $_
                    try
                    {
                        if ($responseObj.identity.uniqueName -contains 'Project Collection Build Service') {
                             $IsGlobalSecurityGroupPermitted = $true;
                            }
                      # $apiURL = "https://vssps.dev.azure.com/e/Microsoft/_apis/Identities/{0}" -f $($identity.id)
                      # $identityObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                      # if(($identityObj | Measure-Object).Count -gt 0 ) {
                      #     $IsGroup = [Helpers]::CheckMember($identityObj,"Properties.SchemaClassName") -and ($identityObj.Properties.SchemaClassName -eq "Group")
                      #     $IsGlobalSecurityGroup = [Helpers]::CheckMember($identityObj,"Properties.ScopeName") -and `
                      #                             (($identityObj.Properties.ScopeName -eq $($this.ResourceContext.ResourceGroupName)) -or ($identityObj.Properties.ScopeName -eq $($this.SubscriptionContext.SubscriptionName)))
                      #     $IsWhitelisted = ($this.ControlSettings.ServiceConnection.WhitelistedGroupIdentities -contains $identityObj.Properties.Account)
                      #     if($IsGroup -and $IsGlobalSecurityGroup -and (-not $IsWhitelisted))
                      #     {
                      #         $IsGlobalSecurityGroupPermitted = $true
                      #         $nonCompliantIdentities += $identity
                      #     }
                      # }
                    }
                    catch
                    {
                        $otherIdentities += @{ ServiceConnectionName = $($Endpoint.name); Identity = $($identity)}
                    }
                }
                if($IsGlobalSecurityGroupPermitted -eq $true)
                {
                    $controlResult.AddMessage([VerificationResult]::Failed,"Do not grant global security groups access to service connections. Granting elevated permissions to these groups can risk exposure of service connections to unwarranted individuals.");
                    $controlResult.AddMessage("List of service connections granting access to global security groups:",$nonCompliantIdentities)
                }
                else{
                    $controlResult.AddMessage([VerificationResult]::Passed,"");
                }
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

    hidden [ControlResult] CheckServiceConnectionBuildAccess([ControlResult] $controlResult)
    {
        try
           {
               $apiURL = "https://dev.azure.com/{0}/{1}/_apis/pipelines/pipelinePermissions/endpoint/{2}?api-version=5.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName),$($this.ProjectId),$($this.ServiceEndpointsObj.id) ;
               $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

               if([Helpers]::CheckMember($responseObj,"allPipelines")) {
                   if($responseObj.allPipelines.authorized){
                      $controlResult.AddMessage([VerificationResult]::Failed,"Do not grant global security access to all pipeline.");
                   } 
                   else {
                      $controlResult.AddMessage([VerificationResult]::Passed,"Service connection is not granted access to all pipeline");
                   }             
                }
               else {
                $controlResult.AddMessage([VerificationResult]::Passed, "Service connection is not granted access to all pipeline");
               }
           }
        catch {
            $controlResult.AddMessage([VerificationResult]::Manual,"Unable to fetch service connection details. $($_) Please verify from portal that you are not granting all pipeline access to service connections");
        }
         
        return $controlResult;
    }

    hidden [ControlResult] CheckServiceConnectionForPATOrAuth([ControlResult] $controlResult)
    {
        $Endpoint = $this.ServiceEndpointsObj 
        if([Helpers]::CheckMember($Endpoint, "authorization.scheme"))
        {
            if( $Endpoint.authorization.scheme -eq "OAuth")
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Service connection $($Endpoint.name) is authenticated via $($Endpoint.authorization.scheme)");
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Failed, "Service connection $($Endpoint.name) is authenticated via $($Endpoint.authorization.scheme)");
            }
        }
        return $controlResult;
    }

}