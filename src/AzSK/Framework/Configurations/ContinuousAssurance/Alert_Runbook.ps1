Param(
    [object]$WebHookData
)


$telemetryKey ="[#telemetryKey#]"
#Telemetry functions -- start here
function SetCommonProperties([psobject] $EventObj) {
    $notAvailable = "NA"

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
					# Left blank intentionally.
					# Error while sending alert event to telemetry. No need to break the execution.
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
					# Left blank intentionally.
					# Error while sending alert event to telemetry. No need to break the execution.
				}
            }
        }

        $eventJson = ConvertTo-Json $eventObj -Depth 100 -Compress
        $eventObj
        Invoke-WebRequest -Uri "https://dc.services.visualstudio.com/v2/track" `
            -Method Post `
            -ContentType "application/x-json-stream" `
            -Body $eventJson `
            -UseBasicParsing | Out-Null
    }
    catch {
		# Left blank intentionally.
		# Error while sending alert event to telemetry. No need to break the execution.
    }
}

if($null -ne $WebHookData)
{
   #Getting required properties of WebhookData.
    $EventName="ActivityAlertLog"
    $WebhookName    =   $WebhookData.WebhookName
    $WebhookBody    =   $WebhookData.RequestBody
    $WebhookHeaders =   $WebhookData.RequestHeader
 try
  {	
   # Obtain the WebhookBody containing the AlertContext
    $WebhookBody = (ConvertFrom-Json -InputObject $WebhookBody)
    Write-Output "`nWEBHOOK BODY"
    Write-Output "============="
    Write-Output $WebhookBody

     # Obtain the AlertContext
    $AlertContext = [object]$WebhookBody.data.context
    $AlertContext 

     # Some selected AlertContext information
    Write-Output "`nALERT CONTEXT DATA"
    Write-Output "==================="
    Write-Output $alertcontext.activityLog.eventSource
    Write-Output $alertcontext.activityLog.subscriptionId
    Write-Output $alertcontext.activityLog.resourceGroupName
    Write-Output $alertcontext.activityLog.operationName
    Write-Output $alertcontext.activityLog.resourceType
    Write-Output $alertcontext.activityLog.resourceId
    Write-Output $alertcontext.activityLog.eventTimestamp


    PublishEvent -EventName $EventName  -Properties @{
	"subscriptionID"=$alertcontext.activityLog.subscriptionId;`
    "rescourceID"=$alertcontext.activityLog.resourceId;`
    "eventTimeStamp"=$alertcontext.activityLog.eventTimestamp;`
	"operationName"=$alertcontext.activityLog.operationName;`
	"caller"=$alertcontext.activityLog.caller;`
	"correlationId"=$alertcontext.activityLog.correlationId;`
	"eventSource"=$alertcontext.activityLog.eventSource;`
	"eventDataId"=$alertcontext.activityLog.eventDataId;`
	"level"=$alertcontext.activityLog.level;`
	"operationId"=$alertcontext.activityLog.operationId;`
	"resourceGroupName"=$alertcontext.activityLog.resourceGroupName;`
	"resourceProviderName"=$alertcontext.activityLog.resourceProviderName;`
	"status"=$alertcontext.activityLog.status;`
	"submissionTimestamp"=$alertcontext.activityLog.submissionTimestamp;`
	"resourceType"=$alertcontext.activityLog.resourceType
	}
   }
   catch
   {
     
     PublishEvent -EventName "ActivityAlertLog Error" -Properties @{ "ErrorRecord" = ($_ | Out-String) }
   }  
}
else
{
  Write-Error "Runbook called without webhook data." 
} 