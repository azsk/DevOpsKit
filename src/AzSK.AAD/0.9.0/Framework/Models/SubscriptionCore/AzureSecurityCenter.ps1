Set-StrictMode -Version Latest 

class AzureSecurityCenter
{
	[PSObject] $Policies
	[PSObject] $Alerts
	[PSObject] $Tasks
	
	hidden static [PSObject] GetASCAlerts([PSObject] $alertObjects)
	{
		$activeAlerts =@()

        if($null -ne $alertObjects -and ($alertObjects | Measure-Object).Count -gt 0)
        {                
            $alertObjects | ForEach-Object { 
                $out = "" | Select-Object AlertDisplayName, AlertName, Description, State, ReportedTimeUTC, RemediationSteps
				Set-Variable -Name AlertDisplayName -Value $_.properties.alertDisplayName        
				Set-Variable -Name AlertName -Value $_.properties.alertName
				Set-Variable -Name Description -Value $_.properties.description
				Set-Variable -Name State -Value $_.properties.state
				Set-Variable -Name ReportedTimeUTC -Value $_.properties.reportedTimeUtc
				Set-Variable -Name RemediationSteps -Value $_.properties.remediationSteps

				$out.AlertDisplayName = $AlertDisplayName
				$out.AlertName = $AlertName
				$out.Description = $Description
				$out.State = $State
				$out.ReportedTimeUTC = $ReportedTimeUTC
				$out.RemediationSteps = $RemediationSteps
				$activeAlerts += $out
            }
		}
		return $activeAlerts;
	}
	
	hidden static [PSObject] GetASCTasks([PSObject] $taskObjects) 
	{
		$activeTasks =@()

        if($null -ne $taskObjects -and ($taskObjects | Measure-Object).Count -gt 0)
        {                
            $taskObjects | ForEach-Object { 
                if([Helpers]::CheckMember($_, "Id")){
                $out = "" | Select-Object Name, State, ResourceId, Id
				Set-Variable -Name Name -Value $_.properties.securityTaskParameters.name
				Set-Variable -Name State -Value $_.properties.state     
				Set-Variable -Name ResourceId -Value $_.properties.securityTaskParameters.resourceId

				$out.Name = $Name
				$out.State = $State
				$out.ResourceId = $ResourceId
				$out.Id = $_.Id
				$activeTasks += $out
                }                
            }
        }
		return $activeTasks
	}
}