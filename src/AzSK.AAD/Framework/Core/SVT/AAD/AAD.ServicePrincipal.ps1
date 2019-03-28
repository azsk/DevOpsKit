Set-StrictMode -Version Latest 
class ServicePrincipal: SVTBase
{    
	hidden [PSObject] $ResourceObject;
    ServicePrincipal([string] $tenantId, [SVTResource] $svtResource): Base($tenantId, $svtResource) 
    {
        #$this.GetResourceObject();
        $objId = $svtResource.ResourceId

        $this.ResourceObject = Get-AzureADObjectByObjectId -ObjectIds $objId
        
    }

    hidden [PSObject] GetResourceObject()
    {
        return $this.ResourceObject;
    }

    hidden [ControlResult] CheckSPNPasswordCredentials([ControlResult] $controlResult)
	{
        $spn = $this.GetResourceObject()

        if ($spn.PasswordCredentials.Count -gt 0)
        {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        "Found password credentials on SPN.","TODO_FIX");
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "Did not find any password credentials on SPN.");
        }
        return $controlResult;
    }
 
    hidden [ControlResult] ReviewLegacySPN([ControlResult] $controlResult)
	{
        $spn = $this.GetResourceObject()

        if ($spn.ServicePrincipalType -eq 0)
        {
                $controlResult.AddMessage([VerificationResult]::Verify,
                                        "Found legacy SPN. Please review!","TODO_FIX");
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "SPN type ok.");
        }
        return $controlResult;
    }
}