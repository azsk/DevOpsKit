using namespace System.Management.Automation
using namespace Microsoft.Azure.Commands.Management.Storage.Models
using namespace Microsoft.WindowsAzure.Storage.Blob
using namespace Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel
Set-StrictMode -Version Latest

class PolicySetup: CommandBase
{
	[StorageHelper] $StorageAccountInstance;
	[AppInsightHelper] $AppInsightInstance;
	[string] $OrgName;
	[string] $DepartmentName;
	[string] $OrgFullName;
	[string] $StorageAccountName;
	[string] $ResourceGroupName;
	[string] $AppInsightName;
	[string] $AppInsightLocation;
	[string] $ResourceGroupLocation;
	[string] $MonitoringDashboardLocation;
	hidden [string] $PolicyUrl;
	hidden [string] $installerUrl;
	hidden [string] $InstallerFileName;
	hidden [string] $Version = "3.1803.0";
	hidden [string] $RunbookBaseVersion = "1.0.0"
	hidden [string] $AzSKConfigURL = [string]::Empty
	hidden [string] $CASetupRunbookURL = [string]::Empty

	hidden [string] $ConfigContainerName = "policies";
	hidden [string] $InstallerContainerName = "installer";

	hidden [string] $FolderPath;
	hidden [string] $ConfigFolderPath;
	hidden [string] $InstallerFolderPath;
	hidden [string] $RunbookFolderPath;

	hidden [string] $InstallerFile;

	hidden [string] $IWRCommand;
	hidden [string] $MigrationScriptPath = [string]::Empty
	hidden [bool] $IsMigrationOn = $false
	hidden [bool] $IsUpdateSwitchOn = $false
	hidden [string] $updateCommandName = "Update-AzSKOrganizationPolicy"
	hidden [string] $removeCommandName = "Remove-AzSKOrganizationPolicy"
	hidden [string] $installCommandName = "Install-AzSKOrganizationPolicy"
	hidden [OverrideConfigurationType] $OverrideConfiguration = [OverrideConfigurationType]::None

	PolicySetup([string] $subscriptionId, [InvocationInfo] $invocationContext, [string] $orgName, [string] $departmentName, [string] $resourceGroupName, [string] $storageAccountName, [string] $appInsightName, [string] $appInsightLocation, [string] $resourceGroupLocation,[string] $MonitoringDashboardLocation, [string] $localPolicyFolderPath):
        Base($subscriptionId, $invocationContext)
    {
		$this.CreateInstance($subscriptionId, $orgName, $departmentName, $resourceGroupName, $storageAccountName, $appInsightName, $appInsightLocation, $resourceGroupLocation,$MonitoringDashboardLocation, $localPolicyFolderPath);
		if($null -ne $this.InvocationContext.BoundParameters["MigrationScriptPath"])
		{
			$this.MigrationScriptPath = $this.InvocationContext.BoundParameters["MigrationScriptPath"];
		}
		if($null -ne $this.InvocationContext.BoundParameters["Migrate"])
		{
			$this.IsMigrationOn = $true;
		}
		
	}

	[void] CreateInstance([string] $subscriptionId, [string] $orgName, [string] $departmentName, [string] $resourceGroupName, [string] $storageAccountName, [string] $appInsightName, [string] $appInsightLocation, [string] $resourceGroupLocation,[string] $MonitoringDashboardLocation, [string] $localPolicyFolderPath)
	{		
		if([string]::IsNullOrWhiteSpace($orgName))
		{
			throw ([SuppressedException]::new(("The argument 'orgName' is null or empty"), [SuppressedExceptionType]::NullArgument))
		}		

		$this.OrgName = $orgName;
		$this.OrgFullName = $orgName;
		$moduleName = [Constants]::AzSKModuleName
		$prefix = $moduleName + "-" + $this.OrgFullName;
		if([string]::IsNullOrWhiteSpace($resourceGroupName))
		{
			$this.DepartmentName = $departmentName;

			if(-not [string]::IsNullOrWhiteSpace($departmentName))
			{
				$this.OrgFullName = $this.OrgFullName + "-" + $departmentName;
			}
			$prefix = $moduleName + "-" + $this.OrgFullName;
			$candidateStorageAccountName = $prefix.Replace("-", "").ToLower() + "sa";
			[int] $availableLength = 24 - ($moduleName.Length + 2)
			$storageRegEx = [regex]"^[a-z0-9]{3,24}$"
			if(-not $storageRegEx.IsMatch($candidateStorageAccountName))
			{
				throw ([SuppressedException]::new("Only alphanumeric characters are supported in OrgName and DeptName params. Total length (OrgName + DeptName) should be less than $availableLength characters ", [SuppressedExceptionType]::InvalidArgument))
			}
			$this.ResourceGroupName = $prefix + "-RG";
			$this.StorageAccountName = $prefix.Replace("-", "").ToLower() + "sa";
			$this.AppInsightName = $prefix + "-AppInsight";
		}
		else
		{
			$this.ResourceGroupName = $resourceGroupName;
			$this.StorageAccountName = $storageAccountName;
			$this.AppInsightName = $appInsightName;
			if([string]::IsNullOrWhiteSpace($this.StorageAccountName))
			{
				$this.StorageAccountName = $prefix.Replace("-", "").ToLower() + "sa";
			}

			if((-not [string]::IsNullOrWhiteSpace($this.ResourceGroupName) -or -not [string]::IsNullOrWhiteSpace($this.StorageAccountName)) -and ([string]::IsNullOrWhiteSpace($this.ResourceGroupName) -or [string]::IsNullOrWhiteSpace($this.StorageAccountName)))			
			{
				throw ([SuppressedException]::new(("You need to pass valid values for ResourceGroupName and StorageAccountName params. They are either null or empty."), [SuppressedExceptionType]::NullArgument))
			}
			elseif(-not [string]::IsNullOrWhiteSpace($this.StorageAccountName))
			{
				$storageRegEx = [regex]"^[a-z0-9]{3,24}$"
				if(-not $storageRegEx.IsMatch($storageAccountName))
				{
					throw ([SuppressedException]::new("Only alphanumeric characters are supported in StorageAccountName param. And length should be less than 24 characters ", [SuppressedExceptionType]::InvalidArgument))
				}
			}
		}

		$this.AppInsightLocation = $appInsightLocation;
		if([string]::IsNullOrWhiteSpace($this.AppInsightName) -or [string]::IsNullOrWhiteSpace($appInsightLocation))
		{
			$azskInsights = @();
			$azskInsights += Find-AzureRmResource -ResourceType 'Microsoft.Insights/components' -ResourceGroupName $this.ResourceGroupName -ErrorAction SilentlyContinue
			if(($azskInsights | Measure-Object).Count -eq 1)
			{
				$this.AppInsightName = $azskInsights[0].Name;
				if([string]::IsNullOrWhiteSpace($appInsightLocation))
				{
					$this.AppInsightLocation = $azskInsights[0].Location;
				}
			}
		}
		if( [string]::IsNullOrWhiteSpace($resourceGroupLocation))
		{
			$azskRG = @();
			$azskRG += Get-AzureRmResourceGroup -Name $this.ResourceGroupName -ErrorAction SilentlyContinue
			if(($azskRG | Measure-Object).Count -eq 1)
			{
				$this.ResourceGroupLocation = $azskRG[0].Location;			
			}
			else
			{
				$this.ResourceGroupLocation = "EastUS"
			}
		}
		else {
			$this.ResourceGroupLocation = $resourceGroupLocation
		}
		
		$this.MonitoringDashboardLocation = $MonitoringDashboardLocation
		if([string]::IsNullOrWhiteSpace($MonitoringDashboardLocation))
		{
			$this.MonitoringDashboardLocation = $this.ResourceGroupLocation
		}
		
		$this.FolderPath = [System.Environment]::GetFolderPath("Desktop") + "\" + $prefix + "-Policy\";
		if(-not [string]::IsNullOrWhiteSpace($localPolicyFolderPath))
		{
			try
			{
				if (-not $localPolicyFolderPath.EndsWith("\"))
				{
					$localPolicyFolderPath += "\";
				}

				#$localPolicyFolderPath += $prefix + "-Policy\";

				if (-not (Test-Path $localPolicyFolderPath))
				{
					mkdir -Path $localPolicyFolderPath -ErrorAction Stop | Out-Null
				}

				Copy-Item ($PSScriptRoot + "\README.txt") ($localPolicyFolderPath + "README.txt") -Force
				$this.FolderPath = $localPolicyFolderPath;
			}
			catch
			{
				throw ([SuppressedException]::new("Not able to access/modify the folder [$localPolicyFolderPath].`r`n$($_.ToString())", [SuppressedExceptionType]::InvalidOperation))
			}
		}



		$this.StorageAccountInstance = [StorageHelper]::new($subscriptionId, $this.ResourceGroupName , $resourceGroupLocation, $this.StorageAccountName);
		$this.AppInsightInstance = [AppInsightHelper]::new($subscriptionId, $this.ResourceGroupName , $resourceGroupLocation, $appInsightLocation, $this.AppInsightName);

		$this.ConfigFolderPath = $this.FolderPath + "Config\";
		$this.InstallerFolderPath = $this.FolderPath + "Installer\";
		$this.RunbookFolderPath = $this.FolderPath + "CA-Runbook\";
		
		$this.InstallerFileName = $moduleName + "-EasyInstaller.ps1";
		$this.InstallerFile = $this.InstallerFolderPath + $this.InstallerFileName;

		#Setup base version
		$azskConfig = [ConfigurationManager]::GetAzSKConfigData();
		if([Helpers]::CheckMember($azskConfig, "ConfigSchemaBaseVersion") -and (-not [string]::IsNullOrWhiteSpace($azskConfig.ConfigSchemaBaseVersion)))
		{
			$this.Version = $azskConfig.ConfigSchemaBaseVersion;
		}

		if([Helpers]::CheckMember($azskConfig, "RunbookScanAgentBaseVersion") -and (-not [string]::IsNullOrWhiteSpace($azskConfig.RunbookScanAgentBaseVersion)))
		{
			$this.RunbookBaseVersion = $azskConfig.RunbookScanAgentBaseVersion;
		}
	}

	[void] ModifyConfigs()
	{
		#Modify config files and save to temp location
		$metadataFileNames = @();

		if(-not [string]::IsNullOrWhiteSpace($this.InstallerUrl))
		{
			$this.IWRCommand = "iwr '$($this.InstallerUrl)' -UseBasicParsing | iex";
		}

		$askConfigFile = (Get-ChildItem $this.ConfigFolderPath -Recurse -Force | Where-Object { $_.Name -eq "AzSK.json" })
		if((($askConfigFile | Measure-Object).Count -eq 0) -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::All -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::AzSKRootConfig)
		{
			$azskOverride = [ConfigOverride]::new("AzSK.json");
			$azskOverride.UpdatePropertyValue("PolicyMessage", "Running $([Constants]::AzSKModuleName) cmdlet using $($this.OrgFullName) policy...");
			if(-not [string]::IsNullOrWhiteSpace($this.IWRCommand))
			{
				$azskOverride.UpdatePropertyValue("InstallationCommand", $this.IWRCommand);
			}

			if($this.AppInsightInstance -and $this.AppInsightInstance.AppInsightInstance -and $this.AppInsightInstance.AppInsightInstance.Properties)
			{
				$azskOverride.UpdatePropertyValue("ControlTelemetryKey", $this.AppInsightInstance.AppInsightInstance.Properties.InstrumentationKey);
				$azskOverride.UpdatePropertyValue("EnableControlTelemetry", "true");
			}
			if(-not [string]::IsNullOrEmpty($this.CASetupRunbookURL))
			{
				$azskOverride.UpdatePropertyValue("CASetupRunbookURL",$this.CASetupRunbookURL)
			}
			$azskOverride.UpdatePropertyValue("PolicyOrgName",$this.OrgFullName)
			$azskOverride.UpdatePropertyValue("AzSKConfigURL",$this.AzSKConfigURL)
			$azskOverride.WriteToFolder($this.ConfigFolderPath);
		}

		# Dynamically get list of files available in folder
		$metadataFileNames += Get-ChildItem $this.ConfigFolderPath -Recurse -Force |
								Where-Object { $_.mode -match "-a---" -and $_.Name -ne [Constants]::ServerConfigMetadataFileName } |
								Select-Object -Property Name | Select-Object -ExpandProperty Name |
								Select-Object @{ Label="Name"; Expression={ $_ } };

		$metadataOverride = [ConfigOverride]::new([Constants]::ServerConfigMetadataFileName);
		$metadataOverride.UpdatePropertyValue("OnlinePolicyList", $metadataFileNames);
		$metadataOverride.WriteToFolder($this.ConfigFolderPath);
	}

	[void] ModifyInstaller()
	{
		if(-not [string]::IsNullOrWhiteSpace($this.PolicyUrl))
		{
			#Write SAS token url to installer file
			$folderName = [System.IO.Path]::GetDirectoryName($this.InstallerFile);

			# Check for environment specific installer file
			$fileName = $PSScriptRoot + "\" + [Constants]::AzSKModuleName +"-EasyInstaller.ps1";
			if(-not (Test-Path -Path $fileName))
			{
				$fileName = $PSScriptRoot + "\EasyInstaller.ps1";
			}
			#$fileName = $PSScriptRoot + "\EasyInstaller.ps1";
			$fileContent = Get-Content -Path $fileName;
			$fileContent = $fileContent.Replace("#PolicyUrl#", $this.PolicyUrl);
			$fileContent = $fileContent.Replace("#ModuleName#", $([Constants]::AzSKModuleName));
			$fileContent = $fileContent.Replace("#OldModuleName#", [Constants]::OldModuleName);
			$fileContent = $fileContent.Replace("#OrgName#", $this.OrgFullName);
			$fileContent = $fileContent.Replace("#AzSKConfigURL#", $this.AzSKConfigURL);
			
			if(-not [string]::IsNullOrWhiteSpace($this.InstallerUrl))
			{
				$this.IWRCommand = "iwr '$($this.InstallerUrl)' -UseBasicParsing | iex";
			}
			$fileContent = $fileContent.Replace("#AutoUpdateCommand#", $this.IWRCommand);

			if (-not (Test-Path $folderName))
			{
				mkdir -Path $folderName -ErrorAction Stop | Out-Null
			}

			if (-not $folderName.EndsWith("\"))
			{
				$folderName += "\";
			}

			Out-File -InputObject $fileContent -Force -FilePath $this.InstallerFile -Encoding utf8
		}
		else
		{
			throw ([SuppressedException]::new("Not able to create installer file.", [SuppressedExceptionType]::Generic))
		}
	}

	[void] CopyRunbook()
	{
		try
		{
			if (-not (Test-Path $this.RunbookFolderPath))
			{
				mkdir -Path $this.RunbookFolderPath -ErrorAction Stop | Out-Null
			}
			
			if(((Get-ChildItem $this.RunbookFolderPath -Force | Where-Object { $_.Name -eq "RunbookScanAgent.ps1" } | Measure-Object).Count -eq 0) -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::All -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::CARunbooks)
			{
				$caFilePath = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName + "\Configurations\ContinuousAssurance\RunbookScanAgent.ps1"
				Copy-Item ($caFilePath) ($this.RunbookFolderPath + "RunbookScanAgent.ps1") -Force
			}

			if(((Get-ChildItem $this.RunbookFolderPath -Force | Where-Object { $_.Name -eq "RunbookCoreSetup.ps1" } | Measure-Object).Count -eq 0) -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::All -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::CARunbooks)
			{
				$coreSetupFilePath = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName + "\Configurations\ContinuousAssurance\RunbookCoreSetup.ps1"
				Copy-Item ($coreSetupFilePath) ($this.RunbookFolderPath + "RunbookCoreSetup.ps1") -Force

				#Check for environment specific installer file
				$fileName = $this.RunbookFolderPath + "RunbookCoreSetup.ps1";
				if(Test-Path -Path $fileName)
				{
					$fileContent = Get-Content -Path $fileName;
					$fileContent = $fileContent.Replace("#AzSKConfigURL#", $this.AzSKConfigURL);
					Out-File -InputObject $fileContent -Force -FilePath $($this.RunbookFolderPath + "RunbookCoreSetup.ps1") -Encoding utf8
				}			
			}

			#Upload AzSKConfig with version details 
			if(((Get-ChildItem $this.RunbookFolderPath -Recurse -Force | Where-Object { $_.Name -eq "AzSK.Pre.json" } | Measure-Object).Count -eq 0) -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::All -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::OrgAzSKVersion)
			{			
				#Get AzSK Module Version				
				$moduleVersion = "0.0.0"
					$moduleVersion= $($this.GetCurrentModuleVersion().Tostring())

				if($moduleVersion -eq "0.0.0.0")
				{
					$module= Find-Module -Name $([Constants]::AzSKModuleName) -Repository "PSGallery"
					if($module)
					{
						$moduleVersion= $module[0].Version.ToString()
					}
				}
				$azskConfig= @{ "CurrentVersionForOrg"= $moduleVersion};
				$azskConfig | ConvertTo-Json | Out-File "$($this.RunbookFolderPath)\AzSK.Pre.json" -Force
			}

			$allCAFiles = @();
			$allCAFiles += Get-ChildItem $this.RunbookFolderPath -Force | Where-Object { $_.mode -match "-a---" }
			if($allCAFiles.Count -ne 0)
			{
				$this.StorageAccountInstance.UploadFilesToBlob($this.ConfigContainerName, $this.RunbookBaseVersion, $allCAFiles);
			}
		}
		catch
		{
            $this.CommandError($_);
		}		
	}

	[MessageData[]] InstallPolicy()
    {
		if($this.IsUpdateSwitchOn)
		{
			$this.ValidatePolicyExists()
		}
		$this.AppInsightInstance.CreateAppInsightIfNotExists();
		$container = $this.StorageAccountInstance.CreateStorageContainerIfNotExists($this.InstallerContainerName, [BlobContainerPublicAccessType]::Blob);
		if($container -and $container.CloudBlobContainer)
		{
			$this.InstallerUrl = $container.CloudBlobContainer.Uri.AbsoluteUri + "/" + $this.InstallerFileName;

		}	

		$container = $this.StorageAccountInstance.CreateStorageContainerIfNotExists($this.ConfigContainerName);
		if($container -and $container.CloudBlobContainer)
		{
			$this.PolicyUrl = $container.CloudBlobContainer.Uri.AbsoluteUri + "/```$(```$Version)/```$(```$FileName)" + $this.StorageAccountInstance.GenerateSASToken($this.ConfigContainerName);
			$this.AzSKConfigURL = $container.CloudBlobContainer.Uri.AbsoluteUri + "/$($this.RunbookBaseVersion)/AzSK.Pre.json" + $this.StorageAccountInstance.GenerateSASToken($this.ConfigContainerName);
		}

		$this.ModifyInstaller();

		$this.StorageAccountInstance.UploadFilesToBlob($this.InstallerContainerName, "", (Get-ChildItem -Path $this.InstallerFile));

		$this.CopyRunbook();
		if($container -and $container.CloudBlobContainer)
		{
			$this.CASetupRunbookURL = $container.CloudBlobContainer.Uri.AbsoluteUri + "/$($this.RunbookBaseVersion)/RunbookCoreSetup.ps1" + $this.StorageAccountInstance.GenerateSASToken($this.ConfigContainerName);
		}
		$this.ModifyConfigs();
		$allFiles = @();
		$allFiles += Get-ChildItem $this.ConfigFolderPath -Recurse -Force | Where-Object { $_.mode -match "-a---" } 
		if($allFiles.Count -ne 0)
		{
			$this.StorageAccountInstance.UploadFilesToBlob($this.ConfigContainerName, $this.Version, $allFiles);
		}
		else
		{			
			$this.PublishCustomMessage(" `r`n.No configuration files found under folder [$($this.ConfigFolderPath)]", [MessageType]::Warning);
		}

		$this.CreateMonitoringDashboard()
		$this.PublishCustomMessage(" `r`nThe setup has been completed and policies have been copied to [$($this.FolderPath)].`r`nRun the command below to install Organization specific version.`r`n$($this.IWRCommand)", [MessageType]::Update);
		$this.PublishCustomMessage(" `r`nNote: This is a basic setup and uses a public access blob for storing your org's installer. Once you have richer org policies, consider using a location/end-point protected by your tenant authentication.", [MessageType]::Warning);
		return @();
	}

	[void] CleanupTempFolders()
	{
		Remove-Item -Path $this.ConfigFolderPath -Force -Recurse -ErrorAction Ignore
		Remove-Item -Path $this.InstallerFolderPath -Force -Recurse -ErrorAction Ignore
	}

	[void] MigratePolicy([PolicySetup] $OldPolicyInstance)
	{		
		$SubscriptionContext = $this.SubscriptionContext
		$OPolicyInstance = $OldPolicyInstance
		$PolicyInstance = $this	
		$this.PublishAzSKRootEvent([AzSKRootEvent]::PolicyMigrationCommandStarted, $this.OrgFullName);
		
		if(-not [string]::IsNullOrEmpty($this.MigrationScriptPath))
		{
			& $this.MigrationScriptPath
		}
		else
		{
			$mgrationScript = $this.LoadServerConfigFile("PolicyMigration.ps1")			
			Invoke-Expression $mgrationScript
		}
		$this.PublishAzSKRootEvent([AzSKRootEvent]::PolicyMigrationCommandCompleted, $this.OrgFullName);
	}

	[void] CreateMonitoringDashboard()
	{
		#Validate if monitoring dashboard is already created
		$dashboardResource = Get-AzureRmResource -ResourceType "Microsoft.Portal/dashboards" -ResourceGroupName $($this.ResourceGroupName) -ErrorAction SilentlyContinue
		if((($dashboardResource | Measure-Object).Count -eq 0 ) -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::All -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::MonitoringDashboard) 
		{
			$this.PublishCustomMessage("Creating DevOps Kit ops monitoring dashboard in the policy host subscription...");
			
			#Store dashboard template to temp location
			$MonitoringDashboardTemplatePath = [Constants]::AzSKTempFolderPath + "\MonitoringDashboard";
			if(-not (Test-Path -Path $MonitoringDashboardTemplatePath))
			{
				mkdir -Path $MonitoringDashboardTemplatePath -Force | Out-Null
			}						
			$MonitoringDashboardTemplateObj = [ConfigurationManager]::LoadServerConfigFile("MonitoringDashboard.json"); 				
			$MonitoringDashboardTemplatePath = $MonitoringDashboardTemplatePath+"\MonitoringDashboard.json";
			$MonitoringDashboardTemplateObj | ConvertTo-Json -Depth 100 | Out-File $MonitoringDashboardTemplatePath 

			#Create arm template parameter specific to the org
			$parameters = New-Object -TypeName Hashtable
			$parameters.Add("SubscriptionId", $this.SubscriptionContext.SubscriptionId)
			$parameters.Add("ResourceGroups",$this.ResourceGroupName)
			$parameters.Add("AIName",$this.AppInsightName)
			if(($dashboardResource | Measure-Object).Count -eq 1 )
			{
			 $this.MonitoringDashboardLocation =$dashboardResource.Location
			}
			$parameters.Add("Location",$this.MonitoringDashboardLocation)
			$parameters.Add("DashboardTitle","DevOps Kit Monitoring Dashboard [$($this.OrgFullName)]")

			New-AzureRmResourceGroupDeployment -Name "MonitoringDashboard" -TemplateFile $MonitoringDashboardTemplatePath   -ResourceGroupName $($this.ResourceGroupName) -TemplateParameterObject $parameters   
			$this.PublishCustomMessage("Successfully created dashboard. You can access it through this link: ", [MessageType]::Update);
			$rmContext = [Helpers]::GetCurrentRMContext();
			$tenantId = $rmContext.Tenant.Id
			$this.PublishCustomMessage("https://ms.portal.azure.com/#$($tenantId)/dashboard/arm/subscriptions/$($this.SubscriptionContext.SubscriptionId)/resourcegroups/$($this.ResourceGroupName)/providers/microsoft.portal/dashboards/devopskitmonitoring",[MessageType]::Update)
		}
		
	}

	[void] ValidatePolicyExists()
	{
		$OrgPolicyRG = Get-AzureRmResourceGroup -Name $this.ResourceGroupName -ErrorAction SilentlyContinue

		if(-not $OrgPolicyRG)
		{
			throw ([SuppressedException]::new(("Org policy not found under resource group '$($this.ResourceGroupName)'. Please pass 'ResourceGroupName' parameter to command if custom RG name used to setup policy."), [SuppressedExceptionType]::InvalidArgument))

		}
		if (-not (Test-Path $this.FolderPath))
		{
			throw ([SuppressedException]::new(("Policy folder '$($this.FolderPath)' not found. Please pass 'PolicyFolderPath' parameter to command if custom policy path used to setup policy."), [SuppressedExceptionType]::InvalidArgument))
		}
		
	}

	[void] CheckPolicyHealth()
	{
		[PSObject] $PolicyScanOutput = @{}
		$PolicyScanOutput.Resources = @{}
		$policyTempFolder = [Constants]::AzSKTempFolderPath+ "Policies\";

		#Check 01: Presence of Org policy resources
		$this.PublishCustomMessage("Check 01: Presence of Org policy resources.", [MessageType]::Info);

		#a. Validate presense of policy resource group
		$policyResourceGroup= Get-AzureRmResourceGroup -Name $($this.ResourceGroupName) -ErrorAction SilentlyContinue  
		if(-not $policyResourceGroup)
		{
			$this.PublishCustomMessage("Policy resource group [$($this.ResourceGroupName)] not found. `r`nIf custom resource names used to create Org policy, pass parameters ResourceGroupName and StorageAccountName to command '$($this.updateCommandName)'", [MessageType]::Error);
			$PolicyScanOutput.Resources.ResourceGroup = $false
			return
		}
		else
		{
			$PolicyScanOutput.Resources.ResourceGroup = $true
		}

		#b. Validate presense of policy resources storage, app insight and monitoring dashboard
		$policyResources= Find-AzureRmResource -ResourceGroupName $($this.ResourceGroupName)
		#Check if poliy store  is present 
		$missingResources =@()
		$policyStore = $policyResources  | Where-Object {$_.ResourceType -eq "Microsoft.Storage/storageAccounts" }
		if(($policyStore | Measure-Object).Count -eq 0)
		{
			$missingResources +="storage account"
			$PolicyScanOutput.Resources.PolicyStore = $false
		}
		else
		{
		$PolicyScanOutput.Resources.PolicyStore = $true
		}
		
		#Check if app insight is present
		$appInsight = $policyResources  | Where-Object {$_.ResourceType -eq "Microsoft.Insights/components" }
		if(($appInsight | Measure-Object).Count -eq 0)
		{
			$missingResources +="app insight"
			$PolicyScanOutput.Resources.AppInsight = $false
		}
		else
		{
			$PolicyScanOutput.Resources.AppInsight = $true
		}

		#Check if monitoring dashboard is present
		$monitoringDashboard = $policyResources  | Where-Object {$_.ResourceType -eq "Microsoft.Portal/dashboards" }
		if(($monitoringDashboard | Measure-Object).Count -eq 0)
		{
			$missingResources +="manitoring dashboard"
			$PolicyScanOutput.Resources.MonitoringDashboard = $false
		}
		else
		{
			$PolicyScanOutput.Resources.MonitoringDashboard = $true
		}

		if($PolicyScanOutput.Resources.PolicyStore -and $PolicyScanOutput.Resources.AppInsight -and $PolicyScanOutput.Resources.MonitoringDashboard)
		{
			$this.PublishCustomMessage("Status:   OK.", [MessageType]::Update);
			$PolicyScanOutput.Resources.Status = $true
		}
		else
		{
			$this.PublishCustomMessage("Status:   Failed. Missing mandatory resources: $($missingResources -join ",") `nTo resolve this run command '$($this.installCommandName)'", [MessageType]::Error);
			$PolicyScanOutput.Resources.Status = $false
		}
		$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info);

		
		if($PolicyScanOutput.Resources.PolicyStore)
		{
			#Check 02: Presence of mandatory policies
			$this.PublishCustomMessage("Check 02: Presence of mandatory policies.", [MessageType]::Info);
			$PolicyScanOutput.Policies = @{}
			$InstallerPath = $policyTempFolder + "$([Constants]::AzSKModuleName)-EasyInstaller.ps1"
			$PolicyStoragekey = Get-AzureRmStorageAccountKey -ResourceGroupName $policyStore.ResourceGroupName  -Name $policyStore.Name 
			$currentContext = New-AzureStorageContext -StorageAccountName $policyStore.Name  -StorageAccountKey $PolicyStoragekey[0].Value -Protocol Https    										
			[Helpers]::CreateFolder($policyTempFolder)

			#Validate presense of installer
			$missingPolicies = @()
			$Installer = Get-AzureStorageBlobContent -Container "installer" -Blob "$([Constants]::AzSKModuleName)-EasyInstaller.ps1" -Context $currentContext -Destination $policyTempFolder -Force -ErrorAction SilentlyContinue			
			if(($Installer | Measure-Object).Count -eq 0)
			{
				$missingPolicies += "Installer"
				$PolicyScanOutput.Policies.Installer = $false
			}
			else
			{
				$PolicyScanOutput.Policies.Installer = $true
			}    

			#Validate presense of AzSK.Pre.json
			$AzSKPre = Get-AzureStorageBlobContent -Container "policies" -Blob "1.0.0/AzSK.Pre.json" -Context $currentContext -Destination $policyTempFolder -Force -ErrorAction SilentlyContinue
			if(($AzSKPre | Measure-Object).Count -eq 0)
			{
				$missingPolicies += "AzSKPre Config"				
				$PolicyScanOutput.Policies.AzSKPre = $false
			}
			else
			{
				$PolicyScanOutput.Policies.AzSKPre = $true
			}

			$RunbookCoreSetup = Get-AzureStorageBlobContent -Container "policies" -Blob "1.0.0/RunbookCoreSetup.ps1" -Context $currentContext -Destination $policyTempFolder -Force -ErrorAction SilentlyContinue
			if(($RunbookCoreSetup | Measure-Object).Count -eq 0)
			{
				$missingPolicies += "RunbookCoreSetup"				
				$PolicyScanOutput.Policies.RunbookCoreSetup = $false
			}
			else
			{
				$PolicyScanOutput.Policies.RunbookCoreSetup = $true
			}

			$RunbookScanAgent = Get-AzureStorageBlobContent -Container "policies" -Blob "1.0.0/RunbookScanAgent.ps1" -Context $currentContext -Destination $policyTempFolder -Force -ErrorAction SilentlyContinue
			if(($RunbookScanAgent | Measure-Object).Count -eq 0)
			{
				$missingPolicies += "RunbookScanAgent"
				$PolicyScanOutput.Policies.RunbookScanAgent = $false
			}
			else
			{
				$PolicyScanOutput.Policies.RunbookScanAgent = $true
			}


			$AzSKConfig = Get-AzureStorageBlobContent -Container "policies" -Blob "3.1803.0/AzSK.json" -Context $currentContext -Destination $policyTempFolder -Force -ErrorAction SilentlyContinue
			if(($AzSKConfig | Measure-Object).Count -eq 0)
			{
				$missingPolicies += "AzSK Config"
				$PolicyScanOutput.Policies.AzSKConfig = $false
			}
			else
			{
				$PolicyScanOutput.Policies.AzSKConfig = $true
			}

			$ServerConfigMetadata = Get-AzureStorageBlobContent -Container "policies" -Blob "3.1803.0/ServerConfigMetadata.json" -Context $currentContext -Destination $policyTempFolder -Force -ErrorAction SilentlyContinue
			if(($ServerConfigMetadata | Measure-Object).Count -eq 0)
			{
				$missingPolicies += "ServerConfigMetadata"				
				$PolicyScanOutput.Policies.ServerConfigMetadata = $false
			}
			else
			{
				$PolicyScanOutput.Policies.ServerConfigMetadata = $true
			}
				
			if($PolicyScanOutput.Policies.Installer -and $PolicyScanOutput.Policies.AzSKPre -and $PolicyScanOutput.Policies.RunbookCoreSetup -and $PolicyScanOutput.Policies.RunbookScanAgent -and $PolicyScanOutput.Policies.AzSKConfig -and $PolicyScanOutput.Policies.ServerConfigMetadata)
			{
				$this.PublishCustomMessage("Status:   OK.", [MessageType]::Update);
				$PolicyScanOutput.Policies.Status = $true
			}
			else
			{
				$this.PublishCustomMessage("Status:   Failed. Missing mandatory policies: $($missingPolicies -join ",") `nTo resolve this run command '$($this.updateCommandName)'", [MessageType]::Error);
				$PolicyScanOutput.Policies.Status = $false
			}
			$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info);
		

		
		
		#Check 03: Validate installer file 
		$this.PublishCustomMessage("Check 03: Check Installer configurations.", [MessageType]::Info);
		$PolicyScanOutput.Configurations = @{}
		$PolicyScanOutput.Configurations.Installer = @{}
		$InstallOutput = $PolicyScanOutput.Configurations.Installer
		if($PolicyScanOutput.Policies.Installer)
		{
		$InstallerContent =  Get-Content -Path $InstallerPath   
		$missingInstallerConfigurations = @()
		#Validate OnlinePolicyStoreUrl
		$pattern = 'OnlinePolicyStoreUrl = "(.*?)"'
			$InstallerPolicyUrl = [Helpers]::GetSubString($InstallerContent,$pattern)   
			$policyContainerUrl= $AzSKConfig.ICloudBlob.Container.Uri.AbsoluteUri  
			if($InstallerPolicyUrl -like "*$policyContainerUrl*" )
			{
				$InstallOutput.PolicyUrl = $true
			}
			else
			{
				$InstallOutput.PolicyUrl = $false
				#$this.PublishCustomMessage("`t Missing Configuration: OnlinePolicyStoreUrl", [MessageType]::Error);
				#$this.PublishCustomMessage("`t Actual: $([Helpers]::IsStringEmpty($InstallerPolicyUrl))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($policyContainerUrl))", [MessageType]::Error);
				$missingInstallerConfigurations += "OnlinePolicyStoreUrl"
			}
			
			#Validate AutoUpdateCommand command 
			$pattern = 'AutoUpdateCommand = "(.*?)"'
			$autoUpdateCommandUrl = [Helpers]::GetSubString($InstallerContent, $pattern)  
			$installerAbsoluteUrl = $Installer.ICloudBlob.Uri.AbsoluteUri  

			if($autoUpdateCommandUrl -like "*$installerAbsoluteUrl*" )
			{
				$InstallOutput.AutoUpdateCommandUrl = $true
			}
			else
			{
				$InstallOutput.AutoUpdateCommandUrl = $false
				#$this.PublishCustomMessage("`t Missing Configuration: AutoUpdateCommand", [MessageType]::Error);
				#$this.PublishCustomMessage("`t Actual: $([Helpers]::IsStringEmpty($autoUpdateCommandUrl))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($installerAbsoluteUrl))", [MessageType]::Error);
				$missingInstallerConfigurations += "AutoUpdateCommand"
			} 

			#Validate AzSKConfigURL
			$pattern = 'AzSKConfigURL = "(.*?)"'
			$InstallerAzSKPreUrl = [Helpers]::GetSubString($InstallerContent,$pattern)  
			$AzSKPreUrl = $AzSKPre.ICloudBlob.Uri.AbsoluteUri  

			if($InstallerAzSKPreUrl -like "*$AzSKPreUrl*" )
			{
				$InstallOutput.AzSKPreUrl = $true
			}
			else
			{
				$InstallOutput.AzSKPreUrl = $false
				#$this.PublishCustomMessage("`t Missing Configuration: AzSKPreConfigUrl", [MessageType]::Error);
				#$this.PublishCustomMessage("`t Actual: $([Helpers]::IsStringEmpty($InstallerAzSKPreUrl))  `n`t Expected Substring Url: $([Helpers]::IsStringEmpty($AzSKPreUrl))", [MessageType]::Error);
				$missingInstallerConfigurations += "AzSKPreConfigUrl"
			}

			if($InstallOutput.PolicyUrl -and $InstallOutput.AutoUpdateCommandUrl -and $InstallOutput.AzSKPreUrl)
			{
				$this.PublishCustomMessage("Status:   OK.", [MessageType]::Update);
				$InstallOutput.Status = $true
			}
			else
			{
				$this.PublishCustomMessage("Status:   Failed. Missing configurations in installer: $($missingInstallerConfigurations -join ",") `nTo resolve this run command '$($this.updateCommandName)'", [MessageType]::Error);
				$InstallOutput.Status = $false   
			}
		}
		else
		{
			$this.PublishCustomMessage("Status:   Skipped. Installer not found.", [MessageType]::Info);
			$InstallOutput.Status = $false   
		}

		$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info);

		#Check 04: Validate AzSKPre
		$PolicyScanOutput.Configurations.AzSKPre = @{}
		$this.PublishCustomMessage("Check 04: Check AzSKPre configurations.", [MessageType]::Info);
		if($PolicyScanOutput.Policies.AzSKPre)
		{
		$AzSKPreConfigPath = $policyTempFolder + "1.0.0\AzSK.Pre.json"
		$AzSKPreConfigContent =  Get-Content -Path $AzSKPreConfigPath | ConvertFrom-Json   

		#Validate CurrentVersionForOrg
		$LatestAzSKVersion = [ConfigurationManager]::GetAzSKConfigData().GetAzSKLatestPSGalleryVersion([Constants]::AzSKModuleName)
			if($AzSKPreConfigContent.CurrentVersionForOrg -eq $LatestAzSKVersion )
			{
				$PolicyScanOutput.Configurations.AzSKPre.CurrentVersionForOrg = $true
			}
			else
			{
				$PolicyScanOutput.Configurations.AzSKPre.CurrentVersionForOrg = $true
				$this.PublishCustomMessage("Warning: Currently Org policy is running with older AzSK version. Consider updating it to latest available version.", [MessageType]::Warning)
				$this.PublishCustomMessage("`tCurrentOrgAzSKVersion: $([Helpers]::IsStringEmpty($($AzSKPreConfigContent.CurrentVersionForOrg)))  `n`t LatestAzSKVersion: $([Helpers]::IsStringEmpty($($LatestAzSKVersion)))", [MessageType]::Warning)
			}
			
			if($PolicyScanOutput.Configurations.AzSKPre.CurrentVersionForOrg)
			{
				$this.PublishCustomMessage("Status:   OK.", [MessageType]::Update);
				$PolicyScanOutput.Configurations.AzSKPre.Status = $true
			}
			else
			{
				$this.PublishCustomMessage("Status:   Failed. Supported AzSK Org version is not configured. `nTo resolve this run command '$($this.updateCommandName)'", [MessageType]::Error);
				$PolicyScanOutput.Configurations.AzSKPre.Status = $false
			}    
		}
		else
		{
			$this.PublishCustomMessage("Status:   Skipped. AzSKPreConfig not found.", [MessageType]::Info); 
			$PolicyScanOutput.Configurations.AzSKPre.Status = $false  
		}

		$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info);

		#Check 05: Validate CoreSetup 
		$PolicyScanOutput.Configurations.RunbookCoreSetup = @{}
		$this.PublishCustomMessage("Check 05: Check RunbookCoreSetup configurations.", [MessageType]::Info);
		if($PolicyScanOutput.Policies.RunbookCoreSetup)
		{
		$RunbookCoreSetupPath = $policyTempFolder + "1.0.0\RunbookCoreSetup.ps1"
		$RunbookCoreSetupContent =  Get-Content -Path $RunbookCoreSetupPath     
		$missingCoreSetupConfigurations = @()
			#Validate AzSkVersionForOrgUrl command 
			$pattern = 'azskVersionForOrg = "(.*?)"'
			$coreSetupAzSkVersionForOrgUrl = [Helpers]::GetSubString($RunbookCoreSetupContent,$pattern)  
			$AzSkVersionForOrgUrl = $AzSKPre.ICloudBlob.Uri.AbsoluteUri  

			if($coreSetupAzSkVersionForOrgUrl -like "*$AzSkVersionForOrgUrl*" )
			{
				$PolicyScanOutput.Configurations.RunbookCoreSetup.AzSkVersionForOrgUrl = $true
			}
			else
			{
				$PolicyScanOutput.Configurations.RunbookCoreSetup.AzSkVersionForOrgUrl = $false
				$missingCoreSetupConfigurations += "AzSkVersionForOrgUrl"
				#$this.PublishCustomMessage("`t Missing Configuration: AzSkVersionForOrgUrl", [MessageType]::Error);
				#$this.PublishCustomMessage("`t Actual: $([Helpers]::IsStringEmpty($coreSetupAzSkVersionForOrgUrl))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($AzSkVersionForOrgUrl))", [MessageType]::Error);
			}
			
			if($PolicyScanOutput.Configurations.RunbookCoreSetup.AzSkVersionForOrgUrl)
			{
				$this.PublishCustomMessage("Status:   OK.", [MessageType]::Update);
				$PolicyScanOutput.Configurations.RunbookCoreSetup.Status = $true
			}
			else
			{
				$this.PublishCustomMessage("Status:   Failed. Missing configurations in runbookCoreSetup: $($missingCoreSetupConfigurations -join ",") `nTo resolve this run command '$($this.updateCommandName)' with parameter '-OverrideBaseConfig CARunbooks'", [MessageType]::Error);
				$PolicyScanOutput.Configurations.RunbookCoreSetup.Status = $false
			}       
		}
		else
		{
			$this.PublishCustomMessage("Status:   Skipped. RunbookCoreSetup not found.", [MessageType]::Info);
			$PolicyScanOutput.Configurations.RunbookCoreSetup.Status = $false
		}

		$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info);

		#Check 06: Validate AzSKConfig
		$PolicyScanOutput.Configurations.AzSKConfig = @{}
		$this.PublishCustomMessage("Check 06: Check AzSKConfig configurations.", [MessageType]::Info);
		$AzSKConfiguOutput = $PolicyScanOutput.Configurations.AzSKConfig
		if($PolicyScanOutput.Policies.AzSKConfig)
		{
		$AzSKConfigPath = $policyTempFolder + "3.1803.0\AzSK.json" #TODO:Constant
		$AzSKConfigContent =  Get-Content -Path $AzSKConfigPath | ConvertFrom-Json
		$missingAzSKConfigurations = @()
		#Validate CurrentVersionForOrg     
		$RunbookCoreSetupUrl =  $RunbookCoreSetup.ICloudBlob.Uri.AbsoluteUri
			if([Helpers]::CheckMember($AzSKConfigContent,"CASetupRunbookURL") -and $AzSKConfigContent.CASetupRunbookURL -and $AzSKConfigContent.CASetupRunbookURL -like "*$RunbookCoreSetupUrl*")
			{
				$AzSKConfiguOutput.CASetupRunbookUrl = $true
			}
			else
			{
				$AzSKConfiguOutput.CASetupRunbookUrl = $false
				$missingAzSKConfigurations += "CASetupRunbookUrl"
				#$this.PublishCustomMessage("`t Missing Configuration: CASetupRunbookUrl", [MessageType]::Error);
				#$this.PublishCustomMessage("`t Actual: $([Helpers]::IsStringEmpty($($AzSKConfigContent.CASetupRunbookURL)))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($($RunbookCoreSetupUrl)))", [MessageType]::Error);
			} 
			
			#Validate ControlTelemetryKey 
			$appInsightResource= Get-AzureRMApplicationInsights -ResourceGroupName $appInsight.ResourceGroupName -Name $appInsight.Name
			$InstrumentationKey =  $appInsightResource.InstrumentationKey

			if([Helpers]::CheckMember($AzSKConfigContent,"ControlTelemetryKey") -and $AzSKConfigContent.ControlTelemetryKey -and $AzSKConfigContent.ControlTelemetryKey -eq $InstrumentationKey)
			{
				$AzSKConfiguOutput.ControlTelemetryKey = $true
			}
			else
			{
				$AzSKConfiguOutput.ControlTelemetryKey = $false
				$missingAzSKConfigurations += "ControlTelemetryKey"
				#$this.PublishCustomMessage("`t Missing Configuration: ControlTelemetryKey", [MessageType]::Error);
				#$this.PublishCustomMessage("`t Actual: $([Helpers]::IsStringEmpty($($AzSKConfigContent.ControlTelemetryKey)))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($($InstrumentationKey)))", [MessageType]::Error);
			} 
			
			# Validate InstallationCommand     
			$installerAbsoluteUrl = $Installer.ICloudBlob.Uri.AbsoluteUri 
			if($AzSKConfigContent.InstallationCommand -and $AzSKConfigContent.InstallationCommand -like "*$installerAbsoluteUrl*") 
			{
				$AzSKConfiguOutput.InstallationCommand = $true
			}
			else
			{
				$AzSKConfiguOutput.InstallationCommand = $false
				$missingAzSKConfigurations += "InstallationCommand"
				#$this.PublishCustomMessage("`t Missing Configuration: InstallationCommand", [MessageType]::Error);
				#$this.PublishCustomMessage("`t Actual: $([Helpers]::IsStringEmpty($($AzSKConfigContent.InstallationCommand)))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($($installerAbsoluteUrl)))", [MessageType]::Error);
			}


			# Validate PolicyOrgName    
			if([Helpers]::CheckMember($AzSKConfigContent,"PolicyOrgName")  -and $AzSKConfigContent.PolicyOrgName -and -not [string]::IsNullOrEmpty($AzSKConfigContent.PolicyOrgName) )
			{
				$PolicyScanOutput.Configurations.AzSKConfig.PolicyOrgName = $true
			}
			else
			{
				$AzSKConfiguOutput.PolicyOrgName = $false
				$missingAzSKConfigurations += "PolicyOrgName"
				#$this.PublishCustomMessage("`t Missing Configuration: PolicyOrgName", [MessageType]::Error);
			}

			# Validate AzSKPre Url     
			$azSKPreUrl = $AzSKPre.ICloudBlob.Uri.AbsoluteUri 
			if([Helpers]::CheckMember($AzSKConfigContent,"AzSKConfigURL") -and  $AzSKConfigContent.AzSKConfigURL  -and $AzSKConfigContent.AzSKConfigURL -like "*$azSKPreUrl*")
			{
				$AzSKConfiguOutput.AzSKPreConfigURL = $true
			}
			else
			{
				$AzSKConfiguOutput.AzSKPreConfigURL = $false
				$missingAzSKConfigurations += "AzSKPreConfigURL"
				#$this.PublishCustomMessage("`t Missing Configuration: AzSKPreConfigURL", [MessageType]::Error);
				#$this.PublishCustomMessage("`t Actual: $([Helpers]::IsStringEmpty($($AzSKConfigContent.AzSKConfigURL)))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($($azSKPreUrl)))", [MessageType]::Error);
			}
			
			if([Helpers]::CheckMember($AzSKConfigContent,"CASetupRunbookUrl")  -and $AzSKConfiguOutput.CASetupRunbookUrl -and $AzSKConfiguOutput.ControlTelemetryKey -and $AzSKConfiguOutput.InstallationCommand -and $AzSKConfiguOutput.PolicyOrgName -and $AzSKConfiguOutput.AzSKPreConfigURL ) 
			{
				$this.PublishCustomMessage("Status:   OK.", [MessageType]::Update);
				$AzSKConfiguOutput.Status = $true
			}
			else
			{
				$this.PublishCustomMessage("Status:   Failed. Missing configurations in AzSKConfig: $($missingAzSKConfigurations -join ",") `nTo resolve this run command '$($this.updateCommandName)' with parameter '-OverrideBaseConfig AzSKRootConfig'", [MessageType]::Error);
				$AzSKConfiguOutput.Status = $false
			}           
		}
		else
		{
			$this.PublishCustomMessage("Status:   Skipped. AzSKConfig not found.", [MessageType]::Info); 
			$AzSKConfiguOutput.Status = $false  
		}

		if(-not $PolicyScanOutput.Resources.Status -or -not $PolicyScanOutput.Policies.Status -or -not $InstallOutput.Status -or -not $PolicyScanOutput.Configurations.AzSKPre.Status -or  -not $PolicyScanOutput.Configurations.RunbookCoreSetup.Status -or  -not $AzSKConfiguOutput.Status)
		{
			$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Warning)
			$this.PublishCustomMessage("Found that Org policy configuration is not correctly setup.`nReview the failed check and follow the remedy suggested", [MessageType]::Warning) 
			$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Warning)
		}
		else
		{
			$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info);
			$this.PublishCustomMessage("Org policy configuration is in healthy state.", [MessageType]::Info); 
			$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info);
		}
	}
	else 
	{
		$this.PublishCustomMessage("Status:   Skipped. Policy store not found.", [MessageType]::Info);
		$PolicyScanOutput.Policies.Status = $false
	}


	}

}

