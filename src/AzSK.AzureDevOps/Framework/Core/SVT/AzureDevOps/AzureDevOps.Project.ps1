Set-StrictMode -Version Latest 
class Project: SVTBase
{    
    [PSObject] $PipelineSettingsObj = $null

    Project([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        $this.GetPipelineSettingsObj()
    }

    GetPipelineSettingsObj()
    {
        $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
        #TODO: testing adding below line commenting above line
        #$apiURL = "https://dev.azure.com/{0}/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);

        $orgUrl = "https://{0}.visualstudio.com" -f $($this.SubscriptionContext.SubscriptionName);
        $projectName = $this.ResourceContext.ResourceName;
        #$inputbody =  "{'contributionIds':['ms.vss-org-web.collection-admin-policy-data-provider'],'context':{'properties':{'sourcePage':{'url':'$orgUrl/_settings/policy','routeId':'ms.vss-admin-web.collection-admin-hub-route','routeValues':{'adminPivot':'policy','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
        $inputbody = "{'contributionIds':['ms.vss-build-web.pipelines-general-settings-data-provider'],'dataProviderContext':{'properties':{'sourcePage':{'url':'$orgUrl/$projectName/_settings/settings','routeId':'ms.vss-admin-web.project-admin-hub-route','routeValues':{'project':'$projectName','adminPivot':'settings','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
        $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);
      
        if([Helpers]::CheckMember($responseObj,"dataProviders") -and $responseObj.dataProviders.'ms.vss-build-web.pipelines-general-settings-data-provider')
        {
            $this.PipelineSettingsObj = $responseObj.dataProviders.'ms.vss-build-web.pipelines-general-settings-data-provider'
        }
    }

    hidden [ControlResult] CheckPublicProjects([ControlResult] $controlResult)
	{
        $apiURL = $this.ResourceContext.ResourceId;
        $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        if([Helpers]::CheckMember($responseObj,"visibility"))
        {
            if($responseObj.visibility -eq "Private")
            {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                                "Project visibility is set to private"); 

            }
            else {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                                "Project visibility is set to public");
            }              
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckBadgeAnonAccess([ControlResult] $controlResult)
    {
       if($this.PipelineSettingsObj)
       {
            
            if($this.PipelineSettingsObj.statusBadgesArePrivate.enabled -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Anonymous access to status badge API is disabled. It is set as '$($this.PipelineSettingsObj.statusBadgesArePrivate.orgEnabled)' at organization scope.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Failed, "Anonymous access to status badge API is enabled. It is set as '$($this.PipelineSettingsObj.statusBadgesArePrivate.orgEnabled)' at organization scope.");
            }       
       }
        return $controlResult
    }

    hidden [ControlResult] CheckSetQueueTime([ControlResult] $controlResult)
    {
       if($this.PipelineSettingsObj)
       {
            
            if($this.PipelineSettingsObj.enforceSettableVar.enabled -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Only limited variables can be set at queue time. It is set as '$($this.PipelineSettingsObj.enforceSettableVar.orgEnabled)' at organization scope.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Failed, "All variables can be set at queue time. It is set as '$($this.PipelineSettingsObj.enforceSettableVar.orgEnabled)' at organization scope.");
            }       
       }
        return $controlResult
    }

    hidden [ControlResult] CheckJobAuthnScope([ControlResult] $controlResult)
    {
       if($this.PipelineSettingsObj)
       {
            
            if($this.PipelineSettingsObj.enforceJobAuthScope.enabled -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Scope of access of all pipelines is restricted to current project. It is set as '$($this.PipelineSettingsObj.enforceJobAuthScope.orgEnabled)' at organization scope.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Failed, "Scope of access of all pipelines is set to project collection. It is set as '$($this.PipelineSettingsObj.enforceJobAuthScope.orgEnabled)' at organization scope.");
            }       
       }
        return $controlResult
    }

    hidden [ControlResult] CheckPublishMetadata([ControlResult] $controlResult)
    {
       if($this.PipelineSettingsObj)
       {
            
            if($this.PipelineSettingsObj.publishPipelineMetadata.enabled -eq $true )
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Publishing metadata from pipeline is enabled. It is set as '$($this.PipelineSettingsObj.publishPipelineMetadata.orgEnabled)' at organization scope.");
            }
            else{
                $controlResult.AddMessage([VerificationResult]::Failed, "Publishing metadata from pipeline is disabled. It is set as '$($this.PipelineSettingsObj.publishPipelineMetadata.orgEnabled)' at organization scope.");
            }       
       }
        return $controlResult
    }
}