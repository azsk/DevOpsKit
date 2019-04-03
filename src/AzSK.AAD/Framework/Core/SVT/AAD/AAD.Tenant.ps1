Set-StrictMode -Version Latest 
class Tenant: SVTBase
{    
    hidden [PSObject] $AADPermissions;

    hidden [PSObject] $CASettings;
    hidden [PSObject] $AdminMFASettings;
    hidden [PSObject] $B2BSettings;

    Tenant([string] $tenantId, [SVTResource] $svtResource): Base($tenantId, $svtResource) 
    {
        $this.GetAADSettings()
    }

    hidden GetAADSettings()
    {
        if ($this.AADPermissions -eq $null)
        {
            $this.AADPermissions = [Helpers]::InvokeAADAPI("/api/Permissions")
        }

        if ($this.CASettings -eq $null)
        {
            $this.CASettings = [Helpers]::InvokeAADAPI("/api/PasswordReset/PasswordResetPolicies")
        }

        if ($this.AdminMFASettings -eq $null)
        {
            $this.AdminMFASettings = [Helpers]::InvokeAADAPI("/api/BaselinePolicies/RequireMfaForAdmins")
        }

        if ($this.B2BSettings -eq $null)
        {
            $this.B2BSettings = [Helpers]::InvokeAADAPI("/api/Directories/B2BDirectoryProperties")
        }
    }

    hidden [ControlResult] CheckGuestsHaveLimitedAccess([ControlResult] $controlResult)
	{
        $b2b = $this.B2BSettings
        if($b2b.restrictDirectoryAccess -ne $true) #Guests permissions are limited?
        {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        [MessageData]::new("Guest account directory permissions are not restricted."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("Guest account permissions are restricted."));
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckGuestsIfCanInvite([ControlResult] $controlResult)
	{
        $b2b = $this.B2BSettings
        if($b2b.limitedAccessCanAddExternalUsers -eq $true) #Guests can invite?
        {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        [MessageData]::new("Guest have privilege to invite other guests."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("Guest do not have the privilege to invite other guests."));
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckBaselineMFAPolicyForAdmins([ControlResult] $controlResult)
	{
        $adminSettings = $this.AdminMFASettings
        if($adminSettings.enable -eq $false -or $adminSettings.state -eq  0)
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                        [MessageData]::new("MFA is set as 'not required' for admin accounts."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("MFA is set as 'required' for admin accounts."));
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckUserPermissionsToCreateApps([ControlResult] $controlResult)
	{
        $aadPerms = $this.AADPermissions
        if($aadPerms.allowedActions.application.Contains('create')) #has to match case
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                        [MessageData]::new("Regular users have privilege to create new apps."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("Regular users do not have privilege to create new apps."));
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckUserPermissionToInviteGuests([ControlResult] $controlResult)
	{
        $aadPerms = $this.AADPermissions

        if($aadPerms.allowedActions.user.Contains('inviteguest')) #has to match case
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                        [MessageData]::new("Regular users have privilege to invite guests."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("Regular users do not have privilege to invite guests."));
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckMinQuestionsForSSPR([ControlResult] $controlResult)
	{
        $sspr = $this.CASettings
        if($sspr.numberOfQuestionsToReset -lt 3)
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                        [MessageData]::new("Found that less than 3 questions are required for password reset."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("Found that 3 or more questions are required for password reset."));
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckUserNotificationUponSSPR([ControlResult] $controlResult)
	{
        $sspr = $this.CASettings
        if($sspr.notifyUsersOnPasswordReset -ne $true)
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                        [MessageData]::new("User notification not configured for password resets."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("User notification is configured for password resets."));
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckAdminNotificationUponSSPR([ControlResult] $controlResult)
	{
        $sspr = $this.CASettings
        if($sspr.notifyOnAdminPasswordReset -ne $true)
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                        [MessageData]::new("Notification to all admins not configured for admin password resets."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("Notification to all admins is configured for admin password resets."));
        }
        return $controlResult;
    }
}