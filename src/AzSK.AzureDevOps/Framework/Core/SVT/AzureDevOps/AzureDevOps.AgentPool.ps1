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
                  $agentPools = ($agentPoolsObj.fps.dataProviders.data."ms.vss-build-web.agent-pools-data-provider".taskAgentPools | Where-Object { ($_.autoProvision -eq $true) }) | Select-Object @{Name = "Name"; Expression = {$_.Name}}
                  if (($agentPools | Measure-Object).Count -gt 0 ) {
                    $controlResult.AddMessage([VerificationResult]::Failed,"Auto-provision is enabled for below agent pools:", $agentPools);
                  }
                  else {
                    $controlResult.AddMessage([VerificationResult]::Passed,"Auto-provision is not enabled for any agent pool.");
                   }
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,"Auto-provision is not enabled for any agent pool.");
            }
        }
        catch{
            $controlResult.AddMessage([VerificationResult]::Manual,"could not able to fetch agent pool details.");
        }
        return $controlResult
    }

    #hidden [ControlResult] CheckPrjAgtAutoProvisioning([ControlResult] $controlResult)
    #{
    #    try {
    #        $agentPoolsURL = "https://{0}.visualstudio.com/{1}/_settings/agentqueues?__rt=fps&__ver=2" -f $($this.SubscriptionContext.SubscriptionName),'ArvTestDevOps';
    #        $agentPoolsObj = [WebRequestHelper]::InvokeGetWebRequest($agentPoolsURL);
    #                               
    #         if([Helpers]::CheckMember($agentPoolsObj,"fps.dataProviders.data") -and $agentPoolsObj.fps.dataProviders.data."ms.vss-build-web.agent-pools-data-provider" )
    #        {
    #            Write-Information $agentPoolsObj.fps.dataProviders.data."ms.vss-build-web.agent-pools-data-provider"
    #        }
    #        else {
    #            Write-Information $agentPoolsObj.fps.dataProviders.data
    #        }
    #    }
    #    catch{
    #        Write-Error $_  
    #    }
    #    return $controlResult
    #}
}