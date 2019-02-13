Set-StrictMode -Version Latest 

class WebhookOutput: ListenerBase
{		
	hidden static [WebhookOutput] $Instance = $null;  
	#Default source is kept as SDL / PowerShell. 
	#This value must be set in respective environment i.e. CICD,CC   
	[string] $WebhookSource;

	WebhookOutput()
	{
		
	}


	static [WebhookOutput] GetInstance()
	{
		if($null -eq [WebhookOutput]::Instance)
		{
			[WebhookOutput]::Instance = [WebhookOutput]::new();
		}
		return [WebhookOutput]::Instance;
	}

	[void] RegisterEvents()
	{
		$this.UnregisterEvents();

		$this.RegisterEvent([SVTEvent]::EvaluationCompleted, {
			$currentInstance = [WebhookOutput]::GetInstance();
			try
			{
				$currentInstance.WriteControlResult([SVTEventContext[]] ($Event.SourceArgs));
			}
			catch
			{
				$currentInstance.PublishException($_);
			}
		});
	}

	hidden [void] WriteControlResult([SVTEventContext[]] $eventContextAll)
	{
		try
		{
			$settings = [ConfigurationManager]::GetAzSKSettings()
			$tempBodyObjectsAll = [System.Collections.ArrayList]::new()

			if(-not [string]::IsNullOrWhiteSpace($settings.WebhookSource))
			{
				$this.WebhookSource = $settings.WebhookSource
			}

			if(-not [string]::IsNullOrWhiteSpace($settings.WebhookUrl))
			{
				$eventContextAll | ForEach-Object{
				$eventContext = $_
					$tempBodyObjects = $this.GetWebhookBodyObjects($this.WebhookSource,$eventContext) #need to prioritize this
					$tempBodyObjects | ForEach-Object{
					Set-Variable -Name tempBody -Value $_ -Scope Local
					$tempBodyObjectsAll.Add($tempBody)
					
				}
				}

				PostWebhookData `
						-webHookUrl $settings.WebhookUrl `
						-authZHeaderName $settings.WebhookAuthZHeaderName `
						-authZHeaderValue $settings.WebhookAuthZHeaderValue `
						-eventBody $tempBodyObjectsAll `
						-logType $settings.WebhookType
						#Currently logType param is not used
				          
			}
		}
		catch
		{
			[Exception] $ex = [Exception]::new(("Invalid Webhook Settings: " + $_.Exception.ToString()), $_.Exception)
			throw [SuppressedException] $ex
		}
	}

	hidden [PSObject[]] GetWebhookBodyObjects([string] $Source,[SVTEventContext] $eventContext)
	{
		[PSObject[]] $output = @();
		[array] $eventContext.ControlResults | ForEach-Object{
			Set-Variable -Name ControlResult -Value $_ -Scope Local
			$out = "" | Select-Object ResourceType, ResourceGroup, Reference, ResourceName, ChildResourceName, ControlStatus, ActualVerificationResult, ControlId, SubscriptionName, SubscriptionId, FeatureName, Source, Recommendation, ControlSeverity, TimeTakenInMs, AttestationStatus, AttestedBy, Justification
			if($eventContext.IsResource())
			{
				$out.ResourceType=$eventContext.ResourceContext.ResourceType
				$out.ResourceGroup=$eventContext.ResourceContext.ResourceGroupName			
				$out.ResourceName=$eventContext.ResourceContext.ResourceName
				$out.ChildResourceName=$ControlResult.ChildResourceName
			}

			$out.Reference=$eventContext.Metadata.Reference
			$out.ControlStatus=$ControlResult.VerificationResult.ToString()
			$out.ActualVerificationResult=$ControlResult.ActualVerificationResult.ToString()
			$out.ControlId=$eventContext.ControlItem.ControlID
			$out.SubscriptionName=$eventContext.SubscriptionContext.SubscriptionName
			$out.SubscriptionId=$eventContext.SubscriptionContext.SubscriptionId
			$out.FeatureName=$eventContext.FeatureName
			$out.Recommendation=$eventContext.ControlItem.Recommendation
			$out.ControlSeverity=$eventContext.ControlItem.ControlSeverity.ToString()
			$out.Source=$Source

			#mapping the attestation properties
			if($null -ne $ControlResult -and $null -ne $ControlResult.StateManagement -and $null -ne $ControlResult.StateManagement.AttestedStateData)
			{
				$attestedData = $ControlResult.StateManagement.AttestedStateData;
				$out.AttestationStatus = $ControlResult.AttestationStatus.ToString();
				$out.AttestedBy = $attestedData.AttestedBy;
				$out.Justification = $attestedData.Justification;
			}
			
			#$out.TimeTakenInMs=[int] $Metrics["TimeTakenInMs"]	
			$output += $out
		}
		return $output	
	}
}


function PostWebhookData($webHookUrl, $authZHeaderName, $authZHeaderValue, $eventBody, $logType)
{
	#$now = [DateTime]::Now.DateTime
	#$eventDataX = @{"event" = "Hello Splunk! This is AzSK speaking @ $now"} | ConvertTo-Json

    $eventJson = @{
        "event" = $eventBody
    } | ConvertTo-Json

	$defaultSecurityProtocol = $null
	try
	{
		[TertiaryBool] $AllowSelfSignedWebhookCertificate = [TertiaryBool]::NotSet;
		$AllowSelfSignedWebhookCertificate = [ConfigurationManager]::GetLocalAzSKSettings().AllowSelfSignedWebhookCertificate;
		if($AllowSelfSignedWebhookCertificate -eq [TertiaryBool]::NotSet)
		{
			$serverAllowSelfSignedWebhookCertificate = [ConfigurationManager]::GetAzSKConfigData().AllowSelfSignedWebhookCertificate;
			if($serverAllowSelfSignedWebhookCertificate)
			{
				$AllowSelfSignedWebhookCertificate = [TertiaryBool]::True;
			}
			else
			{
				$AllowSelfSignedWebhookCertificate = [TertiaryBool]::False;
			}
		}
		if($AllowSelfSignedWebhookCertificate -eq [TertiaryBool]::NotSet)
		{
			$AllowSelfSignedWebhookCertificate = [TertiaryBool]::False;
		}

		if($AllowSelfSignedWebhookCertificate -eq [TertiaryBool]::False)
		{
			[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
		}
		$defaultSecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol
		[System.Net.ServicePointManager]::SecurityProtocol = `
					[System.Net.SecurityProtocolType]::Tls12
	
		if (-not [String]::IsNullOrWhiteSpace($authZHeaderValue))
		{
			$response = Invoke-WebRequest `
						-Uri $webhookUrl `
						-Method "Post" `
						-Body $eventJson `
						-Header @{ $authZHeaderName = $authZHeaderValue} 
		}
		else 
		{
			$response = Invoke-WebRequest `
						-Uri $webhookUrl `
						-Method "Post" `
						-Body $eventJson
		}
	}
	catch 
	{
		$msg = $_.Exception.Message
		$status = $_.Exception.Status
		$hr = "{0:x8}" -f ($_.Exception.HResult)
		$innerException = $_.Exception.InnerException
		#Just issue a warning as about being unable to send notification...
		Write-Warning("`n`t[$status] `n`t[0x$hr] `n`t[$msg] `n`t[$innerException]")
	}
	finally 
	{
		# Set securityProtocol and CertValidation behavior back to default state.
		[System.Net.ServicePointManager]::SecurityProtocol = $defaultSecurityProtocol
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
	}
}
