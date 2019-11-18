class HDInsightClusterCA : CommandBase {
    [PSObject] $ResourceContext;

    HDInsightClusterCA([PSObject] $ResourceContext, [InvocationInfo] $invocationContext): 
    Base([Constants]::BlankSubscriptionId, $invocationContext) { 
        $this.ResourceContext = $ResourceContext
    }

    static [PSObject] GetParameters($SubscriptionId, $ClusterName, $ResourceGroupName) {
        if([string]::IsNullOrEmpty($SubscriptionId) -or 
            [string]::IsNullOrEmpty($ClusterName) -or
            [string]::IsNullOrEmpty($ResourceGroupName)) {

            Write-Host "Input the following parameters"
            if ([string]::IsNullOrEmpty($SubscriptionId)) {
                $SubscriptionId = [Helpers]::ReadInput("Subscription ID")
            }
            if ([string]::IsNullOrEmpty($ClusterName)) {
                $ClusterName = [Helpers]::ReadInput("HDInsight Cluster Name")
            }
            if ([string]::IsNullOrEmpty($ResourceGroupName)) {
                $ResourceGroupName = [Helpers]::ReadInput("HDInsight Resource Group Name")
            }
        }
        Set-AzContext -SubscriptionId $SubscriptionId *> $null
        $Cluster = Get-AzHDInsightCluster -ClusterName $ClusterName -ErrorAction Ignore
        if ($null -eq $Cluster) { 
            Write-Host "HDInsight cluster [$ClusterName] wasn't found. Please retry" -ForegroundColor Red
            throw $_;
        }
        $ResourceGroup = $cluster.ResourceGroup
        # Extracting Storage Account
        $StorageAccount = $cluster.DefaultStorageAccount.Split(".")[0]
        $StorageAccountContext = Get-AzStorageAccount -Name $storageAccount `
                                    -ResourceGroupName $ResourceGroup `
                                    -ErrorAction Ignore
        while ($null -eq $StorageAccountContext) {
            Write-Host "Storage [$StorageAccount] not found in resource group [$resourceGroup]."
            $NewRGName = Read-Host -Prompt "Enter the resource group name where [$storageAccount] is present."
            $StorageAccountContext = Get-AzStorageAccount -Name $StorageAccount -ResourceGroupName $NewRGName
        }
        return @{
            "SubscriptionId" =          $SubscriptionId;
            "StorageAccountContext" =   $StorageAccountContext.Context;
            "Container" =               $Cluster.DefaultStorageContainer;
            "ResourceGroup" =           $Cluster.ResourceGroup;
            "ClusterName" =             $Cluster.Name;
        }
    }


    [void] UploadAzSKNotebookToCluster() {
        $NotebookUrl = [Constants]::HDInsightCANotebookUrl
        $FilePath = $env:TEMP + "\AzSK_CA_Scan_Notebook.ipynb"
        Invoke-RestMethod  -Method Get -Uri $NotebookUrl -OutFile $filePath
        (Get-Content $FilePath) -replace '\#AI_KEY\#', $this.ResourceContext.InstrumentationKey | Set-Content $FilePath -Force
        (Get-Content $FilePath) -replace '\#SID\#', $this.ResourceContext.SubscriptionId | Set-Content $FilePath -Force
        (Get-Content $FilePath) -replace '\#RG_NAME\#', $this.ResourceContext.ResourceGroup | Set-Content $FilePath -Force
        (Get-Content $FilePath) -replace '\#RES_NAME\#', $this.ResourceContext.ClusterName | Set-Content $FilePath -Force
        Set-AzStorageBlobContent -File $FilePath -Blob "HdiNotebooks/PySpark/AzSK_CA_Scan_Notebook.ipynb" `
                                -Container $this.ResourceContext.Container `
                                -Context $this.ResourceContext.StorageAccountContext | Out-Null
        Remove-Item $FilePath -ErrorAction Ignore
    }

    [void] RemoveAzSKNotebookFromCluster() {
        Remove-AzStorageBlob -Blob "HdiNotebooks/PySpark/AzSK_CA_Scan_Notebook.ipynb" `
                             -Container $this.ResourceContext.Container `
                             -Context $this.ResourceContext.StorageAccountContext
    }

    [void] InstallAzSKPy() {
        $ScriptActionUri = [Constants]::AzSKPyInstallUrl
        # Install on both head, and worker nodes
        $NodeTypes = "headnode", "workernode"
        $ScriptActionName = "AzSKInstaller-" + (Get-Date -f MM-dd-yyyy-HH-mm-ss)
        Submit-AzHDInsightScriptAction -ClusterName $this.ResourceContext.clusterName `
                                        -Name $ScriptActionName `
                                        -Uri $ScriptActionUri `
                                        -NodeTypes $NodeTypes `
                                        -PersistOnSuccess > $null
        $this.PublishCustomMessage("AzSK python library installed")
    }

    [void] UninstallAzSKPy() {
        $uninstallScript = [Constants]::AzSKPyUninstallUrl
        # Uninstall on both head, and worker nodes
        $nodeTypes = "headnode", "workernode"
        $uninstallActionName = "AzSKUnInstaller-" + (Get-Date -f MM-dd-yyyy-HH-mm-ss)
        $this.PublishCustomMessage("Uninstalling AzSKPy on the cluster")
        Submit-AzHDInsightScriptAction -ClusterName $this.ResourceContext.ClusterName `
                                            -Name $uninstallActionName `
                                            -Uri $uninstallScript `
                                            -NodeTypes $nodeTypes `
                                            -PersistOnSuccess > $null
    }

    [void] InstallCA() {
        $this.PublishCustomMessage("Uploading Notebook to the cluster")
        $this.UploadAzSKNotebookToCluster()
        $this.PublishCustomMessage("Installing AzSK python library in the cluster")
        $this.InstallAzSKPy()
    }

    [void] RemoveCA() {
       # Submit uninstall script
       $this.UninstallAzSKPy()
       # Remove notebook
       $this.RemoveAzSKNotebookFromCluster()
    }

    [void] UpdateCA() {
        $this.PublishCustomMessage("Updating scan Notebook on the cluster")
        $this.UploadAzSKNotebookToCluster()
        $this.PublishCustomMessage("Updating AzSK python library in the cluster")
        # uninstall first
        $this.UninstallAzSKPy()
        # install new version
        $this.InstallAzSKPy()       
    }

    [void] GetCA() {
        $metapathtemp = $env:TEMP + "\azskmetatemp.json"
        $metapath = $env:TEMP + "\azskmeta.json"
        $notebook = Get-AzStorageBlob -Blob "HdiNotebooks/PySpark/AzSK_CA_Scan_Notebook.ipynb" `
                                      -Container $this.ResourceContext.Container `
                                      -Context $this.ResourceContext.StorageAccountContext -ErrorAction Ignore
        if ($notebook -eq $null) {
            $this.PublishCustomMessage("CA Health not OK. Either the installation is broken or not present. Please re-install using Install-AzSKContinuousAssuranceForCluster", [MessageType]::Error)
            return;
        }
        $list = New-Object System.Collections.Generic.List[System.Object]
        $filesList = Get-AzStorageBlob -Blob "" -Container $this.ResourceContext.Container -Context $this.ResourceContext.StorageAccountContext
        foreach ($x in $filesList.Name) {
            if ($x.Contains("AzSK_Meta") -and $x.Contains("part") -and $x.Contains("json")) {
                $content = Get-AzStorageBlob -Blob $x -Container $this.ResourceContext.Container -Context $this.ResourceContext.StorageAccountContext
                if ($content.Length -gt 0) {
                    $list.Add($content)
                }
            }
        }

        if ($list.Count -eq 0) {
            $this.PublishCustomMessage("Required information not found. Please check if AzSK CA is installed on the cluster", [MessageType]::Error)
            $this.PublishCustomMessage("Note that you need to run the scan once to populate the metadata.", [MessageType]::Error)
        } else {
            $sortedList = $list | Sort-Object LastModified -Descending
            $res = Get-AzStorageBlobContent -Blob $sortedList[0].Name -Container $this.ResourceContext.Container -Context $this.ResourceContext.StorageAccountContext -Destination $metapath -Force
            $json = (Get-Content -Path $metapath)
            $json = $json | ConvertFrom-Json
            $this.PublishCustomMessage("CA Health OK. Following is the summary", [MessageType]::Update)
            $this.PublishCustomMessage([Helpers]::ConvertObjectToString($json, $true))
        }        
    }
}