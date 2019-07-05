Set-StrictMode -Version Latest 
class Build: SVTBase
{    

    Build([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {

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
                            New-Item -ItemType Directory -Path $buildDefPath -Force | Out-Null
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

        $apiURL = $this.ResourceContext.ResourceId
        $buildObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        if($buildObj)
        {
                    $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery/project/{1}?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName),$buildObj.project.id;
            $inputbody =  "{
                'contributionIds': [
                    'ms.vss-build-web.ci-data-provider'
                ],
                'dataProviderContext': {
                    'properties': {
                        'definitionIds': '$($buildObj.id)',
                        'definitionId': '$($buildObj.id)',
                        'view': 'buildsHistory',
                        'hubQuery': 'true',
                        'sourcePage': {
                            'url': 'https://$($this.SubscriptionContext.SubscriptionName).visualstudio.com/AzSDKDemoRepo/_build?definitionId=$($buildObj.id)',
                            'routeId': 'ms.vss-build-web.ci-definitions-hub-route',
                            'routeValues': {
                                'project': '$($buildObj.project.name)',
                                'viewname': 'definitions',
                                'controller': 'ContributedPage',
                                'action': 'Execute'
                            }
                        }
                    }
                }
        }"  | ConvertFrom-Json #-f $($buildObj.id),$this.SubscriptionContext.SubscriptionName,$buildObj.project.name

        $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);

        if([Helpers]::CheckMember($responseObj,"dataProviders") -and $responseObj.dataProviders.'ms.vss-build-web.ci-data-provider'-and  $responseObj.dataProviders.'ms.vss-build-web.ci-data-provider'.historyView.builds)
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
}