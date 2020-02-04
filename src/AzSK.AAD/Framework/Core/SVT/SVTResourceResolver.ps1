Set-StrictMode -Version Latest

class SVTResourceResolver: AzSKRoot
{
    
    [string[]] $ResourceNames = @();
    [string] $ResourceType = "";
    [ResourceTypeName] $ResourceTypeName = [ResourceTypeName]::All;
	[Hashtable] $Tag = $null;
    [string] $TagName = "";
    [string[]] $TagValue = "";
	hidden [string[]] $ResourceGroups = @();
	[ResourceTypeName] $ExcludeResourceTypeName = [ResourceTypeName]::All;
	[string[]] $ExcludeResourceNames=@();
	[SVTResource[]] $ExcludedResources=@();
	[string] $ExcludeResourceWarningMessage=[string]::Empty
	[string[]] $ExcludeResourceGroupNames=@();
	[string[]] $ExcludedResourceGroupNames=@();
	[string] $ExcludeResourceGroupWarningMessage=[string]::Empty
    
    
    [SVTResource[]] $SVTResources = @();
    [string] $ResourcePath;
    [string] $tenantId;
    [int] $SVTResourcesFoundCount=0;
    [bool] $scanTenant;
    [int] $MaxObjectsToScan;
    [string[]] $ObjectTypesToScan;
    hidden static [string[]] $AllTypes = @("Application", "Device", "Group", "ServicePrincipal", "User");
    SVTResourceResolver([string]$tenantId, [bool] $bScanTenant): Base($tenantId)
	{
        if ([string]::IsNullOrEmpty($tenantId))
        {
            $this.tenantId = ([ContextHelper]::GetCurrentAADContext()).TenantId
        }
        else 
        {
            $this.tenantId = $tenantId
        }
        $this.scanTenant = $bScanTenant
    }

    [void] SetScanParameters([string[]] $objTypesToScan, $maxObj)
    {
        $this.MaxObjectsToScan = $maxObj
        
        if ($objTypesToScan.Contains("All"))
        {
            if ($objTypesToScan.Count -ne 1)
            {
                throw ([SuppressedException]::new("The objectType 'All' cannot be used in combination with other types.", [SuppressedExceptionType]::InvalidOperation))
            }
            $this.ObjectTypesToScan = [SVTResourceResolver]::AllTypes
        }
        elseif ($objTypesToScan.Contains("None"))
        {
            if ($objTypesToScan.Count -ne 1)
            {
                throw ([SuppressedException]::new("The objectType 'None' cannot be used in combination with other types.", [SuppressedExceptionType]::InvalidOperation))
            }
            $this.ObjectTypesToScan = $objTypesToScan
        }
        else
        {
            $this.ObjectTypesToScan = $objTypesToScan
        }
    }

    [bool] NeedToScanType([string] $objType)
    {
        return $this.ObjectTypesToScan -contains $objType
    }

    [void] LoadResourcesForScan()
	{
        $tenantInfoMsg = [ContextHelper]::GetCurrentTenantInfo();
        #Write-Host -ForegroundColor Green $tenantInfoMsg  #TODO: Need to do with PublishCustomMessage...just before #-of-resources...etc.?
        $this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`n$tenantInfoMsg`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update )

        #TODO: TBD - for use later...
        $bAdmin = [ContextHelper]::IsUserInAPermanentAdminRole();

        #scanTenant is used to determine is the scan is tenant wide or just within the scope of the current (logged-in) user.
        if ($this.scanTenant)
        {
            $svtResource = [SVTResource]::new();
            $svtResource.ResourceName = $this.SubscriptionContext.SubscriptionName;
            $svtResource.ResourceType = "AAD.Tenant";
            $svtResource.ResourceId = $this.tenantId
            $svtResource.ResourceTypeMapping = ([SVTMapping]::AADResourceMapping |
                                            Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                            Select-Object -First 1)
            $this.SVTResources +=$svtResource
        }

        $currUser = [ContextHelper]::GetCurrentSessionUserObjectId();

        $userOwnedObjects = @()

        try {  #BUGBUG: Investigate why this crashes in the Live tenant (even if user-created-objects exist...which should show up as 'user-owned' by default!) 
            $userOwnedObjects = [array] (Get-AzureADUserOwnedObject -ObjectId $currUser)
        }
        catch { #As a workaround, we take user-created objects, which seems to work (strange!)
            $userCreatedObjects = [array] (Get-AzureADUserCreatedObject -ObjectId $currUser)
            $userOwnedObjects = $userCreatedObjects
        }
        #TODO Explore delta between 'user-created' v. 'user-owned' for Apps/SPNs

        $maxObj = $this.MaxObjectsToScan

        if ($this.NeedToScanType("Application"))
        {
            $appObjects = @()
            if ($this.scanTenant)
            {
                $appObjects = [array] (Get-AzureADApplication -Top  $maxObj)
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
                $svtResource.ResourceGroupName = ""  #If blank, the column gets skipped in CSV file. 
                #TODO: If rgName == "" then all LOGs end up in root folder alongside CSV, README.txt. May need to have a reasonable 'mock' RGName.
                $svtResource.ResourceType = "AAD.Application";
                $svtResource.ResourceId = $obj.ObjectId     
                $svtResource.ResourceTypeMapping = $appTypeMapping   
                $this.SVTResources +=$svtResource
                if (--$nObj -eq 0) { break;} 
            }        
        }

        if ($this.NeedToScanType("ServicePrincipal"))
        {
            $spnObjects = @()
            if ($this.scanTenant)
            {
                $spnObjects = [array] (Get-AzureADServicePrincipal -Top  $maxObj)
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
                $svtResource.ResourceGroupName = ""  #If blank, the column gets skipped in CSV file.
                $svtResource.ResourceType = "AAD.ServicePrincipal";
                $svtResource.ResourceId = $obj.ObjectId     
                $svtResource.ResourceTypeMapping = $spnTypeMapping   
                $this.SVTResources +=$svtResource
                if (--$nObj -eq 0) { break;} 
            }   #TODO odd that above query does not show user created 'Group' objects.
        }

        if ($this.NeedToScanType("Device"))
        {
            $deviceObjects = @()
            if ($this.scanTenant)
            {
                $deviceObjects = [array] (Get-AzureADDevice -Top  $maxObj)
            }
            else {
                $DeviceObjects = [array] (Get-AzureADUserOwnedDevice -ObjectId $currUser)
            }
            
            $deviceTypeMapping = ([SVTMapping]::AADResourceMapping |
                Where-Object { $_.ResourceType -eq 'AAD.Device' } |
                Select-Object -First 1)

            $nObj = $maxObj
            foreach ($obj in $deviceObjects) {
                $svtResource = [SVTResource]::new();
                $svtResource.ResourceName = $obj.DisplayName;
                $svtResource.ResourceGroupName = ""  #If blank, the column gets skipped in CSV file.
                $svtResource.ResourceType = "AAD.Device";
                $svtResource.ResourceId = $obj.ObjectId     
                $svtResource.ResourceTypeMapping = $deviceTypeMapping   
                $this.SVTResources +=$svtResource
                if (--$nObj -eq 0) { break;} 
            }   #TODO odd that above query does not show user created 'Group' objects.
        }

    
        if ($this.NeedToScanType("User"))
        {

            $userObjects = @()
            if ($this.scanTenant)
            {
                $userObjects = [array] (Get-AzureADUser -Top  $maxObj)
            }
            else {
                $userObjects = [array] (Get-AzureADUser -ObjectId $currUser)
            }

            $userTypeMapping = ([SVTMapping]::AADResourceMapping |
                Where-Object { $_.ResourceType -eq 'AAD.User' } |
                Select-Object -First 1)

            $nObj = $maxObj
            foreach ($obj in $userObjects) {
                $svtResource = [SVTResource]::new();
                $svtResource.ResourceName = $obj.DisplayName;
                $svtResource.ResourceGroupName = ""  #If blank, the column gets skipped in CSV file.
                $svtResource.ResourceType = "AAD.User";
                $svtResource.ResourceId = $obj.ObjectId     
                $svtResource.ResourceTypeMapping = $userTypeMapping   
                $this.SVTResources +=$svtResource
                if (--$nObj -eq 0) { break;} 
            } 
        }


        if ($this.NeedToScanType("Group"))
        {


            $grpObjects = @()
            if ($this.scanTenant)
            {
                $grpObjects = [array] (Get-AzureADGroup -Top  $maxObj)
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
                $svtResource.ResourceGroupName = ""  #If blank, the column gets skipped in CSV file.
                $svtResource.ResourceType = "AAD.Group";
                $svtResource.ResourceId = $obj.ObjectId     
                $svtResource.ResourceTypeMapping = $grpTypeMapping   
                $this.SVTResources +=$svtResource
                if (--$nObj -eq 0) { break;} 
            }   #TODO Why does this not show user created 'Group' objects in live tenant?
        }

        $this.SVTResourcesFoundCount = $this.SVTResources.Count
    }
}