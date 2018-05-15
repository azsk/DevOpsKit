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
	hidden [string] $PolicyUrl;
	hidden [string] $InstallerUrl;
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

	PolicySetup([string] $subscriptionId, [InvocationInfo] $invocationContext, [string] $orgName, [string] $departmentName, [string] $resourceGroupName, [string] $storageAccountName, [string] $appInsightName, [string] $appInsightLocation, [string] $resourceGroupLocation, [string] $localPolicyFolderPath, [string] $moduleName):
        Base($subscriptionId, $invocationContext)
    {
		$this.CreateInstance($subscriptionId, $orgName, $departmentName, $resourceGroupName, $storageAccountName, $appInsightName, $appInsightLocation, $resourceGroupLocation, $localPolicyFolderPath, $moduleName);
		if($null -ne $this.InvocationContext.BoundParameters["MigrationScriptPath"])
		{
			$this.MigrationScriptPath = $this.InvocationContext.BoundParameters["MigrationScriptPath"];
		}
		if($null -ne $this.InvocationContext.BoundParameters["Migrate"])
		{
			$this.IsMigrationOn = $true;
		}
		
	}

	[void] CreateInstance([string] $subscriptionId, [string] $orgName, [string] $departmentName, [string] $resourceGroupName, [string] $storageAccountName, [string] $appInsightName, [string] $appInsightLocation, [string] $resourceGroupLocation, [string] $localPolicyFolderPath, [string] $moduleName)
	{		
		if([string]::IsNullOrWhiteSpace($orgName))
		{
			throw ([SuppressedException]::new(("The argument 'orgName' is null or empty"), [SuppressedExceptionType]::NullArgument))
		}		

		$this.OrgName = $orgName;
		$this.OrgFullName = $orgName;
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
		if([string]::IsNullOrWhiteSpace($this.AppInsightName))
		{
			throw ([SuppressedException]::new(("You need to pass valid value for AppInsightsName param. They are either null or empty."), [SuppressedExceptionType]::NullArgument))
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

	[void] ModifyConfigs($moduleName)
	{
		#Modify config files and save to temp location
		$metadataFileNames = @();

		if(-not [string]::IsNullOrWhiteSpace($this.InstallerUrl))
		{
			$this.IWRCommand = "iwr '$($this.InstallerUrl)' -UseBasicParsing | iex";
		}

		if((Get-ChildItem $this.ConfigFolderPath -Recurse -Force | Where-Object { $_.Name -eq "AzSK.json" } | Measure-Object).Count -eq 0)
		{
			$azskOverride = [ConfigOverride]::new("AzSK.json");
			$azskOverride.UpdatePropertyValue("PolicyMessage", "Running $moduleName cmdlet using $($this.OrgFullName) policy...");
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
			$azskOverride.WriteToFolder($this.ConfigFolderPath);
		}
		elseif($this.IsMigrationOn)
		{
			$azskOverride = [ConfigOverride]::new($this.ConfigFolderPath,"AzSK.json");
			if([Helpers]::CheckMember($azskOverride.ParsedFile, "PolicyMessage"))
			{
				$PolicyMessage = $azskOverride.ParsedFile.PolicyMessage
				$PolicyMessage = $PolicyMessage.Replace($([Constants]::OldModuleName),$moduleName)
				$azskOverride.UpdatePropertyValue("PolicyMessage", $PolicyMessage);
			}
			
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
			$azskOverride.WriteToFolder($this.ConfigFolderPath);
		}



		#Dynamically get list of files available in folder
		$metadataFileNames += Get-ChildItem $this.ConfigFolderPath -Recurse -Force |
								Where-Object { $_.mode -match "-a---" -and $_.Name -ne "ServerConfigMetadata.json" } |
								Select-Object -Property Name | Select-Object -ExpandProperty Name |
								Select-Object @{ Label="Name"; Expression={ $_ } };

		$metadataOverride = [ConfigOverride]::new("ServerConfigMetadata.json");
		$metadataOverride.UpdatePropertyValue("OnlinePolicyList", $metadataFileNames);
		$metadataOverride.WriteToFolder($this.ConfigFolderPath);
	}

	[void] ModifyInstaller($moduleName)
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
			$fileContent = $fileContent.Replace("#ModuleName#", $moduleName);
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

	[void] CopyRunbook($moduleName)
	{
		try
		{
			if (-not (Test-Path $this.RunbookFolderPath))
			{
				mkdir -Path $this.RunbookFolderPath -ErrorAction Stop | Out-Null
			}
			
			if((Get-ChildItem $this.RunbookFolderPath -Force | Where-Object { $_.Name -eq "RunbookScanAgent.ps1" } | Measure-Object).Count -eq 0)
			{
				$caFilePath = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName + "\Configurations\ContinuousAssurance\RunbookScanAgent.ps1"
				Copy-Item ($caFilePath) ($this.RunbookFolderPath + "RunbookScanAgent.ps1")
			}

			if((Get-ChildItem $this.RunbookFolderPath -Force | Where-Object { $_.Name -eq "RunbookCoreSetup.ps1" } | Measure-Object).Count -eq 0)
			{
				$coreSetupFilePath = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName + "\Configurations\ContinuousAssurance\RunbookCoreSetup.ps1"
				Copy-Item ($coreSetupFilePath) ($this.RunbookFolderPath + "RunbookCoreSetup.ps1")

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
			if((Get-ChildItem $this.RunbookFolderPath -Recurse -Force | Where-Object { $_.Name -eq "AzSK.Pre.json" } | Measure-Object).Count -eq 0)
			{			
				#Get AzSK Module Version				
				$moduleVersion = "0.0.0"
				if($moduleName -eq [Constants]::AzSKModuleName)
				{
					$moduleVersion= $($this.GetCurrentModuleVersion().Tostring())
				}
				else
				{
					$module= Find-Module $moduleName -Repository "PSGallery"
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

	[MessageData[]] InstallPolicy($moduleName)
    {
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

		$this.ModifyInstaller($moduleName);

		$this.StorageAccountInstance.UploadFilesToBlob($this.InstallerContainerName, "", (Get-ChildItem -Path $this.InstallerFile));

		$this.CopyRunbook($moduleName);
		if($container -and $container.CloudBlobContainer)
		{
			$this.CASetupRunbookURL = $container.CloudBlobContainer.Uri.AbsoluteUri + "/$($this.RunbookBaseVersion)/RunbookCoreSetup.ps1" + $this.StorageAccountInstance.GenerateSASToken($this.ConfigContainerName);
		}
		$this.ModifyConfigs($moduleName);
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
		if(($dashboardResource | Measure-Object).Count -eq 0 )
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
			$parameters.Add("DashboardTitle","DevOps Kit Monitoring Dashboard [$($this.OrgFullName)]")
			New-AzureRmResourceGroupDeployment -Name "MonitoringDashboard" -TemplateFile $MonitoringDashboardTemplatePath   -ResourceGroupName $($this.ResourceGroupName) -TemplateParameterObject $parameters   
			$this.PublishCustomMessage("Successfully created dashboard. You can access it through this link: ", [MessageType]::Update);
			$rmContext = [Helpers]::GetCurrentRMContext();
			$tenantId = $rmContext.Tenant.Id
			$this.PublishCustomMessage("https://ms.portal.azure.com/#$($tenantId)/dashboard/arm/subscriptions/$($this.SubscriptionContext.SubscriptionId)/resourcegroups/$($this.ResourceGroupName)/providers/microsoft.portal/dashboards/devopskitmonitoring",[MessageType]::Update)
		}
		
	}
}

