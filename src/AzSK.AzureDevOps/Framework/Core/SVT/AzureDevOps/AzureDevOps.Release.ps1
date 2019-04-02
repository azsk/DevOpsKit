Set-StrictMode -Version Latest 
class Release: SVTBase
{   

    hidden [PSObject] $releaseObj;
    
    Release([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        $this.releaseObj = [WebRequestHelper]::InvokeGetWebRequest($this.ResourceContext.ResourceId);
    }

    hidden [ControlResult] CheckCredInVariables([ControlResult] $controlResult)
	{
        $ToolFolderPath =  [ConfigurationManager]::GetAzSKSettings().ScanToolPath
        $ScanToolName = [ConfigurationManager]::GetAzSKSettings().ScanToolName
        if((-not [string]::IsNullOrEmpty($ToolFolderPath)) -and (Test-Path $ToolFolderPath) -and (-not [string]::IsNullOrEmpty($ScanToolName)))
        {
            $ToolPath = Get-ChildItem -Path $ToolFolderPath -File -Filter $ScanToolName -Recurse 
            if($ToolPath)
            {
                $apiURL = $this.ResourceContext.ResourceId
                $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                if($responseObj)
                {
                    try
                    {
                        $releaseDefFileName = $($this.ResourceContext.ResourceName).Replace(" ","")
                        $releaseDefPath = [Constants]::AzSKTempFolderPath + "\Releases\"+ $releaseDefFileName + "\";
                        if(-not (Test-Path -Path $releaseDefPath))
                        {
                            mkdir -Path $releaseDefPath -Force | Out-Null
                        }

                        $responseObj | ConvertTo-Json -Depth 5 | Out-File "$releaseDefPath\$releaseDefFileName.json"
                        $searcherPath = Get-ChildItem -Path $($ToolPath.Directory.FullName) -Include "buildsearchers.xml" -Recurse
                        ."$($Toolpath.FullName)" -I $releaseDefPath -S "$($searcherPath.FullName)" -f csv -Ve 1 -O "$releaseDefPath\Scan"    
                        
                        $scanResultPath = Get-ChildItem -Path $releaseDefPath -File -Include "*.csv"
                        
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
                        Remove-ITem -Path $releaseDefPath -Recurse
                    }
                }
            }
        }
        
        return $controlResult;
    }

    hidden [ControlResult] CheckInActiveRelease([ControlResult] $controlResult)
    {

        $apiURL = $this.ResourceContext.ResourceId
        $this.releaseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        if($this.releaseObj)
        {
            $pattern = "https://vsrm.dev.azure.com/$($this.SubscriptionContext.SubscriptionName)/(.*?)/_apis/Release/definitions/$($this.releaseObj.id)" 
            $projectId = [regex]::match($this.releaseObj.url.ToLower(), $pattern.ToLower()).Groups[1].Value
            $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery/project/{1}?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName),$projectId;
            $inputbody =  "{
                'contributionIds': [
                    'ms.vss-releaseManagement-web.releases-list-data-provider'
                ],
                'dataProviderContext': {
                    'properties': {
                        'definitionIds': '$($this.releaseObj.id)',
                        'definitionId': '$($this.releaseObj.id)',
                        'fetchAllReleases': true,
                        'sourcePage': {
                            'url': 'https://$($this.SubscriptionContext.SubscriptionName).visualstudio.com/AzSDKDemoRepo/_release?view=mine&definitionId=$($this.releaseObj.id)',
                            'routeId': 'ms.vss-releaseManagement-web.hub-explorer-3-default-route',
                            'routeValues': {
                                'project': '$($this.ResourceContext.ResourceGroupName)',
                                'viewname': 'hub-explorer-3-view',
                                'controller': 'ContributedPage',
                                'action': 'Execute'
                            }
                        }
                    }
                }
            }"  | ConvertFrom-Json 

        $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);

        if([Helpers]::CheckMember($responseObj,"dataProviders") -and $responseObj.dataProviders.'ms.vss-releaseManagement-web.releases-list-data-provider')
        {

            $releases = $responseObj.dataProviders.'ms.vss-releaseManagement-web.releases-list-data-provider'.releases

            if(($releases | Measure-Object).Count -gt 0 )
            {
                $recentReleases = @()
                 $releases | ForEach-Object { 
                    if([datetime]::Parse( $_.createdOn) -gt (Get-Date).AddDays(-$($this.ControlSettings.Release.ReleaseHistoryPeriodInDays)))
                    {
                        $recentReleases+=$_
                    }
                }
                
                if(($recentReleases | Measure-Object).Count -gt 0 )
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,
                    "Found recent releases triggered within $($this.ControlSettings.Release.ReleaseHistoryPeriodInDays) days");
                }
                else
                {
                    $controlResult.AddMessage([VerificationResult]::Failed,
                    "No recent release history found in last $($this.ControlSettings.Release.ReleaseHistoryPeriodInDays) days");
                }
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                "No release history found.");
            }
           
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Failed,
                                                "No release history found. release is inactive.");
        }
    } 
        return $controlResult
    }

    hidden [ControlResult] CheckRBACInheritPermissions ([ControlResult] $controlResult)
    {
        $projectId = $this.releaseObj.artifacts.definitionReference.project.id
        # Get security namespace identifier of current release pipeline.
        $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
        $securityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $securityNamespaceId = ($securityNamespacesObj | Where-Object { ($_.Name -eq "ReleaseManagement") -and ($_.actions.name -contains "ViewReleaseDefinition")}).namespaceId

        # Here 'permissionSet' = security namespace identifier, 'token' = project id
        $apiURL = "https://{0}.visualstudio.com/{1}/_admin/_security/index?useApiUrl=true&permissionSet={2}&token={3}%2F{4}&style=min" -f $($this.SubscriptionContext.SubscriptionName), $($projectId), $($securityNamespaceId), $($projectId), $($this.releaseObj.id);
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

    hidden [ControlResult] CheckGroupPermissions ([ControlResult] $controlResult)
    {
        $pattern = "https://$($this.SubscriptionContext.SubscriptionName).vsrm.visualstudio.com/(.*?)/_apis/Release/definitions/$($this.releaseObj.id)"
        $projectId = [regex]::match($this.releaseObj.url.ToLower(), $pattern.ToLower()).Groups[1].Value
        # Get security namespace identifier of current release pipeline.
        $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
        $securityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $securityNamespaceId = ($securityNamespacesObj | Where-Object { ($_.Name -eq "ReleaseManagement") -and ($_.actions.name -contains "ViewReleaseDefinition")}).namespaceId

        # Here 'permissionSet' = security namespace identifier, 'token' = project id
        $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/ReadExplicitIdentitiesJson?__v=5&permissionSetId={2}&permissionSetToken={3}%2F{4}" -f $($this.SubscriptionContext.SubscriptionName), $($projectId), $($securityNamespaceId), $($projectId), $($this.releaseObj.id);
        $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $securityGroups = $responseObj.identities | Where-Object { $_.IdentityType -eq "group" }
        $nonWhitelistedSecurityGroups =  $securityGroups | ForEach-Object {
            $inScope = $false
            $groupIdentity = $_
            $Match = $this.ControlSettings.Release.WhitelistedBuiltInSecurityGroups.Where({$_.Name -eq $groupIdentity.FriendlyDisplayName})
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