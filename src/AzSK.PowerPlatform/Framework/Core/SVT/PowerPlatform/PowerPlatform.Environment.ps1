Set-StrictMode -Version Latest 
class Environment: SVTBase
{    
    hidden [PSObject] $AppsOwnedByUser = @();
     
    Environment([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        $this.AppsOwnedByUser = @(Get-AdminPowerApp -Owner $Global:currentSession.userId)
    }

    hidden [ControlResult] CheckDemoAppsLimit([ControlResult] $controlResult)
	{
        $demoAppsRegex = 'test|demo|trial'
        $demoAppsLimit = 0
        
        $testDemoApps = @();
        
        if ($this.AppSOwnedByUser.Count -gt 0)
        {
            $testDemoApps = $this.AppsOwnedByUser |?{$_.DisplayName -imatch $demoAppsRegex} 
        }

        if($testDemoApps.Count -gt $demoAppsLimit)
        {

                $controlResult.AddMessage([VerificationResult]::Failed,
                                        "Found test/demo apps owned by you:",$testDemoApps);

        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "No test/demo app owned by you.");
        }
        
        return $controlResult;
    }
}