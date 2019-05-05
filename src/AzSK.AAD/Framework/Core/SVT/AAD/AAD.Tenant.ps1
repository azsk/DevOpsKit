Set-StrictMode -Version Latest 
class Tenant: SVTBase
{    
    hidden [PSObject] $AADPermissions;

    hidden [PSObject] $CASettings;
    hidden [PSObject] $AdminMFASettings;
    hidden [PSObject] $B2BSettings;
    hidden [PSObject] $MFASettings;
    hidden [PSObject] $SSPRSettings;
    hidden [PSObject] $EnterpriseAppSettings;
    hidden [PSObject] $MFABypassList;
    #static [int] $RecommendedMaxDevicePerUserLimit = 20;
    hidden [PSObject] $DeviceSettings;

    Tenant([string] $tenantId, [SVTResource] $svtResource): Base($tenantId, $svtResource) 
    {
        $this.GetAADSettings()
    }

    hidden GetAADSettings()
    {
        $this.PublishCustomMessage("`nQuerying tenant API endpoints. This may take a few seconds...");

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

        if ($this.MFASettings -eq $null)
        {
            $this.MFASettings = [WebRequestHelper]::InvokeAADAPI("/api/MultiFactorAuthentication/TenantModel")
        }

        if ($this.B2BSettings -eq $null)
        {
            $this.B2BSettings = [WebRequestHelper]::InvokeAADAPI("/api/Directories/B2BDirectoryProperties")
        }

        if ($this.DeviceSettings -eq $null)
        {
            $this.DeviceSettings = [WebRequestHelper]::InvokeAADAPI("/api/DeviceSetting")
        }

        if ($this.MFABypassList -eq $null)
        {
            $this.MFABypassList = [WebRequestHelper]::InvokeAADAPI("/api/MultifactorAuthentication/BypassedUser")
        }

        if ($this.SSPRSettings -eq $null)
        {
            $this.SSPRSettings = [WebRequestHelper]::InvokeAADAPI("/api/PasswordReset/PasswordResetPolicies")
        }

        if ($this.EnterpriseAppSettings -eq $null)
        {
            $this.EnterpriseAppSettings = [WebRequestHelper]::InvokeAADAPI("/api/EnterpriseApplications/UserSettings")
        }

        if ($this.AADPermissions -eq $null -or 
            $this.CASettings -eq $null -or
            $this.AdminMFASettings -eq $null -or
            $this.MFASettings -eq $null -or
            $this.B2BSettings -eq $null -or
            $this.DeviceSettings -eq $null -or
            $this.MFABypassList -eq $null -or
            $this.SSPRSettings -eq $null -or
            $this.EnterpriseAppSettings -eq $null
        )
        {
            Write-Host -ForegroundColor Yellow "`nYou may not have sufficient permission to evaluate all controls.`nStatus for controls that could not be evaluated will show as 'Manual' in the report."
        }
    }

    [ControlItem[]] ApplyServiceFilters([ControlItem[]] $controls)
	{
		if($controls.Count -eq 0)
		{
			return $controls;
		}

		$result = $controls;

        $sspr = $this.CASettings

        #If we definitively determine that SSPR is not enabled for this tenant, exclude SSPR-specific controls
		if ($sspr -ne $null -and $sspr.EnablementType -eq 0)
		{
			$result = $result | Where-Object {$_.Tags -notcontains "SSPR"}
		}

		return $result;
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


    hidden [ControlResult] MFACheckUsersCanNotifyFraud([ControlResult] $controlResult)
	{
        $mfa = $this.MFASettings
        if ($mfa -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission"));
        }
        elseif($mfa.enableFraudAlert -eq $true) #Users can notify about fraud
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                [MessageData]::new("Users have the permission to raise fraud alerts."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                               [MessageData]::new("Users do not have the permission to raise fraud alerts."));

        }
        return $controlResult;
    }

    hidden [ControlResult] MFAReviewBypassedUsers([ControlResult] $controlResult)
	{
        $bp = $this.MFABypassList
        if ($bp -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission")); #BUGBUG: Empty BP list case?
        }
        elseif($bp.Count -eq 0) #No users on bypass list
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                [MessageData]::new("No users found on the MFA bypass list."));
        }
        else
        {
            $bpUsers = @()
            $bp | % {$bpUsers += $_.Username}
            $bpUsersList = $bpUsers -join ", "
            $controlResult.AddMessage([VerificationResult]::Verify,
                               [MessageData]::new("Found the following users on MFA bypass list. Please review.`n`t $bpUsersList" ));

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

    hidden [ControlResult] CheckEnoughGlobalAdmins([ControlResult] $controlResult)
	{

        $ca = Get-AzureAdDirectoryRole -Filter "DisplayName eq 'Company Administrator'"
        $rm = @()

        try 
        {
            $rm = @(Get-AzureADDirectoryRoleMember -ObjectId $ca.ObjectId)
        }
        catch 
        {
            $rm = $null
        }
        
        $recommendedMinGlobalAdmins = $this.ControlSettings.Tenant.RecommendedMinGlobalAdmins
        if ($rm -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission"));
        }
        elseif ($rm.Count -le $recommendedMinGlobalAdmins) 
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                [MessageData]::new("Only [$($rm.Count)] global administrator(s) found."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                [MessageData]::new("Found [$($rm.Count)] global administrators."));
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckNoGuestsInGlobalAdminRole([ControlResult] $controlResult)
	{
        #TODO: Move this to common/.ctor similar to API calls.
        #TODO: Expand this to other privileged roles (Security Admin, etc. - see AccountHelper)
        #TODO: This and other RBAC checks should cover PIM-eligible members.
        $ca = Get-AzureAdDirectoryRole -Filter "DisplayName eq 'Company Administrator'"
        $rm = @()

        try 
        {
            $rm = @(Get-AzureADDirectoryRoleMember -ObjectId $ca.ObjectId)
        }
        catch 
        {
            $rm = $null
        }
        
        if ($rm -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission"));
        }
        else
        {
            $foundGuests = $false
            $guests = @()
            
            $rm | % {if ($_.ObjectType -eq 'User' -and $_.UserType -eq 'Guest') {$foundGuests = $true; $guests += "$($_.DisplayName) ($($_.ObjectId))"}}
            $guestList = $guests -join "`n`t"
            if ($foundGuests)
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                    [MessageData]::new("Found the following 'Guest' users in Global Admin role: `n`t$guestList."));
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                    [MessageData]::new("Did not find any 'Guest' member in Global Admin role."));
            }
        }
        return $controlResult;
    }

    
    hidden [ControlResult] CheckTenantDataAccessForApps([ControlResult] $controlResult)
	{
        $eas = $this.EnterpriseAppSettings

        if ($eas -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission")); #BUGBUG: Empty BP list case?
        }
        elseif($eas.usersCanAllowAppsToAccessData -eq $true) #Users can approve apps to access tenant data
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                [MessageData]::new("Users are permitted to approve app access to tenant data without admin consent."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                               [MessageData]::new("Users are not permitted to approve app access to tenant data without admin consent." ));

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

    

    hidden [ControlResult] SSPRMinAuthNMethodsRequired([ControlResult] $controlResult)
	{
        $sspr = $this.SSPRSettings
        $minAuthNMethodsRequired = $this.ControlSettings.Tenant.SSPRMinAuthNMethodsRequired
        if ($sspr -eq $null)
        {
            $controlResult.AddMessage([VerificationResult]::Manual,
                [MessageData]::new("Unable to evaluate control. You may not have sufficient permission")); #BUGBUG: Empty BP list case?
        }
        elseif($sspr.numberOfAuthenticationMethodsRequired -ge $minAuthNMethodsRequired)
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                [MessageData]::new("More than one authentication methods are required to reset password."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                               [MessageData]::new("Ensure that at least two methods are required during a self-service password reset." ));

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
            $recommendedMaxDevicePerUserLimit = $this.ControlSettings.Tenant.RecommendedMaxDevicePerUserLimit
            if ($ds.maxDeviceNumberPerUserSetting -gt $recommendedMaxDevicePerUserLimit)
            {
                    $controlResult.AddMessage([VerificationResult]::Failed,
                                            [MessageData]::new("Max device per user limit is not set or too high. Recommended: ["+ $recommendedMaxDevicePerUserLimit + "]."));
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