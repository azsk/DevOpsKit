
Set-StrictMode -Version Latest 
class BotService: SVTBase
{
    hidden [PSObject] $ResourceObject;

	BotService([string] $subscriptionId, [SVTResource] $svtResource):
        Base($subscriptionId, $svtResource)
    {
        $this.GetResourceObject();
    }

	hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject)
		{
			# Get App Service details
            $this.ResourceObject = Get-AzureRmResource -Name $this.ResourceContext.ResourceName  `
                                        -ResourceType $this.ResourceContext.ResourceType `
                                        -ResourceGroupName $this.ResourceContext.ResourceGroupName

            if(-not $this.ResourceObject)
            {
				throw ([SuppressedException]::new(("Resource '$($this.ResourceContext.ResourceName)' not found under Resource Group '$($this.ResourceContext.ResourceGroupName)'"), [SuppressedExceptionType]::InvalidOperation))
            }
			
        }

        return $this.ResourceObject;
    }

	hidden [ControlResult] CheckBotConfiguredChannels([ControlResult] $controlResult)
	{
		# Get custom domain URLs
        $ConfiguredChannels = $this.ResourceObject.Properties.enabledChannels

        # Combine custom domain name and SSL configuration TCP

        if(($ConfiguredChannels | Measure-Object).Count -gt 0)
		{
			$controlResult.AddMessage([VerificationResult]::Verify,
                                    [MessageData]::new("Configured Channles for Bot Service " + $this.ResourceContext.ResourceName, $this.ResourceObject.Properties.enabledChannels));
        }

        return $controlResult;
    }

	hidden [ControlResult] CheckAIConfigured([ControlResult] $controlResult)
	{
		# Get custom domain URLs
        $developerAppInsightsApplicationId = $this.ResourceObject.Properties.developerAppInsightsApplicationId

        # Combine custom domain name and SSL configuration TCP

        if($developerAppInsightsApplicationId -ne "")
		{
			$controlResult.AddMessage([VerificationResult]::Verify,
                                    [MessageData]::new("Application Insights is configured for the Bot Service "+ $this.ResourceContext.ResourceName  +". Please verify if critical data is not stored."));
        }
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed,
                                    [MessageData]::new("Application Insights is not Configured for " +  $this.ResourceContext.ResourceName + ". Please refer recommendation of the same to implement."));
		}

        return $controlResult;
    }
}