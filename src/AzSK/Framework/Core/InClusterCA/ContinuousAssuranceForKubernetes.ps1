class KubernetesClusterCA : AzCommandBase {

    [PSObject] $ResourceObject;
    [string]  $ResourceGroupName;
    [string]  $ResourceName;
    [string]  $LAWorkspaceId;
    [string]  $LASharedSecret;
    [string]  $ResourceType = "Microsoft.ContainerService/managedClusters";
    [string]  $nameSpace = "azsk-scanner"
    [string]  $serviceAccountName = "azsk-scanner-account"
    [string]  $clusterRoleName = "azsk-scanner-clusterrole"
    [string]  $configMapName = "azsk-config"
    [string]  $clusterRoleBindingName = "azsk-scanner-rolebinding"
    [string]  $cronJobName = "azsk-ca-job"
    [string]  $deploymentFileBaseUrl = ""
    [string]  $deploymentFileName =  "deploy_azsk_ca_job.yml"
    [string]  $configMapFileName =  "update_azsk_ca_job_configmap.yml"
    [string]  $runtimeAccountFileName = "update_azsk_ca_job_runtime.yml"
    [string]  $jobSpecificationsFileName = "update_azsk_ca_job_spec.yml"

    KubernetesClusterCA(
        [string] $subscriptionId, `
        [string] $ResourceGroupName, `
        [string] $ResourceName, `
        [InvocationInfo] $invocationContext) : Base($subscriptionId, $invocationContext)
        {
            if(-not [string]::IsNullOrWhiteSpace($ResourceGroupName))
            {
                $this.ResourceGroupName = $ResourceGroupName;
            }

            if(-not [string]::IsNullOrWhiteSpace($ResourceName))
            {
                $this.ResourceName = $ResourceName;
            }

            $this.CheckPrerequisites();
            $this.GetResourceObject();
            $this.SetKubernetesContext();
            $this.deploymentFileBaseUrl = [Constants]::AKSBaseConfigurationUrl
        }

        hidden [bool] CheckPrerequisites()
        {
            # This method verifies that if both Azure CLI and Kubernetes CLI are installed or not
            $IsPrerequisitesPresent = $false
            try{
                $azCliCmdOutput  = az --help --output json
            }catch{
                $azCliCmdOutput = $null
            }
            
            try{
                $aksCliCmdOuput = kubectl help
            }catch{
                $aksCliCmdOuput = $null
            }
            

            if($null -ne $azCliCmdOutput -and $null -ne $aksCliCmdOuput ){
                $IsPrerequisitesPresent = $true
            }else{
                if($null -eq $azCliCmdOutput){
                    $IsPrerequisitesPresent = $false
                    $this.PublishCustomMessage("Azure CLI is not presnet in machine, you need to install Azure CLI. To install, please refer: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest", [MessageType]::Warning)         
                }
                if($null -eq $aksCliCmdOuput){
                    $IsPrerequisitesPresent = $false
                    $this.PublishCustomMessage( "The Kubernetes command-line client 'kubectl' is not present in machine, it is required to connect to the Kubernetes cluster. To install, please run command: 'az aks install-cli' ", [MessageType]::Warning)
                }
            }
            # If any one of Azure CLI and Kubernetes CLI are not present in Users Machine, throw error
            if(-not  $IsPrerequisitesPresent){
                throw ([SuppressedException]::new(("Both Azure CLI and Kubernetes client 'kubectl' must be present in machine to perform any operation."), [SuppressedExceptionType]::InvalidOperation))
            }

            return $IsPrerequisitesPresent

        }
    
        hidden [PSObject] GetResourceObject()
        {
            if (-not $this.ResourceObject)
            {
                # Get App Service details
                $this.ResourceObject = Get-AzResource -Name $this.ResourceName  `
                                                                                    -ResourceType $this.ResourceType `
                                                                                    -ResourceGroupName $this.ResourceGroupName
                if(-not $this.ResourceObject)
                {
                    throw ([SuppressedException]::new(("Resource '$($this.ResourceName)' not found under Resource Group '$($this.ResourceGroupName)'"), [SuppressedExceptionType]::InvalidOperation))
                }

            }
            return $this.ResourceObject;
        }

        [Void] InstallKubernetesContinuousAssurance($LAWorkspaceId, $LASharedSecret)
        {
            # Get the App Insight Key
            $AppInsightKey = [RemoteReportHelper]::GetAIOrgTelemetryKey()
            if([string]::IsNullOrWhiteSpace($AppInsightKey))
            {
                $AppInsightKey = 'None'
            }else
            {
                $AppInsightKey = $AppInsightKey.Trim()
            }
            
            # Check if LAWorkspaceId and LASharedSecret param are passed by user 
            if(-not [string]::IsNullOrWhiteSpace($LAWorkspaceId) -and -not [string]::IsNullOrWhiteSpace($LASharedSecret))
            {
                $this.LAWorkspaceId = $LAWorkspaceId
                $this.LASharedSecret = $LASharedSecret
            }else{
               # Get values from local settings file 
                $this.GetLASettings()
            }
           
            # Check if LA ID and Keys are non-empty 

            if([string]::IsNullOrWhiteSpace($this.LAWorkspaceId))
            {
                $this.LAWorkspaceId = 'None'
            }else
            {
                $this.LAWorkspaceId = $this.LAWorkspaceId.Trim()
            }

            if([string]::IsNullOrWhiteSpace($this.LASharedSecret))
            {
                $this.LASharedSecret = 'None'
            }else
            {
                $this.LASharedSecret = $this.LASharedSecret.Trim()
            }

            # Prepare job schedule
            $Schedule = '"0 #h#/24 * * *"' 
            $jobHrs = ((Get-Date).ToUniversalTime().Hour + 1)%24
            $Schedule = $Schedule -replace '\#h\#', $jobHrs
            
            # Download deployment file from server and store it in temp location
            $deploymentFileUrl =  $this.deploymentFileBaseUrl + $this.deploymentFileName
            $InClusterCATempFolderPath = Join-Path $([Constants]::AzSKTempFolderPath) "InClusterCA";
            if(-not (Test-Path -Path $InClusterCATempFolderPath -PathType Container)){
                New-Item -ItemType Directory -Force -Path $InClusterCATempFolderPath
            }
            $filePath = Join-Path $($InClusterCATempFolderPath)  $($this.deploymentFileName)
            Invoke-RestMethod  -Method Get -Uri $deploymentFileUrl -OutFile $filePath 
            
            # Bootstrap basic properties like App Insight Key and job schedule in deployment file
            
            (Get-Content $filePath) -replace '\#AppInsightKey\#', $AppInsightKey | Set-Content $filePath -Force
            (Get-Content $filePath) -replace '\#Schedule\#', $Schedule | Set-Content $filePath -Force
            (Get-Content $filePath) -replace '\#RGName\#', $this.ResourceGroupName | Set-Content $filePath -Force
            (Get-Content $filePath) -replace '\#ResourceName\#', $this.ResourceName | Set-Content $filePath -Force
            (Get-Content $filePath) -replace '\#SubscriptionID\#', $this.SubscriptionContext.SubscriptionId | Set-Content $filePath -Force
            (Get-Content $filePath) -replace '\#LAWSId\#', $this.LAWorkspaceId | Set-Content $filePath -Force
            (Get-Content $filePath) -replace '\#LAWSSharedKey\#', $this.LASharedSecret | Set-Content $filePath -Force   

            # create ca scan job
            
            $this.PublishCustomMessage("Setting up AzSK Continuous Assurance in Kubernetes cluster...", [MessageType]::Warning)
        
            kubectl apply -f $filePath
            
            # Check if job created successfully
            
            $jobName = kubectl get cronjob $this.cronJobName --namespace $this.nameSpace -o jsonpath='{.metadata.name}' 
            if($null -ne $jobName)
            {
                $this.PublishCustomMessage("AzSK Continuous Assurance setup completed.", [MessageType]::Update)
                $this.PublishCustomMessage("Your cluster will be scanned periodically by AzSK CA.", [MessageType]::Warning)
                $this.PublishCustomMessage("The first CA scan job will be triggered within next 60 mins. You can check control evaluation results (job logs of 'azsk-ca-job') after that.", [MessageType]::Warning)
                $this.PublishCustomMessage("All security control evaluation results will also be sent to App Insight if an instrumentation key was provided during setup above.", [MessageType]::Warning)
                $this.PublishCustomMessage("For more info, please see docs: https://aka.ms/devopskit/inclusterca", [MessageType]::Warning)
            }else
            {
                $this.PublishCustomMessage("AzSK Continuous Assurance setup could not be completed. Please check error logs above for next steps." , [MessageType]::Error)
            }
            
        }
        
        [Void] SetKubernetesContext()
        {
            # Try to read existing context present in local
            try
            {
                $contexts = kubectl config view -o jsonpath='{.contexts[*].name}'
                $contextList = $contexts.Split("")
                Write-Host "Found the following cluster contexts in your local setup:" -ForegroundColor "Yellow"
                $contextList | ForEach-Object {
                    Write-Host $_
                        }
                $choice = Read-Host -Prompt 'To use one of the contexts above enter "Y". To use/create a new context enter "N"'
                if($choice -eq "Y")
                {
                    $contextName = Read-Host -Prompt "Enter the name of the context for setting up CA"
                    kubectl config use-context $contextName
                }
            }
            catch
            {
                # If any error occur while reading existing context, try to fetch new credentials and set context
                $choice = "N"
            }
            
            if($choice -ne "Y")
            {
                # Login

                az login *> $null
                
                # Set Subscription Context 
            
                az account set --subscription $this.SubscriptionContext.SubscriptionId

                # Fetch credentails of the cluster in which ca scan need to be setup

                az aks get-credentials --resource-group $this.ResourceGroupName --name $this.ResourceName
            }
        
        }
        
        [void] GetLASettings() {
            # Get LA settings if not passed
            [LogAnalyticsHelper]::SetLAWSDetails()
            $settings = [ConfigurationManager]::GetAzSKSettings()
            $this.LAWorkspaceId = $settings.LAWSId
            $this.LASharedSecret = $settings.LAWSSharedKey
        }

        [Void] RemoveKubernetesContinuousAssurance($DownloadJobLogs, $Force)
        {

            $deploymentFileUrl =  $this.deploymentFileBaseUrl + $this.deploymentFileName
            
            $choice = "N"
            if(-not $Force){
                $choice = Read-Host -Prompt 'This action will remove AzSK Continuous Assurance from cluster. Do you want to continue "Y/N"'
            }
            else{
                $choice = "Y"
            }
            if($choice -eq "Y"){
            
                # download all logs to local before deleting job
            
                if($DownloadJobLogs -eq "Yes"){
                    $response = kubectl get pods --namespace $this.nameSpace -o json
                    if($null -ne $response){
                        $allJObPods = $response | ConvertFrom-Json | Select-Object -ExpandProperty items
                        $jobPodsCount =    ($allJObPods | Measure-Object).Count
                        if($jobPodsCount -gt 0){
                            $moduleName = $this.GetModuleName();
                            $this.PublishCustomMessage("Downloading existing job's log to local machine..." , [MessageType]::Warning)
                            $baseFolder = Join-Path $([Constants]::AzSKAppFolderPath) "Logs" | Join-Path -ChildPath "ClusterScans\Kubernetes"| Join-Path -ChildPath $($this.SubscriptionContext.SubscriptionId )| Join-Path -ChildPath $($this.ResourceGroupName)| Join-Path -ChildPath $($this.ResourceName)
                            If(!(test-path $baseFolder))
                            {
                                New-Item -ItemType Directory -Force -Path $baseFolder | Out-Null
                            }
                            $allJObPods | ForEach-Object {
                            $jobPodName = $_.metadata.name
                            $jobTimeStamp = $_.metadata.creationTimestamp
                            $dateTime = $jobTimeStamp.split("T")
                            $date = $dateTime[0]
                            $time = $dateTime[1]
                            $fileName = $date.Replace("-","")+"_"+ $time.Replace(":","") + ".txt"
                            $fileName = Join-Path $baseFolder $fileName
                            Kubectl logs $jobPodName --namespace $this.nameSpace| Out-File $fileName -Force
                            }
                            $this.PublishCustomMessage("All previous job logs have been exported to: $($baseFolder)" , [MessageType]::Update)
                        }else{
                            $this.PublishCustomMessage("No previous job's log found." , [MessageType]::Warning)
                        }
                    }else{
                        $this.PublishCustomMessage("Some error occurred while fetching previous job logs." , [MessageType]::Error)
                        $choice = Read-Host -Prompt 'Do you want to remove AzSK Continuous Assurance from cluster without downloading previous logs "Y/N"'
                        if($choice -ne "Y"){
                            return;
                        }
                    }

                }
                else
                {
                    $this.PublishCustomMessage("You have choosen not to download previous logs." , [MessageType]::Warning)
                }
            
                $this.PublishCustomMessage("Removing AzSK Continuous Assurance from cluster..."  , [MessageType]::Warning)
            
                $response = kubectl delete -f $deploymentFileUrl

                if($null -ne $response){
                    $this.PublishCustomMessage("Successfully removed AzSK Continuous Assurance from cluster."  , [MessageType]::Update)
                }else{
                    $this.PublishCustomMessage("Some error occurred while removing AzSK Continuous Assurance from cluster." , [MessageType]::Error)
                }
            
            }
            
        }
        
        [Void] GetKubernetesContinuousAssurance()
        {
            $this.PublishCustomMessage("`nCheck 01: Presence of required configuration settings.",[MessageType]::Info)
            $configJson = kubectl get configmaps $this.configMapName --namespace $this.nameSpace -o json
            if($null -ne $configJson){
                $configJson = $configJson| ConvertFrom-Json | Select-Object data
                $configMaps = $configJson.data
                $presentConfig = $null
                if($null -eq $configMaps){     
                    $this.PublishCustomMessage("`nConfiguration settings for your cluster are missing.",[MessageType]::Error)
                }else{
                        $presentConfig = @{
                        "AppInsightKey    " = $configMaps.APP_INSIGHT_KEY
                        "SubscriptionId   " = $configMaps.SUBSCRIPTION_ID
                        "ResourceName     " = $configMaps.RESOURCE_NAME
                        "ResourceGroupName" = $configMaps.RG_NAME
                        }
                        $this.PublishCustomMessage("Configuration settings for your cluster are as follows:")
                        foreach($key in $presentConfig.keys)
                        {
                            Write-Host "$($key) : $($presentConfig.Item($key))" -ForegroundColor Yellow
                        }
                }
            
                if($null -eq $configMaps -or $null -eq $configMaps.APP_INSIGHT_KEY){
                    $this.PublishCustomMessage("`nApplication Inight key is not present. Scan logs will not be sent to telelmetry.",[MessageType]::Warning)
                }else{
                    $this.PublishCustomMessage("`nScan logs will be sent to Application Insight: $($configMaps.APP_INSIGHT_KEY)",[MessageType]::Update)
                }

                if($null -eq $configMaps -or $null -eq $configMaps.LA_WS_ID -or $null -eq $configMaps.LA_WS_SHAREDKEY){
                    $this.PublishCustomMessage("`nLA Workspace details are not present. Scan logs will not be sent to LA workspace.",[MessageType]::Warning)
                }else{
                    $this.PublishCustomMessage("`nScan logs will be sent to LA workspace: $($configMaps.LA_WS_ID)",[MessageType]::Update)
                }

            }else{
                $this.PublishCustomMessage("Unable to fetch Cluster's Configuration settings.",[MessageType]::Error)
            }

        
            $this.PublishCustomMessage("`nCheck 02: Validate runtime permissions to scan cluster.",[MessageType]::Info)
            $isRuntimeAccountValid = $true
            $svcAccountJson = kubectl get ServiceAccount $this.serviceAccountName --namespace $this.nameSpace -o json
            if($null -ne $svcAccountJson){
                $svcAccountJson = $svcAccountJson | ConvertFrom-Json | Select-Object metadata
                $svcAccountUID = $svcAccountJson.metadata.uid
                if($null -eq $svcAccountUID){
                    $this.PublishCustomMessage("Service account is not present.",[MessageType]::Error)
                    $isRuntimeAccountValid = $false
                }
            }else{
                $this.PublishCustomMessage("Unable to fetch Service account details.",[MessageType]::Error)
                $isRuntimeAccountValid = $false
            }
         
        
            $requiredApiGroups = "*"
            $requiredResources = @("pods","deployments","nodes","serviceaccounts","configmaps","clusterrolebindings")
            $requiredVerbs = @("get","watch","list")
        
            $clusterRoleJson = kubectl get ClusterRole $this.clusterRoleName --namespace $this.nameSpace -o json
            if($null -ne $clusterRoleJson){
                $clusterRoleJson = $clusterRoleJson | ConvertFrom-Json | Select-Object rules
                $clusterRoleRules = $clusterRoleJson.rules
            
                if(Compare-Object $clusterRoleRules.resources $requiredResources){
                    $this.PublishCustomMessage("Required resources permission is not correctly configured.",[MessageType]::Error)
                    $isRuntimeAccountValid = $false
                }
                if(Compare-Object $clusterRoleRules.verbs  $requiredVerbs){
                    $this.PublishCustomMessage("Required verbs permission is not correctly configured.",[MessageType]::Error)
                    $isRuntimeAccountValid = $false
                }
                if(Compare-Object $clusterRoleRules.apiGroups  $requiredApiGroups){
                    $this.PublishCustomMessage("Required api groups permission is not correctly configured.",[MessageType]::Error)
                    $isRuntimeAccountValid = $false
                }
            }else{
                $this.PublishCustomMessage("Unable to fetch Cluster role details.",[MessageType]::Error)
                $isRuntimeAccountValid = $false
            }

        
            $roleBindingJson = kubectl get ClusterRoleBinding $this.clusterRoleBindingName --namespace $this.nameSpace -o json
            if($null -ne  $roleBindingJson){
                $roleBindingJson  = $roleBindingJson  | ConvertFrom-Json | Select-Object roleRef, subjects
                $roleRef = $roleBindingJson.roleRef
                $subjects = $roleBindingJson.subjects
            
                if($roleRef.kind -ne "ClusterRole" -or $roleRef.name -ne $this.clusterRoleName ){
                    $this.PublishCustomMessage("Required Cluster role binding is not properly configured. ",[MessageType]::Error)
                    $isRuntimeAccountValid = $false
                }
            
                if($subjects.kind -ne "ServiceAccount" -or $subjects.name -ne $this.serviceAccountName){
                    $this.PublishCustomMessage("Required Cluster role binding is not properly configured. ",[MessageType]::Error)
                    $isRuntimeAccountValid = $false
                }
            }else{
                $this.PublishCustomMessage("Unable to fetch Cluster role details.",[MessageType]::Error)
                $isRuntimeAccountValid = $false
            }

        
            if($isRuntimeAccountValid){
                $this.PublishCustomMessage("Required runtime account for scanning cluster is properly configured.", [MessageType]::Update)
            }else{
                $this.PublishCustomMessage("Required runtime account for scanning cluster is not properly configured.",[MessageType]::Error)
            }
        
            $this.PublishCustomMessage("`ncheck 03: Check if latest image is used.",[MessageType]::Info)
            $controlSettings = $this.LoadServerConfigFile("ControlSettings.json");
            $requiredImagePath = $controlSettings.InClusterCA.AKS.RequiredImagePath
            $reuiredImageTag = $controlSettings.InClusterCA.AKS.RequiredImageTag
            $requiredImage = $requiredImagePath + ":"+ $reuiredImageTag
            $cronJobJson = kubectl get CronJob $this.cronJobName --namespace $this.nameSpace -o json | ConvertFrom-Json
        
            if($null -ne $cronJobJson){
                $jobContainer = $cronJobJson.spec.jobTemplate.spec.template.spec.containers[0]
        
                # Get image 
                if($jobContainer.image -ne $requiredImage)
                {
                    $this.PublishCustomMessage("Job is not running with latest image.",[MessageType]::Error)
                    
                }else{
                    $this.PublishCustomMessage("Job is running with latest image." , [MessageType]::Update)
                }
            }else{
                $this.PublishCustomMessage("AzSK CA job is not present in cluster.",[MessageType]::Error)
                # return if job not found, because other check depends on CA job specification
                return
            }
        
            $this.PublishCustomMessage("`nCheck 04: Job scan interval.",[MessageType]::Info)
            # Get last job, schedule and logs retention 
            $jobSpec = $cronJobJson.spec
            $jobSchedule = $jobSpec.schedule
            if(-not [string]::IsNullOrWhiteSpace($jobSchedule)){
            $startIndex = $jobSchedule.IndexOf("/")
            $lastIndex = $jobSchedule.IndexOf("*")
            $jobSchedule = $jobSchedule.Substring($startIndex+1, $lastIndex - $startIndex-1)
        
            }else{
                $jobSchedule = "Not Found"
            }
            $this.PublishCustomMessage("Current scan interval for job is:  $($jobSchedule)" , [MessageType]::Update)
            
            $this.PublishCustomMessage("`nCheck 05: Job's recent schdeule.",[MessageType]::Info)
            $lastScheduleTime = "NA"
            if([Helpers]::CheckMember($cronJobJson,"status.lastScheduleTime")){
                $lastScheduleTime = $cronJobJson.status.lastScheduleTime
            }
            $this.PublishCustomMessage("Job's last scheduled time: $($lastScheduleTime)"  , [MessageType]::Update)
            
            $this.PublishCustomMessage("`nCheck 06: Log retention.",[MessageType]::Info)
            $this.PublishCustomMessage("Log retention period: $($jobSpec.successfulJobsHistoryLimit)" , [MessageType]::Update)
        }
        
        [Void] UpdateKubernetesContinuousAssurance($AppInsightKey, $LAWorkspaceId, $LASharedSecret, $FixRuntimeAccount, $LogRetentionInDays,  $ScanIntervalInHours, $ImageTag)
        {
            $updateConfigDetails = -not ( [String]::IsNullOrEmpty($LAWorkspaceId) -and [String]::IsNullOrEmpty($AppInsightKey) -and [String]::IsNullOrEmpty($LASharedSecret))
        
            if($updateConfigDetails){
            
                $configJson = kubectl get configmaps $this.configMapName --namespace $this.nameSpace -o json
                if($null -ne $configJson){
                    $configJson = $configJson| ConvertFrom-Json | Select-Object data
                    $configMaps = $configJson.data
                    
                    if(-not [String]::IsNullOrEmpty($AppInsightKey)){
                        $newAppInsightKey = $AppInsightKey
                    }elseif ($null -ne $configMaps -and $null -ne $configMaps.APP_INSIGHT_KEY) {
                        $newAppInsightKey =   $configMaps.APP_INSIGHT_KEY
                    }
                    else{        
                        $newAppInsightKey = 'None'
                    }
                    
                    if(-not [String]::IsNullOrEmpty($LAWorkspaceId)){
                        $newLAWSId = $LAWorkspaceId
                    }elseif ($null -ne $configMaps -and $null -ne $configMaps.LA_WS_ID) {
                        $newLAWSId =   $configMaps.LA_WS_ID
                    }
                    else{        
                        $newLAWSId = 'None'
                    }

                    if(-not [String]::IsNullOrEmpty($LASharedSecret)){
                        $newLAWSKey = $LAWorkspaceId
                    }elseif ($null -ne $configMaps -and $null -ne $configMaps.LA_WS_SHAREDKEY) {
                        $newLAWSKey =   $configMaps.LA_WS_SHAREDKEY
                    }
                    else{        
                        $newLAWSKey = 'None'
                    }

                    # Download deployment file from server and store it in temp location
                    $deploymentFileUrl =  $this.deploymentFileBaseUrl +  $this.configMapFileName
                    $InClusterCATempFolderPath = Join-Path $([Constants]::AzSKTempFolderPath) "InClusterCA";
                    if(-not (Test-Path -Path $InClusterCATempFolderPath -PathType Container)){
                        New-Item -ItemType Directory -Force -Path $InClusterCATempFolderPath
                    }

                    $filePath = Join-Path $($InClusterCATempFolderPath) $this.configMapFileName
                    Invoke-RestMethod  -Method Get -Uri $deploymentFileUrl -OutFile $filePath 
                    (Get-Content $filePath) -replace '\#AppInsightKey\#', $newAppInsightKey | Set-Content $filePath -Force
                    (Get-Content $filePath) -replace '\#RGName\#', $this.ResourceGroupName | Set-Content $filePath -Force
                    (Get-Content $filePath) -replace '\#ResourceName\#', $this.ResourceName | Set-Content $filePath -Force
                    (Get-Content $filePath) -replace '\#SubscriptionID\#', $this.SubscriptionContext.SubscriptionId | Set-Content $filePath -Force
                    (Get-Content $filePath) -replace '\#LAWSId\#', $newLAWSId | Set-Content $filePath -Force
                    (Get-Content $filePath) -replace '\#LAWSSharedKey\#', $newLAWSKey | Set-Content $filePath -Force  
                    
                    # update ca config maps like App Insight key
                    $this.PublishCustomMessage("Upadting App Insight Key...",[MessageType]::Warning)
                    $response = kubectl apply -f $filePath
                    if($null -ne $response){
                        $this.PublishCustomMessage("Successfully updated App Insight Key.",[MessageType]::Update)   
                    }else{
                        $this.PublishCustomMessage("Some error occurred while updating App Insight Key. See logs above for details.",[MessageType]::Error)
                    }
                }else{
                    $this.PublishCustomMessage("Some error occurred while updating App Insight Key/Log Analytics workspace details. See logs above for details.",[MessageType]::Error)
                }

              
                      
            }
            
            if($FixRuntimeAccount -eq $true){
        
                # Download deployment file from server and store it in temp location
                $deploymentFileUrl =  $this.deploymentFileBaseUrl +  $this.runtimeAccountFileName
                $InClusterCATempFolderPath = Join-Path $([Constants]::AzSKTempFolderPath) "InClusterCA";
                if(-not (Test-Path -Path $InClusterCATempFolderPath -PathType Container)){
                    New-Item -ItemType Directory -Force -Path $InClusterCATempFolderPath
                }
                $filePath = Join-Path $($InClusterCATempFolderPath) $this.runtimeAccountFileName
                Invoke-RestMethod  -Method Get -Uri $deploymentFileUrl -OutFile $filePath 
                # update ca scan job runtime account
                $this.PublishCustomMessage("Upadting AzSK Continuous Assurance job runtime account...",[MessageType]::Warning)
                $response = kubectl apply -f $filePath
                if($null -ne $response){
                    $this.PublishCustomMessage("Successfully Upadted AzSK Continuous Assurance job runtime account.",[MessageType]::Update)
                }else{
                    $this.PublishCustomMessage("Some error occurred while updating AzSK Continuous Assurance job runtime account. See logs above for details.",[MessageType]::Error)
                }

            }
            
            if($LogRetentionInDays -gt 0 -or $ScanIntervalInHours -gt 0 -or -not [string]::IsNullOrEmpty($ImageTag)){
                    # Upadte scan interval (if provided, deafult is 24) 
                    $Schedule = '"0 #h#/#i# * * *"' 
                    $jobHrs = ((Get-Date).ToUniversalTime().Hour + 1)%24
                    $Schedule = $Schedule -replace '\#h\#', $jobHrs
                    # Update job history limit (if provided , deafult is 7) 
                    if($LogRetentionInDays -gt 0){
                        $JobHistoryLimit = $LogRetentionInDays
                    }else{
                        $JobHistoryLimit = 7 
                    }
            
                    if($ScanIntervalInHours -gt 0){
                        $Schedule = $Schedule -replace '\#i\#', $ScanIntervalInHours
                    }else{
                        $Schedule = $Schedule -replace '\#i\#', 24 
                    }
                    
                    $controlSettings = $this.LoadServerConfigFile("ControlSettings.json");
                    $requiredImagePath = $controlSettings.InClusterCA.AKS.RequiredImagePath
                    $reuiredImageTag = $controlSettings.InClusterCA.AKS.RequiredImageTag

                    if([string]::IsNullOrEmpty($ImageTag)){
                        $ImagePath =  $requiredImagePath + ":" + $reuiredImageTag
                    }else{
                        $ImagePath =  $requiredImagePath + ":" + $ImageTag
                    }
            
                    # Download deployment file from server and store it in temp location
                    $deploymentFileUrl =  $this.deploymentFileBaseUrl +  $this.jobSpecificationsFileName
                    $InClusterCATempFolderPath = Join-Path $([Constants]::AzSKTempFolderPath) "InClusterCA";
                    if(-not (Test-Path -Path $InClusterCATempFolderPath -PathType Container)){
                        New-Item -ItemType Directory -Force -Path $InClusterCATempFolderPath
                    }
                    $filePath = Join-Path $($InClusterCATempFolderPath) $this.jobSpecificationsFileName
                    Invoke-RestMethod  -Method Get -Uri $deploymentFileUrl -OutFile $filePath 
                    (Get-Content $filePath) -replace '\#Schedule\#', $Schedule | Set-Content $filePath -Force
                    (Get-Content $filePath) -replace '\#JobHistoryLimit\#', $JobHistoryLimit | Set-Content $filePath -Force
                    (Get-Content $filePath) -replace '\#ImagePath\#', $ImagePath | Set-Content $filePath -Force
                    # update ca job configuration like scan interval, job history limit etc.
                    $this.PublishCustomMessage("Upadting AzSK Continuous Assurance job configuration...",[MessageType]::Warning)
                    $response = kubectl apply -f $filePath
                    if($null -ne $response){
                        $this.PublishCustomMessage("Successfully Upadted AzSK Continuous Assurance job configuration.",[MessageType]::Update)
                    }else{
                        $this.PublishCustomMessage("Some error occurred while updating AzSK Continuous Assurance job configuration. See logs above for details.",[MessageType]::Error)
                    }
                  
            
            }
        }
}
