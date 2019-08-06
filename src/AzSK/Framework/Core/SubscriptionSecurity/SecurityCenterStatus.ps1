using namespace System.Management.Automation
Set-StrictMode -Version Latest 

# The class serves as an intermediate class to call SecurityCenter class
# SecurityCenter class is being used in SubscriptionCore
class SecurityCenterStatus: AzCommandBase
{   
	
	[string] $SecurityContactEmails;
	[string] $SecurityPhoneNumber;

	SecurityCenterStatus([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext)
    { }

	[string] SetPolicies([bool] $setOptionalPolicy)
    {	
		$secCenter = [SecurityCenter]::new($this.SubscriptionContext.SubscriptionId,$this.SecurityContactEmails, $this.SecurityPhoneNumber);

		if ($secCenter) 
		{
			$updatePolicies = $true;
			$updateSecurityContacts = $true;
			$updateProvisioningSettings = $true;
			return $this.InvokeFunction($secCenter.SetPolicies,@($updateProvisioningSettings,$updatePolicies,$updateSecurityContacts,$setOptionalPolicy));
		}

		return "";
    }
	
}
