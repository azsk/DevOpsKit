Set-StrictMode -Version Latest 
class Group: SVTBase
{    
    hidden [PSObject] $ResourceObject;
    Group([string] $tenantId, [SVTResource] $svtResource): Base($tenantId, $svtResource) 
    {
        $objId = $svtResource.ResourceId
        $this.ResourceObject = Get-AzureADGroup -ObjectId $objId
    }

    hidden [PSObject] GetResourceObject()
    {
        return $this.ResourceObject;
    }

    hidden [ControlResult] CheckGroupsIsSecurityEnabled([ControlResult] $controlResult)
	{
        $g = $this.GetResourceObject()

        if($g.SecurityEnabled -eq $false)
        {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        [MessageData]::new("Group object is not security enabled."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("Group object is security enabled."));
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckGroupHasNonGuestOwner([ControlResult] $controlResult)
    {
        $g = $this.GetResourceObject()
        $go = [array] (Get-AzureADGroupOwner -ObjectId $g.ObjectId)

        #TODO: may need more logic (e.g., can Groups or SPNs be 'Group Owners'?)
        $ret = $false

        if ($go.Count -ne 0)
        {
            $go | % {
                $o = $_
                if ($o.ObjectType -eq 'User' -and $o.UserType -ne 'Guest')
                {
                    $ret = $true  #Pass only if we find at least one non-Guest user
                }
            }
        }
        else
        {
            #Group has no owners...fail!
            $ret = $false
        }

        if ($ret -eq $true)
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        [MessageData]::new("Found at least one non-guest owner for group: $($g.DisplayName)."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                        [MessageData]::new("Did not find at least one non-guest owner for group: $($g.DisplayName)."));
        }
        return $controlResult;
    }
}