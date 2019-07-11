Set-StrictMode -Version Latest 
class SubscriptionSecurityStatus: SVTCommandBase
{

	SubscriptionSecurityStatus([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext)
    { 
		$this.UseBaselineControls = $invocationContext.BoundParameters["UseBaselineControls"];
		$this.UsePreviewBaselineControls = $invocationContext.BoundParameters["UsePreviewBaselineControls"];
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

			if([FeatureFlightingManager]::GetFeatureStatus("EnableASCTelemetry",$($svtObject.SubscriptionContext.SubscriptionId)) -eq $true)
			{
				$scanSource = [RemoteReportHelper]::GetScanSource();
				if($scanSource -eq [ScanSource]::Runbook)
				{
					$secContacts = New-Object psobject -Property @{
						Phone = $svtObject.SecurityCenterInstance.ContactPhoneNumber;
						Email = $svtObject.SecurityCenterInstance.ContactEmail;
						AlertNotifications = $svtObject.SecurityCenterInstance.AlertNotifStatus;
						AlertsToAdmins = $svtObject.SecurityCenterInstance.AlertAdminStatus
					}
					[ASCTelemetryHelper]::ascData = [ASCTelemetryHelper]::new($svtObject.SubscriptionContext.SubscriptionId, $svtObject.SecurityCenterInstance.ASCTier, $svtObject.SecurityCenterInstance.AutoProvisioningSettings, $secContacts)
					[RemoteApiHelper]::PostASCTelemetry([ASCTelemetryHelper]::ascData)
				}	
			}
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
		elseif (($baselineControlsDetails.SubscriptionControlIdList | Measure-Object).Count -eq 0 -and $this.UseBaselineControls) 
		{
			throw ([SuppressedException]::new(("There are no baseline controls defined for this policy. No controls will be scanned."), [SuppressedExceptionType]::Generic))
		}

		$previewBaselineControlsDetails = $partialScanMngr.GetPreviewBaselineControlDetails()
		#If Scan source is in supported sources or baselineControls switch is available
		if ($null -ne $previewBaselineControlsDetails -and ($previewBaselineControlsDetails.SubscriptionControlIdList | Measure-Object).Count -gt 0 -and ($previewBaselineControlsDetails.SupportedSources -contains $scanSource -or $this.UsePreviewBaselineControls))
		{
			#Get the list of baseline control ids
			$controlIds = $previewBaselineControlsDetails.SubscriptionControlIdList
			$previewBaselineControlIds = [system.String]::Join(",",$controlIds);		
			if(-not [system.String]::IsNullOrEmpty($previewBaselineControlIds))
			{
				$this.ControlIds += $controlIds;			
			}
		}
		elseif (($previewBaselineControlsDetails.SubscriptionControlIdList | Measure-Object).Count -eq 0 -and $this.UsePreviewBaselineControls) 
		{
			throw ([SuppressedException]::new(("There are no preview baseline controls defined for this policy. No controls will be scanned."), [SuppressedExceptionType]::Generic))
		}
	}	
}
