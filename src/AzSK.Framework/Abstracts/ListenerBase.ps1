Set-StrictMode -Version Latest
class ListenerBase: EventBase
{
    [array] $RegisteredEvents = @();
    static [string] $isAIKeyEnabled =$null
    
    ListenerBase()
    {   
        [Helpers]::AbstractClass($this, [ListenerBase]);
    }

    [void] SetRunIdentifier([AzSKRootEventArgument] $arguments)
    {
        $data = $arguments.Messages | Select-Object -First 1
        if ($data) {
            $this.RunIdentifier = $data.Message;  
			
			# Sending Invocation context in DataObject while firing RunIdentifier event
			if($data.DataObject)
			{
				$this.InvocationContext = $data.DataObject;
			}
        }
    } 

    [void] UnregisterEvents()
    {
        $this.RegisteredEvents | Sort-Object -Descending | 
		ForEach-Object {
            try{
            Unregister-Event -SubscriptionId $_ -Force -ErrorAction SilentlyContinue
            Remove-Job -Id $_ -Force -ErrorAction SilentlyContinue 
            }
            Catch{
                #Keeping exception blank to continue execution flow 
            }
        }

        $this.RegisteredEvents = @();
    }

    [void] RegisterEvent([string] $sourceIdentifier, [ScriptBlock] $action)
    {
        $this.RegisteredEvents += (Register-EngineEvent -SourceIdentifier $sourceIdentifier -Action $action).Id;
    }

    [void] HandleException([ScriptBlock] $script, [System.Management.Automation.PSEventArgs] $event)
    {
        try 
        {
            & $script $event $this
        }
        catch 
        {
             $this.PublishException($_);
        }
    }
    
    [void] PushAIEvents([String] $Eventname)
    {
        if ([String]::IsNullOrEmpty([ListenerBase]::isAIKeyEnabled))
        {
            [ListenerBase]::isAIKeyEnabled = [RemoteReportHelper]::IsAIOrgTelemetryEnabled()
        }
        if([ListenerBase]::isAIKeyEnabled -eq $true)
        {
            $iKey = [RemoteReportHelper]::GetAIOrgTelemetryKey()

            $customPropertiesObj =  @{ 
                'CalledBy'= $Eventname; 
                'RunIdentifier' =$this.runidentifier ;
                'Command' = $this.InvocationContext.InvocationName ;
            }
            $bodyObject = [PSCustomObject]@{
                'name' = "Microsoft.ApplicationInsights.$iKey.Event"
                'time' = ([System.dateTime]::UtcNow.ToString('o'))
                'iKey' = $iKey
                'tags' = [PSCustomObject]@{
                    'ai.internal.sdkVersion' = 'dotnet: 2.1.0.26048'
                }
                'data' = [PSCustomObject]@{
                    'baseType' = 'EventData'
                    'baseData' = [PSCustomObject]@{
                        'ver' = '2'
                        'name' = "ADOScanner additional telemetry"
                        'properties' = $customPropertiesObj
                    }
                }
            }
            
            $bodyAsCompressedJson = $bodyObject | ConvertTo-JSON -Depth 10 -Compress
            $headers = @{
                'Content-Type' = 'application/x-json-stream';
            }
            Invoke-RestMethod -Uri "https://dc.services.visualstudio.com/v2/track" -Method Post -Headers $headers -Body $bodyAsCompressedJson
        }
    }
    
}


