#using namespace Microsoft.Azure.Commands.EventHub.Models
Set-StrictMode -Version Latest 
class ODG: SVTBase
{       

	ODG([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
    }
}