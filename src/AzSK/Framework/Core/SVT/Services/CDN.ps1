Set-StrictMode -Version Latest
class CDN: AzSVTBase
{
	hidden [PSObject] $ResourceObject;

    CDN([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId, $svtResource)
    {
       
    }

	hidden [ControlResult] CheckCDNHttpsProtocol([ControlResult] $controlResult)
	{
		$cdnEndpoints = Get-AzCdnEndpoint -ProfileName $this.ResourceContext.ResourceName `
							-ResourceGroupName $this.ResourceContext.ResourceGroupName `
							-ErrorAction Stop
		
		if(($cdnEndpoints | Measure-Object).Count -eq 0)
		{
			$controlResult.AddMessage([VerificationResult]::Passed,
										[MessageData]::new("No CDN endpoints are found in the CDN profile.")); 
		}
		else
		{
			# list of CDN endpoints which have only http enabled
			$onlyHttpAllowedEndpointList =  @($cdnEndpoints | Where-Object { $_.IsHttpAllowed -eq $true -and  $_.IsHttpsAllowed -eq $false})
			# list of CDN endpoints which have http enabled (irrespective of https)
			$httpAllowedEndpointList =  $cdnEndpoints | Where-Object { $_.IsHttpAllowed -eq $true }

			if(($httpAllowedEndpointList | Measure-Object).Count -eq 0)
			{
				$controlResult.AddMessage([VerificationResult]::Passed,
										[MessageData]::new("All CDN endpoints in the CDN profile [" + $this.ResourceContext.ResourceName + "] are using HTTPS protocol only - ", ($cdnEndpoints | Select-Object -Property Name, HostName, OriginHostHeader, IsHttpAllowed, IsHttpsAllowed))); 
			}elseif($null -ne $onlyHttpAllowedEndpointList -and ($onlyHttpAllowedEndpointList | Measure-Object).Count -gt 0){
				# If only http protocol is enabled, Fail the control directly without checking for redirection rule
				$httpEndpointObjList=@()
				$httpAllowedEndpointList| Foreach-Object {
					$httpEndpointObj = New-Object -TypeName PSObject
					$httpEndpointObj | Add-Member -NotePropertyName HostName -NotePropertyValue $_.HostName
					$httpEndpointObj | Add-Member -NotePropertyName IsHttpAllowed -NotePropertyValue $_.IsHttpAllowed
					$httpEndpointObj | Add-Member -NotePropertyName IsHttpsAllowed -NotePropertyValue $_.IsHttpsAllowed
					$httpEndpointObjList+=$httpEndpointObj
				}

				$controlResult.SetStateData("Http Enabled Endpoints", $httpEndpointObjList);
				$controlResult.EnableFixControl = $true;
				$controlResult.AddMessage([VerificationResult]::Failed,
				[MessageData]::new("Only HTTP protocol is enabled for following CDN endpoints in the CDN profile [" + $this.ResourceContext.ResourceName + "]  ", ($onlyHttpAllowedEndpointList | Select-Object -Property Name, HostName, OriginHostHeader, IsHttpAllowed, IsHttpsAllowed))); 
			}
			else
			{
				$httpEndpointObjList=@()
				$httpAllowedEndpointList| Foreach-Object {
					$httpEndpointObj = New-Object -TypeName PSObject
					$httpEndpointObj | Add-Member -NotePropertyName HostName -NotePropertyValue $_.HostName
					$httpEndpointObj | Add-Member -NotePropertyName IsHttpAllowed -NotePropertyValue $_.IsHttpAllowed
					$httpEndpointObj | Add-Member -NotePropertyName IsHttpsAllowed -NotePropertyValue $_.IsHttpsAllowed
					$httpEndpointObjList+=$httpEndpointObj
				}
				$httpEndpointsWithRedirectRule = @()
				$httpEndpointsWithoutRedirectRule = @()
				$httpAllowedEndpointList | Foreach-Object {
					$currentEndpoint = $_
					$isRedirectRuleConfigured = $false
					if($null -ne $currentEndpoint.DeliveryPolicy)
					{
						$currentEndpoint.DeliveryPolicy.Rules | Foreach-Object {
							$currentRule = $_
							$requiredHttpCondition = $currentRule.Conditions | Where-Object { $_.MatchVariable -eq "RequestScheme" -and $_.MatchValue -eq "HTTP" -and $_.NegateCondition -eq $false}
							$requiredRedirectAction = $currentRule.Actions | Where-Object { [Helpers]::CheckMember($_, "RedirectType") -and [Helpers]::CheckMember($_, "DestinationProtocol") -and $_.DestinationProtocol -eq "HTTPS"}
							if($null -ne $requiredHttpCondition -and $null -ne $requiredRedirectAction){
								$isRedirectRuleConfigured = $true
							}
						}
					}
					  
					if($isRedirectRuleConfigured)
					{
						$httpEndpointsWithRedirectRule += $currentEndpoint
					}
					else
					{
						$httpEndpointsWithoutRedirectRule += $currentEndpoint
					}
				}	

				if(($httpEndpointsWithoutRedirectRule | Measure-Object).Count -gt 0){
					$controlResult.SetStateData("Http Enabled Endpoints", $httpEndpointObjList);
					$controlResult.EnableFixControl = $true;
					$controlResult.AddMessage([VerificationResult]::Failed,
											[MessageData]::new("Below CDN endpoints in the CDN profile [" + $this.ResourceContext.ResourceName + "] are using HTTP protocol and don't have HTTP to HTTPS redirection rule configured - ", ($httpEndpointsWithoutRedirectRule | Select-Object -Property Name, HostName, OriginHostHeader, IsHttpAllowed, IsHttpsAllowed))); 
				}else{
					$controlResult.AddMessage([VerificationResult]::Passed,
					[MessageData]::new("For all the CDN endpoints (using HTTP protocol) in the CDN profile, HTTP to HTTPs redirection rule is configured in rules engine - ", ($httpEndpointsWithRedirectRule | Select-Object -Property Name, HostName, OriginHostHeader, IsHttpAllowed, IsHttpsAllowed))); 
				}

			}
		}
 
		return $controlResult;    
	}
}