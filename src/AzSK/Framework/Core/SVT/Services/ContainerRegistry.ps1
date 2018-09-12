Set-StrictMode -Version Latest 
class ContainerRegistry: SVTBase
{       
    hidden [PSObject] $ResourceObject;
    hidden [PSObject] $AccessList;

    ContainerRegistry([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
        $this.GetResourceObject();
    }

    ContainerRegistry([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) 
		{
            $this.ResourceObject = Get-AzureRmContainerRegistry -Name $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName

            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }

            # Get RBAC data to avoid multiple calls
            $this.AccessList = [RoleAssignmentHelper]::GetAzSKRoleAssignmentByScope($this.GetResourceId(), $false, $true);
        }
        return $this.ResourceObject;
    }

	hidden [ControlResult] CheckAdminUserStatus([ControlResult] $controlResult)
    {
		$isAdminUserEnabled = $this.ResourceObject.AdminUserEnabled
		
		if($isAdminUserEnabled)
		{
			$controlResult.EnableFixControl = $true;
            $controlResult.VerificationResult = [VerificationResult]::Failed
		}
		else
		{
			$controlResult.VerificationResult = [VerificationResult]::Passed
		}
	
		return $controlResult;
    }

    hidden [ControlResult] CheckResourceRBACAccess([ControlResult] $controlResult)
    {
		return $this.CheckRBACAccess($controlResult, $this.AccessList)
    }

    hidden [ControlResult] CheckResourceAccess([ControlResult] $controlResult)
    {
        $nonSPIdentities = $this.AccessList | Where-Object { $_.Scope -eq $this.GetResourceId() -and $_.ObjectType -ne 'ServicePrincipal' };
        
        if(($nonSPIdentities | Measure-Object).Count -ne 0)
        {
            $controlResult.SetStateData("Non Service Principal identities having RBAC access at resource level", ($nonSPIdentities | Select-Object -Property ObjectId,RoleDefinitionId,RoleDefinitionName,Scope));
            
            $controlResult.AddMessage([VerificationResult]::Failed, 
                            [MessageData]::new("Validate that the following non Service Principal identities have explicitly provided with RBAC access to resource - ["+ $this.ResourceContext.ResourceName +"]"));

            $controlResult.AddMessage([MessageData]::new($nonSPIdentities));
        }
        else 
        {
            $controlResult.AddMessage([VerificationResult]::Verify, 
                            [MessageData]::new("Validate that the inherited non Service Principal identities should not be used to access the resource - ["+ $this.ResourceContext.ResourceName +"]"));
        }
  
        return $controlResult;
    }

    hidden [ControlResult] CheckContainerWebhooks([ControlResult] $controlResult)
    {

        $webhooks = Get-AzureRmContainerRegistryWebhook -RegistryName $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName -ErrorAction SilentlyContinue

        if(($webhooks | Measure-Object).Count -gt 0)
        {
            $controlResult.VerificationResult = [VerificationResult]::Verify; 
            $controlResult.SetStateData("Webhook configured to the Container Registry", ($webhooks | Select-Object -Property Actions, Config, Id, Scope, Status));
            $controlResult.AddMessage([MessageData]::new("Review that image vulnerability scan is configured for all the repositories through following webhook(s) to the Container Registry - ["+ $this.ResourceContext.ResourceName +"]", 
                                                $webhooks));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Failed, 
                            [MessageData]::new("Webhooks for image vulnerability scan is not configured for the Container Registry - ["+ $this.ResourceContext.ResourceName +"]"));
        }
  
        return $controlResult;
    }

    hidden [ControlResult] CheckContentTrust([ControlResult] $controlResult)
    {
        $result = $null;
        $uri = [System.String]::Format("{0}subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.ContainerRegistry/registries/{3}/listPolicies?api-version=2017-10-01", [WebRequestHelper]::AzureManagementUri, $this.SubscriptionContext.SubscriptionId, $this.ResourceContext.ResourceGroupName, $this.ResourceContext.ResourceName)
            
        try 
        { 	
            $result = [WebRequestHelper]::InvokeGetWebRequest($uri) 
        } 
        catch
        { 
            return $controlResult;
        }
  
        $isPolicyEnabled = $false
        if($null -ne $result)
        {
            if([Helpers]::CheckMember($result,"trustPolicy.status"))
            {
                if($result.trustPolicy.status -eq "enabled")
                {
                    $isPolicyEnabled = $true
                }
            }
        }

        if($isPolicyEnabled -eq $true)
        {
            $controlResult.AddMessage([VerificationResult]::Verify, 
                            [MessageData]::new("Verify that all the images in the repository must be signed."));
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Failed, 
                            [MessageData]::new("Content Trust is not enabled for the Container Registry - ["+ $this.ResourceContext.ResourceName +"]"));
        }
        
        return $controlResult;
    }
}
