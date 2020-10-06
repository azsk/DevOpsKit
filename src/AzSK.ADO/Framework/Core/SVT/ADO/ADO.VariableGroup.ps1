Set-StrictMode -Version Latest 
class VariableGroup: ADOSVTBase
{    

    hidden [PSObject] $VarGrp;
    hidden [PSObject] $ProjectId;
    hidden [PSObject] $VarGrpId;
    
    VariableGroup([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        $this.ProjectId = ($this.ResourceContext.ResourceId -split "Project/")[-1].Split('/')[0];
        $this.VarGrpId = $this.ResourceContext.ResourceDetails.id
        $apiURL = "https://$($this.SubscriptionContext.SubscriptionName).visualstudio.com/$($this.ProjectId)/_apis/distributedtask/variablegroups/$($this.VarGrpId)"
        $this.VarGrp = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

    }
    hidden [ControlResult] CheckPipelineAccess([ControlResult] $controlResult)
    {
        $url = 'https://{0}.visualstudio.com/{1}/_apis/build/authorizedresources?type=variablegroup&id={2}&api-version=5.1-preview.1' -f $($this.SubscriptionContext.SubscriptionName),$($this.ProjectId) ,$($this.VarGrpId);
        try 
        {
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($url);
            # If var grp is not shared across all pipelines, 'count' property is available for $responseObj[0] and its value is 0. 
            # If var grp is shared across all pipelines, 'count' property is not available for $responseObj[0]. 
            #'Count' is a PSObject property and 'count' is response object property. Notice the case sensitivity here.
            
            # TODO: When there var grp is not shared across all pipelines, CheckMember in the below condition returns false when checknull flag [third param in CheckMember] is not specified (default value is $true). Assiging it $false. Need to revisit.
            if(([Helpers]::CheckMember($responseObj[0],"count",$false)) -and ($responseObj[0].count -eq 0))
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Variable group is not accessible to all pipelines.");
            }
             # When var grp is shared across all pipelines - the below condition will be true.
            elseif((-not ([Helpers]::CheckMember($responseObj[0],"count"))) -and ($responseObj.Count -gt 0) -and ([Helpers]::CheckMember($responseObj[0],"authorized"))) 
            {
                if($responseObj[0].authorized -eq $true)
                {
                    $controlResult.AddMessage([VerificationResult]::Failed, "Variable group is accessible to all pipelines.");
                }
                else
                {
                    $controlResult.AddMessage([VerificationResult]::Passed, "Variable group is not accessible to all pipelines.");
                }  
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch authorization details of variable group.");
            }   

        }
        catch 
        {   
            $controlResult.AddMessage([VerificationResult]::Error,"Could not fetch authorization details of variable group.");    
        }
        return $controlResult
    }
    hidden [ControlResult] CheckInheritedPermissions([ControlResult] $controlResult)
    {
        $url = 'https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.variablegroup/roleassignments/resources/{1}%24{2}?api-version=6.1-preview.1' -f $($this.SubscriptionContext.SubscriptionName),$($this.ProjectId) ,$($this.VarGrpId); 
        try 
        {
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($url);
            $inheritedRoles = $responseObj | Where-Object {$_.access -eq "inherited"}
            if(($inheritedRoles | Measure-Object).Count -gt 0)
            {
                $roles = @();
                $roles += ($inheritedRoles  | Select-Object -Property @{Name="Name"; Expression = {$_.identity.displayName}}, @{Name="Role"; Expression = {$_.role.displayName}});
                $controlResult.AddMessage([VerificationResult]::Failed,"Review the list of inherited role assignments on variable group: ", $roles);
                $controlResult.SetStateData("List of inherited role assignments on variable group: ", $roles);
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Passed,"No inherited role assignments found on variable group.")
            }

        }
        catch 
        {   
            $controlResult.AddMessage([VerificationResult]::Error,"Could not fetch permission details of variable group.");    
        }
        return $controlResult
    }
    hidden [ControlResult] CheckRBACAccess([ControlResult] $controlResult)
    {
        $url = 'https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.variablegroup/roleassignments/resources/{1}%24{2}?api-version=6.1-preview.1' -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $($this.VarGrpId); 
        try 
        {
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($url);
            if(($responseObj | Measure-Object).Count -gt 0)
            {
                $roles = @();
                $roles += ($responseObj  | Select-Object -Property @{Name="Name"; Expression = {$_.identity.displayName}}, @{Name="Role"; Expression = {$_.role.displayName}}, @{Name="AccessType"; Expression = {$_.access}});
                $controlResult.AddMessage([VerificationResult]::Verify,"Review the list of role assignments on variable group: ", $roles);
                $controlResult.SetStateData("List of role assignments on variable group: ", $roles);
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Passed,"No role assignments found on variable group.")
            }

        }
        catch 
        {   
            $controlResult.AddMessage([VerificationResult]::Error,"Could not fetch RBAC details of variable group.");    
        }
        return $controlResult
    }
    hidden [ControlResult] CheckCredInVarGrp([ControlResult] $controlResult)
	{
        if([Helpers]::CheckMember([ConfigurationManager]::GetAzSKSettings(),"SecretsScanToolFolder"))
        {
            $ToolFolderPath = [ConfigurationManager]::GetAzSKSettings().SecretsScanToolFolder
            $SecretsScanToolName = [ConfigurationManager]::GetAzSKSettings().SecretsScanToolName
            if((-not [string]::IsNullOrEmpty($ToolFolderPath)) -and (Test-Path $ToolFolderPath) -and (-not [string]::IsNullOrEmpty($SecretsScanToolName)))
            {
                $ToolPath = Get-ChildItem -Path $ToolFolderPath -File -Filter $SecretsScanToolName -Recurse 
                if($ToolPath)
                { 
                    if($this.VarGrp)
                    {
                        try
                        {
                            $varGrpDefFileName = $($this.ResourceContext.ResourceName).Replace(" ","")
                            $varGrpDefPath = [Constants]::AzSKTempFolderPath + "\VarGrps\"+ $varGrpDefFileName + "\";
                            if(-not (Test-Path -Path $varGrpDefPath))
                            {
                                New-Item -ItemType Directory -Path $varGrpDefPath -Force | Out-Null
                            }

                            $this.VarGrp | ConvertTo-Json -Depth 5 | Out-File "$varGrpDefPath\$varGrpDefFileName.json"
                            $searcherPath = Get-ChildItem -Path $($ToolPath.Directory.FullName) -Include "buildsearchers.xml" -Recurse
                            ."$($Toolpath.FullName)" -I $varGrpDefPath -S "$($searcherPath.FullName)" -f csv -Ve 1 -O "$varGrpDefPath\Scan"    
                            
                            $scanResultPath = Get-ChildItem -Path $varGrpDefPath -File -Include "*.csv"
                            
                            if($scanResultPath -and (Test-Path $scanResultPath.FullName))
                            {
                                $credList = Get-Content -Path $scanResultPath.FullName | ConvertFrom-Csv 
                                if(($credList | Measure-Object).Count -gt 0)
                                {
                                    $controlResult.AddMessage("No. of credentials found:" + ($credList | Measure-Object).Count )
                                    $controlResult.AddMessage([VerificationResult]::Failed,"Found credentials in variables.")
                                }
                                else {
                                    $controlResult.AddMessage([VerificationResult]::Passed,"No credentials found in variables.")
                                }
                            }
                        }
                        catch 
                        {
                            #Publish Exception
                            $this.PublishException($_);
                        }
                        finally
                        {
                            #Clean temp folders 
                            Remove-ITem -Path $varGrpDefPath -Recurse
                        }
                    }
                }
            }
        }
        else {
            try {      
                if([Helpers]::CheckMember($this.VarGrp[0],"variables")) 
                {
                    $varList = @();
                    $noOfCredFound = 0;     
                    $patterns = $this.ControlSettings.Patterns | where {$_.RegexCode -eq "SecretsInBuild"} | Select-Object -Property RegexList;
                    $exclusions = $this.ControlSettings.Build.ExcludeFromSecretsCheck;
                    if(($patterns | Measure-Object).Count -gt 0)
                    {                
                        Get-Member -InputObject $this.VarGrp[0].variables -MemberType Properties | ForEach-Object {
                            if([Helpers]::CheckMember($this.VarGrp[0].variables.$($_.Name),"value") -and  (-not [Helpers]::CheckMember($this.VarGrp[0].variables.$($_.Name),"isSecret")))
                            {
                                
                                $varName = $_.Name
                                $varValue = $this.VarGrp[0].variables.$varName.value 
                                <# helper code to build a list of vars and counts
                                if ([Build]::BuildVarNames.Keys -contains $buildVarName)
                                {
                                        [Build]::BuildVarNames.$buildVarName++
                                }
                                else 
                                {
                                    [Build]::BuildVarNames.$buildVarName = 1
                                }
                                #>
                                if ($exclusions -notcontains $varName)
                                {
                                    for ($i = 0; $i -lt $patterns.RegexList.Count; $i++) {
                                        #Note: We are using '-cmatch' here. 
                                        #When we compile the regex, we don't specify ignoreCase flag.
                                        #If regex is in text form, the match will be case-sensitive.
                                        if ($varValue -cmatch $patterns.RegexList[$i]) { 
                                            $noOfCredFound +=1
                                            $varList += " $varName";   
                                            break  
                                            }
                                        }
                                }
                            } 
                        }
                        if($noOfCredFound -gt 0)
                        {
                            $varList = $varList | select -Unique
                            $controlResult.AddMessage([VerificationResult]::Failed, "Found secrets in variable group. Variables name: $varList" );
                            $controlResult.SetStateData("List of variable name containing secret: ", $varList);
                        }
                        else 
                        {
                            $controlResult.AddMessage([VerificationResult]::Passed, "No credentials found in variable group.");
                        }
                        $patterns = $null;
                    }
                    else 
                    {
                        $controlResult.AddMessage([VerificationResult]::Manual, "Regular expressions for detecting credentials in variable groups are not defined in your organization.");    
                    }
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Passed, "No variables found in variable group.");
                }
            }
            catch {
                $controlResult.AddMessage([VerificationResult]::Manual, "Could not fetch the variable group definition.");
                $controlResult.AddMessage($_);
            }    
        } 
        return $controlResult;
    }

}
