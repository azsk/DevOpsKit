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
           try
           {
                $props = $Event.SourceArgs[0];
                $version = $currentInstance.InvocationContext.MyCommand.Version
                if($null -ne $props)
                {
                    $scanSource = [RemoteReportHelper]::GetScanSource();
                    if($scanSource -ne [ScanSource]::Runbook) { return; }                                             			                             
                    [ComplianceStateTableEntity[]] $ResourceFlatEntries = @();
                    $complianceReportHelper = [ComplianceReportHelper]::GetInstance($props.SubscriptionContext, $version); 
                    $complianceData = $null;
                    # Changes for compliance table dependency removal
				    # if IsComplianceStateCachingEnabled is false, do not persist/fetch scan result in compliance state table
                    if($complianceReportHelper.IsComplianceStateCachingEnabled)
                    {
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

        $this.RegisterEvent([AzSKRootEvent]::PublishCustomData, {
            $currentInstance = [WriteCAStatus]::GetInstance();
            try
            {	
                $CustomDataObj =  $Event.SourceArgs
                $CustomObjectData=$CustomDataObj| Select-Object -exp Messages| Select-Object -exp DataObject

                if($CustomObjectData.Name -eq "PolicyComplianceTelemetry")
                {        
                    try {
                        $subId = $CustomObjectData.Value;
                        $resourceAppIdUri = [WebRequestHelper]::GetResourceManagerUrl()
                        $accessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
                        $PolicyUri = [string]::Format("{0}subscriptions/{1}/providers/Microsoft.PolicyInsights/policyStates/latest/queryResults?api-version=2018-07-01-preview",$resourceAppIdUri,$subId)
                        $policyCompliance = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Post, $PolicyUri,$null);
                        $policyCompliance = $policyCompliance | Select-Object ResourceId,PolicyDefinitionId,PolicyAssignmentName,IsCompliant,PolicyAssignmentScope
                        #$policyCompliance = Get-AzPolicyState -SubscriptionId $subId | Select-Object ResourceId,PolicyDefinitionId,PolicyAssignmentName,IsCompliant,PolicyAssignmentScope
                        [RemoteApiHelper]::PostPolicyComplianceTelemetry($policyCompliance);
                    }
                    catch {
                        $currentInstance.PublishException($_);
                    }                                
                }   
                else
                {
                    $ResourceControlsData = $CustomObjectData.Value;
                    # Changes for compliance table dependency removal
				    # if IsComplianceStateCachingEnabled is false, do not persist/fetch scan result in compliance state table
                    $complianceReportHelper = [ComplianceReportHelper]::GetInstance($props.SubscriptionContext, $currentInstance.InvocationContext.MyCommand.Version); 
                    if($complianceReportHelper.IsComplianceStateCachingEnabled)
                    {
                        if($null -ne $ResourceControlsData.ResourceContext -and ($ResourceControlsData.Controls | Measure-Object).Count -gt 0)
                        {
                            
                                $ResourceControlsDataMini = "" | Select-Object ResourceName, ResourceGroupName, ResourceId, Controls, ChildResourceNames
                                $ResourceControlsDataMini.ResourceName = $ResourceControlsData.ResourceContext.ResourceName;
                                $ResourceControlsDataMini.ResourceGroupName = $ResourceControlsData.ResourceContext.ResourceGroupName;
                                $ResourceControlsDataMini.ResourceId = $ResourceControlsData.ResourceContext.ResourceId;
                                $ResourceControlsDataMini.ChildResourceNames = $ResourceControlsData.ChildResourceNames;
                                $controls = @();
                                $ResourceControlsData.Controls | ForEach-Object {
                                    $control = "" | Select-Object ControlStringId, ControlId;
                                    $control.ControlStringId = $_.ControlId;
                                    $control.ControlId = $_.Id;
                                    $controls += $control;
                                }
                                $ResourceControlsDataMini.Controls = $controls;            

                                #compute hash for the given resource
                                $props = $Event.SourceArgs[0];
                                $version = $currentInstance.InvocationContext.MyCommand.Version

                                if($null -ne $props)
                                {
                                    [string[]] $partitionKeys = @();       
                                    [ComplianceStateTableEntity[]] $RecordsToBeDeleted = @();         
                                    $partitionKey = [Helpers]::ComputeHash($ResourceControlsDataMini.ResourceId.ToLower());                
                                    $partitionKeys += $partitionKey                                


                                    $ComplianceStateData = $null;

                                    if($complianceReportHelper.HaveRequiredPermissions())
                                    {
                                        $ComplianceStateData = $complianceReportHelper.GetSubscriptionComplianceReport($partitionKeys); 
                                    }
                                    
                                    if(($ComplianceStateData | Measure-Object).Count -gt 0)
                                    {
                                        $ComplianceStateData | ForEach-Object {
                                            $row = $_;
                                            if(($ResourceControlsDataMini.Controls | Where-Object { $_.ControlId -eq $row.ControlIntId} | Measure-Object).Count -gt 0)
                                            {
                                                if(-not [string]::IsNullOrWhiteSpace($row.ChildResourceName))
                                                {
                                                    if(($ResourceControlsDataMini.ChildResourceNames | Where-Object {$_ -eq $row.ChildResourceName} | Measure-Object).Count -le 0)
                                                    {
                                                        $row.IsActive = $false;
                                                        $RecordsToBeDeleted += $row;
                                                    }
                                                }                            
                                            }
                                            else {
                                                $row.IsActive = $false;
                                                $RecordsToBeDeleted += $row;
                                            }
                                        }
                                        if(($RecordsToBeDeleted | Measure-Object).Count -gt 0)
                                        {
                                                $complianceReportHelper.SetLocalSubscriptionScanReport($RecordsToBeDeleted);
                                                                                }                   
                            }
                        }
                    }
                }
                    
                }
            }
            catch
            {
                $currentInstance.PublishException($_);
            }
        });
	}


}
