Set-StrictMode -Version Latest 

class LogAnalyticsMonitoring #: CommandBase
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

	LogAnalyticsMonitoring([string] $_laWSSubscriptionId,[string] $_laWSResourceGroup,[string] $_laWSId, [InvocationInfo] $invocationContext, [string] $viewName, [bool] $isWorkbook = $false) #: Base([string] $_laWSSubscriptionId, $invocationContext) 
    { 	
		$this.SetAzContext($_laWSSubscriptionId);

		$this.LAWSResourceGroup = $_laWSResourceGroup
		$this.LAWSId = $_laWSId
		$laWSInstance = Get-AzOperationalInsightsWorkspace | Where-Object {$_.CustomerId -eq "$_laWSId" -and $_.ResourceGroupName -eq  "$($this.LAWSResourceGroup)"}
		if($null -eq $laWSInstance)
		{
			throw [SuppressedException] "Invalid Log Analytics Workspace."
		}
		$this.LAWSName = $laWSInstance.Name;
		$locationInstance = Get-AzLocation | Where-Object { $_.DisplayName -eq $laWSInstance.Location -or  $_.Location -eq $laWSInstance.Location } 
		$this.LAWSLocation = $locationInstance.Location
	
		$this.ConfigureLAWS($viewName, $false, $_laWSSubscriptionId, $isWorkbook);
		
	}

	[void] ConfigureLAWS([string] $_viewName, [bool] $_validateOnly, [string] $_laWSSubscriptionId, [bool] $isWorkbook)	
    {		
	   Write-Host "WARNING: This command will overwrite the existing AzSK.AzureDevOps Security View that you may have installed using previous versions of AzSK.AzureDevOps if you are using the same view name as the one used earlier. In that case we recommend taking a backup using 'Edit -> Export' option available in the Log Analytics workspace.`n" -ForegroundColor Yellow
	   $userInput = Read-Host "Enter 'Y' to continue and 'N' to skip installation (Y/N)"
		while ($input -ne "y" -and $input -ne "n")
		{
        if (-not [string]::IsNullOrEmpty($input)) {
			Write-Host "WARNING: Please select an appropriate option.`n" -ForegroundColor Yellow;
                  
        }
        $userInput = Read-Host "Enter 'Y' to continue and 'N' to skip installation (Y/N)"
        $userInput = $input.Trim()
				
		}
		if ($userInput -eq "y") 
		{
			Write-Host "============================================================" -ForegroundColor Cyan
			Write-Host "`rStarted setting up AzSK.AzureDevOps Monitoring solution pack`r" -ForegroundColor Cyan
			Write-Host "============================================================" -ForegroundColor Cyan
			$LAWSLogPath = Join-Path $([Constants]::AzSKTempFolderPath) "LogAnalytics";
			if(-not (Test-Path -Path $LAWSLogPath))
			{
				New-Item -Path $LAWSLogPath -ItemType Directory -Force | Out-Null
			}
			$genericViewTemplateFilepath = "";
			if ($isWorkbook) {
				$genericViewTemplateFilepath = [ConfigurationHelper]::LoadOfflineConfigFile([Constants]::LogAnalyticsGenericViewWorkbook); 				
				$this.LAWSGenericTemplateFilepath = Join-Path $LAWSLogPath ([Constants]::LogAnalyticsGenericViewWorkbook); 				
			}
			else {
				$genericViewTemplateFilepath = [ConfigurationHelper]::LoadOfflineConfigFile([Constants]::LogAnalyticsGenericView);
				$this.LAWSGenericTemplateFilepath = Join-Path $LAWSLogPath ([Constants]::LogAnalyticsGenericView)
			}
			
			$genericViewTemplateFilepath | ConvertTo-Json -Depth 100 | Out-File $this.LAWSGenericTemplateFilepath
			Write-Host "`r`nSetting up AzSK.AzureDevOps Log Analytics generic view.`r" -ForegroundColor Cyan
			$this.ConfigureGenericView($_viewName, $_validateOnly, $_laWSSubscriptionId);	
			Write-Host "----------------------------------------------------------------" -ForegroundColor Green
			Write-Host "`rCompleted setting up AzSK.AzureDevOps Monitoring solution pack.`r" -ForegroundColor Green
			Write-Host "----------------------------------------------------------------" -ForegroundColor Green
			Write-Host "WARNING: `r`nNote: `r`n1) The blades of the Log Analytics view created by this command will start populating only after AzSK.AzureDevOps scan events become available in the corresponding Log Analytics workspace.`n" -ForegroundColor Yellow		
			#Write-Host "WARNING: `r`n2) The Log Analytics view installed contains a basic set of queries over ADO security scanner kit scan events. Please feel free to customize them once you get familiar with the queries.`r`nWe also periodically publish updated/richer queries at: https://aka.ms/adoscanner/omsqueries. `r`n" -ForegroundColor Yellow
		
		}
		if ($userInput -eq "n")
		{
			Write-Host "Skipping installation of AzSK.AzureDevOps Monitoring solution pack...`n" -ForegroundColor Cyan
			return;
		}
    }

	[void] ConfigureGenericView([string] $_viewName, [bool] $_validateOnly, [string] $_laWSSubscriptionId)
	{
		$OptionalParameters = New-Object -TypeName Hashtable
		$OptionalParameters = $this.GetLAWSGenericViewParameters($_viewName, $_laWSSubscriptionId);
		Write-Host "Starting template deployment for Log Analytics generic view. Detailed logs are shown below.`n" -ForegroundColor Cyan
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
			Write-Host "`n----------------------------------------------------------------" -ForegroundColor Green
			Write-Host "Completed template deployment for Log Analytics generic view." -ForegroundColor Green
		}
	}

	[Hashtable] GetLAWSGenericViewParameters([string] $_applicationName, [string] $_laWSSubscriptionId)
	{
		[Hashtable] $laWSParams = $this.GetLAWSBaseParameters($_laWSSubscriptionId);
		$laWSParams.Add("viewName",$_applicationName);
		return $laWSParams;
	}

		
	[void] SetAzContext([string] $_laWSSubscriptionId)
	{
		$subId = $_laWSSubscriptionId

		$Context = @(Get-AzContext -ErrorAction SilentlyContinue )
		if ($Context.count -eq 0)  
		{
			Write-Host "No active Azure login session found. Initiating login flow..." -ForegroundColor Cyan
			Connect-AzAccount -ErrorAction Stop
			$Context = @(Get-AzContext -ErrorAction SilentlyContinue)
		}

		if ($null -eq $Context)  
		{
			Write-Host "No Azure login found. Azure login context is required to setup monitoring solution." -ForegroundColor Red
			throw [SuppressedException] "Unable to sign-in to Azure."
		}
		else
		{
			if($Context.Subscription.SubscriptionId -ne $subId)
			{
				set-azcontext -Subscription $subId -Force | out-null
			}
		}
	}

	[Hashtable] GetLAWSBaseParameters([string] $_laWSSubscriptionId)
	{
		[Hashtable] $laWSParams = @{};
		$laWSParams.Add("location",$this.LAWSLocation);
		$laWSParams.Add("resourcegroup",$this.LAWSResourceGroup);
		$laWSParams.Add("subscriptionId",$_laWSSubscriptionId);
		$laWSParams.Add("workspace",$this.LAWSName);
        $laWSParams.Add("workspaceapiversion", "2017-04-26-preview")
		return $laWSParams;
	}	
}
