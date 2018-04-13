Set-StrictMode -Version Latest 

class FixControlConfig
{
	[SubscriptionContext] $SubscriptionContext;
	[ResourceGroupConfig[]] $ResourceGroups = @();
	[ControlParam[]] $SubscriptionControls = @();
}

class ResourceGroupConfig
{
	[string] $ResourceGroupName = "" 
	[ResourceConfig[]] $Resources = @();
}

class ResourceConfig
{
	[string] $ResourceName = "" 
	[string] $ResourceType = ""  
	[string] $ResourceTypeName = ""  
	[ControlParam[]] $Controls = @();
	hidden [ResourceTypeMapping] $ResourceTypeMapping = $null;
}

class ControlParam
{
	[string] $ControlID = ""
	[string] $Id = ""
	[ControlSeverity] $ControlSeverity = [ControlSeverity]::High
    [FixControlImpact] $FixControlImpact = [FixControlImpact]::High;
	[string] $Description = "";
	[bool] $Enabled = $true;

	[ChildResourceParam[]] $ChildResourceParams = @();
}

class ChildResourceParam
{
	[string] $ChildResourceName = "" 
	[PSObject] $Parameters = $null;
}


class ArrayWrapper 
{ 
	[PSObject[]] $Values = @(); 
	ArrayWrapper([PSObject[]] $values)
	{
		$this.Values = @();
		if($values)
		{
			$this.Values += $values;
		}
	}
} 