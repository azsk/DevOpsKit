Set-StrictMode -Version Latest

class ComplianceReportHelper: ComplianceBase
{
    hidden [string] $ScanSource
	hidden [System.Version] $ScannerVersion
	hidden [string] $ScanKind
	static [ComplianceReportHelper] $Instance
	hidden [bool] $IsComplianceStateCachingEnabled
	
    ComplianceReportHelper([SubscriptionContext] $subscriptionContext,[System.Version] $ScannerVersion):
    Base([SubscriptionContext] $subscriptionContext) 
	{
		$this.ScanSource = [RemoteReportHelper]::GetScanSource();
		$this.ScannerVersion = $ScannerVersion
		$this.ScanKind = [ServiceScanKind]::Partial;
		$this.IsComplianceStateCachingEnabled = $this.ValidateComplianceStateCaching();
	}
	
	#Get cached instance for compliance. This is to avoid repeatative calls for base constructor which fetch details of AzSK resources on every resource
	static [ComplianceReportHelper] GetInstance([SubscriptionContext] $subscriptionContext,[System.Version] $ScannerVersion)
    {
        if ( $null -eq  [ComplianceReportHelper]::Instance)
        {
			[ComplianceReportHelper]::Instance = [ComplianceReportHelper]::new($subscriptionContext, $ScannerVersion)
		}
        return [ComplianceReportHelper]::Instance
    }
	#Function to check if ComplianceStateCaching tag is present on "AzSKRG" resource group
	#if this tag is missing, Compliance state table will not be used to store/fetch compliance data(default case)
	hidden [bool] ValidateComplianceStateCaching()
	{
		$AzSKConfigData = [ConfigurationManager]::GetAzSKConfigData()
		$tagsOnSub =  [ResourceGroupHelper]::GetResourceGroupTags($AzSKConfigData.AzSKRGName)
		if($tagsOnSub)
		{
			$ComplianceCacheTag = $tagsOnSub.GetEnumerator() | Where-Object {$_.Name -like "ComplianceStateCaching*"}
			if(($ComplianceCacheTag | Measure-Object).Count -gt 0)
			{
				$ComplianceCacheTagValue =$ComplianceCacheTag.Value		
				if(-not [string]::IsNullOrWhiteSpace($ComplianceCacheTagValue) -and  $ComplianceCacheTagValue -eq "true")
				{
					return $true
				}
			}			
		}
		return $false
	}

	hidden [ComplianceStateTableEntity[]] GetSubscriptionComplianceReport()
	{
		return $this.GetSubscriptionComplianceReport($null,$null);
	}

	hidden [ComplianceStateTableEntity[]] GetSubscriptionComplianceReport([string[]] $PartitionKeys)
	{		
		[ComplianceStateTableEntity[]] $finalResults = @();
		if($PartitionKeys.Length -gt 0)
		{
			$limit = 15;
			if($PartitionKeys.Length -le $limit)
			{
				$queryStringParam = $this.ConstructPartitionKeysFilterQueryString($PartitionKeys);
				return $this.GetSubscriptionComplianceReport($queryStringParam, $null);
			}
			else {
				$counter = 1;
				$subPartitionKeys = @();
				$totalCount = $PartitionKeys.Length;
				foreach($partitionKey in $PartitionKeys)
				{
					$subPartitionKeys += $partitionKey;
					if($counter % $limit -eq 0 -or $totalCount -eq $counter)
					{
						$queryStringParam = $this.ConstructPartitionKeysFilterQueryString($subPartitionKeys);
						$finalResults += $this.GetSubscriptionComplianceReport($queryStringParam, $null);
						$subPartitionKeys = @();						
					}
					$counter += 1;
				}						
			}
		}		
		return $finalResults;				
	}

	hidden [ComplianceStateTableEntity[]] GetSubscriptionComplianceReport($currentScanResults,$selectColumns)
	{
		$filterStringParams = "";
		$selectStringParams = "";
		$partitionKeys = @();
		if(($currentScanResults | Measure-Object).Count -gt 0)
		{
			$currentScanResults | ForEach-Object {
				$currentScanResult = $_;
				$resourceId = $currentScanResult.SubscriptionContext.Scope;
				if($currentScanResult.IsResource())
				{
					$resourceId = $currentScanResult.ResourceContext.ResourceId;
				}
				$controlsToProcess = @();
				if(($currentScanResult.ControlResults | Measure-Object).Count -gt 0)
				{	
					$controlsToProcess += $currentScanResult.ControlResults;
				}
				$controlsToProcess | ForEach-Object {
					$cScanResult = $_;												
					$currentResultHashId_p = [Helpers]::ComputeHash($resourceId.ToLower());
					$partitionKeys += $currentResultHashId_p;
				}
			}
			$partitionKeys = $partitionKeys | Select -Unique
			$filterStringParams = $this.ConstructPartitionKeysFilterQueryString($partitionKeys);			
		}
		if(($selectColumns | Measure-Object).Count -gt 0)
		{
			$selectStringParams =[String]::Join(",",$selectColumns)
		}
		return $this.GetSubscriptionComplianceReport($filterStringParams,$selectStringParams);
	}
    hidden [ComplianceStateTableEntity[]] GetSubscriptionComplianceReport([string] $filterStringParams, [string] $selectStringParams)
	{
		[ComplianceStateTableEntity[]] $complianceData = @()
		try
		{			
			$storageInstance = $this.azskStorageInstance;
			$TableName = $this.ComplianceTableName
			$AccountName = $storageInstance.StorageAccountName
			$AccessKey = $storageInstance.AccessKey 
			$queryStringParams = "?`$filter=IsActive%20eq%20true"
			if(-not [string]::IsNullOrWhiteSpace($filterStringParams))
			{
				$queryStringParams += "%20and%20(" + $filterStringParams + ")"
			}
			if(-not [string]::IsNullOrWhiteSpace($selectStringParams))
			{
				$queryStringParams += "&`$select=" + $selectStringParams;
			}

			$Uri="https://$AccountName.table.core.windows.net/$TableName()$queryStringParams"
			$Verb = "GET"
			$ContentMD5 = ""
			$ContentType = ""
			$Date = [DateTime]::UtcNow.ToString('r')
			$CanonicalizedResource = "/$AccountName/$TableName()"
			$SigningParts=@($Verb,$ContentMD5,$ContentType,$Date,$CanonicalizedResource)
			$StringToSign = [String]::Join("`n",$SigningParts)
			$sharedKey = [StorageHelper]::CreateStorageAccountSharedKey($StringToSign,$AccountName,$AccessKey)

			$xmsdate = $Date
			$headers = @{"Accept"="application/json";"x-ms-date"=$xmsdate;"Authorization"="SharedKey $sharedKey";"x-ms-version"="2018-03-28"}
			$tempComplianceData  = ([WebRequestHelper]::InvokeGetWebRequest($Uri,$headers)) 
			$newEntity = [ComplianceStateTableEntity]::new();
			$props = @();
			$item = $null;
			if(($tempComplianceData | Measure-Object).Count -gt 0)
			{
				$item = $tempComplianceData[0];
			}
			if($null -ne $item)
			{
				foreach($Property in $newEntity | Get-Member -type NoteProperty, Property)
				{
					if([Helpers]::CheckMember($item, $Property.Name, $false))
					{
						$props += $Property.Name
						
					}
					
				}
				if("IsControlInGrace" -notin $props)
				{
					$props += "IsControlInGrace"
				}
                if("IsPreviewBaselineControl" -notin $props)
				{
					$props += "IsPreviewBaselineControl"
				}
			
				if(($props | Measure-Object).Count -gt 0)
				{
					foreach($item in $tempComplianceData)
					{
						$newEntity = [ComplianceStateTableEntity]::new()
						foreach($Property in $props){
							if([Helpers]::CheckMember($item, $Property, $false))
							{
								$newEntity.$($Property) = $item.$($Property)
							}
						}
						if(-not [string]::IsNullOrWhiteSpace($newEntity.PartitionKey) -and -not [string]::IsNullOrWhiteSpace($newEntity.RowKey))
						{
							$complianceData+=$newEntity
						}						
					}
				}	
			}			
		}
		catch
		{
			Write-Host $_;
			return $null;
		}
		return $complianceData;		
    }     		
		
	hidden [ComplianceStateTableEntity] ConvertScanResultToSnapshotResult($currentSVTResult, $persistedSVTResult, $svtEventContext, $partitionKey, $rowKey, $resourceId)
	{
		[ComplianceStateTableEntity] $scanResult = $null;
		if($null -ne $persistedSVTResult)
		{
			$scanResult = $persistedSVTResult;
		}
		$isLegitimateResult = ($currentSVTResult.CurrentSessionContext.IsLatestPSModule -and $currentSVTResult.CurrentSessionContext.Permissions.HasRequiredAccess -and $currentSVTResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions -and $currentSVTResult.ActualVerificationResult -ne [VerificationResult]::Error -and $currentSVTResult.ActualVerificationResult -ne [VerificationResult]::Disabled)
		if($isLegitimateResult)
		{
			$controlItem = $svtEventContext.ControlItem;
			if($null -eq $scanResult)
			{
				$scanResult = [ComplianceStateTableEntity]::new();
				$scanResult.PartitionKey = $partitionKey;
				$scanResult.RowKey = $rowKey;		
			}						
			$scanResult.ResourceId = $resourceId;
			$scanResult.FeatureName = $svtEventContext.FeatureName; 
			if($svtEventContext.IsResource())
			{
				$scanResult.ResourceName = $svtEventContext.ResourceContext.ResourceName;
				$scanResult.ResourceGroupName = $svtEventContext.ResourceContext.ResourceGroupName;
			}
			if($scanResult.VerificationResult -ne $currentSVTResult.VerificationResult.ToString())
			{
				$scanResult.LastResultTransitionOn = [System.DateTime]::UtcNow.ToString("s");
				$scanResult.PreviousVerificationResult = $scanResult.VerificationResult;
			}
			
			if($scanResult.FirstScannedOn -eq [Constants]::AzSKDefaultDateTime -or ([datetime] $scanResult.FirstScannedOn) -gt ([datetime] $currentSVTResult.FirstScannedOn) )
			{
				if($currentSVTResult.FirstScannedOn -eq [Constants]::AzSKDefaultDateTime)
				{
					$scanResult.FirstScannedOn = [System.DateTime]::UtcNow.ToString("s");
				}
				else 
				{
					$scanResult.FirstScannedOn = (get-date $currentSVTResult.FirstScannedOn).ToString("s");
				}
			}

			if($scanResult.FirstFailedOn -eq [Constants]::AzSKDefaultDateTime -and $currentSVTResult.ActualVerificationResult -ne [VerificationResult]::Passed)
			{
				if($currentSVTResult.FirstFailedOn -eq [Constants]::AzSKDefaultDateTime)
				{
					$scanResult.FirstFailedOn = [System.DateTime]::UtcNow.ToString("s");
				}
				else 
				{
					$scanResult.FirstFailedOn = $currentSVTResult.FirstFailedOn.ToString("s");
				}
			}
			
			$scanResult.IsControlInGrace=$currentSVTResult.IsControlInGrace
			$scanResult.ScannedBy = [ContextHelper]::GetCurrentRMContext().Account
			$scanResult.ScanSource = $this.ScanSource
			$scanResult.ScannerVersion = $this.ScannerVersion
			#TODO check in the case sub control					
			$scanResult.ChildResourceName = $currentSVTResult.ChildResourceName 			
			$scanResult.ControlId = $controlItem.ControlId 			
			$scanResult.ControlIntId = $controlItem.Id 
			$scanResult.ControlSeverity = $controlItem.ControlSeverity.ToString()
			$scanResult.ActualVerificationResult = $currentSVTResult.ActualVerificationResult.ToString(); 
			$scanResult.AttestationStatus = $currentSVTResult.AttestationStatus.ToString();
			if($scanResult.AttestationStatus.ToString() -ne [AttestationStatus]::None -and $null -ne $currentSVTResult.StateManagement -and $null -ne $currentSVTResult.StateManagement.AttestedStateData)
			{
				if($scanResult.FirstAttestedOn -eq [Constants]::AzSKDefaultDateTime)
				{
					$scanResult.FirstAttestedOn = $currentSVTResult.StateManagement.AttestedStateData.AttestedDate.ToString("s");
				}

				if($currentSVTResult.StateManagement.AttestedStateData.AttestedDate -gt $scanResult.AttestedDate)
				{
					$scanResult.AttestationCounter = $scanResult.AttestationCounter + 1 
				}
				$scanResult.AttestedBy =  $currentSVTResult.StateManagement.AttestedStateData.AttestedBy
				$scanResult.AttestedDate = $currentSVTResult.StateManagement.AttestedStateData.AttestedDate.ToString("s");
				$scanResult.Justification = $currentSVTResult.StateManagement.AttestedStateData.Justification
			}
			else
			{
				$scanResult.AttestedBy = ""
				$scanResult.AttestedDate = [Constants]::AzSKDefaultDateTime.ToString("s") ;
				$scanResult.Justification = ""				
			}
			if($currentSVTResult.VerificationResult -ne [VerificationResult]::Manual)
			{
				$scanResult.VerificationResult = $currentSVTResult.VerificationResult
			}
			else {
				$scanResult.VerificationResult = $currentSVTResult.ActualVerificationResult.ToString();
			}
			$scanResult.ScannerModuleName = [Constants]::AzSKModuleName
			$scanResult.IsLatestPSModule = $currentSVTResult.CurrentSessionContext.IsLatestPSModule
			$scanResult.HasRequiredPermissions = $currentSVTResult.CurrentSessionContext.Permissions.HasRequiredAccess
			$scanResult.HasAttestationWritePermissions = $currentSVTResult.CurrentSessionContext.Permissions.HasAttestationWritePermissions
			$scanResult.HasAttestationReadPermissions = $currentSVTResult.CurrentSessionContext.Permissions.HasAttestationReadPermissions
			$scanResult.UserComments = $currentSVTResult.UserComments
			$scanResult.IsBaselineControl = $controlItem.IsBaselineControl
			$scanResult.IsPreviewBaselineControl = $controlItem.IsPreviewBaselineControl
			
			if($controlItem.Tags.Contains("OwnerAccess") -or $controlItem.Tags.Contains("GraphRead"))
			{
				$scanResult.HasOwnerAccessTag = $true
			}
			$scanResult.LastScannedOn = [DateTime]::UtcNow.ToString('s')
		}
						
		return $scanResult
	}

	#new functions	
	
	hidden [ComplianceStateTableEntity[]] MergeSVTScanResult($currentScanResults)
	{
		if($currentScanResults.Count -lt 1) { return $null}
		[ComplianceStateTableEntity[]] $finalScanData = @()
		#TODO
		$SVTEventContextFirst = $currentScanResults[0]

		#TODO get specific data
		$complianceReport = $this.GetSubscriptionComplianceReport($currentScanResults, $null);
		# $inActiveRecords = @();
		# $complianceReport | ForEach-Object { 
		# 	$record = $_;
		# 	if($_.RowKey -eq "EmptyResource")
		# 	{
		# 		$record.IsActive = $false;
		# 		$inActiveRecords += $record;
		# 	}
		# }
		$foundPersistedData = ($complianceReport | Measure-Object).Count -gt 0
		$currentScanResults | ForEach-Object {
			$currentScanResult = $_
			$resourceId = $currentScanResult.SubscriptionContext.Scope;
			if($currentScanResult.IsResource())
			{
				$resourceId = $currentScanResult.ResourceContext.ResourceId;
			}
			if($currentScanResult.FeatureName -ne "AzSKCfg")
			{
				$controlsToProcess = @();

				if(($currentScanResult.ControlResults | Measure-Object).Count -gt 0)
				{	
					$controlsToProcess += $currentScanResult.ControlResults;
				}
				
				$controlsToProcess | ForEach-Object {
					$cScanResult = $_;
					$partsToHash = $currentScanResult.ControlItem.Id;
					if(-not [string]::IsNullOrWhiteSpace($cScanResult.ChildResourceName))
					{
						$partsToHash = $partsToHash + ":" + $cScanResult.ChildResourceName;
					}
					$currentResultHashId_r = [Helpers]::ComputeHash($partsToHash.ToLower());
					$currentResultHashId_p = [Helpers]::ComputeHash($resourceId.ToLower());
					$persistedScanResult = $null;
					if($foundPersistedData)
					{
						$persistedScanResult = $complianceReport | Where-Object { $_.PartitionKey -eq $currentResultHashId_p -and $_.RowKey -eq $currentResultHashId_r }
						# if(($persistedScanResult | Measure-Object).Count -le 0)
						# {
						# 	$foundPersistedData = $false;
						# }				
					}
					$mergedScanResult = $this.ConvertScanResultToSnapshotResult($cScanResult, $persistedScanResult, $currentScanResult, $currentResultHashId_p, $currentResultHashId_r, $resourceId)
					if($null -ne $mergedScanResult)
					{
						$finalScanData += $mergedScanResult;
					}
				}
			}
		}
		# $finalScanData += $inActiveRecords;

		return $finalScanData
	}
	hidden [void] SetLocalSubscriptionScanReport([ComplianceStateTableEntity[]] $scanResultForStorage)
	{		
		$storageInstance = $this.azskStorageInstance;

		$groupedScanResultForStorage = $scanResultForStorage | Group-Object { $_.PartitionKey}
		$groupedScanResultForStorage | ForEach-Object {
			$group = $_;
			$results = $_.Group;
			#MERGE batch req sample
			[WebRequestHelper]::InvokeTableStorageBatchWebRequest($storageInstance.ResourceGroupName,$storageInstance.StorageAccountName,$this.ComplianceTableName,$results,$true, $storageInstance.AccessKey)
			#POST batch req sample
			#[WebRequestHelper]::InvokeTableStorageBatchWebRequest($storageInstance.ResourceGroupName,$storageInstance.StorageAccountName,$this.ComplianceTableName,$results,$false)
		}		
    }
	hidden [void] StoreComplianceDataInUserSubscription([SVTEventContext[]] $currentScanResult)
	{
		$finalScanReport = $this.MergeSVTScanResult($currentScanResult)
		$this.SetLocalSubscriptionScanReport($finalScanReport)
	}

	hidden [string] ConstructPartitionKeysFilterQueryString([string[]] $PartitionKeys)
	{
		if($PartitionKeys.Length -gt 0)
		{
			$template = "PartitionKey%20eq%20'{0}'";
			$tempQS = ""
			$havePartitionKeys = $false;
			$PartitionKeys | ForEach-Object {
				$pKey = $_
				$tempQS = $tempQS + ($template -f $pKey) + "%20or%20";
				$havePartitionKeys = $true;
			}
			if($havePartitionKeys)
			{
				$tempQS = $tempQS.Substring(0,$tempQS.Length - 8);
			}
			return $tempQS;
		}	
		else {
			return "";
		}	
	}

	
}
