Set-StrictMode -Version Latest
function Set-AzSKWebhookSettings
{
	<#
	.SYNOPSIS
	This command would help in updating the Webhook configuration settings under the current powershell session.
	.DESCRIPTION
	This command will update the Webhook settings under the current powershell session. This also remembers the current settings and use them in the subsequent sessions.
	
	.PARAMETER WebhookUrl
		Full URL of the Webhook. Sometimes this contains AuthZ token as well.  
	.PARAMETER AuthZHeaderName
		Name of the AuthZ header (typically this is "Authorization", however sometimes "Signature" is also used).
	.PARAMETER AuthZHeaderValue
		Value of AuthZHeader.
	.PARAMETER Source
		Provide the source of Webhook Events.(e.g. CC,CICD,SDL)
	.PARAMETER AllowSelfSignedWebhookCertificate
		Use -AllowSelfSignedWebhookCertificate option to allow a self-signed certificate for webhooks. This setting is to facilitate development/testing and is *not* recommended for production environments.
	.PARAMETER Disable
		Use -Disable option to clean the Webhook setting under the current instance.
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder.	

	.LINK
	https://aka.ms/azskossdocs 

	#>
	param(
        
		[Parameter(Mandatory = $true, HelpMessage="Full Url of the Webhook.", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("wurl")]
        $WebhookUrl,

        [Parameter(Mandatory = $false, HelpMessage="Name of the AuthZ header (typically 'Authorization')", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("azhn")]
        $AuthZHeaderName,

		[Parameter(Mandatory = $false, HelpMessage="Value of the AuthZ header", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("azhv")]
        $AuthZHeaderValue,

		[Parameter(Mandatory = $false, HelpMessage="Provide the source of Webhook Events.(e.g. CC,CICD,SDL)", ParameterSetName = "Setup")]
        [AllowEmptyString()]
        [string]
		[Alias("so")]
        $Source,

		[Parameter(Mandatory = $false, HelpMessage="Use -AllowSelfSignedWebhookCertificate option to allow a self-signed certificate for webhooks. This setting is to facilitate development/testing and is *not* recommended for production environments.", ParameterSetName = "Setup")]
        [TertiaryBool]
		[Alias("aswc")]
        $AllowSelfSignedWebhookCertificate = [TertiaryBool]::NotSet,

		[Parameter(Mandatory = $true, HelpMessage="Use -Disable option to clear the Webhook settings for the current instance.", ParameterSetName = "Disable")]
        [switch]
		[Alias("dsbl")]
        $Disable
    )
	Begin
	{
		[CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
		[ListenerHelper]::RegisterListeners();
	}
	Process
	{
		try
		{
			$appSettings = [ConfigurationManager]::GetLocalAzSKSettings();
			if(-not $Disable) 
			{
        			$appSettings.WebhookUrl = $WebhookUrl
					# set the default value to authorization only when header value is sent
					if(-not [string]::IsNullOrWhiteSpace($AuthZHeaderValue))
					{
						if([string]::IsNullOrWhiteSpace($AuthZHeaderName))
						{
							$appSettings.WebhookAuthZHeaderName = "Authorization";
						}
						else
						{
							$appSettings.WebhookAuthZHeaderName = $AuthZHeaderName	
						}
						$appSettings.WebhookAuthZHeaderValue = $AuthZHeaderValue
					}					
			}
			else 
			{
        			$appSettings.WebhookUrl = ""
	    			$appSettings.WebhookAuthZHeaderName = ""
	    			$appSettings.WebhookAuthZHeaderValue = ""
			}
			if(-not [string]::IsNullOrWhiteSpace($Source))
			{				
				$appSettings.WebhookSource = $Source
			}
			else
			{
				$appSettings.WebhookSource = "SDL"
			}

			if($AllowSelfSignedWebhookCertificate -ne [TertiaryBool]::NotSet)
			{
				$appSettings.AllowSelfSignedWebhookCertificate = $AllowSelfSignedWebhookCertificate;
			}
			else
			{
				$appSettings.AllowSelfSignedWebhookCertificate = [TertiaryBool]::NotSet;
			}
			[ConfigurationManager]::UpdateAzSKSettings($appSettings);
		}
		catch
		{
			[EventBase]::PublishGenericException($_);
		}
	}
	End
	{
		[ListenerHelper]::UnregisterListeners();
	}
}
