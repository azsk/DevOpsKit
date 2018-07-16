Set-StrictMode -Version Latest
class ServicesSecurityStatus: SVTCommandBase
{
	[SVTResourceResolver] $Resolver = $null;
	[bool] $IsPartialCommitScanActive = $false;
	ServicesSecurityStatus([string] $subscriptionId, [InvocationInfo] $invocationContext, [SVTResourceResolver] $resolver):
        Base($subscriptionId, $invocationContext)
    {
		if(-not $resolver)
		{
			throw [System.ArgumentException] ("The argument 'resolver' is null");
		}

		$this.Resolver = $resolver;
		$this.Resolver.LoadAzureResources();

		#BaseLineControlFilter with control ids
		$this.UsePartialCommits =$invocationContext.BoundParameters["UsePartialCommits"];
		$this.UseBaselineControls = $invocationContext.BoundParameters["UseBaselineControls"];
		[PartialScanManager]::ClearInstance();
		$this.BaselineFilterCheck();
		$this.UsePartialCommitsCheck();

	}

	[SVTEventContext[]] ComputeApplicableControls()
	{
		[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
		# if a scan is active - don't update the control inventory
		[SVTEventContext[]] $result = @();
		if($this.IsPartialCommitScanActive)
		{
			return $result;
		}
		$automatedResources = @();
		$automatedResources += ($this.Resolver.SVTResources | Where-Object { $_.ResourceTypeMapping });
		try
        {
		foreach($resource in $automatedResources) {
			try
			{
				$svtClassName = $resource.ResourceTypeMapping.ClassName;
				$svtObject = $null;
				try
				{
					$svtObject = New-Object -TypeName $svtClassName -ArgumentList $this.SubscriptionContext.SubscriptionId, $resource
				}
				catch
				{
					$this.CommandError($_.Exception.InnerException.ErrorRecord);
				}
				if($svtObject)
				{
					$this.SetSVTBaseProperties($svtObject);
					$result += $svtObject.ComputeApplicableControlsWithContext();
				}
			}
			catch
			{
				$this.CommandError($_);
			}
			#[ListenerHelper]::RegisterListeners();
				 
			}
			$svtClassName = [SVTMapping]::SubscriptionMapping.ClassName;
			$svtObject = $null;
			try
			{
				$svtObject = New-Object -TypeName $svtClassName -ArgumentList $this.SubscriptionContext.SubscriptionId
			}
			catch
			{
				$this.CommandError($_.Exception.InnerException.ErrorRecord);
			}
			if($svtObject)
			{
				$this.SetSVTBaseProperties($svtObject);
				$result += $svtObject.ComputeApplicableControlsWithContext();
			}
            
		}
		catch
        {
			$this.CommandError($_);
        }
		$this.PublishEvent([SVTEvent]::WriteInventory, $result);

		if ($null -ne $result) 
		{
			[RemoteApiHelper]::PostApplicableControlSet($result);					
			$this.PublishCustomMessage("Completed sending control inventory.");
        }
		else {
			$this.PublishCustomMessage("There is an active scan going on. Please try later.");
		}
		return $result;
	}

	hidden [SVTEventContext[]] RunForAllResources([string] $methodNameToCall, [bool] $runNonAutomated, [PSObject] $resourcesList)
	{
		if ([string]::IsNullOrWhiteSpace($methodNameToCall))
		{
			throw [System.ArgumentException] ("The argument 'methodNameToCall' is null. Pass the reference of method to call. e.g.: [YourClass]::new().YourMethod");
		}

		[SVTEventContext[]] $result = @();
		
		if(($resourcesList | Measure-Object).Count -eq 0)
		{
			$this.PublishCustomMessage("No security controls/resources match the input criteria specified. `nPlease rerun the command using a different set of criteria.");
			return $result;
		}
		$this.PublishCustomMessage("Number of resources: $(($resourcesList | Measure-Object).Count)");
		$automatedResources = @();
		
		$automatedResources += ($resourcesList | Where-Object { $_.ResourceTypeMapping });
		
		$this.PublishCustomMessage("Number of resources for which security controls will be evaluated: $($automatedResources.Count)");
		if($runNonAutomated)
		{
			$this.ReportNonAutomatedResources();
		}

		$totalResources = $automatedResources.Count;
		[int] $currentCount = 0;
		$automatedResources | ForEach-Object {
			$exceptionMessage = "Exception for resource: [ResourceType: $($_.ResourceTypeMapping.ResourceTypeName)] [ResourceGroupName: $($_.ResourceGroupName)] [ResourceName: $($_.ResourceName)]"
            try
            {
				$currentCount += 1;
				if($totalResources -gt 1)
				{
					$this.PublishCustomMessage(" `r`nChecking resource [$currentCount/$totalResources] ");
				}
				#Update resource scan retry count in scan snapshot in storage
				$this.UpdateRetryCountForPartialScan();
				$svtClassName = $_.ResourceTypeMapping.ClassName;

				$svtObject = $null;

				try
				{
					$extensionSVTClassName = $svtClassName + "Ext";
					$extensionSVTClassFilePath = [ConfigurationManager]::LoadExtensionFile($svtClassName);				
					if([string]::IsNullOrWhiteSpace($extensionSVTClassFilePath))
					{
						$svtObject = New-Object -TypeName $svtClassName -ArgumentList $this.SubscriptionContext.SubscriptionId, $_
					}
					else {
						# file has to be loaded here due to scope contraint
						. $extensionSVTClassFilePath
						$svtObject = New-Object -TypeName $extensionSVTClassName -ArgumentList $this.SubscriptionContext.SubscriptionId, $_
					}
				}
				catch
				{
					$this.PublishCustomMessage($exceptionMessage);
					# Unwrapping the first layer of exception which is added by New-Object function
					$this.CommandError($_.Exception.InnerException.ErrorRecord);
				}

				[SVTEventContext[]] $currentResourceResults = @();
				if($svtObject)
				{
					$svtObject.RunningLatestPSModule = $this.RunningLatestPSModule
					$this.SetSVTBaseProperties($svtObject);
					$currentResourceResults += $svtObject.$methodNameToCall();
					$svtObject.ChildSvtObjects | ForEach-Object {
						$_.RunningLatestPSModule = $this.RunningLatestPSModule
						$this.SetSVTBaseProperties($_)
						$currentResourceResults += $_.$methodNameToCall();
					}
					$result += $currentResourceResults;

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
					
				# Register/Deregister all listeners to cleanup the memory
				[ListenerHelper]::RegisterListeners();
			}
            catch
            {
				$this.PublishCustomMessage($exceptionMessage);
				$this.CommandError($_);
            }
        }
		

		return $result;
	}

	hidden [SVTEventContext[]] RunAllControls()
	{
		return $this.RunForAllResources("EvaluateAllControls",$true,$this.Resolver.SVTResources)
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

	hidden [void] ReportNonAutomatedResources()
	{
		$nonAutomatedResources = @();
		$nonAutomatedResources += ($this.Resolver.SVTResources | Where-Object { $null -eq $_.ResourceTypeMapping });

		if(($nonAutomatedResources|Measure-Object).Count -gt 0)
		{
			$this.PublishCustomMessage("Number of resources for which security controls will NOT be evaluated: $($nonAutomatedResources.Count)", [MessageType]::Warning);

			$nonAutomatedResTypes = [array] ($nonAutomatedResources | Select-Object -Property ResourceType -Unique);
			$this.PublishCustomMessage([MessageData]::new("Security controls are yet to be automated for the following service types: ", $nonAutomatedResTypes));

			$this.PublishAzSKRootEvent([AzSKRootEvent]::UnsupportedResources, $nonAutomatedResources);
		}
	}


	#BaseLineControlFilter Function
	[void] BaselineFilterCheck()
	{
		#Load ControlSetting Resource Types and Filter resources
		$scanSource = [AzSKSettings]::GetInstance().GetScanSource();
		#Load ControlSetting Resource Types and Filter resources
		[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
		$baselineControlsDetails = $partialScanMngr.GetBaselineControlDetails()
		#If Scan source is in supported sources or baselineControls switch is available
		if ($null -ne $baselineControlsDetails -and ($baselineControlsDetails.ResourceTypeControlIdMappingList | Measure-Object).Count -gt 0 -and ($baselineControlsDetails.SupportedSources -contains $scanSource -or $this.UseBaselineControls))
		{
			#Get resource type and control ids mapping from controlsetting object
			#$this.PublishCustomMessage("Running cmdlet with baseline resource types and controls.", [MessageType]::Warning);
			$baselineResourceTypes = $baselineControlsDetails.ResourceTypeControlIdMappingList | Select-Object ResourceType | Foreach-Object {$_.ResourceType}
			#Filter SVT resources based on baseline resource types
			$ResourcesWithBaselineFilter =$this.Resolver.SVTResources | Where-Object {$null -ne $_.ResourceTypeMapping -and   $_.ResourceTypeMapping.ResourceTypeName -in $baselineResourceTypes }
			
			#Get the list of control ids
			$controlIds = $baselineControlsDetails.ResourceTypeControlIdMappingList | Select-Object ControlIds | ForEach-Object {  $_.ControlIds }
			$BaselineControlIds = [system.String]::Join(",",$controlIds);
			if(-not [system.String]::IsNullOrEmpty($BaselineControlIds))
			{
				$this.ControlIds = $controlIds;

			}
			$this.Resolver.SVTResources = $ResourcesWithBaselineFilter
		}

	}

	[void] UsePartialCommitsCheck()
	{
		#Load ControlSetting Resource Types and Filter resources
		$scanSource = [AzSKSettings]::GetInstance().GetScanSource();
		#Load ControlSetting Resource Types and Filter resources
		[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
		$baselineControlsDetails = $partialScanMngr.GetBaselineControlDetails()
		#If Scan source is in supported sources or UsePartialCommits switch is available
		if ($this.UsePartialCommits -or ($baselineControlsDetails.SupportedSources -contains $scanSource))
		{
			#$this.PublishCustomMessage("Running cmdlet under transactional mode. This will scan resources and store intermittent scan progress to Storage. It resume scan in next run if something breaks inbetween.", [MessageType]::Warning);
			[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
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

	[void] UpdatePartialCommitBlob()
	{
		$scanSource = [AzSKSettings]::GetInstance().GetScanSource();
		[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
		$baselineControlsDetails = $partialScanMngr.GetBaselineControlDetails()
		#If Scan source is in supported sources or UsePartialCommits switch is available
		if ($this.UsePartialCommits -or ($baselineControlsDetails.SupportedSources -contains $scanSource))
		{
			$partialScanMngr.PersistStorageBlob();
		}
	}		
}
