Set-StrictMode -Version Latest 
class Build: SVTBase
{    

    hidden [PSObject] $BuildObj;
    hidden [string] $SecurityNamespaceId;
    
    Build([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        # Get security namespace identifier of current build.
        $apiURL = "https://dev.azure.com/{0}/_apis/securitynamespaces?api-version=5.0" -f $($this.SubscriptionContext.SubscriptionName)
        $securityNamespacesObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $this.SecurityNamespaceId = ($securityNamespacesObj | Where-Object { ($_.Name -eq "Build") -and ($_.actions.name -contains "ViewBuilds")}).namespaceId

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
      try {      
        if([Helpers]::CheckMember($this.BuildObj,"variables")) 
        {

            $CredPatternList = @();
            $noOfCredFound =0;
            [xml] $patterns = [ConfigurationManager]::LoadServerConfigFile("CredentialPatterns.xml")

            if([Helpers]::CheckMember($patterns,"ArrayOfContentSearcher.ContentSearcher"))
            {
                $patterns.ArrayOfContentSearcher.ContentSearcher |   where {$_.ResourceMatchPattern -like '*json*'} | % {
                    $_.ContentSearchPatterns | Foreach-Object { $CredPatternList+= $_.string}} 
                    #$CredPatternList = (('^' + (($CredPatternList |foreach {[regex]::escape($_)}) -join '|') + '$')) -replace '[\\]',''
                    Get-Member -InputObject $this.BuildObj.variables  -MemberType Properties | ForEach-Object {
                    if([Helpers]::CheckMember($this.BuildObj.variables.$($_.Name),"value") -and  (-not [Helpers]::CheckMember($this.BuildObj.variables.$($_.Name),"isSecret")))
                    {

                        $propertyName = $_.Name
                        $CredPatternList | %{
                            $pattern = $_
                            if($this.BuildObj.variables.$($propertyName).value -match $pattern)
                            {
                                $noOfCredFound +=1
                            }
                        }
                        
                        # if($this.BuildObj.variables.$($_.Name).value -match $CredPatternList)
                        # {
                        #     $noOfCredFound +=1
                        # }
                    }
                    
                    }
                      
            }
            if($noOfCredFound -gt 0)
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                "Found credentials in build definition. Total credentials found: $noOfCredFound");
            }
        else {
            $controlResult.AddMessage([VerificationResult]::Passed, "No credentials found in build definition.");
        }
        }
    }
    catch {
        $controlResult.AddMessage([VerificationResult]::Manual, "Could not evaluated build definition.");
        $controlResult.AddMessage($_);
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
        $failMsg = $null
        try
        {
            if($this.SecurityNamespaceId -and $this.BuildObj.project.id)
            {
                # Here 'permissionSet' = security namespace identifier, 'token' = project id and 'tokenDisplayVal' = build name
                $apiURL = "https://{0}.visualstudio.com/{1}/_admin/_security/index?useApiUrl=true&permissionSet={2}&token={3}%2F{4}&tokenDisplayVal={5}&style=min" -f $($this.SubscriptionContext.SubscriptionName), $($this.BuildObj.project.id), $($this.SecurityNamespaceId), $($this.BuildObj.project.id), $($this.BuildObj.id), $($this.BuildObj.name) ;
                $header = [WebRequestHelper]::GetAuthHeaderFromUri($apiURL);
                $responseObj = Invoke-RestMethod -Method Get -Uri $apiURL -Headers $header -UseBasicParsing
                $responseObj = ($responseObj.SelectNodes("//script") | Where-Object { $_.class -eq "permissions-context" }).InnerXML | ConvertFrom-Json; 
                if(!$responseObj -or ![Helpers]::CheckMember($responseObj,"inheritPermissions"))
                {
                    $controlResult.AddMessage([VerificationResult]::Failed,"Unable to verify inherit permission option. Please navigate to the your build pipeline and verify that inherit permission is disabled.",$responseObj);
                }
                elseif($responseObj.inheritPermissions -eq $true)
                {
                    $controlResult.AddMessage([VerificationResult]::Failed,"Inherited permissions are allowed on build pipeline.");
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Passed,"Inherited permissions are disabled on release pipeline.");    
                }
            }
        }
        catch
        {
            #TODO: added temporarily to check 
            Write-Error $_.Exception.Message;             
            $failMsg = $_
        }
        
        if(![string]::IsNullOrEmpty($failMsg))
        {
            $controlResult.AddMessage([VerificationResult]::Manual,"Unable to fetch build pipeline details. $($failMsg). Please verify from portal that permission inheritance is turned OFF.");
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
                $accessList= $accessList | Select-Object -Property @{Name="IdentityName"; Expression = {$_.IdentityName}},@{Name="IdentityType"; Expression = {$_.IdentityType}},@{Name="Permissions"; Expression = {$_.Permissions}} | Format-Table
                $controlResult.AddMessage([VerificationResult]::Verify,"Validate that the following identities have been provided with minimum RBAC access to [$($this.ResourceContext.ResourceName)] pipeline.", $accessList);
                $controlResult.SetStateData("Build pipeline access list: ", $accessList);
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Passed,"No identities have been explicitly provided with RBAC access to [$($this.ResourceContext.ResourceName)] other than build pipeline owner and default groups");
                $controlResult.AddMessage("List of whitelisted user identities:",$whitelistedUserIdentities)
            } 
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
           if($setablevar -or $nonsetablevar){
            $controlResult.AddMessage([VerificationResult]::Verify,"");
              if($setablevar)  { 
                $controlResult.AddMessage("The below variables are settable at queue time",$setablevar);   
              }
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

              $sourceobj = $this.BuildObj.repository | Select-Object -Property @{Name="Name"; Expression = {$_.Name}},@{Name="Type"; Expression = {$_.type}}, @{Name="Agent"; Expression = {$this.BuildObj.queue.name}} | Format-Table

              if (($this.BuildObj.queue.name -eq 'Azure Pipelines' -or $this.BuildObj.queue.name -eq 'Hosted')) {
                $controlResult.AddMessage([VerificationResult]::Passed,"Pipeline code is built on a hosted agent from trusted source.",  $sourceobj); 
               }
               else {
                $controlResult.AddMessage([VerificationResult]::Verify,"Pipeline code is built on a self hosted agent from untrusted external source.", $sourceobj );   
               }
           }
           else {
            $controlResult.AddMessage([VerificationResult]::Verify,"Pipelines build code is from external sources.");   
           }
        }

        return $controlResult;
    }


}