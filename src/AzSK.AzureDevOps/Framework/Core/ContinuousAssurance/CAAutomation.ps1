using namespace System.Management.Automation
Set-StrictMode -Version Latest 
class CAAutomation	#: AzCommandBase
{ 
	hidden [string] $SubscriptionId
    hidden [string] $Location
    hidden [string] $OrganizationToScan
    hidden [string] $PATToken
    hidden [string] $TimeStamp=(Get-Date -format "yyMMddHHmmss")
    hidden [string] $StorageName
    hidden [string] $AppServicePlanName = "ADOScannerFAPlan"
    hidden [string] $FuncAppName
    hidden [string] $AppInsightsName
    hidden [string] $KeyVaultName
    hidden [string] $ImageName = "azsktest01/adosecurityscan"
    hidden [string] $ScanTriggerTimeUTC = [System.DateTime]::UtcNow.AddMinutes(15)
    hidden [string] $ScanTriggerLocalTime = $(Get-Date).AddMinutes(15)
    hidden [string] $SecretName = "PATForADOScan"
    hidden [string] $StorageKind = "StorageV2"
    hidden [string] $StorageType = "Standard_LRS"
    hidden [string] $LAWName = "ADOScannerLAWS"
    hidden [bool] $CreateLaws 
    hidden [string] $ProjectNames 
    hidden [string] $ExtendedCommand 
    hidden [string] $LAWSsku = "Standard"
	hidden [array] $CreatedResources = @()
	hidden [string] $RGName
    hidden [string] $LAWSId
	hidden [string] $LAWSSharedKey
    hidden [string] $SetupComplete =$false
	
	
	CAAutomation(
	[string] $SubId, `
	[string] $Loc, `
	[string] $OrgName, `
	[string] $PAT, `
	[string] $ResourceGroupName, `
	[string] $LAWorkspaceId, `
	[string] $LAWorkspaceKey, `
	[string] $Proj, `
	[string] $ExtCmd, `
	[bool] $CreateLaws) #: Base($subscriptionId, $invocationContext)
    {
		$this.SubscriptionId = $SubId
		$this.Location = $Loc
		$this.OrganizationToScan = $OrgName
		$this.PATToken = $PAT
		$this.ProjectNames = $Proj
		$this.ExtendedCommand = $ExtCmd
		$this.StorageName = "adoscannersa"+$this.TimeStamp 
		$this.FuncAppName = "ADOScannerFA"+$this.TimeStamp 
		$this.KeyVaultName = "ADOScannerKV"+$this.TimeStamp 
		$this.AppInsightsName = $this.FuncAppName

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
				Write-Host "Log Analytics Workspace details are missing. Use -CreateWorkspace switch to create a new workspace while setting up CA. Setup will continue..." -ForegroundColor Yellow
			}
		}
		else
		{
			$this.LAWSId = $LAWorkspaceId
			$this.LAWSSharedKey = $LAWorkspaceKey
		}
	}

	InstallAzSKContinuousAssurance()
    {

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
			   Write-Host "No Azure login found. Azure login context is required to setup Continuous Assurance."
			   return;
			}
			else
			{
				if($Context.Subscription.SubscriptionId -ne $this.SubscriptionId)
				{
					$Context = set-azcontext -Subscription $this.SubscriptionId -Force | out-null
				}
				$Scope = "/subscriptions/"+$this.SubscriptionId
				$RoleAssignment = @((Get-AzRoleAssignment -Scope $Scope -SignInName $Context.Account.Id -IncludeClassicAdministrators ).RoleDefinitionName | where {$_ -eq "Owner" -or $_ -eq "Contributor" -or $_ -eq "CoAdministrator" -or $_ -match "ServiceAdministrator"} )
				if ($RoleAssignment.Count -eq 0)
				{
					Write-Host "Please make sure you have Owner or Contributor role on target subscription. If your permissions were elevated recently, please run the 'Disconnect-AzAccount' command to clear the Azure cache and try again."
					return;
				}
			}
	
			#Step 3: If RG does not exist then create new
			 if((Get-AzResourceGroup -Name $this.RGname -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0)
			 {
				$RG = @(New-AzResourceGroup -Name $this.RGname -Location $this.Location)
				if($RG.Count -eq 0) 
				{
					Write-Host "`r`nNew resource group '$this.RGname' creation failed" -ForegroundColor Red
				}
				else
				{
					Write-Host "`r`nNew resource group '$this.RGname' created" -ForegroundColor Green
				}
			 }
			 else
			 {
				Write-Host "`r`n'$this.RGname' resource group already exists. Skipping RG creation" -ForegroundColor Green
			 }
	
			Write-Host "`r`nCreating required resources in resource group '$this.RGname'..." -ForegroundColor Yellow
	
	
			#Step 4: Create app service plan "Elastic Premium"
			$AppServPlan = @(New-AzResource -ResourceName $this.AppServicePlanName -ResourceGroupName $this.RGname -ResourceType Microsoft.web/serverfarms -ApiVersion "2018-02-01" -Location $this.Location -Kind Elastic -Properties @{"reserved"=$true;} -Sku @{name= "EP1";tier = "ElasticPremium";size= "EP1";family="EP";capacity= 1} -Force)
			if($null -eq $AppServPlan) 
			{
				Write-Host "AppService plan '$this.AppServicePlanName' creation failed" -ForegroundColor Red
			}
			else
			{
				Write-Host "AppService plan '$this.AppServicePlanName' created" -ForegroundColor Green
				$this.CreatedResources += $AppServPlan.ResourceId
			}
	
	
			#Step 5: Create storage account
			$StorageAcc = @(New-AzStorageAccount -ResourceGroupName $this.RGname -Name $this.StorageName -Type $this.StorageType -Location $this.Location -Kind $this.StorageKind -EnableHttpsTrafficOnly $true -ErrorAction Stop)
			if($null -eq $StorageAcc) 
			{
				Write-Host "Storage account '$this.StorageName' creation failed" -ForegroundColor Red
			}
			else
			{
				Write-Host "Storage '$this.StorageName' created" -ForegroundColor Green
				$this.CreatedResources += $StorageAcc.Id
	
			}
	
			#Step 6: Create Function app
			$FuncApp = @(New-AzFunctionApp -DockerImageName $this.ImageName -SubscriptionId $this.SubscriptionId -Name $this.FuncAppName -ResourceGroupName $this.RGname -StorageAccountName $this.StorageName -IdentityType SystemAssigned -PlanName $this.AppServicePlanName) 
			if($null -eq $FuncApp) 
			{
				Write-Host "Function app '$this.FuncAppName' creation failed" -ForegroundColor Red
			}
			else
			{
				Write-Host "Function app '$this.FuncAppName' created" -ForegroundColor Green
				$this.CreatedResources += $FuncApp.Id
			}
			
			#Step 7a: Validate if AI got created
			$AppInsight = @(Get-AzResource -Name $this.AppInsightsName -ResourceType Microsoft.Insights/components)
			if($null -eq $AppInsight) 
			{
				Write-Host "Application Insight '$this.AppInsightsName' creation failed" -ForegroundColor Red
			}
			else
			{
				Write-Host "Application Insight '$this.AppInsightsName' created" -ForegroundColor Green
				$this.CreatedResources += $AppInsight.ResourceId
			}
	
			#Step 7b: Create LAW if applicable
			if ($this.CreateLaws -eq $true)
			{
				$LAWorkspace = @(New-AzOperationalInsightsWorkspace -Location $this.Location -Name $this.LAWName -Sku $this.LAWSsku -ResourceGroupName $this.RGname)
				if($LAWorkspace -eq 0) 
				{
					Write-Host "Log Analytics Workspace '$this.LAWName' creation failed" -ForegroundColor Red
				}
				else
				{
					$this.LAWSId = $LAWorkspace.CustomerId.Guid.ToString()
					$SharedKeys = Get-AzOperationalInsightsWorkspaceSharedKey -Name $this.LAWName -ResourceGroupName $this.RGname -WarningAction silentlycontinue
					$this.LAWSSHaredKey = $SharedKeys.PrimarySharedKey
					Write-Host "Log Analytics Workspace '$this.LAWName' created" -ForegroundColor Green
					$this.CreatedResources += $LAWorkspace.ResourceId
				}
			}
	
			#Step 8: Create keyvault
			$KeyVault = @(New-AzKeyVault -Name $this.KeyVaultName -ResourceGroupName $this.RGname -Location $this.Location)
			if($null -eq $KeyVault) 
			{
				Write-Host "KeyVault '$this.KeyVaultName' creation failed" -ForegroundColor Red
			}
			else
			{
				Write-Host "KeyVault '$this.KeyVaultName' created" -ForegroundColor Green
				$this.CreatedResources += $KeyVault.resourceid
			}
	
	
			#Step 9: Add PAT token secret to KeyVault
			$Secret = ConvertTo-SecureString -String $this.PATToken -AsPlainText -Force
			$CreatedSecret= @(Set-AzKeyVaultSecret -VaultName $this.KeyVaultName -Name $this.SecretName -SecretValue $Secret)
			if($null -eq $CreatedSecret.Count) 
			{
				Write-Host "Secret creation in KeyVault failed" -ForegroundColor Red
			}
			else
			{
				Write-Host "Secret created in KeyVault" -ForegroundColor Green
			}
	
	
			#Step 10: Get Identity details of function app to provide access on keyvault and storage
			$FuncApp = Set-AzWebApp -Name $this.FuncAppName -ResourceGroupName $this.RGname -AssignIdentity $true		
			$FuncAppIdentity= $FuncApp.Identity.PrincipalId 						
			$MSIAccessToKV = Set-AzKeyVaultAccessPolicy -VaultName $this.KeyVaultName -ResourceGroupName $this.RGname -PermissionsToSecrets get,list -PassThru -ObjectId $FuncAppIdentity
			$IsMSIAccess = $MSIAccessToKV.AccessPolicies | foreach { if ($_.ObjectId -match $FuncAppIdentity ) {return $true }}
			if($IsMSIAccess -eq $true) 
			{
				Write-Host "MSI access to keyvault provided" -ForegroundColor Green
			}
			else
			{
				Write-Host "MSI access to keyvault failed" -ForegroundColor Red
			}
	
			$MSIAccessToSA = New-AzRoleAssignment -ObjectId $FuncAppIdentity  -RoleDefinitionName "Contributor" -ResourceName $this.StorageName -ResourceGroupName $this.RGname -ResourceType Microsoft.Storage/storageAccounts
			if($MSIAccessToSA.Count -eq 0) 
			{
				Write-Host "MSI access to storage failed" -ForegroundColor Red
			}
			else
			{
				Write-Host "MSI access to storage provided" -ForegroundColor Green
			}
	
	
			#Step 11: Configure required env variables in function app for scan
			$uri = $CreatedSecret.Id
			$uri = $uri.Substring(0,$uri.LastIndexOf('/'))
	
			#Fetch existing app settings and append the required ones. This has to be done as appsettings get overwritten
			$WebApp = Get-AzWebApp -Name $this.FuncAppName -ResourceGroupName $this.RGname
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
	
			$updatedWebApp = @(Set-AzWebApp -Name $this.FuncAppName -ResourceGroupName $this.RGname -AppSettings $AppSettings)
			if($updatedWebApp.SiteConfig.AppSettings.Count -ne $AppSettings.Count) 
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
	
		}
		catch
		{
			Write-Host "ADO Scanner CA setup failed!" -ForegroundColor Red
			Write-Host $_
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
					}
				}
				else{
					Write-Host "No resource was created." -ForegroundColor Yellow
				}
			}
		}
	}	
}