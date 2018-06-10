Set-StrictMode -Version Latest 
enum ScheduleFrequency
{
	Hour
	Day
}

class AutomationAccount
{
    hidden [string] $Name
	hidden [string] $CoreResourceGroup 
	hidden [string] $ResourceGroup 
	hidden [string] $Location		
	hidden [string] $AzureADAppName
	hidden [Hashtable] $RGTags
	hidden [Hashtable] $AccountTags
	hidden [int] $ScanIntervalInHours
    hidden [PSObject] $BasicResourceInstance
    hidden [PSObject] $DetailedResourceInstance
}
class UserConfig
{
	  hidden [string] $ResourceGroupNames
	  hidden [OMSCredential] $OMSCredential
	  hidden [OMSCredential] $AltOMSCredential
	  hidden [WebhookSetting] $WebhookDetails
	  hidden [string] $StorageAccountName
	  hidden [string] $StorageAccountRG
}

class WebhookSetting
{
	hidden [string] $Url;
	hidden [string] $AuthZHeaderName;
	hidden [string] $AuthZHeaderValue;
}

class OMSCredential
{
	hidden [string] $OMSWorkspaceId
	hidden [string] $OMSSharedKey
}
class SelfSignedCertificate
{
	 hidden [DateTime] $CertStartDate
	 hidden [DateTime] $CertEndDate
	 hidden [DateTime] $CredStartDate
	 hidden [DateTime] $CredEndDate
	 hidden [string] $Provider
	 SelfSignedCertificate()
	 {
		$this.CertStartDate = (Get-Date).AddDays(-1);
		$this.CertEndDate = (Get-Date).AddMonths(6).AddDays(1);          
		$this.CredStartDate = (Get-Date);
		$this.CredEndDate = (Get-Date).AddMonths(6);
		$this.Provider = "Microsoft Enhanced RSA and AES Cryptographic Provider"
	 }
}

class Runbook
{
	hidden [string] $Name 
	hidden [string] $Type 
	hidden [string] $Description
	hidden [boolean] $LogProgress
	hidden [boolean] $LogVerbose 
	hidden [string] $Key
	#tags of dictionary type
}

class RunbookSchedule
{
	hidden [string] $Name
	hidden [string] $Frequency
	hidden [int] $Interval
	hidden [System.DateTime] $StartTime
	hidden [System.DateTime] $ExpiryTime
	hidden [string] $Description
	hidden [string[]] $LinkedRubooks
	hidden [string] $Key
}

class Variable
{
	hidden [string] $Name
	hidden [string] $Value
	hidden [boolean] $IsEncrypted
	hidden [string] $Description
}
