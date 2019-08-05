function Read-Input($msg) {
    return (Read-Host -Prompt $msg).Trim()
}

function Get-DatabricksParameters() {    
    if([string]::IsNullOrEmpty($SubscriptionId) -or 
        [string]::IsNullOrEmpty($WorkspaceName) -or
        [string]::IsNullOrEmpty($ResourceGroupName) -or
        [string]::IsNullOrEmpty($PersonalAccessToken)) {
        Write-Host "Input the following parameters"
        if ([string]::IsNullOrEmpty($SubscriptionId)) {
            $SubscriptionId = Read-Input "Subscription ID"
        }
        if ([string]::IsNullOrEmpty($WorkspaceName)) {
            $WorkspaceName = Read-Input "Databricks Workspace Name"
        }
        if ([string]::IsNullOrEmpty($ResourceGroupName)) {
            $ResourceGroupName = Read-Input "Databricks Resource Group Name"
        }
        if ([string]::IsNullOrEmpty($PersonalAccessToken)) {
            $PersonalAccessToken = Read-Input "Personal Access Token(PAT)"
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
        "PersonalAccessToken" = $PersonalAccessToken;
        "WorkspaceBaseUrl" = $WorkspaceBaseUrl
    }
}

function Get-HDInsightParameters {
    if([string]::IsNullOrEmpty($SubscriptionId) -or 
        [string]::IsNullOrEmpty($ClusterName) -or
        [string]::IsNullOrEmpty($ResourceGroupName)) {

        Write-Host "Input the following parameters"
        if ([string]::IsNullOrEmpty($SubscriptionId)) {
            $SubscriptionId = Read-Input "Subscription ID"
        }
        if ([string]::IsNullOrEmpty($ClusterName)) {
            $ClusterName = Read-Input "HDInsight Cluster Name"
        }
        if ([string]::IsNullOrEmpty($ResourceGroupName)) {
            $ResourceGroupName = Read-Input "HDInsight Resource Group Name"
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
        "SubscriptionId" = $SubscriptionId;
        "StorageAccountContext" = $StorageAccountContext.Context;
        "Container" = $Cluster.DefaultStorageContainer;
        "ResourceGroup" = $Cluster.ResourceGroup;
        "ClusterName" = $Cluster.Name;
    }
}


function Get-AzSKContinuousAssuranceForCluster {
    Param(
        [string]
        [ValidateSet("HDInsight", "Databricks")]
        [Alias("rt")]
        $ResourceType,

        [string]
        [Alias("sid")]
        $SubscriptionId,

        [string]
        [Alias("wsn")]
        $WorkspaceName,
        
        [string]
        [Alias("cn")]
        $ClusterName,

        [string]
        [Alias("rgn")]
        $ResourceGroupName,

        [string]
        [Alias("pat")]
        $PersonalAccessToken
    )

    Begin{
        [CommandHelper]::BeginCommand($MyInvocation);
        [ListenerHelper]::RegisterListeners();         
    }
    Process {
        try {
            if ($ResourceType -eq "Databricks") {
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
                $ResourceContext = Get-DatabricksParameters
                $CAInstance = [CAForDatabricks]::new($ResourceContext, $MyInvocation)
                $CAInstance.InvokeFunction($CAInstance.GetCA)
            }
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }
    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }
}


function Install-AzSKContinuousAssuranceForCluster{
    Param(
        [string]
        [ValidateSet("HDInsight", "Databricks")]
        [Alias("rt")]
        $ResourceType,

        [string]
        [Alias("sid")]
        $SubscriptionId,

        [string]
        [Alias("wsn")]
        $WorkspaceName,

        [string]
        [Alias("cn")]
        $ClusterName,

        [string]
        [Alias("rgn")]
        $ResourceGroupName,

        [string]
        [Alias("pat")]
        $PersonalAccessToken,

        [string]
        [Alias("aik")]
        $InstrumentationKey,

        [string]
        [Alias("lawsid")]
        $LAWorkspaceId,

        [string]
        [Alias("lasec")]
        $LASharedSecret
    )

    Begin{
        [CommandHelper]::BeginCommand($MyInvocation);
        [ListenerHelper]::RegisterListeners();         
    }
    Process {
        try {
            if ($ResourceType -eq "Databricks") {
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
                $ResourceContext = Get-DatabricksParameters
                $ResourceContext.InstrumentationKey = $InstrumentationKey
                $ResourceContext.LAWorkspaceId = $LAWorkspaceId
                $ResourceContext.LASharedSecret = $LASharedSecret
                $CAInstance = [CAForDatabricks]::new($ResourceContext, $MyInvocation)
                $CAInstance.InvokeFunction($CAInstance.InstallCA)
            } elseif ($Resourcetype -eq "HDInsight") {
                $ResourceContext = Get-HDInsightParameters
                $ResourceContext.InstrumentationKey = $InstrumentationKey
                $CAInstance = [CAForHDInsight]::new($ResourceContext, $MyInvocation)
                $CAInstance.InvokeFunction($CAInstance.InstallCA)
            }
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }
    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }
}

function Update-AzSKContinuousAssuranceForDatabricks{
    Param(
        [string]
        [Alias("sid")]
        $SubscriptionId,

        [string]
        [Alias("wsn")]
        $WorkspaceName,

        [string]
        [Alias("rgn")]
        $ResourceGroupName,

        [string]
        [Alias("pat")]
        $PersonalAccessToken,

        [string]
        [Alias("npat")]
        $NewPersonalAccessToken,

        [string]
        [Alias("naik")]
        $NewAppInsightKey,

        [string]
        [Alias("nsed")]
        $NewSchedule

    )

    Begin{
        [CommandHelper]::BeginCommand($MyInvocation);
        [ListenerHelper]::RegisterListeners();         
    }
    Process {
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
            $ResourceContext = Get-DatabricksParameters
            $CAInstance = [CAForDatabricks]::new($ResourceContext, $MyInvocation)
            $CAInstance.InvokeFunction($CAInstance.UpdateCA, @($NewPersonalAccessToken, 
                                       $NewAppInsightKey, $NewSchedule))
        } catch {
            [EventBase]::PublishGenericException($_);
        }
    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }
}

function Remove-AzSKContinuousAssuranceForCluster {
    Param(
        [string]
        [ValidateSet("HDInsight", "Databricks")]
        [Alias("rt")]
        $ResourceType,

        [string]
        [Alias("sid")]
        $SubscriptionId,

        [string]
        [Alias("wsn")]
        $WorkspaceName,

        [string]
        [Alias("cn")]
        $ClusterName,

        [string]
        [Alias("rgn")]
        $ResourceGroupName,

        [string]
        [Alias("pat")]
        $PersonalAccessToken
    )
    Begin{
        [CommandHelper]::BeginCommand($MyInvocation);
        [ListenerHelper]::RegisterListeners();         
    }
    Process {
        try {
            if ($ResourceType -eq "Databricks") {
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
                $ResourceContext = Get-DatabricksParameters
                $CAInstance = [CAForDatabricks]::new($ResourceContext, $MyInvocation)
                $CAInstance.InvokeFunction($CAInstance.RemoveCA)              
            } elseif ($ResourceType -eq "HDInsight") {
                $ResourceContext = Get-HDInsightParameters
                $CAInstance = [CAForHDInsight]::new($ResourceContext, $MyInvocation)
                $CAInstance.InvokeFunction($CAInstance.RemoveCA)  
            }
        } catch {
            [EventBase]::PublishGenericException($_);
        }
    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }
}
