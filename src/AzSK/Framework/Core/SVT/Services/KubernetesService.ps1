Set-StrictMode -Version Latest 
class KubernetesService: SVTBase
{

	hidden [PSObject] $ResourceObject;
	
	KubernetesService([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
		$this.GetResourceObject();
    }

    KubernetesService([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
		$this.GetResourceObject();
    }

	hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) 
		{
			$ResourceAppIdURI = [WebRequestHelper]::AzureManagementUri;
            $AccessToken = [Helpers]::GetAccessToken($ResourceAppIdURI)
			if($null -ne $AccessToken)
			{

				$header = "Bearer " + $AccessToken
				$headers = @{"Authorization"=$header;"Content-Type"="application/json";}

				$uri=[system.string]::Format("https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.ContainerService/managedClusters/{2}?api-version=2018-03-31",$this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName)
				$result = ""
				$err = $null
				try {
					$result = [WebRequestHelper]::InvokeGetWebRequest($uri, $headers); 
					if(($null -ne $result) -and (($result | Measure-Object).Count -gt 0))
					{
						$this.ResourceObject = $result[0]
					}
				}
				catch{
					$err = $_
					if($null -ne $err)
					{
						throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
					}
				}
			}
        }
        return $this.ResourceObject;
    }

	hidden [controlresult[]] CheckClusterRBAC([controlresult] $controlresult)
	{
        if(([Helpers]::CheckMember($this.ResourceObject,"Properties")) -and [Helpers]::CheckMember($this.ResourceObject.Properties,"enableRBAC"))
		{
			$isClusterRBACEnabled = $this.ResourceObject.Properties.enableRBAC

			if($isClusterRBACEnabled)
			{
				$controlResult.VerificationResult = [VerificationResult]::Passed
			}
			else
			{
				$controlResult.VerificationResult = [VerificationResult]::Failed
			}
		}

		return $controlResult;
	}

	hidden [controlresult[]] CheckAADEnabled([controlresult] $controlresult)
	{
		if(([Helpers]::CheckMember($this.ResourceObject,"Properties")) -and [Helpers]::CheckMember($this.ResourceObject.Properties,"aadProfile"))
		{
			if([Helpers]::CheckMember($this.ResourceObject.Properties.aadProfile,"clientAppID") -and [Helpers]::CheckMember($this.ResourceObject.Properties.aadProfile,"serverAppID") -and [Helpers]::CheckMember($this.ResourceObject.Properties.aadProfile,"tenantID"))
			{
				$controlResult.AddMessage([VerificationResult]::Passed,
										[MessageData]::new("AAD profile configuration details", $this.ResourceObject.Properties.aadProfile));
			}
			else
			{
				$controlResult.VerificationResult = [VerificationResult]::Failed
			}
		}

		return $controlResult;
	}

	hidden [controlresult[]] CheckKubernetesVersion([controlresult] $controlresult)
	{
		if(([Helpers]::CheckMember($this.ResourceObject,"Properties")) -and [Helpers]::CheckMember($this.ResourceObject.Properties,"kubernetesVersion"))
		{
			$resourceKubernetVersion = [System.Version] $this.ResourceObject.Properties.kubernetesVersion
			$requiredKubernetsVersion = [System.Version] "1.11.3"

			if($resourceKubernetVersion -lt $requiredKubernetsVersion)
			{
				$controlResult.VerificationResult = [VerificationResult]::Failed
			}
			else
			{
				$controlResult.VerificationResult = [VerificationResult]::Passed
			}
		}

		return $controlResult;
	}
}