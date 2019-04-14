Set-StrictMode -Version Latest

class AADResourceResolver: Resolver
{
    [SVTResource[]] $SVTResources = @();
    [string] $ResourcePath;
    [string] $tenantId;
    [int] $SVTResourcesFoundCount=0;
    [bool] $scanTenant;
    [int] $MaxObjectsToScan;
    AADResourceResolver([string]$tenantId, [bool] $bScanTenant): Base($tenantId)
	{
        if ([string]::IsNullOrEmpty($tenantId))
        {
            $this.tenantId = ([AccountHelper]::GetCurrentAADContext()).TenantId
        }
        else 
        {
            $this.tenantId = $tenantId
        }
        $this.scanTenant = $bScanTenant
    }

    [void] SetMaxObjectsToScan($maxObj)
    {
        $this.MaxObjectsToScan = $maxObj
    }

    [void] LoadResourcesForScan()
	{
        $tenantInfoMsg = [AccountHelper]::GetCurrentTenantInfo();
        Write-Host -ForegroundColor Green $tenantInfoMsg  #TODO: Need to do with PublishCustomMessage...just before #-of-resources...etc.?

        #TODO: TBD - for use later...
        $bAdmin = [AccountHelper]::IsUserInAPermanentAdminRole();

        #scanTenant is used to determine is the scan is tenant wide or just in the scope of the running user.
        if ($this.scanTenant)
        {
            #Core controls are evaluated by default.
            $svtResource = [SVTResource]::new();
            $svtResource.ResourceName = $this.tenantId;
            $svtResource.ResourceType = "AAD.Tenant";
            $svtResource.ResourceId = "Organization/$($this.tenantId)/"  #TODO
            $svtResource.ResourceTypeMapping = ([SVTMapping]::AADResourceMapping |
                                            Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                            Select-Object -First 1)
            $this.SVTResources +=$svtResource
        }

        $currUser = [AccountHelper]::GetCurrentSessionUser();

        $userOwnedObjects = @()

        try {  #BUGBUG: Investigate why this crashes in live tenant (even if user-created-objects exist...which should show up as 'user-owned' by default!) 
            $userOwnedObjects = [array] (Get-AzureADUserOwnedObject -ObjectId $currUser)
        }
        catch { #As a workaround, we take user-created objects, which seems to work (strange!)
            $userCreatedObjects = [array] (Get-AzureADUserCreatedObject -ObjectId $currUser)
            $userOwnedObjects = $userCreatedObjects
        }
        #TODO Explore delta between 'user-created' v. 'user-owned' for Apps/SPNs


        $appObjects = @()
        if ($this.scanTenant)
        {
            $appObjects = [array] (Get-AzureADApplication -Top 20)
        }
        else {
            $appObjects = [array] ($userOwnedObjects | ?{$_.ObjectType -eq 'Application'})
        }

        $appTypeMapping = ([SVTMapping]::AADResourceMapping |
            Where-Object { $_.ResourceType -eq 'AAD.Application' } |
            Select-Object -First 1)

        #TODO: Set to 3 for preview release. A user can use a larger value if they want via the 'MaxObj' cmdlet param.
        $maxObj = $this.MaxObjectsToScan

        $nObj = $maxObj
        foreach ($obj in $appObjects) {
            $svtResource = [SVTResource]::new();
            $svtResource.ResourceName = $obj.DisplayName;
            $svtResource.ResourceGroupName = $currUser #TODO
            $svtResource.ResourceType = "AAD.Application";
            $svtResource.ResourceId = $obj.ObjectId     
            $svtResource.ResourceTypeMapping = $appTypeMapping   
            $this.SVTResources +=$svtResource
            if (--$nObj -eq 0) { break;} 
        }        

        $spnObjects = @()
        if ($this.scanTenant)
        {
            $spnObjects = [array] (Get-AzureADServicePrincipal -Top 20)
        }
        else {
            $spnObjects = [array] ($userOwnedObjects | ?{$_.ObjectType -eq 'ServicePrincipal'})
        }
        
        $spnTypeMapping = ([SVTMapping]::AADResourceMapping |
            Where-Object { $_.ResourceType -eq 'AAD.ServicePrincipal' } |
            Select-Object -First 1)

        $nObj = $maxObj
        foreach ($obj in $spnObjects) {
            $svtResource = [SVTResource]::new();
            $svtResource.ResourceName = $obj.DisplayName;
            $svtResource.ResourceGroupName = $currUser #TODO
            $svtResource.ResourceType = "AAD.ServicePrincipal";
            $svtResource.ResourceId = $obj.ObjectId     
            $svtResource.ResourceTypeMapping = $spnTypeMapping   
            $this.SVTResources +=$svtResource
            if (--$nObj -eq 0) { break;} 
        }   #TODO odd that above query does not show user created 'Group' objects.

        
        $grpObjects = @()
        if ($this.scanTenant)
        {
            $grpObjects = [array] (Get-AzureADGroup -Top 20)
        }
        else {
            $grpObjects = [array] ($userOwnedObjects | ?{$_.ObjectType -eq 'Group'})
        }

        $grpTypeMapping = ([SVTMapping]::AADResourceMapping |
            Where-Object { $_.ResourceType -eq 'AAD.Group' } |
            Select-Object -First 1)

        $nObj = $maxObj
        foreach ($obj in $grpObjects) {
            $svtResource = [SVTResource]::new();
            $svtResource.ResourceName = $obj.DisplayName;
            $svtResource.ResourceGroupName = $currUser #TODO
            $svtResource.ResourceType = "AAD.Group";
            $svtResource.ResourceId = $obj.ObjectId     
            $svtResource.ResourceTypeMapping = $grpTypeMapping   
            $this.SVTResources +=$svtResource
            if (--$nObj -eq 0) { break;} 
        }   #TODO Why does this not show user created 'Group' objects in live tenant?
                
        $this.SVTResourcesFoundCount = $this.SVTResources.Count
    }
}