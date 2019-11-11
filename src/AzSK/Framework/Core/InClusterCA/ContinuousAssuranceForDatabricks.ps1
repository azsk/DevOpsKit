class DatabricksClusterCA : CommandBase {
    # workspace base URL is required to make all the 
    # API calls
    [PSObject] $ResourceContext;
    [string] $PersonalAccessToken;
    [string] $AzSKSecretScopeName = "AzSK_CA_Secret_Scope";


    DatabricksClusterCA([PSObject] $ResourceContext, [InvocationInfo] $invocationContext): 
    Base([Constants]::BlankSubscriptionId, $invocationContext) { 
        $this.ResourceContext = $ResourceContext
    }

    static [PSObject] GetParameters($SubscriptionId, $WorkspaceName, $ResourceGroupName, $PAT) {
        if([string]::IsNullOrEmpty($SubscriptionId) -or 
            [string]::IsNullOrEmpty($WorkspaceName) -or
            [string]::IsNullOrEmpty($ResourceGroupName) -or
            [string]::IsNullOrEmpty($PAT)) {
            Write-Host "Input the following parameters"
            if ([string]::IsNullOrEmpty($SubscriptionId)) {
                $SubscriptionId = [Helpers]::ReadInput("Subscription ID")
            }
            if ([string]::IsNullOrEmpty($WorkspaceName)) {
                $WorkspaceName = [Helpers]::ReadInput("Databricks Workspace Name")
            }
            if ([string]::IsNullOrEmpty($ResourceGroupName)) {
                $ResourceGroupName = [Helpers]::ReadInput("Databricks Resource Group Name")
            }
            if ([string]::IsNullOrEmpty($PAT)) {
                $PAT = [Helpers]::ReadInput("Personal Access Token(PAT)")
            }
        }
        Set-AzContext -SubscriptionId $SubscriptionId *> $null
        $response = Get-AzResource -Name $WorkspaceName -ResourceGroupName $ResourceGroupName
        $response = $response | Where-Object{$_.ResourceType -eq "Microsoft.Databricks/workspaces"}
        # wrong name entered, no resource with that name found
        if ($null -eq $response) {
            Write-Host "Error: Resource [$WorkspaceName] not found in current subscription. Please recheck" -ForegroundColor Red
            return $null
        }
        $WorkspaceBaseUrl = "https://" +  $response.Location + ".azuredatabricks.net"
        return @{
            "SubscriptionId" = $SubscriptionId;
            "ResourceGroupName" = $ResourceGroupName;
            "WorkspaceName" = $WorkspaceName;
            "PersonalAccessToken" = $PAT;
            "WorkspaceBaseUrl" = $WorkspaceBaseUrl
        }
    }

    [void] InferLASettings() {
        # infer LA settings if not passed
        if ([string]::IsNullOrEmpty($this.ResourceContext.LAWorkspaceId)) {
            [LogAnalyticsHelper]::SetLAWSDetails()
            $settings = [ConfigurationManager]::GetAzSKSettings()
            $this.ResourceContext.LAWorkspaceId = $settings.LAWSId
            $this.ResourceContext.LASharedSecret = $settings.LAWSSharedKey
        } 
    }

    [PSObject] InvokeRestAPICall($EndPoint, $Method, $Body, $ErrorMessage) {
        try {
            $Header = @{
                "Authorization" = "Bearer " + $this.ResourceContext.PersonalAccessToken;
            }
            $URI = $this.ResourceContext.WorkspaceBaseURL + $EndPoint
            if ($Method -eq "GET") {
                $response = Invoke-RestMethod -Method $Method -Uri $uri `
                    -Headers $Header `
                    -ContentType 'application/json' -UseBasicParsing
            } else {
                $response = Invoke-RestMethod -Method $Method -Uri $uri `
                    -Headers $Header `
                    -Body $Body `
                    -ContentType 'application/json' -UseBasicParsing
            }
            return $response
        } catch {
            $this.PublishCustomMessage($ErrorMessage, [MessageType]::Error)
            throw ([SuppressedException]::new((""), [SuppressedExceptionType]::Generic))
        }
    }

    [void] InsertDataIntoDB($SecretKeyName, $Secret) {
        if ([string]::IsNullOrEmpty($Secret)) {
            $this.PublishCustomMessage("Skipping inserting $SecretKeyName into cluster")
            return
        }
        $params = @{
            "scope"        = $this.AzSKSecretScopeName;
            "key"          = $SecretKeyName;
            "string_value" = $Secret
        }
        $bodyJson = $params | ConvertTo-Json
        $endPoint = "/api/2.0/secrets/put"
        $ResponseObject = $this.InvokeRestAPICall($endPoint, "POST", $bodyJson, "Unable to create/update secret value, remaining steps will be skipped.")
    }

    [bool] CheckSecretPresence($SecretName, $SecretKey, $response) {
        if ($response.secrets.key.Contains($SecretKey)) {
            return $true
        } else {
            $this.PublishCustomMessage("$SecretName absent in the cluster", [MessageType]::Error)
            return $false
        }
    }

    [void] PrintGCASummary() {
        $SummaryEP = "/api/2.0/dbfs/read?path=/AzSK_Meta/meta.json"
        $response = $this.InvokeRestAPICall($SummaryEP, "GET", $null, 
                                "Unable to fetch summary. Please check if CA instance is present and running")
        $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($response.data))
        $jsonSummary = $decoded | ConvertFrom-Json
        $this.PublishCustomMessage([Helpers]::ConvertObjectToString($jsonSummary, $true))
    }

    [void] GetCA() {
        # check secret scope exist
        if(-not $this.CheckAzSKSecretScopeExists()){
            $this.PublishCustomMessage("AzSK scope not found. CA isn't functioning properly", [MessageType]::Error)
            return
        } 
        $ListEP = "/api/2.0/secrets/list?scope=AzSK_CA_Secret_Scope"
        $fail = $false
        $response = $this.InvokeRestAPICall($ListEP, "GET", $null, "Unable to fetch secrets. Please check if CA instance is present")
        $this.PublishCustomMessage("Checking if runtime permissions are present")
        $res = $this.CheckSecretPresence("AzSK Scan Key", "AzSK_CA_Scan_Key", $response)
        $res = $res -and ($this.CheckSecretPresence("Databricks Host Name", "DatabricksHostDomain" , $response))
        $res = $res -and ($this.CheckSecretPresence("Resource Name", "res_name" , $response))
        $res = $res -and ($this.CheckSecretPresence("Resource Group Name", "rg_name" , $response))
        $res = $res -and ($this.CheckSecretPresence("Subscription ID", "sid" , $response))
        $res = $res -and ($this.CheckSecretPresence("Log Analytics Workspace Id", "LAWorkspaceId" , $response))
        $res = $res -and ($this.CheckSecretPresence("Log Analytics Secret", "LASharedSecret" , $response))
        $foo = $this.CheckSecretPresence("Application Insight Key", "AzSK_AppInsight_Key", $response)
        $CAScanJob = $this.CheckAzSKJobExists()
        if (-not $CAScanJob) {
            $this.PublishCustomMessage("CA Scan Job is absent", [MessageType]::Error)
            $fail = $true
        }

        $this.PrintGCASummary();
        if ($res -and -not $fail) {
            $this.PublishCustomMessage("All required permissions and files present. CA Health OK")
        } else {
            $this.PublishCustomMessage("Not all required permissions and files are present. CA might not function properly", [MessageType]::Error)
        }
        
    }

    [bool] CheckAzSKSecretScopeExists() {
        $endPoint = "/api/2.0/secrets/scopes/list"
        $SecretScopeAlreadyExists = $false
        $Body = @{
            'scope' = $this.AzSKSecretScopeName;
        } | ConvertTo-Json
        $SecretScopes = $this.InvokeRestAPICall($endPoint, "GET", $Body, "Unable to fetch secret scope, remaining steps will be skipped.")
        if (-not [string]::IsNullOrEmpty($SecretScopes) `
                -and ("scopes" -in $SecretScopes.PSobject.Properties.Name) `
                -and ($SecretScopes.scopes | Measure-object).Count -gt 0) {
            $SecretScope = $SecretScopes.scopes | Where { $_.name -eq $this.AzSKSecretScopeName }
            if ($SecretScope -ne $null -and ( $SecretScope | Measure-Object).count -gt 0) {
                $SecretScopeAlreadyExists = $true
            }
        }
        return $SecretScopeAlreadyExists
    }

    [string] GetAzSKNotebookContent() {
        $NotebookUrl = [Constants]::DatabricksCANotebookUrl
        # Download notebook flrom server and store it in temp location
        $filePath = $env:TEMP + "\AzSK_CA_Scan_Notebook.ipynb"
        Invoke-RestMethod  -Method Get -Uri $NotebookUrl -OutFile $filePath
        $fileContent = get-content $filePath
        $fileContentBytes = [System.Text.Encoding]::UTF8.GetBytes($fileContent)
        $fileContentEncoded = [System.Convert]::ToBase64String($fileContentBytes)
        # cleanup notebook from temp location
        Remove-Item $filePath -ErrorAction Ignore
        return $fileContentEncoded;
    }

    [bool] CheckAzSKJobExists() {
        $JobAlreadyExists = $false
        $EndPoint = "/api/2.0/jobs/list"
        $JobList = $this.InvokeRestAPICall($EndPoint, "GET", $null, 
            "Unable to list jobs in workspace, remaining steps will be skipped.")
        if (-not [string]::IsNullOrEmpty($JobList) `
                -and ("jobs" -in $JobList.PSobject.Properties.Name) `
                -and ($JobList.jobs | Measure-object).Count -gt 0) {
            $AzSKJobs = $JobList.jobs | where { $_.settings.name -eq 'AzSK_CA_Scan_Job' }
            if ($AzSKJobs -ne $null -and ( $AzSKJobs | Measure-Object).count -gt 0) {
                $JobAlreadyExists = $true
            }
        }
        return $JobAlreadyExists;
    }

    [void] RemoveAzSKScanJob() {
        $EndPoint = "/api/2.0/jobs/list"
        $JobList = $this.InvokeRestAPICall($EndPoint, "GET", $null, 
            "Unable to list jobs in workspace, remaining steps will be skipped.")
        # we know for sure that the job will exist
        $AzSKJobs = $JobList.jobs | where { $_.settings.name -eq 'AzSK_CA_Scan_Job' }
        $DeleteEndPoint = "/api/2.0/jobs/delete"
        ForEach ($job in $AzSKJobs) {
            $this.PublishCustomMessage("Deleting AzSKJob with ID: $($job.job_id) created by user $($job.creator_user_name)")
            $jid = @{"job_id" = "$($job.job_id)"} | ConvertTo-Json
            $this.InvokeRestAPICall($DeleteEndPoint, "POST", $jid, "Unable to delete job") 
        }
    }

    [void] RemoveLogs() {
        $EndPoint = "/api/2.0/dbfs/delete"
        $BodyJson = @{
            "path" = "/AzSK_Meta";
            "recursive" = "true"
        } | ConvertTo-Json
        $ResponseObject = $this.InvokeRestAPICall($endPoint, "POST", $BodyJson, 
            "Unable to delete meta, remaining steps will be skipped.")
        $BodyJson = @{
            "path" = "/AzSK_Logs";
            "recursive" = "true"
        } | ConvertTo-Json
        $ResponseObject = $this.InvokeRestAPICall($endPoint, "POST", $BodyJson, 
            "Unable to delete logs, remaining steps will be skipped.")    
    }

    [bool] CheckAzSKWorkspaceExist() {
        $workspace = "/api/2.0/workspace/list?path=/"
        $response = $this.InvokeRestAPICall($workspace, "GET", $null, "Unable to fetch workspace.")
        $azskPath = $response | Where {$_.objects.path -eq "/AzSK"}
        if ([string]::IsNullOrEmpty($azskPath)) {
            return $false
        } else {
            return $true
        }
    }

    [void] CreateAzSKWorkspace() {
        $EndPoint = "/api/2.0/workspace/mkdirs"        
        $BodyJson = @{
            "path" = "/AzSK"
        } | ConvertTo-Json
        $ResponseObject = $this.InvokeRestAPICall($endPoint, "POST", $BodyJson, 
            "Unable to create folder in workspace, remaining steps will be skipped.")
    }

    [void] RemoveAzSKWorkspace() {
        $removeBody = @{
            "path" = "/AzSK";
            "recursive" = "true";
        }
        $removeBody = $removeBody | ConvertTo-Json
        $removeEP = "/api/2.0/workspace/delete"
        $this.InvokeRestAPICall($removeEP, "POST", $removeBody, "Unable to delete workspace")
    }

    [void] UploadAzSKNotebookToCluster() {
        # Create AzSK folder in user workspace, if folder already exists it will do nothing
        if (-not $this.CheckAzSKWorkspaceExist()) {
            $this.CreateAzSKWorkspace()
        }
        # Import notebook in user workspace,
        $BodyJson = @{
            'path'      = '/AzSK/AzSK_CA_Scan_Notebook';
            'format'    = 'JUPYTER';
            'language'  = 'PYTHON';
            'content'   = $this.GetAzSKNotebookContent();
            'overwrite' = 'true'
        } | ConvertTo-Json
        $endPoint = "/api/2.0/workspace/import"
        $this.PublishCustomMessage("Uploading AzSK Scan Notebook into the cluster workspace")
        $ResponseObject = $this.InvokeRestAPICall($endPoint, "POST", $BodyJson, "Unable to import notebook in workspace, remaining steps will be skipped.")
    }

    [void] CreateAzSKScanJob($Frequency) {
        $JobConfigServerUrl = [Constants]::DatabricksScanJobConfigurationUrl
        # if frequency is not mentioned, create the job with 24 hr interval at a
        # time one hour after the scan job is created
        if ([string]::IsNullOrEmpty($Frequency)) {
            $jobHrs = ((Get-Date).ToUniversalTime().Hour + 1) % 24
            $Schedule = "0 0 $jobHrs * * ?"
        } else {
            # if frequency is mentioned then run the
            # scan job once every $Frequency hours
            $Schedule = "0 0 */$Frequency * * ?"           
        }
        # schedule expects a single quote around it
        $Schedule = '"' + $Schedule + '"'
        # Create job
        $this.PublishCustomMessage("Creating Job 'AzSK_CA_Scan_Job' in the workspace")
        $filePath = $env:TEMP + "\DatabricksCAScanJobConfig.json"
        $configuration = Invoke-RestMethod -Uri $JobConfigServerUrl -Method "GET"
        $configuration = $configuration -Replace  '#Schedule#', $Schedule
        $EndPoint = "/api/2.0/jobs/create"
        $ResponseObject = $this.InvokeRestAPICall($EndPoint, "POST", $configuration, "Unable to create AzSK_CA_Scan_Job in workspace.")
        $this.PublishCustomMessage("Successfully created job 'AzSK_CA_Scan_Job' with Job ID: $($ResponseObject.job_id).")
    }

    [void] InstallCA() {
        # These are the keys that are stored in the secret scope
        $PatSecretKey = "AzSK_CA_Scan_Key"
        $WorkspaceNameKey = "res_name"
        $ResourceGroupNameKey = "rg_name"
        $IKKey = "AzSK_AppInsight_Key"
        $SubscriptionIdKey = "sid"
        $LASharedSecretKey = "LASharedSecret"
        $LAWorkspaceIdKey = "LAWorkspaceId"
        $HostNameKey = "DatabricksHostDomain"
        $NotebookFolderPath = "/AzSK"  

        # set log analytics keys
        $this.InferLASettings()

        # region Step 1: Create Secret Scope 
        # Check if Secret Scope already exists
        if ($this.CheckAzSKSecretScopeExists()) {
            $this.PublishCustomMessage("Secret scope for AzSK already exists. We'll reuse it.",
                [MessageType]::Warning)
        } else {
            $Body = @{
                'scope' = $this.AzSKSecretScopeName;
            } | ConvertTo-Json
            $this.PublishCustomMessage("Creating a new secret scope [$($this.AzSKSecretScopeName)] in the workspace")
            $EndPoint = "/api/2.0/secrets/scopes/create"
            $ResponseObject = $this.InvokeRestAPICall($EndPoint, "POST", $Body, 
                "Unable to create secret scope, remaining steps will be skipped.")
        }

        
        # region Step 2: PUT Token in Secret Scope
        # If Secret already exists it will update secret value
        $this.PublishCustomMessage("Installing required secrets into the cluster")
        $this.InsertDataIntoDB($PatSecretKey,         $this.ResourceContext.PersonalAccessToken)
        $this.InsertDataIntoDB($WorkspaceNameKey,     $this.ResourceContext.WorkspaceName)
        $this.InsertDataIntoDB($ResourceGroupNameKey, $this.ResourceContext.ResourceGroupName)
        $this.InsertDataIntoDB($SubscriptionIdKey,    $this.ResourceContext.SubscriptionId)
        $this.InsertDataIntoDB($HostNameKey,          $this.ResourceContext.WorkspaceBaseUrl)
        $this.InsertDataIntoDB($LASharedSecretKey,    $this.ResourceContext.LASharedSecret)
        $this.InsertDataIntoDB($LAWorkspaceIdKey,     $this.ResourceContext.LAWorkspaceId)

        if ([string]::IsNullOrEmpty($this.ResourceContext.InstrumentationKey)) {
            $this.PublishCustomMessage("Skipping AppInsight installation, no Instrumentation Key passed")
        } else {
            $this.InsertDataIntoDB($IKKey, $this.ResourceContext.InstrumentationKey)
        }
        

        # region Step 3: Set up AzSk Notebook in Databricks workspace
        # Create AzSK folder in user workspace, if folder already exists it will do nothing
        $this.UploadAzSKNotebookToCluster()

        # region Step 4: Schedule Notebook to run periodically,
        # Check if Job already exists
        if ($this.CheckAzSKJobExists()) {
            $this.PublishCustomMessage("AzSK job already exists. We'll reuse it.", [MessageType]::Warning)
        } else {
            # passing null will create a job with 24hr frequency
            $this.CreateAzSKScanJob($null)
        }

        # print log analytics settings
        $this.PublishCustomMessage("Log Analytics metrics will be sent to:")
        $this.PublishCustomMessage("Workspace Id: $($this.ResourceContext.LAWorkspaceId)")

        # Footer message
        $this.PublishCustomMessage("`n")
        $this.PublishCustomMessage([Constants]::DoubleDashLine)
        $this.PublishCustomMessage("** Next Steps **")
        $this.PublishCustomMessage("AzSK Continuous Assurance For Clusters Setup is completed.")
        $this.PublishCustomMessage("Your cluster will be scanned periodically by the AzSK CA.")
        $this.PublishCustomMessage("The first CA scan job will be triggered within the next 60 mins. You can check control evaluation results (job logs) after that.")
        $this.PublishCustomMessage("All security control evaluation results will also be sent to App Insight if an instrumentation key was provided during setup above.")
        $this.PublishCustomMessage("For more info, please see docs: https://aka.ms/devopskit/inclusterca")
    }

    [void] UpdateCA($NewPersonalAccessToken, $NewAppInsightKey, $NewSchedule) {
        $PatSecretKey = "AzSK_CA_Scan_Key"
        $IKKey = "AzSK_AppInsight_Key"

        # validation- secret scope should already exist
        if (-not $this.CheckAzSKSecretScopeExists()) {
            $this.PublishCustomMessage("AzSK secret scope not found. Please ensure the CA is installed.",
                                       [MessageType]::Error)
            return
        }
        # update secret scope values
        $this.InsertDataIntoDB($PatSecretKey, $NewPersonalAccessToken)
        $this.InsertDataIntoDB($IKKey,        $NewAppInsightKey)
        # update notebook content
        $this.UploadAzSKNotebookToCluster()
        # update schedule, if passed
        # validation- CA scan job should already exist
        if (-not [string]::IsNullOrEmpty($NewSchedule)) {
            if (-not $this.CheckAzSKJobExists()) {
                $this.PublishCustomMessage("CA scan job is abset. Please ensure the CA is installed.", 
                                           [MessageType]::Error)
                return
            } else {
                $this.RemoveAzSKScanJob()
            }
            $this.CreateAzSKScanJob($NewSchedule)
        }
    }

    [void] RemoveAzSKSecretScope() {
        $deleteEP = "/api/2.0/secrets/scopes/delete"
        $deleteBody = @{
            "scope" = "AzSK_CA_Secret_Scope";
        } | ConvertTo-Json
        $response = $this.InvokeRestAPICall($deleteEP, "POST", $deleteBody, "Unable to delete secret scope. Please retry")
        $this.PublishCustomMessage("Deleted AzSK Secret Scope")
    }

    [void] RemoveCA() {
        # remove workspace
        if ($this.CheckAzSKWorkspaceExist()) {
            $this.RemoveAzSKWorkspace()
            $this.PublishCustomMessage("AzSK Workspace removed.")
        } else {
            $this.PublishCustomMessage("AzSK workspace not found. Please ensure the CA is installed. Note: *one* scan needs to be completed for the population of metadata.",
                                       [MessageType]::Error)
            return
        }
        # remove secret scope
        if ($this.CheckAzSKSecretScopeExists()) {
            $this.RemoveAzSKSecretScope()
            $this.PublishCustomMessage("AzSK secret scope removed")
        } else {
            $this.PublishCustomMessage("AzSK secret scope doesn't exist. Please ensure the CA is installed.",
                                       [MessageType]::Error)
            return
        }
        # remove scan job
        if ($this.CheckAzSKJobExists()) {
            $this.RemoveAzSKScanJob()
            $this.PublishCustomMessage("AzSK scan job deleted.")
        } else {
            $this.PublishCustomMessage("AzSK scan job not found. Please ensure the CA is installed.",
                                       [MessageType]::Error)
        }
        # remove logs if the switch is passed
        if ($this.ResourceContext.RemoveLogs) {
            $this.RemoveLogs()
            $this.PublishCustomMessage("AzSK scan logs and meta data removed.")
        }
    }
}
