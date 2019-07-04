#using namespace Microsoft.Azure.Commands.EventHub.Models
Set-StrictMode -Version Latest 
class ODG: AzSVTBase
{       

	ODG([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
    }
}