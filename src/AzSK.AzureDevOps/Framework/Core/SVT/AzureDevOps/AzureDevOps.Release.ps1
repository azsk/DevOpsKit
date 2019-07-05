Set-StrictMode -Version Latest 
class Release: SVTBase
{    

    Release([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {

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
                            New-Item -ItemType Directory -Path $releaseDefPath -Force | Out-Null
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
        $releaesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        if($releaesObj)
        {
            $pattern = "https://vsrm.dev.azure.com/$($this.SubscriptionContext.SubscriptionName)/(.*?)/_apis/Release/definitions/$($releaesObj.id)" 
            $projectId = [regex]::match($releaesObj.url.ToLower(), $pattern.ToLower()).Groups[1].Value
            $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery/project/{1}?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName),$projectId;
            $inputbody =  "{
                'contributionIds': [
                    'ms.vss-releaseManagement-web.releases-list-data-provider'
                ],
                'dataProviderContext': {
                    'properties': {
                        'definitionIds': '$($releaesObj.id)',
                        'definitionId': '$($releaesObj.id)',
                        'fetchAllReleases': true,
                        'sourcePage': {
                            'url': 'https://$($this.SubscriptionContext.SubscriptionName).visualstudio.com/AzSDKDemoRepo/_release?view=mine&definitionId=$($releaesObj.id)',
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
}