Set-StrictMode -Version Latest 
class Build: ADOSVTBase
{    

    hidden [PSObject] $BuildObj;
    hidden [string] $SecurityNamespaceId;
    
    Build([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        # Get security namespace identifier of current build.
        $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
        $securityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $this.SecurityNamespaceId = ($securityNamespacesObj | Where-Object { ($_.Name -eq "Build") -and ($_.actions.name -contains "ViewBuilds")}).namespaceId

        $securityNamespacesObj = $null;
        # Get build object
        $apiURL = $this.ResourceContext.ResourceId
        $this.BuildObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

        if(($this.BuildObj | Measure-Object).Count -eq 0)
        {
            throw [SuppressedException] "Unable to find build pipeline in [Organization: $($this.SubscriptionContext.SubscriptionName)] [Project: $($this.ResourceContext.ResourceGroupName)]."
        }
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
                if($this.BuildObj)
                {
                    try
                    {
                        $buildDefFileName = $($this.ResourceContext.ResourceName).Replace(" ","")
                        $buildDefPath = [Constants]::AzSKTempFolderPath + "\Builds\"+ $buildDefFileName + "\";
                        if(-not (Test-Path -Path $buildDefPath))
                        {
                            mkdir -Path $buildDefPath -Force | Out-Null
                        }

                        $this.BuildObj | ConvertTo-Json -Depth 5 | Out-File "$buildDefPath\$buildDefFileName.json"
                        $searcherPath = Get-ChildItem -Path $($ToolPath.Directory.FullName) -Include "buildsearchers.xml" -Recurse
                        ."$($Toolpath.FullName)" -I $buildDefPath -S "$($searcherPath.FullName)" -f csv -Ve 1 -O "$buildDefPath\Scan"    
                        
                        $scanResultPath = Get-ChildItem -Path $buildDefPath -File -Include "*.csv"
                        
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
        }
        else {
          try {      
            if([Helpers]::CheckMember($this.BuildObj,"variables")) 
            {
                $varList = @();
                $noOfCredFound = 0;     
                $patterns = $this.ControlSettings.Patterns | where {$_.RegexCode -eq "Build"} | Select-Object -Property RegexList;
    
            try {
                $apiURL = "https://extmgmt.dev.azure.com/{0}/_apis/ExtensionManagement/InstalledExtensions/ADOScanner/ADOSecurityScanner/Data/Scopes/Default/Current/Collections/MyCollection/Documents/ControlSettings.json?api-version=5.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
                $resObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL); 
                 
                if($resObj -and [Helpers]::CheckMember($resObj,"ControlSettings")){
                    $ControlSettings = $resObj.ControlSettings | ConvertFrom-Json;;
            
                    if( ($ControlSettings) -and ([Helpers]::CheckMember($ControlSettings,"Patterns")) ){
        
                        $custPatternsRegList = $ControlSettings.Patterns | where {$_.RegexCode -eq "Build"} | Select-Object -Property RegexList
                        #$patterns.RegexList += $custPatternsRegList.RegexList;     
                        $patterns.RegexList = [Helpers]::MergeObjects($patterns.RegexList, $custPatternsRegList.RegexList)	   
                        #$patterns.RegexList = $patterns.RegexList | select -Unique;  
                     }
                     $ControlSettings = $null;
                }
                $resObj = $null;
                }
                catch {
                    $controlResult.AddMessage($_);
                }
                
                Get-Member -InputObject $this.BuildObj.variables -MemberType Properties | ForEach-Object {
                if([Helpers]::CheckMember($this.BuildObj.variables.$($_.Name),"value") -and  (-not [Helpers]::CheckMember($this.BuildObj.variables.$($_.Name),"isSecret")))
                {
                   $propertyName = $_.Name
                  for ($i = 0; $i -lt $patterns.RegexList.Count; $i++) {
                    if ($this.BuildObj.variables.$($propertyName).value -match $patterns.RegexList[$i]) { 
                        $noOfCredFound +=1
                        $varList += "$propertyName ";   
                        break  
                        }
                    }
                } 
                }
                if($noOfCredFound -gt 0)
                {
                    $varList = $varList | select -Unique
                    $controlResult.AddMessage([VerificationResult]::Failed,
                    "Found credentials in build definition. Variables name: $varList" );
                }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed, "No credentials found in build definition.");
            }
            $patterns = $null;
            }
        }
        catch {
            $controlResult.AddMessage([VerificationResult]::Manual, "Could not fetch the build definition.");
            $controlResult.AddMessage($_);
        }    
      } 
     return $controlResult;
    }

    hidden [ControlResult] CheckInActiveBuild([ControlResult] $controlResult)
    {
        if($this.BuildObj)
        {
            $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery/project/{1}?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName),$($this.BuildObj.project.id);
            $inputbody =  "{
                'contributionIds': [
                    'ms.vss-build-web.ci-data-provider'
                ],
                'dataProviderContext': {
                    'properties': {
                        'definitionIds': '$($this.BuildObj.id)',
                        'definitionId': '$($this.BuildObj.id)',
                        'view': 'buildsHistory',
                        'hubQuery': 'true',
                        'sourcePage': {
                            'url': 'https://$($this.SubscriptionContext.SubscriptionName).visualstudio.com/$($this.BuildObj.project.name)/_build?definitionId=$($this.BuildObj.id)',
                            'routeId': 'ms.vss-build-web.ci-definitions-hub-route',
                            'routeValues': {
                                'project': '$($this.BuildObj.project.name)',
                                'viewname': 'definitions',
                                'controller': 'ContributedPage',
                                'action': 'Execute'
                            }
                        }
                    }
                }
        }"  | ConvertFrom-Json #-f $($this.BuildObj.id),$this.SubscriptionContext.SubscriptionName,$this.BuildObj.project.name

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
                $recentBuilds = $null;
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                "No build history found.");
            }
            $builds = $null;
            $responseObj = $null;
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
        try
        {
            if($this.SecurityNamespaceId -and $this.BuildObj.project.id)
            {
                # Here 'permissionSet' = security namespace identifier, 'token' = project id and 'tokenDisplayVal' = build name
                $apiURL = "https://{0}.visualstudio.com/{1}/_admin/_security/index?useApiUrl=true&permissionSet={2}&token={3}%2F{4}&tokenDisplayVal={5}&style=min" -f $($this.SubscriptionContext.SubscriptionName), $($this.BuildObj.project.id), $($this.SecurityNamespaceId), $($this.BuildObj.project.id), $($this.BuildObj.id), $($this.BuildObj.name) ;
                $header = [WebRequestHelper]::GetAuthHeaderFromUri($apiURL);
                $responseObj = Invoke-RestMethod -Method Get -Uri $apiURL -Headers $header -UseBasicParsing
                $responseObj = ($responseObj.SelectNodes("//script") | Where-Object { $_.class -eq "permissions-context" }).InnerXML | ConvertFrom-Json; 
                if($responseObj -and [Helpers]::CheckMember($responseObj,"inheritPermissions") -and $responseObj.inheritPermissions -eq $true)
                {
                    $controlResult.AddMessage([VerificationResult]::Failed,"Inherited permissions are enabled on build pipeline.",$responseObj);
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,"Inherited permissions are disabled on build pipeline.");    
                }
                $header = $null;
                $responseObj = $null;
                
            }
        }
        catch
        {
            $controlResult.AddMessage([VerificationResult]::Manual,"Unable to fetch build pipeline details. $($_). Please verify from portal that permission inheritance is turned OFF.");
        }

        return $controlResult
    }

    hidden [ControlResult] CheckRBACAccess([ControlResult] $controlResult)
    {
        $failMsg = $null
        try
        {
            # Here 'permissionSet' = security namespace identifier, 'token' = project id and 'tokenDisplayVal' = build name
            $buildDefinitionPath = $this.BuildObj.Path.Trim("\").Replace(" ","+").Replace("\","%2F")
            $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/ReadExplicitIdentitiesJson?__v=5&permissionSetId={2}&permissionSetToken={3}%2F{4}%2F{5}" -f $($this.SubscriptionContext.SubscriptionName), $($this.BuildObj.project.id), $($this.SecurityNamespaceId), $($this.BuildObj.project.id), $($buildDefinitionPath), $($this.BuildObj.id);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
            $accessList = @()
            $whitelistedUserIdentities = @()
            # release owner
            $whitelistedUserIdentities += $this.BuildObj.authoredBy.id
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
                        $apiURL = $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/DisplayPermissions?__v=5&tfid={2}&permissionSetId={3}&permissionSetToken={4}%2F{5}%2F{6}" -f $($this.SubscriptionContext.SubscriptionName), $($this.BuildObj.project.id), $($identity.TeamFoundationId) ,$($this.SecurityNamespaceId),$($this.BuildObj.project.id), $($buildDefinitionPath), $($this.BuildObj.id);
                        $identityPermissions = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                        return @{ IdentityName = $identity.DisplayName; IdentityType = $identity.IdentityType; Permissions = ($identityPermissions.Permissions | Select-Object @{Name="Name"; Expression = {$_.displayName}},@{Name="Permission"; Expression = {$_.permissionDisplayString}}) }
                    }
                }

                $accessList += $responseObj.identities | Where-Object { $_.IdentityType -eq "group" } | ForEach-Object {
                    $identity = $_ 
                    $apiURL = "https://{0}.visualstudio.com/{1}/_api/_security/DisplayPermissions?__v=5&tfid={2}&permissionSetId={3}&permissionSetToken={4}%2F{5}%2F{6}" -f $($this.SubscriptionContext.SubscriptionName), $($this.BuildObj.project.id), $($identity.TeamFoundationId) ,$($this.SecurityNamespaceId),$($this.BuildObj.project.id), $($buildDefinitionPath), $($this.BuildObj.id);
                    $identityPermissions = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                    return @{ IdentityName = $identity.DisplayName; IdentityType = $identity.IdentityType; IsAadGroup = $identity.IsAadGroup ;Permissions = ($identityPermissions.Permissions | Select-Object @{Name="Name"; Expression = {$_.displayName}},@{Name="Permission"; Expression = {$_.permissionDisplayString}}) }
                }
            }
            if(($accessList | Measure-Object).Count -ne 0)
            {
                $accessList= $accessList | Select-Object -Property @{Name="IdentityName"; Expression = {$_.IdentityName}},@{Name="IdentityType"; Expression = {$_.IdentityType}},@{Name="Permissions"; Expression = {$_.Permissions}}
                $controlResult.AddMessage([VerificationResult]::Verify,"Validate that the following identities have been provided with minimum RBAC access to [$($this.ResourceContext.ResourceName)] pipeline.", $accessList);
                $controlResult.SetStateData("Build pipeline access list: ", $accessList);
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Passed,"No identities have been explicitly provided with RBAC access to [$($this.ResourceContext.ResourceName)] other than build pipeline owner and default groups");
                $controlResult.AddMessage("List of whitelisted user identities:",$whitelistedUserIdentities)
            } 
           # $accessList = $null;
            $responseObj = $null;
        }
        catch
        {
            $failMsg = $_
        }

        if(![string]::IsNullOrEmpty($failMsg))
        {
            $controlResult.AddMessage([VerificationResult]::Manual,"Unable to fetch build pipeline details. $($failMsg)Please verify from portal all teams/groups are granted minimum required permissions on build definition.");
        }

        return $controlResult
    }

    hidden [ControlResult] CheckSettableAtQueueTime([ControlResult] $controlResult)
	{
      try { 
       
        if([Helpers]::CheckMember($this.BuildObj,"variables")) 
        {
           $setablevar =@();
           $nonsetablevar =@();
          
           Get-Member -InputObject $this.BuildObj.variables -MemberType Properties | ForEach-Object {
            if([Helpers]::CheckMember($this.BuildObj.variables.$($_.Name),"allowOverride") )
            {
                $setablevar +=  $_.Name;
            }
            else {
                $nonsetablevar +=$_.Name;  
            }
           } 
           if(($setablevar | Measure-Object).Count -gt 0){
                $controlResult.AddMessage([VerificationResult]::Verify,"The below variables are settable at queue time",$setablevar);
                $controlResult.SetStateData("Variables settable at queue time: ", $setablevar);
                if ($nonsetablevar) {
                    $controlResult.AddMessage("The below variables are not settable at queue time",$nonsetablevar);      
                } 
           }
                 
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Passed,"No variables are found in the build pipeline");   
        }
       }  
       catch {
           $controlResult.AddMessage([VerificationResult]::Manual,"Unable to fetch build pipeline variables.");   
       }
     return $controlResult;
    }

    hidden [ControlResult] ExternalSourceSelfHostedBuild([ControlResult] $controlResult)
    {
        if(($this.BuildObj | Measure-Object).Count -gt 0)
        {
           if( $this.BuildObj.repository.type -eq 'Git'){

              $sourceobj = $this.BuildObj.repository | Select-Object -Property @{Name="Name"; Expression = {$_.Name}},@{Name="Type"; Expression = {$_.type}}, @{Name="Agent"; Expression = {$this.BuildObj.queue.name}}

              if (($this.BuildObj.queue.name -eq 'Azure Pipelines' -or $this.BuildObj.queue.name -eq 'Hosted')) {
                $controlResult.AddMessage([VerificationResult]::Passed,"Pipeline code is built on a hosted agent from trusted source.",  $sourceobj); 
               }
               else {
                $controlResult.AddMessage([VerificationResult]::Verify,"Pipeline code is built on a self hosted agent from untrusted external source.", $sourceobj );   
               }
               $sourceobj = $null;
           }
           else {
            $controlResult.AddMessage([VerificationResult]::Verify,"Pipeline build code is built from external sources.");   
           }
        }

        return $controlResult;
    }


}