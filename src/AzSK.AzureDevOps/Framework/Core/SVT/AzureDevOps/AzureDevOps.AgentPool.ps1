Set-StrictMode -Version Latest 
class AgentPool: SVTBase
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
         $roles =   $this.AgentObj  | Select-Object -Property @{Name="Name"; Expression = {$_.identity.displayName}},@{Name="Role"; Expression = {$_.role.displayName}}
         $controlResult.AddMessage([VerificationResult]::Verify,"Validate that the following identities have been provided with minimum RBAC access to agent.", $roles);
        }
        elseif(($this.AgentObj | Measure-Object).Count -eq 0)
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"No role assignment found")
        }
        return $controlResult
    }

    hidden [ControlResult] CheckInheritPermissions([ControlResult] $controlResult)
    {
        if(($this.AgentObj | Measure-Object).Count -gt 0)
        {
        $inheritedRoles = $this.AgentObj | Where-Object {$_.access -eq "inherited"} 
            if( ($inheritedRoles | Measure-Object).Count -gt 0)
            {
                $roles =   $inheritedRoles  | Select-Object -Property @{Name="Name"; Expression = {$_.identity.displayName}},@{Name="Role"; Expression = {$_.role.displayName}}
                $controlResult.AddMessage([VerificationResult]::Failed,"Found inherited role assignment on agent.", $roles);
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,"No inherited role assignment found")
            }
        
        }
        elseif(($this.AgentObj | Measure-Object).Count -eq 0)
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"No role assignment found")
        }
        return $controlResult
    }

    hidden [ControlResult] CheckOrgAgtAutoProvisioning([ControlResult] $controlResult)
    {
        try {
            $agentPoolsURL = "https://{0}.visualstudio.com/_settings/agentqueues?__rt=fps&__ver=2" -f $($this.SubscriptionContext.SubscriptionName);
            $agentPoolsObj = [WebRequestHelper]::InvokeGetWebRequest($agentPoolsURL);
              
            $agentPools =@();
            if([Helpers]::CheckMember($agentPoolsObj,"fps.dataProviders.data") -and $agentPoolsObj.fps.dataProviders.data."ms.vss-build-web.agent-pools-data-provider" -and ($agentPoolsObj.fps.dataProviders.data."ms.vss-build-web.agent-pools-data-provider".taskAgentPools.Count -gt 0 ))
            {
                  $agentPools = ($agentPoolsObj.fps.dataProviders.data."ms.vss-build-web.agent-pools-data-provider".taskAgentPools | Where-Object { ($_.autoProvision -eq $true -and $_.Name -eq $this.ResourceContext.resourcename) }) #| Select-Object @{Name = "Name"; Expression = {$_.Name}}
                  if (($agentPools | Measure-Object).Count -gt 0 ) {
                    $controlResult.AddMessage([VerificationResult]::Passed,"Auto-provision is enabled for the $($agentPools) agent pools.");
                  }
                  else {
                    $controlResult.AddMessage([VerificationResult]::Failed,"Auto-provision is not enabled for the agent pool.");
                   }
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Failed,"Auto-provision is not enabled for the agent pool.");
            }
        }
        catch{
            $controlResult.AddMessage([VerificationResult]::Manual,"could not able to fetch agent pool details.");
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
        }
        catch{
            $controlResult.AddMessage($_); 
            $controlResult.AddMessage([VerificationResult]::Manual,"could not able to fetch agent pool details.");
        }
        return $controlResult
    }
}