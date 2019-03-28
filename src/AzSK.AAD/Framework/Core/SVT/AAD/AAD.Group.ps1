Set-StrictMode -Version Latest 
class Group: SVTBase
{    

    Group([string] $tenantId, [SVTResource] $svtResource): Base($tenantId, $svtResource) 
    {

    }

    hidden [ControlResult] CheckGroupsIsSecurityEnabled([ControlResult] $controlResult)
	{
        if(1 -eq 2)
        {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        "TODO.","TODO_FIX");
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "TODO. All good.");
        }
        return $controlResult;
    }
}