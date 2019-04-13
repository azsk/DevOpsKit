Set-StrictMode -Version Latest

class AADResourceResolver: Resolver
{
    [SVTResource[]] $SVTResources = @();
    [string] $ResourcePath;
    [string] $tenantId
    [int] $SVTResourcesFoundCount=0;
    AADResourceResolver([string]$tenantId, $userNames, $appNames, $orgNames): Base($tenantId)
	{
        $this.tenantId = $tenantId
 
        if(-not [string]::IsNullOrEmpty($userNames))
        {
			$this.UserNames += $this.ConvertToStringArray($userNames);

			if ($this.UserNames.Count -eq 0)
			{
				throw [SuppressedException] "The parameter 'UserNames' does not contain any string."
			}
        }	

        if(-not [string]::IsNullOrEmpty($appNames))
        {
			$this.AppNames += $this.ConvertToStringArray($appNames);
			if ($this.AppNames.Count -eq 0)
			{
				throw [SuppressedException] "The parameter 'AppNames' does not contain any string."
			}
        }

        if(-not [string]::IsNullOrEmpty($orgNames))
        {
			$this.OrgNames += $this.ConvertToStringArray($orgNames);
			if ($this.OrgNames.Count -eq 0)
			{
				throw [SuppressedException] "The parameter 'OrgNames' does not contain any string."
			}
        }
    }

    [void] LoadResourcesForScan()
	{
        $tenantInfoMsg = [AccountHelper]::GetCurrentTenantInfo();
        Write-Host -ForegroundColor Green $tenantInfoMsg  #TODO: PublishCustomMessage...just before #-of-resources...etc.?

        #Core controls are evaluated by default.
        $svtResource = [SVTResource]::new();
        $svtResource.ResourceName = $this.tenantId;
        $svtResource.ResourceType = "AAD.Tenant";
        $svtResource.ResourceId = "Organization/$($this.tenantId)/"  #TODO
        $svtResource.ResourceTypeMapping = ([SVTMapping]::AADResourceMapping |
                                        Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                        Select-Object -First 1)
        $this.SVTResources +=$svtResource

        #TODO should we special case current user? @me?
        <#
        $svtResource = [SVTResource]::new();
        $svtResource.ResourceName = $this.organizationName;
        $svtResource.ResourceType = "AAD.User";
        $svtResource.ResourceId = "Organization/$($this.tenantId)/User" #TODO
        $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                        Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                        Select-Object -First 1)
        $this.SVTResources +=$svtResource
        #>

        #Get apps owned by user
        $currUser = [AccountHelper]::GetCurrentSessionUser();
        #BUGBUG-tmp-workaround-mprabhu11AAD: $userCreatedObjects = [array] (Get-AzureADUserCreatedObject -ObjectId $currUser)
        $userCreatedObjects = [array] (Get-AzureADApplication -Top 20)
        $appTypeMapping = ([SVTMapping]::AADResourceMapping |
            Where-Object { $_.ResourceType -eq 'AAD.Application' } |
            Select-Object -First 1)

        $maxObj = 3
        $nObj = $maxObj
        foreach ($obj in $userCreatedObjects) {
            if ($obj.ObjectType -eq 'Application') 
            {
                $svtResource = [SVTResource]::new();
                $svtResource.ResourceName = $obj.DisplayName;
                $svtResource.ResourceGroupName = $currUser #TODO
                $svtResource.ResourceType = "AAD.Application";
                $svtResource.ResourceId = $obj.ObjectId     
                $svtResource.ResourceTypeMapping = $appTypeMapping   
                $this.SVTResources +=$svtResource
                if (--$nObj -eq 0) { break;} 
            }
        }        

        $nObj = $maxObj
        $spnTypeMapping = ([SVTMapping]::AADResourceMapping |
            Where-Object { $_.ResourceType -eq 'AAD.ServicePrincipal' } |
            Select-Object -First 1)

        #BUGBUG: Uncomment below as tmp workaround for mprabhu11live to resolve to some SPNs
        #$userCreatedObjects = [array] (Get-AzureADServicePrincipal -Top 20)
        
        foreach ($obj in $userCreatedObjects) {
            if ($obj.ObjectType -eq 'ServicePrincipal') 
            {
                $svtResource = [SVTResource]::new();
                $svtResource.ResourceName = $obj.DisplayName;
                $svtResource.ResourceGroupName = $currUser #TODO
                $svtResource.ResourceType = "AAD.ServicePrincipal";
                $svtResource.ResourceId = $obj.ObjectId     
                $svtResource.ResourceTypeMapping = $spnTypeMapping   
                $this.SVTResources +=$svtResource
                if (--$nObj -eq 0) { break;} 
            }
        }              #TODO odd that above query does not show user created 'Group' objects.

        #TODO delta between user-created/user-owned for Apps/SPNs?
        $nObj = $maxObj
        $userOwnedObjects =  [array] (Get-AzureADUserOwnedObject -ObjectId $currUser)
        $grpTypeMapping = ([SVTMapping]::AADResourceMapping |
            Where-Object { $_.ResourceType -eq 'AAD.Group' } |
            Select-Object -First 1)

        foreach ($obj in $userOwnedObjects) {
            if ($obj.ObjectType -eq 'Group') 
            {
                $svtResource = [SVTResource]::new();
                $svtResource.ResourceName = $obj.DisplayName;
                $svtResource.ResourceGroupName = $currUser #TODO
                $svtResource.ResourceType = "AAD.Group";
                $svtResource.ResourceId = $obj.ObjectId     
                $svtResource.ResourceTypeMapping = $grpTypeMapping   
                $this.SVTResources +=$svtResource
                if (--$nObj -eq 0) { break;} 
            }
        }              #TODO odd that above query does not show user created 'Group' objects.
                

        Write-Warning("TODO: Remove 3 object restriction for all types '`$nObj'")
        $this.SVTResourcesFoundCount = $this.SVTResources.Count
    }
}