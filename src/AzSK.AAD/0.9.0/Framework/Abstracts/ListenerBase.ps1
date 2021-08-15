﻿Set-StrictMode -Version Latest
class ListenerBase: EventBase
{
    [array] $RegisteredEvents = @();
    
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
        $unreg = 0
        $this.RegisteredEvents | Sort-Object -Descending | 
		ForEach-Object {
            try{
            Unregister-Event -SubscriptionId $_ -Force -ErrorAction SilentlyContinue
            Remove-Job -Id $_ -Force -ErrorAction SilentlyContinue 
            $unreg++
            }
            Catch{
                #Keeping exception blank to continue execution flow 
            }
        }
        if ([EventBase]::logLvl -ge 2) {Write-Host -ForegroundColor Yellow "Unregistered all [$unreg] events for classs: $($this.GetType())" }
        $this.RegisteredEvents = @();
    }

    [void] RegisterEvent([string] $sourceIdentifier, [ScriptBlock] $action)
    {
        $this.RegisteredEvents += (Register-EngineEvent -SourceIdentifier $sourceIdentifier -Action $action).Id;
        $eid = $this.RegisteredEvents[$this.RegisteredEvents.Count-1]
        if ([EventBase]::logLvl -ge 2) { Write-Host -ForegroundColor Green "RegEvt: [$eid] Type: $($this.GetType()) SrcId: $sourceIdentifier" }
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
}


