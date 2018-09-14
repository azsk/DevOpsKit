Set-StrictMode -Version Latest 
Class OMSHelper{
	static [string] $DefaultOMSType = "AzSK"
	hidden static [int] $isOMSSettingValid = 0  #-1:Fail (OMS Empty, OMS Return Error) | 1:CA | 0:Local
	hidden static [int] $isAltOMSSettingValid = 0
	# Create the function to create and post the request
	static PostOMSData([string] $OMSWorkspaceID, [string] $SharedKey, $Body, $LogType, $OMSType)
	{
		try
		{
			if(($OMSType | Measure-Object).Count -gt 0 -and [OMSHelper]::$("is"+$OMSType+"SettingValid") -ne -1)
			{
				if([string]::IsNullOrWhiteSpace($LogType))
				{
					$LogType = [OMSHelper]::DefaultOMSType
				}
				[string] $method = "POST"
				[string] $contentType = "application/json"
				[string] $resource = "/api/logs"
				$rfc1123date = [System.DateTime]::UtcNow.ToString("r")
				[int] $contentLength = $Body.Length
				[string] $signature = [OMSHelper]::GetOMSSignature($OMSWorkspaceID , $SharedKey , $rfc1123date ,$contentLength ,$method ,$contentType ,$resource)
				[string] $uri = "https://" + $OMSWorkspaceID + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"
				[DateTime] $TimeStampField = [System.DateTime]::UtcNow
				$headers = @{
					"Authorization" = $signature;
					"Log-Type" = $LogType;
					"x-ms-date" = $rfc1123date;
					"time-generated-field" = $TimeStampField;
				}
				$response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $Body -UseBasicParsing
			}
		}
		catch
		{
			$warningMsg=""
			if($OMSType -eq 'OMS' -or $OMSType -eq 'AltOMS')
			{	
				switch([OMSHelper]::$("is"+$OMSType+"SettingValid"))
				{
					0 { $warningMsg += "The $($OMSType) workspace id or key is invalid in the local settings file. You can use Set-AzSKOMSSettings with correct values to update it.";}
					1 { $warningMsg += "The $($OMSType) workspace id or key is invalid in the ContinuousAssurance configuration. You can use Update-AzSKContinuousAssurance with the correct OMS values to correct it."; }
				}
				[EventBase]::PublishGenericCustomMessage(" `r`nWARNING: $($warningMsg)", [MessageType]::Warning);
				
				#Flag to disable OMS scan 
				[OMSHelper]::$("is"+$OMSType+"SettingValid") = -1
			}
		}
	}

	static [string] GetOMSSignature ($OMSWorkspaceID, $SharedKey, $Date, $ContentLength, $Method, $ContentType, $Resource)
	{
			[string] $xHeaders = "x-ms-date:" + $Date
			[string] $stringToHash = $Method + "`n" + $ContentLength + "`n" + $ContentType + "`n" + $xHeaders + "`n" + $Resource
        
			[byte[]]$bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
			
			[byte[]]$keyBytes = [Convert]::FromBase64String($SharedKey)

			[System.Security.Cryptography.HMACSHA256] $sha256 = New-Object System.Security.Cryptography.HMACSHA256
			$sha256.Key = $keyBytes
			[byte[]]$calculatedHash = $sha256.ComputeHash($bytesToHash)
			$encodedHash = [Convert]::ToBase64String($calculatedHash)
			$authorization = 'SharedKey {0}:{1}' -f $OMSWorkspaceID,$encodedHash
			return $authorization   
	}

	static [PSObject[]] GetOMSBodyObjects([SVTEventContext] $eventContext,[AzSKContextDetails] $AzSKContext)
	{
		[PSObject[]] $output = @();		
		[array] $eventContext.ControlResults | ForEach-Object{
			Set-Variable -Name ControlResult -Value $_ -Scope Local
			$out = [OMSModel]::new() 
			if($eventContext.IsResource())
			{
				$out.ResourceType=$eventContext.ResourceContext.ResourceType
				$out.ResourceGroup=$eventContext.ResourceContext.ResourceGroupName			
				$out.ResourceName=$eventContext.ResourceContext.ResourceName
				$out.ResourceId = $eventContext.ResourceContext.ResourceId
				$out.ChildResourceName=$ControlResult.ChildResourceName
				$out.PartialScanIdentifier=$eventContext.PartialScanIdentifier
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
			$out.HasAttestationWritePermissions = $ControlResult.CurrentSessionContext.Permissions.HasAttestationWritePermissions
			$out.HasAttestationReadPermissions = $ControlResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions				
			$out.IsLatestPSModule = $ControlResult.CurrentSessionContext.IsLatestPSModule
			$out.PolicyOrgName =$AzSKContext.PolicyOrgName
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
        $set = [OMSHelper]::ConvertToSimpleSet($contexts,$AzSKContext);
        [OMSHelper]::WriteControlResult($set,"AzSK_Inventory")
		#$omsMetadata = [ConfigurationManager]::LoadServerConfigFile("OMSSettings.json")
		#[OMSHelper]::WriteControlResult($omsMetadata,"AzSK_MetaData")		
    }

	static [void] WriteControlResult([PSObject[]] $omsDataObject, [string] $OMSEventType)
	{
		try
		{
			$settings = [ConfigurationManager]::GetAzSKSettings()
			if([string]::IsNullOrWhiteSpace($OMSEventType))
			{
				$OMSEventType = $settings.OMSType
			}

			if((-not [string]::IsNullOrWhiteSpace($settings.OMSWorkspaceId)) -or (-not [string]::IsNullOrWhiteSpace($settings.AltOMSWorkspaceId)))
			{
				$omsDataObject | ForEach-Object{
					Set-Variable -Name tempBody -Value $_ -Scope Local
					$body = $tempBody | ConvertTo-Json
					$omsBodyByteArray = ([System.Text.Encoding]::UTF8.GetBytes($body))
					#publish to primary workspace
					if(-not [string]::IsNullOrWhiteSpace($settings.OMSWorkspaceId) -and [OMSHelper]::isOMSSettingValid -ne -1)
					{
						[OMSHelper]::PostOMSData($settings.OMSWorkspaceId, $settings.OMSSharedKey, $omsBodyByteArray, $OMSEventType, 'OMS')
					}
					#publish to secondary workspace
					if(-not [string]::IsNullOrWhiteSpace($settings.AltOMSWorkspaceId) -and [OMSHelper]::isAltOMSSettingValid -ne -1)
					{
						[OMSHelper]::PostOMSData($settings.AltOMSWorkspaceId, $settings.AltOMSSharedKey, $omsBodyByteArray, $OMSEventType, 'AltOMS')
					}				
				}            
			}
		}
		catch
		{			
			throw ([SuppressedException]::new("Error sending events to OMS. The following exception occurred: `r`n$($_.Exception.Message) `r`nFor more on AzSK OMS setup, refer: https://aka.ms/devopskit/ca"));
		}
	}

	static [PSObject[]] ConvertToSimpleSet($contexts,[AzSKContextDetails] $AzSKContext)
	{
        $ControlSet = [System.Collections.ArrayList]::new()
        foreach ($item in $contexts) {
			$set = [OMSResourceInvModel]::new()
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
            $ControlSet.Add($set) 
        }
        return $ControlSet;
	}
	
	static [void] SetOMSDetails()
	{
		#Check if Settings already contain details of OMS
		$settings = [ConfigurationManager]::GetAzSKSettings()
		#Step 1: if OMS details are not present on machine
		if([string]::IsNullOrWhiteSpace($settings.OMSWorkspaceId) -or [string]::IsNullOrWhiteSpace($settings.AltOMSWorkspaceId))
		{
			$rgName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName
			#Step 2: Validate if CA is enabled on subscription
			$automationAccDetails= Get-AzureRmAutomationAccount -ResourceGroupName $rgName -ErrorAction SilentlyContinue 
			if($automationAccDetails)
			{
				if([string]::IsNullOrWhiteSpace($settings.OMSWorkspaceId))
				{
					#Step 3: Get workspace id from automation account variables
					$omsWorkSpaceId = Get-AzureRmAutomationVariable -ResourceGroupName $automationAccDetails.ResourceGroupName -AutomationAccountName $automationAccDetails.AutomationAccountName -Name "OMSWorkspaceId" -ErrorAction SilentlyContinue
					#Step 4: set workspace id and share key in setting file
					if($omsWorkSpaceId)
					{
						$omsSharedKey = Get-AzureRmAutomationVariable -ResourceGroupName $automationAccDetails.ResourceGroupName -AutomationAccountName $automationAccDetails.AutomationAccountName -Name "OMSSharedKey"						
						if([Helpers]::CheckMember($omsSharedKey,"Value") -and (-not [string]::IsNullOrWhiteSpace($omsSharedKey.Value)))
						{
							#Step 6: Assign it to AzSKSettings Object
							$settings.OMSWorkspaceId = $omsWorkSpaceId.Value
							$settings.OMSSharedKey = $omsSharedKey.Value
							[OMSHelper]::isOMSSettingValid = 1
						}					

					}
				}

				if([string]::IsNullOrWhiteSpace($settings.OMSWorkspaceId) -or [string]::IsNullOrWhiteSpace($settings.OMSSharedKey))
				{
					[OMSHelper]::isOMSSettingValid = -1
				}


				if([string]::IsNullOrWhiteSpace($settings.AltOMSWorkspaceId))
				{
					#Step 3: Get workspace id from automation account variables
					$omsWorkSpaceId = Get-AzureRmAutomationVariable -ResourceGroupName $automationAccDetails.ResourceGroupName -AutomationAccountName $automationAccDetails.AutomationAccountName -Name "AltOMSWorkspaceId" -ErrorAction SilentlyContinue
					#Step 4: set workspace id and share key in setting file
					if($omsWorkSpaceId)
					{
						$omsSharedKey = Get-AzureRmAutomationVariable -ResourceGroupName $automationAccDetails.ResourceGroupName -AutomationAccountName $automationAccDetails.AutomationAccountName -Name "AltOMSSharedKey"						
						if([Helpers]::CheckMember($omsSharedKey,"Value") -and (-not [string]::IsNullOrWhiteSpace($omsSharedKey.Value)))
						{
							#Step 6: Assign it to AzSKSettings Object
							$settings.AltOMSWorkspaceId = $omsWorkSpaceId.Value
							$settings.AltOMSSharedKey = $omsSharedKey.Value
							[OMSHelper]::isAltOMSSettingValid = 1
						}
					}
				}
				
				if([string]::IsNullOrWhiteSpace($settings.AltOMSWorkspaceId) -or [string]::IsNullOrWhiteSpace($settings.AltOMSSharedKey))
				{
					[OMSHelper]::isAltOMSSettingValid = -1
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
				$set = [OMSResourceModel]::new()
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
			[OMSHelper]::WriteControlResult($resourceSet,"AzSK_Inventory")
			$omsMetadata = [ConfigurationManager]::LoadServerConfigFile("OMSSettings.json")
			[OMSHelper]::WriteControlResult($omsMetadata,"AzSK_MetaData")
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



Class OMSModel {
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
	[string[]] $Tags
	[string] $ScannerVersion
	[bool] $IsBaselineControl
	[string] $ExpiryDate
	[string] $PartialScanIdentifier
	[string] $PolicyOrgName
}

Class OMSResourceInvModel{
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
}

Class OMSResourceModel{
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