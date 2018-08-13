Set-StrictMode -Version Latest 
class AnalysisServices: SVTBase
{    
	hidden [PSObject] $ResourceObject;
	   
    AnalysisServices([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
	     $this.GetResourceObject();
	}

    AnalysisServices([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
	    $this.GetResourceObject();
	}

	hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) 
		{
			#Using command Get-AzureRmResource to get resource details (Admin and Backups details).
			#Get-AzureRmAnalysisServicesServer command not provides Backups details 
            $this.ResourceObject = Get-AzureRmResource -Name $this.ResourceContext.ResourceName `
                                                       -ResourceGroupName $this.ResourceContext.ResourceGroupName `
                                                       -ResourceType $this.ResourceContext.ResourceType
            if(-not $this.ResourceObject)
            {
				throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }

    hidden [ControlResult] CheckAnalysisServicesAdmin([ControlResult] $controlResult)
    { 
		if($this.ResourceObject.Properties -and $this.ResourceObject.Properties.State)
		{
			if($this.ResourceObject.Properties.State -eq "Paused")
			{
				#Can not retrieve Analysis Services Admins details if analysis services state is 'Paused'
				$controlResult.AddMessage([MessageData]::new("Unable to fetch Analysis Services Admins as status is - [$($this.ResourceObject.Properties.State)]"))
				return $controlResult
			}
	
			#Get Admin count
			$adminCount = 0
			if(([Helpers]::CheckMember($this.ResourceObject.Properties ,"AsAdministrators")) -and  ([Helpers]::CheckMember($this.ResourceObject.Properties.AsAdministrators ,"members")))
			{
				$adminCount = ($this.ResourceObject.Properties.AsAdministrators.members  | Measure-Object).Count;
				$controlResult.SetStateData("Analysis Services admins", $this.ResourceObject.Properties.AsAdministrators.members);
			}

			#No admins
			if($adminCount -eq 0)
			{
				$controlResult.AddMessage([VerificationResult]::Verify, "Analysis Services admins are not configured"); 
			
			}
			#Threshold case
			elseif($adminCount -gt 0 -and $adminCount -le $this.ControlSettings.AnalysisService.Max_Admin_Count)
			{
				$controlResult.AddMessage([VerificationResult]::Verify, 
											"Validate that the following users require admin access on Analysis Services", 
											$this.ResourceObject.Properties.AsAdministrators.members); 
			}
			#Number of admins are more than permissible limit
			else
			{
				$controlResult.AddMessage([VerificationResult]::Failed, 
								"Number of admins exceeds the maximum recommended value of $($this.ControlSettings.AnalysisService.Max_Admin_Count). Validate that the following users require admin access on Analysis Services", 
								$this.ResourceObject.Properties.AsAdministrators.members); 
			}
        }
		else
		{
            $controlResult.AddMessage([MessageData]::new("Not able to fetch the required data for the resource", [MessageType]::Error)); 
		}
        return $controlResult;
    }

	hidden [ControlResult] CheckAnalysisServicesBCDRStatus([ControlResult] $controlResult)
	{
		if($this.ResourceObject.Properties){
			  #If Backup is enabled then Resource Properties object will have property with name 'backupBlobContainerUri' 
		      if(Get-Member -InputObject $this.ResourceObject.Properties -Name 'backupBlobContainerUri' -MemberType Properties)
				{
					 $controlResult.AddMessage([VerificationResult]::Passed,  [MessageData]::new("Backup is enabled"));
				}
				else
				{
					 $controlResult.AddMessage([VerificationResult]::Failed,  [MessageData]::new("Backup is not enabled"));
				}
		}
		else{
			 $controlResult.AddMessage([MessageData]::new("Not able to fetch the required data for the resource", [MessageType]::Error)); 
		}

		return $controlResult;
	}
}
