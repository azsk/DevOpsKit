#using namespace Microsoft.Azure.Commands.Search.Models
Set-StrictMode -Version Latest 
class Search: SVTBase
{       
    hidden [PSObject] $ResourceObject;

    Search([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
        $this.GetResourceObject();
    }

	Search([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzureRmResource -Name $this.ResourceContext.ResourceName  `
                                        -ResourceType  "Microsoft.Search/searchServices" `
                                        -ResourceGroupName $this.ResourceContext.ResourceGroupName `
                                        -ErrorAction Stop

            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }

        return $this.ResourceObject;
    }

    hidden [ControlResult] CheckSearchReplicaCount([ControlResult] $controlResult)
   {
        $replicaCount = $this.ResourceObject.Properties.replicaCount
	    $isCompliant =  $replicaCount -ge 3
        if($isCompliant) 
        {
          $controlResult.AddMessage([VerificationResult]::Passed,
                                    [MessageData]::new("Replica count for resource " + $this.ResourceContext.ResourceName + " is " + $replicaCount)); 
        }
        else
        {
          $controlResult.AddMessage([VerificationResult]::Failed,
                                    [MessageData]::new("Replica count for resource " + $this.ResourceContext.ResourceName + " is " + $replicaCount));
        }
        
        return $controlResult;
    }
}
