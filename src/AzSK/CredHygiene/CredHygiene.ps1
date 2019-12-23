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
    .PARAMETER CredentialGroup
		Provide the credential group.    
	.PARAMETER RotationInterval
		Provide the rotation interval.
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

        [Parameter(Mandatory = $true, ParameterSetName = "Custom", HelpMessage = "Provide the next expiry due in days")]
        [int]
		[Alias("nexp")]
        $NextExpiryInDays,

        [Parameter(Mandatory = $false, ParameterSetName = "Custom", HelpMessage = "Provide the credential group for alert")]
        [string]
		[Alias("cgp")]
        $CredentialGroup,

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
                
                while($RotationIntervalInDays -le 0){
                    Write-Host 'Rotation interval (in days) should be greater than 0'
                    $RotationIntervalInDays = Read-Host 'Enter rotation interval (> 0 days)'
                }
                $cred.rotationInt = $RotationIntervalInDays
                
                if($NextExpiryInDays -lt 0){
                    $NextExpiryInDays = 0;
                }
                
                $cred.nextExpiry = $NextExpiryInDays
                $cred.comment = $Comment
                $cred.InvokeFunction($cred.NewAlert, @($CredentialLocation,$CredentialGroup))                
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
    .PARAMETER DetailedView
		Switch for detailed metadata information about the credential.	
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
        $CredentialName,

        [Parameter(Mandatory = $false, HelpMessage = "Switch for printing detailed information about the credential.")]
        [switch]
		[Alias("dtl")]
        $DetailedView
    
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
                    $cred.InvokeFunction($cred.GetAlert, @($CredentialName,$DetailedView))
                }
                else {
                    $cred.InvokeFunction($cred.GetAlert, @($null,$DetailedView))
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
    .PARAMETER CredentialGroup
		Provide the credential group.
	.PARAMETER RotationInterval
		Provide the rotation interval.
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

        [Parameter(Mandatory = $false, HelpMessage = "Provide the credential group for alert")]
        [string]
		[Alias("cgp")]
        $CredentialGroup,

        [Parameter(Mandatory = $false, HelpMessage = "Switch for rotating credential at source.")]
        [switch]
		[Alias("rlu")]
        $ResetLastUpdate,
        
        [Parameter(Mandatory = $false, HelpMessage = "Switch for rotating credential at source.")]
        [switch]
		[Alias("uc")]
        $UpdateCredential,

        [Parameter(Mandatory = $true, HelpMessage = "Provide the comment for the credential")]
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

                $updatecred = $false;
                $resetcred = $false;
                
                if($UpdateCredential){
                    $updatecred = $true;
                }
                
                if($ResetLastUpdate){
                    $resetcred = $true;
                }

                while($RotationIntervalInDays -lt 0){
                    Write-Host 'Rotation interval (in days) should be greater than 0'
                    $RotationIntervalInDays = Read-Host 'Enter rotation interval (> 0 days)'
                }
                
                $cred.InvokeFunction($cred.UpdateAlert, @($CredentialName,$RotationIntervalInDays,$CredentialGroup,$updatecred,$resetcred,$Comment)) 
                           
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

