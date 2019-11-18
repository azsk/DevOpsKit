function Get-AzSKContinuousAssuranceForCluster {
    Param(
        [string]
        [ValidateSet("HDInsight", "Databricks", "Kubernetes")]
        [Parameter(Mandatory = $true, HelpMessage="Friendly name of resource type. e.g.: Kubernetes,HDInight")]
		[Alias("rt")]
        $ResourceType,

        [string]
        [Alias("sid","HostSubscriptionId","hsid","s")]
        [Parameter(Mandatory = $true, HelpMessage="Subscription Id of the cluster for which AzSK Continuous Assurance will be installed.")]
        $SubscriptionId,

        [string]
        [Alias("wsn")]
        $WorkspaceName,
        
        [string]
        [Alias("cn","ResourceName")]
        [Parameter(Mandatory = $false, HelpMessage="Resource Name of the cluster for which AzSK Continuous Assurance will be installed.")]
        $ClusterName,

        [string]
        [Alias("rgn")]
        [Parameter(Mandatory = $true, HelpMessage="ResourceGroup Name of the cluster for which AzSK Continuous Assurance will be installed.")]
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
            }  elseif($ResourceType -eq "Kubernetes") {
                $CAInstance = [KubernetesClusterCA]::new($SubscriptionId, $ResourceGroupName, $ClusterName, $MyInvocation);
                if ($CAInstance) 
                {				
                    return $CAInstance.InvokeFunction($CAInstance.GetKubernetesContinuousAssurance);
                }
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
        [ValidateSet("HDInsight", "Databricks", "Kubernetes")]
        [Parameter(Mandatory = $true, HelpMessage="Friendly name of resource type. e.g.: Kubernetes,HDInight")]
		[Alias("rt")]
        $ResourceType,

        [string]
        [Alias("sid","HostSubscriptionId","hsid","s")]
        [Parameter(Mandatory = $true, HelpMessage="Subscription Id of the cluster for which AzSK Continuous Assurance will be installed.")]
        $SubscriptionId,

        [string]
        [Alias("wsn")]
        $WorkspaceName,

        [string]
        [Alias("cn","ResourceName")]
        [Parameter(Mandatory = $false, HelpMessage="Resource Name of the cluster for which AzSK Continuous Assurance will be installed.")]
        $ClusterName,

        [string]
        [Alias("rgn")]
        [Parameter(Mandatory = $true, HelpMessage="ResourceGroup Name of the cluster for which AzSK Continuous Assurance will be installed.")]
        $ResourceGroupName,

        [string]
        [Alias("pat")]
        $PersonalAccessToken,

        [string]
        [Alias("aik")]
        [Parameter(Mandatory = $false, HelpMessage= "Instrumention key of Application Insight where security scan results will be populated.")]
		[ValidateNotNullOrEmpty()]
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
            } elseif($ResourceType -eq "Kubernetes") {
                $CAInstance = [KubernetesClusterCA]::new($SubscriptionId, $ResourceGroupName, $ClusterName,  $MyInvocation);
                if ($CAInstance) 
                {				
                    return $CAInstance.InvokeFunction($CAInstance.InstallKubernetesContinuousAssurance,@($LAWorkspaceId, $LASharedSecret));
                }
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
        [ValidateSet("HDInsight", "Databricks", "Kubernetes")]
        [Parameter(Mandatory = $true, HelpMessage="Friendly name of resource type. e.g.: Kubernetes,HDInight")]
		[Alias("rt")]
        $ResourceType,

        [string]
        [Alias("sid","HostSubscriptionId","hsid","s")]
        [Parameter(Mandatory = $true, HelpMessage="Subscription Id of the cluster for which AzSK Continuous Assurance will be installed.")]
        $SubscriptionId,

        [string]
        [Alias("wsn")]
        $WorkspaceName,

        [string]
        [Alias("cn","ResourceName")]
        [Parameter(Mandatory = $false, HelpMessage="Resource Name of the cluster for which AzSK Continuous Assurance will be installed.")]
        $ClusterName,

        [string]
        [Alias("rgn")]
        [Parameter(Mandatory = $true, HelpMessage="ResourceGroup Name of the cluster for which AzSK Continuous Assurance will be installed.")]
        $ResourceGroupName,

        [string]
        [Alias("pat")]
        $PersonalAccessToken,

        [string]
        [Alias("npat")]
        $NewPersonalAccessToken,

        [string]
        [Alias("naik")]
        [Parameter(Mandatory = $false, HelpMessage= "Instrumention key of Application Insight where security scan results will be populated.")]
		[ValidateNotNullOrEmpty()]
        $NewAppInsightKey,

        [string]
        [Alias("nsed")]
        $NewSchedule,

        [string]
        [Alias("lawsid")]
        $NewLAWorkspaceId,

        [string]
        [Alias("lasec")]
        $NewLASharedSecret,

        [Parameter(Mandatory = $false, HelpMessage = "Use this switch to fix CA runtime account in case of any issue with service account/role etc.")]
        [switch]
		[Alias("fra")]
		$FixRuntimeAccount,

		[Parameter(Mandatory = $false, HelpMessage = "This provides the capability to users to decide how manys previous job logs to be reatined in cluster.")]
	    [int]
		[Alias("lo")]
		$LogRetentionInDays,

        [Parameter(Mandatory = $false, HelpMessage= "This provides the capability to users to run specific version of image.")]
		[ValidateNotNullOrEmpty()]
        [string]
		[Alias("siv")]
		$SpecificImageVersion,

		[Parameter(Mandatory = $false, HelpMessage= "Overrides the default scan interval (24hrs) with the custom provided value")]
		[int]
		[Alias("si")]
		$ScanIntervalInHours

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
            } elseif($ResourceType -eq "Kubernetes") {
                $CAInstance = [KubernetesClusterCA]::new($SubscriptionId, $ResourceGroupName, $ClusterName, $MyInvocation);
                if ($CAInstance) 
                {				
                    return $CAInstance.InvokeFunction($CAInstance.UpdateKubernetesContinuousAssurance,@($NewAppInsightKey, $NewLAWorkspaceId, $NewLASharedSecret, $FixRuntimeAccount,$LogRetentionInDays,$ScanIntervalInHours, $SpecificImageVersion));
                }
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
        [ValidateSet("HDInsight", "Databricks", "Kubernetes")]
        [Parameter(Mandatory = $true, HelpMessage="Friendly name of resource type. e.g.: Kubernetes,HDInight")]
		[Alias("rt")]
        $ResourceType,

        [string]
        [Alias("sid","HostSubscriptionId","hsid","s")]
        [Parameter(Mandatory = $true, HelpMessage="Subscription Id of the cluster for which AzSK Continuous Assurance will be installed.")]
        $SubscriptionId,

        [string]
        [Alias("wsn")]
        $WorkspaceName,

        [string]
        [Alias("cn","ResourceName")]
        [Parameter(Mandatory = $false, HelpMessage="Resource Name of the cluster for which AzSK Continuous Assurance will be installed.")]
        $ClusterName,

        [string]
        [Alias("rgn")]
        [Parameter(Mandatory = $true, HelpMessage="ResourceGroup Name of the cluster for which AzSK Continuous Assurance will be installed.")]
        $ResourceGroupName,

        [string]
        [Alias("pat")]
        $PersonalAccessToken,

        [ValidateSet("Yes","No")] 
        [Parameter(Mandatory = $false, HelpMessage="This provides the capability to download all previous job logs to local before removing AzSK Continuous Assurance from cluster.")]
		[Alias("djl")]
		$DownloadJobLogs,

        [switch]
        $Force,
        
        [switch]
        $RemoveLogs
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
                $ResourceContext.RemoveLogs = $RemoveLogs
                $CAInstance = [DatabricksClusterCA]::new($ResourceContext, $MyInvocation)
                $CAInstance.InvokeFunction($CAInstance.RemoveCA)              
            } elseif ($ResourceType -eq "HDInsight") {
                $ResourceContext = [HDInsightClusterCA]::GetParameters($SubscriptionId, $ClusterName, $ResourceGroupName)
                $ResourceContext.RemoveLogs = $RemoveLogs
                $CAInstance = [HDInsightClusterCA]::new($ResourceContext, $MyInvocation)
                $CAInstance.InvokeFunction($CAInstance.RemoveCA)  
            } elseif($ResourceType -eq "Kubernetes") {
                $CAInstance = [KubernetesClusterCA]::new($SubscriptionId, $ResourceGroupName, $ClusterName, $MyInvocation);
                if ($CAInstance) 
                {				
                    return $CAInstance.InvokeFunction($CAInstance.RemoveKubernetesContinuousAssurance,@($DownloadJobLogs, $Force));
                }
            }
        } catch {
            [EventBase]::PublishGenericException($_);
        }
    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }
}
