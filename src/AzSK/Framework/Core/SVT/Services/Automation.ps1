Set-StrictMode -Version Latest 
class Automation: AzSVTBase
{       

    Automation([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
    }
	hidden [ControlResult] CheckWebhooks([ControlResult] $controlResult)
    {   
		$webhooks = Get-AzAutomationWebhook -AutomationAccountName $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName -ErrorAction Stop
		if(($webhooks|Measure-Object).Count -gt 0)
		{
			$webhookdata = $webhooks | Select-Object ResourceGroupName, AutomationAccountName, Name, Description, IsEnabled, Parameters, RunbookName, WebhookURI, HybridWorker
			$controlResult.AddMessage([VerificationResult]::Verify, "Please verify below webhook(s) created for the runbooks. Remove webhook(s) which are not in use.", $webhookdata)
			$controlResult.SetStateData("Webhooks", $webhookdata);                      
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed, "No webhook(s) are created for runbook(s) in this Automation account.")
		}
        return $controlResult;
    }
	hidden [ControlResult] CheckWebhookExpiry([ControlResult] $controlResult)
    {   
		$webhooks = Get-AzAutomationWebhook -AutomationAccountName $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName -ErrorAction Stop
		$longExpiryWebhooks = @()
		if(($webhooks|Measure-Object).Count -gt 0)
		{
			$webhooks | ForEach-Object{
				if(($_.IsEnabled -eq $true) -and (($_.ExpiryTime - $_.CreationTime).Days -gt $this.ControlSettings.Automation.WebhookValidityInDays))
				{
					$expiryTime = ($_.ExpiryTime - $_.CreationTime).days;
					$webhookdata = $_ | Select-Object ResourceGroupName, AutomationAccountName, Name, Description, IsEnabled, Parameters, RunbookName, WebhookURI, HybridWorker
					$webhookdata | Add-Member ExpiryTime -NotePropertyValue $expiryTime
					$longExpiryWebhooks += $webhookdata
				}
			}
			if($longExpiryWebhooks)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "Webhook URL must have shorter validity period (<=$($this.ControlSettings.Automation.WebhookValidityInDays) days) to prevent malicious access. Below webhook(s) URL have validity period >$($this.ControlSettings.Automation.WebhookValidityInDays) days.", $longExpiryWebhooks)
				$controlResult.SetStateData("Webhook(s) with >$($this.ControlSettings.Automation.WebhookValidityInDays) days validity", $longExpiryWebhooks);                      
			}
			else
			{
				$controlResult.VerificationResult =[VerificationResult]::Passed
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed, "No webhooks are created for runbooks in this Automation account.")
		}
		return $controlResult;
    }
	hidden [ControlResult] CheckVariables([ControlResult] $controlResult)
    {   
		$variables = Get-AzAutomationVariable -AutomationAccountName $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName -ErrorAction Stop
		if(($variables|Measure-Object).Count -gt 0 )
		{
			if($this.ResourceContext.ResourceGroupName -eq [ConfigurationManager]::GetAzSKConfigData().AzSKRGName -and [Helpers]::CheckMember($this.ControlSettings,"Automation.variablesToSkip"))
			{
				$variablestoskip = $this.ControlSettings.Automation.variablesToSkip
				$temp = $variables | Where {$variablestoskip -notcontains $_.Name}
				$variables = $temp
			}
			$encryptedVars = @()
			$unencryptedVars = @()

			$variables | ForEach-Object{
				if($_.Encrypted)
				{
					$encryptedVars += $_
				}
				else
				{
					$unencryptedVars += $_
				}
			}
			if($encryptedVars)
			{
				$controlResult.AddMessage("$($encryptedVars.Count) variable(s) are encrypted in this Automation account.")
			}
			if($unencryptedVars)
			{
				$controlResult.AddMessage([VerificationResult]::Verify, "Below variable(s) are not encrypted, use encrypted variable if it contains sensitive data.", $unencryptedVars)
				$controlResult.SetStateData("Unencrypted variable(s)", $unencryptedVars);                      
			}
			else
			{
				$controlResult.VerificationResult =[VerificationResult]::Passed
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed, "No variables are present in this Automation account.")
		}
		return $controlResult;
    }
	hidden [ControlResult] CheckLAWSSetup([ControlResult] $controlResult)
    {   
		$resource = Get-AzResource -Name $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName -ResourceType "Microsoft.Automation/automationAccounts" -ErrorAction Stop
		$resourceId = $resource.ResourceId
		$diaSettings = $null
		try 
		{
			$diaSettings = Get-AzDiagnosticSetting -ResourceId $resourceId -ErrorAction Stop -WarningAction SilentlyContinue
		}
		catch
		{
			if([Helpers]::CheckMember($_.Exception, "Response") -and ($_.Exception).Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound)
			{
				$controlResult.AddMessage([VerificationResult]::Failed, "Log Analytics workspace is not configured with this Automation account.")
				return $controlResult
			}
			else
			{
				$this.PublishException($_);
			}
		}
		if($null -ne $diaSettings -and (Get-Member -InputObject $diaSettings -Name WorkspaceId -MemberType Properties) -and $null -ne $diaSettings.WorkspaceId)
		{
			$controlResult.AddMessage([VerificationResult]::Passed, "Log Analytics workspace is configured with this Automation account. Log Analytics Workspace Id is given below.", $diaSettings.WorkspaceId)
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Failed, "Log Analytics workspace is not configured with this Automation account.")
		}
		return $controlResult;
    }	
}