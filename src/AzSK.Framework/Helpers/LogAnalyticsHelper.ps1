Set-StrictMode -Version Latest 
Class LogAnalyticsHelper{
	static [string] $DefaultLAWType = "AzSK"
	hidden static [int] $IsLAWSettingValid = 0  #-1:Fail (Log Analytics workspace Empty, Log Analytics workspace Return Error) | 1:CA | 0:Local
	hidden static [int] $IsAltLAWSettingValid = 0
	# Create the function to create and post the request
	static PostLAWData([string] $workspaceId, [string] $sharedKey, $body, $logType, $lawType)
	{
		try
		{
			if(($lawType | Measure-Object).Count -gt 0 -and [LogAnalyticsHelper]::$("is"+$lawType+"SettingValid") -ne -1)
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
				[string] $signature = [LogAnalyticsHelper]::GetLAWSignature($workspaceId , $sharedKey , $rfc1123date ,$contentLength ,$method ,$contentType ,$resource)
				[string] $uri = "https://" + $workspaceId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"
				[DateTime] $TimeStampField = [System.DateTime]::UtcNow
				$headers = @{
					"Authorization" = $signature;
					"Log-Type" = $logType;
					"x-ms-date" = $rfc1123date;
					"time-generated-field" = $TimeStampField;
				}
				$response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
			}
		}
		catch
		{
			$warningMsg=""
			if($lawType -eq 'LAW' -or $lawType -eq 'AltLAW')
			{	
				switch([LogAnalyticsHelper]::$("is"+$lawType+"SettingValid"))
				{
					0 { $warningMsg += "The $($lawType) workspace id or key is invalid in the local settings file. You can use Set-AzSKMonitoringSettings with correct values to update it.";}
					1 { $warningMsg += "The $($lawType) workspace id or key is invalid in the ContinuousAssurance configuration. You can use Update-AzSKContinuousAssurance with the correct Log Analytics workspace values to correct it."; }
				}
				[EventBase]::PublishGenericCustomMessage(" `r`nWARNING: $($warningMsg)", [MessageType]::Warning);
				
				#Flag to disable Log Analytics scan 
				[LogAnalyticsHelper]::$("is"+$lawType+"SettingValid") = -1
			}
		}
	}

	static [string] GetLAWSignature ($workspaceId, $sharedKey, $Date, $ContentLength, $Method, $ContentType, $Resource)
	{
			[string] $xHeaders = "x-ms-date:" + $Date
			[string] $stringToHash = $Method + "`n" + $ContentLength + "`n" + $ContentType + "`n" + $xHeaders + "`n" + $Resource
        
			[byte[]]$bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
			
			[byte[]]$keyBytes = [Convert]::FromBase64String($sharedKey)

			[System.Security.Cryptography.HMACSHA256] $sha256 = New-Object System.Security.Cryptography.HMACSHA256
			$sha256.Key = $keyBytes
			[byte[]]$calculatedHash = $sha256.ComputeHash($bytesToHash)
			$encodedHash = [Convert]::ToBase64String($calculatedHash)
			$authorization = 'SharedKey {0}:{1}' -f $workspaceId,$encodedHash
			return $authorization   
	}

	static [PSObject[]] GetLAWBodyObjects([SVTEventContext] $eventContext,[AzSKContextDetails] $AzSKContext)
	{
		[PSObject[]] $output = @();		
		[array] $eventContext.ControlResults | ForEach-Object{
			Set-Variable -Name ControlResult -Value $_ -Scope Local
			$out = [LAWModel]::new() 
			if($eventContext.IsResource())
			{
				$out.ResourceType=$eventContext.ResourceContext.ResourceType
				$out.ResourceGroup=$eventContext.ResourceContext.ResourceGroupName			
				$out.ResourceName=$eventContext.ResourceContext.ResourceName
				$out.ResourceId = $eventContext.ResourceContext.ResourceId
				$out.ChildResourceName=$ControlResult.ChildResourceName
				$out.PartialScanIdentifier=$eventContext.PartialScanIdentifier

				#Send Log Analytics workspace telmetry for RG tags if feature is enabled and resource group tags are available
				try{
					if ([FeatureFlightingManager]::GetFeatureStatus("EnableResourceGroupTagTelemetry","*") -eq $true -and  $eventContext.ResourceContext.ResourceGroupTags.Count -gt 0) {
						# Try catch block for Env and ComponentId tags if tags throws exceptions in case of null objects
						try
						{
							$out.Env = $eventContext.ResourceContext.ResourceGroupTags[$eventContext.ResourceContext.ResourceGroupTags.Keys -match "\benv\b"]
						}
						catch
						{
							$out.Env = [string]::Empty;	
						}
						try
						{
							$out.ComponentId = $eventContext.ResourceContext.ResourceGroupTags[$eventContext.ResourceContext.ResourceGroupTags.Keys -match "\bcomponentid\b"]
						}
						catch{
							$out.ComponentId = [string]::Empty
						}
					}
				}
				catch{
					#Execution should not break if any excepiton in case of tag telemetry logging. <TODO: Add exception telemetry>
				}
			}

			$out.Reference=$eventContext.Metadata.Reference
			$out.ControlStatus=$ControlResult.VerificationResult.ToString()
			$out.ActualVerificationResult=$ControlResult.ActualVerificationResult.ToString()
			$out.ControlId=$eventContext.ControlItem.ControlID
			$out.SubscriptionName=$eventContext.SubscriptionContext.SubscriptionName
			$out.SubscriptionId=$eventContext.SubscriptionContext.SubscriptionId
			$out.FeatureName=$eventContext.FeatureName
			$out.Recommendation=$eventContext.ControlItem.Recommendation
			$out.ControlSeverity=$eventContext.ControlItem.ControlSeverity.ToString()
			$out.Source=$AzSKContext.Source
			$out.Tags=$eventContext.ControlItem.Tags
			$out.RunIdentifier = $AzSKContext.RunIdentifier
			$out.HasRequiredAccess = $ControlResult.CurrentSessionContext.Permissions.HasRequiredAccess 
			$out.ScannerVersion = $AzSKContext.Version
			$out.IsBaselineControl = $eventContext.ControlItem.IsBaselineControl
			#addPreviewBaselineControl Flag
			$out.IsPreviewBaselineControl = $eventContext.ControlItem.IsPreviewBaselineControl
			$out.HasAttestationWritePermissions = $ControlResult.CurrentSessionContext.Permissions.HasAttestationWritePermissions
			$out.HasAttestationReadPermissions = $ControlResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions				
			$out.IsLatestPSModule = $ControlResult.CurrentSessionContext.IsLatestPSModule
			$out.PolicyOrgName = $AzSKContext.PolicyOrgName
			$out.IsControlInGrace = $ControlResult.IsControlInGrace
			$out.ScannedBy=[Helpers]::GetCurrentRMContext().Account
			#mapping the attestation properties
			if($null -ne $ControlResult -and $null -ne $ControlResult.StateManagement -and $null -ne $ControlResult.StateManagement.AttestedStateData)
			{
				$attestedData = $ControlResult.StateManagement.AttestedStateData;
				$out.AttestationStatus = $ControlResult.AttestationStatus.ToString();
				$out.AttestedBy = $attestedData.AttestedBy;
				$out.Justification = $attestedData.Justification;
				$out.AttestedDate = $attestedData.AttestedDate
				$out.ExpiryDate = $attestedData.ExpiryDate
			}
			$output += $out
		}
		return $output	
	}

	static [void] PostApplicableControlSet([SVTEventContext[]] $contexts,[AzSKContextDetails] $AzSKContext) {
        if (($contexts | Measure-Object).Count -lt 1) { return; }
        $set = [LogAnalyticsHelper]::ConvertToSimpleSet($contexts,$AzSKContext);
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

	static [PSObject[]] ConvertToSimpleSet($contexts,[AzSKContextDetails] $AzSKContext)
	{
        $ControlSet = [System.Collections.ArrayList]::new()
        foreach ($item in $contexts) {
			$set = [LAWResourceInvModel]::new()
			$set.RunIdentifier = $AzSKContext.RunIdentifier
			$set.SubscriptionId = $item.SubscriptionContext.SubscriptionId
			$set.SubscriptionName = $item.SubscriptionContext.SubscriptionName
			$set.Source = $AzSKContext.Source
			$set.ScannerVersion = $AzSKContext.Version
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
			 $ControlSet.Add($set) 
        }
        return $ControlSet;
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
			$automationAccDetails= Get-AzAutomationAccount -ResourceGroupName $rgName -ErrorAction SilentlyContinue 
			if($automationAccDetails)
			{
				if([string]::IsNullOrWhiteSpace($settings.LAWorkspaceId))
				{
					#Step 3: Get workspace id from automation account variables
					$laWorkSpaceId = Get-AzAutomationVariable -ResourceGroupName $automationAccDetails.ResourceGroupName -AutomationAccountName $automationAccDetails.AutomationAccountName -Name "OMSWorkspaceId" -ErrorAction SilentlyContinue
					#Step 4: set workspace id and shared key in setting file
					if($laWorkSpaceId)
					{
						$lawSharedKey = Get-AzAutomationVariable -ResourceGroupName $automationAccDetails.ResourceGroupName -AutomationAccountName $automationAccDetails.AutomationAccountName -Name "OMSSharedKey"						
						if([Helpers]::CheckMember($lawSharedKey,"Value") -and (-not [string]::IsNullOrWhiteSpace($lawSharedKey.Value)))
						{
							#Step 6: Assign it to AzSKSettings Object
							$settings.LAWorkspaceId = $laWorkSpaceId.Value
							$settings.LAWSharedKey = $lawSharedKey.Value
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
					$altLAWorkSpaceId = Get-AzAutomationVariable -ResourceGroupName $automationAccDetails.ResourceGroupName -AutomationAccountName $automationAccDetails.AutomationAccountName -Name "AltOMSWorkspaceId" -ErrorAction SilentlyContinue
					#Step 4: set workspace id and shared key in setting file
					if($altLAWorkSpaceId)
					{
						$altLAWSharedKey = Get-AzAutomationVariable -ResourceGroupName $automationAccDetails.ResourceGroupName -AutomationAccountName $automationAccDetails.AutomationAccountName -Name "AltOMSSharedKey"						
						if([Helpers]::CheckMember($altLAWSharedKey,"Value") -and (-not [string]::IsNullOrWhiteSpace($altLAWSharedKey.Value)))
						{
							#Step 6: Assign it to AzSKSettings Object
							$settings.AltLAWorkspaceId = $altLAWorkSpaceId.Value
							$settings.AltLAWSharedKey = $altLAWSharedKey.Value
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

	static PostResourceInventory([AzSKContextDetails] $AzSKContext)
	{
		if($AzSKContext.Source.Equals("CC", [System.StringComparison]::OrdinalIgnoreCase) -or
		$AzSKContext.Source.Equals("CA", [System.StringComparison]::OrdinalIgnoreCase)){
			$resourceSet = [System.Collections.ArrayList]::new()
			[ResourceInventory]::FetchResources();
			foreach($resource in [ResourceInventory]::FilteredResources){
				$set = [LAWResourceModel]::new()
				$set.RunIdentifier = $AzSKContext.RunIdentifier
				$set.SubscriptionId = $resource.SubscriptionId
				#$set.SubscriptionName = $item.SubscriptionContext.SubscriptionName
				$set.Source = $AzSKContext.Source
				$set.ScannerVersion = $AzSKContext.Version
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

	hidden static [PSObject] QueryStatusfromWorkspace([string] $workspaceId,[string] $query)
	{
		$result=$null;
		try
		{
			$body = @{query=$query};
			$url="https://api.loganalytics.io/beta/workspaces/" +$workspaceId+"/api/query?api-version=2017-01-01-preview"
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
						foreach ($valuetable in $table) {
							foreach ($row in $table.Rows) {
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



Class LAWModel {
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
	[string] $Env
	[string] $ComponentId
}

Class LAWResourceInvModel{
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

Class LAWResourceModel{
	[string] $RunIdentifier
	[string] $SubscriptionId
	[string] $Source
	[string] $ScannerVersion
	[string] $ResourceType
	[string] $ResourceGroupName
	[string] $ResourceName
	[string] $ResourceId
}

Class AzSKContextDetails {
	[string] $RunIdentifier
	[string] $Version
	[string] $Source
	[string] $PolicyOrgName
	}

Class CommandModel{
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