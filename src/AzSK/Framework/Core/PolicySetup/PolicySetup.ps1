using namespace System.Management.Automation
using namespace Microsoft.Azure.Commands.Management.Storage.Models
using namespace Microsoft.Azure.Storage.Blob
using namespace Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel
using namespace Newtonsoft.Json.Schema
Set-StrictMode -Version Latest

class PolicySetup: AzCommandBase
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
	hidden [string] $AzureEnvironment;
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
	hidden [bool] $IsUpdateSwitchOn = $false
	hidden [string] $updateCommandName = "Update-AzSKOrganizationPolicy"
	hidden [string] $removeCommandName = "Remove-AzSKOrganizationPolicy"
	hidden [string] $installCommandName = "Install-AzSKOrganizationPolicy"
	hidden [string] $getCommandName = "Get-AzSKOrganizationPolicyStatus"
	hidden [int] $msgCount = 0;
	hidden [OverrideConfigurationType] $OverrideConfiguration = [OverrideConfigurationType]::None

	PolicySetup([string] $subscriptionId, [InvocationInfo] $invocationContext, [string] $orgName, [string] $departmentName, [string] $resourceGroupName, [string] $storageAccountName, [string] $appInsightName, [string] $appInsightLocation, [string] $resourceGroupLocation,[string] $AzureEnvironment, [string] $MonitoringDashboardLocation, [string] $localPolicyFolderPath):
        Base($subscriptionId, $invocationContext)
    {
		$this.DonotOpenOutputFolder = $true;
		$this.CreateInstance($subscriptionId, $orgName, $departmentName, $AzureEnvironment, $resourceGroupName, $storageAccountName, $appInsightName, $appInsightLocation, $resourceGroupLocation,$MonitoringDashboardLocation, $localPolicyFolderPath);				
	}

	[void] CreateInstance([string] $subscriptionId, [string] $orgName, [string] $departmentName,[string] $AzureEnvironment, [string] $resourceGroupName, [string] $storageAccountName, [string] $appInsightName, [string] $appInsightLocation, [string] $resourceGroupLocation,[string] $MonitoringDashboardLocation, [string] $localPolicyFolderPath)
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
		$this.AzureEnvironment = $AzureEnvironment;
		if([string]::IsNullOrWhiteSpace($this.AppInsightName) -or [string]::IsNullOrWhiteSpace($appInsightLocation))
		{
			$azskInsights = @();
			$azskInsights += Get-AzResource -ResourceType 'Microsoft.Insights/components' -ResourceGroupName $this.ResourceGroupName -ErrorAction SilentlyContinue
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
			$azskRG += Get-AzResourceGroup -Name $this.ResourceGroupName -ErrorAction SilentlyContinue
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
		
		$this.FolderPath = Join-Path $([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop, [System.Environment+SpecialFolderOption]::DoNotVerify)) ($prefix + "-Policy");
		if(-not [string]::IsNullOrWhiteSpace($localPolicyFolderPath))
		{
			try
			{
				
				if (-not (Test-Path $localPolicyFolderPath))
				{
					New-Item -ItemType Directory -Path $localPolicyFolderPath -ErrorAction Stop | Out-Null
				}				
				$this.FolderPath = $localPolicyFolderPath;
			}
			catch
			{
				throw ([SuppressedException]::new("Not able to access/modify the folder [$localPolicyFolderPath].`r`n$($_.ToString())", [SuppressedExceptionType]::InvalidOperation))
			}
		}

		$this.StorageAccountInstance = [StorageHelper]::new($subscriptionId, $this.ResourceGroupName , $resourceGroupLocation, $this.StorageAccountName);
		$this.AppInsightInstance = [AppInsightHelper]::new($subscriptionId, $this.ResourceGroupName , $resourceGroupLocation, $appInsightLocation, $this.AppInsightName);

		$this.ConfigFolderPath = Join-Path $this.FolderPath  "Config";
		$this.InstallerFolderPath = Join-Path $this.FolderPath "Installer";
		$this.RunbookFolderPath = Join-Path $this.FolderPath "CA-Runbook";
		
		$this.InstallerFileName = $moduleName + "-EasyInstaller.ps1";
		$this.InstallerFile = Join-Path $this.InstallerFolderPath $this.InstallerFileName;

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
			$azskOverride.UpdatePropertyValue("PolicyMessage", "Running $([Constants]::AzSKModuleName) cmdlet using ***$($this.OrgFullName)*** policy...");
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
		#If config already exists check and update for SAS token expiry for policy url and change in storage account RG Name
		else {
				$azskConfigContent = Get-Content -Path $askConfigFile.FullName | ConvertFrom-Json
				if([Helpers]::CheckMember($azskConfigContent,"CASetupRunbookURL") -and [Helpers]::IsSASTokenUpdateRequired($azskConfigContent.CASetupRunbookURL))
				{
					$azskConfigContent.CASetupRunbookURL = $this.CASetupRunbookURL
				}

				if([Helpers]::CheckMember($azskConfigContent,"AzSKConfigURL") -and [Helpers]::IsSASTokenUpdateRequired($azskConfigContent.AzSKConfigURL))
				{
					$azskConfigContent.AzSKConfigURL = $this.AzSKConfigURL
				}
				if([Helpers]::CheckMember($azskConfigContent,"AzSKRGName"))
                {
                    $RunbookScanAgentFile = Get-ChildItem $this.RunbookFolderPath -Force | Where-Object { $_.Name -eq "RunbookScanAgent.ps1" } | Select -First 1
                    $RunbookScanAgentFileContent =  Get-Content -Path $RunbookScanAgentFile.FullName
				    #Check Storage Account RG in scan agent
				    $pattern = 'StorageAccountRG = "(.*?)"'
				    $storageAccountRG = [Helpers]::GetSubString($RunbookScanAgentFileContent,$pattern)
				    if(-not [string]::IsNullOrEmpty($storageAccountRG) -and $storageAccountRG -ne $azskConfigContent.AzSKRGName)
				    {
					    $RunbookScanAgentFileContent = $RunbookScanAgentFileContent.Replace($storageAccountRG,$azskConfigContent.AzSKRGName)
					    Out-File -InputObject $RunbookScanAgentFileContent -Force -FilePath $($RunbookScanAgentFile.FullName) -Encoding utf8
				    }

                }
				$azskConfigContent | ConvertTo-Json -Depth 10 | Out-File -Force -FilePath $askConfigFile.FullName -Encoding utf8
		}


		$ServerConfigMetadataFile = (Get-ChildItem $this.ConfigFolderPath -Recurse -Force -Include $([Constants]::ServerConfigMetadataFileName) -ErrorAction SilentlyContinue)
		# Dynamically get list of files available in folder
		# TODO: Need to optimize the logic to calculate ServerConfigMetadataFileContent
		
		if($ServerConfigMetadataFile)
		{
			$filelist =@()
			$filelist += Get-ChildItem $this.ConfigFolderPath -Recurse -Force
			$ServerConfigMetadataFileContent =Get-Content $ServerConfigMetadataFile | ConvertFrom-Json
			$ConfigList = Get-ChildItem -Path $this.ConfigFolderPath -Recurse -File -Exclude "ServerConfigMetadata.json" | Select Name | ForEach-Object { $_.Name}
			if(($ConfigList | Measure-Object).Count -gt 0 )
			{
				$filelist | ForEach-Object {
					$fileName = $_.Name
					$ExistingFileConfig= $ServerConfigMetadataFileContent.OnlinePolicyList | Where-Object { $_.Name -eq  $fileName}
					if((($ExistingFileConfig | Measure-Object).Count -gt 0 -and  [Helpers]::CheckMember($ExistingFileConfig,"OverrideOffline") -and $ExistingFileConfig.OverrideOffline) -or  $fileName -like "*.ext.json" -or $fileName -like "*.ext.ps1" )
					{
						$metadataFileNames +=@{"Name"= $fileName; "OverrideOffline"=$True }
					}
					else
					{
						$metadataFileNames +=@{"Name"= $fileName}
					}
				}
			}
		}
		else {
			$metadataFileNames += Get-ChildItem $this.ConfigFolderPath -Recurse -Force |
								Where-Object { $_.mode -match "^-..--" -and $_.Name -ne [Constants]::ServerConfigMetadataFileName } |
								Select-Object -Property Name | Select-Object -ExpandProperty Name |								
								Select-Object @{ Label="Name"; Expression={ $_ } };
			}

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
			$fileName = Join-Path $PSScriptRoot ([Constants]::AzSKModuleName +"-EasyInstaller.ps1");
			if(-not (Test-Path -Path $fileName))
			{
				$fileName = Join-Path $PSScriptRoot "EasyInstaller.ps1";
			}
			#$fileName = $PSScriptRoot + "\EasyInstaller.ps1";
			$fileContent = Get-Content -Path $fileName;
			$fileContent = $fileContent.Replace("#PolicyUrl#", $this.PolicyUrl);
			$fileContent = $fileContent.Replace("#ModuleName#", $([Constants]::AzSKModuleName));
			$fileContent = $fileContent.Replace("#OrgName#", $this.OrgFullName);
			$fileContent = $fileContent.Replace("#AzureEnv#", $this.AzureEnvironment);
			$fileContent = $fileContent.Replace("#AzSKConfigURL#", $this.AzSKConfigURL);
			
			if(-not [string]::IsNullOrWhiteSpace($this.InstallerUrl))
			{
				$this.IWRCommand = "iwr '$($this.InstallerUrl)' -UseBasicParsing | iex";
			}
			$fileContent = $fileContent.Replace("#AutoUpdateCommand#", $this.IWRCommand);

			if (-not (Test-Path $folderName))
			{
				New-Item -ItemType Directory -Path $folderName -ErrorAction Stop | Out-Null
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
				New-Item -ItemType Directory -Path $this.RunbookFolderPath -ErrorAction Stop | Out-Null
			}

			if(((Get-ChildItem $this.RunbookFolderPath -Force | Where-Object { $_.Name -eq "RunbookScanAgent.ps1" } | Measure-Object).Count -eq 0) -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::All -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::CARunbooks)
			{
				$caFilePath = Join-Path (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName -ChildPath "Configurations" | Join-Path -ChildPath "ContinuousAssurance" | Join-Path -ChildPath "RunbookScanAgent.ps1";
				Copy-Item ($caFilePath) (Join-Path $this.RunbookFolderPath "RunbookScanAgent.ps1") -Force
			}

			$RunbookCoreSetupFile = Get-ChildItem $this.RunbookFolderPath -Force | Where-Object { $_.Name -eq "RunbookCoreSetup.ps1" } | Select -First 1
			if((($RunbookCoreSetupFile | Measure-Object).Count -eq 0) -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::All -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::CARunbooks)
			{
				$coreSetupFilePath = Join-Path (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName "Configurations" | Join-Path -ChildPath "ContinuousAssurance" | Join-Path -ChildPath "RunbookCoreSetup.ps1"
				Copy-Item ($coreSetupFilePath) (Join-Path $this.RunbookFolderPath "RunbookCoreSetup.ps1") -Force
				#Check for environment specific installer file
				$fileName = Join-Path $this.RunbookFolderPath "RunbookCoreSetup.ps1";
				if(Test-Path -Path $fileName)
				{
					$fileContent = Get-Content -Path $fileName;
					$fileContent = $fileContent.Replace("#AzSKConfigURL#", $this.AzSKConfigURL);
					Out-File -InputObject $fileContent -Force -FilePath $(Join-Path $this.RunbookFolderPath "RunbookCoreSetup.ps1") -Encoding utf8
				}
			}
			#If RunbookCoreSetup already exists, check for SAS token expiry and update with latest token 
			else {
				$RunbookCoreSetupContent =  Get-Content -Path $RunbookCoreSetupFile.FullName
				#Validate AzSkVersionForOrgUrl command
				$pattern = 'azskVersionForOrg = "(.*?)"'
				$coreSetupAzSkVersionForOrgUrl = [Helpers]::GetSubString($RunbookCoreSetupContent,$pattern)
				if(-not [string]::IsNullOrEmpty($coreSetupAzSkVersionForOrgUrl) -and [Helpers]::IsSASTokenUpdateRequired($coreSetupAzSkVersionForOrgUrl))
				{
					$RunbookCoreSetupContent = $RunbookCoreSetupContent.Replace($coreSetupAzSkVersionForOrgUrl,$this.AzSKConfigURL)
					Out-File -InputObject $RunbookCoreSetupContent -Force -FilePath $($RunbookCoreSetupFile.FullName) -Encoding utf8
				}
			}

			#Upload AzSKPreConfig with version details 
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
				$azskConfig | ConvertTo-Json | Out-File "$(Join-Path $this.RunbookFolderPath "AzSK.Pre.json")" -Force
			}

			
		}
		catch
		{
            $this.CommandError($_);
		}		
	}

	[MessageData[]] InstallPolicy()
    {
		$this.msgCount = 0
		if($this.IsUpdateSwitchOn)
		{
			$this.ValidatePolicyExists()
			$this.PublishCustomMessage([Constants]::UpdateOrgPolicyInstructionMsg);
		}
		else{
			$this.PublishCustomMessage([Constants]::InstallOrgPolicyInstructionMsg);
			$this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Info)
			$this.msgCount=$this.msgCount + 1
			$this.PublishCustomMessage("[$($this.msgCount)] Creating/Updating resources for supporting org policy in the policy host subscription...`n",[MessageType]::Warning)
		}
		$this.AppInsightInstance.CreateAppInsightIfNotExists()
		# if($this.AzureEnvironment -eq "AzureCloud"){
		# $this.AppInsightInstance.CreateAppInsightIfNotExists();
	    # }
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

			if(-not $this.IsUpdateSwitchOn)
			{
				$this.PublishCustomMessage("`nAll required resources created/updated successfully.",[MessageType]::Update)
			}
			
		}

		if(Test-Path -Path $this.ConfigFolderPath)
		{
			$include=@("*.ext.ps1","*.json",[Constants]::ServerConfigMetadataFileName)
			$policyFiles = Get-ChildItem -Path $this.ConfigFolderPath -Include $include -Recurse
			if(($policyFiles | Measure-Object).Count -gt 0)
			{
				#Validate if all Json file has any syntax issue			
				$InvalidSchemaJsonFiles = @()

				$policyFiles | Where-Object {$_.Name -like "*.json" } | ForEach-Object {
					$fileName = $_.Name
					try{
						$policyContent = Get-Content  $_.FullName | ConvertFrom-Json 
					}
					catch
					{
						$InvalidSchemaJsonFiles += $fileName
					}
				}

				#Validate if all PS1 file has any syntax issue
				$InvalidSchemaPSFiles = @()
				$policyFiles | Where-Object {$_.Name -like "*.ext.ps1" } | ForEach-Object {
					$fileName = $_.Name
					try{
						. $_.FullName  
					}
					catch
					{
						$InvalidSchemaPSFiles += $fileName
					}
				}

				if(($InvalidSchemaJsonFiles | Measure-Object).Count -gt 0 -or  ($InvalidSchemaPSFiles | Measure-Object).Count -gt 0)
				{
					if(($InvalidSchemaJsonFiles | Measure-Object).Count -gt 0 )
					{
						$this.PublishCustomMessage("Invalid schema for Json files: $($InvalidSchemaJsonFiles -Join ',')", [MessageType]::Error);
					}

					if(($InvalidSchemaPSFiles | Measure-Object).Count -gt 0 )
					{
						$this.PublishCustomMessage("Invalid schema for PS1 files: $($InvalidSchemaPSFiles -Join ','). Make sure there is no syntax issue or file is not in blocked state (Right click on file --> Properties --> Click 'Unblock' and Apply)", [MessageType]::Error);
					}
					throw ([SuppressedException]::new("Invalid schema found. Please correct schema and reupload policies.", [SuppressedExceptionType]::Generic))
				}
			}
		}
		$this.ModifyInstaller();

		$this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Info)
		$this.msgCount=$this.msgCount + 1
		$this.PublishCustomMessage("[$($this.msgCount)] Uploading policy files to policy server...`n",[MessageType]::Warning)
		$this.StorageAccountInstance.UploadFilesToBlob($this.InstallerContainerName, "", (Get-ChildItem -Path $this.InstallerFile));

		$this.CopyRunbook();
		if($container -and $container.CloudBlobContainer)
		{
			$this.CASetupRunbookURL = $container.CloudBlobContainer.Uri.AbsoluteUri + "/$($this.RunbookBaseVersion)/RunbookCoreSetup.ps1" + $this.StorageAccountInstance.GenerateSASToken($this.ConfigContainerName);
		}
		$this.ModifyConfigs();
		# Uploading Runbook files to container
		$allCAFiles = @();
		$allCAFiles += Get-ChildItem $this.RunbookFolderPath -Force | Where-Object { $_.mode -match "^-..--" }
		if($allCAFiles.Count -ne 0)
		{
	    	$this.StorageAccountInstance.UploadFilesToBlob($this.ConfigContainerName, $this.RunbookBaseVersion, $allCAFiles);
		}
		$allFiles = @();
		$allFiles += Get-ChildItem $this.ConfigFolderPath -Recurse -Force | Where-Object { $_.mode -match "^-..--" }

		if($allFiles.Count -ne 0)
		{
			$this.StorageAccountInstance.UploadFilesToBlob($this.ConfigContainerName, $this.Version, $allFiles);
		}
		else
		{
			$this.PublishCustomMessage(" `r`n.No configuration files found under folder [$($this.ConfigFolderPath)]", [MessageType]::Warning);
		}
		Copy-Item (Join-Path $PSScriptRoot "README.txt") (Join-Path $($This.FolderPath) "README.txt") -Force

		$this.PublishCustomMessage("All policy files have been uploaded successfully.`n",[MessageType]::Update)
		$this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Info)
		$this.msgCount=$this.msgCount + 1
		$this.PublishCustomMessage("[$($this.msgCount)] Generating an org-specific installer ('iwr' command) for your org...`n",[MessageType]::Warning)
		$this.PublishCustomMessage($($this.IWRCommand),[MessageType]::Info)
		$this.PublishCustomMessage("Installer generated successfully. Run the 'iwr' command above to install Organization specific version.`n`n",[MessageType]::Update)
		$this.PublishCustomMessage("`n")
		$this.PublishCustomMessage("IMPORTANT: Make sure anyone in your org who needs to scan according to your policies uses the above 'iwr' command to install AzSK. (They should not use 'install-module AzSK' directly. Anyone using an incorrect setup will not get your custom '$($this.OrgFullName)' policy when they run any AzSK cmdlet.)",[MessageType]::Warning)
		$this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Info)
		
		
		$this.CreateMonitoringDashboard()
		$this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Info)
		$this.PublishCustomMessage(" `r`nThe setup has been completed and policies have been copied to [$($this.FolderPath)].`r`n", [MessageType]::Update);
		$this.PublishCustomMessage("If you happen to lose/forget them, you can always re-download using Get-AzSKOrganizationPolicyStatus with -DownloadPolicy parameter.");
		$this.PublishCustomMessage(" `r`nNote: This is a basic setup and uses a public access blob for storing your org's installer. Once you have richer org policies, consider using a location/end-point protected by your tenant authentication.", [MessageType]::Warning);
		return @();
	}

	[void] CleanupTempFolders()
	{
		Remove-Item -Path $this.ConfigFolderPath -Force -Recurse -ErrorAction Ignore
		Remove-Item -Path $this.InstallerFolderPath -Force -Recurse -ErrorAction Ignore
	}

	[void] CreateMonitoringDashboard()
	{
		#Validate if monitoring dashboard is already created
		$dashboardResource = Get-AzResource -ResourceType "Microsoft.Portal/dashboards" -ResourceGroupName $($this.ResourceGroupName) -ErrorAction SilentlyContinue
		if((($dashboardResource | Measure-Object).Count -eq 0 ) -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::All -or $this.OverrideConfiguration -eq [OverrideConfigurationType]::MonitoringDashboard) 
		{
			$this.msgCount=$this.msgCount + 1
			$this.PublishCustomMessage("[$($this.msgCount)] Creating DevOps Kit ops monitoring dashboard in the policy host subscription...`n",[MessageType]::Warning)
			#$this.PublishCustomMessage("Creating DevOps Kit ops monitoring dashboard in the policy host subscription...");
			#Store dashboard template to temp location
			$MonitoringDashboardTemplatePath = Join-Path $([Constants]::AzSKTempFolderPath) "MonitoringDashboard";
			if(-not (Test-Path -Path $MonitoringDashboardTemplatePath))
			{
				New-Item -ItemType Directory -Path $MonitoringDashboardTemplatePath -Force | Out-Null
			}						
			$MonitoringDashboardTemplateObj = [ConfigurationManager]::LoadServerConfigFile("MonitoringDashboard.json"); 				
			$MonitoringDashboardTemplatePath = Join-Path $MonitoringDashboardTemplatePath "MonitoringDashboard.json";
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

			New-AzResourceGroupDeployment -Name "MonitoringDashboard" -TemplateFile $MonitoringDashboardTemplatePath   -ResourceGroupName $($this.ResourceGroupName) -TemplateParameterObject $parameters   
			$this.PublishCustomMessage("Monitoring dashboard created successfully. It lets you monitor the operations for various DevOps Kit workflows at your org.(e.g., CA issues, anomalous control drifts, evaluation errors, etc.). You can access it through this link: ", [MessageType]::Update);
			$rmContext = [ContextHelper]::GetCurrentRMContext();
			$tenantId = $rmContext.Tenant.Id
			$this.PublishCustomMessage("https://ms.portal.azure.com/#$($tenantId)/dashboard/arm/subscriptions/$($this.SubscriptionContext.SubscriptionId)/resourcegroups/$($this.ResourceGroupName)/providers/microsoft.portal/dashboards/devopskitmonitoring",[MessageType]::Update)
			$this.PublishCustomMessage('If you are not able to see monitoring dashboard with help of above link. You can navigate to below path `n Go to Azure Portal --> Select "Browse all dashboards" in dashboard dropdown --> Select type "Shared Dashboard" --> Select subscription where policy is setup -->Select "DevOps Kit Monitoring Dashboard [OrgName]"')
		}
	}

	[void] ValidatePolicyExists()
	{
		$OrgPolicyRG = Get-AzResourceGroup -Name $this.ResourceGroupName -ErrorAction SilentlyContinue

		if(-not $OrgPolicyRG)
		{
			throw ([SuppressedException]::new(("Org policy not found under resource group '$($this.ResourceGroupName)'. Please pass 'ResourceGroupName' and 'StorageAccountName' parameter to command if custom RG and StorageAccount name used to setup policy."), [SuppressedExceptionType]::InvalidArgument))

		}
		if (-not (Test-Path $this.FolderPath))
		{
			throw ([SuppressedException]::new(("Policy folder '$($this.FolderPath)' not found. Please pass 'PolicyFolderPath' parameter to command if custom policy path used to setup policy."), [SuppressedExceptionType]::InvalidArgument))
		}
	}

	[MessageData[]] CheckPolicyHealth()
	{
		[MessageData[]] $messages = @();
		$stepCount = 0;
		$checkDescription = ""
		$resultMsg = ""
		$detailedMsg = $null
		$resultStatus = ""
		$shouldReturn = $false

		[PSObject] $PolicyScanOutput = @{}
		$PolicyScanOutput.Resources = @{}
		
		$policyTempFolder = Join-Path $([Constants]::AzSKTempFolderPath) -ChildPath $this.OrgFullName | Join-Path -ChildPath "Policies";
		$orgPolicyOverallSummary = @()
		$appInsight =$null

		#region Check 01: Presence of Org policy resources		
		$stepCount++		
		$checkDescription = "Presence of Org policy resources(Policy StorageAccount/Telemetry AppInsights/Monitoring Dashboard)."
		$policyResourceGroup= Get-AzResourceGroup -Name $($this.ResourceGroupName) -ErrorAction SilentlyContinue  
		if(-not $policyResourceGroup)
		{
			$PolicyScanOutput.Resources.ResourceGroup = $false
			$failMsg = "Policy resource group[$($this.ResourceGroupName)] not found."			
			$resolvemsg = "Resolution: If custom resource names used to create Org policy, pass parameters ResourceGroupName and StorageAccountName to command '$($this.getCommandName)'."
			$resultMsg = "$failMsg`r`n$resolvemsg"
			$resultStatus = "Failed"
			$shouldReturn = $true
		}
		else 
		{
			$PolicyScanOutput.Resources.ResourceGroup = $true

			#b. Validate presense of policy resources storage, app insight and monitoring dashboard
		$policyResources= Get-AzResource -ResourceGroupName $($this.ResourceGroupName)
		#Check if poliy store  is present 
		$missingResources =@()
		$policyStore = $policyResources  | Where-Object {$_.ResourceType -eq "Microsoft.Storage/storageAccounts" }
		if(($policyStore | Measure-Object).Count -eq 0)
		{
			$missingResources +="storage account"
			$PolicyScanOutput.Resources.PolicyStore = $false
			$shouldReturn = $true
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
			$resultMsg = ""
			$resultStatus = "OK"
			$PolicyScanOutput.Resources.Status = $true
		}
		else
		{
			$failMsg = "Missing mandatory resources: $($missingResources -join ",")"			
			$resolvemsg = "Resolution: Run command '$($this.installCommandName)'"
			$resultMsg = "$failMsg`r`n$resolvemsg"
			$resultStatus = "Failed"
			$shouldReturn = $false
			$PolicyScanOutput.Resources.Status = $false
		}		
	}

	$messages += ($this.FormatGetPolicyCheckMessage($stepCount,$checkDescription,$resultStatus,$resultMsg,$detailedMsg,$orgPolicyOverallSummary))				
	if($shouldReturn)
	{
		return $messages
	}
	$detailedMsg = $Null	

			
		#region: Check 02: Presence of mandatory policies
		$stepCount++		
		$checkDescription = "Presence of mandatory policies(Installer/Runbooks/Configuration Index file etc)."

		$PolicyScanOutput.Policies = @{}
		$policies = $PolicyScanOutput.Policies
		$this.StorageAccountInstance.GetStorageAccountInstance()
		$this.FolderPath = $policyTempFolder 
		[Helpers]::CleanupLocalFolder($this.FolderPath)
		$this.ConfigFolderPath = Join-Path $this.FolderPath "Config";
		$this.InstallerFolderPath =Join-Path $this.FolderPath "Installer";
		$this.RunbookFolderPath = Join-Path $this.FolderPath "CA-Runbook";
		$policyBloblist = $this.DownloadPolicy()

		$currentContext = $this.StorageAccountInstance.StorageAccount.Context
		#Validate presense of installer
		$missingPolicies = @()
		$InstallerPath = Get-ChildItem -Path $policyTempFolder -File "$([Constants]::AzSKModuleName)-EasyInstaller.ps1" -Recurse 
		$Installer = $policyBloblist | Where-Object { $_.Name -eq "$([Constants]::AzSKModuleName)-EasyInstaller.ps1"} 
		if(($Installer | Measure-Object).Count -eq 0)
		{
			$missingPolicies += "Installer"
			$policies.Installer = $false
		}
		else
		{
			$policies.Installer = $true
		}

		#Validate presense of AzSK.Pre.json
		$AzSKPre = $policyBloblist | Where-Object { $_.Name -eq "$($this.RunbookBaseVersion)/AzSK.Pre.json"} 
		if(($AzSKPre | Measure-Object).Count -eq 0)
		{
			$missingPolicies += "AzSKPre Config"
			$policies.AzSKPre = $false
		}
		else
		{
			$policies.AzSKPre = $true
		}

		$RunbookCoreSetup =  $policyBloblist | Where-Object { $_.Name -eq "$($this.RunbookBaseVersion)/RunbookCoreSetup.ps1"} 
		if(($RunbookCoreSetup | Measure-Object).Count -eq 0)
		{
			$missingPolicies += "RunbookCoreSetup"
			$policies.RunbookCoreSetup = $false
		}
		else
		{
			$policies.RunbookCoreSetup = $true
		}

		$RunbookScanAgent = $policyBloblist | Where-Object { $_.Name -eq "$($this.RunbookBaseVersion)/RunbookScanAgent.ps1"} 
		if(($RunbookScanAgent | Measure-Object).Count -eq 0)
		{
			$missingPolicies += "RunbookScanAgent"
			$policies.RunbookScanAgent = $false
		}
		else
		{
			$policies.RunbookScanAgent = $true
		}


		$AzSKConfig = $policyBloblist | Where-Object { $_.Name -eq "$($this.Version)/AzSK.json"} 
		if(($AzSKConfig | Measure-Object).Count -eq 0)
		{
			$missingPolicies += "AzSK Config"
			$policies.AzSKConfig = $false
		}
		else
		{
			$policies.AzSKConfig = $true
		}

		$ServerConfigMetadata = $policyBloblist | Where-Object { $_.Name -like "$($this.Version)/ServerConfigMetadata.json"} 
		if(($ServerConfigMetadata | Measure-Object).Count -eq 0)
		{
			$missingPolicies += "ServerConfigMetadata"				
			$policies.ServerConfigMetadata = $false
		}
		else
		{
			$policies.ServerConfigMetadata = $true
		}

		if($policies.Installer -and $policies.AzSKPre -and $policies.RunbookCoreSetup -and $policies.RunbookScanAgent -and $policies.AzSKConfig -and $policies.ServerConfigMetadata)
		{
			$resultMsg = ""
			$resultStatus = "OK"
			$policies.Status =$true
		}
		else 
		{
			$failMsg = "Missing mandatory policies: $($missingPolicies -join ",") "			
			$resolvemsg = "Resolution: Run '$($this.updateCommandName)'"
			$resultMsg = "$failMsg`r`n$resolvemsg"
			$resultStatus = "Failed"
			$shouldReturn = $false
			$policies.Status =$false
		}
		$messages += ($this.FormatGetPolicyCheckMessage($stepCount,$checkDescription,$resultStatus,$resultMsg,$detailedMsg,$orgPolicyOverallSummary))				
		if($shouldReturn)
		{
			return $messages
		}
		$detailedMsg = $Null
		#endregion

		#retion Check 03: Validate installer file 
		$PolicyScanOutput.Configurations = @{}
		$PolicyScanOutput.Configurations.Installer = @{}
		$InstallOutput = $PolicyScanOutput.Configurations.Installer
		
		$stepCount++
		$checkDescription = "Check installer contains policy url/AzSK Version For Org reference(AzSK-EasyInstaller.ps1)."

		if($PolicyScanOutput.Policies.Installer)
		{
			$InstallerContent =  Get-Content -Path $InstallerPath.FullName
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
				$detailedMsg+="`nMissing Configuration: OnlinePolicyStoreUrl";
				$detailedMsg+="`nActual: $([Helpers]::IsStringEmpty($InstallerPolicyUrl))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($policyContainerUrl))";
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
				$detailedMsg+="`nMissing Configuration: AutoUpdateCommand";
				$detailedMsg+="`nActual: $([Helpers]::IsStringEmpty($autoUpdateCommandUrl))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($installerAbsoluteUrl))";
				$missingInstallerConfigurations += "AutoUpdateCommand"
			} 

			#Validate AzSKConfigURL
			$pattern = 'AzSKConfigURL = "(.*?)"'
			$InstallerAzSKPreUrl = [Helpers]::GetSubString($InstallerContent,$pattern)  

			$AzSKPreUrl = "Not Available"
			if($policies.AzSKPre)
			{
				$AzSKPreUrl= $AzSKPre.ICloudBlob.Uri.AbsoluteUri  
			}		 

			if($InstallerAzSKPreUrl -like "*$AzSKPreUrl*" )
			{
				$InstallOutput.AzSKPreUrl = $true
			}
			else
			{
				$InstallOutput.AzSKPreUrl = $false
				$detailedMsg+="`nMissing Configuration: AzSKPreConfigUrl";
				$detailedMsg+="`nActual: $([Helpers]::IsStringEmpty($InstallerAzSKPreUrl))  `n`t Expected Substring Url: $([Helpers]::IsStringEmpty($AzSKPreUrl))";
				$missingInstallerConfigurations += "AzSKPreConfigUrl"
			}

			if($InstallOutput.PolicyUrl -and $InstallOutput.AutoUpdateCommandUrl -and $InstallOutput.AzSKPreUrl)
			{
				#Validate SAS token expiry for Policy Url and AzSKPreUrl
				if([Helpers]::IsSASTokenUpdateRequired($InstallerPolicyUrl) -or [Helpers]::IsSASTokenUpdateRequired($InstallerAzSKPreUrl))
				{
					$failMsg = "SAS token for policy urls is getting expired in installer"			
					$resolvemsg = "Resolution: Run command '$($this.updateCommandName)'."
					$resultMsg = "$failMsg`r`n$resolvemsg"
					$resultStatus = "Failed"
					$shouldReturn = $false
					$InstallOutput.Status = $false  
				}	
				else {
					$resultMsg = ""
					$resultStatus = "OK"
					$InstallOutput.Status = $true
				}				
			}
			else
			{
				$failMsg = "Did not find a reference to $($missingInstallerConfigurations -join ",")  in installer."			
				$resolvemsg = "Resolution: Run '$($this.updateCommandName)' with the usual parameters."
				$resultMsg = "$failMsg`r`n$resolvemsg"
				$resultStatus = "Failed"
				$shouldReturn = $false
				$InstallOutput.Status = $false   
			}
		}
		else
		{
			$resultStatus = "Skipped"
			$resultMsg = "Installer not found."			
			$InstallOutput.Status = $false   
		}

		$messages += ($this.FormatGetPolicyCheckMessage($stepCount,$checkDescription,$resultStatus,$resultMsg,$detailedMsg,$orgPolicyOverallSummary))				
		if($shouldReturn)
		{
			return $messages
		}
		$detailedMsg = $Null
		#endregion

		#region Check 04: Validate AzSKPre
		$PolicyScanOutput.Configurations.AzSKPre = @{}
		$stepCount++		
		$checkDescription = "Check AzSK version configured for Org(AzSK.Pre.json)."		
		if($PolicyScanOutput.Policies.AzSKPre)
		{
		$AzSKPreConfigPath = Get-ChildItem -Path $policyTempFolder -File "AzSK.Pre.json" -Recurse
		$AzSKPreConfigContent =  Get-Content -Path $($AzSKPreConfigPath.FullName) | ConvertFrom-Json   

		#Validate CurrentVersionForOrg
		$LatestAzSKVersion = [ConfigurationManager]::GetAzSKConfigData().GetAzSKLatestPSGalleryVersion([Constants]::AzSKModuleName)
			if($AzSKPreConfigContent.CurrentVersionForOrg -eq $LatestAzSKVersion )
			{
				$resultMsg = ""
				$resultStatus = "OK"
				$PolicyScanOutput.Configurations.AzSKPre.Status = $true
				$PolicyScanOutput.Configurations.AzSKPre.CurrentVersionForOrg = $true
			}
			else
			{
				$PolicyScanOutput.Configurations.AzSKPre.Status = $true
				$PolicyScanOutput.Configurations.AzSKPre.CurrentVersionForOrg = $true				
				$failMsg = "Currently Org policy is running with older AzSK version [$([Helpers]::IsStringEmpty($($AzSKPreConfigContent.CurrentVersionForOrg)))]."			
				$resolvemsg = "Resolution: Consider updating it to latest available version [$([Helpers]::IsStringEmpty($($LatestAzSKVersion)))]."
				$resultMsg = "$failMsg`r`n$resolvemsg"
				$resultStatus = "Warning"
				$shouldReturn = $false				
			}			
		}
		else
		{
			$resultStatus = "Skipped"
			$resultMsg = "AzSKPreConfig not found."			
			$PolicyScanOutput.Configurations.AzSKPre.Status = $false  
		}
		$messages += ($this.FormatGetPolicyCheckMessage($stepCount,$checkDescription,$resultStatus,$resultMsg,$detailedMsg,$orgPolicyOverallSummary))				
		if($shouldReturn)
		{
			return $messages
		}
		$detailedMsg = $Null
		#endregion

		#region Check 05: Validate CoreSetup 
		$PolicyScanOutput.Configurations.RunbookCoreSetup = @{}
		$stepCount++		
		$checkDescription = "Continuous Assurance (CA) runbook must reference AzSK version in use for the org."
		if($PolicyScanOutput.Policies.RunbookCoreSetup)
		{
		$RunbookCoreSetupPath =Get-ChildItem -Path $policyTempFolder -File "RunbookCoreSetup.ps1" -Recurse
		$RunbookCoreSetupContent =  Get-Content -Path $RunbookCoreSetupPath.FullName     
		$missingCoreSetupConfigurations = @()
			#Validate AzSkVersionForOrgUrl command 
			$pattern = 'azskVersionForOrg = "(.*?)"'
			$coreSetupAzSkVersionForOrgUrl = [Helpers]::GetSubString($RunbookCoreSetupContent,$pattern)  
			
			#Recovery code for extra space included as part of coresetup update
			if([string]::IsNullOrEmpty($coreSetupAzSkVersionForOrgUrl))
			{
				$pattern = 'azskVersionForOrg =  "(.*?)"'
				$coreSetupAzSkVersionForOrgUrl = [Helpers]::GetSubString($RunbookCoreSetupContent,$pattern)  
			}
			
			$AzSkVersionForOrgUrl = "Not Available"
			if($policies.AzSKPre)
			{
				$AzSkVersionForOrgUrl = $AzSKPre.ICloudBlob.Uri.AbsoluteUri  
			}			

			if($coreSetupAzSkVersionForOrgUrl -like "*$AzSkVersionForOrgUrl*" )
			{
				$PolicyScanOutput.Configurations.RunbookCoreSetup.AzSkVersionForOrgUrl = $true
			}
			else
			{
				$PolicyScanOutput.Configurations.RunbookCoreSetup.AzSkVersionForOrgUrl = $false
				$missingCoreSetupConfigurations += "AzSkVersionForOrgUrl"
				$detailedMsg+="`nMissing Configuration: AzSkVersionForOrgUrl";
				$detailedMsg+="`nActual: $([Helpers]::IsStringEmpty($coreSetupAzSkVersionForOrgUrl))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($AzSkVersionForOrgUrl))";
			}
			
			if($PolicyScanOutput.Configurations.RunbookCoreSetup.AzSkVersionForOrgUrl)
			{
				#Validate SAS token expiry for Policy Url and AzSKPreUrl
				if([Helpers]::IsSASTokenUpdateRequired($coreSetupAzSkVersionForOrgUrl) )
				{
					$failMsg = "SAS token for policy urls is getting expired in runbookCoreSetup"			
					$resolvemsg = "Resolution: Run '$($this.updateCommandName)' with the usual parameters."
					$resultMsg = "$failMsg`r`n$resolvemsg"
					$resultStatus = "Failed"
					$shouldReturn = $false
					$InstallOutput.Status = $false  

				}
				else {
					$resultMsg = ""
					$resultStatus = "OK"
					$PolicyScanOutput.Configurations.RunbookCoreSetup.Status = $true
				}
				
			}
			else
			{
				$failMsg = "Did not find a reference to: $($missingCoreSetupConfigurations -join ",") in the CA runbook in RunbookCoreSetup.ps1"			
				$resolvemsg = "Resolution: Run '$($this.updateCommandName)' with the usual parameters + '-OverrideBaseConfig CARunbooks'"
				$resultMsg = "$failMsg`r`n$resolvemsg"
				$resultStatus = "Failed"
				$shouldReturn = $false
				$PolicyScanOutput.Configurations.RunbookCoreSetup.Status = $false
			}       
		}
		else
		{
			$resultStatus = "Skipped"
			$resultMsg = "RunbookCoreSetup not found."
			$PolicyScanOutput.Configurations.RunbookCoreSetup.Status = $false
		}
		$messages += ($this.FormatGetPolicyCheckMessage($stepCount,$checkDescription,$resultStatus,$resultMsg,$detailedMsg,$orgPolicyOverallSummary))				
		if($shouldReturn)
		{
			return $messages
		}
		$detailedMsg = $Null	
		#endregion


		#Check 06: Validate AzSKConfig
		$PolicyScanOutput.Configurations.AzSKConfig = @{}
		$stepCount++		
		$checkDescription = "Check AzSKConfig configured with controlTelemetryKey, installation command, Org AzSK version reference etc.(AzSK.json)."
		$AzSKConfiguOutput = $PolicyScanOutput.Configurations.AzSKConfig
		if($PolicyScanOutput.Policies.AzSKConfig)
		{
		$AzSKConfigPath =Get-ChildItem -Path $policyTempFolder -File "AzSK.json" -Recurse
		$AzSKConfigContent =  Get-Content -Path $($AzSKConfigPath.FullName) | ConvertFrom-Json
		$missingAzSKConfigurations = @()
		$expiringSASTokenConfigurations = @()
		$AzSKConfigCASetupRunbookUrl = [string]::Empty
		$AzSKPreConfigURL = [string]::Empty
		#Validate CurrentVersionForOrg 
		$RunbookCoreSetupUrl = "Not Available"
		if($policies.RunbookCoreSetup)
		{
			$RunbookCoreSetupUrl = $RunbookCoreSetup.ICloudBlob.Uri.AbsoluteUri 
		}    
		
			if([Helpers]::CheckMember($AzSKConfigContent,"CASetupRunbookURL") -and $AzSKConfigContent.CASetupRunbookURL -and $AzSKConfigContent.CASetupRunbookURL -like "*$RunbookCoreSetupUrl*")
			{
				$AzSKConfiguOutput.CASetupRunbookUrl = $true
			}
			else
			{
				$AzSKConfiguOutput.CASetupRunbookUrl = $false
				$missingAzSKConfigurations += "CASetupRunbookUrl"
				$detailedMsg+="`nMissing Configuration: CASetupRunbookUrl"
				$ActualValue = ""
				if([Helpers]::CheckMember($AzSKConfigContent,"CASetupRunbookURL"))
				{
					
					$ActualValue = $($AzSKConfigContent.CASetupRunbookURL)
					#Validate SAS token expiry for CASetupRunbook Url
					$AzSKConfigCASetupRunbookUrl = $ActualValue
					if([Helpers]::IsSASTokenUpdateRequired($AzSKConfigCASetupRunbookUrl))
					{
						$expiringSASTokenConfigurations += "CASetupRunbookUrl"
						$AzSKConfiguOutput.CASetupRunbookUrl = $false
						$detailedMsg+= "SAS token getting expired for CASetupRunbookURL."
					}

				}
				$detailedMsg+="`nActual: $([Helpers]::IsStringEmpty($($ActualValue)))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($($RunbookCoreSetupUrl)))";
			}
			
			#Validate ControlTelemetryKey 
			$appInsightResource= Get-AzApplicationInsights -ResourceGroupName $appInsight.ResourceGroupName -Name $appInsight.Name
			$InstrumentationKey =  $appInsightResource.InstrumentationKey

			if([Helpers]::CheckMember($AzSKConfigContent,"ControlTelemetryKey") -and $AzSKConfigContent.ControlTelemetryKey -and $AzSKConfigContent.ControlTelemetryKey -eq $InstrumentationKey)
			{
				$AzSKConfiguOutput.ControlTelemetryKey = $true
			}
			else
			{
				$AzSKConfiguOutput.ControlTelemetryKey = $false
				$missingAzSKConfigurations += "ControlTelemetryKey"
				$detailedMsg+="`nMissing Configuration: ControlTelemetryKey"
				$ActualValue = ""
				if([Helpers]::CheckMember($AzSKConfigContent,"ControlTelemetryKey"))
				{
					$ActualValue = $($AzSKConfigContent.ControlTelemetryKey)
				}
				$detailedMsg+="`nActual: $([Helpers]::IsStringEmpty($($ActualValue)))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($($InstrumentationKey)))";
			} 
			
			# Validate InstallationCommand     
			$installerAbsoluteUrl = "Not Available"
			if($policies.Installer)
			{
				$installerAbsoluteUrl = $Installer.ICloudBlob.Uri.AbsoluteUri
			}		 
			
			if([Helpers]::CheckMember($AzSKConfigContent,"InstallationCommand") -and $AzSKConfigContent.InstallationCommand -and $AzSKConfigContent.InstallationCommand -like "*$installerAbsoluteUrl*") 
			{
				$AzSKConfiguOutput.InstallationCommand = $true
			}
			else
			{
				$AzSKConfiguOutput.InstallationCommand = $false
				$missingAzSKConfigurations += "InstallationCommand"
				$detailedMsg+="`nMissing Configuration: InstallationCommand"
				$ActualValue = ""
				if([Helpers]::CheckMember($AzSKConfigContent,"InstallationCommand"))
				{
					$ActualValue = $($AzSKConfigContent.InstallationCommand)
				}
				$detailedMsg+="`nActual: $([Helpers]::IsStringEmpty($($ActualValue)))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($($installerAbsoluteUrl)))";
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
				$detailedMsg+="`nMissing Configuration: PolicyOrgName";
			}

			# Validate AzSKPre Url
			$azSKPreUrl = "Not Available"
			if($policies.AzSKPre)
			{
				$azSKPreUrl = $AzSKPre.ICloudBlob.Uri.AbsoluteUri 
			}

			if([Helpers]::CheckMember($AzSKConfigContent,"AzSKConfigURL") -and  $AzSKConfigContent.AzSKConfigURL  -and $AzSKConfigContent.AzSKConfigURL -like "*$azSKPreUrl*")
			{
				$AzSKConfiguOutput.AzSKPreConfigURL = $true				
				
			}
			else
			{
				$AzSKConfiguOutput.AzSKPreConfigURL = $false
				$missingAzSKConfigurations += "AzSKPreConfigURL"
				$detailedMsg+="`nMissing Configuration: AzSKPreConfigURL";
				$ActualValue = ""
				if([Helpers]::CheckMember($AzSKConfigContent,"AzSKConfigURL"))
				{
					$ActualValue = $($AzSKConfigContent.AzSKConfigURL)
				}
				$detailedMsg+="`nActual: $([Helpers]::IsStringEmpty($($ActualValue)))  `n`t Expected base Url: $([Helpers]::IsStringEmpty($($azSKPreUrl)))"
			}
			
			#Validate SAS token expiry for CASetupRunbook Url
			if([Helpers]::CheckMember($AzSKConfigContent,"AzSKConfigURL") -and [Helpers]::IsSASTokenUpdateRequired($AzSKConfigContent.AzSKConfigURL))
			{
				$expiringSASTokenConfigurations += "AzSKPreConfigURL"
				$AzSKConfiguOutput.AzSKPreConfigURL = $false
				$detailedMsg+= "SAS token getting expired for AzSKPreConfigURL."
			}

			if([Helpers]::CheckMember($AzSKConfigContent,"CASetupRunbookUrl")  -and $AzSKConfiguOutput.CASetupRunbookUrl -and $AzSKConfiguOutput.ControlTelemetryKey -and $AzSKConfiguOutput.InstallationCommand -and $AzSKConfiguOutput.PolicyOrgName -and $AzSKConfiguOutput.AzSKPreConfigURL ) 
			{
				$resultMsg = ""
				$resultStatus = "OK"
				
				$AzSKConfiguOutput.Status = $true

			}
			else
			{
				$failMsg = [string]::Empty
				$resolvemsg = [string]::Empty
				if(($missingAzSKConfigurations | Measure-Object).Count -gt 0)
				{
					$failMsg = "Did not find a reference to $($missingAzSKConfigurations -join ",") in AzSKConfig."			
					$resolvemsg = "Resolution: Run '$($this.updateCommandName)' with the usual parameters + '-OverrideBaseConfig AzSKRootConfig'"
				}
				#Check after missing configuration if SAS update required
				elseIf(($expiringSASTokenConfigurations | Measure-Object).Count -gt 0)
				{
					$failMsg = "SAS token for policy urls is getting expired in AzSKConfig: $($expiringSASTokenConfigurations -join ",")."			
					$resolvemsg = "Resolution: '$($this.updateCommandName)' with the usual parameters"
				}
				
				$resultMsg = "$failMsg`r`n$resolvemsg"
				$resultStatus = "Failed"
				$shouldReturn = $false				
				$AzSKConfiguOutput.Status = $false
			}

		}
		else
		{
			$resultStatus = "Skipped"
			$resultMsg = "AzSKConfig not found."
			$AzSKConfiguOutput.Status = $false  
		}
		$messages += ($this.FormatGetPolicyCheckMessage($stepCount,$checkDescription,$resultStatus,$resultMsg,$detailedMsg,$orgPolicyOverallSummary))				
		if($shouldReturn)
		{
			return $messages
		}
		$detailedMsg = ""
		#endregion


		#region Check 07: Check CA runbook referring to Org Policy URL
		$stepCount++		
		$checkDescription = "Check installed CA runbook referring to Org policy URL"
		$PolicyScanOutput.Configurations.CARunbook = @{}
		$runbookName = [Constants]::RunbookName
		$automationAccountName = [Constants]::AutomationAccount
		$caResourceGroupName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
		$subscriptionId = $this.SubscriptionContext.SubscriptionId
		$CARunbookOutput= $PolicyScanOutput.Configurations.CARunbook
		$azskRG = Get-AzResourceGroup -Name $caResourceGroupName -ErrorAction SilentlyContinue
		$automationAccount = Get-AzAutomationAccount -ResourceGroupName $caResourceGroupName -Name $automationAccountName -ErrorAction SilentlyContinue

		if($azskRG -and $automationAccount)
		{
			$ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()	
			$validatedUri = $ResourceAppIdURI+"subscriptions/$subscriptionId/resourceGroups/$caResourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks/$runbookName/content?api-version=2015-10-31"
			$ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
			$accessToken=[ContextHelper]::GetAccessToken($ResourceAppIdURI)
			$serverFileContent = Invoke-RestMethod `
												-Method GET `
												-Uri $validatedUri `
												-Headers @{"Authorization" = "Bearer $accessToken"} `
												-UseBasicParsing
			
			#Check if OSS CoreSetup is refered in runbooks
			$RunbookCoreSetupUrl = "Not Available"
			if($policies.RunbookCoreSetup)
			{
				$RunbookCoreSetupUrl = $RunbookCoreSetup.ICloudBlob.Uri.AbsoluteUri 
			}
			
			$policyContainerUrl= $AzSKConfig.ICloudBlob.Container.Uri.AbsoluteUri
			$policyReferenceUrl = "$policyContainerUrl/```$(```$Version)/```$(```$FileName)"
			if(-not $serverFileContent.Contains($RunbookCoreSetupUrl))
			{
				$pattern = 'CoreSetupSrcUrl = "(.*?)"'
				$actualCoreSetupUrl = [Helpers]::GetSubString($serverFileContent,$pattern)  
				if([String]::IsNullOrEmpty($actualCoreSetupUrl))
				{
					$pattern = 'OSSPolicyStoreUrl = "(.*?)"'
					$actualCoreSetupUrl = [Helpers]::GetSubString($serverFileContent,$pattern)
				}
				$CARunbookOutput.CoreSetupURL = $false				
				$detailedMsg+="`n Missing Configuration : [CoreSetupSrcUrl]"
				$detailedMsg+="`n Actual: $([Helpers]::IsStringEmpty($($actualCoreSetupUrl)))  `n`t Expected: $([Helpers]::IsStringEmpty($($RunbookCoreSetupUrl)))"
			}
			else
			{
				$CARunbookOutput.CoreSetupURL = $true
			}

			if(-not $serverFileContent.Contains($policyReferenceUrl))
			{
				$CARunbookOutput.PolicyURL = $false

				$detailedMsg+="`n Missing Configuration : [PolicyUrl]"
				$pattern = 'onlinePolicyStoreUrl = "(.*?)"'
				$actualPolicyUrl = [Helpers]::GetSubString($serverFileContent,$pattern)				
				$detailedMsg+="`n Actual: [$([Helpers]::IsStringEmpty($($actualPolicyUrl)))]  `n`t Expected: [$([Helpers]::IsStringEmpty($policyReferenceUrl))]"
			}
			else
			{
				$CARunbookOutput.PolicyURL = $true
			}
			if($CARunbookOutput.CoreSetupURL -and $CARunbookOutput.PolicyURL)
			{
				$resultMsg = ""
				$resultStatus = "OK"				
				$CARunbookOutput.Status = $true
			}
			else
			{
				$failMsg = "Installed CA runbook is not configured with Org policy url"			
				$resolvemsg = "Resolution: Run 'Update-AzSKContinuousAssurance -SubscriptionId <SubscriptionId>'."
				$resultMsg = "$failMsg`r`n$resolvemsg"
				$resultStatus = "Failed"
				$shouldReturn = $false
				$CARunbookOutput.Status = $false
			}
		}
		else
		{
			$resultStatus = "Skipped"
			$resultMsg = "CA not found in current subscription under resource group [$caResourceGroupName]."		
			$PolicyScanOutput.Configurations.CARunbook.Status = $true  
		}

		$messages += ($this.FormatGetPolicyCheckMessage($stepCount,$checkDescription,$resultStatus,$resultMsg,$detailedMsg,$orgPolicyOverallSummary))				
		if($shouldReturn)
		{
			return $messages
		}
		$detailedMsg = ""
		#endregion

		#region Check 08: Validate Syntax exceptions for policy files
		$PolicyScanOutput.SyntaxException= @{}
		$stepCount++		
		$checkDescription = "Check syntax exceptions for policies."

		$include=@("*.ext.ps1","*.json",[Constants]::ServerConfigMetadataFileName)
		$policyFiles = Get-ChildItem -Path $this.FolderPath -Include $include -Recurse
		if(($policyFiles | Measure-Object).Count -gt 0)
		{
			#Validate if all Json file has any syntax issue			
			$InvalidSchemaJsonFiles = @()

			$policyFiles | Where-Object {$_.Name -like "*.json" } | ForEach-Object {
				$fileName = $_.Name
				try{
					$policyContent = Get-Content  $_.FullName | ConvertFrom-Json 

					$schemaUrl = [string]::Empty
					$schemaDefination = $null
					#Validate policy against the schema template
					if([Helpers]::CheckMember($policyContent,"`$schema") -and -not [string]::IsNullOrEmpty($policyContent.'$schema'))
					{
						$schemaDefination = Invoke-RestMethod `
						-Method GET `
						-Uri $policyContent.'$schema'  #
						#-UseBasicParsing
					}
					else
					{
						$azskConfig = [ConfigurationManager]::GetAzSKConfigData()						
						if([Helpers]::CheckMember($policyContent,"FeatureName"))
						{
							$policyName = "ServiceControl"
						}
						else
						{
							$policyName = $_.Name.Replace(".json","")
						}
						$schemaUrl = $azskConfig.SchemaTemplateURL + $policyName
						try
						{
							$schemaDefination = Invoke-RestMethod `
							-Method GET `
							-Uri $schemaUrl
						}
						catch
						{
							#Skip exception of schema is not present on server side
							$messages += "Schema validation skipped for policy: $schemaUrl"	
						}
						
					}
						if($schemaDefination)
						{
							$schemaDefinationContent = $schemaDefination | ConvertTo-Json -Depth 10
							$jsonContent = Get-Content  $_.FullName
							$libraryPath = Join-Path (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName "ARMCheckerLib";
							$ErrorMessages= Start-Job  -ScriptBlock {
								param($jsonContent,$schemaDefinationContent,$libraryPath )
								Add-Type -Path (Join-Path $libraryPath "Newtonsoft.Json.dll")
								Add-Type -Path (Join-Path $libraryPath "Newtonsoft.Json.Schema.dll")
								$Token = [Newtonsoft.Json.Linq.JToken]::Parse($jsonContent)
								$Schema = [Newtonsoft.Json.Schema.JSchema]::Parse($schemaDefinationContent)
								$ErrorMessages = New-Object "System.Collections.Generic.List[string]"						
								$output= [Newtonsoft.Json.Schema.SchemaExtensions]::IsValid($Token, $Schema,[ref] $ErrorMessages)
								$ErrorMessages
							} -ArgumentList $jsonContent,$schemaDefinationContent,$libraryPath | Receive-Job -Wait -AutoRemoveJob 

							if(-not [string]::IsNullOrEmpty($ErrorMessages) )
							{
								$InvalidSchemaJsonFiles += $fileName
								$messages += $ErrorMessages								
							}
						}											
					

				}
				catch
				{
					$InvalidSchemaJsonFiles += $fileName
				}
			}
			
			#Validate if all PS1 file has any syntax issue
			$InvalidSchemaPSFiles = @()
			$policyFiles | Where-Object {$_.Name -like "*.ext.ps1" } | ForEach-Object {
				$fileName = $_.Name
				try{
					. $_.FullName  
				}
				catch
				{
					$InvalidSchemaPSFiles += $fileName
				}
			}

			if(($InvalidSchemaJsonFiles | Measure-Object).Count -gt 0 -or  ($InvalidSchemaPSFiles | Measure-Object).Count -gt 0)
			{
				$PolicyScanOutput.SyntaxException.Status = $false
				$failMsg = "Invalid schema present in policy files."
				if(($InvalidSchemaJsonFiles | Measure-Object).Count -gt 0 )
				{
					$failMsg +="Json files: $($InvalidSchemaJsonFiles -Join ',')";
				}

				if(($InvalidSchemaPSFiles | Measure-Object).Count -gt 0 )
				{
					$failMsg +="PS1 files: $($InvalidSchemaPSFiles -Join ',')."
				}						
				$resolvemsg = "Resolution: Make sure there is no syntax issue or file is not in blocked state (Right click on file --> Properties --> Click 'Unblock' and Apply. For more details about syntax issue, refer detail logs.)"
				$resultMsg = "$failMsg`r`n$resolvemsg"
				$resultStatus = "Failed"
				$shouldReturn = $false
					
			}
			else
			{
				$resultMsg = ""
				$resultStatus = "OK"
				$PolicyScanOutput.SyntaxException.Status =$true
			}

			$messages += ($this.FormatGetPolicyCheckMessage($stepCount,$checkDescription,$resultStatus,$resultMsg,$detailedMsg,$orgPolicyOverallSummary))				
			if($shouldReturn)
			{
				return $messages
			}
			$detailedMsg = $Null	
			#endregion
		}
		#endregion

		

		if(-not $PolicyScanOutput.Resources.Status -or -not $PolicyScanOutput.Policies.Status -or -not $InstallOutput.Status -or -not $PolicyScanOutput.Configurations.AzSKPre.Status -or  -not $PolicyScanOutput.Configurations.RunbookCoreSetup.Status -or  -not $AzSKConfiguOutput.Status -or -not $PolicyScanOutput.SyntaxException.Status -or -not $CARunbookOutput.Status)
		{
			$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Warning)
			$this.PublishCustomMessage("Your Org policy configuration is not correctly setup..`nReview the failed checks and follow the recommendations suggested.", [MessageType]::Warning) 
			$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Warning)
		}
		else
		{
			$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info);
			$this.PublishCustomMessage("Org policy configuration is in healthy state.", [MessageType]::Info); 
			$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info);
		}
		return $messages
	}

	[void] DownloadPolicies()
	{
		$bloblist= $this.DownloadPolicy()
	}

	#Function to download all policies from Org policy store
	[PSObject] DownloadPolicy()
	{
		[bool] $downloadPolicy = $true
		$PolicyList =@()
		$this.PublishCustomMessage("Downloading policies to location:[$($this.FolderPath)]...", [MessageType]::Info);	
		$this.StorageAccountInstance.GetStorageAccountInstance()

		if(Test-Path $this.FolderPath)
		{
			$existingPolicyFolderContent= Get-ChildItem -Path $($this.FolderPath) -ErrorAction SilentlyContinue
			if(($existingPolicyFolderContent | Measure-Object).Count -gt 0)
			{
				$this.PublishCustomMessage("Warning: Policy folder already contains files. Downloading policies can override existing files.", $([MessageType]::Warning))
				$answer= Read-Host "Do you want to continue(Y/N)"
				if($answer.ToLower() -ne "y" )
				{
					$downloadPolicy = $false
					$this.PublishCustomMessage("Skipped downloading policies.", [MessageType]::Update);
					#return
				}
			}
		}
		
		if($downloadPolicy)
		{
			#Downloading policies
			$PolicyList+=$this.StorageAccountInstance.DownloadFilesFromContainer($this.ConfigContainerName, $this.Version, $this.ConfigFolderPath, $true,$true)
			$PolicyList+=$this.StorageAccountInstance.DownloadFilesFromContainer($this.ConfigContainerName, $this.RunbookBaseVersion, $this.RunbookFolderPath, $true,$true)
			$PolicyList+=$this.StorageAccountInstance.DownloadFilesFromContainer($this.InstallerContainerName, "", $this.InstallerFolderPath, $true,$true)
			$this.PublishCustomMessage("Completed downloading policies", [MessageType]::Update);
		}
		return $PolicyList
	}

	#Function to upload module extensions
	[void] UpdateExtensions()
	{
		$this.PublishCustomMessage("Downloading latest policy index file[ServerConfigMetadata.json] from Org policy store...", [MessageType]::Info);
		#Download ServConfigMetadata (index file) from policy store
		$serverConfigMetadataBlobName = Join-Path $this.Version $([Constants]::ServerConfigMetadataFileName)
		$this.StorageAccountInstance.GetStorageAccountInstance()
		$this.StorageAccountInstance.DownloadFilesFromBlob($this.ConfigContainerName, $serverConfigMetadataBlobName, $this.FolderPath, $true,$true)
		$this.PublishCustomMessage("Completed downloading latest policy index file.", [MessageType]::Update);
		#Get all extensions 
		$include=@("*.ext.ps1","*.ext.json",[Constants]::ServerConfigMetadataFileName)
		
		$extensionFiles = Get-ChildItem -Path $this.FolderPath -Include $include -Recurse
		if(($extensionFiles | Measure-Object).Count -gt 0)
		{

			#Validate if all Json file has any syntax issue
			$this.PublishCustomMessage("Validating sytax exception for extension files...", [MessageType]::Info);
			$InvalidSchemaJsonFiles = @()

			$extensionFiles | Where-Object {$_.Name -like "*.ext.json" } | ForEach-Object {
				$fileName = $_.Name
				try{
					$extensionContent = Get-Content  $_.FullName | ConvertFrom-Json 
				}
				catch
				{
					$InvalidSchemaJsonFiles += $fileName
				}
			}

			#Validate if all PS1 file has any syntax issue
			$InvalidSchemaPSFiles = @()
			$extensionFiles | Where-Object {$_.Name -like "*.ext.ps1" } | ForEach-Object {
				$fileName = $_.Name
				try{
					. $_.FullName  
				}
				catch
				{
					$InvalidSchemaPSFiles += $fileName
				}
			}

			if(($InvalidSchemaJsonFiles | Measure-Object).Count -gt 0 -or  ($InvalidSchemaPSFiles | Measure-Object).Count -gt 0)
			{
				if(($InvalidSchemaJsonFiles | Measure-Object).Count -gt 0 )
				{
					$this.PublishCustomMessage("Invalid schema for Json files: $($InvalidSchemaJsonFiles -Join ',')", [MessageType]::Error);
				}

				if(($InvalidSchemaPSFiles | Measure-Object).Count -gt 0 )
				{
					$this.PublishCustomMessage("Invalid schema for PS1 files: $($InvalidSchemaPSFiles -Join ','). Make sure there is no syntax issue or file is not in blocked state (Right click on file --> Properties --> Click 'Unblock' and Apply)", [MessageType]::Error);
				}
				throw ([SuppressedException]::new("Invalid schema found. Please correct schema and reupload extensions.", [SuppressedExceptionType]::Generic))
			}
			$this.PublishCustomMessage("Completed validating sytax exception for extension files.", [MessageType]::Update);
			$serverConfigMetadataPath = Join-Path $this.FolderPath $([Constants]::ServerConfigMetadataFileName) 
			$serverConfigMetadata = Get-Content -Path $serverConfigMetadataPath | ConvertFrom-Json

			# Dynamically get list of files available in folder
			# TODO: Need to optimize the logic to calculate ServerConfigMetadataFileContent
			if($serverConfigMetadata)
			{
				$this.PublishCustomMessage("Updating index file with latest extension list...", [MessageType]::Info);
				if(($extensionFiles | Measure-Object).Count -gt 0 )
				{
					$extensionFiles | ForEach-Object {
						$fileName = $_.Name
						$ExistingFileConfig= $serverConfigMetadata.OnlinePolicyList | Where-Object { $_.Name -eq  $fileName}
						if(($ExistingFileConfig | Measure-Object).Count -eq 0)
						{
							$serverConfigMetadata.OnlinePolicyList  +=@{"Name"= $fileName; "OverrideOffline"=$True }
						}
						else
						{
							if(-not  [Helpers]::CheckMember($ExistingFileConfig,"OverrideOffline"))
							{
								$ExistingFileConfig =@{"Name"= $fileName; "OverrideOffline"=$True}
							}
						}
					}
				}
				$serverConfigMetadata | ConvertTo-Json | Out-File  -Force -FilePath ($this.FolderPath + $([Constants]::ServerConfigMetadataFileName)) -Encoding utf8
				$this.PublishCustomMessage("Completed updating index file with latest extension list.", [MessageType]::Info);
				
				#Upload extension files to policy store
				$this.PublishCustomMessage("Uploading extensions to policy store...", [MessageType]::Info);
				$this.StorageAccountInstance.UploadFilesToBlob($this.ConfigContainerName, $this.Version, $extensionFiles);
				$this.PublishCustomMessage("Completed uploading extensions to policy store.", [MessageType]::Update);
			}
			else {
				throw ([SuppressedException]::new("Policy index file not found.", [SuppressedExceptionType]::Generic))
			}
			}
		else
		{
			throw ([SuppressedException]::new("No extension files found.", [SuppressedExceptionType]::Generic))
		}
	}

	[MessageData[]] FormatGetPolicyCheckMessage($checkCount, $description, $resultStatus, $resultMsg, $detailedMsg, $summaryTable)
	{
		[MessageData[]] $returnMsg = @();
		$messageType = $Null
		$commonFailMsg = [Constants]::SingleDashLine + "`r`nFound that AzSK Org policy is not correctly setup.`r`nReview the failed check and follow the remedy suggested. If it does not work, please file a support request after reviewing the FAQ.`r`n"+[Constants]::SingleDashLine;

		$newMsg = [MessageData]::new("Check $($checkCount.ToString("00")): $description", [MessageType]::Info)
		$this.PublishCustomMessage($newMsg)
		$returnMsg += $newMsg

		switch($resultStatus)
		{
			"OK" {$messageType = [MessageType]::Update}
			"Failed" {$messageType = [MessageType]::Error}
			"Skipped" {$messageType = [MessageType]::Warning}
			"Unhealthy" {$messageType = [MessageType]::Warning}
			"Warning" {$messageType = [MessageType]::Warning}
		}
		if($null -ne $detailedMsg)
		{
			$returnMsg += $detailedMsg
		}
		$newMsg = [MessageData]::new("Status:   $resultStatus. $resultMsg",$messageType)
		$returnMsg += $newMsg
		$this.PublishCustomMessage($newMsg);

		$this.PublishCustomMessage([MessageData]::new([Constants]::SingleDashLine));
		$returnMsg += [MessageData]::new([Constants]::SingleDashLine);
		
		if($summaryTable.Count -gt 0)
		{
			$summaryTable | ForEach-Object{
				$this.PublishCustomMessage($_)
			}
			$returnMsg += $summaryTable;		
		}
		# if($resultStatus -eq "Failed")
		# {
		# 	$this.PublishCustomMessage([MessageData]::new("$commonFailMsg",  [MessageType]::Warning))
		# 	$returnMsg += $commonFailMsg
		# }
		return $returnMsg
	}
}

