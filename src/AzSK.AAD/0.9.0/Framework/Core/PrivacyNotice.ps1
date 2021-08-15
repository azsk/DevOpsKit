Set-StrictMode -Version Latest
class PrivacyNotice {
    static [void] ValidatePrivacyAcceptance()
	{
        $appSettings = [ConfigurationManager]::GetLocalAzSKSettings();		
		$source = "SDL"		

		if(-not $appSettings.PrivacyNoticeAccepted)
		{
			$azskConfig = [ConfigurationManager]::GetAzSKConfigData();
			if(-not [string]::IsNullOrWhiteSpace($appSettings.OMSSource))
			{
				$source = $appSettings.OMSSource;
			}
			if(($azskConfig.PrivacyAcceptedSources | Measure-Object).Count -gt 0 -and ($azskConfig.PrivacyAcceptedSources -contains $source))
			{
				$appSettings.PrivacyNoticeAccepted = $true
                $appSettings.UsageTelemetryLevel = "Anonymous"
				[ConfigurationManager]::UpdateAzSKSettings($appSettings)
				return;
			}
			Write-Host " `nAzSK: EULA and Privacy Disclosure: `nPlease review the following:`n`tEULA (http://aka.ms/azskeula)`n`tPrivacy Disclosure (http://aka.ms/azskpd)`n" -ForegroundColor Yellow;
            $input = ""
            while ($input -ne "y" -and $input -ne "n") {
                if (-not [string]::IsNullOrEmpty($input)) {
                    Write-Host "Please select an appropriate option.`n"
                }
                $input = Read-Host "Enter 'Y' if you agree and 'N' if you don't (Y/N)"
                $input = $input.Trim()
				Write-Host "`n"
            }
			if ($input -eq "y") {
                $appSettings.PrivacyNoticeAccepted = $true
                $appSettings.UsageTelemetryLevel = "Anonymous"
            }
			if ($input -eq "n") {
				$result = $false
				$appSettings.PrivacyNoticeAccepted = $false
				$appSettings.UsageTelemetryLevel = "None"
				throw ([SuppressedException]::new(("We are sorry to see you go!"), [SuppressedExceptionType]::Generic))
			}
            Write-Host "Your response has been recorded.`n" -ForegroundColor Green
			[ConfigurationManager]::UpdateAzSKSettings($appSettings)
		}		
    }
}
