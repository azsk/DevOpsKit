using namespace Microsoft.IdentityModel.Clients.ActiveDirectory
using namespace System.IO

class AzSKADOTokenCache : TokenCache
{
    [String]$CacheFilePath = [Constants]::AzSKAppFolderPath + "/AzSKADOTkns.dat"; 
    #TODO: Move to constants. Also, add feature-flag (or AzSKSetting)
  
    AzSKADOTokenCache() {
        $beforeAccessMethod   = [AzSKADOTokenCache].GetMethod("BeforeAccessNotification") 
        $beforeAccessDelegate = [System.Delegate]::CreateDelegate([TokenCacheNotification], $this, $beforeAccessMethod);
        $this.BeforeAccess =  $beforeAccessDelegate;

        $afterAccessMethod   = [AzSKADOTokenCache].GetMethod("AfterAccessNotification") 
        $afterAccessDelegate = [System.Delegate]::CreateDelegate([TokenCacheNotification], $this, $afterAccessMethod);
        $this.AfterAccess =  $afterAccessDelegate;
    } 

    hidden [void] Clear()
    {
        ([TokenCache]$this).Clear();
        [File]::Delete($this.CacheFilePath);
    }



    # Triggered right before ADAL needs to access the cache.
    # Reload the cache from the persistent store in case it changed since the last access.
    [void] BeforeAccessNotification($args)
    {
        #TODO: Lock file?
        [byte[]] $dataFromFile = [AzSKADOTokenCache]::ReadFromFileIfExists($this.CacheFilePath);
        $this.Deserialize($dataFromFile);
    }

    # Triggered right after ADAL accessed the cache.
    [void] AfterAccessNotification($args)
    {
        if ($this.HasStateChanged)
        {
            #TODO: Lock file?
            # reflect changes in the persistent store
            [byte[]] $dataToFile = $this.Serialize();
            [AzSKADOTokenCache]::WriteToFileIfNotNull($this.CacheFilePath, $dataToFile);
            # once the write operation took place, restore the HasStateChanged bit to false
            $this.HasStateChanged = $false;
        }
    }

    static [byte[]] ReadFromFileIfExists([string] $path)
    {
        [byte[]] $protectedBytes = $null
        
        if (Test-Path $path -PathType Leaf) 
        {
            $protectedBytes = [File]::ReadAllBytes($path);
        }

        [byte[]] $unprotectedBytes = $null

        if ($protectedBytes -ne $null)
        {
            $unprotectedBytes = [System.Security.Cryptography.ProtectedData]::Unprotect($protectedBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser);
        }

        return $unprotectedBytes;
    }

    static [void] WriteToFileIfNotNull([string] $path, [byte[]] $blob)
    {
        if ($blob -ne $null)
        {
            [byte[]] $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect($blob, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser);
            [File]::WriteAllBytes($path, $protectedBytes);
        }
        else
        {
            [File]::Delete($path);
        }
    }
}