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
}