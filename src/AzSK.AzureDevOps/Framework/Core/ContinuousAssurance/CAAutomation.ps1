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
    hidden [bool] $CreateLaws 
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
	[bool] $CreateLaws) : Base($subscriptionId, $invocationContext)
    {
		$this.SubscriptionId = $SubId
		$this.Location = $Loc
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
		$this.ImageName = $this.ControlSettings.DockerImage.ImageName
		
		if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) 
		{
			$this.RGName ="ADOScannerRG"
		}
		else{
			$this.RGName = $ResourceGroupName
		}
	
		if ([string]::IsNullOrWhiteSpace($LAWorkspaceId) -or [string]::IsNullOrWhiteSpace($LAWorkspaceKey) ) 
		{
			if ($CreateLaws -ne $true)
			{
				$this.messages = "Log Analytics Workspace details are missing. Use -CreateWorkspace switch to create a new workspace while setting up CA. Setup will continue...`r`n"
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
		[InvocationInfo] $invocationContext) : Base($subscriptionId, $invocationContext)
		{
			$this.SubscriptionId = $SubId
			$this.OrganizationToScan = $OrgName
			$this.PATToken = $PATToken
			$this.ProjectNames = $Proj
			$this.ExtendedCommand = $ExtCmd
			$this.SetupComplete = $false
			$this.ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");
			$this.ImageName = $this.ControlSettings.DockerImage.ImageName
			$this.LAWSId = $LAWorkspaceId
			$this.LAWSSharedKey = $LAWorkspaceKey

			if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) 
			{
				$this.RGName ="ADOScannerRG"
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
				Write-Host	"No active Azure login session found. Initiating login flow..."
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
					$Context = set-azcontext -Subscription $this.SubscriptionId -Force | out-null
				}
				$Scope = "/subscriptions/"+$this.SubscriptionId
				$RoleAssignment = @((Get-AzRoleAssignment -Scope $Scope -SignInName $Context.Account.Id -IncludeClassicAdministrators ).RoleDefinitionName | where {$_ -eq "Owner" -or $_ -eq "CoAdministrator" -or $_ -match "ServiceAdministrator"} )
				if ($RoleAssignment.Count -eq 0)
				{
					Write-Host "Please make sure you have Owner or Contributor role on target subscription. If your permissions were elevated recently, please run the 'Disconnect-AzAccount' command to clear the Azure cache and try again."
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

	[MessageData[]] InstallAzSKContinuousAssurance()
    {
		[MessageData[]] $messageData = @();
		$this.messages += ([Constants]::DoubleDashLine + "`r`nStarted setting up Continuous Assurance (CA)`r`n"+[Constants]::DoubleDashLine);
		Write-Host $this.messages
		try
		{
			$output = $this.ValidateUserPermissions();
			if($output -ne 'OK') # if there is some while validating permissions output will contain exception
			{
				Write-Host "Error validating permissions on the subscription" -ForegroundColor Red
				$messageData += $output
			}
			else 
			{
				#Step 1: If RG does not exist then create new
				if((Get-AzResourceGroup -Name $this.RGname -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0)
				{
					$RG = @(New-AzResourceGroup -Name $this.RGname -Location $this.Location)
					if($RG.Count -eq 0) 
					{
						Write-Host "New resource group '$($this.RGname)' creation failed" -ForegroundColor Red
					}
					else
					{
						Write-Host "New resource group '$($this.RGname)' created" -ForegroundColor Green
					}
				}
				else
				{
					Write-Host "$($this.RGname)' resource group already exists. Skipping RG creation" -ForegroundColor Green
				}
		
				Write-Host "Creating required resources in resource group '$($this.RGname)'..." -ForegroundColor Cyan
		
		
				#Step 2: Create app service plan "Elastic Premium"
				$AppServPlan = New-AzResource -ResourceName $this.AppServicePlanName -ResourceGroupName $this.RGname -ResourceType Microsoft.web/serverfarms -ApiVersion "2018-02-01" -Location $this.Location -Kind Elastic -Properties @{"reserved"=$true;} -Sku @{name= "EP1";tier = "ElasticPremium";size= "EP1";family="EP";capacity= 1} -Force
				if($null -eq $AppServPlan) 
				{
					Write-Host "AppService plan '$($this.AppServicePlanName)' creation failed" -ForegroundColor Red
				}
				else
				{
					Write-Host "AppService plan '$($this.AppServicePlanName)' created" -ForegroundColor Green
					$this.CreatedResources += $AppServPlan.ResourceId
				}
		
		
				#Step 3: Create storage account
				$StorageAcc = New-AzStorageAccount -ResourceGroupName $this.RGname -Name $this.StorageName -Type $this.StorageType -Location $this.Location -Kind $this.StorageKind -EnableHttpsTrafficOnly $true -ErrorAction Stop
				if($null -eq $StorageAcc) 
				{
					Write-Host "Storage account '$($this.StorageName)' creation failed" -ForegroundColor Red
				}
				else
				{
					Write-Host "Storage '$($this.StorageName)' created" -ForegroundColor Green
					$this.CreatedResources += $StorageAcc.Id
		
				}
		
				#Step 4: Create Function app
				$FuncApp = New-AzFunctionApp -DockerImageName $this.ImageName -SubscriptionId $this.SubscriptionId -Name $this.FuncAppName -ResourceGroupName $this.RGname -StorageAccountName $this.StorageName -IdentityType SystemAssigned -PlanName $this.AppServicePlanName
				if($null -eq $FuncApp) 
				{
					Write-Host "Function app '$($this.FuncAppName)' creation failed" -ForegroundColor Red
				}
				else
				{
					Write-Host "Function app '$($this.FuncAppName)' created" -ForegroundColor Green
					$this.CreatedResources += $FuncApp.Id
				}
				
				#Step 5: Validate if AI got created
				$AppInsight = Get-AzResource -Name $this.AppInsightsName -ResourceType Microsoft.Insights/components
				if($null -eq $AppInsight) 
				{
					Write-Host "Application Insight '$($this.AppInsightsName)' creation failed" -ForegroundColor Red
				}
				else
				{
					Write-Host "Application Insight '$($this.AppInsightsName)' created" -ForegroundColor Green
					$this.CreatedResources += $AppInsight.ResourceId
				}
		
				#Step 6: Create LAW if applicable
				if ($this.CreateLaws -eq $true)
				{
					$LAWorkspace = @(New-AzOperationalInsightsWorkspace -Location $this.Location -Name $this.LAWSName -Sku $this.LAWSsku -ResourceGroupName $this.RGname)
					if($LAWorkspace -eq 0) 
					{
						Write-Host "Log Analytics Workspace '$($this.LAWSName)' creation failed" -ForegroundColor Red
					}
					else
					{
						$this.LAWSId = $LAWorkspace.CustomerId.Guid.ToString()
						$SharedKeys = Get-AzOperationalInsightsWorkspaceSharedKey -Name $this.LAWSName -ResourceGroupName $this.RGname -WarningAction silentlycontinue
						$this.LAWSSHaredKey = $SharedKeys.PrimarySharedKey
						Write-Host "Log Analytics Workspace '$($this.LAWSName)' created" -ForegroundColor Green
						$this.CreatedResources += $LAWorkspace.ResourceId
					}
				}
		
				#Step 7: Create keyvault
				$KeyVault = New-AzKeyVault -Name $this.KeyVaultName -ResourceGroupName $this.RGname -Location $this.Location
				if($null -eq $KeyVault) 
				{
					Write-Host "KeyVault '$($this.KeyVaultName)' creation failed" -ForegroundColor Red
				}
				else
				{
					Write-Host "KeyVault '$($this.KeyVaultName)' created" -ForegroundColor Green
					$this.CreatedResources += $KeyVault.resourceid
				}
		
		
				#Step 8: Add PAT token secret to KeyVault
				#$Secret = ConvertTo-SecureString -String $this.PATToken -AsPlainText -Force
				$CreatedSecret = Set-AzKeyVaultSecret -VaultName $this.KeyVaultName -Name $this.SecretName -SecretValue $this.PATToken
				if($null -eq $CreatedSecret) 
				{
					Write-Host "Secret creation in KeyVault failed" -ForegroundColor Red
				}
				else
				{
					Write-Host "Secret created in KeyVault" -ForegroundColor Green
				}
		
		
				#Step 9: Get Identity details of function app to provide access on keyvault and storage
				$FuncApp = Get-AzWebApp -Name $this.FuncAppName -ResourceGroupName $this.RGname		
				$FuncAppIdentity= $FuncApp.Identity.PrincipalId 						
				$MSIAccessToKV = Set-AzKeyVaultAccessPolicy -VaultName $this.KeyVaultName -ResourceGroupName $this.RGname -PermissionsToSecrets get,list -PassThru -ObjectId $FuncAppIdentity
				$IsMSIAccess = $MSIAccessToKV.AccessPolicies | ForEach-Object { if ($_.ObjectId -match $FuncAppIdentity ) {return $true }}
				if($IsMSIAccess -eq $true) 
				{
					Write-Host "MSI access to keyvault provided" -ForegroundColor Green
				}
				else
				{
					Write-Host "MSI access to keyvault failed" -ForegroundColor Red
				}
		
				$MSIAccessToSA = New-AzRoleAssignment -ObjectId $FuncAppIdentity  -RoleDefinitionName "Contributor" -ResourceName $this.StorageName -ResourceGroupName $this.RGname -ResourceType Microsoft.Storage/storageAccounts
				if($null -eq $MSIAccessToSA) 
				{
					Write-Host "MSI access to storage failed" -ForegroundColor Red
				}
				else
				{
					Write-Host "MSI access to storage provided" -ForegroundColor Green
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
					Write-Host "App settings update failed" -ForegroundColor Red
				}
				else
				{
					Write-Host "App settings updated" -ForegroundColor Green
				}
		
		
				Write-Host "`r`nSetup Complete!" -ForegroundColor Green
				Restart-AzFunctionApp -name $this.FuncAppName -ResourceGroupName $this.RGname -SubscriptionId $this.SubscriptionId -Force
		
				Write-Host "Scan will begin at $($this.ScanTriggerLocalTime)" -ForegroundColor Green
				$this.SetupComplete = $true
				$messageData += [MessageData]::new("The following resources were created in resource group $($this.RGName) as part AzureDevOps of Continuous Assurance", ($this.CreatedResources| Out-String))
			}
		}
		catch
		{
			Write-Host "ADO Scanner CA setup failed!" -ForegroundColor Red
			Write-Host $_
			$messageData += $Error
		}
		finally
		{
			if ($this.SetupComplete -eq $false)
			{
				Write-Host "CA Setup could not be completed. Deleting created resources..." -ForegroundColor Yellow
				if ($this.CreatedResources.Count -ne 0)
				{
					Foreach ($resourceId in $this.CreatedResources)
					{
						Remove-AzResource -ResourceId $resourceId -Force
						$Index = $resourceId.LastIndexOf('/') + 1 ;
						$ResourceName = $resourceId.Substring($Index)

						Write-Host "Deleted resource: $($ResourceName)" -ForegroundColor Cyan
					}
				}
				else{
					Write-Host "No resource was created." -ForegroundColor Cyan
				}
			}
		}
		return $messageData
	}
	
	
	[MessageData[]] UpdateAzSKContinuousAssurance()
    {
		[MessageData[]] $messageData = @();
		$updateAppSettings = $false
		$updatePATToken = $false

		$this.messages += ([Constants]::DoubleDashLine + "`r`nStarted updating Continuous Assurance (CA)`r`n"+[Constants]::DoubleDashLine);
		Write-Host $this.messages
		try
		{
			$output = $this.ValidateUserPermissions();
			if($output -ne 'OK') # if there is some while validating permissions output will contain exception
			{
				Write-Host "Error validating permissions on the subscription" -ForegroundColor Red
				$messageData += $output
			}
			else 
			{

				#Validate if app settings update is required based on input paramaeters. 
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

				if ($updateAppSettings -eq $false -and $updatePATToken -eq $false)
				{
					Write-Host "Please use additonal paramaeters to perform update on LAWSId, LAWSSharedKey, OrganizationName, PATToken etc."
				}

				if ($updatePATToken -eq $true)
				{
					#Get KeyVault resource from RG
					$keyVaultResource = @((Get-AzResource -ResourceGroupName $this.RGname -ResourceType "Microsoft.KeyVault/vaults").Name | where {$_ -match $this.KVDefaultName})
					if($keyVaultResource.Count -eq 0)
					{
						Write-Host "ADOScanner KeyVault is not available in resource group '$($this.RGname)'. Update Failed!"
					}
					elseif ($keyVaultResource.Count -gt 1)
					{
						Write-Host "More than one ADOScanner KeyVault is available in resource group '$($this.RGname)'. Update Failed!"
					}
					else {
						#$Secret = ConvertTo-SecureString -String $this.PATToken -AsPlainText -Force
						$CreatedSecret = Set-AzKeyVaultSecret -VaultName $keyVaultResource[0] -Name $this.SecretName -SecretValue $this.PATToken
						if($null -eq $CreatedSecret) 
						{
							Write-Host "Unable to update PATToken. Please validate your permissions in access policy of the KeyVault '$($keyVaultResource[0])'" -ForegroundColor Red
						}
						else
						{
							Write-Host "Secret updated in '$($keyVaultResource[0])' KeyVault" -ForegroundColor Green
						}
					}
				}

				if ($updateAppSettings -eq $true)
				{
					#Get function app resource from RG to get existing app settings details
					$appServResource = @((Get-AzResource -ResourceGroupName $this.RGname -ResourceType "Microsoft.Web/Sites").Name | where {$_ -match $this.FuncAppDefaultName})
					if($appServResource.Count -eq 0)
					{
						Write-Host "ADOScanner FunctionApp is not available in resource group '$($this.RGname)'. Update Failed!"
					}
					elseif ($appServResource.Count -gt 1)
					{
						Write-Host "More than one ADOScanner app service is available in resource group '$($this.RGname)'. Update Failed!"
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

						if($null -ne $this.OrganizationToScan )
						{
							#If property already exists then update it else add new property
							if($null -ne $AppSettingsHT["OrgName"])
							{
								$AppSettingsHT["OrgName"] = $this.OrganizationToScan
							}
							else
							{
								$AppSettingsHT += @{"OrgName" = $this.OrganizationToScan}
							}
						}
						if($null -ne $this.LAWSId -and $null -ne $this.LAWSSharedKey )
						{
							#If property already exists then update it else add new property
							if($null -ne $AppSettingsHT["LAWSId"])
							{
								$AppSettingsHT["LAWSId"] = $this.LAWSId
							}
							else
							{
								$AppSettingsHT += @{"LAWSId" = $this.LAWSId}
							}
							if($null -ne $AppSettingsHT["LAWSSharedKey"])
							{
								$AppSettingsHT["LAWSSharedKey"] = $this.LAWSSharedKey
							}
							else
							{
								$AppSettingsHT += @{"LAWSSharedKey" = $this.LAWSSharedKey}
							}
						}
						if($null -ne $this.ExtendedCommand )
						{
							#If property already exists then update it else add new property
							if($null -ne $AppSettingsHT["ExtendedCommand"])
							{
								$AppSettingsHT["ExtendedCommand"] = $this.ExtendedCommand
							}
							else
							{
								$AppSettingsHT += @{"ExtendedCommand" = $this.ExtendedCommand}
							}
						}
						if($null -ne $this.ProjectNames )
						{
							#If property already exists then update it else add new property
							if($null -ne $AppSettingsHT["ProjectNames"])
							{
								$AppSettingsHT["ProjectNames"] = $this.ProjectNames
							}
							else
							{
								$AppSettingsHT += @{"ProjectNames" = $this.ProjectNames}
							}
						}

						$updatedWebApp = Update-AzFunctionAppSetting -Name $appServResource[0] -ResourceGroupName $this.RGname -AppSetting $AppSettingsHT -Force
						if($null -eq $updatedWebApp) 
						{
							Write-Host "App settings update failed in '$($appServResource[0])'" -ForegroundColor Red
						}
						else
						{
							Write-Host "App settings updated in '$($appServResource[0])'" -ForegroundColor Green
						}
					}
				}
			}
		}
		catch
		{
			Write-Host "ADO Scanner CA update failed!" -ForegroundColor Red
			Write-Host $_
			$messageData += $Error
		}
		return $messageData
	}
}