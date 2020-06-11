Set-StrictMode -Version Latest
class Context
{
    [Account] $Account = [Account]::new();
    [Subscription] $Subscription = [Subscription]::new();
    [EnvironmentDetails] $Environment = [EnvironmentDetails]::new();
    [Tenant] $Tenant = [Tenant]::new();
    [string] $AccessToken;
    [DateTime] $TokenExpireTimeLocal;
}

class Account {
   [string] $Id;
    [AccountType] $Type = [AccountType]::User;
}

enum AccountType{
    User
    ServicePrincipal
    ServiceAccount
}

class Subscription{
    [string] $Id;
    [string] $Name;
}

class EnvironmentDetails {
    [string] $Name;
}

class Tenant{
    [string] $Id
}

enum CommandType
{
	Azure
	AzureDevOps
	AAD
}