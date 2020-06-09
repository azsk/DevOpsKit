Set-StrictMode -Version Latest 
#Listner to write CA scan status on completion of resource scan 
class PartialScanHandler: ListenerBase
{
    hidden static [PartialScanHandler] $Instance = $null;
    static [PartialScanHandler] GetInstance()
    {
        if ( $null -eq  [PartialScanHandler]::Instance)
        {
            [PartialScanHandler]::Instance = [PartialScanHandler]::new();
        }    
        return [PartialScanHandler]::Instance
    }


	[void] RegisterEvents()
    {
        $this.UnregisterEvents();       

        $this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
            $currentInstance = [PartialScanHandler]::GetInstance();
            try 
            {
                $currentInstance.SetRunIdentifier([AzSKRootEventArgument] ($Event.SourceArgs | Select-Object -First 1));                         
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

		$this.RegisterEvent([SVTEvent]::EvaluationCompleted, {
            $currentInstance = [PartialScanHandler]::GetInstance();
            try 
            {
				$props = $Event.SourceArgs[0];
				if($props)
				{
					if($props.IsResource())
					{
						#if Use partial commit is ON. Update scan tracker with resource completion status.
						if ($currentInstance.InvocationContext.BoundParameters["UsePartialCommits"] )
						{
                            [PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
							$partialScanMngr.UpdateResourceStatus( $props.ResourceContext.ResourceId,"COMP");
						}
					}					
				}            
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

        $this.RegisterEvent([SVTEvent]::CommandStarted, {
           $currentInstance = [PartialScanHandler]::GetInstance();
       });

		 $this.RegisterEvent([SVTEvent]::CommandCompleted, {
            $currentInstance = [PartialScanManager]::GetInstance();
            try 
            {
				$currentInstance = [PartialScanHandler]::GetInstance();
				$scanSource = [AzSKSettings]::GetInstance().GetScanSource();
				[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
				#$baselineControlsDetails = $partialScanMngr.GetBaselineControlDetails()
				#If Scan source is in supported sources or UsePartialCommits switch is available
				#if ($currentInstance.InvocationContext.BoundParameters["UsePartialCommits"] -or ($baselineControlsDetails.SupportedSources -contains $scanSource))
            if ($currentInstance.InvocationContext.BoundParameters["UsePartialCommits"])
				{
					$partialScanMngr.RemovePartialScanData();   
				}
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

        $this.RegisterEvent([AzSKRootEvent]::PublishCustomData, {
            $currentInstance = [PartialScanHandler]::GetInstance();
            try
            {	
                $CustomDataObj =  $Event.SourceArgs
                $CustomObjectData=$CustomDataObj| Select-Object -exp Messages| Select-Object -exp DataObject
            }
            catch
            {
                $currentInstance.PublishException($_);
            }
        });
	}


}
