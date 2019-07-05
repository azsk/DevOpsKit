Set-StrictMode -Version Latest

function Set-AzSKCredentialAlert { 
   
    <#
	.SYNOPSIS
	This command would help to set alert on expiring credentials.
	.DESCRIPTION
	This command would help to set alert on expiring credentials.
    
	.PARAMETER SubscriptionId
		Provide the subscription id.
	.PARAMETER CredentialLocation
		Provide the credential location.
	.PARAMETER CredentialName
		Provide the credential name.
	.PARAMETER RotationInterval
		Provide the rotation interval.
	.PARAMETER AlertEmail
		Provide the email id for alert.
	.PARAMETER AlertSMS
		Provide the contact number for alert.
    .PARAMETER Comment
		Provide the comment for the credential.
	
	.LINK
	https://aka.ms/azskossdocs

	#>
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = "Other", Position=0, HelpMessage = "Provide the subscription id")]
        #[Parameter(Mandatory = $true, ParameterSetName = "AppService", HelpMessage = "Provide the subscription id")]
        #[Parameter(Mandatory = $true, ParameterSetName = "KeyVault", HelpMessage = "Provide the subscription id")]
        [string]
        [ValidateNotNullOrEmpty()]
        [Alias("s")]
        $SubscriptionId,

        [Parameter(Mandatory = $true, ParameterSetName = "Other", Position=1, HelpMessage = "Provide the credential name")]
        #[Parameter(Mandatory = $true, ParameterSetName = "AppService", HelpMessage = "Provide the credential name")]
        #[Parameter(Mandatory = $true, ParameterSetName = "KeyVault", HelpMessage = "Provide the credential name")]
        [string]
		[Alias("cn")]
        $CredentialName,

        [Parameter(Mandatory = $true, ParameterSetName = "Other", HelpMessage = "Provide the credential location")]
        #[Parameter(Mandatory = $true, ParameterSetName = "AppService", HelpMessage = "Provide the credential location")]
        #[Parameter(Mandatory = $true, ParameterSetName = "KeyVault", HelpMessage = "Provide the credential location")]
        [ValidateSet("Other", "AppService", "KeyVault")]
        [string]
		[Alias("cl")]
        $CredentialLocation,

        [Parameter(Mandatory = $true, ParameterSetName = "Other", HelpMessage = "Provide the rotation interval in days")]
        #[Parameter(Mandatory = $true, ParameterSetName = "AppService", HelpMessage = "Provide the rotation interval")]
        #[Parameter(Mandatory = $true, ParameterSetName = "KeyVault", HelpMessage = "Provide the rotation interval")]
        [int]
		[Alias("rint")]
        $RotationIntervalInDays,

        [Parameter(Mandatory = $true, ParameterSetName = "Other", HelpMessage = "Provide the email id for alert")]
        #[Parameter(Mandatory = $true, ParameterSetName = "AppService", HelpMessage = "Provide the email id for alert")]
        #[Parameter(Mandatory = $true, ParameterSetName = "KeyVault", HelpMessage = "Provide the email id for alert")]
        #[string]
		[Alias("aem")]
        $AlertEmail,

        [Parameter(Mandatory = $false, ParameterSetName = "Other", HelpMessage = "Provide the contact number for alert")]
        #[Parameter(Mandatory = $false, ParameterSetName = "AppService", HelpMessage = "Provide the contact number for alert")]
        #[Parameter(Mandatory = $false, ParameterSetName = "KeyVault", HelpMessage = "Provide the contact number for alert")]
        #[string]
		[Alias("acn")]
        $AlertSMS,

        [Parameter(Mandatory = $true, ParameterSetName = "Other", HelpMessage = "Provide the comment for the credential")]
        #[Parameter(Mandatory = $true, ParameterSetName = "AppService", HelpMessage = "Provide the comment for the credential")]
        #[Parameter(Mandatory = $true, ParameterSetName = "KeyVault", HelpMessage = "Provide the comment for the credential")]
        [string]
		[Alias("cmt")]
        $Comment
    )
    Begin {
        [CommandHelper]::BeginCommand($MyInvocation);
        [ListenerHelper]::RegisterListeners();
    }
    Process {
        try {
			
            $cred = [CredRotation]::new($SubscriptionId, $PSCmdlet.MyInvocation);
            if($cred){
                $cred.credName = $CredentialName
                $cred.credLocation = $CredentialLocation
                $cred.rotationInt = $RotationIntervalInDays
                $cred.alertEmail = $AlertEmail
                if($AlertSMS){
                    $cred.alertPhoneNumber = $AlertSMS
                }
                $cred.comment = $Comment

                if($CredentialLocation -eq "Other"){
                    $cred.InvokeFunction($cred.SetAlert, @($CredentialLocation, $null, $null, $null, $null, $null, $null, $null))
                }
                elseif($CredentialLocation -eq "AppService"){
                    $ResourceGroupName = Read-Host "`nProvide the resource group name of the appservice"
                    $ResourceName = Read-Host "`nProvide the name of the appservice"
            
                    $input = Read-Host "`nProvide the app config type where the credential is used. Enter 1 for 'Application Settings' or 2 for 'Connection Strings'."
                    if($input -eq 1)
                    {
                        $AppConfigType = "Application Settings"
                    }
                    elseif($input -eq 2)
                    {
                        $AppConfigType = "Connection Strings"
                    }
            
                    $AppConfigName = Read-Host "`nProvide the app config name where the credential is used"      
                    $cred.InvokeFunction($cred.SetAlert, @($CredentialLocation, $ResourceGroupName, $ResourceName, $AppConfigType, $AppConfigName, $null, $null, $null))
                }
                elseif($CredentialLocation -eq "KeyVault"){

                    $KVName = Read-Host "`nProvide the key vault name"
                    $input = Read-Host "`nProvide the key vault credential type. Enter 1 for 'Key' or 2 for 'Secret'."
                    if($input -eq 1)
                    {
                        $KVCredentialType = "Key"
                    }
                    elseif($input -eq 2)
                    {
                        $KVCredentialType = "Secret"
                    }
                    $KVCredentialName = Read-Host "`nProvide the key vault credential name"                    
                    $cred.InvokeFunction($cred.SetAlert, @($CredentialLocation, $null, $null, $null, $null, $KVName, $KVCredentialType, $KVCredentialName))
                }
                
            }
			
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }  
    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }

}