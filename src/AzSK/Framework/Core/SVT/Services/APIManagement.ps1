Set-StrictMode -Version Latest 
class APIManagement: SVTBase
{       
    APIManagement([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    {  }

	APIManagement([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    {  }

	hidden [ControlResult] CheckAPIMMetricAlert([ControlResult] $controlResult)
    {
		$this.CheckMetricAlertConfiguration($this.ControlSettings.MetricAlert.APIManagement, $controlResult, "");
		return $controlResult;
    }
    hidden [ControlResult] CheckAPIMURLScheme([ControlResult] $controlResult)
    {
        $apimContext = New-AzureRmApiManagementContext -ResourceGroupName $this.ResourceContext.ResourceGroupName -ServiceName $this.ResourceContext.ResourceName         
        $noncompliantAPIs = Get-AzureRmApiManagementApi -Context $apimContext | where-object{$_.Protocols.count -gt 1 -or $_.Protocols[0] -ne 'https' }
        if(($noncompliantAPIs|Measure-Object).Count -gt 0)
        {
            $controlResult.AddMessage([VerificationResult]::Failed, "Below API(s) are configured to use non-secure HTTP access to the backend via API Management.", $noncompliantAPIs)
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"")
        }
        
		return $controlResult;
    }

    hidden [ControlResult] CheckSecretNamedValues([ControlResult] $controlResult)
    {
        $apimContext = New-AzureRmApiManagementContext -ResourceGroupName $this.ResourceContext.ResourceGroupName -ServiceName $this.ResourceContext.ResourceName         
        $allNamedValues = @()
        $allNamedValues += Get-AzureRmApiManagementProperty -Context $apimContext 
        if($allNamedValues.count -eq 0)
        {
            $controlResult.AddMessage([VerificationResult]::Passed, "Named Values are not added.")
            
        }
        else
        {
            $nonsecretNamedValues = $allNamedValues | where-object {$_.Secret -eq $false}
            if(($nonsecretNamedValues|Measure-Object).Count -gt 0)
            {
                $controlResult.AddMessage([VerificationResult]::Verify, "Below Named Values are not marked as secret values. Please mark it as secret if it contains critical data.", $nonsecretNamedValues)
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "")
            }
        } 
		return $controlResult;
    }
    hidden [ControlResult] CheckNonARMAPIUsage([ControlResult] $controlResult)
    {
        $apimContext = New-AzureRmApiManagementContext -ResourceGroupName $this.ResourceContext.ResourceGroupName -ServiceName $this.ResourceContext.ResourceName         
        $tanantAccess = Get-AzureRmApiManagementTenantAccess -Context $apimContext
        if($null -ne $tanantAccess -and $tanantAccess.Enabled -eq $true)
        {
            $controlResult.AddMessage([VerificationResult]::Failed, "Access to non-ARM based REST API is enabled for this API Management service.") 
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"")
        } 
		return $controlResult;
    }
}