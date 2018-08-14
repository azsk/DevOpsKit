Set-StrictMode -Version Latest 
class DataLakeStore: SVTBase
{       
    hidden [PSObject] $ResourceObject;

    DataLakeStore([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
        $this.GetResourceObject();
    }

    DataLakeStore([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzureRmDataLakeStoreAccount -Name $this.ResourceContext.ResourceName `
                                            -ResourceGroupName $this.ResourceContext.ResourceGroupName
            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }
    
	hidden [ControlResult] CheckFirewall([ControlResult] $controlResult)
    {   
		$firewallSetting = New-Object PSObject
		Add-Member -InputObject $firewallSetting -MemberType NoteProperty -Name FirewallState -Value $this.ResourceObject.FirewallState   
		Add-Member -InputObject $firewallSetting -MemberType NoteProperty  -Name FirewallRules -Value $this.ResourceObject.FirewallRules

		#Check for any to any rule (0.0.0.0-255.255.255.255)
        $anyToAnyRuleCount = 0
		if(($firewallSetting.FirewallRules|Measure-Object).Count -gt 0)
		{
			$anyToAnyRuleCount = (($firewallSetting.FirewallRules | Where-Object{ 
			$_.StartIpAddress -eq $this.ControlSettings.IPRangeStartIP -and $_.EndIpAddress -eq  $this.ControlSettings.IPRangeEndIP}) | Measure-Object).count        
		}

		if($firewallSetting.FirewallState -eq "Disabled") 
		{  
		   $controlResult.AddMessage([VerificationResult]::Failed, "Firewall status : ", $firewallSetting.FirewallState)
		} 
		elseif($anyToAnyRuleCount -gt 0)
		{
			$controlResult.AddMessage("Firewall rules - [$this.ResourceContext.ResourceName]", $firewallSetting.FirewallRules)
			$controlResult.AddMessage([VerificationResult]::Failed,"Any to Any firewall rule `
			(Start IP address: $this.ControlSettings.IPRangeStartIP To End IP Address :$this.ControlSettings.IPRangeEndIP) `
			is defined which must be removed.")
			$controlResult.SetStateData("Firewall rules", $firewallSetting.FirewallRules);                      
		}
		elseif(($firewallSetting.FirewallRules | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage([VerificationResult]::Verify, "Please verify Firewall rules", $firewallSetting.FirewallRules)
			$controlResult.SetStateData("Firewall rules", $firewallSetting.FirewallRules)  
		}
		else
		{
			$controlResult.VerificationResult = [VerificationResult]::Passed
		}
       
        return $controlResult;
    }
		
	hidden [ControlResult] CheckACLAccess([ControlResult] $controlResult)
    {  
			$rootAcl= $null 
			$otherACLDetails = $null 
			try
			{
				$rootAcl=Get-AzureRmDataLakeStoreItemAclEntry -Account $this.ResourceContext.ResourceName -Path "/" -ErrorAction Stop
			}
			catch
			{
				if([Helpers]::CheckMember($_.Exception, "HttpStatus") -and ($_.Exception).HttpStatus -eq [System.Net.HttpStatusCode]::Forbidden)
				{
					$controlResult.AddMessage("Access denied: The user does not have the permission to perform this operation. Please check firewall and ACL settings.");
					return $controlResult
				}
				else
				{
					throw $_
				}
			}
		
			$displayAclObj =  $rootAcl | Select-Object Scope,Type,Id,Permission
			$controlResult.AddMessage("Current ACL setting for root folder of data lake store:", $displayAclObj)		
			
			#check if ACL access is enabled for "Other" users (Public access) 
			$otherACLDetails= $rootAcl | where-object { $_.Type -eq "Other" -and ($_.Scope -eq "Access" -or $_.Scope -eq "Default") } | Where-Object {$_.Permission -ne "---"} 
			$isCompliant =  $null -eq $otherACLDetails 
			if($isCompliant)
			{
				$controlResult.VerificationResult = [VerificationResult]::Passed; 
			}
			else
			{
				$displayOtherPermission = $otherACLDetails |  Select-Object Scope,Type,Id,Permission
				$controlResult.AddMessage( [VerificationResult]::Failed, "Other have access to root folder of data lake store:", $displayOtherPermission)	
				$controlResult.SetStateData("Root folder ACL", $displayOtherPermission); 
			}	
     	
        return $controlResult;
    }

	hidden [ControlResult] CheckEncryptionAtRest([ControlResult] $controlResult)
    {   
		$encryptionSettings = $this.ResourceObject | Select-Object -Property EncryptionConfig, EncryptionState, EncryptionProvisioningState
		if($this.ResourceObject.EncryptionState -eq [Microsoft.Azure.Management.DataLake.Store.Models.EncryptionState]::Enabled)
		{
			$controlResult.VerificationResult = [VerificationResult]::Passed;
		}
		else
		{
			$controlResult.VerificationResult = [VerificationResult]::Failed;
		}

		$controlResult.AddMessage("Encryption settings of Data Lake Store account", $encryptionSettings);	
		return $controlResult;
    }
   
}
