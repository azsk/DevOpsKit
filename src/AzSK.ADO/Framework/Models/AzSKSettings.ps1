using namespace System.Management.Automation
Set-StrictMode -Version Latest
class AzSKSettings {
    [string] $LAWSId;
    [string] $LAWSSharedKey;
	[string] $AltLAWSId;
    [string] $AltLAWSSharedKey;
    [string] $LAType;
	[string] $LASource;

	[string] $EventHubNamespace;
	[string] $EventHubName;
	[string] $EventHubSendKeyName;
	[string] $EventHubSendKey;
    [string] $EventHubType;
	[string] $EventHubSource;
	[string] $WebhookUrl;
	[string] $WebhookAuthZHeaderName;
	[string] $WebhookAuthZHeaderValue;
	[string] $WebhookType;
	[string] $WebhookSource;
	[string] $AutoUpdateCommand;
	[AutoUpdate] $AutoUpdateSwitch = [AutoUpdate]::On;

	[string] $OutputFolderPath;

	[TertiaryBool] $AllowSelfSignedWebhookCertificate;
	[bool] $EnableAADAuthForOnlinePolicyStore;
    [bool] $UseOnlinePolicyStore;
	[string] $OnlinePolicyStoreUrl;
	[string] $AzureEnvironment;
	[string] $UsageTelemetryLevel;
	[string] $LocalControlTelemetryKey;
	[bool] $LocalEnableControlTelemetry;
	[bool] $PrivacyNoticeAccepted = $false;
	[bool] $IsCentralScanModeOn = $false;
    hidden static [AzSKSettings] $Instance = $null;
	hidden static [string] $FileName = "AzSKSettings.json";
	[bool] $StoreComplianceSummaryInUserSubscriptions;	
	static [SubscriptionContext] $SubscriptionContext
	static [InvocationInfo] $InvocationContext
	[string] $BranchId;

	AzSKSettings()
	{	
	}
    AzSKSettings([SubscriptionContext] $subscriptionContext, [InvocationInfo] $invocationContext)
	{
		[AzSKSettings]::SubscriptionContext = $subscriptionContext;
		[AzSKSettings]::InvocationContext = $invocationContext;	
	}
	hidden static SetDefaultSettings([AzSKSettings] $settings) {
		if($null -ne  $settings -and [string]::IsNullOrWhiteSpace( $settings.AzureEnvironment))
		{
            $settings.AzureEnvironment = [Constants]::DefaultAzureEnvironment
		}
	}

    static [AzSKSettings] GetInstance() {
        if (-not [AzSKSettings]::Instance)
		{
			[AzSKSettings]::LoadAzSKSettings($false);
			[AzSKSettings]::SetDefaultSettings([AzSKSettings]::Instance);
			#todo: change to default env by using a fn
        }

        return [AzSKSettings]::Instance
	}

	static [AzSKSettings] GetLocalInstance() {
	    $settings = [AzSKSettings]::LoadAzSKSettings($true);
		[AzSKSettings]::SetDefaultSettings($settings);
		return $settings
    }

    hidden static [AzSKSettings] LoadAzSKSettings([bool] $loadUserCopy) {
        #Filename will be static.
        #For AzSK Settings, never use online policy store. It's assumed that file will be available offline
		#-------- AzSK rename code change--------#
		$localAppDataSettings = $null
		
		if(-not $localAppDataSettings)
		{
			$localAppDataSettings = [ConfigurationHelper]::LoadOfflineConfigFile([AzSKSettings]::FileName)
		}
		
		#------------------------------#	
		[AzSKSettings] $parsedSettings = $null;
		[AzSKSettings] $localModuleSettings = $null;
		[AzSKSettings] $serverSettings = $null;
		$migratedPropNames = @();
        #Validate settings content is not null
        if ($localAppDataSettings) {
			try
			{
				#Step1: Try parsing the object from local app data settings. If parse is successful then there is no change to settings schema.
				$parsedSettings = [AzSKSettings] $localAppDataSettings
			}
			catch
			{
				#Step2: Any error occurred while converting local json file indicates change in schema
				#Load latest Settings from modules folder
				$parsedSettings = [ConfigurationHelper]::LoadModuleJsonFile([AzSKSettings]::FileName)
				$parsedSettings | Get-Member -MemberType Properties |
					ForEach-Object {
						$propertyName = $_.Name;

						if($propertyName -eq "LAWSId" -or $propertyName -eq "LAWSSharedKey" -or $propertyName -eq "AltLAWSId" -or $propertyName -eq "AltLAWSSharedKey" -or $propertyName -eq "LAType" -or $propertyName -eq "LASource")
						{
							switch($propertyName)
							{
								"LAWSId"{
									$newSetting = "OMSWorkspaceId"
									break;
								}
								"LAWSSharedKey"{
									$newSetting = "OMSSharedKey"
									break;
								}
								"AltLAWSId"{
									$newSetting = "AltOMSWorkspaceId"
									break;
								}
								"AltLAWSSharedKey"{
									$newSetting = "AltOMSSharedKey"
									break;
								}
								"LAType"{
									$newSetting = "OMSType"
									break;
								}
								"LASource"{
									$newSetting = "OMSSource"
									break;
								}								
							}
							$parsedSettings.$propertyName = $localAppDataSettings.$newSetting
							$migratedPropNames += $newSetting;
						}

						if([Helpers]::CheckMember($localAppDataSettings, $propertyName))
						{
							$parsedSettings.$propertyName = $localAppDataSettings.$propertyName;
							$migratedPropNames += $propertyName;
						}
					};

				if($migratedPropNames.Count -ne 0)
				{
                    [AzSKSettings]::Update($parsedSettings);
					[EventBase]::PublishGenericCustomMessage("Local AzSK settings file was not compatible with the latest version. `r`nMigrated the existing values for properties: [$([string]::Join(", ", $migratedPropNames))] ", [MessageType]::Warning);
				}
			}

			#Step 3: Get the latest server settings and merge with that
			if(-not $loadUserCopy)
			{
				if([AzSKSettings]::InvocationContext)
				{
					$parsedSettings.OnlinePolicyStoreUrl = [AzSKSettings]::SetPolicy($parsedSettings.OnlinePolicyStoreUrl, $parsedSettings.BranchId)	
				}
				
				[bool] $_useOnlinePolicyStore = $parsedSettings.UseOnlinePolicyStore;
				[string] $_onlineStoreUri = $parsedSettings.OnlinePolicyStoreUrl;
				[bool] $_enableAADAuthForOnlinePolicyStore = $parsedSettings.EnableAADAuthForOnlinePolicyStore;
				$serverSettings = [ConfigurationHelper]::LoadServerConfigFile([AzSKSettings]::FileName, $_useOnlinePolicyStore, $_onlineStoreUri, $_enableAADAuthForOnlinePolicyStore);

				$mergedServerPropNames = @();
				$serverSettings | Get-Member -MemberType Properties |
					ForEach-Object {
						$propertyName = $_.Name;
						if([string]::IsNullOrWhiteSpace($parsedSettings.$propertyName) -and -not [string]::IsNullOrWhiteSpace($serverSettings.$propertyName))
						{
							$parsedSettings.$propertyName = $serverSettings.$propertyName;
							$mergedServerPropNames += $propertyName;
						}
					};		
					
				[AzSKSettings]::Instance = $parsedSettings;				
			}
            #Sever merged settings should not be persisted, as it should always take latest from the server
			return $parsedSettings;
        }
		else
		{
			return $null;
		}
    }

    [void] Update()
	{
		if (-not (Test-Path $([Constants]::AzSKAppFolderPath)))
		{
			New-Item -ItemType Directory -Path $([Constants]::AzSKAppFolderPath) -ErrorAction Stop | Out-Null
		}

		#persisting back to file
		[AzSKSettings]::Instance | ConvertTo-Json | Out-File -Force -FilePath (Join-Path $([Constants]::AzSKAppFolderPath) $([AzSKSettings]::FileName))
	}

    static [void] Update([AzSKSettings] $localSettings)
	{
		if (-not (Test-Path $([Constants]::AzSKAppFolderPath)))
		{
			New-Item -ItemType Directory -Path $([Constants]::AzSKAppFolderPath) -ErrorAction Stop | Out-Null
		}

		#persisting back to file
		$localSettings | ConvertTo-Json | Out-File -Force -FilePath (Join-Path $([Constants]::AzSKAppFolderPath) $([AzSKSettings]::FileName))
	}
	
	hidden [string] GetScanSource()
	{
		return $this.LASource
	}

	hidden static [string] SetPolicy([string] $onlinePolicyStoreUrl, $branch)
	{
		$projectName = "";
		$orgName = [AzSKSettings]::SubscriptionContext.SubscriptionName;
		$repoName = "";
		$isPolicyProjectFound = $false;
		
		if([AzSKSettings]::InvocationContext.BoundParameters["PolicyProject"]){
			$projectName = [AzSKSettings]::InvocationContext.BoundParameters["PolicyProject"];
            try { 
				$rmContext = [ContextHelper]::GetCurrentContext();
		        $user = "";
		        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user, $rmContext.AccessToken)))
		
			    $prjUri = "https://dev.azure.com/{0}/_apis/projects/{1}?api-version=6.0" -f [AzSKSettings]::SubscriptionContext.SubscriptionName, $projectName;
				$prjObj = Invoke-RestMethod -Uri $prjUri -Method Get -ContentType "application/json" -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo) }
				
				$repository = [Constants]::OrgPolicyRepo + $projectName
				try {
					$repoUri = "https://dev.azure.com/{0}/{1}/_apis/git/repositories/{2}?api-version=4.1" -f [AzSKSettings]::SubscriptionContext.SubscriptionName, $projectName, $repository;
					$repoObj = Invoke-RestMethod -Uri $repoUri -Method Get -ContentType "application/json" -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo) }

					#policy project found and policy repo found inside project
					$isPolicyProjectFound = $true;
					$repoName = [Constants]::OrgPolicyRepo + $projectName;
					Write-Host -ForegroundColor Green "Using policy from: [$orgName::$projectName::$repoName]"
				}
				catch {
					Write-Host "[$($repository)] repository is not found in the policy project." -ForegroundColor Yellow
				}
            }
            catch {
				Write-Host 'Policy project not found: Incorrect project name or you do not have neccessary permission to access the project.' -ForegroundColor Yellow
            }
		}
		if(([AzSKSettings]::InvocationContext.BoundParameters["ProjectNames"]) -and !$isPolicyProjectFound){
			$projectName = [AzSKSettings]::InvocationContext.BoundParameters["ProjectNames"].split(',')[0];
			$repoName = [Constants]::OrgPolicyRepo + $projectName;
			try {
				$rmContext = [ContextHelper]::GetCurrentContext();
		        $user = "";
		        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user, $rmContext.AccessToken)))
		
				$repoUri = "https://dev.azure.com/{0}/{1}/_apis/git/repositories/{2}?api-version=4.1" -f [AzSKSettings]::SubscriptionContext.SubscriptionName, $projectName, $repoName;
				$repoObj = Invoke-RestMethod -Uri $repoUri -Method Get -ContentType "application/json" -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)}
				Write-Host -ForegroundColor Green "Using policy from: [$orgName::$projectName::$repoName]"
			}
			catch {
				#Write-Host "[$($repoName)] repository is not found in the project." -ForegroundColor Yellow
			}
		}
		elseif (!$isPolicyProjectFound)
		{
			Write-Host -ForegroundColor Yellow "Not using online policy. No project specified. (*TODO*: Use explicit policyProject param?)"
		}

		# If $branch variable valus is null or empty, then set its default value as 'master' (production policy branch)
		if(!$branch)
		{
			$branch = "master";
		}
		
		return $onlinePolicyStoreUrl -f $orgName, $projectName, $repoName, $branch
	}
}
