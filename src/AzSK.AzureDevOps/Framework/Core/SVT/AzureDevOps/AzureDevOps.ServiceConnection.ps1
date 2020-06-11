Set-StrictMode -Version Latest
class ServiceConnection: ADOSVTBase
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

        $projectObj = $null;

        # Get security namespace identifier of service endpoints.
        $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
        $securityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $this.SecurityNamespaceId = ($securityNamespacesObj | Where-Object { ($_.Name -eq "ServiceEndpoints")}).namespaceId

        $securityNamespacesObj = $null;

        # Get service connection details https://dev.azure.com/{organization}/{project}/_admin/_services 
        $this.ServiceEndpointsObj = $this.ResourceContext.ResourceDetails

        if(($this.ServiceEndpointsObj | Measure-Object).Count -eq 0)
        {
            throw [SuppressedException] "Unable to find active service connection(s) under [$($this.ResourceContext.ResourceGroupName)] project."
        }
    }

    hidden [ControlResult] CheckServiceConnectionAccess([ControlResult] $controlResult)
	{
        if([Helpers]::CheckMember($this.ServiceEndpointsObj, "data.scopeLevel"))
        {
            if($this.ServiceEndpointsObj.data.scopeLevel -eq "Subscription" )
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        "Service connection is configured at subscription scope.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Passed,
                                        "Service connection is configured at resource group scope.");
            }
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Verify,
                                        "Service connection details not found. Verify connection access is configured at resource group scope.");
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
                                                "Classic service connection detected.");
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                                "Classic service connection not detected.");
            }
        }
        else{
            $controlResult.AddMessage([VerificationResult]::Manual,
                                                "Service connection type could not be detetcted.");
        }
        return $controlResult;
    }


    hidden [ControlResult] CheckSPNAuthenticationCertificate([ControlResult] $controlResult)
	{
        if([Helpers]::CheckMember($this.ServiceEndpointsObj, "authorization.parameters.authenticationType"))
        {
            if( $this.ServiceEndpointsObj.authorization.parameters.authenticationType -eq "spnKey")
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        "Service endpoint is authenticated using secret.");
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                            "Service endpoint is authenticated using certificate.");
            }
        }
        return $controlResult;
    }


    hidden [ControlResult] CheckInactiveEndpoints([ControlResult] $controlResult)
	{
        $apiURL = "https://dev.azure.com/organization/project/_apis/serviceendpoint/$($this.ServiceEndpointsObj.Id)/executionhistory/?api-version=4.1-preview.1"
        $serverFileContent = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

        if($serverFileContent.Count -gt 0)
        {
            if([DateTime]$serverFileContent[0].value[0].data.startTime -gt (Get-Date).AddDays(-180))
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                    "Service endpoint is authenticated using secret.");
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,
                "Service endpoint is authenticated using certificate.");
            }
        }
        $serverFileContent = $null;
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
                $controlResult.AddMessage([VerificationResult]::Failed,"Inherited permissions are enabled on service connection.");
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,"Inherited permissions are disabled on service connection.");
            }
            
            $Endpoint = $null; 
            $responseObj = $null; 
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
            $apiURL = "https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.serviceendpointrole/roleassignments/resources/{1}_{2}" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId),$($this.ServiceEndpointsObj.id);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            $restrictedGroups = @();
            $restrictedGlobalGroupsForSerConn = $this.ControlSettings.ServiceConnection.RestrictedGlobalGroupsForSerConn;

            if((($responseObj | Measure-Object).Count -gt 0) -and [Helpers]::CheckMember($responseObj,"identity"))
            {
                # match all the identities added on service connection with defined restricted list
                $restrictedGroups = $responseObj.identity | Where-Object { $restrictedGlobalGroupsForSerConn -contains $_.displayName.split('\')[-1] } | select displayName

                # fail the control if restricted group found on service connection
                if($restrictedGroups)
                {
                    $controlResult.AddMessage([VerificationResult]::Failed,"Do not grant global groups access to service connections. Granting elevated permissions to these groups can risk exposure of service connections to unwarranted individuals.");
                    $controlResult.AddMessage("Global groups that have access to service connection.",$restrictedGroups)
                    $controlResult.SetStateData("Global groups that have access to service connection",$restrictedGroups)
                }
                else{
                    $controlResult.AddMessage([VerificationResult]::Passed,"No global groups have access to service connection.");
                }
            }
            $responseObj = $null;
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
        $failMsg = $null
        try
        {
            $isBuildSvcAccGrpFound = $false
            $apiURL = "https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.serviceendpointrole/roleassignments/resources/{1}_{2}" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId),$($this.ServiceEndpointsObj.id);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

            if((($responseObj | Measure-Object).Count -gt 0) -and [Helpers]::CheckMember($responseObj,"identity"))
            {
                foreach ($identity in $responseObj.identity)
                {
                    if ($identity.uniqueName -like '*Project Collection Build Service Accounts') 
                    {
                        $isBuildSvcAccGrpFound = $true;
                        break;
                    }
                }
                #Faile the control if prj coll Buil Ser Acc Group Found added on serv conn
                if($isBuildSvcAccGrpFound -eq $true)
                {
                    $controlResult.AddMessage([VerificationResult]::Failed,"Do not grant 'Project Collection Build Service Account' groups access to service connections.");
                }
                else{
                    $controlResult.AddMessage([VerificationResult]::Passed,"'Project Collection Build Service Account' is not granted access to the service connection.");
                }
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Passed,"'Project Collection Build Service Account' does not have access to service connection.");
            }
            $responseObj = $null;
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
               $responseObj = $null;
           }
        catch {
            $controlResult.AddMessage([VerificationResult]::Manual,"Unable to fetch service connection details. $($_) Please verify from portal that you are not granting all pipeline access to service connections");
        }
         
        return $controlResult;
    }

    hidden [ControlResult] CheckServiceConnectionForPATOrAuth([ControlResult] $controlResult)
    {
        if([Helpers]::CheckMember($this.ServiceEndpointsObj, "authorization.scheme"))
        {
            if( $this.ServiceEndpointsObj.authorization.scheme -eq "OAuth")
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Service connection $($this.ServiceEndpointsObj.name) is authenticated via $($this.ServiceEndpointsObj.authorization.scheme)");
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Failed, "Service connection $($this.ServiceEndpointsObj.name) is authenticated via $($this.ServiceEndpointsObj.authorization.scheme)");
            }
        }
        return $controlResult;
    }

}