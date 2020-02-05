Set-StrictMode -Version Latest 
class Environment: SVTBase
{    
    hidden [PSObject] $AppsOwnedByUser = @();
    hidden [string] $EnvName;
     
    Environment([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {

        $this.EnvName = $svtResource.ResourceName

        if ($Script:AsAdmin)
        {
            $this.AppsOwnedByUser = @(Get-AdminPowerApp -Owner $Global:currentSession.userId -EnvironmentName $this.EnvName)
        }
        else 
        {
            #BUGBUG: Refine this to apps really owned by 'me' (v. editable by me)
            $this.AppsOwnedByUser = @(Get-PowerApp -EnvironmentName $this.EnvName -MyEditable)         
        }
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

            $appsList = $testDemoApps | Select-Object -Property @{Name="AppName"; Expression = {$_.AppName}}, @{Name="DisplayName"; Expression = {$_.DisplayName}}, @{Name="Owner"; Expression = {$_.Internal.properties.createdBy.userPrincipalName}}, @{Name="LastModified"; Expression = {$_.LastModifiedTime}}  

            $controlResult.AddMessage([VerificationResult]::Failed,
                                    "Found test/demo apps owned by you:",$appsList);

        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "No test/demo app owned by you.");
        }
        
        return $controlResult;
    }

    hidden [ControlResult] CheckGitHubConnections([ControlResult] $controlResult)
	{

        $connectorName = "shared_github"
        $connectorNameFilter = "*shared_github" #doesn't work with just "shared_github" so whatever! 

        $env = $this.EnvName

        if ($Script:AsAdmin)
        {
            $connector =  Get-AdminPowerAppConnector -EnvironmentName $env -ConnectorName $connectorName
            $connections = @(Get-AdminPowerAppConnection -EnvironmentName $env -ConnectorName $connectorName)
        }
        else 
        {
            $connector =  Get-PowerAppConnector -EnvironmentName $env -ConnectorName $connectorName
            $connections = @(Get-PowerAppConnection -EnvironmentName $env -ConnectorNameFilter $connectorNameFilter)
        }

        #                $controlResult.SetStateData("Build pipeline access list: ", $accessList);

        if($connections.Count -gt 0)
        {

            $controlResult.AddMessage([VerificationResult]::Failed,
                                    "Number of connections of type $($connectorName) found: ",$connections.Count);
            $connList = $connections | Select-Object -Property @{Name="ConnectionName"; Expression = {$_.ConnectionName}},`
                                                                @{Name="DisplayName"; Expression = {$_.DisplayName}},`
                                                                @{Name="Owner"; Expression = {$_.Internal.properties.createdBy.userPrincipalName}} 
            $controlResult.AddMessage("List of connections found: ", $connList)
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "No connections of type $($connectorName) found!");
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckSqlConnections([ControlResult] $controlResult)
	{  
        $connectorName = "shared_sql"
        if ($Script:AsAdmin)
        {


        }
        else 
        {
            

        }

        if($false)
        {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        "Bleh");
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "Wow!");
        }
        
        return $controlResult;
    }
}
