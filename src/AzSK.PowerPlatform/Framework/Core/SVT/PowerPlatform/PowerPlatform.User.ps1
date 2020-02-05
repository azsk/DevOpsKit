Set-StrictMode -Version Latest 
class User: SVTBase
{    

    User([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {

    }

    hidden [ControlResult] CheckPATAccessLevel([ControlResult] $controlResult)
	{
        #TBD
        return $controlResult;
    }
}