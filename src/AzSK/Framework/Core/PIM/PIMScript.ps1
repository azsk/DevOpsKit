
#Acquire Access token
class PIM: CommandBase {
    hidden $APIroot = [string]::Empty
    hidden $headerParams = "";
    hidden $UserId = "";
    hidden  $AccessToken = "";
    hidden $AccountId = "" ;
    hidden $abortflow = 0;

    PIM([string] $subscriptionId, [InvocationInfo] $invocationContext)
    : Base([string] $subscriptionId, [InvocationInfo] $invocationContext) {
        $this.AccessToken = "";
        $this.AccountId = "";
        $this.APIroot = "https://api.azrbac.mspim.azure.com/api/v2/privilegedAccess/azureResources/";
    }
  
    #Acquire Access token
    AcquireToken() {
        # Using helper method to get current context and access token   
        $ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
        $this.AccessToken = [Helpers]::GetAccessToken($ResourceAppIdURI);
        $this.AccountId = [Helpers]::GetCurrentSessionUser()
        $this.UserId = (Get-AzADUser -UserPrincipalName  $this.AccountId).Id
        $this.headerParams = @{'Authorization' = "Bearer $($this.AccessToken)" }
    
    }

    #Gets the jit assignments for logged-in user
    hidden [PSObject] MyJitAssignments() {
        $this.AcquireToken();    
        $urlme = $this.APIroot + "/roleAssignments?`$expand=linkedEligibleRoleAssignment,subject,roleDefinition(`$expand=resource)&`$filter=(subject/id%20eq%20%27$($this.UserId)%27)+and+(assignmentState%20eq%20%27Eligible%27)"
    
    
        $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $urlme -Method Get
        $assignments = ConvertFrom-Json $response.Content
        $assignments = $assignments.value 
        $assignments = $assignments | Sort-Object  roleDefinition.resource.type , roleDefinition.resource.displayName
        $obj = @()
        Write-Host ""
        if (($assignments | Measure-Object).Count -gt 0) {
        
            foreach ($assignment in $assignments) {
                $item = New-Object psobject -Property @{
                    IdGuid         = $assignment.id
                    ResourceId     = $assignment.roleDefinition.resource.id
                    OriginalId     = $assignment.roleDefinition.resource.externalId
                    ResourceName   = $assignment.roleDefinition.resource.displayName
                    ResourceType   = $assignment.roleDefinition.resource.type
                    RoleId         = $assignment.roleDefinition.id
                    RoleName       = $assignment.roleDefinition.displayName
                    ExpirationDate = $assignment.endDateTime
                    SubjectId      = $assignment.subject.id
                }
                $obj = $obj + $item
            }
        }
         
        return $obj
    }

    # This function resolves the resource that matches to parameters passed in command
    hidden [PIMResource] PIMResourceResolver($SubscriptionId, $ResourceGroupName, $ResourceName) {
        $rtype = 'subscription'
        $selectedResourceName = $this.SubscriptionContext.SubscriptionName;
    
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
        $resources = $this.ListResources($item.ResourceType);
        $resolvedResource = $resources | Where-Object { $_.ResourceName -eq $item.ResourceName }
        #If context has access over resourcegroups or resources with same name, get a match based on Subscription and rg passed in param
        if (($resolvedResource | Measure-Object).Count -gt 1) {       
           
            $resolvedResource = $resolvedResource | Where-Object { $_.ExternalId -match  $SubscriptionId}
            if(-not([string]::IsNullOrEmpty($ResourceGroupName))){
                $resolvedResource = $resolvedResource | Where-Object { $_.ExternalId -match  $ResourceGroupName}
            }
        
        }
        return $resolvedResource
    
    }
    #List all the resources accessible to context.
    hidden [System.Collections.Generic.List[PIMResource]] ListResources($type) {
        $this.AcquireToken();
        $resources = $null
        #this seperation is required due to nature of API, it operates in paging/batching manner when we query for all types
        if ($type -eq 'resource') {
            $Resourceurl = $this.APIroot + "/resources?`$select=id,displayName,type&`$filter=(type%20ne%20%27resourcegroup%27%20and%20type%20ne%20%27subscription%27%20and%20type%20ne%20%27managementgroup%27%20and%20type%20ne%20%27resourcegroup%27%20and%20type%20ne%20%27subscription%27%20and%20type%20ne%20%27managementgroup%27)" 
            try {
                $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $Resourceurl -Method Get
                $values = ConvertFrom-Json $response.Content
                $resources = $values.value
                $hasOdata = $values | Get-Member -Name '@odata.nextLink'
                while ($null -ne $hasOdata -and -not([string]::IsNullOrEmpty(($values).'@odata.nextLink'))) {
                    $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $(($values).'@odata.nextLink') -Method Get
                    $values = ConvertFrom-Json $response.Content
                    $resources += $values.value
                    $hasOdata = $values | Get-Member -Name '@odata.nextLink'
                
                }
            
            
            }
            catch {
                $this.PublishCustomMessage($_.ErrorDetails.Message, [MessageType]::Error)
            }
        }
        else {   
            $Resourceurl = $this.APIroot + "/resources?`$select=id,displayName,type&`$filter=(type%20eq%20%27resourcegroup%27%20or%20type%20eq%20%27subscription%27or%20type%20eq%20%27managementgroup%27)&`$orderby=type" 
            $response = $null
            try {
                $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $Resourceurl -Method Get
                $values = ConvertFrom-Json $response.Content
                $resources = $values.value
            }
            catch {
                $this.PublishCustomMessage($_.ErrorDetails.Message, [MessageType]::Error)
                return $null;
            }
        
        
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



    #List roles
    hidden [PSObject] ListRoles($resourceId) {
        $this.AcquireToken();
        $url = $this.APIroot + "resources/" + $resourceId + "/roleDefinitions?`$select=id,displayName,type,templateId,resourceId,externalId,subjectCount,eligibleAssignmentCount,activeAssignmentCount&`$orderby=activeAssignmentCount%20desc"
        $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $url -Method Get
        $roles = ConvertFrom-Json $response.Content
        $i = 0
        $obj = @()
        foreach ($role in $roles.value) {
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

    #List Assignment
    hidden [PSObject] ListAssignmentsWithFilter($resourceId, $IsPermanent) {
        $this.AcquireToken()
        $url = $this.APIroot + "resources/" + $resourceId + "`/roleAssignments?`$expand=subject,roleDefinition(`$expand=resource)"
        #Write-Host $url

        $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $url -Method Get
        $roleAssignments = ConvertFrom-Json $response.Content
        $i = 0
        $obj = @()
        $assignments =@();
        foreach ($roleAssignment in $roleAssignments.value) {
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
            }
            $obj = $obj + $item
        }
        if($obj.Count -gt 0)
        {
            if($IsPermanent)
            {
                $assignments = $obj | Where-Object{$_.IsPermanent -eq $true}
                
            }
            else{
                $assignments = $obj | Where-Object{$_.IsPermanent -eq $false}
                
            }
        }
        
    return $assignments
    }

    #List Users
    hidden [PSObject]  ListUsers($user_search) {
        $url = $this.APIroot + "users?`$filter=startswith(displayName,'" + $user_search + "')"
        #Write-Host $url

        $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $url -Method Get
        $users = ConvertFrom-Json $response.Content
        $i = 0
        $obj = @()
        foreach ($user in $users.value) {
            $item = New-Object psobject -Property @{
                Id       = ++$i
                UserId   = $user.id
                UserName = $user.DisplayName
            }
            $obj = $obj + $item
        }

        return $obj
    }

    #Activates the user
    hidden Activate($SubscriptionId, $ResourceGroupName, $ResourceName, $roleName, $Justification, $Duration) {
        $this.AcquireToken();
        $assignments = $this.MyJitAssignments()
        $resource = $this.PIMResourceResolver($SubscriptionId, $ResourceGroupName, $ResourceName)

        if (($assignments | Measure-Object).Count -gt 0) {
            $matchingAssignment = $assignments | Where-Object { $_.OriginalId -eq $resource.ExternalId -and $_.RoleName -eq $roleName }
            if (($matchingAssignment | Measure-Object).Count -gt 0) {
                $this.PublishCustomMessage("Requesting activation of your $($matchingAssignment.RoleName) role on $($matchingAssignment.ResourceName). ", [MessageType]::Update);
                $resourceId = $matchingAssignment.ResourceId
                $roleDefinitionId = $matchingAssignment.RoleId
                $subjectId = $matchingAssignment.SubjectId
                $RequestActivationurl = $this.APIroot + "roleAssignmentRequests "
                $postParams = '{"roleDefinitionId":"' + $roleDefinitionId + '","resourceId":"' + $resourceId + '","subjectId":"' + $subjectId + '","assignmentState":"Active","type":"UserAdd","reason":"' + $Justification + '","schedule":{"type":"Once","startDateTime":"' + (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + '","duration":"PT' + $Duration + 'H"},"linkedEligibleRoleAssignmentId":"' + $matchingAssignment.IdGuid + '"}'
       
    
                try {
                    $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $RequestActivationurl -Method Post -ContentType "application/json" -Body $postParams
                    if ($response.StatusCode -eq 201) {
                        $this.PublishCustomMessage("Activation queued successfully ... ", [MessageType]::Update);
                    }
                 
                }
                catch {
                    $this.PublishCustomMessage($_.ErrorDetails.Message, [MessageType]::Error)
                }
            }
            else {
                $this.PublishCustomMessage(" No matching eligible role found for the current context", [MessageType]::Warning)
            }
        }    
        else {
            $this.PublishCustomMessage(" No eligible role found for the current context", [MessageType]::Warning)
        }
    }

    #Deactivates the user
    hidden Deactivate($SubscriptionId, $ResourceGroupName, $ResourceName, $roleName) {
        $this.AcquireToken();
        $assignments = $this.MyJitAssignments() | Where-Object { -not [string]::IsNullorEmpty($_.ExpirationDate) }
        $resource = $this.PIMResourceResolver($SubscriptionId, $ResourceGroupName, $ResourceName)

        if (($assignments | Measure-Object).Count -gt 0) {
            $matchingAssignment = $assignments | Where-Object { $_.OriginalId -eq $resource.ExternalId -and $_.RoleName -eq $roleName }
            if (($matchingAssignment | Measure-Object).Count -gt 0) {     
                $this.PublishCustomMessage("Requesting deactivation of your $($matchingAssignment.RoleName) role on $($matchingAssignment.ResourceName). ", [MessageType]::Default);
                $id = $matchingAssignment.IdGuid
                $resourceId = $matchingAssignment.ResourceId
                $roleDefinitionId = $matchingAssignment.RoleId
                $subjectId = $matchingAssignment.SubjectId
                $deactivaturl = $this.APIroot + "/roleAssignmentRequests "
                $postParams = '{"roleDefinitionId":"' + $roleDefinitionId + '","resourceId":"' + $resourceId + '","subjectId":"' + $subjectId + '","assignmentState":"Active","type":"UserRemove","linkedEligibleRoleAssignmentId":"' + $id + '"}'
                try {
                    $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $deactivaturl -Method Post -ContentType "application/json" -Body $postParams
                    if ($response.StatusCode -eq '201') {
                        $this.PublishCustomMessage("Deactivation queued successfully... ", [MessageType]::Update);
                    }

            
                }
                catch {
                    $this.PublishCustomMessage($_.ErrorDetails.Message, [MessageType]::Error)
                }
            }
        }
        else {
            $this.PublishCustomMessage("No active assignments found for the current context.", [MessageType]::Warning);
        }
    

    }

    #List RoleAssignment
    hidden [PSObject] ListAssignment($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $CheckPermanent,) {
        #List and Pick resource
        $this.AcquireToken();
        $resources = $this.PIMResourceResolver($SubscriptionId, $ResourceGroupName, $ResourceName)

        $permanentAssignment = $null
        if (($resources | Measure-Object).Count -gt 0) {
       
            $roleAssignments = $this.ListAssignmentsWithFilter($resources.ResourceId, $CheckPermanent)
            $Assignments = $roleAssignments | Where-Object {$_.MemberType -ne 'Inherited' -and $_.RoleName -in $RoleNames}
            if (($Assignments | Measure-Object).Count -gt 0) {
                $Assignments = $Assignments | Sort-Object -Property RoleName, Name 
                $this.PublishCustomMessage("")
                $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default)
                $this.PublishCustomMessage($($Assignments | Format-Table -Property RoleName, UserName, ResourceType | Out-String), [MessageType]::Default)
            }
            else {
                if ($CheckPermanent) {
                    $this.PublishCustomMessage(" No permanent assignments found for this combination.", [MessageType]::Warning);
                }
                else {
                    $this.PublishCustomMessage(" No PIM eligible assignments found for this combination.", [MessageType]::Warning);
                }    
            }
        }
        else {
            $this.PublishCustomMessage("No active assignments found for the current logged in context.", [MessageType]::Warning )
        }
        return $permanentAssignment;
    }

    #Assign a user to Eligible Role
    hidden AssignPIMRole($subscriptionId, $resourcegroupName, $resourceName, $roleName, $PrincipalName, $duration) {
        $this.AcquireToken();
        $resolvedResource = $this.PIMResourceResolver($subscriptionId, $resourcegroupName, $resourceName)
        if (($resolvedResource | Measure-Object).Count -gt 0) {
            $resourceId = $resolvedResource.ResourceId
            $roles = $this.ListRoles($resourceId)
            $roleDefinitionId = ($roles | Where-Object { $_.RoleName -eq $RoleName }).RoleDefinitionId
            $users = $null
            $subjectId = "";
            #Get Object Id of usesr by Name, and get input for allowed time of role assignment
            try {
                $users = Get-AzADUser -UserPrincipalName $PrincipalName
            }
            catch {
                $this.PublishCustomMessage("  Unable to fetch details of the principal name provided.", [MessageType]::Warning)
                return;
            }
            if (($users | Measure-Object).Count -gt 0) {
                $subjectId = $users.Id
            }
            else {
                $this.PublishCustomMessage("  Unable to fetch details of the principal name provided.", [MessageType]::Error)
                return;
            }            
            $url = $this.APIroot + "/roleAssignmentRequests"
            # Update end time
            if (-not($duration)) {
                $duration = 15
            }
            $ts = New-TimeSpan -Days $duration
            $postParams = '{"assignmentState":"Eligible","type":"AdminAdd","reason":"Assign","roleDefinitionId":"' + $roleDefinitionId + '","resourceId":"' + $resourceId + '","subjectId":"' + $subjectId + '","schedule":{"startDateTime":"' + (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + '","endDateTime":"' + ((get-date) + $ts).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + '","type":"Once"}}'
    
            try {
                $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $url -Method Post -ContentType "application/json" -Body $postParams
                if ($response.StatusCode -eq 201) {
                    $this.PublishCustomMessage("Assignment request for $PrincipalName for the $RoleName role on $($resolvedResource.ResourceName) queued successfully ...", [MessageType]::Update);
                }  
                if ($response.StatusCode -eq 401) {
                    $this.PublishCustomMessage("You are not eligible to assign a role. If you have recently elevated/activated your permissions, please run Connect-AzAccount and re-run the script.", [MessageType]::Error);
                }          
            }
            catch {
                $this.PublishCustomMessage($_.ErrorDetails.Message, [MessageType]::Error)   
                        
            }
        }
        else {
            $this.PublishCustomMessage("No matching resource found for assignment.", [MessageType]::Error)
        }
    }

    hidden ListMyEligibleRoles() {
        $assignments = $this.MyJitAssignments()
        if (($assignments | Measure-Object).Count -gt 0) {
            $this.PublishCustomMessage("Your eligible role assignments:", [MessageType]::Default)
            $this.PublishCustomMessage("");
            $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default)
            $this.PublishCustomMessage(($assignments | Format-Table -AutoSize Id, RoleName, ResourceName, ResourceType, ExpirationDate | Out-String), [MessageType]::Default)
            $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default)
            $this.PublishCustomMessage("");
        }
        else {
            $this.PublishCustomMessage("No eligible roles found for the current login", [MessageType]::Warning);
        }
    }

    hidden TransitionFromPermanentRolesToPIM($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName) {
       
        $resolvedResource = $this.PIMResourceResolver($subscriptionId, $resourcegroupName, $resourceName)
        if (($resolvedResource | Measure-Object).Count -gt 0) {    
            $resourceId = $resolvedResource.ResourceId
            $roles = $this.ListRoles($resourceId)
            $role = ($roles | Where-Object { $_.RoleName -eq $RoleName })
            $roleDefinitionId = $role.RoleDefinitionId
            $CriticalRoles = $role.RoleName #$ControlSettings.CriticalPIMRoles 
            $this.PublishCustomMessage("  Fetching permanent assignment for '$(($criticalRoles) -join ", ")' on $($resolvedResource.Type): $($resolvedResource.ResourceName )")
            $permanentRoles = $this.ListAssignmentsWithFilter($resourceId, $true)
            if (($permanentRoles | Measure-Object).Count -gt 0) {
                $permanentRolesForTransition = $permanentRoles | Where-Object { $_.SubjectType -eq 'User' -and $_.MemberType -ne 'Inherited' -and $_.RoleName -in $CriticalRoles }
                if (($permanentRolesForTransition | Measure-Object).Count -gt 0) {    
                    $this.PublishCustomMessage($($permanentRolesForTransition | Format-Table -AutoSize -Wrap UserName, ResourceName, ResourceType, RoleName | Out-String), [MessageType]::Default)
                    $this.PublishCustomMessage("");
                    Write-Host "  For the above shown permanent assignments corresponding PIM roles will be assigned. Do you want to continue? (Y/N)" -ForegroundColor Yellow
                    $ToContinue = Read-Host
                    if ($ToContinue -eq 'y') {               
                        $Assignmenturl = $this.APIroot + "/roleAssignmentRequests"  
                        $roles = $this.ListRoles($resourceId)  
                        Write-Host "  Enter the duration in days for role assignment" -ForegroundColor Cyan
                        $ts = Read-Host;
                        $permanentRolesForTransition | ForEach-Object {
                            $roleName = $_.RoleName
                            $roleDefinitionId = ($roles | Where-Object { $_.RoleName -eq $roleName }).RoleDefinitionId 
                            $subjectId = $_.SubjectId
                            #$Scope= $_.OriginalId
                            $postParams = '{"assignmentState":"Eligible","type":"AdminAdd","reason":"Assign","roleDefinitionId":"' + $roleDefinitionId + '","resourceId":"' + $resourceId + '","subjectId":"' + $subjectId + '","schedule":{"startDateTime":"' + (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + '","endDateTime":"' + ((get-date).AddDays($ts).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")) + '","type":"Once"}}'
                            try {
                                $this.PublishCustomMessage("");
                                $this.PublishCustomMessage([Constants]::SingleDashLine)
                                $this.PublishCustomMessage("Requesting PIM assignment for '$($_.RoleName)' role for $($_.UserName) on $($_.ResourceType) '$($resolvedResource.ResourceName)'...");
                                $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $Assignmenturl -Method Post -ContentType "application/json" -Body $postParams
                                if ($response.StatusCode -eq 201) {
                                    $this.PublishCustomMessage("Assignment request queued successfully.", [MessageType]::Warning);
                                }
                                $this.PublishCustomMessage([Constants]::SingleDashLine)
                          
                            }
                            catch {
                          
                                $code = $_.ErrorDetails.Message | ConvertFrom-Json
                          
                                if ($code.error.code -eq "RoleAssignmentExists") {
                                    $this.PublishCustomMessage("  PIM Assignment for the above already exists.", [MessageType]::Default)
                                }
                                else {
                                    $this.PublishCustomMessage("$($code.error)", [MessageType]::Error)
                                }
                            }         
          
                        }#foreach
                      
                    }
                    else {
                        return;
                    }
                }
                else {
                    $this.PublishCustomMessage(" No permanent assignments eligible for PIM assignment found.", [MessageType]::Warning);       
                }
            }
            else {
                $this.PublishCustomMessage(" No permanent assignments found for this resource.", [MessageType]::Warning);       
            }
        }

    
    }

    hidden RemovePermanentAssignments($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName, $OnlyPIMEligibleAssignments) {
        $this.AcquireToken();
        $resolvedResource = $this.PIMResourceResolver($subscriptionId, $resourcegroupName, $resourceName)
        $resourceId = ($resolvedResource).ResourceId 
        $users = @();
        $CriticalRoles = $RoleName 
        $this.PublishCustomMessage("  Fetching permanent assignment for '$(($criticalRoles) -join ", ")' role on $($resolvedResource.Type): $($resolvedResource.ResourceName )")
        $this.PublishCustomMessage("Note: Assignments for the current context running the command will not be subjected to removal. ", [MessageType]::Warning)
        $permanentRoles = $this.ListAssignmentsWithFilter($resourceId, $true)
        $eligibleAssignments = $this.ListAssignmentsWithFilter($resourceId, $false)
        $eligibleAssignments = $eligibleAssignments | Where-Object { $_.SubjectType -eq 'User' -and $_.MemberType -ne 'Inherited' -and $_.RoleName -in $CriticalRoles }
        if (($permanentRoles | Measure-Object).Count -gt 0) {
            $permanentRolesForTransition = $permanentRoles | Where-Object { $_.SubjectType -eq 'User' -and $_.MemberType -ne 'Inherited' -and $_.RoleName -in $CriticalRoles }
            $successfullyassignedRoles = @();
            $currentContext = [Helpers]::GetCurrentRmContext();
            $permanentRolesForTransition = $permanentRolesForTransition | Where-Object { $_.PrincipalName -ne $currentContext.Account.Id }
            if($OnlyPIMEligibleAssignments -ne 'All')
            {
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
    
    if (($users | Measure-Object).Count -gt 0) {
                
        
        $this.PublishCustomMessage("Following user assignments would be removed. $($users | Format-Table -Property UserName, RoleName, OriginalId | Out-String)")
        $this.PublishCustomMessage("");
        Write-Host "Do you want to proceed? (Y/N)" -ForegroundColor Yellow
        $userResp = Read-Host 
        if ($userResp -eq 'y') {
            foreach ($user in $users) {
                $this.PublishCustomMessage([Constants]::SingleDashLine);
                $this.PublishCustomMessage("Requesting removal of permanent assignment of'$($user.RoleName)' role for $($user.UserName) from $($user.OriginalId)")
                Remove-AzRoleAssignment -SignInName $user.PrincipalName -RoleDefinitionName $user.RoleName -Scope $user.OriginalId
                $this.PublishCustomMessage("Successfully removed permanent assignment", [MessageType]::Update )                
                $this.PublishCustomMessage([Constants]::SingleDashLine);

            }
        }
    }
    else {
        if($OnlyPIMEligibleAssignments -ne 'All'){
            $this.PublishCustomMessage("No eligible roles corresponding to permanent assignments found for the scope", [MessageType]::Warning)
        }
        else {
            $this.PublishCustomMessage("No permanent assignments found for the scope", [MessageType]::Warning)
        }
    }

    }

    hidden ConfigureRoleSetting() {
        $this.AcquireToken();
        $resources = $this.ListResources();    
        $resourceId = $null;
        $rtype = @();
        $i = 0;
        $distTypes = $resources | Sort-Object -Property  'Type' -Unique | Select-Object -Property 'Type' 
        foreach ($res in $distTypes) {
            $item = New-Object psobject -Property @{
                Id   = ++$i
                Type = $res.Type
           
            }
            $rtype = $rtype + $item;
        }
        $this.PublishCustomMessage($($rtype | Format-Table  @{Label = "#"; Expression = { $_.Id } }, 'Type' | Out-String));
        Write-Host "Enter # for the type of resource you want to perform operation on" -ForegroundColor Cyan
        $resourceTypeId = Read-Host
        while ($resourceTypeId -notin $rType.Id) {
            if ($resourceTypeId -eq 0) {                
                $this.abortflow = 1;
                return ;
            }
            Write-Host "  Invalid input" -ForegroundColor Yellow
            Write-Host "  Pick a valid # for resource type: " -ForegroundColor Cyan -NoNewline
            $resourceTypeId = Read-Host       
        }
        $resourceId = $null
        $resources = $resources | Where-Object { $_.Type -eq ($rtype[$resourceTypeId - 1].Type) }
        if (($rtype[$resourceTypeId - 1].Type) -match 'resourcegroup') {
            Write-Host "Please enter the resource group name for which permanent assignments are required to transition to eligible" -ForegroundColor Cyan
            $rgname = Read-Host 
            while ($rgname -notin $resources.ResourceName) {
                if ($rgname -eq 0) {
                    $this.abortflow = 1;
                    return;
                }
                Write-Host "  Invalid input" -ForegroundColor Yellow
                Write-Host "Please enter the resource group name for for which role settings are required to configured" -ForegroundColor Cyan
                $rgname = Read-Host 
            }
            $resourceId = ($resources | Where-Object { $_.ResourceName -eq $rgname }).ResourceId
            $Rid = ($resources | Where-Object { $_.ResourceName -eq $rgname }).Id
        }
        else {
       
            $this.PublishCustomMessage($($resources | Format-Table -AutoSize -Wrap @{Label = "#"; Expression = { $_.Id } }, ResourceName, Type, ExternalId | Out-String), [MessageType]::Default)
            Write-Host "  Enter # for which role settings are required to configured" -ForegroundColor Cyan
            $res_choice = Read-Host 
            while ($res_choice -notin $resources.Id) {
                if ($res_choice -eq 0) {                
                    $this.abortflow = 1;
                    return ;
                }
                Write-Host "  Invalid input" -ForegroundColor Yellow
                Write-Host "  Pick a resource Id for assigment: " -ForegroundColor Cyan -NoNewline
                $res_choice = Read-Host            
            }
            $resourceId = ($resources | Where-Object { $_.Id -eq $res_choice }).ResourceId 
            $Rid = ($resources | Where-Object { $_.Id -eq $res_choice }).Id
        }

        # Get the roles
        $roles = $this.ListRoles($resourceId)
        $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default)
        $this.PublishCustomMessage($($roles | Format-Table -AutoSize -Wrap Id, RoleName, RoleDefinitionId | Out-String), [MessageType]::Default)
        $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default)
        $this.PublishCustomMessage("")
        Write-Host "  Pick a role Id: " -ForegroundColor Cyan -NoNewline
        $role_choice = Read-Host 
        while ($role_choice -notin $roles.Id) {
            if ($role_choice -eq 0) {
                $this.abortflow = 1;
                return;
            }
            Write-Host "  Invalid input" -ForegroundColor Yellow
            Write-Host "  Pick a role Id: " -ForegroundColor Cyan -NoNewline
            $role_choice = Read-Host 
        }
        $roleDefinitionId = $roles[$role_choice - 1].RoleDefinitionId
        $roleName = $roles[$role_choice - 1].RoleName
        $resourceName = $resources | Where-Object { $_.Id -eq $Rid }
        $response = $null;
        $roleSettings = $null;
        $obj = @();
        try {
            $url = $this.APIroot + "roleSettings`?`$filter=(resource/id+eq+%27" + $resourceId + "%27)"
            # Write-Host $url
    
            $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $url -Method Get
            $roleSettings = $response.Content | ConvertFrom-Json
            $ChosenRolesSetting = $roleSettings.value | Where-Object { $_.roleDefinitionId -eq $roleDefinitionId }
            Write-Host "  Do you want to allow permanent eligible assignment for $roleName for Resource: $resourceName ? (Y/N) " -ForegroundColor Cyan
            $allowPermanentEligibleAssignment = Read-Host
            # $roleSettings.
            $eligibleAdminDays = 90;
            if ($allowPermanentEligibleAssignment -eq 'y') {
                Write-Host "  Enter the duration in days you want to expire eligible assignment" -ForegroundColor Cyan
                $eligibleAdminDays = Read-Host 
            }
            $eligibleAdminDaysInMin = $eligibleAdminDays * 1440
            ($ChosenRolesSetting.adminEligibleSettings | Where-Object { $_.ruleIdentifier -eq "ExpirationRule" }).setting = "{`"maximumGrantPeriod`":$eligibleAdminDays,`"maximumGrantPeriodInMinutes`":`"$eligibleAdminDaysInMin`",`"permanentAssignment`":`"$allowPermanentEligibleAssignment`"}"

            Write-Host "Require Multi-Factor Authentication on active assignment? (Y/N)" -ForegroundColor Cyan
            $adminMFA = $true
            $adminMFAchoice = Read-Host
            while ($adminMFAchoice -ne 'y' -and $adminMFAchoice -ne 'n' ) {
                if ($adminMFAchoice -eq 'n') {
                    $adminMFA = $false
                
                }
                Write-Host " Invalide Choice. Enter (Y/N)" -ForegroundColor Cyan
                $adminMFAchoice = Read-Host
            
            }
            if ($adminMFAchoice -eq 'n') {
                $adminMFA = $false
            
            }
            ($ChosenRolesSetting.adminEligibleSettings | Where-Object { $_.ruleIdentifier -eq "MFARule" }).setting = "{`"mfaRequired`":$adminMFA}"
            Write-Host "Require justification on active assignment? (Y/N)" -ForegroundColor Cyan
            $adminJustification = Read-Host
            $RequireAdminJust = $true
            while ($adminJustification -ne 'y' -and $adminJustification -ne 'n' ) {
                if ($adminJustification -eq 'y') {
                    $RequireAdminJust = $false
                }
            }
            if ($adminJustification -eq 'n') {
                $RequireAdminJust = $false
            }
            ($ChosenRolesSetting.adminMemberSettings | Where-Object { $_.ruleIdentifier -eq "JustificationRule" }).setting = "{`"required`":$RequireAdminJust}"
            Write-Host "Activation maximum duration (hours)?  (Y/N)" -ForegroundColor Cyan
            $maxActivationHrs = Read-Host
            ($ChosenRolesSetting.userMemberSettings | Where-Object { $_.ruleIdentifier -eq "ExpirationRule" }).setting = "{`"maximumGrantPeriod`":`"$maxActivationHrs`",`"maximumGrantPeriodInMinutes`":$($maxActivationHrs*60),`"permanentAssignment`":false}"
            Write-Host "Require Multi-Factor Authentication on activation? (Y/N)" -ForegroundColor Cyan
            $mfaForActivation = Read-Host
            $userMFA = $true
            while ($mfaForActivation -ne 'y' -and $mfaForActivation -ne 'n' ) {
                if ($mfaForActivation -eq 'n') {
                    $userMFA = $false
                
                }
                Write-Host " Invalide Choice. Enter (Y/N)" -ForegroundColor Cyan
                $mfaForActivation = Read-Host
            
            }
            if ($mfaForActivation -eq 'n') {
                $userMFA = $false
            
            }
            ($ChosenRolesSetting.userMemberSettings | Where-Object { $_.ruleIdentifier -eq "MFARule" }).setting = "{`"mfaRequired`":$userMFA}"
            Write-Host "Require justification on activation? (Y/N)" -ForegroundColor Cyan
            $userJustification = Read-Host
            $adminJustification = Read-Host
            $userJust = $true
            while ($userJustification -ne 'y' -and $userJustification -ne 'n' ) {
                if ($userJustification -eq 'y') {
                    $userJust = $false
                }
            }
            if ($userJustification -eq 'n') {
                $userJust = $false
            }
            ($ChosenRolesSetting.userMemberSettings | Where-Object { $_.ruleIdentifier -eq "JustificationRule" }).setting = "{`"required`":$userJust}"
            Write-Host "Require approval to activate? (Y/N)" -ForegroundColor Cyan
            $requireApprover = Read-Host
            $users = $null
            if ($requireApprover -eq 'y') {

                Write-Host "Enter the Approvers" -ForegroundColor Cyan
                Write-Host "  Please enter the Principal Name ( e.g. 'xyz@contoso.com') of the approver: " -ForegroundColor Cyan -NoNewline
                $user_search = Read-Host 
                try {
                    $users = Get-AzADUser -UserPrincipalName $user_search
                    while (($users | Measure-Object).Count -ne 1) {
                        if ($users -eq 0) {
                            $this.abortflow = 1;
                            return;
                        }
                        $this.PublishCustomMessage("Unable to fetch details of the principal name provided, please make sure to enter the correct values.", [MessageType]::Warning)
                        Write-Host "  Please enter the Principal Name ( e.g. 'xyz@contoso.com') of the user to whom role has to be assigned: " -ForegroundColor Cyan -NoNewline
                        $user_search = Read-Host 
                        $users = Get-AzADUser -UserPrincipalName $user_search
                    }
                }
                catch {
                    $this.PublishCustomMessage("Unable to fetch details of the principal name provided, please make sure to enter the correct values.", [MessageType]::Warning)
                    return;
                }
                $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default)
                $this.PublishCustomMessage($($users | Format-Table -Property  * | Out-String), [MessageType]::Default);
                # setting={"enabled":true,"approvers":[{"id":"1281d7dc-c6ae-4d78-ad65-612971c73ba2","displayName":"Zhilmil Gupta (Tata Consultancy Services Ltd)","type":"User","email":"v-zhgup@microsoft.com"}]}
                # ($ChosenRolesSetting.userMemberSettings | Where-Object{$_.ruleIdentifier -eq "ApprovalRule"}).setting.enabled = 'true'
                ($ChosenRolesSetting.userMemberSettings | Where-Object { $_.ruleIdentifier -eq "ApprovalRule" }).setting = "{`"enabled`":true,`"approvers`":[{`"id`": $($users.Id|Out-String),`"displayName `": $($users.DisplayName | Out-String),`"type`" : `"User`" ,`"email`" : $($users.UserPrincipalName|Out-String)}]}"
            }
            else {
                ($ChosenRolesSetting.userMemberSettings | Where-Object { $_.ruleIdentifier -eq "ApprovalRule" }).setting = "{`"enabled`":false,`"approvers`":[]}"
            }
            $param = $ChosenRolesSetting | ConvertTo-Json -Depth 5
            $url = $this.APIroot + "roleSettings/$($ChosenRolesSetting.Id)"
            $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $url -Method PATCH -ContentType "application/json" -Body $param
          
        }
        catch {
            $this.PublishCustomMessage($_)
        }
    }


    #Show menu
    ShowMenu() {
        $this.PublishCustomMessage("")
        $this.PublishCustomMessage("`n###################################################################################")
        $this.PublishCustomMessage("")
        $this.PublishCustomMessage("  PIM Assignment Menu")
        $this.PublishCustomMessage("  1. List your eligible role assignments")
        $this.PublishCustomMessage("  2. Activate an eligible role" )
        $this.PublishCustomMessage("  3. Deactivate an active role" )
        $this.PublishCustomMessage("  4. Assign a role to user" )
        $this.PublishCustomMessage("  5. Check permanent access on subscription for a role")
        $this.PublishCustomMessage("  6. Assign PIM roles to permanent assignments")
        $this.PublishCustomMessage("  7. Remove permanent assignemnts for eligible assignments.")
        # $this.PublishCustomMessage("  7. Configure role settings")
        # $this.PublishCustomMessage("  0. Exit")
        $this.PublishCustomMessage("")
        $this.PublishCustomMessage("`n###################################################################################")
        $this.PublishCustomMessage(" Note: Enter 0 during any stage to abort the PIM workflow. ", [MessageType]::Warning)
    }

    hidden [void] PIMScript() {
        try {
            $this.AcquireToken();
        }
        catch {
            Write-Host "Unable to fetch access token. Run Connect-AzAccount -UseDeviceAuthentication and then execute this command." -ForegroundColor Red
            return;
        }  
     
        do {
            $this.ShowMenu();
            Write-Host " Enter your selection: " -ForegroundColor Cyan -NoNewline
            $input = Read-Host 
            switch ($input) {
                '1' {
                    $assignments = $this.MyJitAssignments()
                    if (($assignments | Measure-Object).Count -gt 0) {
                        $this.PublishCustomMessage("Role assignments:", [MessageType]::Default)
                        $this.PublishCustomMessage("");
                        $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default)
                        $this.PublishCustomMessage(($assignments | Format-Table -AutoSize Id, RoleName, ResourceName, ResourceType, ExpirationDate | Out-String), [MessageType]::Default)
                        $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default)
                        $this.PublishCustomMessage("");
                    }
                    else {
                        $this.PublishCustomMessage("No eligible roles found for the current login", [MessageType]::Warning);
                    }
                }
                '2' {
                    $this.Activate()
                }
                '3' {
                    $this.Deactivate()
                }
                '4' {
                    $this.AssignmentEligible()
                }
                '5' {
                    $this.ListAssignment()
                }
                '6' {
                    $this.TransitionFromPermanentRolesToPIM()
                }
                '7' {
                    $this.RemovePermanentAssignments($null)
                }
                '8' {
                    $this.ConfigureRoleSetting();
                }
                    
            }
            if ($this.abortflow) {
                return;
            }
        }
        until($input -lt 1 )
    
             
    }     



}

class PIMResource {
    [int] $Id
    [string] $ResourceId #Id refered by PIM API to uniquely identify a resource
    [string] $ResourceName 
    [string] $Type 
    [string] $ExternalId #ARM resourceId
}

