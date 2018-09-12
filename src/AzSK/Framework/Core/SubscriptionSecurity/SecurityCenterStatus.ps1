using namespace System.Management.Automation
Set-StrictMode -Version Latest 

# The class serves as an intermediate class to call SecurityCenter class
# SecurityCenter class is being used in SubscriptionCore
class SecurityCenterStatus: CommandBase
{   
	
	[string] $SecurityContactEmails;
	[string] $SecurityPhoneNumber;

	SecurityCenterStatus([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext)
    { }

	[string] SetPolicies()
    {	
		$secCenter = [SecurityCenter]::new($this.SubscriptionContext.SubscriptionId);

		if ($secCenter) 
		{
			return $this.InvokeFunction($secCenter.SetPolicies, @($this.SecurityContactEmails, $this.SecurityPhoneNumber));
		}

		return "";
    }
	
}
