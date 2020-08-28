Set-StrictMode -Version Latest 
class Build: ADOSVTBase
{    

    hidden [PSObject] $BuildObj;
    hidden [string] $SecurityNamespaceId;
    hidden static [PSObject] $SecurityNamespacesObj = $null;
    hidden static [PSObject] $BuildVarNames = @{};
    
    Build([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        # Get security namespace identifier of current build.
        $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
        if ([Build]::SecurityNamespacesObj -eq $null)
        {
            [Build]::SecurityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        }
        $this.SecurityNamespaceId = ([Build]::SecurityNamespacesObj | Where-Object { ($_.Name -eq "Build") -and ($_.actions.name -contains "ViewBuilds")}).namespaceId

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
                            New-Item -ItemType Directory -Path $buildDefPath -Force | Out-Null
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
            if([Helpers]::CheckMember($this.BuildObj[0],"variables")) 
            {
                $varList = @();
                $noOfCredFound = 0;     
                $patterns = $this.ControlSettings.Patterns | where {$_.RegexCode -eq "SecretsInBuild"} | Select-Object -Property RegexList;
                $exclusions = $this.ControlSettings.Build.ExcludeFromSecretsCheck;
                if(($patterns | Measure-Object).Count -gt 0)
                {                
                    Get-Member -InputObject $this.BuildObj[0].variables -MemberType Properties | ForEach-Object {
                        if([Helpers]::CheckMember($this.BuildObj[0].variables.$($_.Name),"value") -and  (-not [Helpers]::CheckMember($this.BuildObj[0].variables.$($_.Name),"isSecret")))
                        {
                            
                            $buildVarName = $_.Name
                            $buildVarValue = $this.BuildObj[0].variables.$buildVarName.value 
                            <# helper code to build a list of vars and counts
                            if ([Build]::BuildVarNames.Keys -contains $buildVarName)
                            {
                                    [Build]::BuildVarNames.$buildVarName++
                            }
                            else 
                            {
                                [Build]::BuildVarNames.$buildVarName = 1
                            }
                            #>
                            if ($exclusions -notcontains $buildVarName)
                            {
                                for ($i = 0; $i -lt $patterns.RegexList.Count; $i++) {
                                    #Note: We are using '-cmatch' here. 
                                    #When we compile the regex, we don't specify ignoreCase flag.
                                    #If regex is in text form, the match will be case-sensitive.
                                    if ($buildVarValue -cmatch $patterns.RegexList[$i]) { 
                                        $noOfCredFound +=1
                                        $varList += " $buildVarName";   
                                        break  
                                        }
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
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Manual, "Regular expressions for detecting credentials in pipeline variables are not defined in your organization.");    
                }
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "No variables found in build definition.");
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

        $orgURL='https://{0}.visualstudio.com/{1}/_build?view=folders' -f $($this.SubscriptionContext.SubscriptionName),$($this.BuildObj.project.name)
        $inputbody="{'contributionIds':['ms.vss-build-web.pipelines-data-provider'],'dataProviderContext':{'properties':{'definitionIds':'$($this.BuildObj.id)','sourcePage':{'url':'$orgURL','routeId':'ms.vss-build-web.pipelines-hub-route','routeValues':{'project':'$($this.BuildObj.project.name)','viewname':'pipelines','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
        $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);

        if([Helpers]::CheckMember($responseObj,"dataProviders") -and $responseObj.dataProviders.'ms.vss-build-web.pipelines-data-provider' -and [Helpers]::CheckMember($responseObj.dataProviders.'ms.vss-build-web.pipelines-data-provider',"pipelines") -and  $responseObj.dataProviders.'ms.vss-build-web.pipelines-data-provider'.pipelines)
        {

            $builds = $responseObj.dataProviders.'ms.vss-build-web.pipelines-data-provider'.pipelines

            if(($builds | Measure-Object).Count -gt 0 )
            {
                
                    if ($builds[0].latestRun -ne $null -and [datetime]::Parse( $builds[0].latestRun.queueTime) -gt (Get-Date).AddDays( - $($this.ControlSettings.Build.BuildHistoryPeriodInDays))) {
                        $controlResult.AddMessage([VerificationResult]::Passed,
                            "Found recent builds triggered within $($this.ControlSettings.Build.BuildHistoryPeriodInDays) days");
                    }               
                
                
                    else {
                        $controlResult.AddMessage([VerificationResult]::Failed,
                            "No recent build history found in last $($this.ControlSettings.Build.BuildHistoryPeriodInDays) days");
                    }
                
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
            $exemptedUserIdentities = @()
            # release owner
            $exemptedUserIdentities += $this.BuildObj.authoredBy.id
            if(($responseObj.identities|Measure-Object).Count -gt 0)
            {
                $exemptedUserIdentities += $responseObj.identities | Where-Object { $_.IdentityType -eq "user" }| ForEach-Object {
                    $identity = $_
                    $exemptedIdentity = $this.ControlSettings.Build.ExemptedUserIdentities | Where-Object { $_.Domain -eq $identity.Domain -and $_.DisplayName -eq $identity.DisplayName }
                    if(($exemptedIdentity | Measure-Object).Count -gt 0)
                    {
                        return $identity.TeamFoundationId
                    }
                }

                $accessList += $responseObj.identities | Where-Object { $_.IdentityType -eq "user" } | ForEach-Object {
                    $identity = $_ 
                    if($exemptedUserIdentities -notcontains $identity.TeamFoundationId)
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
                $controlResult.AddMessage("List of exempted user identities:",$exemptedUserIdentities)
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
        
        if([Helpers]::CheckMember($this.BuildObj[0],"variables")) 
        {
           $setablevar =@();
           $nonsetablevar =@();
          
           Get-Member -InputObject $this.BuildObj[0].variables -MemberType Properties | ForEach-Object {
            if([Helpers]::CheckMember($this.BuildObj[0].variables.$($_.Name),"allowOverride") )
            {
                $setablevar +=  $_.Name;
            }
            else {
                $nonsetablevar +=$_.Name;  
            }
           } 
           if(($setablevar | Measure-Object).Count -gt 0){
                $controlResult.AddMessage([VerificationResult]::Verify,"The below variables are settable at queue time : ",$setablevar);
                $controlResult.SetStateData("Variables settable at queue time : ", $setablevar);
                if ($nonsetablevar) {
                    $controlResult.AddMessage("The below variables are not settable at queue time : ",$nonsetablevar);      
                } 
           }
           else
           {
                $controlResult.AddMessage([VerificationResult]::Passed, "No variables were found in the build pipeline that are settable at queue time.");   
           }
                 
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Passed,"No variables were found in the build pipeline");   
        }
       }  
       catch {
           $controlResult.AddMessage([VerificationResult]::Manual,"Could not fetch build pipeline variables.");   
       }
     return $controlResult;
    }

    hidden [ControlResult] CheckSettableAtQueueTimeForURL([ControlResult] $controlResult) 
    {
        try 
        { 
            if ([Helpers]::CheckMember($this.BuildObj[0], "variables")) 
            {
                $settableURLVars = @();
                $count = 0;
                $patterns = $this.ControlSettings.Patterns | where {$_.RegexCode -eq "URLs"} | Select-Object -Property RegexList;

                if(($patterns | Measure-Object).Count -gt 0){                
                    Get-Member -InputObject $this.BuildObj[0].variables -MemberType Properties | ForEach-Object {
                        if ([Helpers]::CheckMember($this.BuildObj[0].variables.$($_.Name), "allowOverride") )
                        {
                            $varName = $_.Name;
                            $varValue = $this.BuildObj[0].variables.$($varName).value;
                            for ($i = 0; $i -lt $patterns.RegexList.Count; $i++) {
                                if ($varValue -match $patterns.RegexList[$i]) { 
                                    $count +=1
                                    $settableURLVars += @( [PSCustomObject] @{ Name = $varName; Value = $varValue } )  
                                    break  
                                }
                            }
                        }
                    } 
                    if ($count -gt 0) 
                    {
                        $controlResult.AddMessage([VerificationResult]::Failed, "Found variables that are settable at queue time and contain URL value : ", $settableURLVars);
                        $controlResult.SetStateData("List of variables settable at queue time and containing URL value : ", $settableURLVars);
                    }
                    else {
                        $controlResult.AddMessage([VerificationResult]::Passed, "No variables were found in the build pipeline that are settable at queue time and contain URL value.");   
                    }
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Manual, "Regular expressions for detecting URLs in pipeline variables are not defined in your organization.");    
                }
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "No variables were found in the build pipeline.");   
            }
        }  
        catch 
        {
            $controlResult.AddMessage([VerificationResult]::Manual, "Could not fetch variables of the build pipeline.");   
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