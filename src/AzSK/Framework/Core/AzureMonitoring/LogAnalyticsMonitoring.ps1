Set-StrictMode -Version Latest 

class LogAnalyticsMonitoring: AzCommandBase
{
	[string] $LAWSSampleViewTemplateFilepath;
	[string] $LAWSSearchesTemplateFilepath;
	[string] $LAWSAlertsTemplateFilepath;
	[string] $LAWSGenericTemplateFilepath;
	
	[string] $LAWSLocation;
	[string] $LAWSResourceGroup;
	[string] $LAWSName;
	[string] $LAWSId;
	[string] $ApplicationSubscriptionName

	LogAnalyticsMonitoring([string] $_laWSSubscriptionId,[string] $_laWSResourceGroup,[string] $_laWSId, [InvocationInfo] $invocationContext): 
        Base([string] $_laWSSubscriptionId, $invocationContext) 
    { 	
		$this.LAWSResourceGroup = $_laWSResourceGroup
		$this.LAWSId = $_laWSId
		$laWSInstance = Get-AzOperationalInsightsWorkspace | Where-Object {$_.CustomerId -eq "$_laWSId" -and $_.ResourceGroupName -eq  "$($this.LAWSResourceGroup)"}
		if($null -eq $laWSInstance)
		{
			throw [SuppressedException] "Invalid Log Analytics Workspace."
		}
		$this.LAWSName = $laWSInstance.Name;
		#$locationInstance = Get-AzLocation | Where-Object { $_.DisplayName -eq $laWSInstance.Location -or  $_.Location -eq $laWSInstance.Location } 
		#$this.LAWSLocation = $locationInstance.Location
		$this.LAWSLocation = $laWSInstance.Location
	}

	[void] ConfigureLAWS([string] $_viewName, [bool] $_validateOnly,[bool] $forceDeployment)	
    {	
		# If force switch is passed don't prompt user for consent and deploy solution
		if($forceDeployment)
		{
			$userInput = "y"
		}
		else{
			Write-Host "WARNING: This command will overwrite the existing AzSK Security View that you may have installed using previous versions of AzSK if you are using the same view name as the one used earlier. In that case we recommend taking a backup using 'Edit -> Export' option available in the Log Analytics workspace.`n" -ForegroundColor Yellow
	    	$userInput = Read-Host "Enter 'Y' to continue and 'N' to skip installation (Y/N)"
			while ($userInput -ne "y" -and $userInput -ne "n")
			{
				if (-not [string]::IsNullOrEmpty($userInput)) {
					$this.PublishCustomMessage(("Please select an appropriate option.`n" + [Constants]::DoubleDashLine), [MessageType]::Warning)
					
				}
				$userInput = Read-Host "Enter 'Y' to continue and 'N' to skip installation (Y/N)"
				$userInput = $userInput.Trim()	
		    }
		}	
	    
		if ($userInput -eq "y") 
		{
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nStarted setting up AzSK Monitoring solution pack`r`n"+[Constants]::DoubleDashLine);
			$LAWSLogPath = Join-Path $([Constants]::AzSKTempFolderPath) "LogAnalytics";
			if(-not (Test-Path -Path $LAWSLogPath))
			{
				New-Item -Path $LAWSLogPath -ItemType Directory -Force | Out-Null
			}
			$genericViewTemplateFilepath = [ConfigurationManager]::LoadServerConfigFile([Constants]::LogAnalyticsGenericView); 				
			$this.LAWSGenericTemplateFilepath = Join-Path $LAWSLogPath ([Constants]::LogAnalyticsGenericView)
			$genericViewTemplateFilepath | ConvertTo-Json -Depth 100 | Out-File $this.LAWSGenericTemplateFilepath
			$this.PublishCustomMessage("`r`nSetting up AzSK Log Analytics generic view.");
			$this.ConfigureGenericView($_viewName, $_validateOnly);	
			$this.PublishCustomMessage([Constants]::SingleDashLine + "`r`nCompleted setting up AzSK Monitoring solution pack.`r`n"+[Constants]::SingleDashLine );
			$this.PublishCustomMessage("`r`nNote: `r`n1) The blades of the Log Analytics view created by this command will start populating only after AzSK scan events become available in the corresponding Log Analytics workspace.`nTo understand how to send AzSK events to a Log Analytics workspace see https://aka.ms/devopskit/oms.`r`n", [MessageType]::Warning);		
			$this.PublishCustomMessage("`r`n2) The Log Analytics view installed contains a basic set of queries over DevOps Kit scan events. Please feel free to customize them once you get familiar with the queries.`r`nWe also periodically publish updated/richer queries at: https://aka.ms/devopskit/omsqueries. `r`n",[MessageType]::Warning);
		
		}
		if ($userInput -eq "n")
		{
			$this.PublishCustomMessage("Skipping installation of AzSK Monitoring solution pack...`n" , [MessageType]::Info)
			return;
		}
    }

	[void] ConfigureGenericView([string] $_viewName, [bool] $_validateOnly)
	{
		$OptionalParameters = New-Object -TypeName Hashtable
		$OptionalParameters = $this.GetLAWSGenericViewParameters($_viewName);
		$this.PublishCustomMessage([MessageData]::new("Starting template deployment for Log Analytics generic view. Detailed logs are shown below."));
		$ErrorMessages = @()
        if ($_validateOnly) {
			$ErrorMessages += Test-AzResourceGroupDeployment -ResourceGroupName $this.LAWSResourceGroup `
                                                    -TemplateFile $this.LAWSGenericTemplateFilepath `
                                                    -TemplateParameterObject $OptionalParameters -Verbose
		}
        else {
			$SubErrorMessages = @()
            New-AzResourceGroupDeployment -Name ((Get-ChildItem $this.LAWSGenericTemplateFilepath).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
                                        -ResourceGroupName $this.LAWSResourceGroup `
                                        -TemplateFile $this.LAWSGenericTemplateFilepath  `
                                        -TemplateParameterObject $OptionalParameters `
                                        -Verbose -Force -ErrorVariable SubErrorMessages
            $SubErrorMessages = $SubErrorMessages | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") }
            $ErrorMessages += $SubErrorMessages
           
     }
        if ($ErrorMessages)
        {
            "", ("{0} returned the following errors:" -f ("Template deployment", "Validation")[[bool]$_validateOnly]), @($ErrorMessages) | ForEach-Object { $this.PublishCustomMessage([MessageData]::new($_));}
        }
		else
		{
			$this.PublishCustomMessage([MessageData]::new("Completed template deployment for Log Analytics generic view."));			
		}
	}

	[Hashtable] GetLAWSGenericViewParameters([string] $_applicationName)
	{
		[Hashtable] $laWSParams = $this.GetLAWSBaseParameters();
		$laWSParams.Add("viewName",$_applicationName);
		return $laWSParams;
	}

	[Hashtable] GetLAWSBaseParameters()
	{
		[Hashtable] $laWSParams = @{};
		$laWSParams.Add("location",$this.LAWSLocation);
		$laWSParams.Add("resourcegroup",$this.LAWSResourceGroup);
		$laWSParams.Add("subscriptionId",$this.SubscriptionContext.SubscriptionId);
		$laWSParams.Add("workspace",$this.LAWSName);
        $laWSParams.Add("workspaceapiversion", "2017-04-26-preview")
		return $laWSParams;
	}	
}
