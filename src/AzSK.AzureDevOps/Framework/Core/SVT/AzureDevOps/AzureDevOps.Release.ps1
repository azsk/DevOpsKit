Set-StrictMode -Version Latest 
class Release: SVTBase
{   

    hidden [PSObject] $ReleaseObj;
    hidden [string] $ProjectId;
    hidden [string] $securityNamespaceId;

    
    Release([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        # Get release object
        $apiURL = $this.ResourceContext.ResourceId
        $this.ReleaseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        # Get project id
        $pattern = "https://$($this.SubscriptionContext.SubscriptionName).vsrm.visualstudio.com/(.*?)/_apis/Release/definitions/$($this.ReleaseObj.id)"
        $this.ProjectId = [regex]::match($this.ReleaseObj.url.ToLower(), $pattern.ToLower()).Groups[1].Value
        if([string]::IsNullOrEmpty($this.ProjectId))
        {
            $pattern = "https://vsrm.dev.azure.com/$($this.SubscriptionContext.SubscriptionName)/(.*?)/_apis/Release/definitions/$($this.ReleaseObj.id)"
            $this.ProjectId = [regex]::match($this.ReleaseObj.url.ToLower(), $pattern.ToLower()).Groups[1].Value
        }
        # Get security namespace identifier of current release pipeline.
        $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
        $securityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $this.SecurityNamespaceId = ($securityNamespacesObj | Where-Object { ($_.Name -eq "ReleaseManagement") -and ($_.actions.name -contains "ViewReleaseDefinition")}).namespaceId
    }

    hidden [ControlResult] CheckCredInVariables([ControlResult] $controlResult)
	{
        
        if([Helpers]::CheckMember([ConfigurationManager]::GetAzSKSettings(),"ScanToolPath"))
        {
            $ToolFolderPath =  [ConfigurationManager]::GetAzSKSettings().ScanToolPath
        $ScanToolName = [ConfigurationManager]::GetAzSKSettings().ScanToolName
        if((-not [string]::IsNullOrEmpty($ToolFolderPath)) -and (Test-Path $ToolFolderPath) -and (-not [string]::IsNullOrEmpty($ScanToolName)))
        {
            $ToolPath = Get-ChildItem -Path $ToolFolderPath -File -Filter $ScanToolName -Recurse 
            if($ToolPath)
            { 
                if($this.ReleaseObj)
                {
                    try
                    {
                        $releaseDefFileName = $($this.ResourceContext.ResourceName).Replace(" ","")
                        $releaseDefPath = [Constants]::AzSKTempFolderPath + "\Releases\"+ $releaseDefFileName + "\";
                        if(-not (Test-Path -Path $releaseDefPath))
                        {
                            mkdir -Path $releaseDefPath -Force | Out-Null
                        }

                        $this.ReleaseObj | ConvertTo-Json -Depth 5 | Out-File "$releaseDefPath\$releaseDefFileName.json"
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

        }
        
        
        return $controlResult;
    }

    hidden [ControlResult] CheckInActiveRelease([ControlResult] $controlResult)
    {        
        if($this.ReleaseObj)
        {
            $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery/project/{1}?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName),$this.ProjectId;
            $inputbody =  "{
                'contributionIds': [
                    'ms.vss-releaseManagement-web.releases-list-data-provider'
                ],
                'dataProviderContext': {
                    'properties': {
                        'definitionIds': '$($this.ReleaseObj.id)',
                        'definitionId': '$($this.ReleaseObj.id)',
                        'fetchAllReleases': true,
                        'sourcePage': {
                            'url': 'https://$($this.SubscriptionContext.SubscriptionName).visualstudio.com/AzSDKDemoRepo/_release?view=mine&definitionId=$($this.ReleaseObj.id)',
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

    hidden [ControlResult] CheckInheritPermissions([ControlResult] $controlResult)
    {
        # Here 'permissionSet' = security namespace identifier, 'token' = project id
        $apiURL = "https://{0}.visualstudio.com/{1}/_admin/_security/index?useApiUrl=true&permissionSet={2}&token={3}%2F{4}&style=min" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $($this.SecurityNamespaceId), $($this.ProjectId), $($this.ReleaseObj.id);
        $header = [WebRequestHelper]::GetAuthHeaderFromUri($apiURL);
        $responseObj = Invoke-RestMethod -Method Get -Uri $apiURL -Headers $header -UseBasicParsing
        $responseObj = ($responseObj.SelectNodes("//script") | Where-Object { $_.class -eq "permissions-context" }).InnerXML | ConvertFrom-Json; 
        if($responseObj.inheritPermissions -eq $true)
        {
            $controlResult.AddMessage([VerificationResult]::Failed,"Inherited permissions are allowed on release pipeline.");
        }
        else 
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"Inherited permissions are disabled on release pipeline.");
        }
        return $controlResult
    }

    hidden [ControlResult] CheckPreDeploymentApproval ([ControlResult] $controlResult)
    {
        $releaseStages = $this.ReleaseObj.environments;# | Where-Object { $this.ControlSettings.Release.RequirePreDeployApprovals -contains $_.name.Trim()}
        if($releaseStages)
        {
            $nonComplaintStages = $releaseStages | ForEach-Object { 
                $releaseStage = $_
                if([Helpers]::CheckMember($releaseStage,"preDeployApprovals.approvals.isAutomated") -and $releaseStage.preDeployApprovals.approvals.isAutomated -eq $true) 
                {
                    return $($releaseStage | Select-Object id,name, @{Name = "Owner"; Expression = {$_.owner.displayName}}) 
                }
            }

            if(($nonComplaintStages | Measure-Object).Count -gt 0)
            {
                $controlResult.AddMessage([VerificationResult]::Failed,"Pre-deployment approvals is not enabled for following release stages in [$($this.ReleaseObj.name)] pipeline.", ($nonComplaintStages| Format-Table));
            }
            else 
            {
                $complaintStages = $releaseStages | ForEach-Object {
                    $releaseStage = $_
                    return  $($releaseStage | Select-Object id,name, @{Name = "Owner"; Expression = {$_.owner.displayName}})
                }
                $controlResult.AddMessage([VerificationResult]::Passed,"Pre-deployment approvals is enabled for following release stages.",($complaintStages | Format-Table));
            }
        }
        else
        {
            $otherStages = $this.ReleaseObj.environments | ForEach-Object {
                $releaseStage = $_
                if([Helpers]::CheckMember($releaseStage,"preDeployApprovals.approvals.isAutomated") -and $releaseStage.preDeployApprovals.approvals.isAutomated -ne $true) 
                {
                    return $($releaseStage | Select-Object id,name, @{Name = "Owner"; Expression = {$_.owner.displayName}}) 
                }
            }
            
            if ($otherStages) {
                $controlResult.AddMessage([VerificationResult]::Verify,"No release stage found matching to $($this.ControlSettings.Release.RequirePreDeployApprovals -join ", ") in [$($this.ReleaseObj.name)] pipeline.  Verify that pre-deployment approval is enabled for below found environments.");
                $controlResult.AddMessage(($otherStages | Format-Table))
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,"No release stage found matching to $($this.ControlSettings.Release.RequirePreDeployApprovals -join ", ") in [$($this.ReleaseObj.name)] pipeline.  Found pre-deployment approval is enabled for present environments.");
            }
        }
        return $controlResult
    }

    hidden [ControlResult] CheckPreDeploymentApprovers ([ControlResult] $controlResult)
    {
        $releaseStages = $this.ReleaseObj.environments | Where-Object { $this.ControlSettings.Release.RequirePreDeployApprovals -contains $_.name.Trim()}
        if($releaseStages)
        {
            $approversList = $releaseStages | ForEach-Object { 
                $releaseStage = $_
                if([Helpers]::CheckMember($releaseStage,"preDeployApprovals.approvals.isAutomated") -and $($releaseStage.preDeployApprovals.approvals.isAutomated -eq $false))
                {
                    if([Helpers]::CheckMember($releaseStage,"preDeployApprovals.approvals.approver"))
                    {
                        return @{ ReleaseStageName= $releaseStage.Name; Approvers = $releaseStage.preDeployApprovals.approvals.approver }
                    }
                }
            }
            if(($approversList | Measure-Object).Count -eq 0)
            {
                $controlResult.AddMessage([VerificationResult]::Failed,"No approvers found. Please ensure that pre-deployment approval is enabled for production release stages");
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Verify,"Validate users/groups added as approver within release pipeline.",$approversList);
                $controlResult.SetStateData("List of approvers for each release stage: ", $approversList);
            }
        }
        else
        {
            $controlResult.AddMessage([VerificationResult]::Passed,"No release stage found matching to $($this.ControlSettings.Release.RequirePreDeployApprovals -join ", ") in [$($this.ReleaseObj.name)] pipeline.");
        }
        
        return $controlResult
    }

    hidden [ControlResult] CheckRBACAccess ([ControlResult] $controlResult)
    {
        $failMsg = $null
        try
        {
            # This functions is to check users permissions on release definition. Groups' permissions check is not added here.
            $releaseDefinitionPath = $this.ReleaseObj.Path.Trim("\").Replace(" ","+").Replace("\","%2F")
            $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/ReadExplicitIdentitiesJson?__v=5&permissionSetId={2}&permissionSetToken={3}%2F{4}%2F{5}" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $($this.SecurityNamespaceId), $($this.ProjectId), $($releaseDefinitionPath) ,$($this.ReleaseObj.id);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            $accessList = @()
            $whitelistedUserIdentities = @()
            # exclude release owner
            $whitelistedUserIdentities += $this.ReleaseObj.createdBy.id
            if([Helpers]::CheckMember($responseObj,"identities") -and ($responseObj.identities|Measure-Object).Count -gt 0)
            {
                $whitelistedUserIdentities += $responseObj.identities | Where-Object { $_.IdentityType -eq "user" }| ForEach-Object {
                    $identity = $_
                    $whitelistedIdentity = $this.ControlSettings.Release.WhitelistedUserIdentities | Where-Object { $_.Domain -eq $identity.Domain -and $_.DisplayName -eq $identity.DisplayName }
                    if(($whitelistedIdentity | Measure-Object).Count -gt 0)
                    {
                        return $identity.TeamFoundationId
                    }
                }

                $accessList += $responseObj.identities | Where-Object { $_.IdentityType -eq "user" } | ForEach-Object {
                    $identity = $_ 
                    if($whitelistedUserIdentities -notcontains $identity.TeamFoundationId)
                    {
                        $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/DisplayPermissions?__v=5&tfid={2}&permissionSetId={3}&permissionSetToken={4}%2F{5}%2F{6}" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $($identity.TeamFoundationId) ,$($this.SecurityNamespaceId), $($this.ProjectId), $($releaseDefinitionPath), $($this.ReleaseObj.id);
                        $identityPermissions = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                        return @{ IdentityName = $identity.DisplayName; IdentityType = $identity.IdentityType; Permissions = ($identityPermissions.Permissions | Select-Object @{Name="Name"; Expression = {$_.displayName}},@{Name="Permission"; Expression = {$_.permissionDisplayString}}) }
                    }
                }

                $accessList += $responseObj.identities | Where-Object { $_.IdentityType -eq "group" } | ForEach-Object {
                    $identity = $_ 
                    $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/DisplayPermissions?__v=5&tfid={2}&permissionSetId={3}&permissionSetToken={4}%2F{5}%2F{6}" -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $($identity.TeamFoundationId) ,$($this.SecurityNamespaceId), $($this.ProjectId), $($releaseDefinitionPath), $($this.ReleaseObj.id);
                    $identityPermissions = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                    return @{ IdentityName = $identity.DisplayName; IdentityType = $identity.IdentityType; IsAadGroup = $identity.IsAadGroup ;Permissions = ($identityPermissions.Permissions | Select-Object @{Name="Name"; Expression = {$_.displayName}},@{Name="Permission"; Expression = {$_.permissionDisplayString}}) }
                }
            }
            
            if(($accessList | Measure-Object).Count -ne 0)
            {
                $accessList= $accessList | Select-Object -Property @{Name="IdentityName"; Expression = {$_.IdentityName}},@{Name="IdentityType"; Expression = {$_.IdentityType}},@{Name="Permissions"; Expression = {$_.Permissions}} | Format-Table
                $controlResult.AddMessage([VerificationResult]::Verify,"Validate that the following identities have been provided with minimum RBAC access to [$($this.ResourceContext.ResourceName)] pipeline", $accessList);
                $controlResult.SetStateData("Release pipeline access list: ", $accessList);
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Passed,"No identities have been explicitly provided with RBAC access to [$($this.ResourceContext.ResourceName)] pipeline other than release pipeline owner and default groups");
                $controlResult.AddMessage("List of whitelisted user identities:",$whitelistedUserIdentities)
            }
        }
        catch
        {
            $failMsg = $_
        }
        if(![string]::IsNullOrEmpty($failMsg))
        {
            $controlResult.AddMessage([VerificationResult]::Manual,"Unable to fetch release pipeline details. $($failMsg)Please verify from portal all teams/groups are granted minimum required permissions on release definition.");
        }       
        return $controlResult
    }

    hidden [ControlResult] CheckMixingGitHubAndADOSources([ControlResult] $controlResult)
    {
        if(($this.ReleaseObj | Measure-Object).Count -gt 0)
        {
            if( [Helpers]::CheckMember($this.ReleaseObj[0],"artifacts") -and ($this.ReleaseObj[0].artifacts | Measure-Object).Count -gt 0){
                $sourcetypes = @();
                $sourcetypes = $this.ReleaseObj[0].artifacts;
                $nonadoresource = $sourcetypes | Where-Object { $_.type -ne 'Git'} ;
               
               if( ($nonadoresource | Measure-Object).Count -gt 0){
                   $nonadoresource = $nonadoresource | Select-Object -Property @{Name="alias"; Expression = {$_.alias}},@{Name="Type"; Expression = {$_.type}} | Format-Table
                   $controlResult.AddMessage([VerificationResult]::Verify,"Pipelines contains artifact from the below external sources.", $nonadoresource);    
               }
               else {
                $controlResult.AddMessage([VerificationResult]::Passed,"Pipeline does not contain artifacts from external sources");   
               }
           }
           else {
            $controlResult.AddMessage([VerificationResult]::Passed,"Pipeline does not contain any source repositories");   
           } 
        }

        return $controlResult;
    }
}