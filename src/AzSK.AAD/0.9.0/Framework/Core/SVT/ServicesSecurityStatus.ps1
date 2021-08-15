﻿Set-StrictMode -Version Latest
class ServicesSecurityStatus: SVTCommandBase
{
	[Resolver] $Resolver = $null;
	[bool] $IsPartialCommitScanActive = $false;
	[bool] $IsPrivilegedUser = $false;
	
	ServicesSecurityStatus([string] $tenantId, [InvocationInfo] $invocationContext, [Resolver] $resolver):
        Base($tenantId, $invocationContext)
    {
		if(-not $resolver)
		{
			throw [System.ArgumentException] ("The argument 'resolver' is null");
		}

		$this.Resolver = $resolver;
		$this.Resolver.LoadResourcesForScan();

		#BaseLineControlFilter with control ids
		$this.UsePartialCommits =$invocationContext.BoundParameters["UsePartialCommits"];
		$this.UseBaselineControls = $invocationContext.BoundParameters["UseBaselineControls"];
		$this.CentralStorageAccount = $invocationContext.BoundParameters["CentralStorageAccount"];
		#[PartialScanManager]::ClearInstance();
		#$this.BaselineFilterCheck();
		#$this.UsePartialCommitsCheck();
	}

	[SVTEventContext[]] ComputeApplicableControls()
	{
		#[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
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
					$svtObject = New-Object -TypeName $svtClassName -ArgumentList $this.TenantContext.tenantId, $resource
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
				$svtObject = New-Object -TypeName $svtClassName -ArgumentList $this.TenantContext.tenantId
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
			#TODO: why not: $this.WriteMessage("No security controls/resources match the input criteria specified. `nPlease rerun the command using a different set of criteria.",[MessageType]::Warning)
			return $result;
		}
		$this.PublishCustomMessage("Number of resources: $($this.resolver.SVTResourcesFoundCount)");
		$automatedResources = @();
		
		$automatedResources += ($resourcesList | Where-Object { $_.ResourceTypeMapping });
		
		# Resources skipped from scan using excludeResourceName or -ExcludeResourceGroupNames parameters
		if([Helpers]::CheckMember($this.resolver,"ExcludedResourceGroupNames") -or [Helpers]::CheckMember($this.resolver,"ExcludedResources"))
		{
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
	}
		if($runNonAutomated)
		{
			$this.ReportNonAutomatedResources();
		}
					
		$this.PublishCustomMessage("`nNumber of resources for which security controls will be evaluated: $($automatedResources.Count)",[MessageType]::Info);
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
				#$this.UpdateRetryCountForPartialScan();
				$svtClassName = $_.ResourceTypeMapping.ClassName;

				$svtObject = $null;

				try
				{
					$extensionSVTClassName = $svtClassName + "Ext";
					$extensionSVTClassFilePath = [ConfigurationManager]::LoadExtensionFile($svtClassName);				
					if([string]::IsNullOrWhiteSpace($extensionSVTClassFilePath))
					{
						$svtObject = New-Object -TypeName $svtClassName -ArgumentList $this.TenantContext.tenantId, $_
					}
					else {
						# file has to be loaded here due to scope contraint
						. $extensionSVTClassFilePath
						$svtObject = New-Object -TypeName $extensionSVTClassName -ArgumentList $this.TenantContext.tenantId, $_
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
				# if(($result | Measure-Object).Count -gt 0)
				# {
				# 	if($currentCount % 5 -eq 0 -or $currentCount -eq $totalResources)
				# 	{
				# 		$this.UpdatePartialCommitBlob()
				# 	}					
				# }
					
				# Register/Deregister all listeners to cleanup the memory
				#BUGBUG TODO [ListenerHelper]::RegisterListeners();
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
	# hidden [SVTEventContext[]] FetchAttestationInfo()
	# {
	# 	[ControlStateExtension] $ControlStateExt = [ControlStateExtension]::new($this.TenantContext, $this.InvocationContext);
	# 	$ControlStateExt.UniqueRunId = $(Get-Date -format "yyyyMMdd_HHmmss");
	# 	$ControlStateExt.Initialize($false);
	# 	$attestationFound = $ControlStateExt.ComputeControlStateIndexer();
	# 	$attestedResources = @()
	# 	if(($null -ne $ControlStateExt.ControlStateIndexer) -and ([Helpers]::CheckMember($ControlStateExt.ControlStateIndexer, "ResourceId")))
	# 	{
	# 		$attestedResources = $this.Resolver.SVTResources | Where-Object {$ControlStateExt.ControlStateIndexer.ResourceId -contains $_.ResourceId}
	# 	}
	# 	return $this.RunForAllResources("FetchStateOfAllControls",$false,$attestedResources)
	# }

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
	# [void] BaselineFilterCheck()
	# {
	# 	#Load ControlSetting Resource Types and Filter resources
	# 	$scanSource = [AzSKSettings]::GetInstance().GetScanSource();
	# 	#Load ControlSetting Resource Types and Filter resources
	# 	if($this.CentralStorageAccount){
	# 		[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance($this.CentralStorageAccount, $this.TenantContext.tenantId);	
	# 	}
	# 	else{
	# 		[PartialScanManager] $partialScanMngr = [PartialScanManager]::GetInstance();
	# 	}
	#     $baselineControlsDetails = $partialScanMngr.GetBaselineControlDetails()
	# 	#If Scan source is in supported sources or baselineControls switch is available
	# 	if ($null -ne $baselineControlsDetails -and ($baselineControlsDetails.ResourceTypeControlIdMappingList | Measure-Object).Count -gt 0 -and ($baselineControlsDetails.SupportedSources -contains $scanSource -or $this.UseBaselineControls))
	# 	{
	# 		#Get resource type and control ids mapping from controlsetting object
	# 		#$this.PublishCustomMessage("Running cmdlet with baseline resource types and controls.", [MessageType]::Warning);
	# 		$baselineResourceTypes = $baselineControlsDetails.ResourceTypeControlIdMappingList | Select-Object ResourceType | Foreach-Object {$_.ResourceType}
	# 		#Filter SVT resources based on baseline resource types
	# 		$ResourcesWithBaselineFilter =$this.Resolver.SVTResources | Where-Object {$null -ne $_.ResourceTypeMapping -and   $_.ResourceTypeMapping.ResourceTypeName -in $baselineResourceTypes }
			
	# 		#Get the list of control ids
	# 		$controlIds = $baselineControlsDetails.ResourceTypeControlIdMappingList | Select-Object ControlIds | ForEach-Object {  $_.ControlIds }
	# 		$BaselineControlIds = [system.String]::Join(",",$controlIds);
	# 		if(-not [system.String]::IsNullOrEmpty($BaselineControlIds))
	# 		{
	# 			$this.ControlIds = $controlIds;

	# 		}
	# 		$this.Resolver.SVTResources = $ResourcesWithBaselineFilter
	# 	}

	# }

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
