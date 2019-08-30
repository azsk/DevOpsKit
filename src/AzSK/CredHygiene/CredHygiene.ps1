Set-StrictMode -Version Latest

function New-AzSKTrackedCredential { 
   
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
        [Parameter(Mandatory = $true, ParameterSetName = "Custom", Position=0, HelpMessage = "Provide the subscription id")]
        [string]
        [ValidateNotNullOrEmpty()]
        [Alias("s")]
        $SubscriptionId,

        [Parameter(Mandatory = $true, ParameterSetName = "Custom", Position=1, HelpMessage = "Provide the credential location")]
        [ValidateSet("Custom", "AppService", "KeyVault")]
        [string]
		[Alias("cl")]
        $CredentialLocation,

        [Parameter(Mandatory = $true, ParameterSetName = "Custom", Position=2, HelpMessage = "Provide the credential name")]
        [string]
		[Alias("cn")]
        $CredentialName,

        [Parameter(Mandatory = $true, ParameterSetName = "Custom", HelpMessage = "Provide the rotation interval in days")]
        [int]
		[Alias("rint")]
        $RotationIntervalInDays,

        [Parameter(Mandatory = $true, ParameterSetName = "Custom", HelpMessage = "Provide the email id for alert")]
        [string]
		[Alias("aem")]
        $AlertEmail,

        [Parameter(Mandatory = $false, ParameterSetName = "Custom", HelpMessage = "Provide the contact number for alert")]
        [string]
		[Alias("acn")]
        $AlertSMS,

        [Parameter(Mandatory = $true, ParameterSetName = "Custom", HelpMessage = "Provide the comment for the credential")]
        [string]
		[Alias("cmt")]
        $Comment
    )
    Begin {
        [CommandHelper]::BeginCommand($MyInvocation);
        [AzListenerHelper]::RegisterListeners();
    }
    Process {
        try {
			
            $cred = [CredHygiene]::new($SubscriptionId, $PSCmdlet.MyInvocation);
            if($cred){
                $cred.credName = $CredentialName
                $cred.credLocation = $CredentialLocation
                $cred.rotationInt = $RotationIntervalInDays
                $cred.alertEmail = $AlertEmail
                if($AlertSMS){
                    $cred.alertPhoneNumber = $AlertSMS
                }
                $cred.comment = $Comment

                if($CredentialLocation -eq "Custom"){
                    $cred.InvokeFunction($cred.NewAlert, @($CredentialLocation, $null, $null, $null, $null, $null, $null, $null))
                }
                elseif($CredentialLocation -eq "AppService"){
                    Write-Host "`nProvide the following details for the app service: `n"
                    $ResourceName = Read-Host "App service name"
                    $ResourceGroupName = Read-Host "Resource group"

                    Write-Host "`nPlease select app config type from below: `n[1]: Application Settings`n[2]: Connection Strings" -ForegroundColor Cyan

                    $input = Read-Host "App config type"
                    
                    while(($input -ne 1) -and ($input -ne 2)){
                        Write-Host "`nIncorrect value supplied." -ForegroundColor Red
                        Write-Host "Please select app config type from below: `n[1]: Application Settings`n[2]: Connection Strings" -ForegroundColor Cyan
                        $input = Read-Host "App config type"
                    }
                    
                    if($input -eq 1)
                    {
                        $AppConfigType = "Application Settings"
                    }
                    elseif($input -eq 2)
                    {
                        $AppConfigType = "Connection Strings"
                    }
            
                    $AppConfigName = Read-Host "App config name"      
                    $cred.InvokeFunction($cred.NewAlert, @($CredentialLocation, $ResourceGroupName, $ResourceName, $AppConfigType, $AppConfigName, $null, $null, $null))
                }
                elseif($CredentialLocation -eq "KeyVault"){
                    Write-Host "`nProvide the following details for the key vault: `n"
                    $KVName = Read-Host "Key Vault name"
                   
                    Write-Host "`nPlease select key vault credential type from below: `n[1]: Key`n[2]: Secret" -ForegroundColor Cyan
                    $input = Read-Host "`Key Vault credential type"
                   
                    while(($input -ne 1) -and ($input -ne 2)){
                        Write-Host "`nIncorrect value supplied." -ForegroundColor Red
                        Write-Host "Please select key vault credential type from below: `n[1]: Key`n[2]: Secret" -ForegroundColor Cyan
                        $input = Read-Host "Key Vault credential type"
                    }

                    if($input -eq 1)
                    {
                        $KVCredentialType = "Key"
                    }
                    elseif($input -eq 2)
                    {
                        $KVCredentialType = "Secret"
                    }
                    $KVCredentialName = Read-Host "Key Vault credential name"                    
                    $cred.InvokeFunction($cred.NewAlert, @($CredentialLocation, $null, $null, $null, $null, $KVName, $KVCredentialType, $KVCredentialName))
                }
                
            }
			
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }  
    }
    End {
        [AzListenerHelper]::UnregisterListeners();
    }
}

function Get-AzSKTrackedCredential { 
   
    <#
	.SYNOPSIS
	This command would help to list expiring credentials.
	.DESCRIPTION
	This command would help to list expiring credentials.
    
	.PARAMETER SubscriptionId
		Provide the subscription id.
	.PARAMETER CredentialName
		Provide the credential name.	
	.LINK
	https://aka.ms/azskossdocs

	#>
    Param(
        [Parameter(Mandatory = $true, HelpMessage = "Provide the subscription id")]
        [string]
		[Alias("s")]
        $SubscriptionId,

        [Parameter(Mandatory = $false, HelpMessage = "Provide the credential name")]
        [string]
		[Alias("cn")]
        $CredentialName
    
    )
    Begin {
        [CommandHelper]::BeginCommand($MyInvocation);
        [AzListenerHelper]::RegisterListeners();
    }
    Process {
        try {
			
            $cred = [CredHygiene]::new($SubscriptionId, $PSCmdlet.MyInvocation);
            if($cred){
                if($CredentialName){
                    $cred.InvokeFunction($cred.GetAlert, @($CredentialName))
                }
                else {
                    $cred.InvokeFunction($cred.GetAlert, @($null))
                }            
            }
	
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }  
    }
    End {
        [AzListenerHelper]::UnregisterListeners();
    }

}

function Remove-AzSKTrackedCredential { 
   
    <#
	.SYNOPSIS
	This command would help to delete the expiration details of the credential.
	.DESCRIPTION
	This command would help to delete the expiration details of the credential.
    
	.PARAMETER SubscriptionId
		Provide the subscription id.
	.PARAMETER CredentialName
		Provide the credential name.
	
	.LINK
	https://aka.ms/azskossdocs

	#>
    Param(
        [Parameter(Mandatory = $true, HelpMessage = "Provide the subscription id")]
        [string]
		[Alias("s")]
        $SubscriptionId,

        [Parameter(Mandatory = $true, HelpMessage = "Provide the credential name")]
        [string]
		[Alias("cn")]
        $CredentialName,

        [Parameter(Mandatory = $false, HelpMessage = "Switch for removing credential metadata without further user consent.")]
        [switch]
		[Alias("f")]
        $Force
    )
    Begin {
        [CommandHelper]::BeginCommand($MyInvocation);
        [AzListenerHelper]::RegisterListeners();
    }
    Process {
        try {
			
            $cred = [CredHygiene]::new($SubscriptionId, $PSCmdlet.MyInvocation);
            if($cred){
                if($Force){
                    $cred.InvokeFunction($cred.RemoveAlert, @($CredentialName, $true))
                }
                else {
                    $cred.InvokeFunction($cred.RemoveAlert, @($CredentialName, $false))
                }            
            }
	
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }  
    }
    End {
        [AzListenerHelper]::UnregisterListeners();
    }
}

function Update-AzSKTrackedCredential { 
   
    <#
	.SYNOPSIS
	This command would help to update the alert on expiring credentials.
	.DESCRIPTION
	This command would help to update the alert on expiring credentials.
    
	.PARAMETER SubscriptionId
		Provide the subscription id.
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
        [Parameter(Mandatory = $true, HelpMessage = "Provide the subscription id")]
        [string]
		[Alias("s")]
        $SubscriptionId,

        [Parameter(Mandatory = $true, HelpMessage = "Provide the credential name")]
        [string]
		[Alias("cn")]
        $CredentialName,

        [Parameter(Mandatory = $false, HelpMessage = "Provide the rotation interval in days")]
        [int]
		[Alias("rint")]
        $RotationIntervalInDays,

        [Parameter(Mandatory = $false, HelpMessage = "Provide the email id for alert")]
        [string]
		[Alias("aem")]
        $AlertEmail,

        [Parameter(Mandatory = $false, HelpMessage = "Provide the contact number for alert")]
        [string]
		[Alias("acn")]
        $AlertSMS,

        [Parameter(Mandatory = $true, HelpMessage = "Provide the comment for the credential")]
        [string]
		[Alias("cmt")]
        $Comment,

        [Parameter(Mandatory = $false, HelpMessage = "Switch for rotating credential at source.")]
        [switch]
		[Alias("rlu")]
        $ResetLastUpdate,
        
        [Parameter(Mandatory = $false, HelpMessage = "Switch for rotating credential at source.")]
        [switch]
		[Alias("uc")]
        $UpdateCredential

    )
    Begin {
        [CommandHelper]::BeginCommand($MyInvocation);
        [AzListenerHelper]::RegisterListeners();
    }
    Process {
        try {
			
            $cred = [CredHygiene]::new($SubscriptionId, $PSCmdlet.MyInvocation);
            if($cred){

                $updatecred = $false;
                $resetcred = $false;
                
                if($UpdateCredential){
                    $updatecred = $true;
                }
                
                if($ResetLastUpdate){
                    $resetcred = $true;
                }
                
                $cred.InvokeFunction($cred.UpdateAlert, @($CredentialName,$RotationIntervalInDays,$AlertEmail,$AlertSMS,$Comment,$updatecred,$resetcred)) 
                           
            }
	
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }  
    }
    End {
        [AzListenerHelper]::UnregisterListeners();
    }
}

function New-AzSKTrackedCredentialGroup { 
   
    <#
	.SYNOPSIS
	This command would help to update the alert on expiring credentials.
	.DESCRIPTION
	This command would help to update the alert on expiring credentials.
    
	.PARAMETER SubscriptionId
		Provide the subscription id.
	.PARAMETER AlertEmail
		Provide the email id for alert.
	
	.LINK
	https://aka.ms/azskossdocs

	#>
    Param(
        [Parameter(Mandatory = $true, HelpMessage = "Provide the subscription id")]
        [string]
		[Alias("s")]
        $SubscriptionId,

        [Parameter(Mandatory = $true, HelpMessage = "Provide the email id for alert")]
        [string]
		[Alias("aem")]
        $AlertEmail
    )
    Begin {
        [CommandHelper]::BeginCommand($MyInvocation);
        [ListenerHelper]::RegisterListeners();
    }
    Process {
        try {
			
            $cred = [CredHygiene]::new($SubscriptionId, $PSCmdlet.MyInvocation);
            if($cred){                
                $cred.InvokeFunction($cred.InstallAlert, @($AlertEmail))                            
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

