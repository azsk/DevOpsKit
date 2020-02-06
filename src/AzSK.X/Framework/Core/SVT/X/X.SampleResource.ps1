Set-StrictMode -Version Latest 
class SampleResource: SVTBase
{    

    hidden [PSObject] $ResourceObj;
    hidden [string] $SecurityNamespaceId;
    
    SampleResource([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        # Get security namespace identifier of current build.
        $this.ResourceObj = "Resource Details"
    }

    hidden [ControlResult] CheckRBACAccess([ControlResult] $controlResult)
    {
       
        # Core logic of the control evaluation

        if( 1 -eq 1)
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"Resource passed for ");
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Failed,"Reseoning of control failure");
        }

        return $controlResult
    }
}