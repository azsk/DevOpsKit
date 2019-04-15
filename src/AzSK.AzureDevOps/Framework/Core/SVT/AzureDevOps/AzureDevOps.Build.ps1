Set-StrictMode -Version Latest 
class Build: SVTBase
{    

    hidden [PSObject] $buildObj;
    hidden [string] $securityNamespaceId;
    
    Build([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        # Get build object
        $apiURL = $this.ResourceContext.ResourceId
        $this.buildObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        # Get security namespace identifier of current build.
        $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
        $securityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $this.securityNamespaceId = ($securityNamespacesObj | Where-Object { ($_.Name -eq "Build") -and ($_.actions.name -contains "ViewBuilds")}).namespaceId
    }

    hidden [ControlResult] CheckCredInVariables([ControlResult] $controlResult)
	{
        
        $ToolFolderPath =  [ConfigurationManager]::GetAzSKSettings().ScanToolPath
        $ScanToolName = [ConfigurationManager]::GetAzSKSettings().ScanToolName
        if((-not [string]::IsNullOrEmpty($ToolFolderPath)) -and (Test-Path $ToolFolderPath) -and (-not [string]::IsNullOrEmpty($ScanToolName)))
        {
            $ToolPath = Get-ChildItem -Path $ToolFolderPath -File -Include $ScanToolName -Recurse 
            if($ToolPath)
            {
                if($this.buildObj)
                {
                    try
                    {
                        $buildDefFileName = $($this.ResourceContext.ResourceName).Replace(" ","")
                        $buildDefPath = [Constants]::AzSKTempFolderPath + "\Builds\"+ $buildDefFileName + "\";
                        if(-not (Test-Path -Path $buildDefPath))
                        {
                            mkdir -Path $buildDefPath -Force | Out-Null
                        }

                        $this.buildObj | ConvertTo-Json -Depth 5 | Out-File "$buildDefPath\$buildDefFileName.json"
                        $searcherPath = Get-ChildItem -Path $($ToolPath.Directory.FullName) -Include "buildsearchers.xml" -Recurse
                        ."$($Toolpath.FullName)" -I $buildDefPath -S $searcherPath -f csv -Ve 1 -O "$buildDefPath\Scan"    
                        
                        $scanResultPath = Get-ChildItem -Path $buildDefPath -File -Filter "*.csv"
                        if($scanResultPath -and (Test-Path $scanResultPath.FullName))
                        {
                            $credList = Get-Content -Path $scanResultPath.FullName | ConvertFrom-Csv 
                            if(($credList | Measure-Object).Count -gt 0)
                            {
                                $controlResult.AddMessage("No. of credentials found:" + ($credList | Measure-Object).Count )
                                $controlResult.AddMessage([VerificationResult]::Failed,"Found credentials in variables")
                            }
                            else {
                                $controlResult.AddMessage([VerificationResult]::Passed,"No credentials found in variables")
                            }
                        }
                    }
                    catch {
                        #Publish Exception
                        $this.PublishException($_);           
                    }
                    finally
                    {
                        #Clean temp folders 
                        Remove-ITem -Path $buildDefPath -Recurse
                    }
                }
            }
        }
        
        return $controlResult;
    }

    hidden [ControlResult] CheckInActiveBuild([ControlResult] $controlResult)
    {
        if($this.buildObj)
        {
            $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery/project/{1}?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName),$($this.buildObj.project.id);
            $inputbody =  "{
                'contributionIds': [
                    'ms.vss-build-web.ci-data-provider'
                ],
                'dataProviderContext': {
                    'properties': {
                        'definitionIds': '$($this.buildObj.id)',
                        'definitionId': '$($this.buildObj.id)',
                        'view': 'buildsHistory',
                        'hubQuery': 'true',
                        'sourcePage': {
                            'url': 'https://$($this.SubscriptionContext.SubscriptionName).visualstudio.com/AzSDKDemoRepo/_build?definitionId=$($this.buildObj.id)',
                            'routeId': 'ms.vss-build-web.ci-definitions-hub-route',
                            'routeValues': {
                                'project': '$($this.buildObj.project.name)',
                                'viewname': 'definitions',
                                'controller': 'ContributedPage',
                                'action': 'Execute'
                            }
                        }
                    }
                }
        }"  | ConvertFrom-Json #-f $($this.buildObj.id),$this.SubscriptionContext.SubscriptionName,$this.buildObj.project.name

        $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);

        if([Helpers]::CheckMember($responseObj,"dataProviders") -and $responseObj.dataProviders.'ms.vss-build-web.ci-data-provider' -and [Helpers]::CheckMember($responseObj.dataProviders.'ms.vss-build-web.ci-data-provider'.historyView,"builds") -and  $responseObj.dataProviders.'ms.vss-build-web.ci-data-provider'.historyView.builds)
        {

            $builds = $responseObj.dataProviders.'ms.vss-build-web.ci-data-provider'.historyView.builds

            if(($builds | Measure-Object).Count -gt 0 )
            {
                $recentBuilds = @()
                 $builds | ForEach-Object { 
                    if([datetime]::Parse( $_.build.queueTime) -gt (Get-Date).AddDays(-$($this.ControlSettings.Build.BuildHistoryPeriodInDays)))
                    {
                        $recentBuilds+=$_
                    }
                }
                
                if(($recentBuilds | Measure-Object).Count -gt 0 )
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,
                    "Found recent builds triggered within $($this.ControlSettings.Build.BuildHistoryPeriodInDays) days");
                }
                else
                {
                    $controlResult.AddMessage([VerificationResult]::Failed,
                    "No recent build history found in last $($this.ControlSettings.Build.BuildHistoryPeriodInDays) days");
                }
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                "No build history found.");
            }
           
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                                "No build history found. Build is inactive.");
        }
    }
        return $controlResult
    }

    hidden [ControlResult] CheckInheritPermissions([ControlResult] $controlResult)
    {
        # Here 'permissionSet' = security namespace identifier, 'token' = project id and 'tokenDisplayVal' = build name
        $apiURL = "https://{0}.visualstudio.com/{1}/_admin/_security/index?useApiUrl=true&permissionSet={2}&token={3}%2F{4}&tokenDisplayVal={5}&style=min" -f $($this.SubscriptionContext.SubscriptionName), $($this.buildObj.project.id), $($this.securityNamespaceId), $($this.buildObj.project.id), $($this.buildObj.id), $($this.buildObj.name) ;
        $header = [WebRequestHelper]::GetAuthHeaderFromUri($apiURL);
        $responseObj = Invoke-RestMethod -Method Get -Uri $apiURL -Headers $header -UseBasicParsing
        $responseObj = ($responseObj.SelectNodes("//script") | Where-Object { $_.class -eq "permissions-context" }).InnerXML | ConvertFrom-Json; 
        if(-not $responseObj)
        {
            $controlResult.AddMessage([VerificationResult]::Failed,"Unable to verify inherit permission option. Please navigate to the your build pipeline and verify that inherit permission is disabled.",$responseObj);
        }
        elseif($responseObj.inheritPermissions -eq $true)
        {
            $controlResult.AddMessage([VerificationResult]::Failed,"Build pipeline is using inherit permissions. It is specifically turned ON.",$responseObj);
        }
        else 
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"Build pipeline is not using inherit permissions. It is specifically turned OFF.");    
        }
        return $controlResult
    }

    hidden [ControlResult] CheckRBACAccess([ControlResult] $controlResult)
    {
        # Here 'permissionSet' = security namespace identifier, 'token' = project id and 'tokenDisplayVal' = build name
        $buildDefinitionPath = $this.buildObj.Path.Trim("\").Replace(" ","+").Replace("\","%2F")
        $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/ReadExplicitIdentitiesJson?__v=5&permissionSetId={2}&permissionSetToken={3}%2F{4}%2F{5}" -f $($this.SubscriptionContext.SubscriptionName), $($this.buildObj.project.id), $($this.securityNamespaceId), $($this.buildObj.project.id), $($buildDefinitionPath), $($this.buildObj.id);
        $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $accessList = @()
        $whitelistedUserIdentities = @()
        # release owner
        $whitelistedUserIdentities += $this.buildObj.authoredBy.id
        if(($responseObj.identities|Measure-Object).Count -gt 0)
        {
            $whitelistedUserIdentities += $responseObj.identities | Where-Object { $_.IdentityType -eq "user" }| ForEach-Object {
                $identity = $_
                $whitelistedIdentity = $this.ControlSettings.Build.WhitelistedUserIdentities | Where-Object { $_.Domain -eq $identity.Domain -and $_.DisplayName -eq $identity.DisplayName }
                if(($whitelistedIdentity | Measure-Object).Count -gt 0)
                {
                    return $identity.TeamFoundationId
                }
            }

            $accessList += $responseObj.identities | Where-Object { $_.IdentityType -eq "user" } | ForEach-Object {
                $identity = $_ 
                if($whitelistedUserIdentities -notcontains $identity.TeamFoundationId)
                {
                    $apiURL = $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/DisplayPermissions?__v=5&tfid={2}&permissionSetId={3}&permissionSetToken={4}%2F{5}%2F{6}" -f $($this.SubscriptionContext.SubscriptionName), $($this.buildObj.project.id), $($identity.TeamFoundationId) ,$($this.securityNamespaceId),$($this.buildObj.project.id), $($buildDefinitionPath), $($this.buildObj.id);
                    $identityPermissions = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                    return @{ IdentityName = $identity.DisplayName; IdentityType = $identity.IdentityType; Permissions = ($identityPermissions.Permissions | Select-Object @{Name="Name"; Expression = {$_.displayName}},@{Name="Permission"; Expression = {$_.permissionDisplayString}}) }
                }
            }

            $accessList += $responseObj.identities | Where-Object { $_.IdentityType -eq "group" } | ForEach-Object {
                $identity = $_ 
                $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/DisplayPermissions?__v=5&tfid={2}&permissionSetId={3}&permissionSetToken={4}%2F{5}%2F{6}" -f $($this.SubscriptionContext.SubscriptionName), $($this.buildObj.project.id), $($identity.TeamFoundationId) ,$($this.securityNamespaceId),$($this.buildObj.project.id), $($buildDefinitionPath), $($this.buildObj.id);
                $identityPermissions = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                return @{ IdentityName = $identity.DisplayName; IdentityType = $identity.IdentityType; IsAadGroup = $identity.IsAadGroup ;Permissions = ($identityPermissions.Permissions | Select-Object @{Name="Name"; Expression = {$_.displayName}},@{Name="Permission"; Expression = {$_.permissionDisplayString}}) }
            }
        }
        if(($accessList | Measure-Object).Count -ne 0)
        {
            $controlResult.AddMessage([VerificationResult]::Verify,"Validate that the following identities have explicitly provided with RBAC access to resource - [$($this.ResourceContext.ResourceName)]", $accessList);
            $controlResult.SetStateData("Build pipeline access list: ", $accessList);
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"No identities have been explicitly provided with RBAC access to resource - [$($this.ResourceContext.ResourceName)] other than build pipeline owner and default groups");
            $controlResult.AddMessage("List of whitelisted user identities:",$whitelistedUserIdentities)
        }
        return $controlResult
    }
}