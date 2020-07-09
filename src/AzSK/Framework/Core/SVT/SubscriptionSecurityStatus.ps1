Set-StrictMode -Version Latest 
class SubscriptionSecurityStatus: AzSVTCommandBase
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
			$this.Severity = $this.ConvertToStringArray($this.Severity) # to handle case when no severity is passed to command
			if($this.Severity)
			{
				$this.Severity = [ControlHelper]::CheckValidSeverities($this.Severity);				
				 
			}
			$this.SetSVTBaseProperties($svtObject);
			$result += $svtObject.$methodNameToCall();	
			#$this.FetchRBACTelemetry($svtObject);
			[CustomData] $customData = [CustomData]::new();
			$customData.Name = "SubSVTObject";
			$customData.Value = $svtObject;
			$this.PublishCustomData($customData);	

			try
			{
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
			catch
			{
				#eat the exception
				Write-Warning "Could not post additional ASC telemetry data...`r`nPlease ignore for now if the cmdlet ran successfully."
			}
		}

		#save result into local compliance report
		# Changes for compliance table dependency removal
		# if IsComplianceStateCachingEnabled is false, do not persist scan result in compliance state table
		if($this.IsComplianceStateCachingEnabled)
		{
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
						$this.ComplianceReportHelper.StoreComplianceDataInUserSubscription($result);
						
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
		[AzListenerHelper]::RegisterListeners();
		
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
	hidden [SVTEventContext[]] ScanAttestedControls()
	{
		return $this.RunForSubscription("RescanAndPostAttestationData")
	}
	#BaseLineControlFilter Function
	[void] BaselineFilterCheck()
	{
		
		#Check if use baseline or preview baseline flag is passed as parameter
		if($this.UseBaselineControls -or $this.UsePreviewBaselineControls)
		{
			#Load ControlSetting file
			$ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");

			$baselineControlsDetails = $ControlSettings.BaselineControls
			#if baselineControls switch is available and baseline controls available in settings
			if ($null -ne $baselineControlsDetails -and ($baselineControlsDetails.SubscriptionControlIdList | Measure-Object).Count -gt 0 -and  $this.UseBaselineControls)
			{
				
				#$this.PublishCustomMessage("Running cmdlet with baseline resource types and controls.", [MessageType]::Warning);
				#Get the list of baseline control ids
				$controlIds = $baselineControlsDetails.SubscriptionControlIdList
				$baselineControlIds = [system.String]::Join(",",$controlIds);		
				if(-not [system.String]::IsNullOrEmpty($baselineControlIds))
				{
					#Assign baseline control list to ControlIds filter parameter. This controls gets filtered during scan.
					$this.ControlIds = $controlIds;			
				}
			}
			#If baseline switch is passed and there is no baseline control list present then throw exception 
			elseif (($baselineControlsDetails.SubscriptionControlIdList | Measure-Object).Count -eq 0 -and $this.UseBaselineControls) 
			{
				throw ([SuppressedException]::new(("There are no baseline controls defined for your org. No controls will be scanned."), [SuppressedExceptionType]::Generic))
			}

			$previewBaselineControlsDetails = $ControlSettings.PreviewBaselineControls
			#If Scan source is in supported sources or baselineControls switch is available
			if ($null -ne $previewBaselineControlsDetails -and ($previewBaselineControlsDetails.SubscriptionControlIdList | Measure-Object).Count -gt 0 -and  $this.UsePreviewBaselineControls)
			{
				#Get the list of baseline control ids
				$controlIds = $previewBaselineControlsDetails.SubscriptionControlIdList
				$previewBaselineControlIds = [system.String]::Join(",",$controlIds);		
				if(-not [system.String]::IsNullOrEmpty($previewBaselineControlIds))
				{
					#Assign preview control list to ControlIds filter parameter. This controls gets filtered during scan.
					$this.ControlIds += $controlIds;			
				}
			}
			#If preview baseline switch is passed and there is no baseline control list present then throw exception 
			elseif (($previewBaselineControlsDetails.SubscriptionControlIdList | Measure-Object).Count -eq 0 -and $this.UsePreviewBaselineControls) 
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
	}	

	
	
}
