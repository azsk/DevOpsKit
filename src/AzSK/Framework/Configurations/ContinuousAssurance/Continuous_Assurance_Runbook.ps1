$AzSKRunbookVersion = "[#runbookVersion#]"

#Telemetry functions -- start here
function SetCommonProperties([psobject] $EventObj) {
    $notAvailable = "NA"
    $eventObj.data.baseData.properties.Add("JobId",$PsPrivateMetaData.JobId.Guid)
	$eventObj.data.baseData.properties.Add("SubscriptionId",$RunAsConnection.SubscriptionID)
	$eventObj.data.baseData.properties.Add("AzSKRunbookVersion", $AzSKRunbookVersion)
}

function GetEventBaseObject([string] $EventName) {
    $eventObj = "" | Select-Object data, iKey, name, tags, time
    $eventObj.iKey = $telemetryKey
    $eventObj.name = "Microsoft.ApplicationInsights." + $telemetryKey.Replace("-", "") + ".Event"
    $eventObj.time = [datetime]::UtcNow.ToString("o")

    $eventObj.tags = "" | Select-Object ai.internal.sdkVersion
    $eventObj.tags.'ai.internal.sdkVersion' = "dotnet: 2.1.0.26048"

    $eventObj.data = "" | Select-Object baseData, baseType
    $eventObj.data.baseType = "EventData"
    $eventObj.data.baseData = "" | Select-Object ver, name, measurements, properties

    $eventObj.data.baseData.ver = 2
    $eventObj.data.baseData.name = $EventName

    $eventObj.data.baseData.measurements = New-Object 'system.collections.generic.dictionary[string,double]'
    $eventObj.data.baseData.properties = New-Object 'system.collections.generic.dictionary[string,string]'

    return $eventObj;
}

function PublishEvent([string] $EventName, [hashtable] $Properties, [hashtable] $Metrics) {
    try {
		#return if telemetry key is empty
        if ([string]::IsNullOrWhiteSpace($telemetryKey)) { return; };

        $eventObj = GetEventBaseObject -EventName $EventName
        SetCommonProperties -EventObj $eventObj

        if ($null -ne $Properties) {
            $Properties.Keys | ForEach-Object {
                try {
                    if (!$eventObj.data.baseData.properties.ContainsKey($_)) {
                        $eventObj.data.baseData.properties.Add($_ , $Properties[$_].ToString())
                    }
                }
                catch
				{
					# Left blank intentionally
					# Error while sending CA events to telemetry. No need to break the execution.
				}
            }
        }
        if ($null -ne $Metrics) {
            $Metrics.Keys | ForEach-Object {
                try {
                    $metric = $Metrics[$_] -as [double]
                    if (!$eventObj.data.baseData.measurements.ContainsKey($_) -and $null -ne $metric) {
                        $eventObj.data.baseData.measurements.Add($_ , $Metrics[$_])
                    }
                }
                catch {
					# Left blank intentionally
					# Error while sending CA events to telemetry. No need to break the execution.
				}
            }
        }

        $eventJson = ConvertTo-Json $eventObj -Depth 100 -Compress

        Invoke-WebRequest -Uri "https://dc.services.visualstudio.com/v2/track" `
            -Method Post `
            -ContentType "application/x-json-stream" `
            -Body $eventJson `
            -UseBasicParsing | Out-Null
    }
    catch {
		# Left blank intentionally
		# Error while sending CA events to telemetry. No need to break the execution.
    }
}
#Telemetry functions -- end here

#function to create one time temporary helper schedule
function CreateHelperSchedule($nextRetryIntervalInMinutes)
{
    #create next run schedule
    Get-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName `
    -ResourceGroupName $AutomationAccountRG -Name $CAHelperScheduleName -ErrorAction SilentlyContinue | Remove-AzureRmAutomationSchedule -Force

    New-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $CAHelperScheduleName `
                    -ResourceGroupName $AutomationAccountRG -StartTime $(get-date).AddMinutes($nextRetryIntervalInMinutes) `
                    -OneTime -ErrorAction Stop | Out-Null

    Register-AzureRmAutomationScheduledRunbook -RunbookName $RunbookName -ScheduleName $CAHelperScheduleName `
                    -ResourceGroupName $AutomationAccountRG `
                    -AutomationAccountName $AutomationAccountName -ErrorAction Stop | Out-Null
	PublishEvent -EventName "CA Job Rescheduled" -Properties @{"IntervalInMinutes" = $nextRetryIntervalInMinutes}
}
#function to invoke script from server
function InvokeScript($accessToken, $policyStoreURL,$fileName, $version)
{
    [System.Uri] $validatedURI = $null;
    $URI = $global:ExecutionContext.InvokeCommand.ExpandString($policyStoreURL)
	$result = "Write-Host 'Error connecting to AzSK policy store server.'"
    if([System.Uri]::TryCreate($URI, [System.UriKind]::Absolute, [ref] $validatedURI))
    {
        if($accessToken)
        {
			$retry = 3
			while($retry -gt 0)
			{
				$retry = $retry - 1
				$result = Invoke-WebRequest $validatedUri -Headers @{"Authorization" = "Bearer $accessToken"} -UseBasicParsing
				 if ($null -ne $result -and $result.StatusCode -ge 200 -and $result.StatusCode -le 399) {
					$retry = -1;
				}
			}

        }
        else
        {
			$retry = 3
			while($retry -gt 0)
			{
				$retry = $retry - 1
				$result = Invoke-WebRequest $validatedUri -UseBasicParsing
				if ($null -ne $result -and $result.StatusCode -ge 200 -and $result.StatusCode -le 399) {
					$retry = -1;
				}
			}
        }
		Invoke-Expression $result;
    }
}

function ConvertStringToBoolean($strToConvert)
{
	switch($strToConvert)
	{
		"true" {return $true}
		"false" {return $false}
	}
	return $false #adding this to prevent error all path doesn't return value"
}

try
{
	#start job timer
	$jobTimer = [System.Diagnostics.Stopwatch]::StartNew();

	#----------------------------------Config start------------------------------------------------------------------
	$automationAccountRG =  "[#automationAccountRG#]"
	$automationAccountName="[#automationAccountName#]"
	$telemetryKey ="[#telemetryKey#]"
	$onlinePolicyStoreUrl = "[#onlinePolicyStoreUrl#]"
	$OSSPolicyStoreUrl = "[#OSSPolicyStoreUrl#]"
	$enableAADAuthForOnlinePolicyStore = "[#enableAADAuthForOnlinePolicyStore#]"
	$runbookCoreSetupScript = "RunbookCoreSetup.ps1"
	$runbookScanAgentScript = "RunbookScanAgent.ps1"
	$RunbookName = "Continuous_Assurance_Runbook"
	$CAHelperScheduleName = "CA_Helper_Schedule"
	$UpdateToLatestVersion = "[#UpdateToLatestVersion#]"	
	$azureRmResourceURI = "https://management.core.windows.net/"
	$RunAsConnection = Get-AutomationConnection -Name "AzureRunAsConnection"

	#-----------------------------------Config end-------------------------------------------------------------------------

	#-----------------------------------Telemetry script-------------------------------------------------------------------
	PublishEvent -EventName "CA Job Started" -Properties @{
	"OnlinePolicyStoreUrl"=$OnlinePolicyStoreUrl; `
    "AzureADAppId"=$RunAsConnection.ApplicationId
	}

	#------------------------------------Execute RunbookCoreSetup.ps1 to download required modules-------------------------
	#Login
	if(!$RunAsConnection)
	{
		throw "Cannot login to Azure from AzSK CA runbook. Connection info for AzureRunAsConnection not found."
	}
	try
	{
		"Logging in to Azure..."
		Add-AzureRmAccount `
			-ServicePrincipal `
			-TenantId $RunAsConnection.TenantId `
			-ApplicationId $RunAsConnection.ApplicationId `
			-CertificateThumbprint $RunAsConnection.CertificateThumbprint | Out-Null

		Set-AzureRmContext -SubscriptionId $RunAsConnection.SubscriptionID  | Out-Null
	}
	catch
	{
		Write-Output ("Failed to login to Azure with AzSK CA Runtime account.")
		throw $_.Exception
	}

	#create helper schedule to run job again after 30 minutes in case online policy URL is down

    "Validating installed AzSK version..."
	#Step 1: Get module version from installed AzSK module
	$module = Get-AzureRmAutomationModule -ResourceGroupName $AutomationAccountRG `
			-AutomationAccountName $AutomationAccountName | `
			Where-Object { $_.Name -like "azsk*"}

	$moduleVersion = "1.0.0"
	$UpdateToLatestVersion = ConvertStringToBoolean($UpdateToLatestVersion)

	PublishEvent -EventName "CA Job Invoke Setup Started"
	Write-Output ("Starting invocation: policyStoreURL=$OSSPolicyStoreUrl")
	InvokeScript -policyStoreURL $OSSPolicyStoreUrl -fileName $runbookCoreSetupScript -version $moduleVersion
	Write-Output ("Completed runbook setup script.")
	PublishEvent -EventName "CA Job Invoke Setup Completed"

	#------------------------------------Execute RunbookScanAgent.ps1 to scan subscription and resources-------------------
	if((Get-Command -Name "Get-AzSKAccessToken" -ErrorAction SilentlyContinue|Measure-Object).Count -gt 0)
	{
		if($enableAADAuthForOnlinePolicyStore -eq "true")
		{
			$accessToken = Get-AzSKAccessToken -ResourceAppIdURI $azureRmResourceURI
		}
		PublishEvent -EventName "CA Job Invoke Scan Started"
		Write-Output ("Starting invocation: policyStoreURL=$onlinePolicyStoreUrl")
		Write-Output ("Starting CA scan...")
		InvokeScript -accessToken $accessToken -policyStoreURL $onlinePolicyStoreUrl -fileName $runbookScanAgentScript -version $moduleVersion
		Write-Output ("CA scan completed.")
		PublishEvent -EventName "CA Job Invoke Scan Completed"
	}
	else
	{
		Write-Output("Not triggering a scan. AzSK module not yet ready in the account.")
	}
	Write-Output ("CA job completed.")
	PublishEvent -EventName "CA Job Completed" -Metrics @{
	"TimeTakenInMs" = $jobTimer.ElapsedMilliseconds; `
	"SuccessCount" = 1
	}
}
catch
{
	Write-Output ("Exception happened in runbook...")
	$_
	PublishEvent -EventName "CA Job Error" -Properties @{ "ErrorRecord" = ($_ | Out-String) } -Metrics @{"TimeTakenInMs" =$jobTimer.ElapsedMilliseconds; "SuccessCount" = 0}
	throw;
}
#----------------------------------Runbook end-------------------------------------------------------------------------
