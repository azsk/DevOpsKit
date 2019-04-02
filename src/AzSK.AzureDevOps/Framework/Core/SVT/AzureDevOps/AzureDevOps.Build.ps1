Set-StrictMode -Version Latest 
class Build: SVTBase
{    

    hidden [PSObject] $buildObj;
    
    Build([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        # Get build object
        $this.buildObj = [WebRequestHelper]::InvokeGetWebRequest($this.ResourceContext.ResourceId);
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
                $apiURL = $this.ResourceContext.ResourceId
                $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                if($responseObj)
                {
                    try
                    {
                        $buildDefFileName = $($this.ResourceContext.ResourceName).Replace(" ","")
                        $buildDefPath = [Constants]::AzSKTempFolderPath + "\Builds\"+ $buildDefFileName + "\";
                        if(-not (Test-Path -Path $buildDefPath))
                        {
                            mkdir -Path $buildDefPath -Force | Out-Null
                        }

                        $responseObj | ConvertTo-Json -Depth 5 | Out-File "$buildDefPath\$buildDefFileName.json"
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
                    $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery/project/{1}?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName),$this.buildObj.project.id;
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

    hidden [ControlResult] CheckRBACInheritPermissions([ControlResult] $controlResult)
    {
        # Get security namespace identifier of current build.
        $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
        $securityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $securityNamespaceId = ($securityNamespacesObj | Where-Object { ($_.Name -eq "Build") -and ($_.actions.name -contains "ViewBuilds")}).namespaceId

        # Here 'permissionSet' = security namespace identifier, 'token' = project id and 'tokenDisplayVal' = build name
        $apiURL = "https://{0}.visualstudio.com/{1}/_admin/_security/index?useApiUrl=true&permissionSet={2}&token={3}%2F{4}&tokenDisplayVal={5}&style=min" -f $($this.SubscriptionContext.SubscriptionName), $($this.buildObj.project.id), $($securityNamespaceId), $($this.buildObj.project.id), $($this.buildObj.id), $($this.buildObj.name) ;
        $header = [WebRequestHelper]::GetAuthHeaderFromUri($apiURL);
        $responseObj = Invoke-RestMethod -Method Get -Uri $apiURL -Headers $header -UseBasicParsing
        $responseObj = ($responseObj.SelectNodes("//script") | Where-Object { $_.class -eq "permissions-context" }).InnerXML | ConvertFrom-Json; 
        if($responseObj.inheritPermissions -eq $true)
        {
            $controlResult.AddMessage([VerificationResult]::Failed,"##");
        }
        else 
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"##");    
        }
        return $controlResult
    }

    hidden [ControlResult] CheckGroupPermissions([ControlResult] $controlResult)
    {
        # Get security namespace identifier of current build.
        $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
        $securityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $securityNamespaceId = ($securityNamespacesObj | Where-Object { ($_.Name -eq "Build") -and ($_.actions.name -contains "ViewBuilds")}).namespaceId

        # Here 'permissionSet' = security namespace identifier, 'token' = project id and 'tokenDisplayVal' = build name
        $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/ReadExplicitIdentitiesJson?__v=5&permissionSetId={2}&permissionSetToken={3}%2F{4}" -f $($this.SubscriptionContext.SubscriptionName), $($this.buildObj.project.id), $($securityNamespaceId), $($this.buildObj.project.id), $($this.buildObj.id);
        $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $securityGroups = $responseObj.identities | Where-Object { $_.IdentityType -eq "group" }
        $nonWhitelistedSecurityGroups =  $securityGroups | ForEach-Object {
            $inScope = $false
            $groupIdentity = $_
            $Match = $this.ControlSettings.Build.WhitelistedBuiltInSecurityGroups.Where({$_.Name -eq $groupIdentity.FriendlyDisplayName})
            if(($Match | Measure-Object).Count -gt 0)
            {
               $inScope = ($Match.Level -eq "Project" -and $groupIdentity.Scope -eq $this.ResourceContext.ResourceGroupName) -or 
               ($Match.Level -eq "Organization" -and $groupIdentity.Scope -eq $this.SubscriptionContext.SubscriptionName)
            }                    
            if(-not $inScope)
            {
               return $groupIdentity
            }
        }
        if(($nonWhitelistedSecurityGroups | Measure-Object).Count -eq 0)
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"##");
        }
        else 
        {
            $controlResult.AddMessage([VerificationResult]::Verify,"##");
            $controlResult.SetStateData("##", $nonWhitelistedSecurityGroups);
        }
        return $controlResult
    }
}