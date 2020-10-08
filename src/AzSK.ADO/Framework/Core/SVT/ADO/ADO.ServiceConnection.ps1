Set-StrictMode -Version Latest
class ServiceConnection: ADOSVTBase
{
    hidden [PSObject] $ServiceEndpointsObj = $null;
    hidden static [string] $SecurityNamespaceId = $null;
    hidden [PSObject] $ProjectId;
    hidden [PSObject] $ServiceConnEndPointDetail = $null;
    hidden [PSObject] $pipelinePermission = $null;
    hidden [PSObject] $serviceEndPointIdentity = $null;

    ServiceConnection([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource)
    {
        # Get project id 
        $this.ProjectId = ($this.ResourceContext.ResourceDetails.ResourceLink -split $this.SubscriptionContext.SubscriptionName)[1].split("/")[1];

        # Get security namespace identifier of service endpoints.
        if([string]::IsNullOrEmpty([ServiceConnection]::SecurityNamespaceId))
        {
            $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
            $securityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            [ServiceConnection]::SecurityNamespaceId = ($securityNamespacesObj | Where-Object { ($_.Name -eq "ServiceEndpoints")}).namespaceId
    
            $securityNamespacesObj = $null;
        }

        # Get service connection details https://dev.azure.com/{organization}/{project}/_admin/_services 
        $this.ServiceEndpointsObj = $this.ResourceContext.ResourceDetails

        if(($this.ServiceEndpointsObj | Measure-Object).Count -eq 0)
        {
            throw [SuppressedException] "Unable to find active service connection(s) under [$($this.ResourceContext.ResourceGroupName)] project."
        }

        try {
            $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName)
            $sourcePageUrl = "https://{0}.visualstudio.com/{1}/_settings/adminservices" -f $($this.SubscriptionContext.SubscriptionName), $this.ResourceContext.ResourceGroupName;
            $inputbody = "{'contributionIds':['ms.vss-serviceEndpoints-web.service-endpoints-details-data-provider'],'dataProviderContext':{'properties':{'serviceEndpointId':'$($this.ServiceEndpointsObj.id)','projectId':'$($this.projectId)','sourcePage':{'url':'$($sourcePageUrl)','routeId':'ms.vss-admin-web.project-admin-hub-route','routeValues':{'project':'$($this.ResourceContext.ResourceGroupName)','adminPivot':'adminservices','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
    
            $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody); 
            if([Helpers]::CheckMember($responseObj, "dataProviders") -and $responseObj.dataProviders."ms.vss-serviceEndpoints-web.service-endpoints-details-data-provider")
            {
                $this.ServiceConnEndPointDetail = $responseObj.dataProviders."ms.vss-serviceEndpoints-web.service-endpoints-details-data-provider"
            }
        }
        catch {
            
        }
    }

    hidden [ControlResult] CheckServiceConnectionAccess([ControlResult] $controlResult)
	{
        if ($this.ServiceEndpointsObj.type -eq "azurerm") 
        {
            try {
                if($this.ServiceConnEndPointDetail -and [Helpers]::CheckMember($this.ServiceConnEndPointDetail, "serviceEndpoint") ) 
                {
                    $serviceEndPoint = $this.ServiceConnEndPointDetail.serviceEndpoint
                    # 'scopeLevel' and 'creationMode' properties are required to determine whether a svc conn is automatic or manual.
                    # irrespective of creationMode - pass the control for conn authorized at MLWorkspace and PublishProfile (app service) scope as such conn are granted access at resource level.
                    if(([Helpers]::CheckMember($serviceEndPoint, "data.scopeLevel") -and ([Helpers]::CheckMember($serviceEndPoint.data, "creationMode")) -or (([Helpers]::CheckMember($serviceEndPoint, "data.scopeLevel") -and $serviceEndPoint.data.scopeLevel -eq "AzureMLWorkspace")  -or ([Helpers]::CheckMember($serviceEndPoint, "authorization.scheme") -and $serviceEndPoint.authorization.scheme -eq "PublishProfile") )))
                    {
                        #If Service connection creation mode is 'automatic' and scopeLevel is subscription and no resource group is defined in its access definition -> conn has subscription level access -> fail the control, 
                        #else pass the control if scopeLevel is 'Subscription' and 'scope' is RG  (note scope property is visible, only if conn is authorized to an RG)
                        #Fail the control if it has access to management group (last condition)
                        if(($serviceEndPoint.data.scopeLevel -eq "Subscription" -and $serviceEndPoint.data.creationMode -eq "Automatic" -and !([Helpers]::CheckMember($serviceEndPoint.authorization.parameters,"scope") )) -or ($serviceEndPoint.data.scopeLevel -eq "ManagementGroup"))
                        {
                            $controlFailedMsg = "Service connection has access at [$($serviceEndPoint.data.subscriptionName)] subscription scope."
                            if ($serviceEndPoint.data.scopeLevel -eq "ManagementGroup") {
                                $controlFailedMsg = "Service connection has access at [$($serviceEndPoint.data.managementGroupName)] management group scope."
                            }
                            $controlResult.AddMessage([VerificationResult]::Failed, $controlFailedMsg);
                        }
                        else{
                            $message = "Service connection has access at [{0}] {1} scope in the subscription [$($serviceEndPoint.data.subscriptionName)] .";
                            if ($serviceEndPoint.data.scopeLevel -eq "AzureMLWorkspace") 
                            {
                                $message =  $message -f $serviceEndPoint.data.mlWorkspaceName, 'ML workspace'
                            }
                            elseif ($serviceEndPoint.authorization.scheme -eq "PublishProfile") {
                                $message =  $message -f $serviceEndPoint.data.resourceId.split('/')[-1], 'app service'
                            }
                            elseif ([Helpers]::CheckMember($serviceEndPoint.authorization.parameters, "scope")) {
                                $message =  $message -f $serviceEndPoint.authorization.parameters.scope.split('/')[-1], 'resource group'
                            }
                            else {
                                $message = "Service connection is not configured at subscription scope."
                            }
                            $controlResult.AddMessage([VerificationResult]::Passed, $message);
                        }
                    }
                    else  # if creation mode is manual and type is other (eg. managed identity) then verify the control
                    {
                        $controlResult.AddMessage([VerificationResult]::Verify, "Access scope of service connection can not be verified as it is not an 'automatic' service prinicipal.");
                    }
                }
                else
                {
                    $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the service connection details.");
                }
            }
            catch {
                $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch the service connection details.");
            }
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Manual,"Access scope of service connections of type other than 'Azure Resource Manager' can not be verified.");
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

    hidden [ControlResult] CheckInheritedPermissions ([ControlResult] $controlResult)
	{
        $failMsg = $null
        try
        {
            $Endpoint = $this.ServiceEndpointsObj
            $apiURL = "https://dev.azure.com/{0}/_apis/accesscontrollists/{1}?token=endpoints/{2}/{3}&api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName),$([ServiceConnection]::SecurityNamespaceId),$($this.ProjectId),$($Endpoint.id);
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
            if ($null -eq $this.serviceEndPointIdentity) {
                $apiURL = "https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.serviceendpointrole/roleassignments/resources/{1}_{2}" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId),$($this.ServiceEndpointsObj.id);
                $this.serviceEndPointIdentity = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            }
            $restrictedGroups = @();
            
            if ($this.ControlSettings -and [Helpers]::CheckMember($this.ControlSettings, "ServiceConnection.RestrictedGlobalGroupsForSerConn") ) 
            {
                $restrictedGlobalGroupsForSerConn = $this.ControlSettings.ServiceConnection.RestrictedGlobalGroupsForSerConn;
                if((($this.serviceEndPointIdentity[0] | Measure-Object).Count -gt 0) -and [Helpers]::CheckMember($this.serviceEndPointIdentity[0],"identity"))
                {
                    # match all the identities added on service connection with defined restricted list
                    $restrictedGroups = $this.serviceEndPointIdentity[0].identity | Where-Object { $restrictedGlobalGroupsForSerConn -contains $_.displayName.split('\')[-1] } | select displayName
    
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
                else {
                    $controlResult.AddMessage([VerificationResult]::Passed,"No global groups have access to service connection.");
                }
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Manual,"List of restricted global groups for service connection is not defined in your organization policy. Please update your ControlSettings.json as per the latest AzSK.ADO PowerShell module.");
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
        $failMsg = $null
        try
        {
            $isBuildSvcAccGrpFound = $false
            if ($null -eq $this.serviceEndPointIdentity) {
                $apiURL = "https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.serviceEndPointrole/roleassignments/resources/{1}_{2}" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId),$($this.ServiceEndpointsObj.id);
                $this.serviceEndPointIdentity = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            }
            if((($this.serviceEndPointIdentity | Measure-Object).Count -gt 0) -and [Helpers]::CheckMember($this.serviceEndPointIdentity[0],"identity"))
            {
                foreach ($identity in $this.serviceEndPointIdentity[0].identity)
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
            if ($null -eq $this.pipelinePermission) {
               $apiURL = "https://dev.azure.com/{0}/{1}/_apis/pipelines/pipelinePermissions/endpoint/{2}?api-version=5.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName),$($this.ProjectId),$($this.ServiceEndpointsObj.id) ;
               $this.pipelinePermission = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            }
            if([Helpers]::CheckMember($this.pipelinePermission,"allPipelines")) {
                if($this.pipelinePermission.allPipelines.authorized){
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

    hidden [ControlResult] CheckInactiveConnection([ControlResult] $controlResult)
	{             
        try
        {
            if ($this.ServiceConnEndPointDetail -and [Helpers]::CheckMember($this.ServiceConnEndPointDetail, "serviceEndpointExecutionHistory") ) 
            {
                #if this job is still running then finishTime is not available. pass the control
                if ([Helpers]::CheckMember($this.ServiceConnEndPointDetail.serviceEndpointExecutionHistory[0].data, "finishTime")) 
                {
                    #Get the last known usage (job) timestamp of the service connection
                    $svcLastRunDate = $this.ServiceConnEndPointDetail.serviceEndpointExecutionHistory[0].data.finishTime;
                    
                    #format date
                    $formatLastRunTimeSpan = New-TimeSpan -Start (Get-Date $svcLastRunDate)
                    
                    # $inactiveLimit denotes the upper limit on number of days of inactivity before the svc conn is deemed inactive.
                    if ($this.ControlSettings -and [Helpers]::CheckMember($this.ControlSettings, "ServiceConnection.ServiceConnectionHistoryPeriodInDays") ) 
                    {
                        $inactiveLimit = $this.ControlSettings.ServiceConnection.ServiceConnectionHistoryPeriodInDays
                        if ($formatLastRunTimeSpan.Days -gt $inactiveLimit)
                        {
                            $controlResult.AddMessage([VerificationResult]::Failed, "Service connection has not been used in the last $inactiveLimit days.");
                        }
                        else
                        {
                            $controlResult.AddMessage([VerificationResult]::Passed, "Service connection has been used in the last $inactiveLimit days.");
                        }
                    }
                    else {
                        $controlResult.AddMessage([VerificationResult]::Manual,"History period in days (ServiceConnectionHistoryPeriodInDays) to check last running day of service connection is not defined in your organization policy. Please update your ControlSettings.json as per the latest AzSK.ADO PowerShell module.");
                    }  
                }
                else
                {
                    $controlResult.AddMessage([VerificationResult]::Passed, "Service connection was under use during the control scan.");
                }
            }
            else #service connection was created but never used. (Fail for now)
            {    
                $controlResult.AddMessage([VerificationResult]::Failed, "Service connection has never been used.");
            }
        }
        catch
        {
            $controlResult.AddMessage([VerificationResult]::Error,"Could not fetch the service connection details.");
        }
        
        return $controlResult;
    }

    hidden [ControlResult] CheckCrossProjectSharing([ControlResult] $controlResult)
	{  
        if($this.ServiceConnEndPointDetail -and [Helpers]::CheckMember($this.ServiceConnEndPointDetail, "serviceEndpoint") ) 
        {
            #Get the project list which are accessible to the service connection. 
            $svcProjectReferences = $this.ServiceConnEndPointDetail.serviceEndpoint.serviceEndpointProjectReferences
            if (($svcProjectReferences | Measure-Object).Count -gt 1) 
            {
                $stateData = @();
                $stateData += $svcProjectReferences | Select-Object name, projectReference
                
                $controlResult.AddMessage([VerificationResult]::Failed, "Review the list of projects that have access to the service connection: ", $stateData);
                $controlResult.SetStateData("List of projects that have access to the service connection: ", $stateData); 
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Service connection is not shared with multiple projects.");
            }
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Service connection details could not be fetched.");
        }       
        return $controlResult;
    }

    hidden [ControlResult] CheckCrossPipelineSharing([ControlResult] $controlResult) {  
        try 
        {
            if ($null -eq $this.pipelinePermission) {
                #Get pipeline access on svc conn
                $apiURL = "https://dev.azure.com/{0}/{1}/_apis/pipelines/pipelinePermissions/endpoint/{2}?api-version=5.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $($this.ServiceEndpointsObj.id) ;
                $this.pipelinePermission = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            }
            
            #check if svc conn is set to "Grant access permission to all pipelines"
            if ([Helpers]::CheckMember($this.pipelinePermission[0], "allPipelines.authorized") -and $this.pipelinePermission[0].allPipelines.authorized -eq $true) 
            {
                $controlResult.AddMessage([VerificationResult]::Failed, "Service connection is accessible to all pipelines in the project.");        
            }
            elseif ([Helpers]::CheckMember($this.pipelinePermission[0], "pipelines") -and ($this.pipelinePermission[0].pipelines | Measure-Object).Count -gt 1) #Atleast one pipeline has access to svvc conn
            { 
                #get the pipelines ids in comma separated string to pass in api to get the pipeline name
                $pipelinesIds = $this.pipelinePermission[0].pipelines.id -join ","
                #api call to get the pipeline name
                $apiURL = "https://{0}.visualstudio.com/{1}/_apis/build/definitions?definitionIds={2}&api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $pipelinesIds;
                $pipelineObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                    
                # We are fixing the control status here and the state data info will be done as shown below. This is done in case we are not able to fetch the pipeline names. Although, we have the pipeline ids as shown above.
                $controlResult.AddMessage([VerificationResult]::Verify, "");
                $pipelines = @();
                    
                if ($pipelineObj -and ($pipelineObj | Measure-Object).Count -gt 0) 
                {
                    $pipelines += $pipelineObj.name
                    $controlResult.AddMessage("Review the list of pipelines that have access to the service connection: ", $pipelines);
                    $controlResult.SetStateData("List of pipelines that have access to the service connection: ", $pipelines);   
                }                    
            } 
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Service connection is not shared with multiple pipelines.");
            }
        }
        catch 
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch pipeline permission details for the service connection.");
        }
         
        return $controlResult;
    }
    hidden [ControlResult] FetchSTMapping([ControlResult] $controlResult) {  
        
        $orgName = "MicrosoftIT"
        $projectName = "OneITVSO"

        $serviceEndpointURL = ("https://dev.azure.com/{0}/{1}/_apis/serviceendpoint/endpoints?api-version=4.1-preview.1") -f $orgName, $projectName;
        $serviceEndpointObj = [WebRequestHelper]::InvokeGetWebRequest($serviceEndpointURL)

        $Connections = $null
        if (([Helpers]::CheckMember($serviceEndpointObj, "count") -and $serviceEndpointObj[0].count -gt 0) -or (($serviceEndpointObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($serviceEndpointObj[0], "name"))) {
            
            $Connections = $serviceEndpointObj | Where-Object { ($_.type -eq "azurerm" -or $_.type -eq "azure" -or $_.type -eq "git" -or $_.type -eq "github" -or $_.type -eq "externaltfs") } 
            
        }

        $i = 1;
        $buildSTDataFileName ="BuildSTData.json";
        $BuildSTDetails = [ConfigurationManager]::LoadServerConfigFile($buildSTDataFileName);

        $releaseSTDataFileName ="ReleaseSTData.json";
        $ReleaseSTDetails = [ConfigurationManager]::LoadServerConfigFile($releaseSTDataFileName);

        $svcConnSTMapping = @{
            data = @();
        };
        
        $Connections | ForEach-Object {
            $projectId = "3d1a556d-2042-4a45-9dae-61808ff33d3b"
            $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $orgName
            $sourcePageUrl = "https://{0}.visualstudio.com/{1}/_settings/adminservices" -f $orgName, $projectName;
            $inputbody = "{'contributionIds':['ms.vss-serviceEndpoints-web.service-endpoints-details-data-provider'],'dataProviderContext':{'properties':{'serviceEndpointId':'$($_.id)','projectId':'$($projectId)','sourcePage':{'url':'$($sourcePageUrl)','routeId':'ms.vss-admin-web.project-admin-hub-route','routeValues':{'project':'$($projectName)','adminPivot':'adminservices','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
            
            $definitionId = '';
            $pipelineType = '';
            $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL, $inputbody); 
            
            if ([Helpers]::CheckMember($responseObj, "dataProviders") -and $responseObj.dataProviders."ms.vss-serviceEndpoints-web.service-endpoints-details-data-provider") {
                
                $serviceConnEndPointDetail = $responseObj.dataProviders."ms.vss-serviceEndpoints-web.service-endpoints-details-data-provider"
                if ($serviceConnEndPointDetail -and [Helpers]::CheckMember($serviceConnEndPointDetail, "serviceEndpointExecutionHistory") ) {
                    if ([Helpers]::CheckMember($serviceConnEndPointDetail.serviceEndpointExecutionHistory[0].data, "planType") -and $serviceConnEndPointDetail.serviceEndpointExecutionHistory[0].data.planType -eq "Build") {
                        
                        $definitionId = $serviceConnEndPointDetail.serviceEndpointExecutionHistory[0].data.definition.id;
                        $pipelineType = 'Build';
                        
                        $buildSTData = $BuildSTDetails.Data | Where-Object { ($_.buildDefinitionID -eq $definitionId) -and ($_.projectName -eq $projectName) };
                        if($buildSTData){
                            $svcConnSTMapping.data += @([PSCustomObject] @{ serviceConnectionName = $_.Name; serviceConnectionID = $_.id; serviceID = $buildSTData.serviceID; projectName = $buildSTData.projectName; projectID = $buildSTData.projectID; orgName = $buildSTData.orgName } )
                        }
                        
                    }
                    elseif ([Helpers]::CheckMember($serviceConnEndPointDetail.serviceEndpointExecutionHistory[0].data, "planType") -and $serviceConnEndPointDetail.serviceEndpointExecutionHistory[0].data.planType -eq "Release") {
                        $definitionId = $serviceConnEndPointDetail.serviceEndpointExecutionHistory[0].data.definition.id;
                        $pipelineType = 'Release'; 
                        
                        $releaseSTData = $ReleaseSTDetails.Data | Where-Object { ($_.releaseDefinitionID -eq $definitionId) -and ($_.projectName -eq $projectName) };
                        if($releaseSTData){
                            $svcConnSTMapping.data += @([PSCustomObject] @{ serviceConnectionName = $_.Name; serviceConnectionID = $_.id; serviceID = $releaseSTData.serviceID; projectName = $releaseSTData.projectName; projectID = $releaseSTData.projectID; orgName = $releaseSTData.orgName } )
                        }
                    }
                    
                }
            }

            Write-Host "$i - Id = $definitionId - PipelineType = $pipelineType"
            $i++
        }
        $svcConnSTMapping | ConvertTo-Json -Depth 10 | Out-File 'C:\Users\abdaga\Downloads\ServiceConnectionSTMapping.json' 
        return $controlResult;
    }
}