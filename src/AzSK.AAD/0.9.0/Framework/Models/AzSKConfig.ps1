Set-StrictMode -Version Latest
class AzSKConfig
{
    [string] $MaintenanceMessage
	[string] $AzSKRGName
	[string] $AzSKRepoURL
	[string] $AzSKServerVersion
	[string[]] $SubscriptionMandatoryTags = @()
	[string] $ERvNetResourceGroupNames
	[string] $UpdateCompatibleCCVersion
	[string] $AzSKApiBaseURL;
	[bool] $PublishVulnDataToApi;
	[string] $ControlTelemetryKey;
	[bool] $EnableControlTelemetry;
	[string] $PolicyMessage;
	[string] $AzSKLocation;
	[string] $InstallationCommand;
	[string] $PublicPSGalleryUrl;
	[string] $AzSKCARunbookVersion;
	[string] $AzSKCAMinReqdRunbookVersion;
	[string] $AzSKAlertsMinReqdVersion;
	[string] $AzSKARMPolMinReqdVersion;
	[string[]] $PrivacyAcceptedSources = @();
	[string] $OutputFolderPath;
	[int] $BackwardCompatibleVersionCount;
	[string[]] $DefaultControlExculdeTags = @()
	[string[]] $DefaultControlFiltersTags = @()
	[System.Version[]] $AzSKVersionList = @()
	[int] $CAScanIntervalInHours;
	[string] $ConfigSchemaBaseVersion;
	[string] $AzSKASCMinReqdVersion;
	#Bool flag to check selfsigned cert to avoid break of current configurations
	[bool] $AllowSelfSignedWebhookCertificate;
	[bool] $EnableDevOpsKitSetupCheck;
	[bool] $UpdateToLatestVersion;
	[string] $CASetupRunbookURL;
	[string] $AzSKConfigURL;
    [bool] $IsAlertMonitoringEnabled;
	[string] $SupportDL;
	[string] $RunbookScanAgentBaseVersion;
	[string] $PolicyOrgName;
	[bool] $StoreComplianceSummaryInUserSubscriptions;
	[string] $LatestPSGalleryVersion;
	[string] $SchemaTemplateURL;
	[bool] $EnableAzurePolicyBasedScan;
	[string] $AzSKInitiativeName;
	hidden static [AzSKConfig] $Instance = $null;
	
    static [AzSKConfig] GetInstance([bool] $useOnlinePolicyStore, [string] $onlineStoreUri, [bool] $enableAADAuthForOnlinePolicyStore)
    {
        if ( $null -eq  [AzSKConfig]::Instance)
        {
            [AzSKConfig]::Instance = [AzSKConfig]::LoadRootConfiguration($useOnlinePolicyStore,$onlineStoreUri,$enableAADAuthForOnlinePolicyStore)
        }

        return [AzSKConfig]::Instance
    }

	hidden static [AzSKConfig] LoadRootConfiguration([bool] $useOnlinePolicyStore, [string] $onlineStoreUri, [bool] $enableAADAuthForOnlinePolicyStore)
    {
        #Config filename will be static constant 
        return [AzSKConfig] ([ConfigurationHelper]::LoadServerConfigFile("AzSK.json", $useOnlinePolicyStore, $onlineStoreUri, $enableAADAuthForOnlinePolicyStore));
    }

	hidden  [string] GetLatestAzSKVersion([string] $moduleName)
    {
		if([string]::IsNullOrWhiteSpace($this.AzSKServerVersion))
		{
			$this.AzSKServerVersion = "0.0.0.0";
			try
			{
					
				if((-not [string]::IsNullOrWhiteSpace($this.AzSKConfigURL)) -and (-not $this.UpdateToLatestVersion))
				{
					try
					{
						$serverFileContent = [ConfigurationHelper]::InvokeControlsAPI($this.AzSKConfigURL, '', '', '');
						if($null -ne $serverFileContent)
						{
							if(-not [string]::IsNullOrWhiteSpace($serverFileContent.CurrentVersionForOrg))
							{
								$this.AzSKServerVersion = $serverFileContent.CurrentVersionForOrg
							}
						}
					}
					catch
					{
						# If unable to fetch server config file or module version property then continue and download latest version module.
					}
				}

				if($this.AzSKServerVersion -eq '0.0.0.0')
				{
					$repoUrl = $this.AzSKRepoURL;
					#Searching for the module in the repo
					$Url = "$repoUrl/api/v2/Search()?`$filter=IsLatestVersion&searchTerm=%27$moduleName%27&includePrerelease=false" 
					[System.Uri] $validatedUri = $null;
					if([System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref] $validatedUri))
					{
						$SearchResult = @()
						$SearchResult += Invoke-RestMethod -Method Get -Uri $validatedUri -UseBasicParsing
						if($SearchResult.Length -and $SearchResult.Length -gt 0) 
						{
								#filter latest module
								$SearchResult = $SearchResult | Where-Object -FilterScript {
									return $_.title.'#text' -eq $moduleName
								} 
								$moduleName = $SearchResult.title.'#text' # get correct casing for the module name
								$PackageDetails = Invoke-RestMethod -Method Get -UseBasicParsing -Uri $SearchResult.id 
								$this.AzSKServerVersion = $PackageDetails.entry.properties.version
						}
					}
				}
			}
			catch
			{
				$this.AzSKServerVersion = "0.0.0.0";
			}
		}
		return $this.AzSKServerVersion;
    }

	#Function to get list of AzSK version using API
	hidden [System.Version[]] GetAzSKVersionList([string] $moduleName)
    {
		if(($this.AzSKVersionList | Measure-Object).Count -eq 0)
		{
			try
			{
				$repoUrl = $this.AzSKRepoURL;
				#Searching for the module in the repo
				$Url = "$repoUrl/api/v2/FindPackagesById()?id='$moduleName'&`$skip=0&`$top=40&`$orderby=Version desc" 
				[System.Uri] $validatedUri = $null;
				if([System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref] $validatedUri))
				{                    
					$searchResult = Invoke-RestMethod -Method Get -Uri $validatedUri -UseBasicParsing
					$versionList =@()
					if($searchResult.Length -and $searchResult.Length -gt 0) 
					{
						$versionList += $SearchResult | Where-Object {$_.title.'#text' -eq $ModuleName
						} | ForEach-Object {[System.Version] $_.properties.version }											
						$this.AzSKVersionList = $versionList
					}
				}
			}
			catch
			{
				$this.AzSKVersionList = @();
			}
		}
		return $this.AzSKVersionList;
	}
	
	hidden [string] GetAzSKLatestPSGalleryVersion([string] $moduleName)
	{
		if([string]::IsNullOrWhiteSpace($this.LatestPSGalleryVersion))
		{
			$this.LatestPSGalleryVersion = "0.0.0.0";
			try
			{
				if($this.LatestPSGalleryVersion -eq '0.0.0.0')
				{
					$repoUrl = $this.AzSKRepoURL;
					#Searching for the module in the repo
					$Url = "$repoUrl/api/v2/Search()?`$filter=IsLatestVersion&searchTerm=%27$moduleName%27&includePrerelease=false" 
					[System.Uri] $validatedUri = $null;
					if([System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref] $validatedUri))
					{
						$SearchResult = @()
						$SearchResult += Invoke-RestMethod -Method Get -Uri $validatedUri -UseBasicParsing
						if($SearchResult.Length -and $SearchResult.Length -gt 0) 
						{
								#filter latest module
								$SearchResult = $SearchResult | Where-Object -FilterScript {
									return $_.title.'#text' -eq $moduleName
								} 
								$moduleName = $SearchResult.title.'#text' # get correct casing for the module name
								$PackageDetails = Invoke-RestMethod -Method Get -UseBasicParsing -Uri $SearchResult.id 
								$this.LatestPSGalleryVersion = $PackageDetails.entry.properties.version
						}
					}
				}
			}
			catch
			{
				$this.LatestPSGalleryVersion = "0.0.0.0";
			}
		}
		return $this.LatestPSGalleryVersion;

	}
}
