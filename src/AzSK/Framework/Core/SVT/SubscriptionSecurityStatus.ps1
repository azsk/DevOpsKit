Set-StrictMode -Version Latest 
class SubscriptionSecurityStatus: SVTCommandBase
{

	SubscriptionSecurityStatus([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext)
    { 
		$this.UseBaselineControls = $invocationContext.BoundParameters["UseBaselineControls"];
		$this.BaselineFilterCheck();
	}

	hidden [SVTEventContext[]] RunForSubscription([string] $methodNameToCall)
	{
		[SVTEventContext[]] $result = @();		
		$svtClassName = [SVTMapping]::SubscriptionMapping.ClassName;

		$svtObject = $null;

		try
		{
			$extensionSVTClassName = $svtClassName + "Ext";
			$extensionSVTClassFilePath = [ConfigurationManager]::LoadExtensionFile($svtClassName);				
			if([string]::IsNullOrWhiteSpace($extensionSVTClassFilePath))
			{
				$svtObject = New-Object -TypeName $svtClassName -ArgumentList $this.SubscriptionContext.SubscriptionId
			}
			else {
				# file has to be loaded here due to scope contraint
				. $extensionSVTClassFilePath
				$svtObject = New-Object -TypeName $extensionSVTClassName -ArgumentList $this.SubscriptionContext.SubscriptionId
			}
		}
		catch
		{
			# Unwrapping the first layer of exception which is added by New-Object function
			$this.CommandError($_.Exception.InnerException.ErrorRecord);
		}

		if($svtObject)
		{
			$svtObject.RunningLatestPSModule = $this.RunningLatestPSModule
			$this.SetSVTBaseProperties($svtObject);
			$result += $svtObject.$methodNameToCall();	
			#$this.FetchRBACTelemetry($svtObject);
			[CustomData] $customData = [CustomData]::new();
			$customData.Name = "SubSVTObject";
			$customData.Value = $svtObject;
			$this.PublishCustomData($customData);		
		}

		#save result into local compliance report
		if($this.IsLocalComplianceStoreEnabled -and ($result | Measure-Object).Count -gt 0)
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
					$this.ComplianceReportHelper.StoreComplianceDataInUserSubscription($result)
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
		[ListenerHelper]::RegisterListeners();
		
		return $result;
	}

	hidden [SVTEventContext[]] RunAllControls()
	{
		return $this.RunForSubscription("EvaluateAllControls")
	}
	hidden [SVTEventContext[]] FetchAttestationInfo()
	{
		return $this.RunForSubscription("FetchStateOfAllControls")
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
		if ($null -ne $baselineControlsDetails -and ($baselineControlsDetails.SubscriptionControlIdList | Measure-Object).Count -gt 0 -and ($baselineControlsDetails.SupportedSources -contains $scanSource -or $this.UseBaselineControls))
		{
			
			#$this.PublishCustomMessage("Running cmdlet with baseline resource types and controls.", [MessageType]::Warning);
			#Get the list of baseline control ids
			$controlIds = $baselineControlsDetails.SubscriptionControlIdList
			$baselineControlIds = [system.String]::Join(",",$controlIds);		
			if(-not [system.String]::IsNullOrEmpty($baselineControlIds))
			{
				$this.ControlIds = $controlIds;			
			}
		}
	}	
}
