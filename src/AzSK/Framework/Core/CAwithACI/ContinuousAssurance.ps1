Set-StrictMode -Version Latest 
class ContinuousAssurance: AzCommandBase
{ 
    hidden [string] $ResourceGroup
    hidden [string] $ContainerName
    hidden [string] $FunctionAppName
    hidden [string] $FunctionAppPrefix
    hidden [string] $ContainerImage
    hidden [string] $CALocation
    hidden [string] $ResourceGroupNames
    hidden [string] $StorageAccountName
    hidden $EnvironmentVariables = @{}
    hidden [Hashtable] $reportStorageTags = @{}
    hidden [string] $LAWSId
    hidden [string] $LAWSSharedKey
    hidden [string] $AltLAWSId
    hidden [string] $AltLAWSSharedKey
    hidden [bool] $UpdateScheduler
    hidden [string] $CAScanOutputLogsContainerName = [Constants]::CAScanOutputLogsContainerName
    hidden [string] $ContainerMSI
    hidden [string] $FunctionAppMSI

	ContinuousAssurance(
	[string] $subscriptionId, `
	[InvocationInfo] $invocationContext, `
    [string] $ResourceGroupNames, `
    [string] $LAWSId, `
    [string] $LAWSSharedKey, `
    [string] $AltLAWSId, `
    [string] $AltLAWSSharedKey) : Base($subscriptionId, $invocationContext)
    {
        $this.PublishCustomMessage([Constants]::SingleDashLine+"`r`nWarning: You are running a preview command`r`n"+[Constants]::SingleDashLine, [MessageType]::Warning)
        $this.ResourceGroupNames = $ResourceGroupNames
        $this.CALocation = [UserSubscriptionDataHelper]::GetUserSubscriptionRGLocation()
        $this.ResourceGroup = [UserSubscriptionDataHelper]::GetUserSubscriptionRGName()
        $this.ContainerName = [UserSubscriptionDataHelper]::GetContainerName()
        $this.FunctionAppPrefix = "azskcasheduler" #Needs to change
        $this.ContainerImage = [Constants]::AzSKContainerImage
        # if(-not [string]::IsNullOrWhiteSpace($CALocation))
        # {
        #     $this.CALocation = $CALocation
        # }
        $this.SetEnvironmentVariables($ResourceGroupNames, $LAWSId, $LAWSSharedKey, $AltLAWSId, $AltLAWSSharedKey)
	  
    }

    ContinuousAssurance(
	[string] $subscriptionId, `
    [InvocationInfo] $invocationContext, `
    [string] $ResourceGroupNames, `
    [string] $LAWSId, `
    [string] $LAWSSharedKey, `
    [string] $AltLAWSId, `
    [string] $AltLAWSSharedKey, `
    [bool] $UpdateScheduler) : Base($subscriptionId, $invocationContext)
    {
        $this.PublishCustomMessage([Constants]::SingleDashLine+"`r`nWarning: You are running a preview command`r`n"+[Constants]::SingleDashLine, [MessageType]::Warning)
        $this.CALocation = [UserSubscriptionDataHelper]::GetUserSubscriptionRGLocation()
        if(-not [string]::IsNullOrWhiteSpace($ResourceGroupNames))
        {
            $this.ResourceGroupNames = $ResourceGroupNames
        }
        if(-not [string]::IsNullOrWhiteSpace($LAWSId))
        {
            $this.LAWSId = $LAWSId
        }
        if(-not [string]::IsNullOrWhiteSpace($LAWSSharedKey))
        {
            $this.LAWSSharedKey = $LAWSSharedKey
        }
        if(-not [string]::IsNullOrWhiteSpace($AltLAWSId))
        {
            $this.AltLAWSId = $AltLAWSId
        }
        if(-not [string]::IsNullOrWhiteSpace($AltLAWSSharedKey))
        {
            $this.AltLAWSSharedKey = $AltLAWSSharedKey
        }
        $this.ResourceGroup = [UserSubscriptionDataHelper]::GetUserSubscriptionRGName()
        $this.ContainerName = [UserSubscriptionDataHelper]::GetContainerName()
        $this.FunctionAppPrefix = "azskcasheduler"
        $this.ContainerImage = [Constants]::AzSKContainerImage
    }

    ContinuousAssurance(
	[string] $subscriptionId, `
    [InvocationInfo] $invocationContext) : Base($subscriptionId, $invocationContext)
    {
        $this.PublishCustomMessage([Constants]::SingleDashLine+"`r`nWarning: You are running a preview command`r`n"+[Constants]::SingleDashLine, [MessageType]::Warning)
        $this.CALocation = [UserSubscriptionDataHelper]::GetUserSubscriptionRGLocation()
        $this.ResourceGroup = [UserSubscriptionDataHelper]::GetUserSubscriptionRGName()
        $this.ContainerName = [UserSubscriptionDataHelper]::GetContainerName()
        $this.FunctionAppPrefix = "azskcasheduler"
        $this.ContainerImage = [Constants]::AzSKContainerImage
    }
    
    hidden [void] SetEnvironmentVariables([string] $ResourceGroupNames, [string] $LAWSId, [string] $LAWSSharedKey,[string] $AltLAWSId, [string] $AltLAWSSharedKey)
    {
        $this.EnvironmentVariables.Add('ResourceGroupNames', $ResourceGroupNames)
        $this.EnvironmentVariables.Add('SubscriptionId', $this.SubscriptionContext.SubscriptionId)
        $this.EnvironmentVariables.Add('ACIRG', $this.ResourceGroup)
        if(-not [string]::IsNullOrWhiteSpace($LAWSId) -and -not [string]::IsNullOrWhiteSpace($LAWSSharedKey))
        {
            $this.EnvironmentVariables.Add('LAWSId', $LAWSId)
            $this.EnvironmentVariables.Add('LAWSSharedKey', $LAWSSharedKey)
        }
        if(-not [string]::IsNullOrWhiteSpace($AltLAWSId) -and -not [string]::IsNullOrWhiteSpace($AltLAWSSharedKey))
        {
            $this.EnvironmentVariables.Add('AltLAWSId', $AltLAWSId)
            $this.EnvironmentVariables.Add('AltLAWSSharedKey', $AltLAWSSharedKey)
        }

    }

    hidden [void] CreteAzSKContainer()
    {
        #register resource provider if not registered
		[ResourceHelper]::RegisterResourceProviderIfNotRegistered("Microsoft.ContainerInstance")
        $AzSKContainer = New-AzContainerGroup -ResourceGroupName $this.ResourceGroup -Name $this.ContainerName  -Image $this.ContainerImage -AssignIdentity -RestartPolicy OnFailure `
        -EnvironmentVariable $this.EnvironmentVariables -Location $this.CALocation
        #Stop the container as it starts immediately after the creation
        Invoke-AzResourceAction -ResourceGroupName $this.ResourceGroup -ResourceName $this.ContainerName -Action Stop -ResourceType Microsoft.ContainerInstance/containerGroups -Force
        $this.ContainerMSI = $AzSKContainer.Identity.PrincipalId
    }
    # Can add more parameters if required
    hidden [void] UpdateAzSKContainer($ContainerVariables)
    {
        $this.EnvironmentVariables = $ContainerVariables
        if(-not [string]::IsNullOrWhiteSpace($this.ResourceGroupNames))
        {
            $this.EnvironmentVariables['ResourceGroupNames'] = $this.ResourceGroupNames
        }
        if(-not [string]::IsNullOrWhiteSpace($this.LAWSId))
        {
            $this.EnvironmentVariables['LAWSId'] = $this.LAWSId
        }
        if(-not [string]::IsNullOrWhiteSpace($this.LAWSSharedKey))
        {
            $this.EnvironmentVariables['LAWSSharedKey'] = $this.LAWSSharedKey
        }
        if(-not [string]::IsNullOrWhiteSpace($this.AltLAWSId))
        {
            $this.EnvironmentVariables['AltLAWSId'] = $this.AltLAWSId
        }
        if(-not [string]::IsNullOrWhiteSpace($this.AltLAWSSharedKey))
        {
            $this.EnvironmentVariables['AltLAWSSharedKey'] = $this.AltLAWSSharedKey
        }
        $AzSKContainer = New-AzContainerGroup -ResourceGroupName $this.ResourceGroup -Name $this.ContainerName  -Image $this.ContainerImage -AssignIdentity -RestartPolicy OnFailure `
        -EnvironmentVariable $this.EnvironmentVariables -Location $this.CALocation
        #Stop the container as it starts immediately after the creation
        Invoke-AzResourceAction -ResourceGroupName $this.ResourceGroup -ResourceName $this.ContainerName -Action Stop -ResourceType Microsoft.ContainerInstance/containerGroups -Force
        $this.ContainerMSI = $AzSKContainer.Identity.PrincipalId
    }

    hidden [bool] CheckRBACAccess($ObjectId, $Scope, $Role)
	{
		$RoleAssignments = Get-AzRoleAssignment -ObjectId $ObjectId -Scope $Scope -RoleDefinitionId $Role
		if(($RoleAssignments|Measure-Object).count -gt 0)
		{
			#$hasAccess = ($RoleAssignments | Where-Object {$_.scope -eq $Scope -and $_.RoleDefinitionId -eq $Role}).count -gt 0
			return $true	
        }
        return $false
	}

    hidden [void] SetRBACAccess($ObjectId, $Scope, $Role)
    {
        New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionId $Role -Scope $Scope
        Start-Sleep -Seconds 10
    }
    hidden [void] SetContainerMSIAccess()
    {
        #Reader access on Sub
        $hasSubAccess = $this.CheckRBACAccess($this.ContainerMSI, "/subscriptions/$($this.SubscriptionContext.SubscriptionId)", 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
        if(-not $hasSubAccess)
        {
            $this.SetRBACAccess($this.ContainerMSI, "/subscriptions/$($this.SubscriptionContext.SubscriptionId)", 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
        }
        #Contributor access on AzSKRG
        $hasRGAccess = $this.CheckRBACAccess($this.ContainerMSI, "/subscriptions/$($this.SubscriptionContext.SubscriptionId)/resourcegroups/$($this.ResourceGroup)", 'b24988ac-6180-42a0-ab88-20f7382dd24c')
        if(-not $hasRGAccess)
        {
            $this.SetRBACAccess($this.ContainerMSI, "/subscriptions/$($this.SubscriptionContext.SubscriptionId)/resourcegroups/$($this.ResourceGroup)", 'b24988ac-6180-42a0-ab88-20f7382dd24c')
        }
    }

    hidden [void] SetFunctionAppMSIAccess()
    {
        #Contributor access on AzSKRG
        $hasRGAccess = $this.CheckRBACAccess($this.FunctionAppMSI, "/subscriptions/$($this.SubscriptionContext.SubscriptionId)/resourcegroups/$($this.ResourceGroup)", 'b24988ac-6180-42a0-ab88-20f7382dd24c')
        if(-not $hasRGAccess)
        {
            $this.SetRBACAccess($this.FunctionAppMSI, "/subscriptions/$($this.SubscriptionContext.SubscriptionId)/resourcegroups/$($this.ResourceGroup)", 'b24988ac-6180-42a0-ab88-20f7382dd24c')
        }
    }

    hidden [PSObject] GetCAContainerInstance()
    {
          $ContainerObject = Get-AzContainerGroup -ResourceGroupName $this.ResourceGroup -Name $this.ContainerName -ErrorAction SilentlyContinue
          return $ContainerObject
    }

    hidden [PSObject] GetFnAppInstance()
    {
          $FunctionAppObject = Get-AzResource -ResourceGroupName $this.ResourceGroup -ResourceType "Microsoft.Web/sites" | Where-Object { $_.Name.StartsWith($this.FunctionAppPrefix)}
          return $FunctionAppObject
    }

    hidden [PSObject] GetFnAppResource()
    {
          $FnAppResource = Get-AzWebApp -ResourceGroupName $this.ResourceGroup -Name $this.FunctionAppName -ErrorAction SilentlyContinue
          return $FnAppResource
    }

    hidden [void] ResolveStorageCompliance($storageName,$ResourceId,$resourceGroup,$containerName)
	{
		$storageObject = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageName -ErrorAction Stop
	    $keys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageName 
	    $currentContext = New-AzStorageContext -StorageAccountName $storageName -StorageAccountKey $keys[0].Value -Protocol Https
	
		#Azure_Storage_AuthN_Dont_Allow_Anonymous
		$keys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageName		
		$storageContext = New-AzStorageContext -StorageAccountName $storageName -StorageAccountKey $keys[0].Value -Protocol Https
		$existingContainer = Get-AzStorageContainer -Name $containerName -Context $storageContext -ErrorAction SilentlyContinue
		if($existingContainer)
		{
			Set-AzStorageContainerAcl -Name  $containerName -Permission 'Off' -Context $currentContext 
		}
		$storageSku = [Constants]::NewStorageSku
	    Set-AzStorageAccount -Name $storageName  -ResourceGroupName $resourceGroup -SkuName $storageSku
	    
		#Azure_Storage_Audit_AuthN_Requests
	    $currentContext = $storageObject.Context
	    Set-AzStorageServiceLoggingProperty -ServiceType Blob -LoggingOperations All -Context $currentContext -RetentionDays 365 -PassThru
	    Set-AzStorageServiceMetricsProperty -MetricsType Hour -ServiceType Blob -Context $currentContext -MetricsLevel ServiceAndApi -RetentionDays 365 -PassThru
	    
		#Azure_Storage_DP_Encrypt_In_Transit
        Set-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageName -EnableHttpsTrafficOnly $true
        
        #Setting the TLSVersion to 1.2 and disabling public blob access
		$subid = $ResourceId.split("/")[2]
		$this.UpdateTLSandBlobAccessForAzSKStorage($subid,$resourceGroup,$storageName)
    }

    #TBD
    hidden [void] UpdateAzSKFunctionApp()
    {
        $storageConnectionStringformat = "DefaultEndpointsProtocol=https;AccountName=$($this.StorageAccountName);AccountKey={0};EndpointSuffix=core.windows.net";
        $keys = Get-AzStorageAccountKey -ResourceGroupName $this.ResourceGroup -Name $this.StorageAccountName
        $value = $keys[0].Value;
        $StorageAccountConnectionString = $storageConnectionStringformat -f $value;	
        $timeTrigger = [System.DateTime]::UtcNow.AddMinutes(15)
        $AppSettings = @{
            'AzureWebJobsStorage' = $StorageAccountConnectionString;
            'FUNCTIONS_EXTENSION_VERSION' = '~2';
            "FUNCTIONS_WORKER_RUNTIME" = "powershell";
            "schedule" = "0 $($timeTrigger.Minute) $($timeTrigger.Hour) * * *";
        }
        $functionAppObjet = $this.GetFnAppInstance()
        $functionAppResource = $this.GetFnAppResource()
        if($null -ne $functionAppResource)
		{
			if(($functionAppResource.SiteConfig.AppSettings | Measure-Object).Count -gt 0)
			{
				$appSettingsList = $functionAppResource.SiteConfig.AppSettings;
				ForEach ($item in $appSettingsList){
					$AppSettings[$item.Name] = $item.Value;
				}
			}
		}
        if(($functionAppObjet | Measure-Object).Count -le 0)
        {
            New-AzResource -ResourceType 'Microsoft.Web/Sites' -ResourceName $this.FunctionAppName -kind 'functionapp' -Location $this.CALocation -ResourceGroupName $this.ResourceGroup -Properties @{} -Force;
        }
        $AzSKFunctionApp = Set-AzWebApp -Name $this.FunctionAppName -ResourceGroupName $this.ResourceGroup -AppSettings $AppSettings -AssignIdentity $true -HttpsOnly $true								
        Start-Sleep -Seconds 10
        $this.FunctionAppMSI = $AzSKFunctionApp.Identity.PrincipalId
       
        $zipFilePath = Join-Path (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName -ChildPath "Configurations" | Join-Path -ChildPath "ContinuousAssurance" | Join-Path -ChildPath "FunctionApp.zip";
        $pub = $this.FunctionAppName + '/publishingcredentials';
        $pubCredResourceType = "Microsoft.Web/sites/config";
        $pubCreds = @();
        $pubCred= Invoke-AzResourceAction -ResourceGroupName $this.ResourceGroup -ResourceName $pub -ResourceType $pubCredResourceType -Action list -ApiVersion 2015-08-01 -Force;
        if(($pubCred | Measure-Object).Count -gt 0)
        {
            $pubCreds += $pubCred;
            $pubName = $pubCreds[0].Properties.PublishingUserName;
            $pubpwd = $pubCreds[0].Properties.PublishingPassword;
            $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $pubName,$pubpwd)))
            $apiUrl = "https://"+$($this.FunctionAppName)+".scm.azurewebsites.net/api/zipdeploy";  
            $this.PublishCustomMessage("Adding/updating scanner function on [$($this.FunctionAppName)] function app...")         
            Invoke-RestMethod -Uri $apiUrl -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method PUT -InFile $zipFilePath -ContentType "multipart/form-data";
        }
        else
        {
            $this.PublishCustomMessage("Not able to fetch publish credentials...");
        }
    }

    [void] InstallAzSKContinuousAssurancewithACI()
    {
        #Using a trick to exclude non CSEO users..To be removed
        if(-not [ConfigurationManager]::GetAzSKSettings().EnableAADAuthForOnlinePolicyStore)
        {
            $this.PublishCustomMessage("Container based CA is currently not available to your org ", [MessageType]::Error)
            return
        }
        #create AzSKRG resource group if not exists
        [ResourceGroupHelper]::CreateNewResourceGroupIfNotExists($this.ResourceGroup, $this.CALocation,$this.GetCurrentModuleVersion())
        #create storage account if not exists
        $ExistingStorage = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
        if(($ExistingStorage|Measure-Object).Count -gt 0)
        {
            $this.StorageAccountName = $ExistingStorage.Name
            $this.PublishCustomMessage("Preparing a storage account for storing reports from CA scans...`r`nFound existing AzSK storage account: ["+ $this.StorageAccountName +"]. This will be used to store reports from CA scans.")
        }
        else
        {
            #create new storage
            $this.StorageAccountName = ("azsk" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"))
            $this.PublishCustomMessage("Creating a storage account: ["+ $this.StorageAccountName +"] for storing reports from CA scans.")
            $newStorage = [StorageHelper]::NewAzskCompliantStorage($this.StorageAccountName, $this.ResourceGroup, $this.CALocation) 
            if(!$newStorage)
            {
                $this.cleanupFlag = $true
                throw ([SuppressedException]::new(($this.exceptionMsg + "Failed to create storage account."), [SuppressedExceptionType]::Generic))
            }  
            else
            {
                #apply tags
                $timestamp = $(get-date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
                $this.reportStorageTags += @{
                "CreationTime"=$timestamp;
                "LastModified"=$timestamp
                }
                Set-AzStorageAccount -ResourceGroupName $newStorage.ResourceGroupName -Name $newStorage.StorageAccountName -Tag $this.reportStorageTags -Force -ErrorAction SilentlyContinue
            } 
        }

        #update TLS and blob access settings for new storage
        $caStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
        if($null -ne $caStorageAccount)
        { 
            $this.UpdateTLSandBlobAccessForAzSKStorage($this.SubscriptionContext.SubscriptionId,$caStorageAccount.ResourceGroupName,$caStorageAccount.Name)
        }

        $this.EnvironmentVariables.Add('StorageAccountName', $this.StorageAccountName)
        $ContainerIntstance = $this.GetCAContainerInstance()
        if($ContainerIntstance)
        {
            $this.PublishCustomMessage("AzSK CA container instance [$($this.ContainerName)] already exists. Please delete it before running install command", [MessageType]::Error)
            return
        }
        $this.PublishCustomMessage("Creating Azure container instance: [" + $this.ContainerName + "]")
        $this.CreteAzSKContainer()
        $this.PublishCustomMessage("Configuring permissions for AzSK Container MSI...")
        $this.SetContainerMSIAccess()
        $FunctionAppInstance = $this.GetFnAppInstance()
        if($FunctionAppInstance)
        {
            $this.FunctionAppName = $FunctionAppInstance.Name
            $this.PublishCustomMessage("AzSK CA function app [$($this.FunctionAppName)] already exists. Please delete it before running install command", [MessageType]::Error)
            # TBD: delete ACI
            return
        }
        #Use class variable
        $this.FunctionAppName = "azskcasheduler" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
        $this.PublishCustomMessage("Creating Azure function app: [$($this.FunctionAppName)] ")
        $this.UpdateAzSKFunctionApp()
        $this.PublishCustomMessage("Configuring permissions for AzSK function app MSI...")
        $this.SetFunctionAppMSIAccess()
    }

    [void] UpdateAzSKContinuousAssurancewithACI()
    {
        #Using a trick to exclude non CSEO users..To be removed
        if(-not [ConfigurationManager]::GetAzSKSettings().EnableAADAuthForOnlinePolicyStore)
        {
            $this.PublishCustomMessage("Container based CA is currently not available to your org ", [MessageType]::Error)
            return
        }
        $ContainerIntstance = $this.GetCAContainerInstance()
        if(($ContainerIntstance|Measure-Object).Count -eq 0)
        {
            throw ([SuppressedException]::new(("Continuous Assurance(CA) is not configured in this subscription. Please install with required parameters."), [SuppressedExceptionType]::InvalidOperation))
        }
        #create storage account if not exists
        $ExistingStorage = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
        if(($ExistingStorage|Measure-Object).Count -gt 0)
        {
            $this.PublishCustomMessage("Found existing AzSK storage account: ["+ $ExistingStorage.Name +"]")
            $this.StorageAccountName = $ExistingStorage.Name
            #make storage compliant to azsk
            $this.ResolveStorageCompliance($ExistingStorage.Name, $ExistingStorage.ResourceId, $this.ResourceGroup,$this.CAScanOutputLogsContainerName)
        }
        else {
            #create default storage
            $newStorageName = ("azsk" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"))				
            $this.PublishCustomMessage("Creating Storage Account: [$newStorageName] for storing reports from CA scans.")
            $this.StorageAccountName = $newStorageName
            $newStorage = [StorageHelper]::NewAzskCompliantStorage($newStorageName, $this.ResourceGroup, $this.CALocation) 
            if(!$newStorage)
            {
                throw ([SuppressedException]::new(($this.exceptionMsg + "Failed to create storage account."), [SuppressedExceptionType]::Generic))
            } 
            else {
                #apply tags
                $timestamp = $(get-date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
                $this.reportStorageTags += @{
                "CreationTime"=$timestamp;
                "LastModified"=$timestamp
                }
                Set-AzStorageAccount -ResourceGroupName $newStorage.ResourceGroupName -Name $newStorage.StorageAccountName -Tag $this.reportStorageTags -Force -ErrorAction SilentlyContinue
            }

            #update TLS and blob access settings for new storage
            $caStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage()
            if($null -ne $caStorageAccount)
            { 
                $this.UpdateTLSandBlobAccessForAzSKStorage($this.SubscriptionContext.SubscriptionId,$caStorageAccount.ResourceGroupName,$caStorageAccount.Name)
            }

        }
        $this.EnvironmentVariables.Add('StorageAccountName', $this.StorageAccountName)
        $this.PublishCustomMessage("Updating Azure container instance: [" + $this.ContainerName + "]")
        $ContainerVariables = $ContainerIntstance.Containers[0].EnvironmentVariables
        $this.UpdateAzSKContainer($ContainerVariables)
        # To update the daily scan time
        if($this.UpdateScheduler)
        {
            $this.PublishCustomMessage("Updating CA scan scheduler time")
            $FunctionAppInstance = $this.GetFnAppInstance()
            if($FunctionAppInstance)
            {
                $this.FunctionAppName = $FunctionAppInstance.Name
            }
            else {
            $this.FunctionAppName = "azskcasheduler" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
            $this.PublishCustomMessage("AzSK CA function app is not present. Creating it", [MessageType]::Info)
            }
            #TBD: take time as i/p instead of current time
            $this.UpdateAzSKFunctionApp()
            $this.SetFunctionAppMSIAccess()
        }
    }

    [void] GetAzSKContinuousAssurancewithACI()
    {
        #Using a trick to exclude non CSEO users..To be removed
        if(-not [ConfigurationManager]::GetAzSKSettings().EnableAADAuthForOnlinePolicyStore)
        {
            $this.PublishCustomMessage("Container based CA is currently not available to your org ", [MessageType]::Error)
            return
        }
        $currentMessage = [MessageData]::new([Constants]::DoubleDashLine + "`r`nStarted validating your AzSK Continuous Assurance (CA) setup...`r`n"+[Constants]::DoubleDashLine);
        $this.PublishCustomMessage($currentMessage); 
        # validate container  
        $ContainerIntstance = $this.GetCAContainerInstance()
        if($ContainerIntstance)
        {
            $this.PublishCustomMessage("Found AzSK CA container instance [$($this.ContainerName)] with below configurations ", [MessageType]::Update)
            $ContainerConfig = @{}
            $ContainerConfig.Add('MSI', $ContainerIntstance.Identity.PrincipalId)
            $ContainerConfig.Add('LAWSId', $ContainerIntstance.Containers[0].EnvironmentVariables.LAWSId)
            $ContainerConfig.Add('LAWSSharedKey', $ContainerIntstance.Containers[0].EnvironmentVariables.LAWSSharedKey)
            $ContainerConfig = $ContainerConfig.GetEnumerator() | Format-Table -AutoSize -Wrap | Out-String
            $this.PublishCustomMessage($ContainerConfig, [MessageType]::Info)
            #TBD: Altvar, container health: restart count, errors etc....
        }
        else {
            $this.PublishCustomMessage("AzSK CA container instance [$($this.ContainerName)] is missing. Please run install command", [MessageType]::Error)
            return
        }
        $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info)
        # validate fn app
        $FunctionAppInstance = $this.GetFnAppInstance()
        if($FunctionAppInstance)
        {
            $this.FunctionAppName = $FunctionAppInstance.Name
            $this.PublishCustomMessage("Found AzSK CA function app [$($this.FunctionAppName)] ", [MessageType]::Update)
        }
        else {
            $this.PublishCustomMessage("AzSK CA function app [$($this.FunctionAppPrefix)].... is missing. Please run update command", [MessageType]::Error)
            return
        }
        $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info)
        # Validate MSI access
        $hasSubAccess = $this.CheckRBACAccess($ContainerIntstance.Identity.PrincipalId, "/subscriptions/$($this.SubscriptionContext.SubscriptionId)", 'acdd72a7-3385-48ef-bd42-f606fba81ae7') # Guid of reader role 
        $hasRGAccess = $this.CheckRBACAccess($ContainerIntstance.Identity.PrincipalId, "/subscriptions/$($this.SubscriptionContext.SubscriptionId)/resourcegroups/$($this.ResourceGroup)", 'b24988ac-6180-42a0-ab88-20f7382dd24c') # Guid of contributor role 
        if($hasSubAccess -and $hasRGAccess)
        {
            $this.PublishCustomMessage("AzSK CA container MSI [$($ContainerIntstance.Identity.PrincipalId)] has required permissions", [MessageType]::Update)
        }
        else {
            $this.PublishCustomMessage("AzSK CA container MSI [$($ContainerIntstance.Identity.PrincipalId)] doesn't have required permissions. Please run update command", [MessageType]::Error)
       }
       $hasRGAccess = $this.CheckRBACAccess($FunctionAppInstance.Identity.PrincipalId, "/subscriptions/$($this.SubscriptionContext.SubscriptionId)/resourcegroups/$($this.ResourceGroup)", 'b24988ac-6180-42a0-ab88-20f7382dd24c')
       if($hasRGAccess)
        {
            $this.PublishCustomMessage("AzSK CA function app MSI [$($FunctionAppInstance.Identity.PrincipalId)] has required permissions", [MessageType]::Update)
        }
        else {
            $this.PublishCustomMessage("AzSK CA function app MSI [$($FunctionAppInstance.Identity.PrincipalId)] doesn't have required permissions. Please run update command", [MessageType]::Error)
       }
       $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info)
       $reportsStorageAccount = [UserSubscriptionDataHelper]::GetUserSubscriptionStorage();
        if(($reportsStorageAccount|Measure-Object).Count -eq 1)
        {
            $this.PublishCustomMessage("AzSK reports storage account is correctly set up.", [MessageType]::Update)
        }
        else {
            $this.PublishCustomMessage("AzSK reports storage account does not exist.", [MessageType]::Error)
        }
    }

    [void] RemoveAzSKContinuousAssurancewithACI()
    {
        #Using a trick to exclude non CSEO users..To be removed
        if(-not [ConfigurationManager]::GetAzSKSettings().EnableAADAuthForOnlinePolicyStore)
        {
            $this.PublishCustomMessage("Container based CA is currently not available to your org ", [MessageType]::Error)
            return
        }
        $this.PublishCustomMessage("This command will delete resources in your subscription which were installed by AzSK Continuous Assurance using containers",[MessageType]::Warning);
        Remove-AzContainerGroup -ResourceGroupName $this.ResourceGroup -Name $this.ContainerName
        $this.PublishCustomMessage("Removed Container instance : [$($this.ContainerName)] from resource group: [$($this.ResourceGroup)]")
        $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Info)
        $FunctionAppInstance = $this.GetFnAppInstance()
		if($FunctionAppInstance)
        {
            $this.FunctionAppName = $FunctionAppInstance.Name
            Remove-AzWebApp -ResourceGroupName $this.ResourceGroup -Name $this.FunctionAppName -Force
            $this.PublishCustomMessage("Removed Function app : [$($this.FunctionAppName)] from resource group: [$($this.ResourceGroup)]")
        }
    }

    #function to update TLS version and public blob access of AzSK storage account
	[void] UpdateTLSandBlobAccessForAzSKStorage($subscriptionId,$resourceGroup,$storageName)
	{
        $body = $null;
        $APIVersion = $null;
		$controlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");
        $ResourceAppIdURI = [WebRequestHelper]::GetResourceManagerUrl()	
        if([Helpers]::CheckMember($ControlSettings, 'APIVersionForTLSandBlobUpdate'))
		{
			$APIVersion = $controlSettings.APIVersionForTLSandBlobUpdate
		}		
		$uri = $ResourceAppIdURI + "subscriptions/$($subscriptionId)/resourceGroups/$($resourceGroup)/providers/Microsoft.Storage/storageAccounts/$($storageName)?api-version=$APIVersion"
		if([Helpers]::CheckMember($ControlSettings, 'TLSandBlobAccessForAzSKStorage'))
		{
			$body = $controlSettings.TLSandBlobAccessForAzSKStorage
		}
		try
		{
			[WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Patch, $uri, $body);
		}
		catch
		{
			#eat exception
		}
	}
}