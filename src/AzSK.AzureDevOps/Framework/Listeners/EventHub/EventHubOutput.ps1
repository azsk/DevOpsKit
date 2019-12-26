Set-StrictMode -Version Latest 

class EventHubOutput: ListenerBase
{		
	hidden static [EventHubOutput] $Instance = $null;  
	#Default source is kept as SDL / PowerShell. 
	#This value must be set in respective environment i.e. CICD,CC   
	[string] $EventHubSource;

	EventHubOutput()
	{
		
	}


	static [EventHubOutput] GetInstance()
	{
		if($null -eq [EventHubOutput]::Instance)
		{
			[EventHubOutput]::Instance = [EventHubOutput]::new();
		}
		return [EventHubOutput]::Instance;
	}

	[void] RegisterEvents()
	{
		$this.UnregisterEvents();

		$this.RegisterEvent([SVTEvent]::EvaluationCompleted, {
			$currentInstance = [EventHubOutput]::GetInstance();
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

			if(-not [string]::IsNullOrWhiteSpace($settings.EventHubSource))
			{
				$this.EventHubSource = $settings.EventHubSource
			}

			if(-not [string]::IsNullOrWhiteSpace($settings.EventHubNamespace))
			{
				$eventContextAll | ForEach-Object{
				$eventContext = $_

				$tempBodyObjects = $this.GetEventHubBodyObjects($this.EventHubSource,$eventContext) 
				$tempBodyObjects | ForEach-Object{
					Set-Variable -Name tempBody -Value $_ -Scope Local
					$tempBodyObjectsAll.Add($tempBody)
					}
				}
				
				$body = $tempBodyObjectsAll | ConvertTo-Json
				[EventHubOutput]::PostEventHubData(`
                            $settings.EventHubNamespace, `
                            $settings.EventHubName, `
                            $settings.EventHubSendKeyName, `
                            $settings.EventHubSendKey,`
                            $body, `
                            $settings.EventHubType)
			}
		}
		catch
		{
			[Exception] $ex = [Exception]::new(("Invalid EventHub Settings: " + $_.Exception.ToString()), $_.Exception)
			throw [SuppressedException] $ex
		}
	}

	hidden [PSObject[]] GetEventHubBodyObjects([string] $Source,[SVTEventContext] $eventContext)
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
			
			$output += $out
		}
		return $output	
	}

	static [string] PostEventHubData([string] $ehNamespace, [string] $ehName, [string] $ehSendKeyName, [string] $ehSendKey, $body, $logType)
	{
        $ehUrl = "$ehNamespace.servicebus.windows.net/$ehName"
        $ControlSettingsJson = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json")
        $sasToken=GetEventHubToken -URI $ehUrl -AccessPolicyName $ehSendKeyName -AccessPolicyKey $ehSendKey -TokenTimeOut $ControlSettingsJson.EventHubOutput.TokenTimeOut
        $response = SendEventHubMessage -URI $ehUrl -SASToken $sasToken -Message $body -TimeOut $ControlSettingsJson.EventHubOutput.TimeOut -APIVersion $ControlSettingsJson.EventHubOutput.APIVersion
        return $response.StatusCode
    }
}

function GetEventHubToken([string]$URI, [string]$AccessPolicyName, [string]$AccessPolicyKey, [int]$TokenTimeOut)
{
	[Reflection.Assembly]::LoadWithPartialName("System.Web")| out-null

    $now = [DateTimeOffset]::Now
	$Expires=($now.ToUnixTimeSeconds())+$TokenTimeOut

	$SignatureString=[System.Web.HttpUtility]::UrlEncode($URI)+ "`n" + [string]$Expires
	$HMAC = New-Object System.Security.Cryptography.HMACSHA256
	$HMAC.key = [Text.Encoding]::ASCII.GetBytes($AccessPolicyKey)
	$Signature = $HMAC.ComputeHash([Text.Encoding]::ASCII.GetBytes($SignatureString))
	$Signature = [Convert]::ToBase64String($Signature)
	$SASToken = "SharedAccessSignature sr=" + `
                    [System.Web.HttpUtility]::UrlEncode($URI) +`
                    "&sig=" + [System.Web.HttpUtility]::UrlEncode($Signature) + `
                    "&se=" + $Expires + `
                    "&skn=" + $AccessPolicyName
	return $SASToken
}

function SendEventHubMessage([string]$URI, [string]$SASToken, [string]$Message, [int]$TimeOut, [string]$APIVersion)
{
	try {
		$webRequest=Invoke-WebRequest `
                            -Method POST `
                            -Uri ("https://"+$URI+"/messages?timeout="+$TimeOut+"&api-version="+$APIVersion) `
                            -Header @{ Authorization = $SASToken} `
                            -ContentType "application/atom+xml;type=entry;charset=utf-8" `
                            -Body $Message `
                            -ErrorAction SilentlyContinue
	} 
	catch
	{
		Write-Error("Invoke-WebRequest returned: `n`tStatusCode: "+$_.Exception.Response.StatusCode+"`n`tStausDescription: "+$_.Exception.Response.StatusDescription)
		break
	}
	return $webRequest
}
