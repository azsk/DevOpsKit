Set-StrictMode -Version Latest
class AzServicesSecurityStatus: ServicesSecurityStatus
{
	[bool] $IsPartialCommitScanActive = $false;
	AzServicesSecurityStatus([string] $subscriptionId, [InvocationInfo] $invocationContext, [SVTResourceResolver] $resolver):
        Base($subscriptionId, $invocationContext)
    {
		if(-not $resolver)
		{
			throw [System.ArgumentException] ("The argument 'resolver' is null");
		}

		$this.Resolver = $resolver;
		$this.Resolver.LoadResourcesForScan();

		#BaseLineControlFilter with control ids
		$this.UsePartialCommits =$invocationContext.BoundParameters["UsePartialCommits"];
		$this.CentralStorageAccount = $invocationContext.BoundParameters["CentralStorageAccount"];
		[PartialScanManager]::ClearInstance();
		$this.UsePartialCommitsCheck();
    }
    

    [void] RunForAllResourcesExt()
    {
        #Update resource scan retry count in scan snapshot in storage if user partial commit switch is on
        if($this.UsePartialCommits)
        {
            $this.UpdateRetryCountForPartialScan();
        }
                
        if(($result | Measure-Object).Count -gt 0)
        {
            if($currentCount % 5 -eq 0 -or $currentCount -eq $totalResources)
            {
                $this.UpdatePartialCommitBlob()
            }					
        }

        if($this.IsLocalComplianceStoreEnabled -and ($currentResourceResults | Measure-Object).Count -gt 0)
        {	
            # Persist scan data to subscription
            try 
            {
                if($null -eq $this.ComplianceReportHelper)
                {
                    $this.ComplianceReportHelper = [ComplianceReportHelper]::new($this.SubscriptionContext, $this.GetCurrentModuleVersion())
                }
                if($this.ComplianceReportHelper.HaveRequiredPermissions())
                {
                    $this.ComplianceReportHelper.StoreComplianceDataInUserSubscription($currentResourceResults)
                }
                else
                {
                    $this.IsLocalComplianceStoreEnabled = $false;
                }
            }
            catch 
            {
                $this.PublishException($_);
            }

        }
    }
    
	hidden [SVTEventContext[]] FetchAttestationInfo()
	{
		[ControlStateExtension] $ControlStateExt = [ControlStateExtension]::new($this.SubscriptionContext, $this.InvocationContext);
		$ControlStateExt.UniqueRunId = $(Get-Date -format "yyyyMMdd_HHmmss");
		$ControlStateExt.Initialize($false);
		$attestationFound = $ControlStateExt.ComputeControlStateIndexer();
		$attestedResources = @()
		if(($null -ne $ControlStateExt.ControlStateIndexer) -and ([Helpers]::CheckMember($ControlStateExt.ControlStateIndexer, "ResourceId")))
		{
			$attestedResources = $this.Resolver.SVTResources | Where-Object {$ControlStateExt.ControlStateIndexer.ResourceId -contains $_.ResourceId}
		}
		return $this.RunForAllResources("FetchStateOfAllControls",$false,$attestedResources)
	}

	[void] UsePartialCommitsCheck()
	{
			#If Scan source is in supported sources or UsePartialCommits switch is available
			if ($this.UsePartialCommits)
			{
				#Load ControlSetting Resource Types and Filter resources
				if($this.CentralStorageAccount){
					[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance($this.CentralStorageAccount, $this.SubscriptionContext.SubscriptionId);	
				}
				else{
					[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
				}
				#$this.PublishCustomMessage("Running cmdlet under transactional mode. This will scan resources and store intermittent scan progress to Storage. It resume scan in next run if something breaks inbetween.", [MessageType]::Warning);
				#Validate if active resources list already available in store
				#If list not available in store. Get resources filtered by baseline resource types and store it storage
				if(($partialScanMngr.IsMasterListActive() -eq [ActiveStatus]::Yes)  )
				{
					$this.IsPartialCommitScanActive = $true;
					$allResourcesList = $partialScanMngr.GetAllListedResources()
					# Get list of non-scanned active resources
					$nonScannedResourcesList = $partialScanMngr.GetNonScannedResources();
					$this.PublishCustomMessage("Resuming scan from last commit. $(($nonScannedResourcesList | Measure-Object).Count) out of $(($allResourcesList | Measure-Object).Count) resources will be scanned.", [MessageType]::Warning);
					$nonScannedResourceIdList = $nonScannedResourcesList | Select-Object Id | ForEach-Object { $_.Id}
					#Filter SVT resources based on master resources list available and scan completed
					[AIOrgTelemetryHelper]::PublishEvent( "Partial Commit Details", @{"TotalSVTResources"= $($this.Resolver.SVTResources | Where-Object { $_.ResourceTypeMapping } | Measure-Object).Count;"UnscannedResource"=$(($nonScannedResourcesList | Measure-Object).Count); "ResourceToBeScanned" = ($this.Resolver.SVTResources | Where-Object {$_.ResourceId -in $nonScannedResourceIdList } | Measure-Object).Count},$null)
					$this.Resolver.SVTResources = $this.Resolver.SVTResources | Where-Object {$_.ResourceId -in $nonScannedResourceIdList }				
				}
				else{
					$this.IsPartialCommitScanActive = $false;
					$resourceIdList =  $this.Resolver.SVTResources| Where-Object {$null -ne $_.ResourceTypeMapping} | Select ResourceId | ForEach-Object {  $_.ResourceId }
					$partialScanMngr.CreateResourceMasterList($resourceIdList);
				}
				#Set unique partial scan indentifier 
				$this.PartialScanIdentifier = [Helpers]::ComputeHash($partialScanMngr.ResourceScanTrackerObj.Id)

			}
	}

	[void] UpdateRetryCountForPartialScan()
	{
		$scanSource = [AzSKSettings]::GetInstance().GetScanSource();
		[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
		$baselineControlsDetails = $partialScanMngr.GetBaselineControlDetails()
		#If Scan source is in supported sources or UsePartialCommits switch is available
		if ($this.UsePartialCommits -or ($baselineControlsDetails.SupportedSources -contains $scanSource))
		{
			$partialScanMngr.UpdateResourceScanRetryCount($_.ResourceId);
		}
	}
	
}
