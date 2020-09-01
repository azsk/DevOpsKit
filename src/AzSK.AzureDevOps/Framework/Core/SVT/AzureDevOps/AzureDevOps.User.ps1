Set-StrictMode -Version Latest 
class User: ADOSVTBase {    

    User([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId, $svtResource) {

    }

    hidden [ControlResult] CheckPATAccessLevel([ControlResult] $controlResult) {
        $apiURL = "https://{0}.vssps.visualstudio.com/_apis/Token/SessionTokens?displayFilterOption=1&createdByOption=3&sortByOption=3&isSortAscending=false&startRowNumber=1&pageSize=100&api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
        $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);
        $controlResult.AddMessage("Currently this control evaluates PATs for all the organizations the user has access to.")
        try {
            if ($responseObj.Count -gt 0) {
                $AccessPATList = $responseObj | Where-Object { $_.validto -gt $(Get-Date -Format "yyyy-MM-dd") }
                if ($AccessPATList.Count -gt 0) {
                    $fullAccessPATList = $AccessPATList | Where-Object { $_.scope -eq "app_token" }
                    if (($fullAccessPATList | Measure-Object).Count -gt 0) {
                        $fullAccessPATNames = $fullAccessPATList | Select displayName, scope 
                        $controlResult.AddMessage([VerificationResult]::Failed,
                            "The following PATs have been configured with full access : ", $fullAccessPATNames);
                    }
                    else {
                        $AccessPATNames = $responseObj | Select displayName, scope 
                        $controlResult.AddMessage([VerificationResult]::Verify,
                            "Verify that the following PATs have minimum required permissions : ", $AccessPATNames)   
                    }
                }
                else {
                    $controlResult.AddMessage([VerificationResult]::Passed,
                        "No active PATs found");
                }
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,
                    "No PATs found");
            }
                    
        }
        catch {
            $controlResult.AddMessage([VerificationResult]::Error,
                "Could not fetch the list of PATs");
        }
        
        return $controlResult;
    }

    hidden [ControlResult] CheckAltCred([ControlResult] $controlResult) {

        $apiURL = "https://{0}.visualstudio.com/_apis/Contribution/dataProviders/query?api-version=5.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
        $inputbody = '{"contributionIds": ["ms.vss-admin-web.alternate-credentials-data-provider","ms.vss-admin-web.action-url-data-provider"]}' | ConvertFrom-Json
        $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL, $inputbody);

        if ([Helpers]::CheckMember($responseObj, "data"), $responseObj.data.'ms.vss-admin-web.alternate-credentials-data-provider') {
            if ((-not $responseObj.data.'ms.vss-admin-web.alternate-credentials-data-provider'.alternateCredentialsModel.basicAuthenticationDisabled) -or (-not $responseObj.data.'ms.vss-admin-web.alternate-credentials-data-provider'.alternateCredentialsModel.basicAuthenticationDisabledOnAccount)) {
                $controlResult.AddMessage([VerificationResult]::Passed,
                    "Alt credential is disabled");
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,
                    "Alt credential is enabled");
            }
        }
        else {
            $controlResult.AddMessage([VerificationResult]::Manual,
                "Alt credential not found");
        }
        return $controlResult
    }

    hidden [ControlResult] ValidatePATExpiryPeriod([ControlResult] $controlResult) {
        $controlResult.AddMessage("Currently this control evaluates PATs for all the organizations the user has access to.")  
        try {

            $apiURL = "https://{0}.vssps.visualstudio.com/_apis/Token/SessionTokens?displayFilterOption=1&createdByOption=3&sortByOption=3&isSortAscending=false&startRowNumber=1&pageSize=100&api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

            if ($responseObj.Count -gt 0) { 
                $AccessPATList = $responseObj | Where-Object { $_.validto -gt $(Get-Date -Format "yyyy-MM-dd") }
           
                if (($AccessPATList | Measure-Object).Count -gt 0) {
                    $res = $AccessPATList | Where-Object {(New-Timespan -Start $_.ValidFrom -End $_.ValidTo).Days -gt 180 }
                
                    if (($res | Measure-Object).Count -gt 0) {
                        $PATList = ($res | Select-Object -Property @{Name = "Name"; Expression = { $_.displayName } }, @{Name = "ValidFrom"; Expression = { $_.validfrom } }, @{Name = "ValidTo"; Expression = { $_.validto } }, @{Name = "ValidationPeriod"; Expression = { ([datetime]::parseexact($_.validto.Split('T')[0], 'yyyy-MM-dd', $null) - [datetime]::parseexact($_.validfrom.Split('T')[0], 'yyyy-MM-dd', $null)).Days } });    
                        $controlResult.AddMessage([VerificationResult]::Failed, "The following PATs have validity period of more than 180 days : ", $PATList)  
                    }
                    else {
                        $controlResult.AddMessage([VerificationResult]::Passed,
                            "No PATs have been found with validity period of more than 180 days.") 
                    }
                }
                else {
                    $controlResult.AddMessage([VerificationResult]::Passed,
                        "No active PATs have been found.")  
                }
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,
                    "No PATs have been found.");
            }
        }
        catch {
            $controlResult.AddMessage([VerificationResult]::Error,
                "Could not fetch the list of PATs.");
        }
        
        return $controlResult;
    }
    hidden [ControlResult] CheckPATExpiration([ControlResult] $controlResult) {
        $controlResult.AddMessage("Currently this control evaluates PATs for all the organizations the user has access to.")
        try {

            $apiURL = "https://{0}.vssps.visualstudio.com/_apis/Token/SessionTokens?displayFilterOption=1&createdByOption=3&sortByOption=3&isSortAscending=false&startRowNumber=1&pageSize=100&api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

            if ($responseObj.Count -gt 0) { 
                $date = Get-Date;
                $AccessPATList = $responseObj | Where-Object { $_.validto -gt $(Get-Date -Format "yyyy-MM-dd") }
           
                if (($AccessPATList | Measure-Object).Count -gt 0) {
                    $PATExpri7Days = $AccessPATList | Where-Object { (New-Timespan -Start $date -End $_.validto ).Days  -lt 8 };
                    $PATExpri30Days = $AccessPATList | Where-Object { ((New-Timespan -Start $date -End $_.validto).Days -gt 7) -and ((New-Timespan -Start $date -End $_.validto).Days -lt 31) };
                    $PATOther = $AccessPATList | Where-Object { ((New-Timespan -Start $date -End $_.validto).Days -gt 30) };

                    if (($PATExpri7Days | Measure-Object).Count -gt 0) {
                        $PAT7List = ($PATExpri7Days | Select-Object -Property @{Name = "Name"; Expression = { $_.displayName } }, @{Name = "ValidFrom"; Expression = { $_.validfrom } }, @{Name = "ValidTo"; Expression = { $_.validto } }, @{Name = "Remaining"; Expression = { (New-Timespan -Start $date -End $_.validto).Days } });    
                        $controlResult.AddMessage("The following PATs expire within 7 days : ", $PAT7List )
                    }
                    if (($PATExpri30Days | Measure-Object).Count -gt 0) {
                        $PAT30List = ($PATExpri30Days | Select-Object -Property @{Name = "Name"; Expression = { $_.displayName } }, @{Name = "ValidFrom"; Expression = { $_.validfrom } }, @{Name = "ValidTo"; Expression = { $_.validto } }, @{Name = "Remaining"; Expression = { (New-Timespan -Start $date -End $_.validto).Days } });    
                        $controlResult.AddMessage("The following PATs expire after 7 days but within 30 days : ", $PAT30List )
                    }
              
                    if (($PATOther | Measure-Object).Count -gt 0) {
                        $PATOList = ($PATOther | Select-Object -Property @{Name = "Name"; Expression = { $_.displayName } }, @{Name = "ValidFrom"; Expression = { $_.validfrom } }, @{Name = "ValidTo"; Expression = { $_.validto } }, @{Name = "Remaining"; Expression = { (New-Timespan -Start $date -End $_.validto).Days } });    
                        $controlResult.AddMessage("The following PATs expire after 30 days : ", $PATOList )
                    }
                    if (($PATExpri7Days | Measure-Object).Count -gt 0) {
                        $controlResult.AddMessage([VerificationResult]::Failed)
                    }
                    elseif (($PATExpri30Days | Measure-Object).Count -gt 0) {
                        $controlResult.AddMessage([VerificationResult]::Verify)
                    }
                    else {
                        $controlResult.AddMessage([VerificationResult]::Passed, "No PATs have been found which expire within 30 days")
                    }
                }
                else {
                    $controlResult.AddMessage([VerificationResult]::Passed,
                        "No active PATs have been found.")  
                }
            }
            else {
                $controlResult.AddMessage([VerificationResult]::Passed,
                    "No PATs have been found.");
            }
        }
        catch {
            $controlResult.AddMessage([VerificationResult]::Error,
                "Could not fetch the list of PATs.");
        }
        
        return $controlResult;
    }

}