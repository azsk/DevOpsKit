Set-StrictMode -Version Latest
class BugMetaInfoProvider {

    hidden static [PSObject] $BuildSTDetails;
    hidden static [PSObject] $ReleaseSTDetails;
    hidden static [PSObject] $ServiceDetails;
    hidden [InvocationInfo] $InvocationContext
    hidden [PSObject] $ControlSettingsBugLog
    hidden static [bool] $BuildSTFileAvailableOnServer = $true;
    hidden static [bool] $ReleaseSTFileAvailableOnServer = $true;
    hidden static [bool] $ServiceTreeFileAvailableOnServer = $true;

    BugMetaInfoProvider() {
    }

    hidden static Initialize()
	{
        [BugMetaInfoProvider]::BuildSTFileAvailableOnServer = $true;		
        [BugMetaInfoProvider]::ReleaseSTFileAvailableOnServer = $true;		
        [BugMetaInfoProvider]::ServiceTreeFileAvailableOnServer = $true;		
	}

    hidden [string] GetAssignee([SVTEventContext[]] $ControlResult, [InvocationInfo] $InvocationContext, $controlSettingsBugLog) {
        $this.ControlSettingsBugLog = $controlSettingsBugLog;
        $isBugLogCustomFlow = $false;
        if ([Helpers]::CheckMember($this.ControlSettings.BugLogging, "BugAssigneeAndPathCustomFlow", $null)) {
            $isBugLogCustomFlow = $this.ControlSettings.BugLogging.BugAssigneeAndPathCustomFlow;
        }
        if ($isBugLogCustomFlow) {
            $ResourceType = $ControlResult.ResourceContext.ResourceTypeName
            $ResourceName = $ControlResult.ResourceContext.ResourceName
            $organizationName = $ControlResult.SubscriptionContext.SubscriptionName;
            $this.InvocationContext = $InvocationContext;
            switch -regex ($ResourceType) {
                #get the last run svc pipeline based on pipeline get assignee, else fallback
                'ServiceConnection' {
                    try {
                        $projectId = ($ControlResult.ResourceContext.ResourceDetails.ResourceLink -split $organizationName)[1].split("/")[1]; #$projectObj.id
                        $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($organizationName)
                        $sourcePageUrl = "https://{0}.visualstudio.com/{1}/_settings/adminservices" -f $($organizationName), $ControlResult.ResourceContext.ResourceGroupName;
                        $inputbody = "{'contributionIds':['ms.vss-serviceEndpoints-web.service-endpoints-details-data-provider'],'dataProviderContext':{'properties':{'serviceEndpointId':'$($ControlResult.ResourceContext.ResourceDetails.id)','projectId':'$($projectId)','sourcePage':{'url':'$($sourcePageUrl)','routeId':'ms.vss-admin-web.project-admin-hub-route','routeValues':{'project':'$($ControlResult.ResourceContext.ResourceGroupName)','adminPivot':'adminservices','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
            
                        $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL, $inputbody); 
                        if ([Helpers]::CheckMember($responseObj, "dataProviders") -and $responseObj.dataProviders."ms.vss-serviceEndpoints-web.service-endpoints-details-data-provider") {
                            $serviceConnEndPointDetail = $responseObj.dataProviders."ms.vss-serviceEndpoints-web.service-endpoints-details-data-provider"
                            if ($serviceConnEndPointDetail -and [Helpers]::CheckMember($serviceConnEndPointDetail, "serviceEndpointExecutionHistory") ) {
                                if ([Helpers]::CheckMember($serviceConnEndPointDetail.serviceEndpointExecutionHistory[0].data, "planType") -and $serviceConnEndPointDetail.serviceEndpointExecutionHistory[0].data.planType -eq "Build") {
                                    $definitionId = $serviceConnEndPointDetail.serviceEndpointExecutionHistory[0].data.definition.id;
                                    return $this.CalculateAssigneeBuild($ControlResult, $definitionId); 
                                }
                                elseif ([Helpers]::CheckMember($serviceConnEndPointDetail.serviceEndpointExecutionHistory[0].data, "planType") -and $serviceConnEndPointDetail.serviceEndpointExecutionHistory[0].data.planType -eq "Release") {
                                    $definitionId = $serviceConnEndPointDetail.serviceEndpointExecutionHistory[0].data.definition.id;
                                    return $this.CalculateAssigneeRelease($ControlResult, $definitionId); 
                                }
                                else {
                                    return $this.GetAssigneeFallback($ControlResult)
                                }
                            }
                            else {
                                return $this.GetAssigneeFallback($ControlResult, $organizationName)
                            }
                        }
                        else {
                            return $this.GetAssigneeFallback($ControlResult, $organizationName)
                        }
                    }
                    catch {
                        return "";
                    }
                }
                #get last run agent pool pipeline base on that get assignee else fallback option 
                'AgentPool' {
                    $apiurl = "https://dev.azure.com/{0}/_apis/distributedtask/pools?poolName={1}&api-version=5.1" -f $organizationName, $ResourceName
                    try {
                        $projectId = $ControlResult.ResourceContext.ResourceId.Split('/')[-1].Split('_')[0];
                        $agtPoolId = $ControlResult.ResourceContext.ResourceId.Split('/')[-1].Split('_')[1];    
                        $agentPoolsURL = "https://{0}.visualstudio.com/{1}/_settings/agentqueues?queueId={2}&__rt=fps&__ver=2" -f $($ControlResult.SubscriptionContext.SubscriptionName), $projectId, $agtPoolId
                        $agentPool = [WebRequestHelper]::InvokeGetWebRequest($agentPoolsURL);
                        
                        if (([Helpers]::CheckMember($agentPool[0], "fps.dataProviders.data") ) -and ($agentPool[0].fps.dataProviders.data."ms.vss-build-web.agent-jobs-data-provider")) {
                            $agentPoolJobs = $agentPool[0].fps.dataProviders.data."ms.vss-build-web.agent-jobs-data-provider".jobs | Where-Object { $_.scopeId -eq $projectId };
                            #If agent pool has been queued at least once
                            if (($agentPoolJobs | Measure-Object).Count -gt 0) {
                                if ([Helpers]::CheckMember($agentPoolJobs[0], "planType") -and $agentPoolJobs[0].planType -eq "Build") {
                                    $definitionId = $agentPoolJobs[0].definition.id;
                                    return $this.CalculateAssigneeBuild($ControlResult, $definitionId); 
                                }
                                elseif ([Helpers]::CheckMember($agentPoolJobs[0], "planType") -and $agentPoolJobs[0].planType -eq "Release") {
                                    $definitionId = $agentPoolJobs[0].definition.id;
                                    return $this.CalculateAssigneeRelease($ControlResult, $definitionId); 
                                }
                                else {
                                    return $this.GetAssigneeFallback($ControlResult)
                                }
                            }
                            else {
                                return $this.GetAssigneeFallback($ControlResult)
                            }
                        }
                    }
                    catch {
                        return "";
                    }
                }
                #assign to the person who recently triggered the build pipeline, or if the pipeline is empty assign it to the creator
                'Build' {
                    $definitionId = $ControlResult.ResourceContext.ResourceId.Split("/")[-1];
                    return $this.CalculateAssigneeBuild($ControlResult, $definitionId);
                }
                #assign to the person who recently triggered the release pipeline, or if the pipeline is empty assign it to the creator
                'Release' {
                    $definitionId = ($ControlResult.ResourceContext.ResourceId -split "definitions/")[1];
                    return $this.CalculateAssigneeRelease($ControlResult, $definitionId) 
                }
                #assign to the person running the scan, as to reach at this point of code, it is ensured the user is PCA/PA and only they or other PCA
                #PA members can fix the control
                'Organization' {
                    return [ContextHelper]::GetCurrentSessionUser();
                }
                'Project' {
                    return [ContextHelper]::GetCurrentSessionUser();
    
                }
            }
        }
        else {
            return $this.GetAssigneeFallback($ControlResult);
        }
        return "";
    }

    hidden [string] CalculateAssigneeBuild([SVTEventContext[]] $ControlResult, $buildId) {
        $buildSTDataFileName ="BuildSTData.json";
        try {
            if (![BugMetaInfoProvider]::BuildSTDetails) {
                
                if([Helpers]::CheckMember($this.ControlSettingsBugLog, "BuildSTData"))
                {
                    $buildSTDataFileName = $this.ControlSettingsBugLog.BuildSTData;
                }
                if ([BugMetaInfoProvider]::BuildSTFileAvailableOnServer) {
                    [BugMetaInfoProvider]::BuildSTDetails = [ConfigurationManager]::LoadServerConfigFile($buildSTDataFileName);
                }
            }
            $buildSTDeatils = [BugMetaInfoProvider]::BuildSTDetails.Data | Where-Object { $_.buildDefinitionID -eq $buildId }; 
            if ($buildSTDeatils) {
                $assignee = $this.GetDataFromServiceTree($buildSTDeatils.serviceID);
                if ($assignee) {
                    return $assignee;
                }
                else {
                    return $this.GetAssigneeFallback($ControlResult)
                }
            }
            else {
                return $this.GetAssigneeFallback($ControlResult)
            }
            #if no triggers found assign to the creator
            else {
                return $this.GetAssigneeFallback($ControlResult)
            }
        }
        catch {
            if ($_.Exception.Message -like "Unable to find the specified file*") {
                [BugMetaInfoProvider]::BuildSTFileAvailableOnServer = $false;
                Write-Host "Could not find build service tree data file [$($buildSTDataFileName)]." -ForegroundColor Yellow
            }
            return "";
        }	
    }

    hidden [string] CalculateAssigneeRelease([SVTEventContext[]] $ControlResult, $relDefId) {
        $releaseSTDataFileName ="ReleaseSTData.json";
        try {
            if (![BugMetaInfoProvider]::ReleaseSTDetails) {
                
                if([Helpers]::CheckMember($this.ControlSettingsBugLog, "ReleaseSTData"))
                {
                    $releaseSTDataFileName = $this.ControlSettingsBugLog.ReleaseSTData;
                }
                if ([BugMetaInfoProvider]::ReleaseSTFileAvailableOnServer) {
                    [BugMetaInfoProvider]::ReleaseSTDetails = [ConfigurationManager]::LoadServerConfigFile($releaseSTDataFileName);   
                }
                [BugMetaInfoProvider]::ReleaseSTDetails = [ConfigurationManager]::LoadServerConfigFile($releaseSTDataFileName)
            }
            $releaseSTDeatils = [BugMetaInfoProvider]::ReleaseSTDetails.Data | Where-Object { $_.releaseDefinitionID -eq $relDefId }; 
                
            if ($releaseSTDeatils) {
                $assignee = $this.GetDataFromServiceTree($releaseSTDeatils.serviceID);
                if ($assignee) {
                    return $assignee;
                }
                else {
                    return $this.GetAssigneeFallback($ControlResult)
                }
            }
            else {
                return $this.GetAssigneeFallback($ControlResult)
            }                            
            #if no triggers found then fallback option
            else {
                return $this.GetAssigneeFallback($ControlResult)
            }
        }
        catch {
            if ($_.Exception.Message -like "Unable to find the specified file*") {
                [BugMetaInfoProvider]::ReleaseSTFileAvailableOnServer = $false;
                Write-Host "Could not find release service tree data file [$($releaseSTDataFileName)]." -ForegroundColor Yellow
            }
            return "";
        }	
    }

    hidden [string] GetAssigneeFallback([SVTEventContext[]] $ControlResult) {
        $ResourceType = $ControlResult.ResourceContext.ResourceTypeName
        $ResourceName = $ControlResult.ResourceContext.ResourceName
        $organizationName = $ControlResult.SubscriptionContext.SubscriptionName;
        switch -regex ($ResourceType) {
            #assign to the creator of service connection
            'ServiceConnection' {
                return $ControlResult.ResourceContext.ResourceDetails.createdBy.uniqueName
            }
            #assign to the creator of agent pool
            'AgentPool' {
                $apiurl = "https://dev.azure.com/{0}/_apis/distributedtask/pools?poolName={1}&api-version=5.1" -f $organizationName, $ResourceName
                try {
                    $response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
                    return $response.createdBy.uniqueName
                }
                catch {
                    return "";
                }
            }
            #assign to the person who recently triggered the build pipeline, or if the pipeline is empty assign it to the creator
            'Build' {
                $definitionId = ($ControlResult.ResourceContext.ResourceDetails.ResourceLink -split "=")[1]
    
                try {
                    $apiurl = "https://dev.azure.com/{0}/{1}/_apis/build/builds?definitions={2}&api-version=5.1" -f $organizationName, $ControlResult.ResourceContext.ResourceGroupName , $definitionId;
			    	
                    $response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
                    #check for recent trigger
                    if ([Helpers]::CheckMember($response, "requestedBy")) {
                        return $response[0].requestedBy.uniqueName
                    }
                    #if no triggers found assign to the creator
                    else {
                        $apiurl = "https://dev.azure.com/{0}/{1}/_apis/build/definitions/{2}?api-version=5.1" -f $organizationName, $ControlResult.ResourceContext.ResourceGroupName , $definitionId;
                        $response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
                        return $response.authoredBy.uniqueName
                    }
                }
                catch {
                    return "";
                }	
			    	
            }
            #assign to the person who recently triggered the release pipeline, or if the pipeline is empty assign it to the creator
            'Release' {
                $definitionId = ($ControlResult.ResourceContext.ResourceId -split "definitions/")[1]
                try {
                    $apiurl = "https://vsrm.dev.azure.com/{0}/{1}/_apis/release/releases?definitionId={2}&api-version=5.1" -f $organizationName, $ControlResult.ResourceContext.ResourceGroupName , $definitionId;
                    $response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
                    #check for recent trigger
                    if ([Helpers]::CheckMember($response, "modifiedBy")) {
                        return $response[0].modifiedBy.uniqueName
                    }
                    #if no triggers found assign to the creator
                    else {
                        $apiurl = "https://vsrm.dev.azure.com/{0}/{1}/_apis/release/definitions/{2}?&api-version=5.1" -f $organizationName, $ControlResult.ResourceContext.ResourceGroupName , $definitionId;
                        $response = [WebRequestHelper]::InvokeGetWebRequest($apiurl)
                        return $response.createdBy.uniqueName
                    }
                }
                catch {
                    return "";
                }
            }
            #assign to the person running the scan, as to reach at this point of code, it is ensured the user is PCA/PA and only they or other PCA
            #PA members can fix the control
            'Organization' {
                return [ContextHelper]::GetCurrentSessionUser();
            }
            'Project' {
                return [ContextHelper]::GetCurrentSessionUser();
    
            }
        }
        return "";
    }

    hidden [string] GetDataFromServiceTree($serviceId) {
        $serviceDataFileName ="ServiceTreeData.json";
        try 
        {
            if (![BugMetaInfoProvider]::ServiceDetails) {
                
                if([Helpers]::CheckMember($this.ControlSettingsBugLog, "ServiceTreeData"))
                {
                    $serviceDataFileName = $this.ControlSettingsBugLog.ServiceTreeData;
                }
                if ([BugMetaInfoProvider]::ServiceTreeFileAvailableOnServer) {
                    [BugMetaInfoProvider]::ServiceDetails = [ConfigurationManager]::LoadServerConfigFile($serviceDataFileName);
                }
            }
            $serviceTree = [BugMetaInfoProvider]::ServiceDetails.Data | Where-Object { $_.serviceID -eq $serviceId };
            if ($serviceTree) {
                [BugLogPathManager]::AreaPath = $serviceTree.areaPath.Replace("\", "\\");
                $domainNameForAssignee = "microsoft.com"
                if([Helpers]::CheckMember($this.ControlSettingsBugLog, "DomainName"))
                {
                    $domainNameForAssignee = $this.ControlSettingsBugLog.DomainName;
                }
                return $serviceTree.devOwner.Split(";")[0] + "@"+ $domainNameForAssignee
            }
            else {
                return "";
            }
           
        }
        catch {
            if ($_.Exception.Message -like "Unable to find the specified file*") {
                [BugMetaInfoProvider]::ServiceTreeFileAvailableOnServer = $false;
                Write-Host "Could not find service tree data file [$($serviceDataFileName)]." -ForegroundColor Yellow
            }
            return "";
        }
    }
}