Set-StrictMode -Version Latest
class ServicesSecurityStatus: AzSVTCommandBase
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
		$this.UsePreviewBaselineControls = $invocationContext.BoundParameters["UsePreviewBaselineControls"];
		$this.CentralStorageAccount = $invocationContext.BoundParameters["CentralStorageAccount"];
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
			#[AzListenerHelper]::RegisterListeners();
				 
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
		
		$this.Severity = $this.ConvertToStringArray($this.Severity) # to handle when no severity is passed in command
		if($this.Severity)
		{
			$this.Severity = [ControlHelper]::CheckValidSeverities($this.Severity);
			
		}
		[SVTEventContext[]] $result = @();
		
		if(($resourcesList | Measure-Object).Count -eq 0)
		{
			$this.PublishCustomMessage("No security controls/resources match the input criteria specified. `nPlease rerun the command using a different set of criteria.");
			return $result;
		}
		$this.PublishCustomMessage("Number of resources: $($this.resolver.SVTResourcesFoundCount)");
		$automatedResources = @();
		
		$automatedResources += ($resourcesList | Where-Object { $_.ResourceTypeMapping });
		
		# Resources skipped from scan using excludeResourceName or -ExcludeResourceGroupNames parameters
		$ExcludedResourceGroups=$this.resolver.ExcludedResourceGroupNames 
		$ExcludedResources=$this.resolver.ExcludedResources ;
		if(($this.resolver.ExcludeResourceGroupNames| Measure-Object).Count -gt 0 -or ($this.resolver.ExcludeResourceNames| Measure-Object).Count -gt 0)
		{
			$this.PublishCustomMessage("One or more resources/resource groups will be excluded from the scan based on exclude flags.")	
			if(-not [string]::IsNullOrEmpty($this.resolver.ExcludeResourceGroupWarningMessage))
			{
				$this.PublishCustomMessage("$($this.resolver.ExcludeResourceGroupWarningMessage)",[MessageType]::Warning)
				
			}
			if(-not [string]::IsNullOrEmpty($this.resolver.ExcludeResourceWarningMessage))
			{
				$this.PublishCustomMessage("$($this.resolver.ExcludeResourceWarningMessage)",[MessageType]::Warning)
			}
			$this.PublishCustomMessage("Summary of exclusions: ");
			if(($this.resolver.ExcludeResourceGroupNames| Measure-Object).Count -gt 0)
			{
				$this.PublishCustomMessage("	Resource groups excluded: $(($ExcludedResourceGroups | Measure-Object).Count)", [MessageType]::Info);	
			}
			$this.PublishCustomMessage("	Resources excluded: $(($ExcludedResources | Measure-Object).Count)(includes RGs,resourcetypenames and explicit exclusions).", [MessageType]::Info);	
			$this.PublishCustomMessage("For a detailed list of excluded resources, see 'ExcludedResources-$($this.RunIdentifier).txt' in the output log folder.")
			$this.ReportExcludedResources($this.resolver);
		}
		if($runNonAutomated)
		{
			$this.ReportNonAutomatedResources();
		}

		#Begin-perf-optimize for ControlIds parameter  
		#If controlIds are specified  filter only to applicable resources
		#Filter resources based control tags like OwnerAccess, GraphAccess,RBAC, Authz, SOX etc 
		$this.MapTagsToControlIds();
		#Filter automated resources based on control ids 
        $automatedResources = $this.MapControlsToResourceTypes($automatedResources)
		#End-perf-optimize

					
		$this.PublishCustomMessage("`nNumber of resources for which security controls will be evaluated: $($automatedResources.Count)",[MessageType]::Info);
		
		$totalResources = $automatedResources.Count;
		[int] $currentCount = 0;
		$childResources = @();
		$automatedResources | ForEach-Object {
			$exceptionMessage = "Exception for resource: [ResourceType: $($_.ResourceTypeMapping.ResourceTypeName)] [ResourceGroupName: $($_.ResourceGroupName)] [ResourceName: $($_.ResourceName)]"
            try
            {
				$currentCount += 1;
				if($totalResources -gt 1)
				{
					$this.PublishCustomMessage(" `r`nChecking resource [$currentCount/$totalResources] ");
				}

				#Update resource scan retry count in scan snapshot in storage if user partial commit switch is on
				if($this.UsePartialCommits)
				{
					$this.UpdateRetryCountForPartialScan();
				}
				
				$svtClassName = $_.ResourceTypeMapping.ClassName;

				$svtObject = $null;

				try
				{
					$extensionSVTClassName = $svtClassName + "Ext";
                    # Resetting $extensionSVTClassFilePath to null as PS session holds the previous value
                    $extensionSVTClassFilePath = $null

                    # Checks if $extensionSVTClassName type is not loaded in memory
					if (-not ($extensionSVTClassName -as [type])) 
					{
   
                        # Looking for Extension class using configuration
                        $extensionSVTClassFilePath = [ConfigurationManager]::LoadExtensionFile($svtClassName); 
						if ([string]::IsNullOrWhiteSpace($extensionSVTClassFilePath)) 
						{
                            $svtObject = New-Object -TypeName $svtClassName -ArgumentList $this.SubscriptionContext.SubscriptionId, $_
                        }
						else 
						{
                            # Loading Extension class, if Extension class is already present
                            Write-Warning "########## Loading extended type [$extensionSVTClassName] into session... ##########"
                            . $extensionSVTClassFilePath
                            $svtObject = New-Object -TypeName $extensionSVTClassName -ArgumentList $this.SubscriptionContext.SubscriptionId, $_
                        }
                    }   
                    else 
                    {
                        # Create the instance of Extension class
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
					$svtObject.RunningLatestPSModule = $this.RunningLatestPSModule;
					$this.SetSVTBaseProperties($svtObject);
					$childResources += $svtObject.ChildSvtObjects;
					$currentResourceResults += $svtObject.$methodNameToCall();
					$result += $currentResourceResults;

				}
				if(($result | Measure-Object).Count -gt 0)
				{
					if($currentCount % 5 -eq 0 -or $currentCount -eq $totalResources)
					{
						$this.UpdatePartialCommitBlob()
					}					
				}

				# Changes for compliance table dependency removal
				# if IsComplianceStateCachingEnabled is false, do not persist scan result in compliance state table
				if($this.IsComplianceStateCachingEnabled)
				{	
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
				
				
			}
            catch
            {
				$this.PublishCustomMessage($exceptionMessage);
				$this.CommandError($_);
			}
		}
		if(($childResources | Measure-Object).Count -gt 0)
		{
			try
			{
				[SVTEventContext[]] $childResourceResults = @();
				$temp=  $childResources |Sort-Object -Property @{Expression={$_.ResourceId}} -Unique
				$temp| ForEach-Object {
					$_.RunningLatestPSModule = $this.RunningLatestPSModule
					$this.SetSVTBaseProperties($_)
					$childResourceResults += $_.$methodNameToCall();
					
				}
				$result += $childResourceResults;
			}
			catch
			{
				$this.PublishCustomMessage($_);
				
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

	hidden [SVTEventContext[]] ScanAttestedControls()
	{
		[ControlStateExtension] $ControlStateExt = [ControlStateExtension]::new($this.SubscriptionContext, $this.InvocationContext);
		$ControlStateExt.UniqueRunId = $this.ControlStateExt.UniqueRunId;
		$ControlStateExt.Initialize($false);
		$ControlStateExt.ComputeControlStateIndexer();
		$resourcesAttestedinCurrentScan = @()
		if(($null -ne $ControlStateExt.ControlStateIndexer) -and ([Helpers]::CheckMember($ControlStateExt.ControlStateIndexer, "ResourceId")))
		{
			$resourcesAttestedinCurrentScan = $this.Resolver.SVTResources | Where-Object {$ControlStateExt.ControlStateIndexer.ResourceId -contains $_.ResourceId}
		}
		return $this.RunForAllResources("RescanAndPostAttestationData",$false,$resourcesAttestedinCurrentScan)
	}
	
	#BaseLine Control Filter Function
	[void] BaselineFilterCheck()
	{
		
		#Check if use baseline or preview baseline flag is passed as parameter
		if($this.UseBaselineControls -or $this.UsePreviewBaselineControls)
		{
			$ResourcesWithBaselineFilter =@()
			#Load ControlSetting file
			$ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");

			$baselineControlsDetails = $ControlSettings.BaselineControls
			#if baselineControls switch is available and baseline controls available in settings
			if ($null -ne $baselineControlsDetails -and ($baselineControlsDetails.ResourceTypeControlIdMappingList | Measure-Object).Count -gt 0 -and  $this.UseBaselineControls)
			{
				#Get resource type and control ids mapping from controlsetting object
				#$this.PublishCustomMessage("Running cmdlet with baseline resource types and controls.", [MessageType]::Warning);
				$baselineResourceTypes = $baselineControlsDetails.ResourceTypeControlIdMappingList | Select-Object ResourceType | Foreach-Object {$_.ResourceType}
				#Filter SVT resources based on baseline resource types
				$ResourcesWithBaselineFilter += $this.Resolver.SVTResources | Where-Object {$null -ne $_.ResourceTypeMapping -and   $_.ResourceTypeMapping.ResourceTypeName -in $baselineResourceTypes }
				
				#Get the list of control ids
				$controlIds = $baselineControlsDetails.ResourceTypeControlIdMappingList | Select-Object ControlIds | ForEach-Object {  $_.ControlIds }
				$BaselineControlIds = [system.String]::Join(",",$controlIds);
				if(-not [system.String]::IsNullOrEmpty($BaselineControlIds))
				{
					#Assign preview control list to ControlIds filter parameter. This controls gets filtered during scan.
					$this.ControlIds = $controlIds;

				}		
			}
			#If baseline switch is passed and there is no baseline control list present then throw exception 
			elseif (($baselineControlsDetails.ResourceTypeControlIdMappingList | Measure-Object).Count -eq 0 -and $this.UseBaselineControls) 
			{
				throw ([SuppressedException]::new(("There are no baseline controls defined for your org. No controls will be scanned."), [SuppressedExceptionType]::Generic))
			}

			#Preview Baseline Controls

			$previewBaselineControlsDetails = $null
			#if use preview baseline switch is passed and preview baseline list property present 
			if($this.UsePreviewBaselineControls -and [Helpers]::CheckMember($ControlSettings,"PreviewBaselineControls"))
			{
				$previewBaselineControlsDetails = $ControlSettings.PreviewBaselineControls
				#if preview baseline list is defined in settings
				if ($null -ne $previewBaselineControlsDetails -and ($previewBaselineControlsDetails.ResourceTypeControlIdMappingList | Measure-Object).Count -gt 0 )
				{
					
					$previewBaselineResourceTypes = $previewBaselineControlsDetails.ResourceTypeControlIdMappingList | Select-Object ResourceType | Foreach-Object {$_.ResourceType}
					#Filter SVT resources based on preview baseline baseline resource types
					$BaselineResourceList = @()
					if(($ResourcesWithBaselineFilter | Measure-Object).Count -gt 0)
					{
						$BaselineResourceList += $ResourcesWithBaselineFilter | Foreach-Object { $_.ResourceId}
					}
					$ResourcesWithBaselineFilter += $this.Resolver.SVTResources | Where-Object {$null -ne $_.ResourceTypeMapping -and  $_.ResourceTypeMapping.ResourceTypeName -in $previewBaselineResourceTypes -and $_.ResourceId -notin $BaselineResourceList }
					
					#Get the list of preview control ids
					$controlIds = $previewBaselineControlsDetails.ResourceTypeControlIdMappingList | Select-Object ControlIds | ForEach-Object {  $_.ControlIds }
					$previewBaselineControlIds = [system.String]::Join(",",$controlIds);
					if(-not [system.String]::IsNullOrEmpty($previewBaselineControlIds))
					{
						# Assign preview control list to ControlIds filter parameter. This controls gets filtered during scan.
						$this.ControlIds += $controlIds;
					}			
				}
				#If preview baseline switch is passed and there is no baseline control list present then throw exception 
				elseif (($previewBaselineControlsDetails.ResourceTypeControlIdMappingList | Measure-Object).Count -eq 0 -and $this.UsePreviewBaselineControls) 
				{
					if(($baselineControlsDetails.ResourceTypeControlIdMappingList | Measure-Object).Count -eq 0 -and $this.UseBaselineControls)
					{
						throw ([SuppressedException]::new(("There are no  baseline and preview-baseline controls defined for this policy. No controls will be scanned."), [SuppressedExceptionType]::Generic))
					}
					if(-not ($this.UseBaselineControls))
					{
						throw ([SuppressedException]::new(("There are no preview-baseline controls defined for your org. No controls will be scanned."), [SuppressedExceptionType]::Generic))
					} 		
				}
			}

			#Assign baseline filtered resources to SVTResources list (resource list to be scanned)
			if(($ResourcesWithBaselineFilter | Measure-Object).Count -gt 0)
			{
				$this.Resolver.SVTResources = $ResourcesWithBaselineFilter
			}
		}
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
                $nonScannedResourcesList = @();
                if(($partialScanMngr.IsMasterListActive() -eq [ActiveStatus]::Yes)  )
                {
                    $this.IsPartialCommitScanActive = $true;
                    $allResourcesList = $partialScanMngr.GetAllListedResources()
                    # Get list of non-scanned active resources
                    $nonScannedResourcesList = $partialScanMngr.GetNonScannedResources();
                    $this.PublishCustomMessage("Resuming scan from last commit. $(($nonScannedResourcesList | Measure-Object).Count) out of $(($allResourcesList | Measure-Object).Count) resources will be scanned.", [MessageType]::Warning);
                    $nonScannedResourceIdList = $nonScannedResourcesList | Select-Object Id | ForEach-Object { $_.Id}
                    #Filter SVT resources based on master resources list available and scan completed
                    #Commenting telemtry here to include PartialScanIdentifier
                    #[AIOrgTelemetryHelper]::PublishEvent( "Partial Commit Details", @{"TotalSVTResources"= $($this.Resolver.SVTResources | Where-Object { $_.ResourceTypeMapping } | Measure-Object).Count;"UnscannedResource"=$(($nonScannedResourcesList | Measure-Object).Count); "ResourceToBeScanned" = ($this.Resolver.SVTResources | Where-Object {$_.ResourceId -in $nonScannedResourceIdList } | Measure-Object).Count;},$null)
                    $this.Resolver.SVTResources = $this.Resolver.SVTResources | Where-Object {$_.ResourceId -in $nonScannedResourceIdList }             
                }
                else{
                    $this.IsPartialCommitScanActive = $false;
                    $resourceIdList =  $this.Resolver.SVTResources| Where-Object {$null -ne $_.ResourceTypeMapping} | Select ResourceId | ForEach-Object {  $_.ResourceId }
                    $partialScanMngr.CreateResourceMasterList($resourceIdList);
                    #This should fetch full list of resources to be scanned 
                    $nonScannedResourcesList = $partialScanMngr.GetNonScannedResources();
                }
                #Set unique partial scan indentifier 
                $this.PartialScanIdentifier = [Helpers]::ComputeHash($partialScanMngr.ResourceScanTrackerObj.Id)
                #Telemetry with addition for Subscription Id, PartialScanIdentifier and correction in count of resources
                #Need optimization for calcuations done for total resources.
                try{
                    $CompletedResources  = 0;
                    $IncompleteScans = 0;
                    $InErrorResources = 0;
                    $ScanResourcesList = $partialScanMngr.GetAllListedResources() 
                    
                    $ScanResourcesList | Group-Object -Property State | Select-Object Name,Count | ForEach-Object{
                        if($_.Name -eq "COMP")
                        {
                            $CompletedResources = $_.Count
                        }
                        elseif ($_.Name -eq "INIT") {
                            $IncompleteScans = $_.Count
                        }
                        elseif ($_.Name -eq "ERR") {
                            $InErrorResources = $_.Count
                        }
                          
                    }   
					[AIOrgTelemetryHelper]::PublishEvent( "Partial Commit Details",@{"TotalSVTResources"= $($ScanResourcesList |Measure-Object).Count;"ScanCompletedResourcesCount"=$CompletedResources; "NonScannedResourcesCount" = $IncompleteScans;"ErrorStateResourcesCount"= $InErrorResources;"SubscriptionId"=$this.SubscriptionContext.SubscriptionId;"PartialScanIdentifier"=$this.PartialScanIdentifier;}, $null)
					
					#By default below detail partial scan tracker telemetry will be in disabled state 
					# and only be enabled using feature flag for perticular subscriptions to analaze the CA scan issues
					# Register/Deregister all listeners to cleanup the memory
					if([FeatureFlightingManager]::GetFeatureStatus("EnableDetailedResourceTrackerTelemetry",$this.SubscriptionContext.SubscriptionId) -eq $true)
					{
						$resourceTrackerEvents = [System.Collections.ArrayList]::new()
						#Loop through all resource list present in tracker and prepare array of events with common properties like RunIdentifier, SubId,etc
						foreach($resource in $ScanResourcesList){
							$resourceEvent = "" | Select-Object Name, Properties, Metrics
							#RunIdentifier value is not set at this stage. Its value is default. 
							#Investigation needs to be done base don partialScanIdentifier 
							#"RunIdentifier" = $this.RunIdentifier; 
							$Properties = @{
								"SubscriptionId"= $this.SubscriptionContext.SubscriptionId;
								"PartialScanIdentifier"=$this.PartialScanIdentifier;
								"ResourceId" = $resource.Id;
								"ScanRetryCount" = $resource.ScanRetryCount;
								"State" = $resource.State;
								"StateModifiedDate" = $resource.ModifiedDate
								"TrackerId" = $partialScanMngr.ResourceScanTrackerObj.Id
							}
								$resourceEvent.Name = "Partial Tracker Resource Details"
								$resourceEvent.Properties = $properties
								$resourceTrackerEvents.Add($resourceEvent) | Out-Null
						}
						#Push array of resourcelist to AI telemetry
						[AIOrgTelemetryHelper]::TrackEvents($resourceTrackerEvents);
					}

                }
                catch{
                    #Continue exexution if telemetry is not sent 
                }            
        }
}

	#Get list of controlIds based control tags like OwnerAccess, GraphAccess,RBAC, Authz, SOX etc.
	[void] MapTagsToControlIds()
	{
		#Check if filtertags or exclude filter tags parameter is passed from user then get mapped control ids
		if(-not [string]::IsNullOrEmpty($this.FilterTags) ) #-or -not [string]::IsNullOrEmpty($this.ExcludeTags)
		{
			$resourcetypes = @() 
			$controlList = @()
			#Get list of all supported resource Types
			$resourcetypes += ([SVTMapping]::Mapping | Sort-Object ResourceTypeName | Select-Object JsonFileName )

			$resourcetypes | ForEach-Object{
				#Fetch control json for all resource type and collect all control jsons
				$controlJson = [ConfigurationManager]::GetSVTConfig($_.JsonFileName); 
				if ([Helpers]::CheckMember($controlJson, "Controls")) 
				{
					$controlList += $controlJson.Controls | Where-Object {$_.Enabled}
				}
			}

			#If FilterTags are specified, limit the candidate set to matching controls
			if (-not [string]::IsNullOrEmpty($this.FilterTags))
			{
				$filterTagList = $this.ConvertToStringArray($this.FilterTags)
				$controlIdsWithFilterTagList = @()
				#Look at each candidate control's tags and see if there's a match in FilterTags
				$filterTagList | ForEach-Object {
					$tagName = $_ 
					$controlIdsWithFilterTagList += $controlList | Where-Object{ $tagName -in $_.Tags  } | ForEach-Object{ $_.ControlId}
				}
				#Assign filtered control Id with tag name 
				if(($this.ControlIds | Measure-Object).Count -gt 0)
				{
					#If controlids are already present in the object then intersection of controlids should be scanned
					$controlIdsWithFilterTagList = $controlIdsWithFilterTagList | where {$this.ControlIds -Contains $_}
				}
				$this.ControlIds = $controlIdsWithFilterTagList
			}

			#********** Commentiing Exclude tags logic as this will not require perf optimization as excludeTags mostly will result in most of the resources
			# #If FilterTags are specified, limit the candidate set to matching controls
			# #Note: currently either includeTag or excludeTag will work at a time. Combined flag result will be overridden by excludeTags 
			# if (-not [string]::IsNullOrEmpty($this.ExcludeTags))
			# {
			# 	$excludeFilterTagList = $this.ConvertToStringArray($this.ExcludeTags)
			# 	$controlIdsWithFilterTagList = @()
			# 	#Look at each candidate control's tags and see if there's a match in FilterTags
			# 	$excludeFilterTagList | ForEach-Object {
			# 		$tagName = $_ 
			# 		$controlIdsWithFilterTagList += $controlList | Where-Object{ $tagName -notin $_.Tags  } | ForEach-Object{ $_.ControlId}
			# 	}
			# 	#Assign filtered control Id with tag name 
			# 	$this.ControlIds = $controlIdsWithFilterTagList
			# }
		}		
	}

	[PSObject] MapControlsToResourceTypes([PSObject] $automatedResources)
	{
		$allTargetControlIds = @($this.ControlIds)
		$allTargetControlIds += $this.ConvertToStringArray($this.ControlIdString)
		#Do this only for the actual controlIds case (not the Severity-Spec "Severity:High" case)
        if ($allTargetControlIds.Count -gt 0 )
        {
            #Infer resource type names from control ids 
            $allTargetResourceTypeNames = @($allTargetControlIds | ForEach-Object { ($_ -split '_')[1]})
            $allTargetResourceTypeNamesUnique = @($allTargetResourceTypeNames | Sort-Object -Unique)
            #Match resources based on resource types. Here we have made exception for AzSKCfg to scan it every time and virtual network as its type name (VirtualNetwork) is different than controls type name (VNet) 
            $automatedResources = @($automatedResources | Where-Object {$allTargetResourceTypeNamesUnique -contains $_.ResourceTypeMapping.ResourceTypeName -or $_.ResourceType -match 'AzSKCfg' -or ($_.ResourceTypeMapping.ResourceTypeName -match 'VirtualNetwork' -and $allTargetResourceTypeNamesUnique -contains "VNet")})
		}
		return $automatedResources
	}

	[void] UpdateRetryCountForPartialScan()
	{
		$scanSource = [AzSKSettings]::GetInstance().GetScanSource();
		[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
		$baselineControlsDetails = $partialScanMngr.GetBaselineControlDetails()
		#If Scan source is in supported sources or UsePartialCommits switch is available
		if ($this.UsePartialCommits -or ($baselineControlsDetails.SupportedSources -contains $scanSource))
		{
			$partialScanMngr.UpdateResourceScanRetryCount($_.ResourceId,$this.SubscriptionContext.SubscriptionId);
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
	[void] ReportExcludedResources($SVTResolver)
	{
		$excludedObj=New-Object -TypeName PSObject;
		$excludedObj | Add-Member -NotePropertyName ExcludedResourceGroupNames -NotePropertyValue $SVTResolver.ExcludedResourceGroupNames 
		$excludedObj | Add-Member -NotePropertyName ExcludedResources -NotePropertyValue $SVTResolver.ExcludedResources
		$excludedObj | Add-Member -NotePropertyName ExcludedResourceType -NotePropertyValue $SVTResolver.ExcludeResourceTypeName 
		$excludedObj | Add-Member -NotePropertyName ExcludeResourceNames -NotePropertyValue $SVTResolver.ExcludeResourceNames 
		$this.PublishAzSKRootEvent([AzSKRootEvent]::WriteExcludedResources,$excludedObj);
	}
	
}