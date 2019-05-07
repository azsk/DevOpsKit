Set-StrictMode -Version Latest 
Class LogAnalyticsHelper
{
	static [string] $DefaultLAWType = "AzSK"
	hidden static [int] $IsLAWSettingValid = 0  #-1:Fail (Log Analytics workspace Empty, Log Analytics workspace Return Error) | 1:CA | 0:Local
	hidden static [int] $IsAltLAWSettingValid = 0

	# Create the function to create and post the request
	static PostLAWData([string] $workspaceId, [string] $sharedKey, $body, $logType, $lawType)
	{
		try
		{
			if(($lawType | Measure-Object).Count -gt 0 -and [LogAnalyticsHelper]::$("is" + $lawType + "SettingValid") -ne -1)
			{
				if([string]::IsNullOrWhiteSpace($logType))
				{
					$logType = [LogAnalyticsHelper]::DefaultLAWType
				}
				[string] $method = "POST"
				[string] $contentType = "application/json"
				[string] $resource = "/api/logs"
				$rfc1123date = [System.DateTime]::UtcNow.ToString("r")
				[int] $contentLength = $body.Length
				[string] $signature = [LogAnalyticsHelper]::GetLAWSignature($workspaceId, $SharedKey, $rfc1123date, $contentLength, $method, $contentType, $resource)
				[string] $uri = "https://" + $workspaceId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"
				[DateTime] $timeStampField = [System.DateTime]::UtcNow
				$headers = @{
					"Authorization" = $signature;
					"Log-Type" = $logType;
					"x-ms-date" = $rfc1123date;
					"time-generated-field" = $timeStampField;
				}

				#response not being used??
				$response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
			}
		}
		catch
		{
			$warningMessage=""
			if($lawType -eq 'LAW' -or $lawType -eq 'AltLAW')
			{	
				switch([LogAnalyticsHelper]::$("is" + $lawType + "SettingValid"))
				{
					0 { $warningMessage += "The $($lawType) workspace id or key is invalid in the local settings file. You can use Set-AzSKMonitoringSettings with correct values to update it.";}
					1 { $warningMessage += "The $($lawType) workspace id or key is invalid in the ContinuousAssurance configuration. You can use Update-AzSKContinuousAssurance with the correct Log Analytics workspace values to correct it."; }
				}
				[EventBase]::PublishGenericCustomMessage(" `r`nWARNING: $($warningMessage)", [MessageType]::Warning);
				
				#Flag to disable Log Analytics scan 
				[LogAnalyticsHelper]::$("is" + $lawType + "SettingValid") = -1
			}
		}
	}

	static [string] GetLAWSignature ($workspaceId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
	{
		[string] $xHeaders = "x-ms-date:" + $date
		[string] $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource
		
		[byte[]]$bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
		[byte[]]$keyBytes = [Convert]::FromBase64String($sharedKey)
		
		[System.Security.Cryptography.HMACSHA256] $sha256 = New-Object System.Security.Cryptography.HMACSHA256
		$sha256.Key = $keyBytes
		[byte[]]$calculatedHash = $sha256.ComputeHash($bytesToHash)
		$encodedHash = [Convert]::ToBase64String($calculatedHash)
		$authorization = 'SharedKey {0}:{1}' -f $workspaceId,$encodedHash
		return $authorization
	}

	static [PSObject[]] GetLAWBodyObjects([SVTEventContext] $eventContext, [AzSKContextDetails] $azskContext)
	{
		[PSObject[]] $output = @();
		[array] $eventContext.ControlResults | ForEach-Object{
			Set-Variable -Name controlResult -Value $_ -Scope Local
			$out = [LogAnalyticsModel]::new()
			if($eventContext.IsResource())
			{
				$out.ResourceType = $eventContext.ResourceContext.ResourceType
				$out.ResourceGroup = $eventContext.ResourceContext.ResourceGroupName			
				$out.ResourceName = $eventContext.ResourceContext.ResourceName
				$out.ResourceId = $eventContext.ResourceContext.ResourceId
				$out.ChildResourceName = $controlResult.ChildResourceName
				$out.PartialScanIdentifier = $eventContext.PartialScanIdentifier
			}
			
			$out.Reference = $eventContext.Metadata.Reference
			$out.ControlStatus = $controlResult.VerificationResult.ToString()
			$out.ActualVerificationResult = $controlResult.ActualVerificationResult.ToString()
			$out.ControlId = $eventContext.ControlItem.ControlID
			$out.SubscriptionName = $eventContext.SubscriptionContext.SubscriptionName
			$out.SubscriptionId = $eventContext.SubscriptionContext.SubscriptionId
			$out.FeatureName = $eventContext.FeatureName
			$out.Recommendation = $eventContext.ControlItem.Recommendation
			$out.ControlSeverity = $eventContext.ControlItem.ControlSeverity.ToString()
			$out.Source = $azskContext.Source
			$out.Tags = $eventContext.ControlItem.Tags
			$out.RunIdentifier = $azskContext.RunIdentifier
			$out.HasRequiredAccess = $controlResult.CurrentSessionContext.Permissions.HasRequiredAccess 
			$out.ScannerVersion = $azskContext.Version
			$out.IsBaselineControl = $eventContext.ControlItem.IsBaselineControl
			#addPreviewBaselineControl Flag
			$out.IsPreviewBaselineControl = $eventContext.ControlItem.IsPreviewBaselineControl
			$out.HasAttestationWritePermissions = $controlResult.CurrentSessionContext.Permissions.HasAttestationWritePermissions
			$out.HasAttestationReadPermissions = $controlResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions				
			$out.IsLatestPSModule = $controlResult.CurrentSessionContext.IsLatestPSModule
			$out.PolicyOrgName = $azskContext.PolicyOrgName
			$out.IsControlInGrace = $controlResult.IsControlInGrace
			$out.ScannedBy = [Helpers]::GetCurrentRMContext().Account
			#mapping the attestation properties
			if($null -ne $controlResult -and $null -ne $controlResult.StateManagement -and $null -ne $controlResult.StateManagement.AttestedStateData)
			{
				$attestedData = $controlResult.StateManagement.AttestedStateData;
				$out.AttestationStatus = $controlResult.AttestationStatus.ToString();
				$out.AttestedBy = $attestedData.AttestedBy;
				$out.Justification = $attestedData.Justification;
				$out.AttestedDate = $attestedData.AttestedDate
				$out.ExpiryDate = $attestedData.ExpiryDate
			}
			$output += $out
		}
		return $output	
	}
	
	static [void] PostApplicableControlSet([SVTEventContext[]] $contexts, [AzSKContextDetails] $azskContext) {
		if (($contexts | Measure-Object).Count -lt 1)
		{
			return;
		}
        $set = [LogAnalyticsHelper]::ConvertToSimpleSet($contexts, $azskContext);
        [LogAnalyticsHelper]::WriteControlResult($set,"AzSK_Inventory")		
	}
	
	static [void] WriteControlResult([PSObject[]] $lawDataObject, [string] $lawEventType)
	{
		try
		{
			$settings = [ConfigurationManager]::GetAzSKSettings()
			if([string]::IsNullOrWhiteSpace($lawEventType))
			{
				$lawEventType = $settings.LAWType
			}

			if((-not [string]::IsNullOrWhiteSpace($settings.LAWorkspaceId)) -or (-not [string]::IsNullOrWhiteSpace($settings.AltLAWorkspaceId)))
			{
				$lawDataObject | ForEach-Object{
					Set-Variable -Name tempBody -Value $_ -Scope Local
					$body = $tempBody | ConvertTo-Json
					$lawBodyByteArray = ([System.Text.Encoding]::UTF8.GetBytes($body))
					#publish to primary workspace
					if(-not [string]::IsNullOrWhiteSpace($settings.LAWorkspaceId) -and [LogAnalyticsHelper]::IsLAWSettingValid -ne -1)
					{
						[LogAnalyticsHelper]::PostLAWData($settings.LAWorkspaceId, $settings.LAWSharedKey, $lawBodyByteArray, $lawEventType, 'LAW')
					}
					#publish to secondary workspace
					if(-not [string]::IsNullOrWhiteSpace($settings.AltLAWorkspaceId) -and [LogAnalyticsHelper]::IsAltLAWSettingValid -ne -1)
					{
						[LogAnalyticsHelper]::PostLAWData($settings.AltLAWorkspaceId, $settings.AltLAWSharedKey, $lawBodyByteArray, $lawEventType, 'AltLAW')
					}				
				}            
			}
		}
		catch
		{			
			throw ([SuppressedException]::new("Error sending events to Log Analytics. The following exception occurred: `r`n$($_.Exception.Message) `r`nFor more on AzSK Log Analytics workspace setup, refer: https://aka.ms/devopskit/ca"));
		}
	}

	static [PSObject[]] ConvertToSimpleSet($contexts, [AzSKContextDetails] $azskContext)
	{
		$controlSet = [System.Collections.ArrayList]::new()
		foreach ($item in $contexts) {
			$set = [LAWResourceInvModel]::new()
			$set.RunIdentifier = $azskContext.RunIdentifier
			$set.SubscriptionId = $item.SubscriptionContext.SubscriptionId
			$set.SubscriptionName = $item.SubscriptionContext.SubscriptionName
			$set.Source = $azskContext.Source
			$set.ScannerVersion = $azskContext.Version
			$set.FeatureName = $item.FeatureName
			if([Helpers]::CheckMember($item,"ResourceContext"))
			{
				$set.ResourceGroupName = $item.ResourceContext.ResourceGroupName
				$set.ResourceName = $item.ResourceContext.ResourceName
				$set.ResourceId = $item.ResourceContext.ResourceId
            }
			$set.ControlIntId = $item.ControlItem.Id
            $set.ControlId = $item.ControlItem.ControlID
            $set.ControlSeverity = $item.ControlItem.ControlSeverity
			$set.Tags = $item.ControlItem.Tags
			$set.IsBaselineControl = $item.ControlItem.IsBaselineControl
			#add PreviewBaselineFlag
			$set.IsPreviewBaselineControl = $item.ControlItem.IsPreviewBaselineControl
			$controlSet.Add($set) 
        }
        return $controlSet;
	}
	
	static [void] SetLAWDetails()
	{
		#Check if Settings already contain details of Log Analytics workspace
		$settings = [ConfigurationManager]::GetAzSKSettings()
		#Step 1: if Log Analytics workspace details are not present on machine
		if([string]::IsNullOrWhiteSpace($settings.LAWorkspaceId) -or [string]::IsNullOrWhiteSpace($settings.AltLAWorkspaceId))
		{
			$rgName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
			#Step 2: Validate if CA is enabled on subscription
			$automationAccountDetails= Get-AzAutomationAccount -ResourceGroupName $rgName -ErrorAction SilentlyContinue 
			if($automationAccountDetails)
			{
				if([string]::IsNullOrWhiteSpace($settings.LAWorkspaceId))
				{
					#Step 3: Get workspace id from automation account variables
					#$workspaceId = Get-AzAutomationVariable -ResourceGroupName $automationAccountDetails.ResourceGroupName -AutomationAccountName $automationAccountDetails.AutomationAccountName -Name "LAWorkspaceId" -ErrorAction SilentlyContinue
					$workspaceId = Get-AzAutomationVariable -ResourceGroupName $automationAccountDetails.ResourceGroupName -AutomationAccountName $automationAccountDetails.AutomationAccountName -Name "OMSWorkspaceId" -ErrorAction SilentlyContinue
					#Step 4: set workspace id and shared key in settings file
					if($workspaceId)
					{
						#$sharedKey = Get-AzAutomationVariable -ResourceGroupName $automationAccountDetails.ResourceGroupName -AutomationAccountName $automationAccountDetails.AutomationAccountName -Name "LAWSharedKey"
						$sharedKey = Get-AzAutomationVariable -ResourceGroupName $automationAccountDetails.ResourceGroupName -AutomationAccountName $automationAccountDetails.AutomationAccountName -Name "OMSSharedKey"
						if([Helpers]::CheckMember($sharedKey,"Value") -and (-not [string]::IsNullOrWhiteSpace($sharedKey.Value)))
						{
							#Step 6: Assign it to AzSKSettings Object
							$settings.LAWorkspaceId = $workspaceId.Value
							$settings.LAWSharedKey = $sharedKey.Value
							[LogAnalyticsHelper]::IsLAWSettingValid = 1
						}
					}
				}

				if([string]::IsNullOrWhiteSpace($settings.LAWorkspaceId) -or [string]::IsNullOrWhiteSpace($settings.LAWSharedKey))
				{
					[LogAnalyticsHelper]::IsLAWSettingValid = -1
				}
				
				if([string]::IsNullOrWhiteSpace($settings.AltLAWorkspaceId))
				{
					#Step 3: Get workspace id from automation account variables
					#$altWorkspaceId = Get-AzAutomationVariable -ResourceGroupName $automationAccountDetails.ResourceGroupName -AutomationAccountName $automationAccountDetails.AutomationAccountName -Name "AltLAWorkspaceId" -ErrorAction SilentlyContinue
					$altWorkspaceId = Get-AzAutomationVariable -ResourceGroupName $automationAccountDetails.ResourceGroupName -AutomationAccountName $automationAccountDetails.AutomationAccountName -Name "AltOMSWorkspaceId" -ErrorAction SilentlyContinue
					#Step 4: set alt workspace id and alt shared key in settings file
					if($altWorkspaceId)
					{
						#$altSharedKey = Get-AzAutomationVariable -ResourceGroupName $automationAccountDetails.ResourceGroupName -AutomationAccountName $automationAccountDetails.AutomationAccountName -Name "AltLAWSharedKey"
						$altSharedKey = Get-AzAutomationVariable -ResourceGroupName $automationAccountDetails.ResourceGroupName -AutomationAccountName $automationAccountDetails.AutomationAccountName -Name "AltOMSSharedKey"
						if([Helpers]::CheckMember($altSharedKey,"Value") -and (-not [string]::IsNullOrWhiteSpace($altSharedKey.Value)))
						{
							#Step 6: Assign it to AzSKSettings Object
							$settings.AltLAWorkspaceId = $altWorkspaceId.Value
							$settings.AltLAWSharedKey = $altSharedKey.Value
							[LogAnalyticsHelper]::IsAltLAWSettingValid = 1
						}
					}
				}
				
				if([string]::IsNullOrWhiteSpace($settings.AltLAWorkspaceId) -or [string]::IsNullOrWhiteSpace($settings.AltLAWSharedKey))
				{
					[LogAnalyticsHelper]::IsAltLAWSettingValid = -1
				}				
			}
		}		
	}

	static PostResourceInventory([AzSKContextDetails] $azskContext)
	{
		if($azskContext.Source.Equals("CC", [System.StringComparison]::OrdinalIgnoreCase) -or
		$azskContext.Source.Equals("CA", [System.StringComparison]::OrdinalIgnoreCase))
		{
			$resourceSet = [System.Collections.ArrayList]::new()
			[ResourceInventory]::FetchResources();
			foreach($resource in [ResourceInventory]::FilteredResources)
			{
				$set = [LAWResourceModel]::new()
				$set.RunIdentifier = $azskContext.RunIdentifier
				$set.SubscriptionId = $resource.SubscriptionId
				$set.Source = $azskContext.Source
				$set.ScannerVersion = $azskContext.Version
				$set.ResourceType = $resource.ResourceType				
				$set.ResourceGroupName = $resource.ResourceGroupName
				$set.ResourceName = $resource.Name
				$set.ResourceId = $resource.ResourceId
			
				$resourceSet.Add($set)
			}
			[LogAnalyticsHelper]::WriteControlResult($resourceSet,"AzSK_Inventory")
			$lawMetadata = [ConfigurationManager]::LoadServerConfigFile("LogAnalyticsSettings.json")
			[LogAnalyticsHelper]::WriteControlResult($lawMetadata,"AzSK_MetaData")
		}			
	}

	###~Not used anywhere~###
	hidden static [PSObject] QueryStatusfromWorkspace([string] $workspaceId,[string] $query)
	{
		$result = $null;
		try
		{
			$body = @{query=$query};
			$url="https://api.loganalytics.io/beta/workspaces/" + $workspaceId + "/api/query?api-version=2017-01-01-preview"
			$response=[WebRequestHelper]::InvokePostWebRequest($url ,  $body);

			# Formating the response obtained from querying workspace.
			if(($response | Measure-Object).Count -gt 0)
			{
				$data = $response;				
				#Out of four tables obtained, the first table contains result of query
				if(($data | Measure-Object).Count -gt 0)
				{
					$table= $data.Tables[0];
					$Columns=$table.Columns;
					$objectView = @{};		
					$j = 0;
					if($null -ne $table)
					{
						foreach ($valuetable in $table)
						{
							foreach ($row in $table.Rows)
							{
								$i = 0;
								$count=$valuetable.Columns.Count;
								$properties = @{}            
								foreach($col in $Columns)
								{
									if($i -lt  $count)
									{
										$properties[$col.ColumnName] = $row[$i];
									}
									$i++;
								}
								$objectView[$j] = (New-Object PSObject -Property $properties)
								$j++;
							}
						}
						$result=$objectView;
					}
				}
			}
		}
		catch
		{
			[EventBase]::PublishGenericCustomMessage($_)
		}
		return $result;		
	}
}

Class LogAnalyticsModel
{
	[string] $RunIdentifier
	[string] $ResourceType 
	[string] $ResourceGroup 
	[string] $Reference
	[string] $ResourceName 
	[string] $ChildResourceName 
	[string] $ResourceId
	[string] $ControlStatus 
	[string] $ActualVerificationResult 
	[string] $ControlId 
	[string] $SubscriptionName 
	[string] $SubscriptionId 
	[string] $FeatureName 
	[string] $Source 
	[string] $Recommendation 
	[string] $ControlSeverity 
	[string] $TimeTakenInMs 
	[string] $AttestationStatus 
	[string] $AttestedBy 
	[string] $Justification 
	[string] $AttestedDate
	[bool] $HasRequiredAccess
	[bool] $HasAttestationWritePermissions
	[bool] $HasAttestationReadPermissions
	[bool] $IsLatestPSModule
	[bool] $IsControlInGrace
	[string[]] $Tags
	[string] $ScannerVersion
	[bool] $IsBaselineControl
	#add PreviewBaselineFlag
	[bool] $IsPreviewBaselineControl
	[string] $ExpiryDate
	[string] $PartialScanIdentifier
	[string] $PolicyOrgName
	[string] $ScannedBy
}

Class LAWResourceInvModel
{
	[string] $RunIdentifier
	[string] $SubscriptionId
	[string] $SubscriptionName
	[string] $Source
	[string] $ScannerVersion
	[string] $FeatureName
	[string] $ResourceGroupName
	[string] $ResourceName
	[string] $ResourceId
	[string] $ControlId
	[string] $ControlIntId
	[string] $ControlSeverity
	[string[]] $Tags
	[bool] $IsBaselineControl
	#add PreviewBaselineFlag
	[bool] $IsPreviewBaselineControl
}

Class LAWResourceModel
{
	[string] $RunIdentifier
	[string] $SubscriptionId
	[string] $Source
	[string] $ScannerVersion
	[string] $ResourceType
	[string] $ResourceGroupName
	[string] $ResourceName
	[string] $ResourceId
}

Class AzSKContextDetails
{
	[string] $RunIdentifier
	[string] $Version
	[string] $Source
	[string] $PolicyOrgName
}

Class CommandModel
{
	[string] $EventName
	[string] $RunIdentifier
	[string] $PartialScanIdentifier
	[string] $ModuleVersion
	[string] $MethodName
	[string] $ModuleName
	[string] $Parameters
	[string] $SubscriptionId
	[string] $SubscriptionName
}