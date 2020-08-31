Set-StrictMode -Version Latest 
class CAAutomation : ADOSVTCommandBase
{ 
	hidden [string] $SubscriptionId
    hidden [string] $Location
    hidden [string] $OrganizationToScan
    hidden [System.Security.SecureString] $PATToken
    hidden [string] $TimeStamp
    hidden [string] $StorageName
	hidden [string] $AppServicePlanName = "ADOScannerFAPlan"
	hidden [string] $FuncAppDefaultName = "ADOScannerFA"
    hidden [string] $KVDefaultName = "ADOScannerKV"
    hidden [string] $FuncAppName
    hidden [string] $AppInsightsName
    hidden [string] $KeyVaultName
    hidden [string] $ImageName
    hidden [datetime] $ScanTriggerTimeUTC
    hidden [datetime] $ScanTriggerLocalTime
    hidden [string] $SecretName = "PATForADOScan"
    hidden [string] $StorageKind = "StorageV2"
    hidden [string] $StorageType = "Standard_LRS"
    hidden [string] $LAWSName = "ADOScannerLAWS"
    hidden [bool] $CreateLAWS 
    hidden [string] $ProjectNames 
    hidden [string] $ExtendedCommand 
    hidden [string] $LAWSsku = "Standard"
	hidden [string[]] $CreatedResources = @();
	hidden [string[]] $updatedAppSettings = @();
	hidden [string] $RGName
    hidden [string] $LAWSId
	hidden [string] $LAWSSharedKey
	hidden [bool] $SetupComplete
	hidden [string] $messages
	[PSObject] $ControlSettings;
	
	CAAutomation(
		[string] $SubId, `
		[string] $Loc, `
		[string] $OrgName, `
		[System.Security.SecureString] $PATToken, `
		[string] $ResourceGroupName, `
		[string] $LAWorkspaceId, `
		[string] $LAWorkspaceKey, `
		[string] $Proj, `
		[string] $ExtCmd, `
		[InvocationInfo] $invocationContext, `
		[bool] $CreateLAWS) : Base($OrgName, $invocationContext)
    {
		$this.SubscriptionId = $SubId
		$this.OrganizationToScan = $OrgName
		$this.PATToken = $PATToken
		$this.ProjectNames = $Proj
		$this.ExtendedCommand = $ExtCmd
		$this.TimeStamp = (Get-Date -format "yyMMddHHmmss")
		$this.StorageName = "adoscannersa"+$this.TimeStamp 
		$this.FuncAppName = $this.FuncAppDefaultName + $this.TimeStamp 
		$this.KeyVaultName = $this.KVDefaultName+$this.TimeStamp 
		$this.AppInsightsName = $this.FuncAppName
        $this.SetupComplete = $false
        $this.ScanTriggerTimeUTC = [System.DateTime]::UtcNow.AddMinutes(20)
		$this.ScanTriggerLocalTime = $(Get-Date).AddMinutes(20)
		$this.ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");
		$this.CreateLAWS = $CreateLAWS

		if (($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings, "DockerImage.ImageName")) 
		{
			$this.ImageName = $this.ControlSettings.DockerImage.ImageName
		}

		if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) 
		{
			$this.RGName = [Constants]::AzSKADORGName
		}
		else{
			$this.RGName = $ResourceGroupName
		}
		
		if ([string]::IsNullOrWhiteSpace($Loc)) 
		{
			$this.Location =[Constants]::AzSKADORGLocation
		}
		else
		{
			$this.Location = $Loc
		}
	
		if ([string]::IsNullOrWhiteSpace($LAWorkspaceId) -or [string]::IsNullOrWhiteSpace($LAWorkspaceKey) ) 
		{
			if ($this.CreateLAWS -ne $true)
			{
				$this.messages = "Log Analytics Workspace details are missing. Use -CreateWorkspace switch to create a new workspace while setting up CA. Setup will continue...`r`n"
			}
			else{
				$this.LAWSName += $this.TimeStamp
			}
		}
		else
		{
			$this.LAWSId = $LAWorkspaceId
			$this.LAWSSharedKey = $LAWorkspaceKey
		}
	}

	CAAutomation(
		[string] $SubId, `
		[string] $OrgName, `
		[System.Security.SecureString] $PATToken, `
		[string] $ResourceGroupName, `
		[string] $LAWorkspaceId, `
		[string] $LAWorkspaceKey, `
		[string] $Proj, `
		[string] $ExtCmd, `
		[InvocationInfo] $invocationContext) : Base($OrgName, $invocationContext)
		{
			$this.SubscriptionId = $SubId
			$this.OrganizationToScan = $OrgName
			$this.PATToken = $PATToken
			$this.ProjectNames = $Proj
			$this.ExtendedCommand = $ExtCmd
			$this.SetupComplete = $false
			$this.LAWSId = $LAWorkspaceId
			$this.LAWSSharedKey = $LAWorkspaceKey

			<#
			$this.ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");

			if (($null -ne $this.ControlSettings) -and [Helpers]::CheckMember($this.ControlSettings, "DockerImage.ImageName")) 
			{
				$this.ImageName = $this.ControlSettings.DockerImage.ImageName
			}
			#>

			if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) 
			{
				$this.RGName = [Constants]::AzSKADORGName
			}
			else{
				$this.RGName = $ResourceGroupName
			}
		}

	[string] ValidateUserPermissions()
	{
		$output ='';
		try
		{
			#Step 1: Get context. Connect to account if required
			$Context = @(Get-AzContext -ErrorAction SilentlyContinue )
			if ($Context.count -eq 0)  {
				$this.PublishCustomMessage("No active Azure login session found. Initiating login flow...", [MessageType]::Info);
				Connect-AzAccount -ErrorAction Stop
				$Context = @(Get-AzContext -ErrorAction SilentlyContinue)
			}

			#Step 2 : Check if Owner or Contributor role is available at subscription scope.
			if ($null -eq $Context)  {
				$output = "No Azure login found. Azure login context is required to setup Continuous Assurance."
			}
			else
			{
				if($Context.Subscription.SubscriptionId -ne $this.SubscriptionId)
				{
					$Context = set-azcontext -Subscription $this.SubscriptionId -Force  
				}
				$Scope = "/subscriptions/"+$this.SubscriptionId
				$RoleAssignment = @((Get-AzRoleAssignment -Scope $Scope -SignInName $Context.Account.Id -IncludeClassicAdministrators ).RoleDefinitionName | where {$_ -eq "Owner" -or $_ -eq "CoAdministrator" -or $_ -match "ServiceAdministrator"} )
				if ($RoleAssignment.Count -eq 0)
				{
					$this.PublishCustomMessage("Please make sure you have Owner role on target subscription. If your permissions were elevated recently, please run the 'Disconnect-AzAccount' command to clear the Azure cache and try again.", [MessageType]::Info);
				}
				$output = 'OK'
			}
		}
		catch{
			$output += $_;
			$this.messages += $Error
		}
		return $output
	}

	[MessageData[]] InstallAzSKADOContinuousAssurance()
    {
		[MessageData[]] $messageData = @();
		$this.messages += ([Constants]::DoubleDashLine + "`r`nStarted setting up Continuous Assurance (CA)`r`n"+[Constants]::DoubleDashLine);
		$this.PublishCustomMessage($this.messages, [MessageType]::Info);
		try
		{
			$output = $this.ValidateUserPermissions();
			if($output -ne 'OK') # if there is some while validating permissions output will contain exception
			{
				$this.PublishCustomMessage("Error validating permissions on the subscription", [MessageType]::Error);
				$messageData += [MessageData]::new($output)
			}
			else 
			{
				if([string]::IsNullOrWhiteSpace($this.ImageName))
				{
					$messageData += [MessageData]::new("If you are using customized org policy, please ensure DockerImageName is defined in your ControlSettings.json")
					$this.PublishCustomMessage($messageData.Message, [MessageType]::Error);
					return $messageData
				}
				#Step 1: If RG does not exist then create new
				if((Get-AzResourceGroup -Name $this.RGname -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0)
				{
					$RG = @(New-AzResourceGroup -Name $this.RGname -Location $this.Location)
					if($RG.Count -eq 0) 
					{
						$this.PublishCustomMessage("New resource group '$($this.RGname)' creation failed", [MessageType]::Error);
					}
					else
					{
						$this.PublishCustomMessage("New resource group '$($this.RGname)' created", [MessageType]::Update);
					}
				}
				else
				{
					$this.PublishCustomMessage("Resource group: [$($this.RGname)] already exists. Skipping RG creation.", [MessageType]::Update);
				}
		
				$this.PublishCustomMessage("Creating required resources in resource group '$($this.RGname)'....", [MessageType]::Info);
		
				#Step 2: Create app service plan "Elastic Premium"
				if ((($AppServPlan =Get-AzResource -ResourceGroupName $this.RGName -ResourceType 'Microsoft.web/serverfarms' -Name $this.AppServicePlanName) | Measure-Object).Count -eq 0)
				{
					$AppServPlan = New-AzResource -ResourceName $this.AppServicePlanName -ResourceGroupName $this.RGname -ResourceType Microsoft.web/serverfarms -ApiVersion "2018-02-01" -Location $this.Location -Kind Elastic -Properties @{"reserved"=$true;} -Sku @{name= "EP1";tier = "ElasticPremium";size= "EP1";family="EP";capacity= 1} -Force
					if($null -eq $AppServPlan) 
					{
						$this.PublishCustomMessage("AppService plan '$($this.AppServicePlanName)' creation failed", [MessageType]::Error);
					}
					else
					{
						$this.PublishCustomMessage("AppService plan '$($this.AppServicePlanName)' created", [MessageType]::Update);
						$this.CreatedResources += $AppServPlan.ResourceId
					}
				}
				else 
				{
					$this.PublishCustomMessage("AppService Plan: [$($this.AppServicePlanName)] already exists. Skipping creation.", [MessageType]::Update);
				}
		
				#Step 3: Create storage account
				$StorageAcc = New-AzStorageAccount -ResourceGroupName $this.RGname -Name $this.StorageName -Type $this.StorageType -Location $this.Location -Kind $this.StorageKind -EnableHttpsTrafficOnly $true -ErrorAction Stop
				if($null -eq $StorageAcc) 
				{
					$this.PublishCustomMessage("Storage account '$($this.StorageName)' creation failed", [MessageType]::Error);
				}
				else
				{
					$this.PublishCustomMessage("Storage '$($this.StorageName)' created", [MessageType]::Update);
					$this.CreatedResources += $StorageAcc.Id
		
				}
		
				#Step 4: Create Function app
				$FuncApp = New-AzFunctionApp -DockerImageName $this.ImageName -SubscriptionId $this.SubscriptionId -Name $this.FuncAppName -ResourceGroupName $this.RGname -StorageAccountName $this.StorageName -IdentityType SystemAssigned -PlanName $this.AppServicePlanName
				if($null -eq $FuncApp) 
				{
					$this.PublishCustomMessage("Function app '$($this.FuncAppName)' creation failed", [MessageType]::Error);
				}
				else
				{
					$this.PublishCustomMessage("Function app '$($this.FuncAppName)' created", [MessageType]::Update);
					$this.CreatedResources += $FuncApp.Id
				}
				
				#Step 5: Validate if AI got created
				$AppInsight = Get-AzResource -Name $this.AppInsightsName -ResourceType Microsoft.Insights/components
				if($null -eq $AppInsight) 
				{
					$this.PublishCustomMessage("Application Insights '$($this.AppInsightsName)' creation failed", [MessageType]::Error);
				}
				else
				{
					$this.PublishCustomMessage("Application Insights '$($this.AppInsightsName)' created", [MessageType]::Update);
					$this.CreatedResources += $AppInsight.ResourceId
				}
		
				#Step 6: Create LAW if applicable
				if ($this.CreateLAWS -eq $true)
				{
					$LAWorkspace = @(New-AzOperationalInsightsWorkspace -Location $this.Location -Name $this.LAWSName -Sku $this.LAWSsku -ResourceGroupName $this.RGname)
					if($LAWorkspace -eq 0) 
					{
						$this.PublishCustomMessage("Log Analytics Workspace '$($this.LAWSName)' creation failed", [MessageType]::Error);
					}
					else
					{
						$this.LAWSId = $LAWorkspace.CustomerId.Guid.ToString()
						$SharedKeys = Get-AzOperationalInsightsWorkspaceSharedKey -Name $this.LAWSName -ResourceGroupName $this.RGname -WarningAction silentlycontinue
						$this.LAWSSHaredKey = $SharedKeys.PrimarySharedKey
						$this.PublishCustomMessage("Log Analytics Workspace '$($this.LAWSName)' created", [MessageType]::Update);
						$this.CreatedResources += $LAWorkspace.ResourceId
					}
				}
		
				#Step 7: Create keyvault
				$KeyVault = New-AzKeyVault -Name $this.KeyVaultName -ResourceGroupName $this.RGname -Location $this.Location
				if($null -eq $KeyVault) 
				{
					$this.PublishCustomMessage("KeyVault '$($this.KeyVaultName)' creation failed", [MessageType]::Error);
				}
				else
				{
					$this.PublishCustomMessage("KeyVault '$($this.KeyVaultName)' created", [MessageType]::Update);
					$this.CreatedResources += $KeyVault.resourceid
				}
		
		
				#Step 8: Add PAT token secret to KeyVault
				#$Secret = ConvertTo-SecureString -String $this.PATToken -AsPlainText -Force
				$CreatedSecret = Set-AzKeyVaultSecret -VaultName $this.KeyVaultName -Name $this.SecretName -SecretValue $this.PATToken
				if($null -eq $CreatedSecret) 
				{
					$this.PublishCustomMessage("PAT Secret creation in KeyVault failed", [MessageType]::Error);
				}
				else
				{
					$this.PublishCustomMessage("PAT Secret created in KeyVault", [MessageType]::Update);
				}
		
		
				#Step 9: Get Identity details of function app to provide access on keyvault and storage
				$FuncApp = Get-AzWebApp -Name $this.FuncAppName -ResourceGroupName $this.RGname		
				$FuncAppIdentity= $FuncApp.Identity.PrincipalId 						
				$MSIAccessToKV = Set-AzKeyVaultAccessPolicy -VaultName $this.KeyVaultName -ResourceGroupName $this.RGname -PermissionsToSecrets get,list -PassThru -ObjectId $FuncAppIdentity
				$IsMSIAccess = $MSIAccessToKV.AccessPolicies | ForEach-Object { if ($_.ObjectId -match $FuncAppIdentity ) {return $true }}
				if($IsMSIAccess -eq $true) 
				{
					$this.PublishCustomMessage("MSI access to KeyVault provided", [MessageType]::Update);
				}
				else
				{
					$this.PublishCustomMessage("MSI access to KeyVault failed", [MessageType]::Error);
				}
		
				$MSIAccessToSA = New-AzRoleAssignment -ObjectId $FuncAppIdentity  -RoleDefinitionName "Contributor" -ResourceName $this.StorageName -ResourceGroupName $this.RGname -ResourceType Microsoft.Storage/storageAccounts
				if($null -eq $MSIAccessToSA) 
				{
					$this.PublishCustomMessage("MSI access to storage failed", [MessageType]::Error);
				}
				else
				{
					$this.PublishCustomMessage("MSI access to storage provided", [MessageType]::Update);
				}
		
		
				#Step 10: Configure required env variables in function app for scan
				$uri = $CreatedSecret.Id
				$uri = $uri.Substring(0,$uri.LastIndexOf('/'))
		
				#Turn on "Always ON" for function app and also fetch existing app settings and append the required ones. This has to be done as appsettings get overwritten
				$WebApp = Get-AzWebApp -Name $this.FuncAppName -ResourceGroupName $this.RGname #-AlwaysOn $true
				$ExistingAppSettings = $WebApp.SiteConfig.AppSettings 
		
				#convert existing app settings from list to hashtable
				$AppSettingsHT = @{}
				foreach ($Setting in $ExistingAppSettings) 
				{
					$AppSettingsHT["$($Setting.Name)"] = "$($Setting.value)"
				}
		
				$NewAppSettings = @{
								"ScheduleTriggerTime" = "0 $($this.ScanTriggerTimeUTC.Minute) $($this.ScanTriggerTimeUTC.Hour) * * *";
								"SubscriptionId" = $this.SubscriptionId;
								"LAWSId" = $this.LAWSId;
								"LAWSSharedKey" = $this.LAWSSharedKey;
								"OrgName" = $this.OrganizationToScan;
								"PATToken" = "@Microsoft.KeyVault(SecretUri=$uri)";
								"StorageRG" = $this.RGname;
								"ProjectNames" = $this.ProjectNames;
								"ExtendedCommand" = $this.ExtendedCommand;
								"StorageName" = $this.StorageName;
								}
				$AppSettings = $NewAppSettings + $AppSettingsHT 
		
				$updatedWebApp = Update-AzFunctionAppSetting -Name $this.FuncAppName -ResourceGroupName $this.RGname -AppSetting $AppSettings -Force
				if($updatedWebApp.Count -ne $AppSettings.Count) 
				{
					$this.PublishCustomMessage("App settings update failed", [MessageType]::Error);
				}
				else
				{
					$this.PublishCustomMessage("App settings updated", [MessageType]::Update);
				}
		
				$this.PublishCustomMessage("`r`nSetup Complete!", [MessageType]::Update);
				Restart-AzFunctionApp -name $this.FuncAppName -ResourceGroupName $this.RGname -SubscriptionId $this.SubscriptionId -Force
		
				$this.PublishCustomMessage("Scan will begin at $($this.ScanTriggerLocalTime)", [MessageType]::Update);
				$this.SetupComplete = $true
				$this.DoNotOpenOutputFolder = $true
				$messageData += [MessageData]::new("The following resources were created in resource group $($this.RGName) as part of AzSK.ADO Continuous Assurance", ($this.CreatedResources| Out-String))
			}
		}
		catch
		{
			$this.PublishCustomMessage("ADO Scanner CA setup failed!", [MessageType]::Error);
			$this.PublishCustomMessage($_, [MessageType]::Error);
			$messageData += [MessageData]::new($Error)
		}
		finally
		{
			if ($this.SetupComplete -eq $false)
			{
				$this.PublishCustomMessage("CA Setup could not be completed. Deleting created resources...", [MessageType]::Warning);
				if ($this.CreatedResources.Count -ne 0)
				{
					Foreach ($resourceId in $this.CreatedResources)
					{
						Remove-AzResource -ResourceId $resourceId -Force
						$Index = $resourceId.LastIndexOf('/') + 1 ;
						$ResourceName = $resourceId.Substring($Index)

						$this.PublishCustomMessage("Deleted resource: $($ResourceName)", [MessageType]::Info);
					}
				}
				else{
					$this.PublishCustomMessage("No resource was created.", [MessageType]::Info);
				}
			}
		}
		return $messageData
	}
	
	
	[MessageData[]] UpdateAzSKADOContinuousAssurance()
    {
		[MessageData[]] $messageData = @();
		$updateAppSettings = $false
		$updatePATToken = $false

		$this.messages += ([Constants]::DoubleDashLine + "`r`nStarted updating Continuous Assurance (CA)`r`n"+[Constants]::DoubleDashLine);
		$this.PublishCustomMessage($this.messages, [MessageType]::Info);
		try
		{
			$output = $this.ValidateUserPermissions();
			if($output -ne 'OK') # if there is some while validating permissions output will contain exception
			{
				$this.PublishCustomMessage("Error validating permissions on the subscription", [MessageType]::Error);
				$messageData += [MessageData]::new($output)
			}
			else 
			{

				#Step 1: Validate if app settings update is required based on input paramaeters. 
				$this.invocationContext.BoundParameters.GetEnumerator() | foreach-object {
					# If input param is other than below 3 then app settings update will be required
					if($_.Key -ne "SubscriptionId" -and $_.Key -ne "ResourceGroupName" -and $_.Key -ne "PATToken")
					{
						$updateAppSettings = $true
					}
					if($_.Key -eq "PATToken")
					{
						$updatePATToken = $true
					}
				}

				#Step 2: Validate if RG exists.
				if (-not [string]::IsNullOrEmpty($this.RGname))
                {
                     $RG = Get-AzResourceGroup -Name $this.RGname -ErrorAction SilentlyContinue
                     if ($null -eq $RG)
                     {
						$messageData += [MessageData]::new("Resource group '$($this.RGname)' not found. Please validate the resource group name." )
						$this.PublishCustomMessage($messageData.Message, [MessageType]::Error);
		                return $messageData
                     }
				}
				
				#Step 3: If only subid and/or RG name params are used then display below message
				if ($updateAppSettings -eq $false -and $updatePATToken -eq $false)
				{
					$this.PublishCustomMessage("Please use additonal parameters to perform update on LAWSId, LAWSSharedKey, OrganizationName, PATToken, ProjectNames, ExtendedCommand", [MessageType]::Info);
				}

				#Step 4: Update PATToken in KV (if applicable)
				if ($updatePATToken -eq $true)
				{
					#Get KeyVault resource from RG
					$keyVaultResource = @((Get-AzResource -ResourceGroupName $this.RGname -ResourceType "Microsoft.KeyVault/vaults").Name | where {$_ -match $this.KVDefaultName})
					if($keyVaultResource.Count -eq 0)
					{
						$this.PublishCustomMessage("ADOScanner KeyVault is not available in resource group '$($this.RGname)'. Update Failed!", [MessageType]::Error);
					}
					elseif ($keyVaultResource.Count -gt 1)
					{
						$this.PublishCustomMessage("More than one ADOScanner KeyVault is available in resource group '$($this.RGname)'. Update Failed!", [MessageType]::Error);
					}
					else {
						$CreatedSecret = Set-AzKeyVaultSecret -VaultName $keyVaultResource[0] -Name $this.SecretName -SecretValue $this.PATToken
						if($null -eq $CreatedSecret) 
						{
							$this.PublishCustomMessage("Unable to update PATToken. Please validate your permissions in access policy of the KeyVault '$($keyVaultResource[0])'", [MessageType]::Error);
						}
						else
						{
							$this.PublishCustomMessage("Secret updated in '$($keyVaultResource[0])' KeyVault", [MessageType]::Update);
						}
					}
				}

				#Step 5: Update Function app settings (if applicable)
				if ($updateAppSettings -eq $true)
				{
					#Get function app resource from RG to get existing app settings details
					$appServResource = @((Get-AzResource -ResourceGroupName $this.RGname -ResourceType "Microsoft.Web/Sites").Name | where {$_ -match $this.FuncAppDefaultName})
					if($appServResource.Count -eq 0)
					{
						$this.PublishCustomMessage("ADOScanner FunctionApp is not available in resource group '$($this.RGname)'. Update Failed!", [MessageType]::Error);
					}
					elseif ($appServResource.Count -gt 1)
					{
						$this.PublishCustomMessage("More than one ADOScanner app service is available in resource group '$($this.RGname)'. Update Failed!", [MessageType]::Error);
					}
					else {
						$WebApp = Get-AzWebApp -Name $appServResource[0] -ResourceGroupName $this.RGname
						$ExistingAppSettings = $WebApp.SiteConfig.AppSettings 
		
						#convert existing app settings from list to hashtable
						$AppSettingsHT = @{}
						foreach ($Setting in $ExistingAppSettings) 
						{
							$AppSettingsHT["$($Setting.Name)"] = "$($Setting.value)"
						}

						if(-not [string]::IsNullOrEmpty($this.OrganizationToScan))
						{
							$AppSettingsHT["OrgName"] = $this.OrganizationToScan
						}
						if(-not [string]::IsNullOrEmpty($this.LAWSId) -and -not [string]::IsNullOrEmpty($this.LAWSSharedKey))
						{
							$AppSettingsHT["LAWSId"] = $this.LAWSId
							$AppSettingsHT["LAWSSharedKey"] = $this.LAWSSharedKey
						}
						if(-not [string]::IsNullOrEmpty( $this.ExtendedCommand ))
						{
							$AppSettingsHT["ExtendedCommand"] = $this.ExtendedCommand
						}
						if(-not [string]::IsNullOrEmpty( $this.ProjectNames ))
						{
							$AppSettingsHT["ProjectNames"] = $this.ProjectNames
						}

						$updatedWebApp = Update-AzFunctionAppSetting -Name $appServResource[0] -ResourceGroupName $this.RGname -AppSetting $AppSettingsHT -Force
						if($null -eq $updatedWebApp) 
						{
							$this.PublishCustomMessage("App settings update failed in '$($appServResource[0])'", [MessageType]::Error);
						}
						else
						{
							$this.PublishCustomMessage("App settings updated in '$($appServResource[0])'", [MessageType]::Update);
						}
					}
				}
				$this.DoNotOpenOutputFolder = $true
			}
		}
		catch
		{
			$this.PublishCustomMessage("ADO Scanner CA update failed!", [MessageType]::Error);
			$this.PublishCustomMessage($_, [MessageType]::Error);
			$messageData += [MessageData]::new($Error)
		}
		return $messageData
	}
}