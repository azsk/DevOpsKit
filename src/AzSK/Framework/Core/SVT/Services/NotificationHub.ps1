#using namespace Microsoft.Azure.Commands.KeyVault.Models
Set-StrictMode -Version Latest 
class NotificationHub: AzSVTBase
{       
    hidden [PSObject] $ResourceObject;
	hidden [PSObject] $NamespaceObject;

	NotificationHub([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = $this.ResourceContext.ResourceDetails
			$Namespace = $this.ResourceObject.Name.split("/")[0] 
			$this.NamespaceObject = Get-AzNotificationHubsNamespace -ResourceGroup $this.ResourceContext.ResourceGroupName -Namespace $Namespace

            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }


	hidden [ControlResult] CheckAuthorizationRule([ControlResult] $controlResult)
	{
		$resourceName = ($this.ResourceContext.ResourceName.Split("/")[1]);
        $accessPolicieswithManageRights =  (Get-AzNotificationHubAuthorizationRules `
                                                -ResourceGroup $this.ResourceContext.ResourceGroupName `
                                                -Namespace $this.NamespaceObject.Name `
                                                -NotificationHub $resourceName) `
                                                | Where-Object Rights -Contains "Manage" `
                                                | Select-Object -Property Name, Rights  
        if((($accessPolicieswithManageRights | Measure-Object).Count -eq 1) -and ($accessPolicieswithManageRights.Name -eq "DefaultFullSharedAccessSignature")) {
            $controlResult.AddMessage([VerificationResult]::Verify,
                            [MessageData]::new("Only the default authorization rule has 'Manage' security claim access rights for resource -  ["+ $this.ResourceContext.ResourceName +"]. Please ensure that these authorization rules are not used at the client end."  , 
                            $accessPolicieswithManageRights));

            $controlResult.SetStateData("Access policy with 'Manage' rights",$accessPolicieswithManageRights);
        }
        else {
                if($null -ne $accessPolicieswithManageRights){
                    $controlResult.AddMessage([VerificationResult]::Verify,
                                            [MessageData]::new("Authorization rules having 'Manage' security claim access rights for resource -  ["+ $this.ResourceContext.ResourceName +"]. Please ensure that these authorization rules are not used at the client end."  , 
                                            $accessPolicieswithManageRights));
            
                    $controlResult.SetStateData("Access policies with 'Manage' rights",$accessPolicieswithManageRights);
                }
                else{
                    $controlResult.AddMessage([VerificationResult]::Passed,
                                            [MessageData]::new("No authorization rules found with 'Manage' security claim access rights for resource -  ["+ $this.ResourceContext.ResourceName +"]"  , 
                                            $accessPolicieswithManageRights));
                }
        }

		return $controlResult;
	}
}
