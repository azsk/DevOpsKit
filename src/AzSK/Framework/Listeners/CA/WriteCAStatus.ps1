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
						#Update resource scan completion in CA storage account
						$scanSource = [AzSKSettings]::GetInstance().GetScanSource();
						[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
						$baselineControlsDetails = $partialScanMngr.GetBaselineControlDetails()
						#If Scan source is in supported sources or UsePartialCommits switch is available
						if ($currentInstance.InvocationContext.BoundParameters["UsePartialCommits"] -or ($baselineControlsDetails.SupportedSources -contains $scanSource))
						{
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
           try
           {
               $scanSource = [RemoteReportHelper]::GetScanSource();
               if($scanSource -ne [ScanSource]::Runbook) { return; }               
               [ResourceInventory]::FetchResources();              			               
               [ComplianceStateTableEntity[]] $ResourceFlatEntries = @();
               $complianceReportHelper = [ComplianceReportHelper]::new($this.SubscriptionContext.SubscriptionId, $this.GetCurrentModuleVersion()); 
               $selectColumns = @("ParitionKey","RowKey");
               $complianceData = $complianceReportHelper.GetSubscriptionComplianceReport($null, $selectColumns);               
               foreach($resource in [ResourceInventory]::FilteredResources){
                    $resourceIdHash = [Helpers]::ComputeHash($resource.ResourceId.ToLower());
                    if(($complianceData | Where-Object {$_.ParitionKey -eq $resourceIdHash} | Measure-Object).Count -le 0)
                    {
                        [ComplianceStateTableEntity] $newComplianceEntity = [ComplianceStateTableEntity]::CreateEmptyResource($resource.ResourceId, $resourceIdHash);
                        $ResourceFlatEntries += $newComplianceEntity;
                    }                
               }
               if(($ResourceFlatEntries | Measure-Object).Count -gt 0)
               {
                    $complianceReportHelper.SetLocalSubscriptionScanReport($ResourceFlatEntries);
               }               
           }
           catch
           {
               $currentInstance.PublishException($_);
           }
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
	}


}
