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
                $props = $Event.SourceArgs[0];
                $version = $currentInstance.InvocationContext.MyCommand.Version
                if($null -ne $props)
                {
                    $scanSource = [RemoteReportHelper]::GetScanSource();
                    if($scanSource -ne [ScanSource]::Runbook) { return; }                                             			               
                    [ComplianceStateTableEntity[]] $ResourceFlatEntries = @();
                    $complianceReportHelper = [ComplianceReportHelper]::new($props.SubscriptionContext, $version); 
                    $complianceData = $null;
                    if($complianceReportHelper.HaveRequiredPermissions())
                    {
                        $selectColumns = @("PartitionKey","RowKey");
                        $complianceData = $complianceReportHelper.GetSubscriptionComplianceReport($null, $selectColumns);
                    }
                    if(($complianceData | Measure-Object).Count -gt 0)
                    {
                        $resourceHashMap = @{};
                        [ResourceInventory]::FetchResources();   
                        [ResourceInventory]::FilteredResources | ForEach-Object{
                            $resource = $_;
                            $resourceIdHash = [Helpers]::ComputeHash($resource.ResourceId.ToLower());
                            if($null -eq $resourceHashMap[$resourceIdHash])
                            {
                                $resourceHashMap.Add($resourceIdHash, $resource)
                            }                        
                        }
                        $subHash = [Helpers]::ComputeHash($props.SubscriptionContext.Scope.ToLower());
                        if($null -eq $resourceHashMap[$subHash])
                        {
                            $resourceHashMap.Add($subHash,$props.SubscriptionContext.Scope);
                        }
                        [string[]] $deletedResources = @();
                    
                        foreach($resourceRecord in $complianceData)
                        {
                            if($null -eq $resourceHashMap[$resourceRecord.PartitionKey] -and -not $deletedResources.Contains($resourceRecord.PartitionKey))
                            {                                
                                $deletedResources += $resourceRecord.PartitionKey;
                            }
                        }
                        if(($deletedResources | Measure-Object).Count -gt 0)
                        {
                            $recordsToBeDeleted = $complianceReportHelper.GetSubscriptionComplianceReport($deletedResources);
                            if(($recordsToBeDeleted | Measure-Object).Count -gt 0)
                            {
                                $recordsToBeDeleted | ForEach-Object { $_.IsActive = $false;}
                            }
                            $complianceReportHelper.SetLocalSubscriptionScanReport($recordsToBeDeleted);
                        }
                    }                    
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
