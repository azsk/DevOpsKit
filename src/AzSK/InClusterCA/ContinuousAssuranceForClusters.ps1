$INFO_IMP = "Yellow"
$INFO = "Cyan"
$ERR = "Red"
$SUCC = "Green"

function InvokeRestAPICall($EndPoint, $Method, $Body, $ErrorMessage)
{
    $uri = $WorkSpaceBaseUrl + $EndPoint
    try{
        if([string]::IsNullOrEmpty($body))
        {
         $response = Invoke-RestMethod -Method $Method -Uri $uri `
							         -Headers @{"Authorization" = "Bearer " + $PersonalAccessToken} `
							         -ContentType 'application/json' -UseBasicParsing
        }else
        {
         $response = Invoke-RestMethod -Method $Method -Uri $uri `
							           -Headers @{"Authorization" = "Bearer " + $PersonalAccessToken} `
							           -ContentType 'application/json' -Body $Body -UseBasicParsing
        }
    }
    catch{
      
        Write-Host $ErrorMessage -ForegroundColor $ERR
        return $null
    }
    return $response
}


function Insert-StuffIntoDB($SecretScopeName, $SecretKeyName, $Secret) {
    $params = @{
      'scope' = $SecretScopeName;
      "key" = $SecretKeyName;
      "string_value" = $Secret
    }

    $bodyJson = $params | ConvertTo-Json

    $endPoint = "/api/2.0/secrets/put"

    Write-Host "Creating/Updating value for secret [$SecretKeyName] in the workspace" -ForegroundColor $INFO

    $ResponseObject = InvokeRestAPICall -EndPoint $endPoint -Method "POST" -Body $bodyJson -ErrorMessage "Unable to create/update secret value, remaining steps will be skipped."

    Write-Host "Created/Updated value for secret [$SecretKeyName] successfully." -ForegroundColor $SUCC

}

function Setup-DataBricks() {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
    Write-Host "Input the following parameters"
    $sid = Read-Host -Prompt "Subscription Id"
    Set-AzContext -SubscriptionId $sid *> $null
    $res_name = Read-Host -Prompt 'Databricks Workspace Name'
    $rg_name = Read-Host -Prompt "Databricks Resource Group Name"
    $response = Get-AzResource -Name $res_name -ResourceGroupName $rg_name

    $response = $response | Where-Object{$_.ResourceType -eq "Microsoft.Databricks/workspaces"}
    # wrong name entered, no resource with that name found
    if ($response -eq $null) {
        Write-Host "Error: Resource $res_name not found in current subscription. Please recheck" -ForegroundColor $ERR
        return
    }
    # $response = $dbresource
    # $rg_name = $response.ResourceGroupName
    $PAT = Read-Host -Prompt 'Personal Access Token(PAT)'
    $IK = Read-Host -Prompt "Input Instrumentation Key for enabling App Insights (press enter to skip)"
    $PersonalAccessToken = $PAT.Trim()
    $InstrumentationKey = $IK.Trim()
    $WorkSpaceBaseUrl = "https://" +  $response.Location + ".azuredatabricks.net"
    # Please don't modify these values
    $ConfigBaseUrl = "https://azsdkossep.azureedge.net/3.9.0/"
    $NotebookUrl = "https://azsdkdataoss.blob.core.windows.net/azsdk-configurations/recmnds/AzSK_DB.ipynb"
    $SecretScopeName = "AzSK_CA_Secret_Scope"
    $SecretKeyName = "AzSK_CA_Scan_Key"
    $IKName = "AzSK_AppInsight_Key"
    $NotebookFolderPath = "/AzSK"  

    #region Step 1: Create Secret Scope 

     $params = @{
     'scope' = $SecretScopeName
    }

    $bodyJson = $params | ConvertTo-Json

    # Check if Secret Scope already exists
    
    Write-Host "Checking if secret scope [$SecretScopeName] already exists in the workspace" -ForegroundColor $INFO

    $endPoint =  "/api/2.0/secrets/scopes/list"
    $SecretScopeAlreadyExists = $false
    $SecretScopes = InvokeRestAPICall -EndPoint $endPoint -Method "GET" -ErrorMessage "Unable to fetch secret scope, remaining steps will be skipped."
   
    if($SecretScopes -ne $null -and ("scopes" -in $SecretScopes.PSobject.Properties.Name) -and ($SecretScopes.scopes | Measure-object).Count -gt 0)
    {
     $SecretScope = $SecretScopes.scopes | where {$_.name -eq $SecretScopeName}
     if($SecretScope -ne $null -and ( $SecretScope | Measure-Object).count -gt 0)
     {
        $SecretScopeAlreadyExists = $true
        Write-Host "Secret scope [$SecretScopeName] already exists in the workspace. We will reuse it." -ForegroundColor $INFO_IMP
     }
    }
    
    # Create Secret Scope if not already exists
    if(-not $SecretScopeAlreadyExists)
    {
        Write-Host "Creating a new secret scope [$SecretScopeName] in the workspace" -ForegroundColor $INFO
        $endPoint = "/api/2.0/secrets/scopes/create"
        $ResponseObject =  InvokeRestAPICall -EndPoint $endPoint -Method "POST" -Body $bodyJson -ErrorMessage "Unable to create secret scope, remaining steps will be skipped."
				
        Write-Host "Created scope [$SecretScopeName] successfully." -ForegroundColor $INFO
    }
    
    # end region

    # region Step 2: PUT Token in Secret Scope

    # If Secret already exists it will update secret value
     
    Insert-StuffIntoDB -SecretScopeName $SecretScopeName -SecretKeyName $SecretKeyName -Secret $PersonalAccessToken
    Insert-StuffIntoDB -SecretScopeName $SecretScopeName -SecretKeyName "res_name" -Secret $res_name
    Insert-StuffIntoDB -SecretScopeName $SecretScopeName -SecretKeyName "rg_name" -Secret $rg_name
    Insert-StuffIntoDB -SecretScopeName $SecretScopeName -SecretKeyName "sid" -Secret $sid
    Insert-StuffIntoDB -SecretScopeName $SecretScopeName -SecretKeyName "DatabricksHostDomain" -Secret $WorkSpaceBaseUrl

    #end region
    if ($InstrumentationKey -ne "") {
        # region step 2.5: Put instrumentation key in secret scope
        Insert-StuffIntoDB -SecretScopeName $SecretScopeName -SecretKeyName $IKName -Secret $InstrumentationKey
    } else {
        Write-Host "Skipping AppInsight installation, no Instrumentation Key passed" -ForegroundColor $INFO_IMP
    }
    
    # end region

    # region Step 3: Set up AzSk Notebook in Databricks workspace

    # Create AzSK folder in user workspace, if folder already exists it will do nothing

     $endPoint = "/api/2.0/workspace/mkdirs"
     
     $body = @{
     "path" = $NotebookFolderPath
    }

    $bodyJson  = $body | ConvertTo-Json

    $ResponseObject = InvokeRestAPICall -EndPoint $endPoint -Method "POST" -Body $bodyJson -ErrorMessage "Unable to create folder in workspace, remaining steps will be skipped."

    # Download notebook from server and store it in temp location

    $filePath = $env:TEMP + "\AzSK_CA_Scan_Notebook.ipynb"
    Invoke-RestMethod  -Method Get -Uri $NotebookUrl -OutFile $filePath

    # Bootstrap basic properties and urls in Notebook

    (Get-Content $filePath) -replace '\#DatabricksHostDomain\#', $WorkSpaceBaseUrl | Set-Content $filePath -Force
    (Get-Content $filePath) -replace '\#SID\#' , $sid | Set-Content $filePath -Force
    (Get-Content $filePath) -replace '\#RG_NAME\#' , $rg_name | Set-Content $filePath -Force
    (Get-Content $filePath) -replace '\#RES_NAME\#' , $res_name | Set-Content $filePath -Force

    $fileContent = get-content $filePath
    $fileContentBytes = [System.Text.Encoding]::UTF8.GetBytes($fileContent)
    $fileContentEncoded = [System.Convert]::ToBase64String($fileContentBytes)
    


    # Import notebook in user workspace,

    $params = @{
      'path' = $NotebookFolderPath + '/AzSK_CA_Scan_Notebook';
      'format' = 'JUPYTER';
      'language' =  'PYTHON';
      'content'=  $fileContentEncoded;
      'overwrite' = 'true'
    }


    $bodyJson = $params | ConvertTo-Json
    $endPoint = "/api/2.0/workspace/import"
    Write-Host "Uploading AzSK Scan Notebook into the workspace" -ForegroundColor $INFO
    $ResponseObject = InvokeRestAPICall -EndPoint $endPoint -Method "POST" -Body $bodyJson -ErrorMessage "Unable to import notebook in workspace, remaining steps will be skipped."
    Write-Host "Successfully imported AzSK_CA_Scan_Notebook." -ForegroundColor $INFO

    #cleanup notebook from temp location

    Remove-Item $filePath -ErrorAction Ignore

    #end region

    #region Step 4: Schedule Notebook to run periodically,

    # Check if Job already exists

    Write-Host "Checking if CA Scan job exists in the workspace" -ForegroundColor $INFO
    $JobAlreadyExists = $false
    $endPoint =  "/api/2.0/jobs/list"
    $JobList = InvokeRestAPICall -EndPoint $endPoint -Method "GET" -ErrorMessage "Unable to list jobs in workspace, remaining steps will be skipped."

    if($JobList -ne $null -and ("jobs" -in $JobList.PSobject.Properties.Name) -and ($JobList.jobs | Measure-object).Count -gt 0)
    {
     $AzSKJobs = $JobList.jobs  | where {$_.settings.name -eq 'AzSK_CA_Scan_Job'}
     if($AzSKJobs -ne $null -and ( $AzSKJobs | Measure-Object).count -gt 0)
     {
        $JobAlreadyExists = $true
        Write-Host "AzSK_CA_Scan_Job already exists in the workspace" -ForegroundColor $INFO_IMP
     }
    }

    # Create Job if not already exist

    if(-not $JobAlreadyExists)
    {
        # Prepare job schedule
        $Schedule = '"0 0 #h# * * ?"'
        $jobHrs = ((Get-Date).ToUniversalTime().Hour + 1) % 24
        $Schedule = $Schedule -replace '\#h\#', $jobHrs

        # Create job
        Write-Host "Creating Job 'AzSK_CA_Scan_Job' in the workspace" -ForegroundColor $INFO
        $JobConfigServerUrl = $ConfigBaseUrl + "DatabricksCAScanJobConfig.json"
        #$JobConfigServerUrl = "C:\Users\makul\Desktop\ADB_Config.json"
        $filePath = $env:TEMP + "\DatabricksCAScanJobConfig.json"
        Invoke-RestMethod  -Method Get -Uri $JobConfigServerUrl -OutFile $filePath 
        # Bootstrap basic properties like App Insight Key and job schedule in deployment file
        (Get-Content $filePath) -replace '\#Schedule\#', $Schedule | Set-Content $filePath -Force

        $body = Invoke-RestMethod  -Method Get -Uri $filePath
        $bodyJson  = $body | ConvertTo-Json
        $endPoint = "/api/2.0/jobs/create"
        $ResponseObject = InvokeRestAPICall -EndPoint $endPoint -Method "POST" -Body $bodyJson -ErrorMessage "Unable to create AzSK_CA_Scan_Job in workspace."
        Write-Host "Successfully created job 'AzSK_CA_Scan_Job' with Job ID: $($ResponseObject.job_id)." -ForegroundColor $succ
        Write-Host "AzSK Continuous Assurance setup completed." -ForegroundColor $SUCC
        Write-Host "Your cluster will be scanned periodically by AzSK CA." -ForegroundColor $INFO
        Write-Host "The first CA scan job will be triggered within next 60 mins. You can check control evaluation results (job logs) after that." -ForegroundColor $INFO
        Write-Host "All security control evaluation results will also be sent to App Insight if an instrumentation key was provided during setup above." -ForegroundColor $INFO
        Write-Host "For more info, please see docs: https://aka.ms/devopskit/inclusterca" -ForegroundColor $INFO
    }
  
    #end region

}


function Update-DataBricks() {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
    Write-Host "Input the following parameters"
    $sid = Read-Host -Prompt "Subscription Id"
    Set-AzContext -SubscriptionId $sid *> $null
    $res_name = Read-Host -Prompt 'Databricks workspace name'
    $rg_name = Read-Host -Prompt "Databricks resource group name"
    $response = Get-AzResource -Name $res_name -ResourceGroupName $rg_name

    $response = $response | Where-Object{$_.ResourceType -eq "Microsoft.Databricks/workspaces"}
    # wrong name entered, no resource with that name found
    if ($response -eq $null) {
        Write-Host "Error: Resource $res_name not found in current subscription. Please recheck" -ForegroundColor $ERR
        return
    }
    $PAT = Read-Host -Prompt 'Input Personal Access Token(PAT) for Databricks Workspace'
    $IK = Read-Host -Prompt "New Instrumentation Key for updating App Insights (or press enter to skip updating)"
    $newPAT = Read-Host -Prompt "New PAT token for updating the PAT in the workspace (or press enter to skip updating)"
    $PersonalAccessToken = $PAT.Trim()
    $InstrumentationKey = $IK.Trim()
    $newPAT = $newPAT.Trim()
    $newSchedule = Read-Host -Prompt "New schedule (or press enter to skip updating)"
    $WorkSpaceBaseUrl = "https://" +  $response.Location + ".azuredatabricks.net"
    # Please don't modify these values
    $ConfigBaseUrl = "https://azsdkossep.azureedge.net/3.9.0/"
    $NotebookUrl = "https://azsdkdataoss.blob.core.windows.net/azsdk-configurations/recmnds/AzSK_DB.ipynb"
    $SecretScopeName = "AzSK_CA_Secret_Scope"
    $SecretKeyName = "AzSK_CA_Scan_Key"
    $IKName = "AzSK_AppInsight_Key"
    $NotebookFolderPath = "/AzSK"  

    #region Step 1: Create Secret Scope 

     $params = @{
     'scope' = $SecretScopeName
    }

    $bodyJson = $params | ConvertTo-Json

    # Check if Secret Scope already exists
    
    Write-Host "Checking if secret scope [$SecretScopeName] already exists in the workspace" -ForegroundColor $INFO

    $endPoint =  "/api/2.0/secrets/scopes/list"
    $SecretScopeAlreadyExists = $false
    $SecretScopes = InvokeRestAPICall -EndPoint $endPoint -Method "GET" -ErrorMessage "Unable to fetch secret scope, remaining steps will be skipped."
   
    if($SecretScopes -ne $null -and ("scopes" -in $SecretScopes.PSobject.Properties.Name) -and ($SecretScopes.scopes | Measure-object).Count -gt 0)
    {
     $SecretScope = $SecretScopes.scopes | where {$_.name -eq $SecretScopeName}
     if($SecretScope -ne $null -and ( $SecretScope | Measure-Object).count -gt 0)
     {
        $SecretScopeAlreadyExists = $true
     }
    }
    
    # Create Secret Scope if not already exists
    if(-not $SecretScopeAlreadyExists)
    {
        Write-Host "Secret scope [$SecretScopeName] doesn't exist in the workspace. Please install AzSK for your cluster using Install-AzSKContinuousAssuranceForCluster first." -ForegroundColor $ERR
        return
    }
    
    # end region

    # region Step 2: PUT Token in Secret Scope
    
    if($newPAT -ne "") {
        Insert-StuffIntoDB -SecretScopeName $SecretScopeName -SecretKeyName $SecretKeyName -Secret $newPAT
    }

    if ($InstrumentationKey -ne "") {
        Insert-StuffIntoDB -SecretScopeName $SecretScopeName -SecretKeyName $IKName -Secret $InstrumentationKey
    }
    
    # end region

    # region Step 3: Set up AzSk Notebook in Databricks workspace

    # Create AzSK folder in user workspace, if folder already exists it will do nothing

    $endPoint = "/api/2.0/workspace/mkdirs"
     
     $body = @{
     "path" = $NotebookFolderPath
    }

    $bodyJson  = $body | ConvertTo-Json

    $ResponseObject = InvokeRestAPICall -EndPoint $endPoint -Method "POST" -Body $bodyJson -ErrorMessage "Unable to create folder in workspace, remaining steps will be skipped."

    # Download notebook from server and store it in temp location

    $filePath = $env:TEMP + "\AzSK_CA_Scan_Notebook.ipynb"
    Invoke-RestMethod  -Method Get -Uri $NotebookUrl -OutFile $filePath
    $fileContent = get-content $filePath
    $fileContentBytes = [System.Text.Encoding]::UTF8.GetBytes($fileContent)
    $fileContentEncoded = [System.Convert]::ToBase64String($fileContentBytes)

    # Import notebook in user workspace,

    $params = @{
      'path' = $NotebookFolderPath + '/AzSK_CA_Scan_Notebook';
      'format' = 'JUPYTER';
      'language' =  'PYTHON';
      'content'=  $fileContentEncoded;
      'overwrite' = 'true'
    }


    $bodyJson = $params | ConvertTo-Json
    $endPoint = "/api/2.0/workspace/import"
    Write-Host "Uploading AzSK Scan Notebook into the workspace" -ForegroundColor $INFO
    $ResponseObject = InvokeRestAPICall -EndPoint $endPoint -Method "POST" -Body $bodyJson -ErrorMessage "Unable to import notebook in workspace, remaining steps will be skipped."
    Write-Host "Successfully imported AzSK_CA_Scan_Notebook." -ForegroundColor $INFO

    #cleanup notebook from temp location

    Remove-Item $filePath -ErrorAction Ignore

    #end region

    #region Step 4: Schedule Notebook to run periodically,

    # Check if Job already exists
    if ($newSchedule -ne "") {
        Write-Host "Checking if CA Scan job exists in the workspace" -ForegroundColor $INFO
        $JobAlreadyExists = $false
        $endPoint =  "/api/2.0/jobs/list"
        $JobList = InvokeRestAPICall -EndPoint $endPoint -Method "GET" -ErrorMessage "Unable to list jobs in workspace, remaining steps will be skipped."

        if($JobList -ne $null -and ("jobs" -in $JobList.PSobject.Properties.Name) -and ($JobList.jobs | Measure-object).Count -gt 0)
        {
         $AzSKJobs = $JobList.jobs  | where {$_.settings.name -eq 'AzSK_CA_Scan_Job'}
         if($AzSKJobs -ne $null -and ( $AzSKJobs | Measure-Object).count -gt 0)
         {
            $JobAlreadyExists = $true
            Write-Host "Found AzSK_CA_Scan_Job in the workspace" -ForegroundColor $INFO_IMP
         }
        }

        # Create Job if not already exist
        if(-not $JobAlreadyExists)
        {
            Write-Host "Databricks job alread doesn't exist, so can't be updated. Please make a fresh install using Install-AzSKContinuousAssuranceForCluster -ResourceType Databricks." -ForegroundColor $ERR
        } else {
            # Delete existing job/jobs
            $delEndPoint = "/api/2.0/jobs/delete"
            Foreach ($j in $AzSKJobs) {
                Write-Host "Deleting AzSKJob with ID:" $j.job_id -ForegroundColor $INFO
                $jid = @{"job_id" = "$($j.job_id)"} | ConvertTo-Json
                InvokeRestAPICall -EndPoint $delEndPoint -Method "POST" -Body $jid -ErrorMessage "Unable to delete job" 
            }

            # Prepare job schedule
            $Schedule = '"0 0 #h# 1/1 * ? *"'
            $Schedule = $Schedule -replace '\#h\#', $newSchedule
            
            # Create job
            Write-Host "Creating Job 'AzSK_CA_Scan_Job' in the workspace" -ForegroundColor $INFO
            $JobConfigServerUrl = $ConfigBaseUrl + "DatabricksCAScanJobConfig.json"
            $filePath = $env:TEMP + "\DatabricksCAScanJobConfig.json"
            Invoke-RestMethod  -Method Get -Uri $JobConfigServerUrl -OutFile $filePath 
            # Bootstrap basic properties like App Insight Key and job schedule in deployment file
            (Get-Content $filePath) -replace '\#Schedule\#', $Schedule | Set-Content $filePath -Force

            $body = Invoke-RestMethod  -Method Get -Uri $filePath
            $bodyJson  = $body | ConvertTo-Json
            $endPoint = "/api/2.0/jobs/create"
            $ResponseObject = InvokeRestAPICall -EndPoint $endPoint -Method "POST" -Body $bodyJson -ErrorMessage "Unable to create AzSK_CA_Scan_Job in workspace."
            Write-Host "Successfully created job 'AzSK_CA_Scan_Job' with Job ID: $($ResponseObject.job_id)." -ForegroundColor $succ
            
        }
    } else {
        Write-Host "Skipping schedule update" -ForegroundColor $INFO
    }
    Write-Host "AzSK Continuous Assurance update completed." -ForegroundColor $SUCC
    #end region

}

function Check-SecretPresentInDB($SecretName, $SecretKey, $response) {
    # Write-Host "Checking if $SecretName is present in the cluster" -ForegroundColor $INFO
    if ($response.secrets.key.Contains($SecretKey)) {
        # Write-Host "$SecretName present in the cluster" -ForegroundColor $SUCC
        return $true
    } else {
        Write-Host "$SecretName absent in the cluster" -ForegroundColor $ERR
        return $false
    }

}

function Get-CADB() {
    $listEP = "/api/2.0/secrets/list?scope=AzSK_CA_Secret_Scope"
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
    Write-Host "Input the following parameters"
    $sid = Read-Host -Prompt "Subscription ID"
    Set-AzContext -SubscriptionId $sid *> $null
    $res_name = Read-Host -Prompt 'Databricks Workspace Name'
    $rg_name = Read-Host -Prompt "Databricks Resource Group Name"
    $response = Get-AzResource -Name $res_name -ResourceGroupName $rg_name

    $response = $response | Where-Object{$_.ResourceType -eq "Microsoft.Databricks/workspaces"}
    # wrong name entered, no resource with that name found
    if ($response -eq $null) {
        Write-Host "Error: Resource $res_name not found in current subscription. Please recheck" -ForegroundColor $ERR
        return
    }
    $PAT = Read-Host -Prompt 'Personal Access Token(PAT)'
    $PersonalAccessToken = $PAT.Trim()
    $scopebody = @{"scope" = "AzSK_CA_Secret_Scope"} | ConvertTo-Json
    $WorkSpaceBaseUrl = "https://" +  $response.Location + ".azuredatabricks.net"
    $response = InvokeRestAPICall -EndPoint $listEP -Method "GET" -ErrorMessage "Unable to fetch secrets. Please check if CA instance is present"
    if ($response -eq $null) {
        return;
    }
    Write-Host "Checking if runtime permissions are present"
    
    $res = Check-SecretPresentInDB -SecretName "AzSK Scan Key" -SecretKey "AzSK_CA_Scan_Key" -response $response
    $res = $res -and (Check-SecretPresentInDB -SecretName "Databricks Host Name" -SecretKey "DatabricksHostDomain" -response  $response)
    $res = $res -and (Check-SecretPresentInDB -SecretName "Resource Name" -SecretKey "res_name" -response  $response)
    $res = $res -and (Check-SecretPresentInDB -SecretName "Resource Group Name" -SecretKey "rg_name" -response  $response)
    $res = $res -and (Check-SecretPresentInDB -SecretName "Subscription ID" -SecretKey "sid" -response  $response)
    $foo = Check-SecretPresentInDB -SecretName "Application Insight Key" -SecretKey "AzSK_AppInsight_Key" -response  $response
    if ($res) {
        Write-Host "All required permissions present" -ForegroundColor $SUCC;
    } else {
        Write-Host "Not all required permissions present. CA might not function properly" -ForegroundColor $ERR;
    }
}


function Remove-CADB() {
    $workspace = "/api/2.0/workspace/get-status?path=/AzSK"
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
    Write-Host "Input the following parameters"
    $sid = Read-Host -Prompt "Subscription ID"
    Set-AzContext -SubscriptionId $sid *> $null
    $res_name = Read-Host -Prompt 'Databricks Workspace Name'
    $rg_name = Read-Host -Prompt "Databricks Resource Group Name"
    $response = Get-AzResource -Name $res_name -ResourceGroupName $rg_name

    $response = $response | Where-Object{$_.ResourceType -eq "Microsoft.Databricks/workspaces"}
    # wrong name entered, no resource with that name found
    if ($response -eq $null) {
        Write-Host "Error: Resource $res_name not found in current subscription. Please recheck" -ForegroundColor $ERR
        return
    }
    $PAT = Read-Host -Prompt 'Input Personal Access Token(PAT)'
    $PersonalAccessToken = $PAT.Trim()
    $scopebody = @{"scope" = "AzSK_CA_Secret_Scope"} | ConvertTo-Json
    $WorkSpaceBaseUrl = "https://" +  $response.Location + ".azuredatabricks.net"
    
    $response = InvokeRestAPICall -EndPoint $workspace -Method "GET" -ErrorMessage "Unable to fetch workspace."
    
    if ($response.path -eq "/AzSK") {
        Write-Host "Found AzSK Workspace" -ForegroundColor $INFO
    } else {
        Write-Host "Couldn't find AzSK Workspace, please check and retry" -ForegroundColor $ERR
        #return
    }
    
    $removeBody = @{
        "path" = "/AzSK";
        "recursive" = "true";
    }

    $removeBody = $removeBody | ConvertTo-Json
    $removeEP = "/api/2.0/workspace/delete"
    Write-Host "Removing AzSK Workspace" -ForegroundColor $INFO
    
    $response = InvokeRestAPICall -EndPoint $removeEP -Method "POST" -Body $removeBody -ErrorMessage "Unable to fetch workspace. Please retry"
    Write-Host "Deleted workspace succesfully" -ForegroundColor $SUCC
    $secretscopeEP = "/api/2.0/secrets/scopes/list"
    Write-Host "Checking if secret scope exists"
    $response = InvokeRestAPICall -EndPoint $secretscopeEP -Method "GET" -ErrorMessage "Unable to fetch secret scopes. Please retry"
    $azskscope = $response.scopes | Where-Object {$_.name -eq "AzSK_CA_Secret_Scope"}
    if ($azskscope -eq $null) {
        Write-Host "Secret scope was not found. Please retry"
        return;
    } else {
        $deleteEP = "/api/2.0/secrets/scopes/delete"
        $deleteBody = @{
            "scope" = "AzSK_CA_Secret_Scope";
        } | ConvertTo-Json
        $response = InvokeRestAPICall -EndPoint $deleteEP -Method "POST" -Body $deleteBody -ErrorMessage "Unable to delete secret scope. Please retry"
        Write-Host "Deleted Secret Scope"
    }
    Write-Host "Finished cleaning up AzSK files" -ForegroundColor $SUCC
    Write-Host "Log files aren't deleted and can be found in the /AzSK_Logs/ folder" -ForegroundColor $SUCC
}

function Setup-HDInsight($Force) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
    $NotebookUrl = 'https://azsdkdataoss.blob.core.windows.net/azsdk-configurations/recmnds/AzSK_HDI.ipynb'
    $filePath = $env:TEMP + "\AzSK_CA_Scan_Notebook.ipynb"
    Write-Host "Input the following parameters"
    # Download notebook
    Invoke-RestMethod  -Method Get -Uri $NotebookUrl -OutFile $filePath
    $sid = (Read-Host -Prompt "Subscription ID").Trim()
    $clusterName = (Read-Host -Prompt "HDInsight Cluster Name").Trim()
    $IK = (Read-Host -Prompt "AppInsight Instrumentation Key (press enter to skip)").Trim()

    Set-AzContext -SubscriptionId $sid > $null

    # Get cluster context
    
    $cluster = Get-AzHDInsightCluster -ClusterName $clusterName -ErrorAction Ignore
    if ($cluster -eq $null){ 
        Write-Host "HDInsight cluster [$clusterName] wasn't found. Please retry" -ForegroundColor $ERR
        retrun;
    }
    $resourceGroup = $cluster.ResourceGroup
    Write-Host "Connecting to cluster storage account" -ForegroundColor $INFO
    # Extracting Storage Account
    $storageAccount = $cluster.DefaultStorageAccount.Split(".")[0]
    $sac = Get-AzStorageAccount -Name $storageAccount -ResourceGroupName $resourceGroup -ErrorAction Ignore
    while ($sac -eq $null) {
        Write-Host "Storage [$storageAccount] not found in resource group [$resourceGroup]."
        $newRGName = Read-Host -Prompt "Enter the resource group name where [$storageAccount] is"
        $sac = Get-AzStorageAccount -Name $storageAccount -ResourceGroupName $newRGName
    }
    
    $context = $sac.Context
    $container = $cluster.DefaultStorageContainer
    $rg_name = $cluster.ResourceGroup
    $res_name = $cluster.Name

    # Replace key in Notebook
    (Get-Content $FilePath) -replace '\#AI_KEY\#' , $IK | Set-Content $FilePath -Force
    (Get-Content $FilePath) -replace '\#SID\#' , $sid | Set-Content $FilePath -Force
    (Get-Content $FilePath) -replace '\#RG_NAME\#' , $rg_name | Set-Content $FilePath -Force
    (Get-Content $FilePath) -replace '\#RES_NAME\#' , $res_name | Set-Content $FilePath -Force
        
    Write-Host "Setting Subscription Context" -ForegroundColor $INFO 


    # Action Script to install AzSKPy
    $scriptActionUri = "https://azsdkdataoss.blob.core.windows.net/azsdk-configurations/recmnds/pipinstall.sh"
    
    # Install on both head, and worker nodes
    $nodeTypes = "headnode", "workernode"
    $scriptActionName = "AzSKInstaller-" + (Get-Date -f MM-dd-yyyy-HH-mm-ss)
    
    Write-Host "Uploading AzSK Scan Notebook to the cluster" -ForegroundColor $INFO
    # Upload the notebook
    Set-AzStorageBlobContent -File $filePath -Blob "HdiNotebooks/PySpark/AzSK_CA_Scan_Notebook.ipynb" -Container $container -Context $context | Out-Null
    $isAZSKInstalled = $false
    
    
    Write-Host "Checking previous installation of AzSKPy is present" -ForegroundColor $INFO
    # Check if AzSKPy is already installed by looking at the action script history
    $res = Get-AzHDInsightScriptActionHistory -ClusterName $clusterName
    
    foreach($i in $res) {
        if ($i.Name -match "AzSKInstaller") {
            $isAZSKInstalled = $true
        }
    }
    
    if ($Force) {
        Write-Host "Forcing AzSKPy reinstallation, if present" -ForegroundColor Cyan
    }

    # if AzSKPy is not present, install it
    if (-not $isAZSKInstalled -or $Force) {
        Write-Host "Installing AzSKPy on the cluster" -ForegroundColor $INFO
        Submit-AzHDInsightScriptAction -ClusterName $clusterName `
                                            -Name $scriptActionName `
                                            -Uri $scriptActionUri `
                                            -NodeTypes $nodeTypes `
                                            -PersistOnSuccess > $null
    }

    if (-not $Force -and $isAZSKInstalled) {
        Write-Host "AzSKPy already found in install history. Skipping Installation" -ForegroundColor $ERR
        return
    }


    Write-Host "AzSK Continuous Assurance setup completed." -ForegroundColor $SUCC
    Write-Host "Your cluster will be scanned periodically by AzSK CA." -ForegroundColor $INFO
    Write-Host "To trigger the job, please go to your clusters Jupyter Notebooks/PySpark/AzSK_CA_Scan_Notebook.ipynb and 'Run All'." -ForegroundColor $INFO
    Write-Host "All security control evaluation results will also be sent to App Insight if an instrumentation key was provided during setup above." -ForegroundColor $INFO
    Write-Host "For more info, please see docs: https://aka.ms/devopskit/inclusterca" -ForegroundColor $INFO
}


function Update-HDInsight($Force) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
    $NotebookUrl = 'https://azsdkdataoss.blob.core.windows.net/azsdk-configurations/recmnds/AzSK_HDI.ipynb'
    $filePath = $env:TEMP + "\AzSK_CA_Scan_Notebook.ipynb"
    Write-Host "Input the following parameters"
    # Download notebook
    Invoke-RestMethod  -Method Get -Uri $NotebookUrl -OutFile $filePath
    $sid = (Read-Host -Prompt "Subscription ID").Trim()
    $clusterName = (Read-Host -Prompt "HDInsight Cluster Name").Trim()
    $IK = (Read-Host -Prompt "AppInsight Instrumentation Key (press enter to skip)").Trim()

    Set-AzContext -SubscriptionId $sid > $null

    # Get cluster context
    $cluster = Get-AzHDInsightCluster -ClusterName $clusterName
    $resourceGroup = $cluster.ResourceGroup
    
    Write-Host "Connecting to cluster storage account" -ForegroundColor $INFO
    # Extracting Storage Account
    $storageAccount = $cluster.DefaultStorageAccount.Split(".")[0]
    $sac = Get-AzStorageAccount -Name $storageAccount -ResourceGroupName $resourceGroup -ErrorAction Ignore
    while ($sac -eq $null) {
        Write-Host "Storage [$storageAccount] not found in resource group [$resourceGroup]."
        $newRGName = Read-Host -Prompt "Enter the resource group name where [$storageAccount] is"
        $sac = Get-AzStorageAccount -Name $storageAccount -ResourceGroupName $newRGName
    }
    
    $context = $sac.Context
    $container = $cluster.DefaultStorageContainer
    $rg_name = $cluster.ResourceGroup
    $res_name = $cluster.Name

    # Replace key in Notebook
    (Get-Content $FilePath) -replace '\#AI_KEY\#' , $IK | Set-Content $FilePath -Force
    (Get-Content $FilePath) -replace '\#SID\#' , $sid | Set-Content $FilePath -Force
    (Get-Content $FilePath) -replace '\#RG_NAME\#' , $rg_name | Set-Content $FilePath -Force
    (Get-Content $FilePath) -replace '\#RES_NAME\#' , $res_name | Set-Content $FilePath -Force
        
    Write-Host "Setting Subscription Context" -ForegroundColor $INFO 

    # Action Script to install AzSKPy
    $installScript = "https://azsdkdataoss.blob.core.windows.net/azsdk-configurations/recmnds/pipinstall.sh"
    $uninstallScript = "https://azsdkdataoss.blob.core.windows.net/azsdk-configurations/recmnds/uninstall.sh"
    # Install on both head, and worker nodes
    $nodeTypes = "headnode", "workernode"
    $installActionName = "AzSKInstaller-" + (Get-Date -f MM-dd-yyyy-HH-mm-ss)
    $uninstallActionName = "AzSKUnInstaller-" + (Get-Date -f MM-dd-yyyy-HH-mm-ss)
    Write-Host "Uploading AzSK Scan Notebook to the cluster" -ForegroundColor $INFO
    # Upload the notebook
    Set-AzStorageBlobContent -File $filePath -Blob "HdiNotebooks/PySpark/AzSK_CA_Scan_Notebook.ipynb" -Container $container -Context $context | Out-Null
    $isAZSKInstalled = $false
    
    
    Write-Host "Checking previous installation of AzSKPy is present" -ForegroundColor $INFO
    # Check if AzSKPy is already installed by looking at the action script history
    $res = Get-AzHDInsightScriptActionHistory -ClusterName $clusterName
    
    Write-Host "Unstalling AzSKPy on the cluster" -ForegroundColor $INFO
    Submit-AzHDInsightScriptAction -ClusterName $clusterName `
                                            -Name $uninstallActionName `
                                            -Uri $uninstallScript `
                                            -NodeTypes $nodeTypes `
                                            -PersistOnSuccess > $null

    Write-Host "Installing newer AzSKPy on the cluster" -ForegroundColor $INFO
    Submit-AzHDInsightScriptAction -ClusterName $clusterName `
                                            -Name $installActionName `
                                            -Uri $installScript `
                                            -NodeTypes $nodeTypes `
                                            -PersistOnSuccess > $null


    Write-Host "AzSK Continuous Assurance update completed." -ForegroundColor $SUCC
}


function Remove-CAHD() {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
    Write-Host "Input the following parameters"
    $sid = (Read-Host -Prompt "Subscription ID").Trim()
    $clusterName = (Read-Host -Prompt "HDInsight Cluster Name").Trim()
    Set-AzContext -SubscriptionId $sid > $null

    # Get cluster context
    $cluster = Get-AzHDInsightCluster -ClusterName $clusterName
    $resourceGroup = $cluster.ResourceGroup
    
    Write-Host "Connecting to cluster storage account" -ForegroundColor $INFO
    # Extracting Storage Account
    $storageAccount = $cluster.DefaultStorageAccount.Split(".")[0]
    $sac = Get-AzStorageAccount -Name $storageAccount -ResourceGroupName $resourceGroup -ErrorAction Ignore
    while ($sac -eq $null) {
        Write-Host "Storage [$storageAccount] not found in resource group [$resourceGroup]."
        $newRGName = Read-Host -Prompt "Enter the resource group name where [$storageAccount] is"
        $sac = Get-AzStorageAccount -Name $storageAccount -ResourceGroupName $newRGName
    }
    
    $context = $sac.Context
    $container = $cluster.DefaultStorageContainer
    $rg_name = $cluster.ResourceGroup
    $res_name = $cluster.Name
        
    Write-Host "Setting Subscription Context" -ForegroundColor $INFO 

    # Action Script to uninstall AzSKPy
    $uninstallScript = "https://azsdkdataoss.blob.core.windows.net/azsdk-configurations/recmnds/uninstall.sh"
    # Uninstall on both head, and worker nodes
    $nodeTypes = "headnode", "workernode"
    $uninstallActionName = "AzSKUnInstaller-" + (Get-Date -f MM-dd-yyyy-HH-mm-ss)

    Write-Host "Uninstalling AzSKPy on the cluster" -ForegroundColor $INFO
    Submit-AzHDInsightScriptAction -ClusterName $clusterName `
                                            -Name $uninstallActionName `
                                            -Uri $uninstallScript `
                                            -NodeTypes $nodeTypes `
                                            -PersistOnSuccess > $null

    Remove-AzStorageBlob -Blob "HdiNotebooks/PySpark/AzSK_CA_Scan_Notebook.ipynb" -Container $container -Context $context
    Write-Host "AzSK Continuous Assurance uninstall completed." -ForegroundColor $SUCC


}


function Get-CAHD() {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
    Write-Host "Input the following parameters"
    $sid = (Read-Host -Prompt "Subscription ID").Trim()
    $clusterName = (Read-Host -Prompt "HDInsight Cluster Name").Trim()
    Set-AzContext -SubscriptionId $sid > $null

    # Get cluster context
    $cluster = Get-AzHDInsightCluster -ClusterName $clusterName
    $resourceGroup = $cluster.ResourceGroup
    
    Write-Host "Connecting to cluster storage account" -ForegroundColor $INFO
    # Extracting Storage Account
    $storageAccount = $cluster.DefaultStorageAccount.Split(".")[0]
    $sac = Get-AzStorageAccount -Name $storageAccount -ResourceGroupName $resourceGroup -ErrorAction Ignore

    while ($sac -eq $null) {
        Write-Host "Storage [$storageAccount] not found in resource group [$resourceGroup]."
        $newRGName = Read-Host -Prompt "Enter the resource group name where [$storageAccount] is"
        $sac = Get-AzStorageAccount -Name $storageAccount -ResourceGroupName $newRGName
    }
    
    $context = $sac.Context
    $container = $cluster.DefaultStorageContainer
    $rg_name = $cluster.ResourceGroup
    $res_name = $cluster.Name
    $metapathtemp = $env:TEMP + "\azskmetatemp.json"
    $metapath = $env:TEMP + "\azskmeta.json"
    $notebook = Get-AzStorageBlob -Blob "HdiNotebooks/PySpark/AzSK_CA_Scan_Notebook.ipynb" -Container $container -Context $context -ErrorAction Ignore
    if ($notebook -eq $null) {
        Write-Host "CA Health not OK. Either the installation is broken or not present. Please re-install using Install-AzSKContinuousAssuranceForCluster" -ForegroundColor $ERR
        return;
    }
    $list = New-Object System.Collections.Generic.List[System.Object]
    $filesList = Get-AzStorageBlob -Blob "" -Container $container -Context $context
    foreach ($x in $filesList.Name) {
        if ($x.Contains("AzSK_Meta") -and $x.Contains("part") -and $x.Contains("json")) {
            $content = Get-AzStorageBlob -Blob $x -Container $container -Context $context
            if ($content.Length -gt 0) {
                $list.Add($content)
            }
        }
    }

    if ($list.Count -eq 0) {
        Write-Host "Required information not found. Please check if AzSK CA is installed on the cluster" -ForegroundColor $ERR
    } else {
        $sortedList = $list | Sort LastModified -Descending
        $res = Get-AzStorageBlobContent -Blob $sortedList[0].Name -Container $container -Context $context -Destination $metapath -Force
        $json = (Get-Content -Path $metapath)
        $json = $json | ConvertFrom-Json
        Write-Host "CA Health OK. Following is the summary" -ForegroundColor $SUCC
        $json
    }
}



function Install-AzSKContinuousAssuraceForCluster
{
	Param(

		[ValidateSet("Databricks", "Kubernetes", "HDInsight")] 
        [Parameter(Mandatory = $true, HelpMessage="TBD")]
		[Alias("rt")]
		$ResourceType,
        
        [switch]
		$Force
    )

	if ($ResourceType -eq "Databricks"){
       Setup-DataBricks
    } elseif($ResourceType -eq "HDInsight" -and $Force)
    {
       Setup-HDInsight $true
    } else {
       Setup-HDInsight
    }
    
}


function Get-AzSKContinuousAssuraceForCluster
{
	Param(

		[ValidateSet("Databricks", "HDInsight")] 
        [Parameter(Mandatory = $true, HelpMessage="TBD")]
		[Alias("rt")]
		$ResourceType
    )

	if ($ResourceType -eq "Databricks"){
       Get-CADB
    } elseif ($ResourceType -eq "HDInsight") {
       Get-CAHD
    }
    
}

function Update-AzSKContinuousAssuraceForCluster
{
	Param(

		[ValidateSet("Databricks", "HDInsight")] 
        [Parameter(Mandatory = $true, HelpMessage="TBD")]
		[Alias("rt")]
		$ResourceType
    )

	if ($ResourceType -eq "Databricks"){
       Update-DataBricks
    } elseif ($ResourceType -eq "HDInsight") {
       Update-HDInsight
    }
    
}

function Remove-AzSKContinuousAssuraceForCluster
{
	Param(

		[ValidateSet("Databricks", "HDInsight")] 
        [Parameter(Mandatory = $true, HelpMessage="TBD")]
		[Alias("rt")]
		$ResourceType
    )

	if ($ResourceType -eq "Databricks"){
       Remove-CADB
    } elseif ($ResourceType -eq "HDInsight") {
       Remove-CAHD
    }
    
}
