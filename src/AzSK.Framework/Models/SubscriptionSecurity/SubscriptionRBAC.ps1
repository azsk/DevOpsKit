Set-StrictMode -Version Latest 

# Defines data structure for subscription RBAC json
class SubscriptionRBAC
{
	[string] $ActiveCentralAccountsVersion;
	[string] $DeprecatedAccountsVersion;
	[ActiveRBACAccount[]] $ValidActiveAccounts = @();
	[RBACAccount[]] $DeprecatedAccounts = @();
}

class RBACAccount
{
	 #Fields from JSON
    [string] $Name = "";
    [string] $Description = "";
    [bool] $Enabled = $false;
    [string] $ObjectId = "";
    [string] $ObjectType = "";
    [RBACAccountType] $Type = [RBACAccountType]::Validate;
}

class ActiveRBACAccount: RBACAccount
{
    [string[]] $Tags = @();
    [string] $RoleDefinitionName = "";
	[string] $Scope = "";
}
class TelemetryRBAC
{
	[string] $SubscriptionId="";
	[string] $Scope="";
	[string] $DisplayName="";
	[string] $ObjectId="";
	[string] $ObjectType="";
	[string] $RoleAssignmentId="";
	[string] $RoleDefinitionId="";
	[string] $RoleDefinitionName="";
	[bool] $IsPIMEnabled;
}
enum RBACAccountType
{
	# AzSK should not Add/Delete the account
	Validate
	# The account can be fully managed (Add/Delete) from AzSK
	Provision
}