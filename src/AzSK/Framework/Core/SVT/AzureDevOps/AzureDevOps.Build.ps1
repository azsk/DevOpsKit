Set-StrictMode -Version Latest 
class Build: SVTBase
{    

    Build([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {

    }

    hidden [ControlResult] CheckCredInVariables([ControlResult] $controlResult)
	{
        
        $ToolFolderPath =  [ConfigurationManager]::GetAzSKSettings().CredScanToolPath
        if((-not [string]::IsNullOrEmpty($ToolFolderPath)) -and (Test-Path $ToolFolderPath))
        {
            $ToolPath = Get-ChildItem -Path $ToolFolderPath -File -Include "CredentialScanner.exe" -Recurse 
            if($ToolPath)
            {
                $apiURL = $this.ResourceContext.ResourceId
                $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
                if($responseObj)
                {
                    try
                    {
                        $buildDefFileName = $($this.ResourceContext.ResourceName).Replace(" ","")
                        $buildDefPath = [Constants]::AzSKTempFolderPath + "\Builds\"+ $buildDefFileName + "\";
                        if(-not (Test-Path -Path $buildDefPath))
                        {
                            mkdir -Path $buildDefPath -Force | Out-Null
                        }

                        $responseObj | ConvertTo-Json -Depth 5 | Out-File "$buildDefPath\$buildDefFileName.json"
                        $scanResultPath = "$buildDefPath\CredScan-matches.csv"
                        ."$($Toolpath.FullName)" -I $buildDefPath -S "$($ToolPath.Directory.FullName)\Searchers\buildsearchers.xml" -f csv -Ve 1 -O "$buildDefPath\CredScan"    
                        if(Test-Path $scanResultPath)
                        {
                            $credList = Get-Content -Path $scanResultPath | ConvertFrom-Csv 
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
        
        return $controlResult;
    }
}