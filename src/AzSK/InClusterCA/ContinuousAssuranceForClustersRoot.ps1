function Read-Input($msg) {
    return (Read-Host -Prompt $msg).Trim()
}

function Get-DatabricksParameters() {    
    if([string]::IsNullOrEmpty($SubscriptionId) -or 
        [string]::IsNullOrEmpty($WorkspaceName) -or
        [string]::IsNullOrEmpty($ResourceGroupName) -or
        [string]::IsNullOrEmpty($PersonalAccessToken))
    {
        Write-Host "Input the following parameters"
        if ([string]::IsNullOrEmpty($SubscriptionId))
        {
            $SubscriptionId = Read-Input "Subscription ID"
        }
        if ([string]::IsNullOrEmpty($WorkspaceName))
        {
            $WorkspaceName = Read-Input "Databricks Workspace Name"
        }
        if ([string]::IsNullOrEmpty($ResourceGroupName))
        {
            $ResourceGroupName = Read-Input "Databricks Resource Group Name"
        }
        if ([string]::IsNullOrEmpty($PersonalAccessToken))
        {
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

function Get-AzSKContinuousAssuranceForDatabricks {
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
        $PersonalAccessToken
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
            $CAInstance.InvokeFunction($CAInstance.GetCA)   
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }
    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }
}


function Install-AzSKContinuousAssuranceForDatabricks{
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
        [Alias("aik")]
        $InstrumentationKey
    )

    Begin{
        [CommandHelper]::BeginCommand($MyInvocation);
        [ListenerHelper]::RegisterListeners();         
    }
    Process {
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
            $ResourceContext = Get-DatabricksParameters
            $ResourceContext.InstrumentationKey = $InstrumentationKey
            $CAInstance = [CAForDatabricks]::new($ResourceContext, $MyInvocation)
            $CAInstance.InvokeFunction($CAInstance.InstallCA)
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

function Remove-AzSKContinuousAssuranceForDatabricks{
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
        $PersonalAccessToken
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
            $CAInstance.InvokeFunction($CAInstance.RemoveCA)
        } catch {
            [EventBase]::PublishGenericException($_);
        }
    }
    End {
        [ListenerHelper]::UnregisterListeners();
    }
}
