Set-StrictMode -Version Latest 
class SVTStatusReport : SVTCommandBase
{
	[SVTResourceResolver] $ServicesResolver = $null;

	SVTStatusReport([string] $subscriptionId, [InvocationInfo] $invocationContext, [SVTResourceResolver] $resolver): 
        Base($subscriptionId, $invocationContext)
    { 
		if(-not $resolver)
		{
			throw [System.ArgumentException] ("The argument 'resolver' is null");
		}

		$this.ServicesResolver = $resolver;
		$this.ServicesResolver.LoadAzureResources();
	}

	hidden [SVTEventContext[]] RunAllControls()
	{
		[SVTEventContext[]] $result = @();	
		
		# Run all Subscription security controls
		try 
        {
			$this.PublishCustomMessage(" `r`n" + [Constants]::DoubleDashLine + "`r`nStarted Subscription security controls`r`n" + [Constants]::DoubleDashLine);
			$sscore = [SubscriptionSecurityStatus]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext);
			if ($sscore) 
			{
				# Just copy all the tags without validation. Validation will be done internally
				$sscore.FilterTags = $this.FilterTags;
				$sscore.ExcludeTags = $this.ExcludeTags;
				$sscore.ControlIdString = $this.ControlIdString;
				$sscore.GenerateFixScript = $this.GenerateFixScript;
				$sscore.AttestationOptions = $this.AttestationOptions;

				$result += $sscore.RunAllControls();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted Subscription security controls`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }   

		# Run all Azure services security controls
		try 
        {
			$this.PublishCustomMessage(" `r`n" + [Constants]::DoubleDashLine + "`r`nStarted Azure services security controls`r`n" + [Constants]::DoubleDashLine);			
			$secStatus = [ServicesSecurityStatus]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $this.ServicesResolver);
			
			if ($secStatus) 
			{
				# Just copy all the tags without validation. Validation will be done internally
				$secStatus.FilterTags = $this.FilterTags;
				$secStatus.ExcludeTags = $this.ExcludeTags;
				$secStatus.ControlIdString = $this.ControlIdString;
				$secStatus.GenerateFixScript = $this.GenerateFixScript;
				$secStatus.AttestationOptions = $this.AttestationOptions;

				$result += $secStatus.RunAllControls();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted Azure services security controls`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			}   
		}
        catch 
        {
			$this.CommandError($_);
        }
		
		return $result;
	}

	hidden [SVTEventContext[]] FetchAttestationInfo()
	{
		[SVTEventContext[]] $result = @();	
		
		# Fetch state of all Subscription security controls
		try 
        {
			$this.PublishCustomMessage(" `r`n" + [Constants]::DoubleDashLine + "`r`nGetting attestation info for Subscription level controls`r`n" + [Constants]::DoubleDashLine);
			$sscore = [SubscriptionSecurityStatus]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext);
			if ($sscore) 
			{
				# Just copy all the tags without validation. Validation will be done internally
				$sscore.ControlIdString = $this.ControlIdString;
				$sscore.AttestationOptions = $this.AttestationOptions;
				$result += $sscore.FetchAttestationInfo();
				if(($result|Measure-object).count -gt 0)
				{
					$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted Subscription level controls`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
				}
				elseif([string]::IsNullOrWhiteSpace($sscore.ControlIdString))
				{
					$this.PublishCustomMessage([Constants]::SingleDashLine + "`r`nNo attestation data found for Subscription level controls`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update)
				}
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }   

		# Fetch state of all Azure services security controls
		try 
        {
			$this.PublishCustomMessage(" `r`n" + [Constants]::DoubleDashLine + "`r`nGetting attestation info for Azure services controls`r`n" + [Constants]::DoubleDashLine);			
			$secStatus = [ServicesSecurityStatus]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $this.ServicesResolver);
			
			if ($secStatus) 
			{
				# Just copy all the tags without validation. Validation will be done internally
			
				$secStatus.ControlIdString = $this.ControlIdString;
				#$secStatus.GenerateFixScript = $this.GenerateFixScript;
				$secStatus.AttestationOptions = $this.AttestationOptions;		
				$secStatusResult = $secStatus.FetchAttestationInfo()
				if(($secStatusResult|Measure-Object).Count -gt 0)
				{
					$result +=  $secStatusResult 
					$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted Azure services controls`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
				} 
				else
				{
					$this.PublishCustomMessage([Constants]::SingleDashLine + "`r`nNo attestation data found for Azure services controls`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update)
				}
			}  
		}
        catch 
        {
			$this.CommandError($_);
        }
		#display summary
		if(($result|Measure-Object).Count -gt 0)
		{
			$this.DisplayAttetstationStatistics($result)
		}
		else
		{

		}
		return $result;
	
	}
	hidden [void] DisplayAttetstationStatistics([SVTEventContext[]] $Result)
	{
		$this.PublishCustomMessage("`r`n"+[Constants]::DoubleDashLine+"`r`nSummary of attestation details:`r`n`r`n");
		$this.DisplayAttestationStatusWiseControlsCount($Result);
		$this.DisplaySeverityWiseControlsCount($Result);
		$this.DisplayControlIdWiseCount($Result)
		$this.DisplayExpiryDateWiseControlsCount($Result);
	}
	hidden [void] DisplayAttestationStatusWiseControlsCount([SVTEventContext[]] $Result)
	{
			$subCoreResult = $Result|Where-Object{!$_.IsResource()};
			$resResult = $Result|Where-Object{$_.IsResource()};
			if(($subCoreResult|Measure-Object).Count -gt 0)
			{
				$subCoreGroup = $subCoreResult.ControlResults|Group-Object ActualVerificationResult,AttestationStatus | ForEach{
				[pscustomobject]@{
				   'ActualVerificationResult'=$_.Group[0].ActualVerificationResult
				   'AttestationStatus'=$_.Group[0].AttestationStatus 
				   'ControlsCount'=$_.count}
				}
				$this.PublishCustomMessage([Constants]::SingleDashLine+"`r`nSubscription controls:`r`n"+($subCoreGroup|out-string))
				$this.PublishCustomMessage([Constants]::SingleDashLine)
			}
			if(($resResult|Measure-Object).Count -gt 0)
			{
				$resGroup = $resResult.ControlResults|Group-Object ActualVerificationResult,AttestationStatus | ForEach{
				[pscustomobject]@{
				   'ActualVerificationResult'=$_.Group[0].ActualVerificationResult
				   'AttestationStatus'=$_.Group[0].AttestationStatus 
				   'ControlsCount'=$_.count}
				}  
				$this.PublishCustomMessage("Azure Services controls:`r`n"+($resGroup|out-string))
				$this.PublishCustomMessage([Constants]::DoubleDashLine)
			}
		
	}
	hidden [void] DisplaySeverityWiseControlsCount([SVTEventContext[]] $Result)
	{
		$groupResult = $Result.ControlItem| Group ControlSeverity | ForEach{
					[pscustomobject]@{
					'ControlSeverity'=$_.name
					'ControlsCount'=$_.count}
					}
		$this.PublishCustomMessage("Distribution of attested controls by severity:`r`n"+($groupResult|out-string))
		$this.PublishCustomMessage([Constants]::DoubleDashLine);
	}
	hidden [void] DisplayControlIdWiseCount([SVTEventContext[]] $Result)
	{
		$groupResult = $Result.ControlItem| Group ControlId | ForEach{
					[pscustomobject]@{
					'ControlId'=$_.name
					'ControlsCount'=$_.count}
					}
		$this.PublishCustomMessage("Distribution of controls that have been attested:`r`n"+($groupResult|out-string));
		$this.PublishCustomMessage([Constants]::DoubleDashLine);

	}
	hidden [void] DisplayExpiryDateWiseControlsCount([SVTEventContext[]] $Result)
	{
		$subCoreResult = $Result|Where-Object{!$_.IsResource()};
		$resResult = $Result|Where-Object{$_.IsResource()};
		$expiringSubControls = @()
		$expiringStateResources = @()
		if(($subCoreResult|Measure-Object).Count -gt 0)
		{
			$subControlsWithExpDate = $subCoreResult | Where-Object{ $_.ControlResults|Where-Object{![string]::IsNullOrWhiteSpace($_.StateManagement.AttestedStateData.ExpiryDate)}}
			$expiringSubControls= $subControlsWithExpDate | Where-Object{ $_.ControlResults | Where-Object{([datetime]$_.StateManagement.AttestedStateData.ExpiryDate - $(Get-Date).ToUniversalTime()).TotalDays -le 30}}
		}
		if(($resResult|Measure-Object).Count -gt 0)
		{
			$resourcesWithExpDate = $resResult | Where-Object{ $_.ControlResults|Where-Object{![string]::IsNullOrWhiteSpace($_.StateManagement.AttestedStateData.ExpiryDate)}}
			$expiringStateResources = $resourcesWithExpDate | Where-Object{ $_.ControlResults | Where-Object{([datetime]$_.StateManagement.AttestedStateData.ExpiryDate - $(Get-Date).ToUniversalTime()).TotalDays -le 30}}
		}	
		if(($expiringSubControls|Measure-Object).Count -gt 0 -or ($expiringStateResources|Measure-Object).Count -gt 0)
		{
			$expiringSubControls15Days= $expiringSubControls | Where-Object{ $_.ControlResults | Where-Object{([datetime]$_.StateManagement.AttestedStateData.ExpiryDate - $(Get-Date).ToUniversalTime()).TotalDays -le 15}}
			$expiringStateResources15Days = $expiringStateResources | Where-Object{ $_.ControlResults | Where-Object{([datetime]$_.StateManagement.AttestedStateData.ExpiryDate - $(Get-Date).ToUniversalTime()).TotalDays -le 15}}
			$expiringSubControls7Days= $expiringSubControls | Where-Object{ $_.ControlResults | Where-Object{([datetime]$_.StateManagement.AttestedStateData.ExpiryDate - $(Get-Date).ToUniversalTime()).TotalDays -le 7}}
			$expiringStateResources7Days = $expiringStateResources | Where-Object{ $_.ControlResults | Where-Object{([datetime]$_.StateManagement.AttestedStateData.ExpiryDate - $(Get-Date).ToUniversalTime()).TotalDays -le 7}}

			$this.PublishCustomMessage("Summary of controls expiring in near future:`r`n`r`nDays  CountOfSubscriptionControls  CountOfAzureServicesControls`r`n"+[Constants]::SingleDashLine);
			if(($expiringSubControls7Days|Measure-Object).Count -gt 0 -or ($expiringStateResources7Days|Measure-Object).Count -gt 0)
			{
				$this.PublishCustomMessage("07`t`t$(($expiringSubControls7Days|Measure-Object).Count)`t`t`t`t`t`t`t$(($expiringStateResources7Days|Measure-Object).Count)");
			}
			if(($expiringSubControls15Days|Measure-Object).Count -gt 0 -or ($expiringStateResources15Days|Measure-Object).Count -gt 0)
			{
				$this.PublishCustomMessage("15`t`t$(($expiringSubControls15Days|Measure-Object).Count)`t`t`t`t`t`t`t$(($expiringStateResources15Days|Measure-Object).Count)`t`t`t`t");
			}
			$this.PublishCustomMessage("30`t`t$(($expiringSubControls|Measure-Object).Count)`t`t`t`t`t`t`t$(($expiringStateResources|Measure-Object).Count)`t`t`t`t`r`n`r`n");
			$this.PublishCustomMessage("Recommendation: Check Attestation report to get details of expiring controls and fix/attest them before expiry.",[MessageType]::Warning);
		}
		else
		{
			$this.PublishCustomMessage([Constants]::SingleDashLine+"`r`n`r`nCount of Controls expiring in the next 30 days: 0`r`n");
		}
	}
}
