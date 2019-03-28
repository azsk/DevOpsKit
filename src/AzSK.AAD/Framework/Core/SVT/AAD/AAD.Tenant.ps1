Set-StrictMode -Version Latest 
class Tenant: SVTBase
{    
    hidden [PSObject] $AADSettings;

    hidden [PSObject] $AADPermissions;

    Tenant([string] $tenantId, [SVTResource] $svtResource): Base($tenantId, $svtResource) 
    {
        $this.GetAADPermissions()
    }

    hidden [PSObject] GetAADPermissions()
    {
        if ($this.AADPermissions -eq $null)
        {
            $this.AADPermissions = [Helpers]::InvokeAADAPI("/api/Permissions")
        }
        return $this.AADPermissions
    }

    hidden [ControlResult] CheckAADGuestAccessConfig([ControlResult] $controlResult)
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

    hidden [ControlResult] CheckMFASettings([ControlResult] $controlResult)
	{
        if(2 -gt 3)
        {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        "TODO.","TODO_FIX");
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "TODO.");
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckUserPermissionsToCreateApps([ControlResult] $controlResult)
	{
        $aadPerms = $this.GetAADPermissions()
        if($aadPerms.allowedActions.application.Contains('create')) #has to match case
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                    "TODO. Do not permit users to create apps.","TODO_FIX");
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "TODO.");
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckUserPermissionToInviteGuests([ControlResult] $controlResult)
	{
        $aadPerms = $this.GetAADPermissions()

        if($aadPerms.allowedActions.user.Contains('inviteguest')) #has to match case
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                    "TODO. Do not permit users to invite guests.","TODO_FIX");
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "TODO.");
        }
        return $controlResult;
    }
}