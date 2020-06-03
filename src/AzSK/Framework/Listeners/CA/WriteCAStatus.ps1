Set-StrictMode -Version Latest 
#Listner to write CA scan status on completion of resource scan 
class WriteCAStatus: ListenerBase
{
    hidden static [WriteCAStatus] $Instance = $null;
    static [WriteCAStatus] GetInstance()
    {
        if ( $null -eq  [WriteCAStatus]::Instance)
        {
            [WriteCAStatus]::Instance = [WriteCAStatus]::new();
        }    
        return [WriteCAStatus]::Instance
    }


	[void] RegisterEvents()
    {
        $this.UnregisterEvents();       

        $this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
            $currentInstance = [WriteCAStatus]::GetInstance();
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
            $currentInstance = [WriteCAStatus]::GetInstance();
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
           $currentInstance = [WriteCAStatus]::GetInstance();
       });

		 $this.RegisterEvent([SVTEvent]::CommandCompleted, {
            $currentInstance = [PartialScanManager]::GetInstance();
            try 
            {
				$currentInstance = [WriteCAStatus]::GetInstance();
				$scanSource = [AzSKSettings]::GetInstance().GetScanSource();
				[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
				$baselineControlsDetails = $partialScanMngr.GetBaselineControlDetails()
				#If Scan source is in supported sources or UsePartialCommits switch is available
				if ($currentInstance.InvocationContext.BoundParameters["UsePartialCommits"] -or ($baselineControlsDetails.SupportedSources -contains $scanSource))
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
            $currentInstance = [WriteCAStatus]::GetInstance();
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
