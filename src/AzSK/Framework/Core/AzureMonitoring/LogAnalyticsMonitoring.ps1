Set-StrictMode -Version Latest 

class LogAnalyticsMonitoring: CommandBase
{
	[string] $LAWSampleViewTemplateFilepath;
	[string] $LAWSearchesTemplateFilepath;
	[string] $LAWAlertsTemplateFilepath;
	[string] $LAWGenericTemplateFilepath;
	
	[string] $LAWLocation;
	[string] $LAWResourceGroup;
	[string] $LAWorkspaceName;
	[string] $LAWorkspaceId;
	[string] $ApplicationSubscriptionName

	LogAnalyticsMonitoring([string] $_lawSubscriptionId,[string] $_lawResourceGroup,[string] $_laWorkspaceId, [InvocationInfo] $invocationContext): 
        Base([string] $_lawSubscriptionId, $invocationContext) 
    { 	
		
			
					$this.LAWResourceGroup = $_lawResourceGroup
					$this.LAWorkspaceId = $_laWorkspaceId
					$laWorkspaceInstance = Get-AzOperationalInsightsWorkspace | Where-Object {$_.CustomerId -eq "$_laWorkspaceId" -and $_.ResourceGroupName -eq  "$($this.LAWResourceGroup)"}
					if($null -eq $laWorkspaceInstance)
					{
						throw [SuppressedException] "Invalid Log Analytics Workspace."
					}
					$this.LAWorkspaceName = $laWorkspaceInstance.Name;
					$locationInstance = Get-AzLocation | Where-Object { $_.DisplayName -eq $laWorkspaceInstance.Location -or  $_.Location -eq $laWorkspaceInstance.Location } 
					$this.LAWLocation = $locationInstance.Location
				
		
	}

	[void] ConfigureLAW([string] $_viewName, [bool] $_validateOnly)	
    {		
	   Write-Host "WARNING: This command will overwrite the existing AzSK Security View that you may have installed using previous versions of AzSK if you are using the same view name as the one used earlier. In that case we recommend taking a backup using 'Edit -> Export' option available in the Log Analytics workspace.`n" -ForegroundColor Yellow
	   $input = Read-Host "Enter 'Y' to continue and 'N' to skip installation (Y/N)"
		while ($input -ne "y" -and $input -ne "n")
		{
        if (-not [string]::IsNullOrEmpty($input)) {
			$this.PublishCustomMessage(("Please select an appropriate option.`n" + [Constants]::DoubleDashLine), [MessageType]::Warning)
                  
        }
        $input = Read-Host "Enter 'Y' to continue and 'N' to skip installation (Y/N)"
        $input = $input.Trim()
				
		}
		if ($input -eq "y") 
		{
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nStarted setting up AzSK Monitoring solution pack`r`n"+[Constants]::DoubleDashLine);
		
			$OptionalParameters = New-Object -TypeName Hashtable

			$LAWLogPath = [Constants]::AzSKTempFolderPath + "\LogAnalytics";
			if(-not (Test-Path -Path $LAWLogPath))
			{
				mkdir -Path $LAWLogPath -Force | Out-Null
			}
					
			$genericViewTemplateFilepath = [ConfigurationManager]::LoadServerConfigFile("AZSK.AM.LogAnalytics.GenericView.V5.lawview"); 				
			$this.LAWGenericTemplateFilepath = $LAWLogPath+"\AZSK.AM.LogAnalytics.GenericView.V5.lawview";
			$genericViewTemplateFilepath | ConvertTo-Json -Depth 100 | Out-File $this.LAWGenericTemplateFilepath
			$this.PublishCustomMessage("`r`nSetting up AzSK Log Analytics generic view.");
			$this.ConfigureGenericView($_viewName, $_validateOnly);	
			$this.PublishCustomMessage([Constants]::SingleDashLine + "`r`nCompleted setting up AzSK Monitoring solution pack.`r`n"+[Constants]::SingleDashLine );
			$this.PublishCustomMessage("`r`nNote: `r`n1) The blades of the Log Analytics view created by this command will start populating only after AzSK scan events become available in the corresponding Log Analytics workspace.`nTo understand how to send AzSK events to a Log Analytics workspace see https://aka.ms/devopskit/oms.`r`n", [MessageType]::Warning);		
			$this.PublishCustomMessage("`r`n2) The Log Analytics view installed contains a basic set of queries over DevOps Kit scan events. Please feel free to customize them once you get familiar with the queries.`r`nWe also periodically publish updated/richer queries at: https://aka.ms/devopskit/omsqueries. `r`n",[MessageType]::Warning);
		
		}
		if ($input -eq "n")
		{
			$this.PublishCustomMessage("Skipping installation of AzSK Monitoring solution pack...`n" , [MessageType]::Info)
			return;
		}
    }

	[void] ConfigureGenericView([string] $_viewName, [bool] $_validateOnly)
	{
		$OptionalParameters = New-Object -TypeName Hashtable
		$OptionalParameters = $this.GetLAWGenericViewParameters($_viewName);
		$this.PublishCustomMessage([MessageData]::new("Starting template deployment for Log Analytics generic view. Detailed logs are shown below."));
		$ErrorMessages = @()
        if ($_validateOnly) {
            $ErrorMessages =@()
                Test-AzResourceGroupDeployment -ResourceGroupName $this.LAWResourceGroup `
                                                    -TemplateFile $this.LAWGenericTemplateFilepath `
                                                    -TemplateParameterObject $OptionalParameters -Verbose
		}
        else {

            $ErrorMessages =@()
			$SubErrorMessages = @()
            New-AzResourceGroupDeployment -Name ((Get-ChildItem $this.LAWGenericTemplateFilepath).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
                                        -ResourceGroupName $this.LAWResourceGroup `
                                        -TemplateFile $this.LAWGenericTemplateFilepath  `
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

	[Hashtable] GetLAWGenericViewParameters([string] $_applicationName)
	{
		[Hashtable] $lawParams = $this.GetLAWBaseParameters();
		$lawParams.Add("viewName",$_applicationName);
		return $lawParams;
	}

	[Hashtable] GetLAWBaseParameters()
	{
		[Hashtable] $lawParams = @{};
		$lawParams.Add("location",$this.LAWLocation);
		$lawParams.Add("resourcegroup",$this.LAWResourceGroup);
		$lawParams.Add("subscriptionId",$this.SubscriptionContext.SubscriptionId);
		$lawParams.Add("workspace",$this.LAWorkspaceName);
        $lawParams.Add("workspaceapiversion", "2017-04-26-preview")
		return $lawParams;
	}	
}
