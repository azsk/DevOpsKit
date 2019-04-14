Set-StrictMode -Version Latest 
class User: SVTBase
{    

    User([string] $tenantId, [SVTResource] $svtResource): Base($tenantId, $svtResource) 
    {

    }

    hidden [ControlResult] CheckEmergencyContacts([ControlResult] $controlResult)
	{
        if(3 -gt 0)
        {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        "User does not have contacts set.","Please set the contact info.");
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "Found contact info. All good.");
        }
        return $controlResult;
    }
}