Set-StrictMode -Version Latest 
class ServicePrincipal: SVTBase
{    
    hidden [PSObject] $ResourceObject;
    hidden [String] $SPNName;
    ServicePrincipal([string] $tenantId, [SVTResource] $svtResource): Base($tenantId, $svtResource) 
    {
        #$this.GetResourceObject();
        $objId = $svtResource.ResourceId

        $this.ResourceObject = Get-AzureADObjectByObjectId -ObjectIds $objId
        $this.SPNName = "TODO_SPN_Name_Here" #? $this.ResourceObject.DisplayName
        
    }

    hidden [PSObject] GetResourceObject()
    {
        return $this.ResourceObject;
    }

    hidden [ControlResult] CheckSPNPasswordCredentials([ControlResult] $controlResult)
	{
        $spn = $this.GetResourceObject()

        if ($spn.PasswordCredentials.Count -gt 0)
        {
                $nPswd = $spn.PasswordCredentials.Count


                $controlResult.AddMessage([VerificationResult]::Failed,
                                        [MessageData]::new("Found $nPswd assword credentials on SPN: $($this.SPNName).")); 
                                        
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("Did not find any password credentials on SPN."));
        }
        return $controlResult;
    }
 
    hidden [ControlResult] ReviewLegacySPN([ControlResult] $controlResult)
	{
        $spn = $this.GetResourceObject()

        if ($spn.ServicePrincipalType -eq 'Legacy')
        {
                $controlResult.AddMessage([VerificationResult]::Verify,
                                        [MessageData]::new("Found an SPN of type 'Legacy'. Please review: $($this.SPNName)"));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("SPN is not of type 'Legacy'."));
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckCertNearingExpiry([ControlResult] $controlResult)
    {
        $spn = $this.GetResourceObject()

        $spk = [array] $spn.KeyCredentials
        if ($spk -eq $null -or $spk.Count -eq 0)
        {
            #No key creds, pass the control.
            $controlResult.AddMessage([VerificationResult]::Passed,
                                [MessageData]::new("SPN [$($spn.DisplayName)] does not have a key credential configured. Passing control by default."));

        }
        else 
        {
            $renew = @()
            $expireDays = 30
            $expiringSoon = ([DateTime]::Today).AddDays($expireDays)  #TODO: 30 days should be moved to config.
            $needToRenew = $false
            $spk | % {
                $k = $_
                if ($k.EndDate -le $expiringSoon)
                {
                    $renew += $k.KeyId
                    $needToRenew = $true
                }
            }

            if ($needToRenew -eq $true) #found some key close to expiry
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                    [MessageData]::new("One or more keys of SPN [$($spn.DisplayName)] have expired or are nearing expiry (<$expireDays days)."));

                $renewList = $renew -join ", "
                $controlResult.AddMessage([MessageData]::new("KeyIds nearing expiry:`n`t$renewList"));
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                            [MessageData]::new("None of the configured keys for SPN [$($spn.DisplayName)] are nearing expiry (<$expireDays days)."));
            }
        }
        return $controlResult;
    }

    <#
        hidden [ControlResult] TBD([ControlResult] $controlResult)
        {
            $spn = $this.GetResourceObject()

            if ($spn.xyz)
            {
                    $controlResult.AddMessage([VerificationResult]::Failed,
                                            [MessageData]::new("Todo. Please review: $($this.SPNName)"));
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                            [MessageData]::new("Todo. PassMsg."));
            }
            return $controlResult;
        }
    #>
}