Set-StrictMode -Version Latest
class BugLogPathManager {
    hidden static [string] $AreaPath = $null
    hidden static [string] $IterationPath = $null
    #flag to check if the path validity test has been done once, this will be used to skip path validation, whether correct/incorrect for all control results
    hidden static [bool] $checkValidPathFlag = $true;
    #flag to check if the path that has been declared is valid
    hidden static [bool] $isPathValid = $false;
    
    
    #function to find if the area and iteration path are valid
    static hidden [bool] CheckIfPathIsValid([string] $OrgName,[string] $ProjectName, [InvocationInfo] $InvocationContext,[string] $ControlSettingsBugLogAreaPath, [string] $ControlSettingsBugLogIterationPath, [bool] $isBugLogCustomFlow) {
        
        #to check if we have checked path validity before
        if ([BugLogPathManager]::checkValidPathFlag -or $isBugLogCustomFlow) {
            [BugLogPathManager]::AreaPath = $null
            #checking path validity for the first time
            $pathurl = "https://dev.azure.com/{0}/{1}/_apis/wit/wiql?api-version=5.1" -f $($OrgName), $ProjectName
            [BugLogPathManager]::AreaPath = $InvocationContext.BoundParameters['AreaPath'];
            [BugLogPathManager]::IterationPath = $InvocationContext.BoundParameters['IterationPath'];

            #check if area and iteration path have been provided as a parameter in control scan
            if (![BugLogPathManager]::AreaPath) {
                #if no parameter is passed, check in org policy
                if ($ControlSettingsBugLogAreaPath -eq "RootDefaultProject") {
                    #if path specified as RootProjectPath consider the project name as the area path
                    [BugLogPathManager]::AreaPath = $ProjectName
                }
                else {
                    [BugLogPathManager]::AreaPath = $ControlSettingsBugLogAreaPath
                }
            }
            if (![BugLogPathManager]::IterationPath) {
                if ($ControlSettingsBugLogIterationPath -eq "RootDefaultProject") {
                    [BugLogPathManager]::IterationPath = $ProjectName
                }
                else {
                    [BugLogPathManager]::IterationPath = $ControlSettingsBugLogIterationPath
                }
            }

            #sanitizing for JSON
            [BugLogPathManager]::AreaPath = [BugLogPathManager]::AreaPath.Replace("\", "\\")
            [BugLogPathManager]::IterationPath = [BugLogPathManager]::IterationPath.Replace("\", "\\")

            #copying the value for easy inputting to the query JSON
            $AreaPathForJSON = [BugLogPathManager]::AreaPath
            $IterationPathForJSON = [BugLogPathManager]::IterationPath
            $WIQL_query = "Select [System.AreaPath], [System.IterationPath] From WorkItems WHERE [System.AreaPath]='$AreaPathForJSON' AND [System.IterationPath]='$IterationPathForJSON'"
            $body = @{ query = $WIQL_query }
            $bodyJson = @($body) | ConvertTo-Json
		
            try {

                #if paths are found valid, flag should be made false to prevent further checking of this path for rest of the resources
                $response = [WebRequestHelper]::InvokePostWebRequest($pathurl, $body)
                [BugLogPathManager]::checkValidPathFlag = $false
                [BugLogPathManager]::isPathValid = $true;
                return $true;
		
            }
            catch {
                #if paths are not found valid, flag should be made false to prevent further checking of this path for rest of the resources and thus prevent bug logging for all resources
                Write-Host "`nCould not log bug. Verify that the area and iteration path are correct." -ForegroundColor Red
                [BugLogPathManager]::checkValidPathFlag = $false;
			
						
            }
		
        }
		

        return ([BugLogPathManager]::isPathValid)
    }

    #helper functions to obtain area and iteration paths and check if the path was valid

    static hidden [string] GetAreaPath(){
        return [BugLogPathManager]::AreaPath
    }
    static hidden [string] GetIterationPath(){
        return [BugLogPathManager]::IterationPath
    }
    static hidden [bool] GetIsPathValid(){
        return [BugLogPathManager]::isPathValid
    }
}