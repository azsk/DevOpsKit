Set-StrictMode -Version Latest 
class ServicePrincipal: SVTBase
{    
    hidden [PSObject] $ResourceObject;
    hidden [String] $SPNName;
    ServicePrincipal([string] $tenantId, [SVTResource] $svtResource): Base($tenantId, $svtResource) 
    {
        #$this.GetResourceObject();
        $objId = $svtResource.ResourceId

        $this.ResourceObject = Get-AzureADObjectByObjectId -ObjectIds $objId
        $this.SPNName = "TODO_SPN_Name_Here" #? $this.ResourceObject.DisplayName
        
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
                $nPswd = $spn.PasswordCredentials.Count


                $controlResult.AddMessage([VerificationResult]::Failed,
                                        [MessageData]::new("Found $nPswd assword credentials on SPN: $($this.SPNName).")); 
                                        
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("Did not find any password credentials on SPN."));
        }
        return $controlResult;
    }
 
    hidden [ControlResult] ReviewLegacySPN([ControlResult] $controlResult)
	{
        $spn = $this.GetResourceObject()

        if ($spn.ServicePrincipalType -eq 'Legacy')
        {
                $controlResult.AddMessage([VerificationResult]::Verify,
                                        [MessageData]::new("Found an SPN of type 'Legacy'. Please review: $($this.SPNName)"));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("SPN is not of type 'Legacy'."));
        }
        return $controlResult;
    }
}