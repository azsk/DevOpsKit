#using namespace Microsoft.Azure.Commands.AppService.Models
Set-StrictMode -Version Latest
class DBForPostgreSQL: AzSVTBase
{

    DBForPostgreSQL([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId, $svtResource)
    {
		$this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
    }

}
