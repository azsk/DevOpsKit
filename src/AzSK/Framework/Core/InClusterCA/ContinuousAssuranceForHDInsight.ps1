class CAForHDInsight : CommandBase {
    [PSObject] $ResourceContext;

    CAForHDInsight([PSObject] $ResourceContext, [InvocationInfo] $invocationContext): 
    Base([Constants]::BlankSubscriptionId, $invocationContext) { 
        $this.ResourceContext = $ResourceContext
    }

    [void] UploadAzSKNotebookToCluster() {
        $NotebookUrl = 'https://azsdkdataoss.blob.core.windows.net/azsdk-configurations/recmnds/AzSK_HDI.ipynb'
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
        $ScriptActionUri = "https://azsdkdataoss.blob.core.windows.net/azsdk-configurations/recmnds/pipinstall.sh"
        # Install on both head, and worker nodes
        $NodeTypes = "headnode", "workernode"
        $ScriptActionName = "AzSKInstaller-" + (Get-Date -f MM-dd-yyyy-HH-mm-ss)
        Submit-AzHDInsightScriptAction -ClusterName $this.ResourceContext.clusterName `
                                        -Name $ScriptActionName `
                                        -Uri $ScriptActionUri `
                                        -NodeTypes $NodeTypes `
                                        -PersistOnSuccess > $null
     
    }

    [void] UninstallAzSKPy() {
        $uninstallScript = "https://azsdkdataoss.blob.core.windows.net/azsdk-configurations/recmnds/uninstall.sh"
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
        } else {
            $sortedList = $list | Sort LastModified -Descending
            $res = Get-AzStorageBlobContent -Blob $sortedList[0].Name -Container $this.ResourceContext.Container -Context $this.ResourceContext.StorageAccountContext -Destination $metapath -Force
            $json = (Get-Content -Path $metapath)
            $json = $json | ConvertFrom-Json
            $this.PublishCustomMessage("CA Health OK. Following is the summary", [MessageType]::Update)
            $json
        }        
    }
}