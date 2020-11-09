Set-StrictMode -Version Latest 
class AgentPool: ADOSVTBase
{    

    hidden [PSObject] $AgentObj;
    
    AgentPool([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        $apiURL = $this.ResourceContext.ResourceId
        $this.AgentObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

    }

    hidden [ControlResult] CheckRBACAccess([ControlResult] $controlResult)
    {
        if(($this.AgentObj | Measure-Object).Count -gt 0)
        {
            $roles = @();
            $roles +=   ($this.AgentObj  | Select-Object -Property @{Name="Name"; Expression = {$_.identity.displayName}},@{Name="Role"; Expression = {$_.role.displayName}});
            $controlResult.AddMessage([VerificationResult]::Verify,"Validate whether following identities have been provided with minimum RBAC access to agent pool.", $roles);
            $controlResult.SetStateData("Validate whether following identities have been provided with minimum RBAC access to agent pool.", $roles);
        }
        elseif(($this.AgentObj | Measure-Object).Count -eq 0)
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"No role assignment found")
        }
        return $controlResult
    }

    hidden [ControlResult] CheckInheritedPermissions([ControlResult] $controlResult)
    {
        if(($this.AgentObj | Measure-Object).Count -gt 0)
        {
        $inheritedRoles = $this.AgentObj | Where-Object {$_.access -eq "inherited"} 
            if( ($inheritedRoles | Measure-Object).Count -gt 0)
            {
                $roles = @();
                $roles +=   ($inheritedRoles  | Select-Object -Property @{Name="Name"; Expression = {$_.identity.displayName}},@{Name="Role"; Expression = {$_.role.displayName}});
                $controlResult.AddMessage([VerificationResult]::Failed,"Found inherited role assignments on agent pool.", $roles);
                $controlResult.SetStateData("Found inherited role assignments on agent pool.", $roles);
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,"No inherited role assignments found.")
            }
        
        }
        elseif(($this.AgentObj | Measure-Object).Count -eq 0)
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"No role assignment found.")
        }
        return $controlResult
    }

    hidden [ControlResult] CheckOrgAgtAutoProvisioning([ControlResult] $controlResult)
    {
        try {
            #Only agent pools created from org setting has this settings..
            $agentPoolsURL = "https://dev.azure.com/{0}/_apis/distributedtask/pools?poolName={1}&api-version=5.1" -f $($this.SubscriptionContext.SubscriptionName), $this.ResourceContext.resourcename;
            $agentPoolsObj = [WebRequestHelper]::InvokeGetWebRequest($agentPoolsURL);
              
            if ((($agentPoolsObj | Measure-Object).Count -gt 0) -and $agentPoolsObj.autoProvision -eq $true) {
                $controlResult.AddMessage([VerificationResult]::Failed,"Auto-provisioning is enabled for the $($agentPoolsObj.name) agent pool.");
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,"Auto-provisioning is not enabled for the agent pool.");
            }

            $agentPoolsObj =$null;
        }
        catch{
            $controlResult.AddMessage([VerificationResult]::Manual,"Could not fetch agent pool details.");
        }
        return $controlResult
    }

    hidden [ControlResult] CheckPrjAllPipelineAccess([ControlResult] $controlResult)
    {
        try {
            $projectId = $this.ResourceContext.ResourceId.Split('/')[-1].Split('_')[0];
            $agtPoolId = $this.ResourceContext.ResourceId.Split('/')[-1].Split('_')[1];

            $agentPoolsURL = "https://dev.azure.com/{0}/{1}/_apis/build/authorizedresources?type=queue&id={2}" -f $($this.SubscriptionContext.SubscriptionName),$projectId ,$agtPoolId;
            $agentPoolsObj = [WebRequestHelper]::InvokeGetWebRequest($agentPoolsURL);
                                   
             if([Helpers]::CheckMember($agentPoolsObj,"authorized") -and $agentPoolsObj.authorized)
            {
                $controlResult.AddMessage([VerificationResult]::Failed,"Access permission to all pipeline is enabled for the agent pool.");
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,"Access permission to all pipeline is not enabled for the agent pool.");
            }
            $agentPoolsObj =$null;
        }
        catch{
            $controlResult.AddMessage($_); 
            $controlResult.AddMessage([VerificationResult]::Manual,"Could not fetch agent pool details.");
        }
        return $controlResult
    }

    hidden [ControlResult] CheckInActiveAgentPool([ControlResult] $controlResult)
    {
        try 
        {
            $projectId = $this.ResourceContext.ResourceId.Split('/')[-1].Split('_')[0];
            $agtPoolId = $this.ResourceContext.ResourceId.Split('/')[-1].Split('_')[1];    
            $agentPoolsURL = "https://{0}.visualstudio.com/{1}/_settings/agentqueues?queueId={2}&__rt=fps&__ver=2" -f $($this.SubscriptionContext.SubscriptionName), $projectId, $agtPoolId
            $agentPool = [WebRequestHelper]::InvokeGetWebRequest($agentPoolsURL);
            
            if (([Helpers]::CheckMember($agentPool[0], "fps.dataProviders.data") ) -and ($agentPool[0].fps.dataProviders.data."ms.vss-build-web.agent-jobs-data-provider")) 
            {
                # $inactiveLimit denotes the upper limit on number of days of inactivity before the agent pool is deemed inactive.
                $inactiveLimit = $this.ControlSettings.AgentPool.AgentPoolHistoryPeriodInDays
                #Filtering agent pool jobs specific to the current project.
                $agentPoolJobs = $agentPool[0].fps.dataProviders.data."ms.vss-build-web.agent-jobs-data-provider".jobs | Where-Object {$_.scopeId -eq $projectId};
                #If agent pool has been queued at least once
                if (($agentPoolJobs | Measure-Object).Count -gt 0) 
                {
                        #Get the last queue timestamp of the agent pool
                        if ([Helpers]::CheckMember($agentPoolJobs[0], "finishTime")) 
                        {
                            $agtPoolLastRunDate = $agentPoolJobs[0].finishTime;
                            
                            if ((((Get-Date) - $agtPoolLastRunDate).Days) -gt $inactiveLimit)
                            {
                                $controlResult.AddMessage([VerificationResult]::Failed, "Agent pool has not been queued in the last $inactiveLimit days.");
                            }
                            else 
                            {
                                $controlResult.AddMessage([VerificationResult]::Passed,"Agent pool has been queued in the last $inactiveLimit days.");
                            }
                        }
                        else 
                        {
                            $controlResult.AddMessage([VerificationResult]::Passed,"Agent pool was being queued during control evaluation.");
                        }
                }
                else 
                {
                    #[else] Agent pool is created but nenver run, check creation date greated then 180
                    if (([Helpers]::CheckMember($agentPool, "fps.dataProviders.data") ) -and ($agentPool.fps.dataProviders.data."ms.vss-build-web.agent-pool-data-provider")) 
                    {
                        $agentPoolDetails = $agentPool.fps.dataProviders.data."ms.vss-build-web.agent-pool-data-provider"
                        
                        if ((((Get-Date) - $agentPoolDetails.selectedAgentPool.createdOn).Days) -lt $inactiveLimit)
                        {
                            $controlResult.AddMessage([VerificationResult]::Passed, "Agent pool was created within last $inactiveLimit days but never queued.");
                        }
                        else 
                        {
                            $controlResult.AddMessage([VerificationResult]::Failed, "Agent pool has not been queued from last $inactiveLimit days.");
                        }
                    }
                    else 
                    {
                        $controlResult.AddMessage([VerificationResult]::Error, "Agent pool details not found. Verify agent pool manually.");
                    }                    
                } 
            }
            else 
            { 
                $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch agent pool queue history.");
            }
        }
        catch 
        {
            $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch agent pool queue history.");
        }
        #clearing memory space.
        $agentPool = $null;
        return $controlResult
    }
    hidden [ControlResult] FetchSTMapping([ControlResult] $controlResult) {  
        
        $orgName = "MicrosoftIT"
        $projectName = "OneITVSO"

        $agentPoolsDefnURL = ("https://{0}.visualstudio.com/{1}/_settings/agentqueues?__rt=fps&__ver=2") -f $($this.SubscriptionContext.SubscriptionName), $projectName;
        $agentPoolsDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($agentPoolsDefnURL);
        
        $taskAgentQueues = $null;
        
        if (([Helpers]::CheckMember($agentPoolsDefnsObj, "fps.dataProviders.data") ) -and (($agentPoolsDefnsObj.fps.dataProviders.data."ms.vss-build-web.agent-queues-data-provider") -and $agentPoolsDefnsObj.fps.dataProviders.data."ms.vss-build-web.agent-queues-data-provider".taskAgentQueues)) {
            $taskAgentQueues = $agentPoolsDefnsObj.fps.dataProviders.data."ms.vss-build-web.agent-queues-data-provider".taskAgentQueues | where-object{$_.pool.isLegacy -eq $false}; 
        }

        $i = 1;
        $buildSTDataFileName ="BuildSTData.json";
        $BuildSTDetails = [ConfigurationManager]::LoadServerConfigFile($buildSTDataFileName);

        $releaseSTDataFileName ="ReleaseSTData.json";
        $ReleaseSTDetails = [ConfigurationManager]::LoadServerConfigFile($releaseSTDataFileName);

        $agentPoolSTMapping = @{
            data = @();
        };
         
        $taskAgentQueues | ForEach-Object {
            $projectId = "3d1a556d-2042-4a45-9dae-61808ff33d3b"
            $agtPoolId = $_.id
            $agentPoolsURL = "https://{0}.visualstudio.com/{1}/_settings/agentqueues?queueId={2}&__rt=fps&__ver=2" -f $orgName, $projectId, $agtPoolId
            $agentPool = [WebRequestHelper]::InvokeGetWebRequest($agentPoolsURL);
            
            $definitionId = '';
            $pipelineType = '';
            
            if (([Helpers]::CheckMember($agentPool[0], "fps.dataProviders.data") ) -and ($agentPool[0].fps.dataProviders.data."ms.vss-build-web.agent-jobs-data-provider")) {
                $agentPoolJobs = $agentPool[0].fps.dataProviders.data."ms.vss-build-web.agent-jobs-data-provider".jobs | Where-Object { $_.scopeId -eq $projectId };

                #Arranging in descending order of run time.
                $agentPoolJobs = $agentPoolJobs | Sort-Object queueTime -Descending
                #Taking last 10 runs
                $agentPoolJobs = $agentPoolJobs | Select-Object -First 10
                #If agent pool has been queued at least once

                $jobCount = ($agentPoolJobs | Measure-Object).Count
                $j = 0;
                while ($j -lt $jobCount) {
                    
                    if ([Helpers]::CheckMember($agentPoolJobs[$j], "planType") -and $agentPoolJobs[$j].planType -eq "Build") {
                        $definitionId = $agentPoolJobs[$j].definition.id;
                        $pipelineType = 'Build';

                        $buildSTData = $BuildSTDetails.Data | Where-Object { ($_.buildDefinitionID -eq $definitionId) -and ($_.projectName -eq $projectName) };
                        if($buildSTData){
                            $agentPoolSTMapping.data += @([PSCustomObject] @{ agentPoolName = $_.Name; agentPoolID = $_.id; serviceID = $buildSTData.serviceID; projectName = $buildSTData.projectName; projectID = $buildSTData.projectID; orgName = $buildSTData.orgName } )
                            Write-Host "$i - Id = $definitionId - PipelineType = $pipelineType"
                            break;
                        }
                    }
                    elseif ([Helpers]::CheckMember($agentPoolJobs[$j], "planType") -and $agentPoolJobs[$j].planType -eq "Release") {
                        $definitionId = $agentPoolJobs[$j].definition.id;
                        $pipelineType = 'Release';

                        $releaseSTData = $ReleaseSTDetails.Data | Where-Object { ($_.releaseDefinitionID -eq $definitionId) -and ($_.projectName -eq $projectName) };
                        if($releaseSTData){
                            $agentPoolSTMapping.data += @([PSCustomObject] @{ agentPoolName = $_.Name; agentPoolID = $_.id; serviceID = $releaseSTData.serviceID; projectName = $releaseSTData.projectName; projectID = $releaseSTData.projectID; orgName = $releaseSTData.orgName } )
                            Write-Host "$i - Id = $definitionId - PipelineType = $pipelineType"
                            break;
                        }
                    }
                    $j++;
                }
                
            }

            
            $i++
        }
        $agentPoolSTMapping | ConvertTo-Json -Depth 10 | Out-File 'C:\Users\abdaga\Downloads\AgentPoolSTData.json' 
        return $controlResult;
    }
}
