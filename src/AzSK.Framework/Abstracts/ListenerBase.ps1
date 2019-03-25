Set-StrictMode -Version Latest
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
}


