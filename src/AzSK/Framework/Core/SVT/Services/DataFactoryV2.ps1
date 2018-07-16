#using namespace Microsoft.Azure.Commands.DataFactory.Models
Set-StrictMode -Version Latest 
class DataFactoryV2: SVTBase
{       

    DataFactoryV2([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
    }

	DataFactoryV2([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
    }
}