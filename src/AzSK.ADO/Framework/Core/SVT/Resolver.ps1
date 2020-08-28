
Class Resolver : AzSKRoot {

    # Indicates to fetch all resource groups
	Resolver([string] $subscriptionId):Base($subscriptionId)
    {
        
    }
    Resolver([string] $subscriptionId,  [System.Security.SecureString] $PATToken):Base($subscriptionId, $PATToken)
    {
        
    }
}