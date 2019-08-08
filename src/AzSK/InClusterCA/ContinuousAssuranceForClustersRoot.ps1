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
                $ResourceContext = [DatabricksClusterCA]::GetParameters($SubscriptionId, $WorkspaceName, $ResourceGroupName, $PersonalAccessToken)
                $CAInstance = [DatabricksClusterCA]::new($ResourceContext, $MyInvocation)
                $CAInstance.InvokeFunction($CAInstance.GetCA)
            } elseif($ResourceType -eq "HDInsight") {
                $ResourceContext = [HDInsightClusterCA]::GetParameters($SubscriptionId, $ClusterName, $ResourceGroupName)
                $CAInstance = [HDInsightClusterCA]::new($ResourceContext, $MyInvocation)
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
                $ResourceContext = [DatabricksClusterCA]::GetParameters($SubscriptionId, $WorkspaceName, $ResourceGroupName, $PersonalAccessToken)
                $ResourceContext.InstrumentationKey = $InstrumentationKey
                $ResourceContext.LAWorkspaceId = $LAWorkspaceId
                $ResourceContext.LASharedSecret = $LASharedSecret
                $CAInstance = [DatabricksClusterCA]::new($ResourceContext, $MyInvocation)
                $CAInstance.InvokeFunction($CAInstance.InstallCA)
            } elseif ($Resourcetype -eq "HDInsight") {
                $ResourceContext = [HDInsightClusterCA]::GetParameters($SubscriptionId, $ClusterName, $ResourceGroupName)
                $ResourceContext.InstrumentationKey = $InstrumentationKey
                $CAInstance = [HDInsightClusterCA]::new($ResourceContext, $MyInvocation)
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

function Update-AzSKContinuousAssuranceForCluster{
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
        $NewSchedule,

        [string]
        [Alias("lawsid")]
        $NewLAWorkspaceId,

        [string]
        [Alias("lasec")]
        $NewLASharedSecret

    )

    Begin{
        [CommandHelper]::BeginCommand($MyInvocation);
        [ListenerHelper]::RegisterListeners();         
    }
    Process {
        try {
            if ($ResourceType -eq "Databricks") {
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
                $ResourceContext = [DatabricksClusterCA]::GetParameters($SubscriptionId, $WorkspaceName, $ResourceGroupName, $PersonalAccessToken)
                $CAInstance = [DatabricksClusterCA]::new($ResourceContext, $MyInvocation)
                $CAInstance.InvokeFunction($CAInstance.UpdateCA, @($NewPersonalAccessToken, 
                                        $NewAppInsightKey, $NewSchedule))
            } elseif ($Resourcetype -eq "HDInsight") {
                $ResourceContext = [HDInsightClusterCA]::GetParameters($SubscriptionId, $ClusterName, $ResourceGroupName)
                $ResourceContext.InstrumentationKey = $NewAppInsightKey
                $ResourceContext.LAWorkspaceId = $NewLAWorkspaceId
                $ResourceContext.LASharedSecret = $NewLASharedSecret
                $CAInstance = [HDInsightClusterCA]::new($ResourceContext, $MyInvocation)
                $CAInstance.InvokeFunction($CAInstance.UpdateCA)
            }
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
                $ResourceContext = [DatabricksClusterCA]::GetParameters($SubscriptionId, $WorkspaceName, $ResourceGroupName, $PersonalAccessToken)
                $CAInstance = [DatabricksClusterCA]::new($ResourceContext, $MyInvocation)
                $CAInstance.InvokeFunction($CAInstance.RemoveCA)              
            } elseif ($ResourceType -eq "HDInsight") {
                $ResourceContext = [HDInsightClusterCA]::GetParameters($SubscriptionId, $ClusterName, $ResourceGroupName)
                $CAInstance = [HDInsightClusterCA]::new($ResourceContext, $MyInvocation)
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
