#Acquire Access token
class PIM: AzCommandBase {
    hidden $APIroot = [string]::Empty
    hidden $headerParams = "";
    hidden $UserId = "";
    hidden  $AccessToken = "";
    hidden $AccountId = "" ;
    hidden $abortflow = 0;
    hidden $controlSettings;
    PIM([string] $subscriptionId, [InvocationInfo] $invocationContext)
    : Base([string] $subscriptionId, [InvocationInfo] $invocationContext) {
        $this.DoNotOpenOutputFolder = $true;
        $this.AccessToken = "";
        $this.AccountId = "";
        $this.APIroot = "https://api.azrbac.mspim.azure.com/api/v2/privilegedAccess/azureResources";
        $this.ControlSettings= [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");
    }
  
    #Acquire Access token
    AcquireToken() {
        # Using helper method to get current context and access token   
        $ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
        [ContextHelper]::ResetCurrentRMContext
        if([Helpers]::CheckMember($this.ControlSettings,'PIMAppId'))
        {
            if(-not ([string]::IsNullOrEmpty($this.ControlSettings.PIMAppId)))
            {
                $this.AccessToken = Get-AzSKAccessToken -ResourceAppIdURI $this.ControlSettings.PIMAppId;
            }
        }
        else
        {
            $this.AccessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI);
        }
        $this.headerParams = @{'Authorization' = "Bearer $($this.AccessToken)" }
        $this.AccountId = [ContextHelper]::GetCurrentSessionUser()
        $ADUserDetails = Get-AzADUser -UserPrincipalName  $this.AccountId
        if($null -ne $ADUserDetails) {
        $this.UserId = ($ADUserDetails).Id
        }
        
        
    
    }

    #Gets the jit assignments for logged-in user
    hidden [PSObject] MyJitAssignments() {
        $this.AcquireToken();  
        if( -not [string]::IsNullOrEmpty($this.UserId))
        {  
            $urlme = $this.APIroot + "/roleAssignments?`$expand=linkedEligibleRoleAssignment,subject,roleDefinition(`$expand=resource)&`$filter=(subject/id%20eq%20%27$($this.UserId)%27)"
            $assignments = [WebRequestHelper]::InvokeWebRequest('Get', $urlme, $this.headerParams, $null, [string]::Empty, $false, $false )
            $assignments = $assignments | Sort-Object  roleDefinition.resource.type , roleDefinition.resource.displayName
            $obj = @()        
            if (($assignments | Measure-Object).Count -gt 0) {
                $i = 0
                foreach ($assignment in $assignments) {
                    $item = New-Object psobject -Property @{
                        Id             = ++$i
                        IdGuid         = $assignment.id
                        ResourceId     = $assignment.roleDefinition.resource.id
                        OriginalId     = $assignment.roleDefinition.resource.externalId
                        ResourceName   = $assignment.roleDefinition.resource.displayName
                        ResourceType   = $assignment.roleDefinition.resource.type
                        RoleId         = $assignment.roleDefinition.id
                        RoleName       = $assignment.roleDefinition.displayName
                        ExpirationDate = $assignment.endDateTime
                        SubjectId      = $assignment.subject.id
                        AssignmentState = $assignment.assignmentState
                    }
                    $obj = $obj + $item
                }
            }
            
            return $obj
        }
        else {
            return $null
        }
    }

    # this method is an overlaod of existing PIMResolver method, this is to facilitate a seperate flow for pim operations at management group scope
    hidden [PIMResource[]] PIMResourceResolver($ManagementGroupId, $IsActivationRequest)
    {
        $resolvedResource =  @()
        if($IsActivationRequest)
        {
            
            $resolvedResource = [array][PIMResource]::new()
            $eligibleAssignments = $this.MyJitAssignments();
            $resolvedResources = @();
            if($null -ne $eligibleAssignments)
            {
                $resolvedResources = $eligibleAssignments | Where-Object{$_.OriginalId -eq ("/providers/Microsoft.Management/managementGroups/$ManagementGroupId") }
            
                foreach($res in $resolvedResources)
                {
                    $resObj = [PIMResource]::new()
                    $resObj.ExternalId = $res.OriginalId
                    $resObj.ResourceName = $res.ResourceName
                    $resObj.ResourceId = $res.ResourceId
                    $resolvedResource += $resObj
                }
            }
            else
            {
                $this.PublishCustomMessage("No PIM Eligible assignment found for the current context: $($this.AccountId).",[MessageType]::Warning)
            }



        }
        else
        {
            $resources = $this.ListResources($null, "managementgroup", $ManagementGroupId);
            $resolvedResource = $resources | Where-Object {$_.ExternalId -eq "/providers/Microsoft.Management/managementGroups/$($ManagementGroupId)"}
        }
        return $resolvedResource;
    }

    # This function resolves the resource that matches to parameters passed in command
    hidden [PIMResource[]] PIMResourceResolver( $SubscriptionId, $ResourceGroupName, $ResourceName, $IsActivationRequest) {
        $this.AcquireToken();  
        $rtype = 'subscription'
        $selectedResourceName = $SubscriptionId.Trim()
    
        if (-not([string]::IsNullOrEmpty($resourcegroupName))) {
            $selectedResourceName = $resourcegroupName;
            $rtype = 'resourcegroup'
        }
        if (-not([string]::IsNullOrEmpty($resourceName))) {
            $selectedResourceName = $resourceName;
            $rtype = 'resource'
        }
        $item = New-Object psobject -Property @{
            ResourceType = $rtype
            ResourceName = $selectedResourceName
        }
        $resolvedResource = [PIMResource]::new()
        if($IsActivationRequest)
        {
            $myAssignments = $this.MyJitAssignments();
            if($null -ne $myAssignments)
            {
                $resolvedResources = ($myAssignments | Where-Object {$_.OriginalId -match $SubscriptionId})
                $PIMResources = @();            
                if(($resolvedResources | Measure-Object).Count -gt 0 )
                {
                        if( $item.ResourceType -eq 'subscription')
                        {
                            $resolvedResources = $resolvedResources | Where-Object{$_.OriginalId -eq ("/subscriptions/$($SubscriptionId)") }
                        }
                        if( $item.ResourceType -eq 'resourcegroup')
                        {
                            $rgId  = [string]::Format("/subscriptions/{0}/resourceGroups/{1}",$SubscriptionId,$ResourceGroupName)
                            $resolvedResources = $resolvedResources | Where-Object{$_.OriginalId -eq $rgId }
                        }
                        if( $item.ResourceType -eq 'resource'){
                            $rgId  = [string]::Format("/subscriptions/{0}/resourceGroups/{1}",$SubscriptionId,$ResourceGroupName)
                            $resolvedResources = $resolvedResources | Where-Object{$_.OriginalId -like "$rgId*" -and $_.ResourceName-eq $ResourceName }
                            # if multiple resources with same name under one rg are found, ask the end user to choose the resource
                            if(($resolvedResources|Measure-Object).Count -gt 1)
                            {   $counter=0; $tempres = @();
                                foreach ($resource in $resolvedResources)
                                {
                                    $item = New-Object psobject -Property @{
                                    id = ++$counter
                                    ResourceName =  $resource.ResourceName
                                    OriginalId =  $resource.OriginalId
                                    }
                                    $tempres+=$item
                                }
                                [int]$choice = -1;
                                $this.PublishCustomMessage("Multiple resources with same resource name are found. ")                            
                                $this.PublishCustomMessage(($tempres | Format-Table Id, OriginalId | Out-String))
                                Write-Host "Please enter 'Id' from the above table for the resource you want to activate your assignment on." -ForegroundColor Yellow
                                try{ 
                                    $choice = Read-Host
                                    if($choice -notin $tempres.Id)
                                    {
                                        throw "Invalid Input provided";
                                    }
                                }
                                catch
                                {
                                    throw "Invalid Input provided";
                                    
                                }
                            $resolvedResources= $resolvedResources | Where-Object{$_.OriginalId -eq $tempres[$choice-1].OriginalId }
                                
                            }
                    }
                    if(($resolvedResources|Measure-Object).Count -gt 0)
                    {
                        $resObj = [PIMResource]::new()
                        foreach($res in $resolvedResources)
                        {
                            $resObj.ExternalId = $res.OriginalId
                            $resObj.ResourceName = $res.ResourceName
                            $resObj.ResourceId = $res.ResourceId
                            $PIMResources += $resObj
                        }
                    } 
                }
                return $PIMResources;
            }
            else
            {
                $this.PublishCustomMessage("No PIM Eligible assignments found for the current context: $($this.AccountId).",[MessageType]::Warning)
                return $null
            }

        }
        else
        {
            $resources = $this.ListResources($SubscriptionId, $item.ResourceType, $item.ResourceName);
            
            
            if($item.ResourceType -eq 'resource')
            {
                $resolvedResource = $resources | Where-Object { $_.ResourceName -eq $item.ResourceName}
                #If context has access over resourcegroups or resources with same name, get a match based on Subscription and rg passed in param
                if (($resolvedResource | Measure-Object).Count -gt 1) {       
            
                    $resolvedResource = $resolvedResource | Where-Object { $_.ExternalId -match $SubscriptionId }
                    if (-not([string]::IsNullOrEmpty($ResourceGroupName)) -and  ($resolvedResource | Measure-Object).Count -gt 0) {
                        $resolvedResource = $resolvedResource | Where-Object { $_.ExternalId -match $ResourceGroupName }
                    }
            
                }
            }
            else
            {
                
                if($item.ResourceType -eq 'subscription')
                {
                    $resolvedResource.ExternalId = "/subscriptions/$($item.ResourceName)"
                }
                elseif($item.ResourceType -eq 'resourcegroup')
                {
                    $resolvedResource.ExternalId = "/subscriptions/$($SubscriptionId.Trim())/resourceGroups/$($item.ResourceName)"
                }
                
                if($null -ne $resources)
                {
                    $temp = $resources | Where-Object { $_.ExternalId -eq $resolvedResource.ExternalId}
                    if(($temp| Measure-Object).Count -gt 0)
                    {
                        $resolvedResource = $temp
                    }
                }
            }
            
             return $resolvedResource   
        }

        
    }

    #List all the resources accessible to context.
    hidden [System.Collections.Generic.List[PIMResource]] ListResources($Guid, $type, $resourceName) {
        $this.AcquireToken();
        $resources = $null
        $resourceUrl = $null
        if($type -ne'managementGroup')
        {
            Set-AzContext -SubscriptionId $Guid | Out-Null 
        }
        # This seperation is required due to nature of API, it operates in paging/batching manner when we query for all types
        # Note: At present, we do not provide PIM operation management for management group. However, if needed in the future, it can be added in the else statement. >> $filter=(type%20eq%20%27managementgroup%27)
        
        if($type -eq 'managementGroup')
        {
            # Fetch PIM details of the all subscriptions user has access to
            $resourceUrl = $this.APIroot + "/resources?`$filter=(type%20eq%20%27managementgroup%27)&`$orderby=type"
        }
        if($type -eq 'subscription')
        {
            # Fetch PIM details of the all subscriptions user has access to
            
            $useDiscoveryAPI = $false
            # If environment variable AzSKPIMLatencyIssue is set to true then use Discovery API to handle latency issue
            if (Test-Path env:AzSKPIMLatencyIssue ){
                if ($Env:AzSKPIMLatencyIssue -eq $true)
                {
                    $useDiscoveryAPI = $true
                }
            }

            if ($useDiscoveryAPI){
                $resourceUrl = $this.APIroot + "/resources?/discovery?`$filter=(registeredDateTime%20ne%20null%20and%20type%20eq%20%27subscription%27)"
            }
            else
            {
                $resourceUrl = $this.APIroot + "/resources?`$filter=(type%20eq%20%27subscription%27)&`$orderby=type"
            }
        }
        elseif($type -eq 'resourcegroup')
        {
            # Fetch PIM details of the specified resource group
            $resourceUrl = $this.APIroot + "/resources?`$filter=(type%20eq%20%27resourcegroup%27)%20and%20contains(tolower(displayName),%20%27{0}%27)&`$orderby=type" -f $resourceName.ToLower()
           
        }
        elseif($type -eq 'resource')
        {
            # Fetch PIM details of the specified resource
            $resourceUrl = $this.APIroot + "/resources?`$filter=(type%20ne%20%27resourcegroup%27%20and%20type%20ne%20%27subscription%27%20and%20type%20ne%20%27managementgroup%27)%20and%20contains(tolower(displayName),%20%27{0}%27)" -f $resourceName.ToLower()
           
        }               
        
        $response = $null
        try
        {
            $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $resourceUrl -Method Get
            $values = ConvertFrom-Json $response.Content
            $resources = $values.value
            $hasOdata = $values | Get-Member -Name '@odata.nextLink'
            while ($null -ne $hasOdata -and -not([string]::IsNullOrEmpty(($values).'@odata.nextLink')))
            {
                $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $(($values).'@odata.nextLink') -Method Get
                $values = ConvertFrom-Json $response.Content
                $resources += $values.value
                $hasOdata = $values | Get-Member -Name '@odata.nextLink'
            }
        }
        catch
        {
            if([Helpers]::CheckMember($_,"ErrorDetails.Message"))
            {
                $this.PublishCustomMessage($_.ErrorDetails.Message,[MessageType]::Error)
            }
            else
            {
                $this.PublishCustomMessage($_.Exception, [MessageType]::Error)
            }
            return $null;
        }
        
        $i = 0
        $obj = New-Object "System.Collections.Generic.List[PIMResource]"
        foreach ($resource in $resources) {
            $item = New-Object PIMResource
            $item.Id = ++$i
            $item.ResourceId = $resource.id
            $item.ResourceName = $resource.DisplayName
            $item.Type = $resource.type
            $item.ExternalId = $resource.externalId
            $obj.Add($item);
        }
        return $obj
    }

    #List roles from PIM API 
    hidden [PSObject] ListRoles($resourceId) {
        $this.AcquireToken();
        $url = $this.APIroot + "/resources/" + $resourceId + "/roleDefinitions?`$select=id,displayName,type,templateId,resourceId,externalId,subjectCount,eligibleAssignmentCount,activeAssignmentCount&`$orderby=activeAssignmentCount%20desc"
        $roles = [WebRequestHelper]::InvokeWebRequest("Get", $url, $this.headerParams, $null, [string]::Empty, $false, $false )
        $i = 0
        $obj = @()
        foreach ($role in $roles) {
            $item = New-Object psobject -Property @{
                Id               = ++$i
                RoleDefinitionId = $role.id
                RoleName         = $role.DisplayName
                SubjectCount     = $role.SubjectCount
            }
            $obj = $obj + $item
        }

        return $obj 
    }

    #List Assignment for a particular resource
    hidden [PSObject] ListAssignmentsWithFilter($resourceId, $IsPermanent) {
        $this.AcquireToken()
        $url = $this.APIroot + "/resources/" + $resourceId + "`/roleAssignments?`$expand=subject,roleDefinition(`$expand=resource)"
		#NextLink handled in the web request
        $roleAssignments = [WebRequestHelper]::InvokeWebRequest('Get', $url, $this.headerParams, $null, [string]::Empty, @{} )
        $i = 0
        $obj = @()
        $assignments = @();
        foreach ($roleAssignment in $roleAssignments) {
            $item = New-Object psobject -Property @{
                Id               = ++$i
                RoleAssignmentId = $roleAssignment.id
                ResourceId       = $roleAssignment.roleDefinition.resource.id
                OriginalId       = $roleAssignment.roleDefinition.resource.externalId
                ResourceName     = $roleAssignment.roleDefinition.resource.displayName
                ResourceType     = $roleAssignment.roleDefinition.resource.type
                RoleId           = $roleAssignment.roleDefinition.id
                IsPermanent      = $roleAssignment.IsPermanent
                RoleName         = $roleAssignment.roleDefinition.displayName
                ExpirationDate   = $roleAssignment.endDateTime
                SubjectId        = $roleAssignment.subject.id
                SubjectType      = $roleAssignment.subject.type
                UserName         = $roleAssignment.subject.displayName
                AssignmentState  = $roleAssignment.AssignmentState
                MemberType       = $roleAssignment.memberType
                PrincipalName    = $roleAssignment.subject.principalName
                linkedEligibleRoleAssignmentId = $roleAssignment.linkedEligibleRoleAssignmentId
            }
            $obj = $obj + $item
        }
        if (($obj | Measure-Object).Count -gt 0) {
            if (-not $IsPermanent) {
                $assignments = $obj | Where-Object { $_.AssignmentState -eq 'Eligible' }
                
            }
            else {
                # In case of true permanent assignments and permanently eligible active the assignment state will be active. To distiguish it from Permanently Eligible PIM active assignemnts, we need to check LinkedEligibleRoleAssignmentId
                $assignments = $obj | Where-Object { $_.AssignmentState -eq 'Active' -and  ($null -eq $_.linkedEligibleRoleAssignmentId)}
                
            }
        }
        
        return $assignments
    }

    #List Permanent or PIM assignment for a resource
    hidden ListAssignment($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $CheckPermanent) {
        $this.AcquireToken();
        $criticalRoles = @();
        $resources = $null
        $criticalRoles += $this.ConvertToStringArray($RoleNames)
        if(-not([string]::IsNullOrEmpty($ManagementGroupId)))
        {
            
            $resources = $this.PIMResourceResolver($ManagementGroupId, $false);
        
        }
        else 
        {
            $resources = $this.PIMResourceResolver($SubscriptionId, $ResourceGroupName, $ResourceName,$false)   
        }
        if (($resources | Measure-Object).Count -gt 0 -and (-not [string]::IsNullOrEmpty($resources.ResourceId))) {       
            $roleAssignments = $this.ListAssignmentsWithFilter($resources.ResourceId, $CheckPermanent)
            if(($roleAssignments | Measure-Object).Count -gt 0)
            {    if(-not [String]::IsNullOrEmpty($RoleNames))
                {
                    $roleAssignments = $roleAssignments | Where-Object { $_.RoleName -in $criticalRoles -and $_.MemberType -ne 'Inherited' -and ($_.SubjectType -eq 'User' -or $_.SubjectType -eq 'Group') }
                }
                else
                {
                    $roleAssignments = $roleAssignments | Where-Object { $_.MemberType -ne 'Inherited' -and ($_.SubjectType -eq 'User' -or $_.SubjectType -eq 'Group') }
                }
                if (($roleAssignments | Measure-Object).Count -gt 0) {
                    $roleAssignments = $roleAssignments | Sort-Object -Property RoleName, Name, AssignmentState, ResourceId
                    $this.PublishCustomMessage("")
                    $this.PublishCustomMessage("Note: The assignments listed below do not include 'inherited' assignments for the scope.", [MessageType]::Warning)
                    $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default)
                    $this.PublishCustomMessage($($roleAssignments | Format-Table -Property PrincipalName, @{Label = "Role"; Expression = { $_.RoleName } },  AssignmentState, @{Label = "Type"; Expression = { $_.SubjectType } } | Out-String), [MessageType]::Default)
                    
                    $objectToExport = $roleAssignments | Select-Object RoleName, PrincipalName, UserName, ResourceType, ResourceName, SubjectType, AssignmentState,	IsPermanent
                    $this.ExportCSV($objectToExport)
                }
                else {
                    if ($CheckPermanent) {
                        $this.PublishCustomMessage("No permanent assignments found for the current context on the resource for the $($RoleNames -join ', ').", [MessageType]::Warning);
                    }
                    else {
                        $this.PublishCustomMessage("No PIM eligible assignments found for the current context on the resource for the $($RoleNames -join ', ').", [MessageType]::Warning);
                    }    
                }
            }
            else
            {
                if ($CheckPermanent) {
                    $this.PublishCustomMessage("No permanent assignments found for the provided scope and role. ",[MessageType]::Error)
                }
                else {
                    $this.PublishCustomMessage("No PIM eligible assignments found  for the provided scope and role.", [MessageType]::Warning);
                }    
            }
        }
        else {
            $this.PublishCustomMessage( "Unable to find resource on which assignment was requested. Either the resource does not exist or you may not have permissions for the requested operation.", [MessageType]::Error)
            $this.DisplayActivationHelpMessage($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName)
        }
        
    }

    hidden GetRoleSettings($PIMResourceGuid, $RoleName)
    {
       
    }
    #Activates the user assignment for a role
    hidden Activate($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName, $roleName, $Justification, $Duration) {
        $this.AcquireToken();
        $assignments = $this.MyJitAssignments()
        $resource = $null
        if(-not([string]::IsNullOrEmpty($ManagementGroupId)))
        {
            
            $resource = $this.PIMResourceResolver($ManagementGroupId,$true);
        
        }
        else 
        {
            $resource = $this.PIMResourceResolver($SubscriptionId, $ResourceGroupName, $ResourceName, $true)
        }
        
        if(($resource | Measure-Object).Count -gt 0 -and (-not [string]::IsNullOrEmpty($resource.ExternalId)))
        {
            if (($assignments | Measure-Object).Count -gt 0 ) {
                $matchingAssignment = $assignments | Where-Object { $_.OriginalId -in $resource.ExternalId -and $_.RoleName -eq $roleName -and $_.AssignmentState -eq 'Eligible' }
                $matchingAssignment = $matchingAssignment | select -Unique
                
                if (($matchingAssignment | Measure-Object).Count -gt 0) {
                    $this.PublishCustomMessage("Requesting activation of your [$($matchingAssignment.RoleName)] role on [$($matchingAssignment.ResourceName)]... ", [MessageType]::Info);
                    $resourceId = $matchingAssignment.ResourceId
                    $roleDefinitionId = $matchingAssignment.RoleId
                    $subjectId = $matchingAssignment.SubjectId
                    $RoleActivationurl = $this.APIroot + "/roleAssignmentRequests "
                    $postParams = '{"roleDefinitionId":"' + $roleDefinitionId + '","resourceId":"' + $resourceId + '","subjectId":"' + $subjectId + '","assignmentState":"Active","type":"UserAdd","reason":"' + $Justification + '","schedule":{"type":"Once","startDateTime":"' + (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + '","duration":"PT' + $Duration + 'H"},"linkedEligibleRoleAssignmentId":"' + $matchingAssignment.IdGuid + '"}'
                    try{
                    $response = [WebRequestHelper]::InvokeWebRequest('Post', $RoleActivationurl, $this.headerParams, $postParams, "application/json", $false, $true )
                        if ($response.StatusCode -eq 201) {
                            $this.PublishCustomMessage("Activation queued successfully. The role(s) should get activated in a few minutes.", [MessageType]::Update);
                        }
                    }
                    catch 
                    {
                        if([Helpers]::CheckMember($_,"ErrorDetails.Message"))
                        {
                            $err = $_ | ConvertFrom-Json
                            if ($err.error.Code -eq "RoleAssignmentRequestAcrsValidationFailed"){
                                $this.PublishCustomMessage("A Conditional Access policy is enabled for this resource. Your current sign-in does not meet the required criteria.",[MessageType]::Error)
                            }
                            else {
                                $this.PublishCustomMessage($err.error.message,[MessageType]::Error)
                            }
                        }
                        else
                        {
                            $this.PublishCustomMessage($_.Exception, [MessageType]::Error)
                        }
                    }
                }
                else {
                    $this.PublishCustomMessage("No matching eligible role found for the current context", [MessageType]::Warning)
                }
            }
            else {
                $this.PublishCustomMessage("No PIM Eligible assignments found for the current context: $($this.AccountId).",[MessageType]::Warning)
            }    
        }  
        else
        {
            $this.PublishCustomMessage( "Unable to find resource on which activation was requested. Make sure you have PIM eligible assignment on the resource.", [MessageType]::Error)
            #$this.DisplayActivationHelpMessage($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName)
        }
    
    }

    #Deactivates the activated assignment for user
    hidden Deactivate($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName, $roleName) {
        $this.AcquireToken();
        $assignments = $this.MyJitAssignments() 
        $resource = $null
        if(($assignments| Measure-Object).Count -gt 0) 
        {
            $assignments = $assignments|Where-Object { -not [string]::IsNullorEmpty($_.ExpirationDate) }
            if(-not([string]::IsNullOrEmpty($ManagementGroupId)))
            {
                
                $resource = $this.PIMResourceResolver($ManagementGroupId, $false);
            
            }
            else 
            {
                $resource = $this.PIMResourceResolver($SubscriptionId, $ResourceGroupName, $ResourceName, $false)
            }
            if (($assignments | Measure-Object).Count -gt 0 -and (-not [string]::IsNullOrEmpty($resource.ExternalId))) {
                $matchingAssignment = $assignments | Where-Object { $_.OriginalId -eq $resource.ExternalId -and $_.RoleName -eq $roleName -and $_.AssignmentState -eq 'Active' }
                if (($matchingAssignment | Measure-Object).Count -gt 0)
                {     
                    $this.PublishCustomMessage("Requesting deactivation of your [$($matchingAssignment.RoleName)] role on [$($matchingAssignment.ResourceName)]... ", [MessageType]::Info);
                    $id = $matchingAssignment.IdGuid
                    $resourceId = $matchingAssignment.ResourceId
                    $roleDefinitionId = $matchingAssignment.RoleId
                    $subjectId = $matchingAssignment.SubjectId
                    $deactivationurl = $this.APIroot + "/roleAssignmentRequests "
                    $postParams = '{"roleDefinitionId":"' + $roleDefinitionId + '","resourceId":"' + $resourceId + '","subjectId":"' + $subjectId + '","assignmentState":"Active","type":"UserRemove","linkedEligibleRoleAssignmentId":"' + $id + '"}'
                    try 
                    {
                            $response = [WebRequestHelper]::InvokeWebRequest('Post', $deactivationurl, $this.headerParams, $postParams, "application/json", $false, $true )
                            if ($response.StatusCode -eq '201') {
                                $this.PublishCustomMessage("Deactivation queued successfully. The role(s) should get deactivated in a few minutes.", [MessageType]::Update);
                            }
                    }
                    catch 
                    {
                        if([Helpers]::CheckMember($_,"ErrorDetails.Message"))
                        {
                            $err = $_ | ConvertFrom-Json
                            $this.PublishCustomMessage($err.error.message,[MessageType]::Error)
                        }
                        else
                        {
                            $this.PublishCustomMessage($_.Exception, [MessageType]::Error)
                        }
                    }
                }
                else
                {
                    $this.PublishCustomMessage("No active assignments found for the current context.", [MessageType]::Warning);
                }
            }
            else {
                $this.PublishCustomMessage("No active assignments found for the current context.", [MessageType]::Warning);
            }
        }
        else {
            $this.PublishCustomMessage("No PIM Eligible assignments found for the current context: $($this.AccountId).",[MessageType]::Warning)
        }

    }

    #Assign a user to Eligible Role
    hidden AssignExtendPIMRoleForUser($ManagementGroupId, $subscriptionId, $resourcegroupName, $resourceName, $roleName, $PrincipalName, $duration,$isExtensionRequest, $force, $isRemoveAssignmentRequest, $assignmentType) {
        $this.AcquireToken();
        $PrincipalName = $this.ConvertToStringArray($PrincipalName);
        $resolvedResources = $null;
        if(-not([string]::IsNullOrEmpty($ManagementGroupId)))
        {
            
            $resolvedResources = $this.PIMResourceResolver($ManagementGroupId, $false);
        
        }
        else 
        {
            $resolvedResources = $this.PIMResourceResolver($SubscriptionId, $ResourceGroupName, $ResourceName, $false)
        }
       
        if (($resolvedResources | Measure-Object).Count -gt 0 -and (-not [string]::IsNullOrEmpty($resolvedResources.ResourceId))) {
           # if there is same resource name inside and rg for multiple resources, we follow the AzSK standard approach to assign role on both resources
            foreach($resolvedResource in $resolvedResources)
            {
                $resourceId = $resolvedResource.ResourceId
                $roleDefinitionId =""
                $roles = $this.ListRoles($resourceId)
                try
                {
                    $roleDefinitionId = ($roles | Where-Object { $_.RoleName -eq $RoleName }).RoleDefinitionId
                }
                catch
                {
                $this.PublishCustomMessage("Unable to find matching role. Please verify the role name provided is correct.",[MessageType]::Error) 
                    return;
                }
                $users = @();
                $subjectId = @();
                $PrincipalName | ForEach-Object{
                try 
                {
                    $users += Get-AzADUser -UserPrincipalName $_
                    if(($users | Measure-Object).Count -eq 0)
                    {
                        $users += Get-AzADGroup -DisplayName $_
                        
                    }
                    $subjectId +=$users.Id
                }
                catch {
                    $this.PublishCustomMessage("Unable to find provided UPN. If it corresponds to an AD group, use Display name instead of principal name", [MessageType]::Warning)
                    return;
                }
                }
                if (($subjectId | Measure-Object).Count -lt 0) {
                          $this.PublishCustomMessage("Unable to fetch details of the principal name provided.", [MessageType]::Error)
                    return;
                }            
                
                #"If" block will exceute when -ExtendExpiringAssignments parameter is used  
                if($isExtensionRequest)
                {
                    $roleAssignments = $this.ListAssignmentsWithFilter($resourceId, $false)
                    if(($roleAssignments| Measure-Object).Count -gt 0)
                    {
                        $roleAssignments = $roleAssignments | Where-Object{$_.SubjectId -in $subjectId -and $_.RoleName -eq $roleName -and $_.MemberType -ne 'Inherited'}
                        if(($roleAssignments| Measure-Object).Count -gt 0)
                        {
                            $urlrole = $this.APIroot+"/roleSettingsV2?`$expand=resource,roleDefinition(`$expand=resource)&`$filter=(resource/id+eq+%27$($resourceId)%27)+and+(roleDefinition/id+eq+%27$($roleAssignments[0].RoleId)%27)"
                            $rolesettings = [WebRequestHelper]::InvokeWebRequest("Get", $urlrole, $this.headerParams, $null, [string]::Empty, $false, $false )
                            $maxAllowedDays = ((($($($($rolesettings.lifeCycleManagement | Where-Object {$_.caller -eq 'Admin' -and $_.level -eq 'Eligible'}).value) | Where-Object{$_.RuleIdentifier -eq 'ExpirationRule'}).setting | ConvertFrom-Json).maximumGrantPeriodInMinutes)/60)/24   

                            $roleAssignments | ForEach-Object{
                                $days= $DurationInDays
                                [DateTime]$startDate = $_.ExpirationDate
                                $extendedDate = (($startDate).AddDays($DurationInDays).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))
                                $activeForDays = [math]::Round((([DateTime]$startDate).ToUniversalTime().Subtract([DateTime](get-date).ToUniversalTime())).TotalDays)

                                if($extendedDate -gt ((get-date).AddDays($maxAllowedDays).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")))
                                {
                                    $days = $maxAllowedDays
                                    $extendedDate = ((get-date).AddDays($maxAllowedDays).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))
                                }
                                $url = $this.APIroot +"/roleAssignmentRequests "
                                $postParams = '{"roleDefinitionId":"'+ $_.RoleId+'","resourceId":"'+$_.ResourceId+'","subjectId":"'+ $_.SubjectId+'","assignmentState":"Eligible","type":"AdminExtend","reason":"Admin Extend by '+$this.AccountId+'","schedule":{"type":"Once","startDateTime":"'+ ((get-date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))+'","endDateTime":"'+($extendedDate)+'"}}'
                                $this.PublishCustomMessage("Requesting assignment extension for [$($_.PrincipalName)] by $days days...")

                                if(($null -ne $startDate) -and ($activeForDays -ne $maxAllowedDays)){
                                    try
                                    {
                                        $extresponse = [WebRequestHelper]::InvokeWebRequest('Post', $url, $this.headerParams, $postParams, "application/json", $false, $true )
                                        if ($extresponse.StatusCode -eq 201) {
                                            $this.PublishCustomMessage("Assignment extension request for [$($_.PrincipalName)] for the [$RoleName] role on [$($_.ResourceName)] queued successfully.", [MessageType]::Update);
                                        }  
                                        elseif ($extresponse.StatusCode -eq 401) {
                                            $this.PublishCustomMessage("You are not eligible to assign a role. If you have recently elevated/activated your permissions, please run Connect-AzAccount and re-run the script.", [MessageType]::Error);
                                        }
                                    }
                                    catch
                                    {
                                        if([Helpers]::CheckMember($_,"ErrorDetails.Message"))
                                        {
                                            $err = $_ | ConvertFrom-Json
                                            $this.PublishCustomMessage($err.error.message,[MessageType]::Error)
                                        }
                                        else
                                        {
                                            $this.PublishCustomMessage($_.Exception, [MessageType]::Error)
                                        }
                                    }
                                $this.PublishCustomMessage("");
                                }
                                else{
                                    $this.PublishCustomMessage("Assignment of [$($_.PrincipalName)] for the [$($_.RoleName)] role is already set to its maximum limit.", [MessageType]::Warning);
                                    $this.PublishCustomMessage("");
                                }
                            }
                        }
                        else
                        {
                            $this.PublishCustomMessage("No PIM eligible roles found for the principalName(s) provided",[MessageType]::Warning)
                        }
                    }
                    else
                    {
                        $this.PublishCustomMessage("No PIM eligible roles found on the resource",[MessageType]::Warning)
                    }
            
                }
                
                #"ElseIf" block will exceute when -RemoveRole parameter is used  
                elseif ($isRemoveAssignmentRequest)
                 {
                    $userResp = ''
                    $users | ForEach-Object{
                        $this.PublishCustomMessage(($_ | Format-Table  -AutoSize -Wrap -Property UserPrincipalName, DisplayName | Out-String), [MessageType]::Default)
                        if(!$Force)
                        {
                            Write-Host "The above PIM eligible assignments will be removed. `nPlease confirm (Y/N): " -ForegroundColor Yellow -NoNewline
                            $userResp = Read-Host
                        } 
                        if ($userResp -eq 'y' -or $Force)
                        {
                            $url = $this.APIroot + "/roleAssignmentRequests"
                            $postParams = '{"assignmentState":"Eligible","type":"AdminRemove","roleDefinitionId":"' + $roleDefinitionId + '","scopedResourceId": null ,"resourceId":"' + $resourceId + '","subjectId":"' + $_.Id + '"}'

                            $this.PublishCustomMessage("Initiating removal of assignment on [$($resolvedResource.ResourceName)] for [$RoleName] role...")
                            $this.PublishCustomMessage([Constants]::SingleDashLine)

                            try{
                            $response = [WebRequestHelper]::InvokeWebRequest('Post', $url, $this.headerParams, $postParams, "application/json", $false, $true )
                                if ($response.StatusCode -eq 201) {
                                    $this.PublishCustomMessage("Assignment removal request queued successfully.", [MessageType]::Update);
                                }  
                                elseif ($response.StatusCode -eq 401) {
                                    $this.PublishCustomMessage("You are not eligible to revoke a role. If you have recently elevated/activated your permissions, please run Connect-AzAccount and re-run the script.", [MessageType]::Error);
                                }
                            }
                            catch
                            {
                                if([Helpers]::CheckMember($_,"ErrorDetails.Message"))
                                {
                                    $err = $_ | ConvertFrom-Json
                                    $this.PublishCustomMessage($err.error.message,[MessageType]::Error)
                                }
                                else
                                {
                                    $this.PublishCustomMessage($_.Exception, [MessageType]::Error)
                                }
        
                            }
                            $this.PublishCustomMessage([Constants]::SingleDashLine)
                            $this.PublishCustomMessage("");
                        }
                    }
                }

                #"Else" block will exceute when -AssignRole parameter is used  
                else 
                {
                    $users | ForEach-Object{
                    $url = $this.APIroot + "/roleAssignmentRequests"
                    $ts = New-TimeSpan -Days $duration
                    
                    #Assign Role based on selected Assignment Type (Eligible by default)
                    if($assignmentType -eq "Active") {
                        $assignmentState = "Active" #AssignmentState is case sensitive in request body
                    }
                    else{
                        $assignmentState = 'Eligible' #AssignmentState is Eligible by default
                    }

                    $postParams = '{"assignmentState":"' + $assignmentState + '","type":"AdminAdd","reason":"Assign","roleDefinitionId":"' + $roleDefinitionId + '","resourceId":"' + $resourceId + '","subjectId":"' + $_.Id + '","schedule":{"startDateTime":"' + (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + '","endDateTime":"' + ((get-date) + $ts).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + '","type":"Once"}}'
                    $this.PublishCustomMessage("Requesting assignment on [$($resolvedResource.ResourceName)] for [$RoleName] role...")
                    try{
                    $response = [WebRequestHelper]::InvokeWebRequest('Post', $url, $this.headerParams, $postParams, "application/json", $false, $true )
                        if ($response.StatusCode -eq 201) {
                            $this.PublishCustomMessage("Assignment request queued successfully.", [MessageType]::Update);
                            $this.PublishCustomMessage("");
                        }  
                        elseif ($response.StatusCode -eq 401) {
                            $this.PublishCustomMessage("You are not eligible to assign a role. If you have recently elevated/activated your permissions, please run Connect-AzAccount and re-run the script.", [MessageType]::Error);
                        }
                    }
                    catch
                    {
                        if([Helpers]::CheckMember($_,"ErrorDetails.Message"))
                        {
                            $err = $_ | ConvertFrom-Json
                            $this.PublishCustomMessage($err.error.message,[MessageType]::Error)
                        }
                        else
                        {
                            $this.PublishCustomMessage($_.Exception, [MessageType]::Error)
                        }

                    }
                    $this.PublishCustomMessage("");
                }
                }
               
                
            }   
        }
        else {
            $this.PublishCustomMessage( "Unable to find resource on which assignment was requested. Either the resource does not exist or you may not have permissions for assigning a role on it.", [MessageType]::Error)
            $this.DisplayActivationHelpMessage($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName)
        }
    }

    hidden ListMyEligibleRoles() {
        $assignments = $this.MyJitAssignments() | Sort-Object -Property ResourceName,AssignmentState
        if (($assignments | Measure-Object).Count -gt 0) {
            $this.PublishCustomMessage("Your eligible role assignments:", [MessageType]::Default)
            $this.PublishCustomMessage("");
            $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default)
            $this.PublishCustomMessage(($assignments | Format-Table  -Wrap @{Label = "ResourceId"; Expression = { $_.OriginalId }; Width =52}, ResourceName, RoleName,  ResourceType, AssignmentState, ExpirationDate | Out-String), [MessageType]::Default)
            $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default)
            $this.PublishCustomMessage("");
                        
            $objectToExport = $assignments | Select-Object @{Label = "ResourceId"; Expression = { $_.OriginalId } }, ResourceName, ResourceType, RoleName, AssignmentState
            $this.ExportCSV($objectToExport)
        }
        else {
            $this.PublishCustomMessage("No PIM Eligible assignments found for the current context: $($this.AccountId).",[MessageType]::Warning)
        }
    }

    # Below method is intended to assign equivalent PIM eligible roles for permanent assignments for a given role on a particular resource
    hidden AssignPIMforPermanentAssignemnts($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $DurationInDays, $PrincipalNames, $Force) 
    {
        $principalTransitioned = @();        
        $resolvedResource = $null;
        if(-not([string]::IsNullOrEmpty($ManagementGroupId)))
        {
            
            $resolvedResource = $this.PIMResourceResolver($ManagementGroupId, $false);
        
        }
        else 
        {
            $resolvedResource = $this.PIMResourceResolver($SubscriptionId, $ResourceGroupName, $ResourceName, $false)
        }
        if (($resolvedResource | Measure-Object).Count -gt 0 -and (-not [string]::IsNullOrEmpty($resolvedResource.ResourceId))) {    
            $resourceId = $resolvedResource.ResourceId
            $roles = $this.ListRoles($resourceId)
            $roles = ($roles | Where-Object { $_.RoleName -in $($RoleNames.split(",").Trim()) })
            $CriticalRoles = $roles.RoleName 
            $this.PublishCustomMessage("Fetching permanent assignment for [$(($criticalRoles) -join ", ")] role on $($resolvedResource.Type) [$($resolvedResource.ResourceName)]...",[MessageType]::Info)
            $permanentRoles = $this.ListAssignmentsWithFilter($resourceId, $true)
            $permanentRolesForTransition = @();
            if (($permanentRoles | Measure-Object).Count -gt 0) {
                $permanentRoles = $permanentRoles | Where-Object { ($_.SubjectType -eq 'User' -or $_.SubjectType -eq 'Group'  )-and $_.MemberType -ne 'Inherited' -and $_.RoleName -in $CriticalRoles }
                if(($PrincipalNames | Measure-Object).Count -gt 0) # checking if assignment only for certain UPNs are to be removed
                {
                    $principalNames = $principalNames.Split(',').Trim()
                    $permanentRolesForTransition += $permanentRoles | Where-Object {$_.PrincipalName -in $principalNames}
                    if( ($permanentRolesForTransition | Measure-Object).Count -eq 0)
                    {
                        $this.PublishCustomMessage("Unable to find matching permanent assignments for the principal names provided in `$PrincipalNames parameter.",[MessageType]::Warning)
                        return;
                    }
                    
                    
                }
                else
                {
                    $permanentRolesForTransition += $permanentRoles
                }
                if (($permanentRolesForTransition | Measure-Object).Count -gt 0) {
                    $ToContinue = ''
                    if(!$Force)
                    {
                        $this.PublishCustomMessage($($permanentRolesForTransition | Format-Table -AutoSize -Wrap PrincipalName, ResourceName, SubjectType, ResourceType, RoleName | Out-String), [MessageType]::Default)
                        $this.PublishCustomMessage("");
                        Write-Host "The above role assignments will be moved from 'permanent' to 'PIM'. `nPlease confirm (Y/N): " -ForegroundColor Yellow -NoNewline
                        $ToContinue = Read-Host
                    }
                    if ($ToContinue -eq 'y' -or $Force) 
                    {               
                        $Assignmenturl = $this.APIroot + "/roleAssignmentRequests"
                        $roles = $this.ListRoles($resourceId)  
                        $ts = $DurationInDays;
                        $totalPermanentAssignments = ($permanentRolesForTransition | Measure-Object).Count
                        $this.PublishCustomMessage("Initiating PIM assignment for [$totalPermanentAssignments] permanent assignments..."); #TODO: Check the color
                        $i = 1
                        $permanentRolesForTransition | ForEach-Object {
                            $roleName = $_.RoleName
                            $roleDefinitionId = ($roles | Where-Object { $_.RoleName -eq $roleName }).RoleDefinitionId 
                            $subjectId = $_.SubjectId
                            $PrincipalName = $_.PrincipalName
                            $postParams = '{"assignmentState":"Eligible","type":"AdminAdd","reason":"Assign","roleDefinitionId":"' + $roleDefinitionId + '","resourceId":"' + $resourceId + '","subjectId":"' + $subjectId + '","schedule":{"startDateTime":"' + (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + '","endDateTime":"' + ((get-date).AddDays($ts).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")) + '","type":"Once"}}'
                            $this.PublishCustomMessage([Constants]::SingleDashLine)
                                
                               try{
                                $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $Assignmenturl -Method Post -ContentType "application/json" -Body $postParams
                                if ($response.StatusCode -eq 201) {
                                    $this.PublishCustomMessage("[$i`/$totalPermanentAssignments] Successfully requested PIM assignment for [$PrincipalName]", [MessageType]::Update);
                                    $principalTransitioned += $PrincipalName
                                }
                                $this.PublishCustomMessage([Constants]::SingleDashLine)
                          
                               }
                            catch {                                
                                   
                                    $err = $_ | ConvertFrom-Json
                                    if ($err.error.code -eq "RoleAssignmentExists") {
                                        $this.PublishCustomMessage("[$i`/$totalPermanentAssignments] PIM Assignment for [$PrincipalName] already exists.", [MessageType]::Warning)
                                        $principalTransitioned += $PrincipalName
                                    }
                                    else {
                                        $this.PublishCustomMessage("[$i`/$totalPermanentAssignments] $($err.error.message)", [MessageType]::Error)
                                    }
                                                                                            
                            }         
                            $i++;
                        }#foreach  
                        [string] $cmdmsg = "To remove the permanent assignments, please run `n setpim -RemovePermanentAssignments"
                        if([string]::IsNullOrEmpty($ManagementGroupId))
                        {
                            $cmdmsg += " -SubscriptionId $SubscriptionId"
                            if(-not [string]::IsNullOrEmpty($ResourceGroupName))
                                { $cmdmsg += " -ResourceGroupName $ResourceGroupName "}
                            if(-not [string]::IsNullOrEmpty($ResourceName))
                                { $cmdmsg += " -ResourceName $ResourceName "}
                           
                        }
                        else
                        {
                            $cmdmsg += " -ManagementGroupId $ManagementGroupId  "                        
                        }
                        $cmdmsg += '-RoleNames "'+($Rolenames)+ '"'
                        if(-not [string]::IsNullOrEmpty($PrincipalNames))
                        {$cmdmsg += '-PrincipalNames "'+($principalTransitioned -join ', ')+ '"'}
                        $this.PublishCustomMessage("")
                        $this.PublishCustomMessage("This command will assign equivelant eligible role assignments for the above permanent assignments. $cmdmsg", [MessageType]::Warning)
                        
                    }
                    else {
                        return;
                    }

                }
                else {
                    $this.PublishCustomMessage("No permanent assignments eligible for PIM assignment found.", [MessageType]::Warning);       
                }
            }
            else {
                $this.PublishCustomMessage("No permanent assignments found on the requested resource.", [MessageType]::Warning);       
            }
        }
        else
        {
            $this.PublishCustomMessage( "Unable to find resource on which assignment was requested. Either the resource does not exist or you may not have permissions for assigning a role on it.", [MessageType]::Error)
            $this.DisplayActivationHelpMessage($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName)
        }
    }

    # Remove permanent assignments for a particular role on a given resource
    hidden RemovePermanentAssignments($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $RemoveAssignmentFor, $PrincipalNames, $Force) {
        $this.AcquireToken();
        $resolvedResource = $null;
        if(-not([string]::IsNullOrEmpty($ManagementGroupId)))
        {
            
            $resolvedResource = $this.PIMResourceResolver($ManagementGroupId, $false);
        
        }
        else 
        {
            $resolvedResource = $this.PIMResourceResolver($SubscriptionId, $ResourceGroupName, $ResourceName, $false)
        }
        if($null -ne $resolvedResource -and (-not [String]::IsNullOrEmpty($resolvedResource.ResourceId)))
        {
            $resourceId = ($resolvedResource).ResourceId 
            $users = @();
            $CriticalRoles = $RoleNames.split(",").Trim()
            $this.PublishCustomMessage("Note: This command will *not* remove your permanent assignment if one exists.", [MessageType]::Warning)
            $this.PublishCustomMessage("Fetching permanent assignment for [$(($criticalRoles) -join ", ")] role on $($resolvedResource.Type) [$($resolvedResource.ResourceName)]...", [MessageType]::Info)
            $permanentRoles = $this.ListAssignmentsWithFilter($resourceId, $true)
            $eligibleAssignments = $this.ListAssignmentsWithFilter($resourceId, $false)
            $eligibleAssignments = $eligibleAssignments | Where-Object { ($_.SubjectType -eq 'User' -or $_.SubjectType -eq 'Group') -and $_.MemberType -ne 'Inherited' -and $_.RoleName -in $CriticalRoles }
            if (($permanentRoles | Measure-Object).Count -gt 0) {
                $permanentRolesForTransition = $permanentRoles | Where-Object {($_.SubjectType -eq 'User' -or $_.SubjectType -eq 'Group') -and $_.MemberType -ne 'Inherited' -and $_.RoleName -in $CriticalRoles }
                $successfullyassignedRoles = @();
                $currentContext = [ContextHelper]::GetCurrentRmContext();
                $permanentRolesForTransition = $permanentRolesForTransition | Where-Object { $_.PrincipalName -ne $currentContext.Account.Id }
                if(($PrincipalNames |Measure-Object).Count -gt 0) # checking if assignment only for certain UPNs are to be removed
                {
                    $PrincipalNames = $PrincipalNames.Split(',').Trim()
                    $permanentRolesForTransition =  $permanentRolesForTransition | Where-Object{$_.PrincipalName -in $PrincipalNames}
                    if( ($permanentRolesForTransition | Measure-Object).Count -eq 0)
                    {
                        $this.PublishCustomMessage("Permanent assignments matching with principal names provided in `$PrincipalNames parameter are not found.",[MessageType]::Warning)
                        return;
                    }
                }
                
                if ($RemoveAssignmentFor -ne "AllExceptMe") {
                    $eligibleAssignments | ForEach-Object {
                        $allUser = $_;
                        $permanentRolesForTransition | ForEach-Object {
                    
                            if ($_.SubjectId -eq $allUser.SubjectId -and $_.RoleName -eq $allUser.RoleName) {
                                $successfullyassignedRoles += $_
                            } 
                        }
                    }             
                    $users = $successfullyassignedRoles            
                }
                else {
                    $users = $permanentRolesForTransition
                }
            }
            else {
                $this.PublishCustomMessage("No PIM eligible assignments found on the requested resource.", [MessageType]::Warning);  
            }
            if (($users | Measure-Object).Count -gt 0) {
                $userResp = ''
                $totalRemovableAssignments = ($users | Measure-Object).Count
                if(!$Force)
                {
                    $this.PublishCustomMessage($($users | Format-Table  -AutoSize -Wrap -Property PrincipalName, RoleName, OriginalId | Out-String), [MessageType]::Default)
                    Write-Host "The above listed role assignments will be removed. `nPlease confirm (Y/N): " -ForegroundColor Yellow -NoNewline
                    $userResp = Read-Host
                } 
                if ($userResp -eq 'y' -or $Force)
                {
                    $i = 0
                    $this.PublishCustomMessage("Initiating removal of [$totalRemovableAssignments] permanent assignments...")
                    # Remove permanent assignments of specified roles, at the specified scope
                    foreach ($user in $users)
                    {
                        try
                        {
                            $i++;
                            $this.PublishCustomMessage([Constants]::SingleDashLine);                            
                            Remove-AzRoleAssignment -ObjectId $user.SubjectId -RoleDefinitionName $user.RoleName -Scope $user.OriginalId -ErrorAction Stop                             
                            $this.PublishCustomMessage("[$i`/$totalRemovableAssignments]Successfully removed permanent assignment", [MessageType]::Update )                
                            $this.PublishCustomMessage([Constants]::SingleDashLine);
                        }
                        catch
                        {
                            # This code block is to capture any exception while removing role assignment at a specified scope
                            # If exception is captured, stop the command after printing the error message
                            if ([Helpers]::CheckMember($_.Exception, "Response.StatusCode") -and $_.Exception.Response.StatusCode -eq '403')
                            {
                                # Authorization denied exception 
                                $this.PublishCustomMessage("[$i`/$totalRemovableAssignments] You do not have the authorization to delete role assignments or the scope is invalid. If access was recently granted, please refresh your credentials.", [MessageType]::Error)
                            }
                            else
                            {
                                # Other exception
                                $this.PublishCustomMessage("[$i`/$totalRemovableAssignments] $($_.Exception.Message)", [MessageType]::Error)
                            }
                            break;                        
                        }
                        

                    } #foreach end
                }
            }
            else {
                $this.PublishCustomMessage("No permanent assignments found for the scope.", [MessageType]::Warning)
            }
        }
        else
        {
            $this.PublishCustomMessage( "Unable to find resource on which assignment was requested. Either the resource does not exist or you may not have active permissions for the assignment removal", [MessageType]::Error)
            $this.DisplayActivationHelpMessage($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName)
        }
    }
   

    # Get the assignments that are expiring in n days
    hidden  [PSObject] ListSoonToExpireAssignments($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $ExpiringInDays)
    {
        $this.AcquireToken();
        $criticalRoles = @();
        $soonToExpireAssignments = @();
        $criticalRoles += $this.ConvertToStringArray($RoleNames)
        $resources = $null;
        if(-not([string]::IsNullOrEmpty($ManagementGroupId)))
        {
            
            $resources = $this.PIMResourceResolver($ManagementGroupId, $false);
        
        }
        else 
        {
            $resources = $this.PIMResourceResolver($SubscriptionId, $ResourceGroupName, $ResourceName, $false)
        }
        if(($resources | Measure-Object).Count -gt 0 -and (-not [string]::IsNullOrEmpty($resources.ResourceId)))
        {
            $roleAssignments = $this.ListAssignmentsWithFilter($resources.ResourceId, $false)
            $roleAssignments = $roleAssignments | Where-Object{($_.SubjectType -eq 'User' -or $_.SubjectType -eq 'Group') -and $_.memberType -ne 'Inherited' -and -not([string]::IsNullOrEmpty($_.ExpirationDate))}
            if(($roleAssignments | Measure-Object).Count -gt 0)
            {
                [int]$soonToExpireWindow = $ExpiringInDays;
                $soonToExpireAssignments += $roleAssignments | Where-Object {([DateTime]::UTCNow).AddDays($soonToExpireWindow) -gt $_.ExpirationDate -and $_.RoleName -in $criticalRoles -and $_.AssignmentState -eq 'Eligible'}
                if(($soonToExpireAssignments| Measure-Object).Count -gt 0)
                {
                    $this.PublishCustomMessage($($soonToExpireAssignments | Sort-Object -Property ExpirationDate | Format-Table  -Wrap 'SubjectId', 'PrincipalName', 'SubjectType','RoleName', @{Label = "ExpiringInDays"; Expression = { [math]::Round((([DateTime]$_.ExpirationDate).ToUniversalTime().Subtract([DateTime](get-date).ToUniversalTime())).TotalDays) } } |  Out-String), [MessageType]::Default)
                    $objectToExport = $soonToExpireAssignments | Select-Object RoleName, PrincipalName, UserName, ResourceType, ResourceName, SubjectType, AssignmentState,	IsPermanent, @{Label = "ExpiringInDays"; Expression = { [math]::Round((([DateTime]$_.ExpirationDate).ToUniversalTime().Subtract([DateTime](get-date).ToUniversalTime())).TotalDays) } }
                    $this.ExportCSV($objectToExport)
                }
                else 
                {
                    $this.PublishCustomMessage("No assignment found for `"$($criticalRoles -join ", ")`" role expiring in $ExpiringInDays days. ",[MessageType]::Error)
                }
            }
            else 
            {
                $this.PublishCustomMessage("No eligible assignments found for the provided scope and role. ",[MessageType]::Error)
            }

        }
        else
        {
            $this.PublishCustomMessage( "Unable to find resource on which assignment was requested. Either the resource does not exist or you may not have permissions for assigning a role on it", [MessageType]::Error)
            $this.DisplayActivationHelpMessage($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName)
        }
       return $soonToExpireAssignments
    }

    # Extend assignments for roles by n days from expiration date
    hidden [void] ExtendSoonToExpireAssignments($managementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $ExpiringInDays, $DurationInDays, $force)
    {
        $soonToExpireAssignments = @();
        if(-not([string]::IsNullOrEmpty($ManagementGroupId)))
        {
          $soonToExpireAssignments = $this.ListSoonToExpireAssignments($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $ExpiringInDays);
        }
        else
        {
            $soonToExpireAssignments = $this.ListSoonToExpireAssignments($null, $SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $ExpiringInDays);
        }
          $AssignmentCount = ($soonToExpireAssignments | Measure-Object).Count
        if($AssignmentCount -gt 0)
        {
            $ts =$DurationInDays
            $url = $this.APIroot +"/roleAssignmentRequests "
            # get maximum number of days an assigment 

            $urlrole = $this.APIroot+"/roleSettingsV2?`$expand=resource,roleDefinition(`$expand=resource)&`$filter=(resource/id+eq+%27$($soonToExpireAssignments[0].ResourceId)%27)+and+(roleDefinition/id+eq+%27$($soonToExpireAssignments[0].RoleId)%27)"
            $rolesettings = [WebRequestHelper]::InvokeWebRequest("Get", $urlrole, $this.headerParams, $null, [string]::Empty, $false, $false )
            $maxAllowedDays= ((($($($($roleSettings.lifeCycleManagement | Where-Object {$_.caller -eq 'Admin' -and $_.level -eq 'Eligible'}).value) | Where-Object{$_.RuleIdentifier -eq 'ExpirationRule'}).setting | ConvertFrom-Json).maximumGrantPeriodInMinutes)/60)/24 
            
            # If force switch is used extend to expire without any prompt
            $this.PublishCustomMessage("");
            $this.PublishCustomMessage("Initiating assignment extension for [$AssignmentCount] PIM assignments..."); #TODO: Check the color
            $UserResponse = 'N' 
            [int] $i =1
            $soonToExpireAssignments | ForEach-Object{
                    if(-not $force)
                    {
                        $this.PublishCustomMessage("");
                        $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default)
                        Write-Host "[$i/$AssignmentCount] Do you want to extend assignment for [$($_.PrincipalName)]? `nPlease confirm (Y/N): " -ForegroundColor Yellow -NoNewline #TODO: Check the color
                        $UserResponse = Read-Host
                    }
                    else
                    {
                        $this.PublishCustomMessage("");
                        $this.PublishCustomMessage([Constants]::SingleDashLine);
                        $this.PublishCustomMessage("[$i/$AssignmentCount] Requesting assignment extension for [$($_.PrincipalName)] by $DurationInDays days",[MessageType]::Default)
                    }

                    if($force -or ($UserResponse -eq 'Y'))
                    {
                        [DateTime]$startDate = $_.ExpirationDate
                        $activeForDays = [math]::Round((([DateTime]$startDate).ToUniversalTime().Subtract([DateTime](get-date).ToUniversalTime())).TotalDays)
                        
                        #If Block executes for the condition when Assignment days of User are less than Maximum Assignment Days for the Role  
                        if(($null -ne $startDate) -and ($activeForDays -ne $maxAllowedDays))
                        {
                            $extendedDate = (($startDate).AddDays($ts).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))
                            if($extendedDate -gt ((get-date).AddDays($maxAllowedDays).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")))
                            {
                                $extendedDate = ((get-date).AddDays($maxAllowedDays).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))
                            }
                            $postParams = '{"roleDefinitionId":"'+ $_.RoleId+'","resourceId":"'+$_.ResourceId+'","subjectId":"'+ $_.SubjectId+'","assignmentState":"Eligible","type":"AdminExtend","reason":"Admin Extend by '+$this.AccountId+'","schedule":{"type":"Once","startDateTime":"'+ ((get-date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))+'","endDateTime":"'+($extendedDate)+'"}}'
                            try{
                                $response = [WebRequestHelper]::InvokeWebRequest('Post', $url, $this.headerParams, $postParams, "application/json", $false, $true )
                                if ($response.StatusCode -eq 201) {
                                    $this.PublishCustomMessage("[$i/$AssignmentCount] Assignment extension request for [$($_.PrincipalName)] for the [$($_.RoleName)] role queued successfully.", [MessageType]::Update);
                                }  
                                elseif ($response.StatusCode -eq 401) {
                                    $this.PublishCustomMessage("You are not eligible to extend a role. If you have recently elevated/activated your permissions, please run Connect-AzAccount and re-run the script.", [MessageType]::Error);
                                }
                                else
                                {
                                    $this.PublishCustomMessage($response, [MessageType]::Error);
                                }
                            }
                            catch
                            {
                                if([Helpers]::CheckMember($_,"ErrorDetails.Message"))
                                {
                                    $err = $_ | ConvertFrom-Json
                                    $this.PublishCustomMessage($err.error.message,[MessageType]::Error)
                                }
                                else
                                {
                                    $this.PublishCustomMessage($_.Exception, [MessageType]::Error)
                                }
                            }
                        }
                        else # To notify user that Assignment of User is already equal to maximum Assignment for the Role 
                        {
                            $this.PublishCustomMessage("Assignment of [$($_.PrincipalName)] for the [$($_.RoleName)] role is already set to its maximum limit.")
                        }
                    }
                    ++$i;
                }
           
        }# in case no assignments it would error while fetching
       
       
    }

    # configure PIM role settings for a particular role on a resource 
    hidden [void] ConfigureRoleSettings($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName, $RoleSettingsRawInput, $RequireMFAOnActivation,$RequireConditionalAccessOnActivation)
    {
        #  1) get PIM resource id for the resource provided
        $resolvedResource = $null;
        if(-not([string]::IsNullOrEmpty($ManagementGroupId)))
        {
            $resolvedResource = $this.PIMResourceResolver($ManagementGroupId, $false);
        }
        else 
        {
            $resolvedResource = $this.PIMResourceResolver($SubscriptionId, $ResourceGroupName, $ResourceName, $false)
        }
       
        #  2) get PIM identifier for the particular role on resource identified in 1
        if (($resolvedResource | Measure-Object).Count -gt 0 -and (-not [string]::IsNullOrEmpty($resolvedResource.ResourceId))) {
          $roleforResource = @($this.ListRoles($resolvedResource.ResourceId)) | Where-Object {$_.RoleName -eq $RoleName}
        #  3) Get json object for role setting
        $rolesettings = [string]::Empty
        
            if(($roleforResource|Measure-Object).Count -gt 0)
            {
                try {
                    $url = $this.APIroot+"/roleSettingsV2?`$expand=resource,roleDefinition(`$expand=resource)&`$filter=(resource/id+eq+%27$($resolvedResource.ResourceId)%27)+and+(roleDefinition/id+eq+%27$($roleforResource.RoleDefinitionId)%27)"
                    $rolesettings = [WebRequestHelper]::InvokeWebRequest("Get", $url, $this.headerParams, $null, [string]::Empty, $false, $false )
                }
                catch {
                    if([Helpers]::CheckMember($_,"ErrorDetails.Message"))
                    {
                        $err = $_ | ConvertFrom-Json
                        $this.PublishCustomMessage($err.error.message,[MessageType]::Error)
                    }
                    else
                    {
                        $this.PublishCustomMessage("Unable to retrieve existing role settings for provided role. Please verify you have required permissions to view requested role for the given scope.", [MessageType]::Error)
                    }
                    return
                }
            $existingroleSetting  = $rolesettings
            $RequireJustificationOnActivation = $null;
        # 4) Modify the role settings obtained above by the parameters passed in cmdlet
            if( [string]::IsNullOrEmpty($RoleSettingsRawInput.RequireJustificationOnActivation)){
                $RequireJustificationOnActivation = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'EndUser' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'JustificationRule'}).setting | ConvertFrom-Json).required
            }
            else
            {
                $RequireJustificationOnActivation = $RoleSettingsRawInput.RequireJustificationOnActivation
            }
            if( [string]::IsNullOrEmpty($RequireMFAOnActivation)){
                $RequireMFAOnActivation = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'EndUser' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'MfaRule'}).setting | ConvertFrom-Json).mfaRequired
            }

            $MaximumActivationDuration = $null;
            $ExpireEligibleAssignmentsAfter = $null;
            $MaxActivationDurationConstant = 60 #To convert hours to minutes
            $ExpireEligibleAssignmentsAfterConstant = 24*60 #To convert days to minutes

                    $isPermanentAdminEligible = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'Admin' -and $_.level -eq 'Eligible'}).value) | Where-Object{$_.RuleIdentifier -eq 'ExpirationRule'}).setting | ConvertFrom-Json).permanentAssignment
                    $isPermanentuserMember = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'EndUser' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'ExpirationRule'}).setting | ConvertFrom-Json).permanentAssignment
                    if($RoleSettingsRawInput.MaximumActivationDuration -eq -1)
                    {
                            $MaximumActivationDuration = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'EndUser' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'ExpirationRule'}).setting | ConvertFrom-Json).maximumGrantPeriodInMinutes
                    }
                    else 
                    {
                        $MaximumActivationDuration = $RoleSettingsRawInput.MaximumActivationDuration*$MaxActivationDurationConstant
                    }
                    if($RoleSettingsRawInput.ExpireEligibleAssignmentsAfter -eq -1)
                    {
                            $ExpireEligibleAssignmentsAfter = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'Admin' -and $_.level -eq 'Eligible'}).value) | Where-Object{$_.RuleIdentifier -eq 'ExpirationRule'}).setting | ConvertFrom-Json).maximumGrantPeriodInMinutes
                    }
                    else 
                    {
                            $ExpireEligibleAssignmentsAfter =$RoleSettingsRawInput.ExpireEligibleAssignmentsAfter*$ExpireEligibleAssignmentsAfterConstant
                    }
                    $ExpireActiveAssignmentsAfter = $null;
                    if($RoleSettingsRawInput.ExpireActiveAssignmentsAfter -eq -1){ 
                        $ExpireActiveAssignmentsAfter = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'Admin' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'ExpirationRule'}).setting | ConvertFrom-Json).maximumGrantPeriodInMinutes
                    }
                    else{
                        # converting input duration into minutes
                        $ExpireActiveAssignmentsAfter = $RoleSettingsRawInput.ExpireActiveAssignmentsAfter*$ExpireEligibleAssignmentsAfterConstant
                    }

                    $RequireMFAOnActiveAssignment = $null;
                    if( [string]::IsNullOrEmpty($RoleSettingsRawInput.RequireMFAOnActiveAssignment)){
                        $RequireMFAOnActiveAssignment = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'Admin' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'MfaRule'}).setting | ConvertFrom-Json).mfaRequired
                    }
                    else{
                        $RequireMFAOnActiveAssignment =$RoleSettingsRawInput.RequireMFAOnActiveAssignment
                    }

                    $RequireJustificationOnActiveAssignment = $null;
                    if( [string]::IsNullOrEmpty($RoleSettingsRawInput.RequireJustificationOnActiveAssignment)){
                        $RequireJustificationOnActiveAssignment = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'Admin' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'JustificationRule'}).setting | ConvertFrom-Json).required
                    }
                    else{
                        $RequireJustificationOnActiveAssignment =$RoleSettingsRawInput.RequireJustificationOnActiveAssignment
                    }

               # Check for the conditional policy enforcement in Org settings, if applied to accordingly
               $roleSettingId = $existingroleSetting.id
               $policyString = [string]::Empty
               $policyTag= [string]::Empty
               $setFlag = $false  #flag to identify if both $RequireConditionalAccessOnActivation and $RequireMFAOnActivation to remain unchanged

               if ($RequireConditionalAccessOnActivation -eq $false -and $RequireMFAOnActivation -eq $false){
                    $setFlag = $true
                    $RequireConditionalAccessOnActivation = $null
                    $RequireMFAOnActivation = $null
                }
                if($setFlag -eq $false)
                {
                    if($null -ne $RequireConditionalAccessOnActivation)
                    {
                            if($RequireConditionalAccessOnActivation)
                            {
                                
                                if([Helpers]::CheckMember($this.ControlSettings,"PIMCAPolicyTags"))
                                {
                                    $policyTag = $this.ControlSettings.PIMCAPolicyTags
                                    
                                }
                                else 
                                {
                                    $this.PublishCustomMessage("Error: Conditional Access policy tag was not found.",[MessageType]::Error)
                                    $this.PublishCustomMessage("This could happen because DevOps Kit is not configured with the correct org policy. Make sure you install DevOps Kit using the correct `"iwr`" command for your organization. ", [MessageType]::Warning)
                                    return
                                }
                                $policyString= '{"ruleIdentifier":"AcrsRule","setting":"{\"acrsRequired\":true,\"acrs\":\"'+$policyTag+'\"}"}'
                                
                            }
                            else
                            {
                                $policyString= '{"ruleIdentifier":"AcrsRule","setting":"{\"acrsRequired\":false,\"acrs\":\"'+$policyTag+'\"}"}'
                            }
                    }
               if($null -ne $RequireMFAOnActivation)
               {
                    if($RequireMFAOnActivation)
                    {
                        
                        # TODO: if we turn on MFA on activation CA policy cannot be simultaneously applied. Need to check if the API still throws the error
                          $policyString= ''
                        
                        
                    }
                    
                }
            }
        #  5) Create json body for patch request  
               $body=""
               $updateUrl=""
                    if(-not [string]::IsNullOrEmpty($policyString))
                    {
                        $body= '{"id": "'+$roleSettingId+'","lifeCycleManagement": [{"caller":"Admin","level":"Eligible","operation": "ALL","value":[{"ruleIdentifier":"ExpirationRule","setting":"{\"permanentAssignment\":'+$isPermanentAdminEligible+',\"maximumGrantPeriodInMinutes\":'+$ExpireEligibleAssignmentsAfter+'}"}]},{"caller": "EndUser","level": "Member","operation": "ALL","value":[{"ruleIdentifier":"ExpirationRule","setting":"{\"permanentAssignment\":'+$isPermanentuserMember+',\"maximumGrantPeriodInMinutes\":'+$MaximumActivationDuration+'}"},{"ruleIdentifier":"MfaRule","setting":"{\"mfaRequired\":'+$false+'}"},{"ruleIdentifier":"JustificationRule","setting":"{\"required\":'+$RequireJustificationOnActivation+'}"},'+$policyString+']},    
                        {"caller":"Admin","level":"Member","operation": "ALL","value":[{"ruleIdentifier": "ExpirationRule","setting": "{\"permanentAssignment\":false,\"maximumGrantPeriodInMinutes\":'+$ExpireActiveAssignmentsAfter+'}"},{"ruleIdentifier": "MfaRule","setting": "{\"mfaRequired\":'+$RequireMFAOnActiveAssignment+'}"},{"ruleIdentifier": "JustificationRule","setting": "{\"required\":'+ $RequireJustificationOnActiveAssignment+'}"}]}],"roleDefinition":{"id":"'+$rolesettings.roleDefinitionId+'"}}'
                    }
                    else
                    {
                        if($setFlag) {
                            $body='{"id": "'+$roleSettingId+'","lifeCycleManagement": [{"caller":"Admin","level":"Eligible","operation": "ALL","value":[{"ruleIdentifier":"ExpirationRule","setting":"{\"permanentAssignment\":'+$isPermanentAdminEligible+',\"maximumGrantPeriodInMinutes\":'+$ExpireEligibleAssignmentsAfter+'}"}]},{"caller": "EndUser","level": "Member","operation": "ALL","value":[{"ruleIdentifier":"ExpirationRule","setting":"{\"permanentAssignment\":'+$isPermanentuserMember+',\"maximumGrantPeriodInMinutes\":'+$MaximumActivationDuration+'}"},{"ruleIdentifier":"JustificationRule","setting":"{\"required\":'+$RequireJustificationOnActivation+'}"}]},
                            {"caller":"Admin","level":"Member","operation": "ALL","value":[{"ruleIdentifier": "ExpirationRule","setting": "{\"permanentAssignment\":false,\"maximumGrantPeriodInMinutes\":'+$ExpireActiveAssignmentsAfter+'}"},{"ruleIdentifier": "MfaRule","setting": "{\"mfaRequired\":'+$RequireMFAOnActiveAssignment+'}"},{"ruleIdentifier": "JustificationRule","setting": "{\"required\":'+ $RequireJustificationOnActiveAssignment+'}"}]}],"roleDefinition":{"id":"'+$rolesettings.roleDefinitionId+'"}}'

                        }
                        else {
                            $body='{"id": "'+$roleSettingId+'","lifeCycleManagement": [{"caller":"Admin","level":"Eligible","operation": "ALL","value":[{"ruleIdentifier":"ExpirationRule","setting":"{\"permanentAssignment\":'+$isPermanentAdminEligible+',\"maximumGrantPeriodInMinutes\":'+$ExpireEligibleAssignmentsAfter+'}"}]},{"caller": "EndUser","level": "Member","operation": "ALL","value":[{"ruleIdentifier":"ExpirationRule","setting":"{\"permanentAssignment\":'+$isPermanentuserMember+',\"maximumGrantPeriodInMinutes\":'+$MaximumActivationDuration+'}"},{"ruleIdentifier":"MfaRule","setting":"{\"mfaRequired\":'+$RequireMFAOnActivation+'}"},{"ruleIdentifier":"JustificationRule","setting":"{\"required\":'+$RequireJustificationOnActivation+'}"}]},
                            {"caller":"Admin","level":"Member","operation": "ALL","value":[{"ruleIdentifier": "ExpirationRule","setting": "{\"permanentAssignment\":false,\"maximumGrantPeriodInMinutes\":'+$ExpireActiveAssignmentsAfter+'}"},{"ruleIdentifier": "MfaRule","setting": "{\"mfaRequired\":'+$RequireMFAOnActiveAssignment+'}"},{"ruleIdentifier": "JustificationRule","setting": "{\"required\":'+ $RequireJustificationOnActiveAssignment+'}"}]}],"roleDefinition":{"id":"'+$rolesettings.roleDefinitionId+'"}}'

                        }
                    }
                    $updateUrl = $this.APIroot+"/roleSettingsV2/$roleSettingId"
                
                $body = $body -replace "True" ,"true" # the api does not accept "True" so need to lower the casing
                $body = $body -replace "False", "false"                

                try
                {

                    $result = [WebRequestHelper]::InvokeWebRequest('PATCH', $updateUrl, $this.headerParams, $body, "application/json", $false, $true )
                    if($result.StatusCode -eq 204)
                    {
                        $this.PublishCustomMessage( "Updation request for [$rolename] role setting queued successfully.  ", [MessageType]::Update) 
                    }                  
                    elseif ($result.StatusCode -eq 401) {
                        $this.PublishCustomMessage("You are not eligible to configure role settings. If you have recently elevated/activated your permissions, please run Connect-AzAccount and re-run the script.", [MessageType]::Error);
                    }
                    else
                    {
                        $this.PublishCustomMessage($result, [MessageType]::Error);
                    }
                }
                catch
                {
                    if([Helpers]::CheckMember($_,"ErrorDetails.Message"))
                        {
                            $err = $_ | ConvertFrom-Json
                            $this.PublishCustomMessage($err.error.message,[MessageType]::Error)
                        }
                        else
                        {
                            $this.PublishCustomMessage($_.Exception, [MessageType]::Error)
                        }
                }
            }
            else
            {
                $this.PublishCustomMessage( "Unable to find role on which configuration was requested. Either the role does not exist or you may not have sufficient permissions.", [MessageType]::Warning) 
            }
        
        }
        else
        {
            $this.PublishCustomMessage( "Unable to find resource on which role configuration was requested. Either the resource does not exist or you may not have permissions for configuring role settings on it", [MessageType]::Error) 
            $this.DisplayActivationHelpMessage($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName)
        }
        
      
      
    }
    hidden [void] ExportCSV($exportObject)
    {
        $assignmentsCSV = New-Object -TypeName WriteCSVData
        $assignmentsCSV.FileName = 'SecurityReport-' + $this.RunIdentifier
        $assignmentsCSV.FileExtension = 'csv'
        $assignmentsCSV.FolderPath = ''
        $assignmentsCSV.MessageData = $exportObject

        $this.PublishAzSKRootEvent([AzSKRootEvent]::WriteCSV, $assignmentsCSV);
    }
    hidden [void] DisplayActivationHelpMessage($ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName)
    {
        [string] $cmdmsg = ""
        if(-not([string]::IsNullOrEmpty($ManagementGroupId)))
        {
            $cmdmsg = "-ManagementGroupId $ManagementGroupId"           
        }
        else
        {
            $cmdmsg += "-SubscriptionId $SubscriptionId"
                        if(-not [string]::IsNullOrEmpty($ResourceGroupName))
                            { $cmdmsg += " -ResourceGroupName $ResourceGroupName "}
                        if(-not [string]::IsNullOrEmpty($ResourceName))
                            { $cmdmsg += " -ResourceName $ResourceName "}
           
        }
        $this.PublishCustomMessage("Note: If you have PIM eligible role on the resource, make sure you have activated your access before running the above command. Use setpim -ActivateMyRole "+$cmdmsg+"  -DurationInHours `$durationinHrs -Justification `$justification -RoleName `$roleDefinitionName ",[MessageType]::Warning)
    }

    #List exixting settings for a specific role
    hidden [void] ListRoleSettings( $ManagementGroupId, $SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName)
    {
        $resolvedResource = $null;
        
        if(-not([string]::IsNullOrEmpty($ManagementGroupId)))
        {
            $resolvedResource = $this.PIMResourceResolver($ManagementGroupId, $false);
        }
        else 
        {
            $resolvedResource = $this.PIMResourceResolver($SubscriptionId, $ResourceGroupName, $ResourceName,$false)   
        }

        if (($resolvedResource | Measure-Object).Count -gt 0 -and (-not [string]::IsNullOrEmpty($resolvedResource.ResourceId))) {
          $roleforResource = @($this.ListRoles($resolvedResource.ResourceId)) | Where-Object {$_.RoleName -eq $RoleName}
            $rolesettings = [string]::Empty
        
            if(($roleforResource|Measure-Object).Count -gt 0)
            {
                #API call to get existing role settings
                try {
                    $url = $this.APIroot+"/roleSettingsV2?`$expand=resource,roleDefinition(`$expand=resource)&`$filter=(resource/id+eq+%27$($resolvedResource.ResourceId)%27)+and+(roleDefinition/id+eq+%27$($roleforResource.RoleDefinitionId)%27)"
                    $existingroleSetting = [WebRequestHelper]::InvokeWebRequest("Get", $url, $this.headerParams, $null, [string]::Empty, $false, $false )
                }
                catch {
                    if([Helpers]::CheckMember($_,"ErrorDetails.Message"))
                    {
                        $err = $_ | ConvertFrom-Json
                        $this.PublishCustomMessage($err.error.message,[MessageType]::Error)
                    }
                    else
                    {
                        $this.PublishCustomMessage("Unable to retrieve existing role settings for provided role. Please verify you have required permissions to view requested role for the given scope.", [MessageType]::Error)
                    }
                    return
                }
                #Fetch the role settings :ExpireEligibleAssignmentsInDays, RequireJustificationOnActivation, RequireMFAOnActivation, MaximumActivationDuration, ConditionalAccess
                $ExpireEligibleAssignmentsSetting = ((($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'Admin' -and $_.level -eq 'Eligible'}).value) | Where-Object{$_.RuleIdentifier -eq 'ExpirationRule'}).setting | ConvertFrom-Json).maximumGrantPeriodInMinutes)/60)/24 
                $MaximumActivationDurationSetting = (($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'EndUser' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'ExpirationRule'}).setting | ConvertFrom-Json).maximumGrantPeriodInMinutes )/60
                $JustificationOnActivationSetting = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'EndUser' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'JustificationRule'}).setting | ConvertFrom-Json).required
                $MFAOnActivationSetting = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'EndUser' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'MfaRule'}).setting | ConvertFrom-Json).mfaRequired
                $ConditionalAccessSetting = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'EndUser' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'acrsRule'}).setting | ConvertFrom-Json).acrsRequired
                
                #Fetch the role settings :ExpireActiveAssignmentsInDays, RequireJustificationOnActiveAssignment, RequireMFAOnActiveAssignment
                $ExpireActiveAssignmentsSetting = ((($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'Admin' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'ExpirationRule'}).setting | ConvertFrom-Json).maximumGrantPeriodInMinutes)/60)/24 
                $JustificationOnActiveAssignmentSetting = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'Admin' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'JustificationRule'}).setting | ConvertFrom-Json).required
                $MFAOnActiveAssignmentSetting = ($($($($existingroleSetting.lifeCycleManagement | Where-Object {$_.caller -eq 'Admin' -and $_.level -eq 'Member'}).value) | Where-Object{$_.RuleIdentifier -eq 'MfaRule'}).setting | ConvertFrom-Json).mfaRequired


                if($MFAOnActivationSetting -eq $true) { $MFAOnActivationSetting = "Yes"}
                else { $MFAOnActivationSetting = "No"}
                
				if($ConditionalAccessSetting -eq $true) { $ConditionalAccessSetting = "Yes"}
                else { $ConditionalAccessSetting = "No"}
                
				if($JustificationOnActivationSetting -eq $true) { $JustificationOnActivationSetting = "Yes"}
                else { $JustificationOnActivationSetting = "No"}

                if($JustificationOnActiveAssignmentSetting -eq $true) { $JustificationOnActiveAssignmentSetting = "Yes"}
                else { $JustificationOnActiveAssignmentSetting = "No"}

                if($MFAOnActiveAssignmentSetting -eq $true) { $MFAOnActiveAssignmentSetting = "Yes"}
                else { $MFAOnActiveAssignmentSetting = "No"}

                $item = New-Object psobject -Property @{
                    "Activation maximum duration (hours)" = $MaximumActivationDurationSetting
                    "Require justification on activation" =  $JustificationOnActivationSetting
                    "On activation, require Azure MFA" = $MFAOnActivationSetting
                    "On activation, require conditional access" = $ConditionalAccessSetting
                    "Expire eligible assignments after (days)" = $ExpireEligibleAssignmentsSetting
                    "Expire active assignments after (days)" = $ExpireActiveAssignmentsSetting
                    "Require justification on active assignment" = $JustificationOnActiveAssignmentSetting
                    "Require Azure Multi-Factor Authentication on active assignment" = $MFAOnActiveAssignmentSetting
                }

                #Display existing role settings on host
                $obj = $item| Format-List | Out-String
                $this.PublishCustomMessage($obj)    
            }
        }
    }
}

class PIMResource {
    [int] $Id
    [string] $ResourceId #Id refered by PIM API to uniquely identify a resource
    [string] $ResourceName 
    [string] $Type 
    [string] $ExternalId #ARM resourceId
}

