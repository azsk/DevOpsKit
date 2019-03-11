Set-StrictMode -Version Latest 
class Project: SVTBase
{    

    Project([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {

    }

    hidden [ControlResult] CheckPublicProjects([ControlResult] $controlResult)
	{
        $apiURL = $this.ResourceContext.ResourceId;
        $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        if([Helpers]::CheckMember($responseObj,"visibility"))
        {
            if($responseObj.visibility -eq "Private")
            {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                                "Project visibility is set to private"); 

            }
            else {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                                "Project visibility is set to public");
            }              
        }
        return $controlResult;
    }

}