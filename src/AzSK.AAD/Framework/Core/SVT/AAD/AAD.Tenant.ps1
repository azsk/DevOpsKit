Set-StrictMode -Version Latest 
class Tenant: SVTBase
{    
    hidden [PSObject] $AADPermissions;

    hidden [PSObject] $CASettings;
    hidden [PSObject] $AdminMFASettings;
    hidden [PSObject] $B2BSettings;
    static [int] $RecommendedMaxDevicePerUserLimit = 20; #TODO: ControlSettings
    hidden [PSObject] $DeviceSettings;

    Tenant([string] $tenantId, [SVTResource] $svtResource): Base($tenantId, $svtResource) 
    {
        $this.GetAADSettings()
    }

    hidden GetAADSettings()
    {
        if ($this.AADPermissions -eq $null)
        {
            $this.AADPermissions = [WebRequestHelper]::InvokeAADAPI("/api/Permissions")
        }

        if ($this.CASettings -eq $null)
        {
            $this.CASettings = [WebRequestHelper]::InvokeAADAPI("/api/PasswordReset/PasswordResetPolicies")
        }

        if ($this.AdminMFASettings -eq $null)
        {
            $this.AdminMFASettings = [WebRequestHelper]::InvokeAADAPI("/api/BaselinePolicies/RequireMfaForAdmins")
        }

        if ($this.B2BSettings -eq $null)
        {
            $this.B2BSettings = [WebRequestHelper]::InvokeAADAPI("/api/Directories/B2BDirectoryProperties")
        }

        if ($this.DeviceSettings -eq $null)
        {
            $this.DeviceSettings = [WebRequestHelper]::InvokeAADAPI("/api/DeviceSetting")
        }
    }

    hidden [ControlResult] CheckTenantSecurityContactInfoIsSet([ControlResult] $controlResult)
    {
        $td = Get-AzureADTenantDetail

        $result = $false
        $missing = ""
        try {
            #Check that at least 1 email and at least 1 phone number are set.
            $bEmail = ($td.SecurityComplianceNotificationMails.Count -gt 0 -and -not [string]::IsNullOrEmpty($td.SecurityComplianceNotificationMails[0]))
            $bPhone = ($td.SecurityComplianceNotificationPhones.Count -gt 0 -and -not [string]::IsNullOrEmpty($td.SecurityComplianceNotificationPhones[0]))
            if ($bEmail -and $bPhone )
            {
                $result = $true
            }
            else {
                $missing = if (-not $bEmail) {"`n`tSecurityComplianceNotificationMails "} else {""} 
                $missing += if (-not $bPhone) {"`n`tSecurityComplianceNotificationPhone"} else {""}
            }
        }
        catch {
            $controlResult.AddMessage([VerificationResult]::Error, [MessageData]::new("Error reading Security Compliance Notification settings. Perhaps your AAD SKU does not support them."));
        }

        if ($result -eq $false)
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                    [MessageData]::new("Security compliance notification are not correctly set for the tenant."));
            $controlResult.AddMessage("The following are missing: $missing")
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("Security compliance notification phone/email are both set as expected."));
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckGuestsHaveLimitedAccess([ControlResult] $controlResult)
	{
        $b2b = $this.B2BSettings

        if ($b2b -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission"));
        }
        elseif($b2b.restrictDirectoryAccess -ne $true) #Guests permissions are limited?
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
        if ($b2b -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission"));
        }
        elseif($b2b.limitedAccessCanAddExternalUsers -eq $true) #Guests can invite?
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
        if ($adminSettings -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission"));
        }
        elseif($adminSettings.enable -eq $false -or $adminSettings.state -eq  0)
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
        if ($aadPerms -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission"));
        }
        elseif ($aadPerms.allowedActions.application.Contains('create')) #has to match case
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

        if ($aadPerms -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission"));
        }
        elseif($aadPerms.allowedActions.user.Contains('inviteguest')) #has to match case
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
        if ($sspr -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission"));
        }
        elseif ($sspr.numberOfQuestionsToReset -lt 3)
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
        if ($sspr -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission"));
        }
        elseif($sspr.notifyUsersOnPasswordReset -ne $true)
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
        if ($sspr -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission"));
        }
        elseif($sspr.notifyOnAdminPasswordReset -ne $true)
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

    hidden [ControlResult] CheckRequireMFAForJoin([ControlResult] $controlResult)
    {
        $ds = $this.DeviceSettings

        if ($ds -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                            [MessageData]::new("Unable to evaluate control. You may not have sufficient permission"));           
        }
        else
        {
            if (-not $ds.requireMfaSetting)
            {
                    $controlResult.AddMessage([VerificationResult]::Failed,
                                            [MessageData]::new("Please enable MFA as a requirement for joining devices to the tenant."));
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                            [MessageData]::new("MFA is enabled as a requirement for joining new devices to the tenant."));
            }
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckMaxDeviceLimitSet([ControlResult] $controlResult)
    {
        $ds = $this.DeviceSettings

        if ($ds -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission"));           
        }
        else
        {
            if ($ds.maxDeviceNumberPerUserSetting -gt [Tenant]::RecommendedMaxDevicePerUserLimit)
            {
                    $controlResult.AddMessage([VerificationResult]::Failed,
                                            [MessageData]::new("Max device per user limit is not set or too high. Recommended: ["+ [Tenant]::RecommendedMaxDevicePerUserLimit + "]."));
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                            [MessageData]::new("Max device per user limit is set at [$($ds.maxDeviceNumberPerUserSetting)]."));
            }
        }
        return $controlResult;
    }
}