Set-StrictMode -Version Latest 
class ServiceConnection: SVTBase
{    
    [PSObject] $ServiceEndPointsObj = $null
    Pipelines([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId,$svtResource) 
    { 
        [string]$user = ""
        [string]$token = ""
        $validatedUri = "https://dev.azure.com/organization/project/_apis/serviceendpoint/endpoints?api-version=4.1-preview.1" 
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$token)))
        $serverFileContent = Invoke-RestMethod `
                                            -Method GET `
                                            -Uri $validatedUri `
                                            -Headers @{"Authorization" = "Basic $base64AuthInfo"} `
                                            -UseBasicParsing
	    $this.ServiceEndPointsObj = $serverFileContent
    }

    hidden [ControlResult] CheckSPNAuthenticationCertificate([ControlResult] $controlResult)
	{

        $keybasedSPNList = @()

        $this.ServiceEndPointsObj[0].value| ForEach-Object{
  
            $Endpoint = $_
          
            if([Helpers]::CheckMember($Endpoint, "authorization.parameters.authenticationType"))
            {
                $keybasedSPNList += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName; AuthType=$Endpoint.authorization.parameters.authenticationType }
            }
            else
            {
              $keybasedSPNList += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName}
            }
          }

        if($keybasedSPNList.Count -eq 0 )
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "All Service Endpoints are Cert based authenticated");
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                        "Below endpoints are used with secret based auth",$keybasedSPNList);
        }
        return $controlResult;
    }


    hidden [ControlResult] CheckInactiveEndpoints([ControlResult] $controlResult)
	{

        $inactiveEnpoints = @()
        [string]$user = ""
        [string]$token = ""
        $this.ServiceEndPointsObj[0].value | ForEach-Object{
  
            $Endpoint = $_
            $validatedUri = "https://dev.azure.com/organization/project/_apis/serviceendpoint/$($Endpoint.Id)/executionhistory/?api-version=4.1-preview.1" 
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$token)))
$serverFileContent = Invoke-RestMethod `
									-Method GET `
									-Uri $validatedUri `
                					-Headers @{"Authorization" = "Basic $base64AuthInfo"} `
									-UseBasicParsing
            if($serverFileContent.Count -gt 0)
            {
                if([DateTime]$serverFileContent[0].value[0].data.startTime -gt (Get-Date).AddDays(-180))
                {
                    $inactiveEnpoints += @{EndPointName= $Endpoint.Name; Creator = $Endpoint.createdBy.displayName; LastAccessDate=$serverFileContent[0].value[0].data.startTime }
                }                
            }
          }

        if($inactiveEnpoints.Count -eq 0 )
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "All Service Endpoints are Cert based authenticated");
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                        "Below endpoints are used with secret based auth",$inactiveEnpoints);
        }
        return $controlResult;
    }
}