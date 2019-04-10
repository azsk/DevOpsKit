
#Acquire Access token
class PIM: CommandBase
{
    hidden $APIroot =  [string]::Empty
    hidden $headerParams = "";
    hidden $UserId = "";
    hidden  $AccessToken="";
    hidden $AccountId="" ;
    hidden $abortflow = 0;

    PIM([string] $subscriptionId, [InvocationInfo] $invocationContext)
    : Base([string] $subscriptionId, [InvocationInfo] $invocationContext)
    {
        $this.AccessToken = "";
        $this.AccountId="";
        $this.APIroot = "https://api.azrbac.mspim.azure.com/api/v2/privilegedAccess/azureResources/";
    }
  
#Acquire Access token
 AcquireToken()
{
    # Using helper method to get current context and access token   
    $ResourceAppIdURI = [WebRequestHelper]::GetServiceManagementUrl()
    $this.AccessToken = [Helpers]::GetAccessToken($ResourceAppIdURI);
    $this.AccountId = [Helpers]::GetCurrentSessionUser()
    $this.UserId = (Get-AzADUser -UserPrincipalName  $this.AccountId).Id
    $this.headerParams= @{'Authorization'="Bearer $($this.AccessToken)"}
    
}

#Gets the jit assignments for logged-in user
hidden [PSObject] MyJitAssignments($active)
{
    $urlme = "";
    if($active)
    {
    $urlme = $this.APIroot + "/roleAssignments?`$expand=linkedEligibleRoleAssignment,subject,roleDefinition(`$expand=resource)&`$filter=(subject/id%20eq%20%27$($this.UserId)%27)+and+(assignmentState%20eq%20%27Eligible%27)"
    }
    else
     {
        $urlme = $this.APIroot + "/roleAssignments?`$expand=linkedEligibleRoleAssignment,subject,roleDefinition(`$expand=resource)&`$filter=(subject/id%20eq%20%27$($this.UserId)%27)+and+(assignmentState%20eq%20%27Active%27)" 
     }
    $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $urlme -Method Get
    $assignments = ConvertFrom-Json $response.Content
    $assignments = $assignments.value 
    $assignments = $assignments | Sort-Object  roleDefinition.resource.type , roleDefinition.resource.displayName
    $obj = @()
    Write-Host ""
    if(($assignments | Measure-Object).Count -gt 0)
    {
        $i = 0
        foreach ($assignment in $assignments)
        {
            $item = New-Object psobject -Property @{
            Id = ++$i
            IdGuid =  $assignment.id
            ResourceId =  $assignment.roleDefinition.resource.id
            OriginalId =  $assignment.roleDefinition.resource.externalId
            ResourceName =  $assignment.roleDefinition.resource.displayName
            ResourceType =  $assignment.roleDefinition.resource.type
            RoleId = $assignment.roleDefinition.id
            RoleName = $assignment.roleDefinition.displayName
            ExpirationDate = $assignment.endDateTime
            SubjectId = $assignment.subject.id
            }
            $obj = $obj + $item
        }
    }
         
    return $obj
}


#List resources
hidden [PSObject] ListResources()
{
    $url = $this.APIroot + "/resources?`$select=id,displayName,type&`$filter=(type%20eq%20%27subscription%27)&`$orderby=displayName&`$top=10&1540887279129" 
    #  Write-Host $url

    $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $url -Method Get
    $resources = ConvertFrom-Json $response.Content
    $i = 0
    $obj = @()
    foreach ($resource in $resources.value)
    {
        $item = New-Object psobject -Property @{
        Id = ++$i
        ResourceId =  $resource.id
        ResourceName =  $resource.DisplayName
        Type =  $resource.type
        ExternalId =  $resource.externalId
    }
    $obj = $obj + $item
}

return $obj
}

#List roles
hidden [PSObject] ListRoles($resourceId)
{
    $url =$this.APIroot + "resources/" + $resourceId + "/roleDefinitions?`$select=id,displayName,type,templateId,resourceId,externalId,subjectCount,eligibleAssignmentCount,activeAssignmentCount&`$orderby=activeAssignmentCount%20desc"
    # Write-Host $url

    $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $url -Method Get
    $roles = ConvertFrom-Json $response.Content
    $i = 0
    $obj = @()
    foreach ($role in $roles.value)
    {
        $item = New-Object psobject -Property @{
        Id = ++$i
        RoleDefinitionId =  $role.id
        RoleName =  $role.DisplayName
        SubjectCount = $role.SubjectCount
    }
    $obj = $obj + $item
    }

    return $obj 
}

#List Assignment
hidden [PSObject] ListAssignmentsWithFilter($resourceId)
{
    $url = $this.APIroot + "resources/" + $resourceId + "`/roleAssignments?`$expand=subject,roleDefinition(`$expand=resource)"
    # Write-Host $url

    $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $url -Method Get
    $roleAssignments = ConvertFrom-Json $response.Content
    $i = 0
    $obj = @()
    foreach ($roleAssignment in $roleAssignments.value)
        {
        $item = New-Object psobject -Property @{
        Id = ++$i
        RoleAssignmentId =  $roleAssignment.id
        ResourceId =  $roleAssignment.roleDefinition.resource.id
        OriginalId =  $roleAssignment.roleDefinition.resource.externalId
        ResourceName =  $roleAssignment.roleDefinition.resource.displayName
        ResourceType =  $roleAssignment.roleDefinition.resource.type
        RoleId = $roleAssignment.roleDefinition.id
        IsPermanent=$roleAssignment.IsPermanent
        RoleName = $roleAssignment.roleDefinition.displayName
        ExpirationDate = $roleAssignment.endDateTime
        SubjectId = $roleAssignment.subject.id
        UserName = $roleAssignment.subject.displayName
        AssignmentState = $roleAssignment.AssignmentState
    }
    $obj = $obj + $item
}

return $obj
}

#List Users
hidden [PSObject]  ListUsers($user_search)
{
    $url = $this.APIroot + "users?`$filter=startswith(displayName,'" + $user_search + "')"
    # Write-Host $url

    $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $url -Method Get
    $users = ConvertFrom-Json $response.Content
    $i = 0
    $obj = @()
    foreach ($user in $users.value)
    {
        $item = New-Object psobject -Property @{
        Id = ++$i
        UserId =  $user.id
        UserName =  $user.DisplayName
    }
    $obj = $obj + $item
    }

    return $obj
}

#Activates the user
hidden Activate()
{
    
    $assignments =$this.MyJitAssignments(1)
    if(($assignments | Measure-Object).Count -gt 0)
    {
        $this.PublishCustomMessage("Role assignments:",[MessageType]::Default)
        $this.PublishCustomMessage("");
        $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
        $this.PublishCustomMessage($($assignments  | Format-Table -AutoSize -Wrap Id,RoleName,ResourceName,ResourceType,ExpirationDate | Out-String),[MessageType]::Default)
        $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
        $this.PublishCustomMessage("")
        Write-Host "  Enter Id to activate: " -ForegroundColor Cyan -NoNewline 
        $choice = Read-Host 
        while($choice -notin $assignments.Id)
        {
            if($choice -eq 0)
            {

                $this.abortflow = 1;
                return;
            }
           Write-Host "  Invalid input" -ForegroundColor Yellow 
           Write-Host "  Enter Id to activate: " -ForegroundColor Cyan -NoNewline
           $choice = Read-Host 
        }

        try
        {
            Write-Host "  Enter activation duration in hours between 1 to 8 hours: " -ForegroundColor Cyan -NoNewline
            [int] $hours =  Read-Host
            while($hours -lt 1 -or $hours -gt 8)
            {
                if($choice -eq 0)
                {
                    $this.abortflow = 1;
                    return;
                }
                Write-Host "  Invalid input" -ForegroundColor Yellow
                Write-Host "  Enter activation duration in hours between 1 to 8 hours: " -ForegroundColor Cyan -NoNewline
               [int] $hours = Read-Host 
            }
        }
        catch
        {
            Write-Host "   Please enter a valid integer value: " -ForegroundColor Yellow -NoNewline
            [int] $hours = Read-Host
            while($hours -lt 1 -or $hours -gt 8)
            {
                if($choice -eq 0)
                {
                    $this.abortflow = 1;
                     return;
                }
                Write-Host "  Invalid input" -ForegroundColor Yellow
                Write-Host "  Enter activation duration in hours between 1 to 8 hours: " -ForegroundColor Cyan -NoNewline
               [int] $hours = Read-Host
            } 
        }
        Write-Host "  Enter the reason for activation of the role: " -ForegroundColor Cyan -NoNewline
        $reason = Read-Host
        $id = $assignments[$choice-1].IdGuid
        $resourceId = $assignments[$choice-1].ResourceId
        $roleDefinitionId = $assignments[$choice-1].RoleId
        $subjectId = $assignments[$choice-1].SubjectId
        $url = $this.APIroot + "roleAssignmentRequests "
        $postParams = '{"roleDefinitionId":"'+$roleDefinitionId+'","resourceId":"'+$resourceId+'","subjectId":"'+$subjectId+'","assignmentState":"Active","type":"UserAdd","reason":"'+$reason+'","schedule":{"type":"Once","startDateTime":"'+(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")+'","duration":"PT' + $hours + 'H"},"linkedEligibleRoleAssignmentId":"'+$id+'"}'
   

        try
        {
            $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $url -Method Post -ContentType "application/json" -Body $postParams
            if($response.StatusCode -eq 201)
            {
                $this.PublishCustomMessage("Activation request queued successfully ...",[MessageType]::Update);
            }
             $recursive = $false
        }
        catch
        {
            $this.PublishCustomMessage($_.Exception.Message,[MessageType]::Error)
        }
    }
    else
    {
        Write-Host "  No eligible role found for the logged in context" -ForegroundColor Yellow
    }
}

#Deactivates the user
hidden Deactivate()
{
         
        $assignments = $this.MyJitAssignments(0) | Where-Object{-not [string]::IsNullorEmpty($_.ExpirationDate)}
        if(($assignments | Measure-Object).Count -gt 0)
        {
            $this.PublishCustomMessage("Role assignments: ")
            $this.PublishCustomMessage("")
            $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
            $this.PublishCustomMessage($($assignments | Format-Table -AutoSize -Wrap Id,RoleName,ResourceName,ResourceType,ExpirationDate | Out-String),[MessageType]::Default)
            $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
            $this.PublishCustomMessage("")
            Write-Host "  Pick Id to deactivate: " -ForegroundColor Cyan -NoNewline
            $choice = Read-Host
            while($choice -notin $assignments.Id)
            {
                if($choice -eq 0)
                {
                    $this.abortflow = 1;
                     return;
                }
                 Write-Host "  Invalid input" -ForegroundColor Yellow
                 Write-Host "  Pick Id to deactivate: " -ForegroundColor Cyan -NoNewline
                $choice = Read-Host 
            }
            $id = $assignments[$choice-1].IdGuid
            $resourceId = $assignments[$choice-1].ResourceId
            $roleDefinitionId = $assignments[$choice-1].RoleId
            $subjectId = $assignments[$choice-1].SubjectId
            $url = $this.APIroot + "/roleAssignmentRequests "
            $postParams = '{"roleDefinitionId":"'+$roleDefinitionId+'","resourceId":"'+$resourceId+'","subjectId":"'+$subjectId+'","assignmentState":"Active","type":"UserRemove","linkedEligibleRoleAssignmentId":"'+$id+'"}'
           try
           {
                $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $url -Method Post -ContentType "application/json" -Body $postParams
                if($response.StatusCode -eq '201')
                {
                     $this.PublishCustomMessage("Role deactivated successfully ... ",[MessageType]::Update);
                }
            
            }
            catch
            {
                $this.PublishCustomMessage($_.Exception.Message,[MessageType]::Error)
            }
        }
        else
        {
            $this.PublishCustomMessage("No Active assignments found.",[MessageType]::Warning);
        }
    

}

#List RoleAssignment
ListAssignment()
{
    #List and Pick resource
    $resources = $this.ListResources()
    if(($resources | Measure-Object).Count -gt 0)
    {
        $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
        $this.PublishCustomMessage($($resources | Format-Table -AutoSize -Wrap Id, ResourceName, Type, ExternalId | Out-String),[MessageType]::Default)
        $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
        $this.PublishCustomMessage("")
        Write-Host "  Pick a resource Id to check permanent assigment: " -ForegroundColor Cyan -NoNewline
        $res_choice = Read-Host 
        while($res_choice -notin $resources.Id)
        {
            if($res_choice -eq 0)
            {                
                $this.abortflow = 1;
                return;
            }
             Write-Host "  Invalid input" -ForegroundColor Yellow
             Write-Host "  Pick a resource Id for assigment: " -ForegroundColor Cyan -NoNewline
            $res_choice = Read-Host            
        }
        $resourceId = $resources[$res_choice-1].ResourceId

        #List Member
        $roleAssignments=$this.ListAssignmentsWithFilter($resourceId)
        $permanentAssignment=$roleAssignments | Where-Object{$_.IsPermanent -eq $true}
        if(($permanentAssignment | Measure-Object).Count -gt 0)
        {
            $permanentAssignment = $permanentAssignment| Sort-Object -Property RoleName,Name 
            $this.PublishCustomMessage("")
            $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
            $this.PublishCustomMessage($($permanentAssignment | Format-Table -Property RoleName, UserName, ResourceType | Out-String),[MessageType]::Default)
        }
        else
        {
            $this.PublishCustomMessage(" No permanent assignments found for this combination.",[MessageType]::Warning);
        }
    }
    else
    {
        $this.PublishCustomMessage("No active assignments found for the current logged in context.", [MessageType]::Warning )
    }
}

#Assign a user to Eligible Role
hidden AssignmentEligible() 
{
    #List and Pick resource
    $resources = $this.ListResources();
    $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
    $this.PublishCustomMessage($($resources | Format-Table -AutoSize -Wrap Id, ResourceName, Type, ExternalId | Out-String),[MessageType]::Default)
    $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
    $this.PublishCustomMessage("")
    if(($resources | Measure-Object).Count -gt 0)
    {
            Write-Host "  Pick a resource Id for assigment: " -ForegroundColor Cyan -NoNewline
            $res_choice = Read-Host 
            while($res_choice -notin $resources.Id)
            {
                if($res_choice -eq 0)
                {
                     $this.abortflow = 1;
                     return;
                }
                 Write-Host "  Invalid input" -ForegroundColor Yellow
                 Write-Host "  Pick a resource Id for assigment: " -ForegroundColor Cyan -NoNewline
                $res_choice = Read-Host 
            }
            $resourceId = $resources[$res_choice-1].ResourceId

            #List and Pick a role
            $roles = $this.ListRoles($resourceId)
            $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
            $this.PublishCustomMessage($($roles | Format-Table -AutoSize -Wrap Id, RoleName, RoleDefinitionId | Out-String),[MessageType]::Default)
            $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
            $this.PublishCustomMessage("")
            Write-Host "  Pick a role Id: " -ForegroundColor Cyan -NoNewline
            $role_choice = Read-Host 
             while($role_choice -notin $roles.Id)
            {
                if($role_choice -eq 0)
                {
                   $this.abortflow = 1;
                   return;
                }
                Write-Host "  Invalid input" -ForegroundColor Yellow
                Write-Host "  Pick a role Id: " -ForegroundColor Cyan -NoNewline
                $role_choice = Read-Host 
            }
            $roleDefinitionId = $roles[$role_choice-1].RoleDefinitionId
    
            #Get Object Id of usesr by Name, and get input for allowed time of role assignment
            Write-Host "  Please enter the Principal Name ( e.g. 'xyz@contoso.com') of the user to whom role has to be assigned: " -ForegroundColor Cyan -NoNewline
            $user_search = Read-Host 
            try
            {
                $users = Get-AzADUser -UserPrincipalName $user_search
                while(($users | Measure-Object).Count -ne 1)
                {
                    if($users -eq 0)
                    {
                        $this.abortflow = 1;
                         return;
                    }
                    $this.PublishCustomMessage("Unable to fetch details of the principal name provided, please make sure to enter the correct values.", [MessageType]::Warning)
                    Write-Host "  Please enter the Principal Name ( e.g. 'xyz@contoso.com') of the user to whom role has to be assigned: " -ForegroundColor Cyan -NoNewline
                    $user_search = Read-Host 
                    $users = Get-AzADUser -UserPrincipalName $user_search
                }
            }
            catch
            {
                $this.PublishCustomMessage("Unable to fetch details of the principal name provided, please make sure to enter the correct values.", [MessageType]::Warning)
                return;
            }
            $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
            $this.PublishCustomMessage($($users | Format-Table -Property  * | Out-String),[MessageType]::Default);
            $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
            $this.PublishCustomMessage("")
            [int]$days=90
            $subjectId = $users.Id
            try
            {
                Write-Host "  Enter the period in days between 1 to 90 days for role assignment: " -ForegroundColor Cyan -NoNewline
                [int]$days= Read-Host 
                while($days -gt 90 -or $days -lt 1)
                {
                    if($days -eq 0)
                    {
                        $this.abortflow = 1;
                        return;
                    }
                    Write-Host "  Invalid input" -ForegroundColor Yellow
                    Write-Host "  Enter the period in days between 1 to 90 days for role assignment: " -ForegroundColor Cyan -NoNewline
                    $days= Read-Host 
                }
            }
            catch
            {
                
                Write-Host "  Please enter a integer value between 1 to 90" -ForegroundColor Yellow -NoNewline
                Write-Host "  Enter the period in days between 1 to 90 days for role assignment: " -ForegroundColor Cyan
                [int]$days= Read-Host 
                while($days -gt 90 -or $days -lt 1)
                {
                    if($days -eq 0)
                    {
                        $this.abortflow = 1;
                        return;
                    }
                    Write-Host "  Invalid input" -ForegroundColor Yellow
                    Write-Host "  Enter the period in days between 1 to 90 days for role assignment: " -ForegroundColor Cyan -NoNewline
                    $days= Read-Host 
                } 
            }

            $url = $this.APIroot+"/roleAssignmentRequests"
            # Update end time
            $ts = New-TimeSpan -Days $days
            $postParams = '{"assignmentState":"Eligible","type":"AdminAdd","reason":"Assign","roleDefinitionId":"' + $roleDefinitionId + '","resourceId":"' + $resourceId + '","subjectId":"' + $subjectId + '","schedule":{"startDateTime":"' + (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + '","endDateTime":"' + ((get-date) + $ts).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + '","type":"Once"}}'
    
            try
            {
                $response = Invoke-WebRequest -UseBasicParsing -Headers $this.headerParams -Uri $url -Method Post -ContentType "application/json" -Body $postParams
                if($response.StatusCode -eq 201)
                {
                $this.PublishCustomMessage("Assignment request queued successfully ...",[MessageType]::Update);
                }
                $recursive = $false
            }
            catch
            {
                $this.PublishCustomMessage($_.Exception.Message,[MessageType]::Error)               
            }
    }
    else
    {
       $this.PublishCustomMessage("You are not eligible to assign a role. If you have recently elevated/activated your permissions, please run Connect-AzAccount and re-run the script.",[MessageType]::Warning)
    }
}

 #Show menu
ShowMenu()
{
            $this.PublishCustomMessage("")
            $this.PublishCustomMessage("`n###################################################################################")
            $this.PublishCustomMessage("")
            $this.PublishCustomMessage("  PIM Assignment Menu")
            $this.PublishCustomMessage("  1. List your eligible role assignments")
            $this.PublishCustomMessage("  2. Activate an eligible role" )
            $this.PublishCustomMessage("  3. Deactivate an active role" )
            $this.PublishCustomMessage("  4. Assign a role to user" )
            $this.PublishCustomMessage("  5. Check permanent access on subscription for a role")
            $this.PublishCustomMessage("  6. Exit")
            $this.PublishCustomMessage("")
            $this.PublishCustomMessage("`n###################################################################################")
            $this.PublishCustomMessage(" Note: Enter 0 during any stage to abort the PIM workflow. ", [MessageType]::Warning)
}

hidden [void] PIMScript()
{
    try
    {
        $this.AcquireToken();
    }
    catch
    {
        Write-Host "Unable to fetch access token. Run Connect-AzAccount and then execute this command" -ForegroundColor Red
        return;
    }  
     
        do
        {
            $this.ShowMenu();
            Write-Host " Enter your selection: " -ForegroundColor Cyan -NoNewline
            $input = Read-Host 
            switch ($input)
                {
                    '1'
                    {
                        $assignments = $this.MyJitAssignments(1)
                        if(($assignments | Measure-Object).Count -gt 0)
                        {
                        $this.PublishCustomMessage("Role assignments:",[MessageType]::Default)
                        $this.PublishCustomMessage("");
                        $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
                        $this.PublishCustomMessage(($assignments | Format-Table -AutoSize Id,RoleName,ResourceName,ResourceType,ExpirationDate| Out-String),[MessageType]::Default)
                        $this.PublishCustomMessage([Constants]::SingleDashLine,[MessageType]::Default)
                        $this.PublishCustomMessage("");
                        }
                        else
                        {
                            $this.PublishCustomMessage("No eligible roles found for the current login",[MessageType]::Warning);
                        }
                    }
                    '2'
                    {
                        $this.Activate()
                    }
                    '3'
                    {
                        $this.Deactivate()
                    }
                    '4'
                    {
                        $this.AssignmentEligible()
                    }
                    '5'
                    {
                        $this.ListAssignment()
                    }
                    '6'
                    {
                        return
                    }
                    
                }
            if($this.abortflow)
            {
                return;
            }
        }
        until($input -lt 1 )
    
             
}     



}



