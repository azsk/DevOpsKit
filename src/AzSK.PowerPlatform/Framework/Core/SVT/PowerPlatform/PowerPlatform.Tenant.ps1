Set-StrictMode -Version Latest 
class Tenant: SVTBase
{    
    [PSObject] $OrgPolicyObj = $null
    Tenant([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    { 
        $this.GetOrgPolicyObject()
    }

    GetOrgPolicyObject()
    {
        <#TODO#>
    }

    hidden [ControlResult] CheckAADConfiguration([ControlResult] $controlResult)
    {

        <#TODO#>

 
        $controlResult.AddMessage([VerificationResult]::Failed,
                                    "TODO - implement controls");
        return $controlResult
    }
}