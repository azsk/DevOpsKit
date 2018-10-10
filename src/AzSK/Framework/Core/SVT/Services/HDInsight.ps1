Set-StrictMode -Version Latest 
class HDInsight: SVTBase
{
    HDInsight([string] $subscriptionId, [SVTResource] $svtResource):
    Base($subscriptionId, $svtResource)
    { 
        $this.PublishCustomMessage("Currently HDInsight contains only cluster level controls. More controls will be added in future releases.", [MessageType]::Warning);
    }
}