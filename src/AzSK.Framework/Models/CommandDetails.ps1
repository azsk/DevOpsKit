Set-StrictMode -Version Latest  
class CommandDetails
{
	[string] $Noun = "";
	[string] $Verb = "";
	[string] $ShortName = "";
	[bool] $IsLatestRequired = $true;
	[bool] $IsOrgPolicyRequired = $true;
	[bool] $HasAzSKComponentWritePermission = $true;
}
