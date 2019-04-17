Set-StrictMode -Version Latest 
class Device: SVTBase
{    
    hidden [PSObject] $ResourceObject;
    static [int] $InactiveDaysLimit = 180; #TODO: ControlSettings, TODO: statics ok? (in-session tenant change?)
    Device([string] $tenantId, [SVTResource] $svtResource): Base($tenantId, $svtResource) 
    {
        $objId = $svtResource.ResourceId
        $this.ResourceObject = Get-AzureADDevice -ObjectId $objId
    }

    hidden [PSObject] GetResourceObject()
    {
        return $this.ResourceObject;
    }

    hidden [ControlResult] CheckStaleDevices([ControlResult] $controlResult)
	{
        $d = $this.GetResourceObject()

        $lastLoginDateTime = $d[0].ApproximateLastLogonTimeStamp 
        $inactiveThreshold = ([DateTime]::Today).AddDays(-([Device]::InactiveDaysLimit))
        if($lastLoginDateTime -lt $inactiveThreshold)
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                    [MessageData]::new("Device [$($d.DisplayName)] appears to be a stale entry. Last login was at: $lastLoginDateTime.`nConsider removing it from the directory."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("Device appears to be active (not stale). Last login: $lastLoginDateTime"));
        }

        return $controlResult;

    }
}