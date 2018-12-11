Set-StrictMode -Version Latest 
class HDInsight: SVTBase
{
    hidden [PSObject] $ResourceObject;
    HDInsight([string] $subscriptionId, [SVTResource] $svtResource):
    Base($subscriptionId, $svtResource)
    { 
        $this.PublishCustomMessage("Currently HDInsight contains only cluster level controls. More controls will be added in future releases.", [MessageType]::Warning);
        $this.GetResourceObject();
    }

    hidden [void] GetResourceObject()
    {
        if (-not $this.ResourceObject)
		{
            $this.ResourceObject = Get-AzureRmResource -ResourceId $this.ResourceContext.ResourceId -ExpandProperties
            if(-not $this.ResourceObject)
            {
				throw ([SuppressedException]::new(("Resource '$($this.ResourceContext.ResourceName)' not found under Resource Group '$($this.ResourceContext.ResourceGroupName)'"), [SuppressedExceptionType]::InvalidOperation))
            }

        }
    }

    hidden [ControlResult] CheckClusterVersion([ControlResult] $controlResult)
	{
        if([Helpers]::CheckMember($this.ResourceObject,"Properties.clusterVersion"))
		{
            #Validate if cluster version is below supported or retired version
			if([version]$this.ResourceObject.Properties.clusterVersion -gt [version]$this.ControlSettings.HDInsight.MinSupportedClusterVersion)
			{
                $controlResult.AddMessage([VerificationResult]::Passed,
                                        "Supported HDI cluster version available");
			}
			else
			{
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        "Retired HDI cluster version found: "+$this.ResourceObject.ClusterVersion);
			}
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Manual,
                                    "Not able to find HDI cluster version");
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckClusterNetworkProfile([ControlResult] $controlResult)
	{
        if([Helpers]::CheckMember($this.ResourceObject,"Properties.computeProfile.roles"))
		{

            $clusterRoles = $this.ResourceObject.Properties.computeProfile.roles
            $clusterRolesWithoutNetworkProfile = @()
            #Validate if network profile is defined for all cluster roles like head,worker,zookipper nodes
            $clusterRoles | ForEach-Object {
                if(-not [Helpers]::CheckMember($_,"virtualNetworkProfile"))
                {
                    $clusterRolesWithoutNetworkProfile += $_.name
                }
            }
			if($clusterRolesWithoutNetworkProfile.Count -gt 0)
			{
                $controlResult.AddMessage([VerificationResult]::Failed,
                                        "Network profile is not defined for HDI cluster roles", $clusterRolesWithoutNetworkProfile);
			}
			else
			{
                $controlResult.AddMessage([VerificationResult]::Passed,
                                        "Network profile found for all HDI cluster roles");
			}
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Manual,
                                    "Not able to find HDI cluster roles");
        }
        return $controlResult;
    }  
}