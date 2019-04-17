Set-StrictMode -Version Latest 
class User: SVTBase
{    
    hidden [PSObject] $ResourceObject;

    User([string] $tenantId, [SVTResource] $svtResource): Base($tenantId, $svtResource) 
    {
        $objId = $svtResource.ResourceId
        $this.ResourceObject = Get-AzureADUser -ObjectId $objId    
    }

    hidden [PSObject] GetResourceObject()
    {
        return $this.ResourceObject;
    }

    hidden [ControlResult] CheckPasswordExpiration([ControlResult] $controlResult)
	{
        $u = $this.GetResourceObject();
        $pp = $u.PasswordPolicies
        if($pp -ne $null -and $pp -match 'DisablePasswordExpiration' ) 
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                "User [$($u.DisplayName)] has 'password expiration' disabled. Please review!");
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                "User does not have password expiration disabled.");
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckStrongPassword([ControlResult] $controlResult)
	{
        $u = $this.GetResourceObject();
        $pp = $u.PasswordPolicies
        if($pp -ne $null -and $pp -match 'DisableStrongPassword' ) 
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                "User [$($u.DisplayName)] has 'strong password' disabled. Please review!");
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                "User does not have 'strong password' disabled.");
        }
        return $controlResult;
    }
}