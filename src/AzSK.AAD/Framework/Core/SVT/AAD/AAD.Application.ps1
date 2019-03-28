Set-StrictMode -Version Latest 
class Application: SVTBase
{    
	hidden [PSObject] $ResourceObject;

    Application([string] $tenantId, [SVTResource] $svtResource): Base($tenantId,$svtResource) 
    {

        $objId = $svtResource.ResourceId
        $this.ResourceObject = Get-AzureADObjectByObjectId -ObjectIds $objId
    }

    hidden [PSObject] GetResourceObject()
    {
        return $this.ResourceObject;
    }

    hidden [ControlResult] CheckOldTestDemoApps([ControlResult] $controlResult)
	{
        $demoAppNames = @('demo', 'test', 'pilot')    #TODO: This should be in org-policy

        $demoAppsRegex = [string]::Join('|', $demoAppNames) 

        $app = $this.GetResourceObject()

        $appName = $app.DisplayName

        if ($appName -eq $null -or -not ($appName -imatch $demoAppsRegex))
        {
            $controlResult.AddMessage([VerificationResult]::Passed,
                                        "No demo/test/pilot apps found.");
        }
        else
        {
            #TODO: How can we determine how old an app entry is (or if it is 'active'?)
            $controlResult.AddMessage([VerificationResult]::Verify,
                                        "Found one or more demo/test apps. Review and cleanup","TODO_FIX");
        }
        return $controlResult;
    }

    hidden [ControlResult] CheckReturnURLsAreHTTPS([ControlResult] $controlResult)
	{
        $app = $this.GetResourceObject()
        $ret = $false
        if($app.replyURLs -eq $null -or $app.replyURLs.Count -eq 0)
        {
            $ret = $true
        }
        else
        {
            $nonHttpURLs = @()
            foreach ($url  in $app.replyURLs)
            {
                if ($url.tolower().startswith("http:"))
                {
                    $nonHttpURLs += $url
                }
            }

            if ($nonHttpURLs.Count -eq 0)
            {
                $ret = $true
            }
            else
            {
                $controlResult.AddMessage("Found $($nonHttpURLs.Count) non-HTTPS URLs.");
            }

            if ($ret -eq $true)
            {
                $controlResult.AddMessage([VerificationResult]::Passed,
                                            "No non-HTTPS URLs in replyURLs.");
            }
            else
            {
                $controlResult.AddMessage([VerificationResult]::Failed,
                                            "Found one or more non-HTTPS URLs in replyURLs.","TODO_FIX");
            }
        }
        return $controlResult;
    }
#avail-to-other-tenants -> $false
#allow-guests-access -> $false
}