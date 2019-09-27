class KubernetesClusterCA : AzCommandBase {

    [PSObject] $ResourceObject;
    [string]  $ResourceGroupName;
    [string]  $ResourceName;
    [string]  $ResourceType = "Microsoft.ContainerService/managedClusters";
    [string]  $nameSpace = "azsk-scanner"
    [string]  $serviceAccountName = "azsk-scanner-account"
    [string]  $clusterRoleName = "azsk-scanner-clusterrole"
    [string]  $configMapName = "azsk-config"
    [string]  $clusterRoleBindingName = "azsk-scanner-rolebinding"
    [string]  $cronJobName = "azsk-ca-job"
    [string]  $deploymentFileBaseUrl = "https://azsdkdataoss.blob.core.windows.net/azsdk-configurations/recmnds/"
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
        }

        hidden [bool] CheckPrerequisites()
        {
            # This method verifies that if both Azure CLI and Kubernetes CLI are installed or not
            $IsPrerequisitesPresent = $false
            $azCliCmdOutput  = az --help --ouput json
            $aksliCmdOuput = kubectl help

            if($null -ne $azCliCmdOutput -and $null -ne $aksliCmdOuput ){
                $IsPrerequisitesPresent = $true
            }else{
                if($null -eq $azCliCmdOutput){
                    $IsPrerequisitesPresent = $false
                    $this.PublishCustomMessage("Azure CLI is not presnet in machine, you need to install Azure CLI. To install, please refer: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest", [MessageType]::Warning)         
                }
                if($null -eq $aksliCmdOuput){
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

        [Void] InstallKubernetesContinuousAssurance()
        {
            $AppInsightKey = [RemoteReportHelper]::GetAIOrgTelemetryKey()
            if([string]::IsNullOrWhiteSpace($AppInsightKey))
            {
                $AppInsightKey = 'None'
            }else
            {
                $AppInsightKey = $AppInsightKey.Trim()
            }
            
            # Prepare job schedule
            $Schedule = '"0 #h#/24 * * *"' 
            $jobHrs = ((Get-Date).ToUniversalTime().Hour + 1)%24
            $Schedule = $Schedule -replace '\#h\#', $jobHrs
            
            # Download deployment file from server and store it in temp location
            $deploymentFileUrl =  $this.deploymentFileBaseUrl + $this.deploymentFileName
            $filePath = Join-Path $($env:TEMP)  $($this.deploymentFileName)
            Invoke-RestMethod  -Method Get -Uri $deploymentFileUrl -OutFile $filePath 
            
            # Bootstrap basic properties like App Insight Key and job schedule in deployment file
            
            (Get-Content $filePath) -replace '\#AppInsightKey\#', $AppInsightKey | Set-Content $filePath -Force
            (Get-Content $filePath) -replace '\#Schedule\#', $Schedule | Set-Content $filePath -Force
            (Get-Content $filePath) -replace '\#RGName\#', $this.ResourceGroupName | Set-Content $filePath -Force
            (Get-Content $filePath) -replace '\#ResourceName\#', $this.ResourceName | Set-Content $filePath -Force
            (Get-Content $filePath) -replace '\#SubscriptionID\#', $this.SubscriptionContext.SubscriptionId | Set-Content $filePath -Force
            
            
            # craete ca scan job
            
            $this.PublishCustomMessage("Setting up AzSK Continuous Assurance in Kubernetes cluster...", [MessageType]::Warning)
        
            # kubectl apply -f $filePath
            
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
                    $allJObPods = $response | ConvertFrom-Json | Select-Object -ExpandProperty items
                    $jobPodsCount =    ($allJObPods | Measure-Object).Count
                    if($jobPodsCount -gt 0){
                        $moduleName = $this.GetModuleName();
                        $this.PublishCustomMessage("Downloading existing job's log to local machine..." , [MessageType]::Warning)
                        $baseFolder = Join-Path $($Env:LOCALAPPDATA) "Microsoft" | Join-Path -ChildPath $($moduleName) | Join-Path -ChildPath "Logs\ClusterScans\Kubernetes"| Join-Path -ChildPath $($this.SubscriptionContext.SubscriptionId )| Join-Path -ChildPath $($this.ResourceGroupName)| Join-Path -ChildPath $($this.ResourceName)
                        #$baseFolder =  $Env:LOCALAPPDATA + "\Microsoft\" + $moduleName + "Logs\ClusterScans\Kubernetes\"+ $this.SubscriptionContext.SubscriptionId +"\"+  $this.ResourceGroupName +"\"+ $this.ResourceName+ "\" ; 
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
                }
                else
                {
                    $this.PublishCustomMessage("You have choosen not to download previous logs." , [MessageType]::Warning)
                }
            
                $this.PublishCustomMessage("Removing AzSK Continuous Assurance from cluster..."  , [MessageType]::Warning)
            
                #kubectl delete -f $deploymentFileUrl
            
                $this.PublishCustomMessage("Successfully removed AzSK Continuous Assurance from cluster."  , [MessageType]::Update)
            
            }
            
        }
        
        [Void] GetKubernetesContinuousAssurance()
        {
            $this.PublishCustomMessage("`nCheck 01: Presence of required configuration settings.",[MessageType]::Info)
            $configJson = kubectl get configmaps $this.configMapName --namespace $this.nameSpace -o json
            $configJson = $configJson| ConvertFrom-Json | Select-Object data
            $configMaps = $configJson.data
        
            $presentConfig = @{
            "AppInsightKey    " = $configMaps.APP_INSIGHT_KEY
            "SubscriptionId   " = $configMaps.SUBSCRIPTION_ID
            "ResourceName     " = $configMaps.RESOURCE_NAME
            "ResourceGroupName" = $configMaps.RG_NAME
            }
        
            if($null -eq $configMaps){     
                $this.PublishCustomMessage("`nConfiguration settings for your cluster are missing.",[MessageType]::Error)
            }else{
                    $this.PublishCustomMessage("Configuration settings for your cluster are as follows:")
                    foreach($key in $presentConfig.keys)
                    {
                        Write-Host "$($key) : $($presentConfig.Item($key))" -ForegroundColor Yellow
                    }
            }
        
            if($null -eq $presentConfig["AppInsightKey"]){
                $this.PublishCustomMessage("`nApplication Inight key is not present. Scan logs will not be sent to telelmetry.",[MessageType]::Warning)
            }else{
                $this.PublishCustomMessage("`nScan logs will be sent to Application Insight: $($presentConfig['AppInsightKey'])",[MessageType]::Update)
            }
        
            $this.PublishCustomMessage("`nCheck 02: Validate runtime permissions to scan cluster.",[MessageType]::Info)
            $svcAccountJson = kubectl get ServiceAccount $this.serviceAccountName --namespace $this.nameSpace -o json
            $svcAccountJson = $svcAccountJson | ConvertFrom-Json | Select-Object metadata
            $svcAccountUID = $svcAccountJson.metadata.uid
            $isRuntimeAccountValid = $true
        
            if($null -eq $svcAccountUID){
                $this.PublishCustomMessage("Service account is not present.",[MessageType]::Error)
                $isRuntimeAccountValid = $false
            }
        
            $requiredApiGroups = "*"
            $requiredResources = @("pods","deployments","nodes","serviceaccounts","configmaps","clusterrolebindings")
            $requiredVerbs = @("get","watch","list")
        
            $clusterRoleJson = kubectl get ClusterRole $this.clusterRoleName --namespace $this.nameSpace -o json
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
        
            $roleBindingJson = kubectl get ClusterRoleBinding $this.clusterRoleBindingName --namespace $this.nameSpace -o json
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
        
            if($isRuntimeAccountValid){
                $this.PublishCustomMessage("Required runtime account for scanning cluste is properly configured.", [MessageType]::Update)
            }else{
                $this.PublishCustomMessage("Required runtime account for scanning cluste is not properly configured.",[MessageType]::Error)
            }
        
            $this.PublishCustomMessage("`ncheck 03: Check if latest image is used.",[MessageType]::Info)
            $requiredImage = "azsktest/akstest:latest"
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
            $this.PublishCustomMessage("Job's last scheduled time: $($cronJobJson.status.lastScheduleTime)"  , [MessageType]::Update)
            
        
            $this.PublishCustomMessage("`nCheck 06: Log retention.",[MessageType]::Info)
            $this.PublishCustomMessage("Log retention period: $($jobSpec.successfulJobsHistoryLimit)" , [MessageType]::Update)
        }
        
        [Void] UpdateKubernetesContinuousAssurance($AppInsightKey, $FixRuntimeAccount, $LogRetentionInDays,  $ScanIntervalInHours, $ImageTag)
        {
        
            if(-not [String]::IsNullOrEmpty($AppInsightKey)){
            
                # Download deployment file from server and store it in temp location
                $deploymentFileUrl =  $this.deploymentFileBaseUrl +  $this.configMapFileName
                $filePath = Join-Path $($env:TEMP) $this.configMapFileName
                Invoke-RestMethod  -Method Get -Uri $deploymentFileUrl -OutFile $filePath 
                (Get-Content $filePath) -replace '\#AppInsightKey\#', $AppInsightKey | Set-Content $filePath -Force
                (Get-Content $filePath) -replace '\#RGName\#', $this.ResourceGroupName | Set-Content $filePath -Force
                (Get-Content $filePath) -replace '\#ResourceName\#', $this.ResourceName | Set-Content $filePath -Force
                (Get-Content $filePath) -replace '\#SubscriptionID\#', $this.SubscriptionContext.SubscriptionId | Set-Content $filePath -Force
                    # update ca config maps like App Insight key
                    $this.PublishCustomMessage("Upadting App Insight Key...",[MessageType]::Warning)
                    $response = kubectl apply -f $filePath
                    if($null -ne $response){
                        $this.PublishCustomMessage("Successfully updated App Insight Key.",[MessageType]::Update)   
                    }else{
                        $this.PublishCustomMessage("Some error occurred while updating App Insight Key. See logs above for details.",[MessageType]::Error)
                    }
                      
            }
            
            if($FixRuntimeAccount -eq $true){
        
                # Download deployment file from server and store it in temp location
                $deploymentFileUrl =  $this.deploymentFileBaseUrl +  $this.runtimeAccountFileName
                $filePath = Join-Path $($env:TEMP) $this.runtimeAccountFileName
                Invoke-RestMethod  -Method Get -Uri $deploymentFileUrl -OutFile $filePath 
                # update ca scan job runtime account
                $this.PublishCustomMessage("Upadting AzSK Continuous Assurance job runtime account...",[MessageType]::Warning)
                $response = kubectl apply -f $filePath
                $this.PublishCustomMessage("Successfully Upadted AzSK Continuous Assurance job runtime account.",[MessageType]::Update)
        
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
                    
                    $ImagePath = "azsktest/akstest:"
                    if([string]::IsNullOrEmpty($ImageTag)){
                        $ImagePath =  $ImagePath + "latest"
                    }else{
                    $ImagePath =  $ImagePath + $ImageTag
                    }
            
                    # Download deployment file from server and store it in temp location
                    $deploymentFileUrl =  $this.deploymentFileBaseUrl +  $this.jobSpecificationsFileName
                    $filePath = Join-Path $($env:TEMP) $this.jobSpecificationsFileName
                    Invoke-RestMethod  -Method Get -Uri $deploymentFileUrl -OutFile $filePath 
                    (Get-Content $filePath) -replace '\#Schedule\#', $Schedule | Set-Content $filePath -Force
                    (Get-Content $filePath) -replace '\#JobHistoryLimit\#', $JobHistoryLimit | Set-Content $filePath -Force
                    (Get-Content $filePath) -replace '\#ImagePath\#', $ImagePath | Set-Content $filePath -Force
                    # update ca job configuration like scan interval, job history limit etc.
                    $this.PublishCustomMessage("Upadting AzSK Continuous Assurance job configuration...",[MessageType]::Warning)
                    $response = kubectl apply -f $filePath
                    $this.PublishCustomMessage("Successfully Upadted AzSK Continuous Assurance job configuration.",[MessageType]::Update)
            
            }
        }
}
