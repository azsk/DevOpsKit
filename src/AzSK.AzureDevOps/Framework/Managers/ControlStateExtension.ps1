using namespace System.Management.Automation
Set-StrictMode -Version Latest

class ControlStateExtension
{
	#Static attestation index file object. 
	#This gets cashed for every scan and reset for every fresh scan command in servicessecurity status 
	[PSObject] $ControlStateIndexer = $null;
	#Property indicates if Attestation index file is present in blob 
	[bool] $IsControlStateIndexerPresent = $true;
	hidden [int] $HasControlStateReadPermissions = 1;
	hidden [int] $HasControlStateWritePermissions = -1;
	hidden [string]	$IndexerBlobName ="Resource.index.json"

	hidden [int] $retryCount = 3;
	hidden [string] $UniqueRunId;

	hidden [SubscriptionContext] $SubscriptionContext;
	hidden [InvocationInfo] $InvocationContext;
	hidden [PSObject] $ControlSettings; 
	hidden [PSObject] $resourceType;
	hidden [PSObject] $resourceName;

	ControlStateExtension([SubscriptionContext] $subscriptionContext, [InvocationInfo] $invocationContext)
	{
		$this.SubscriptionContext = $subscriptionContext;
		$this.InvocationContext = $invocationContext;	
		$this.ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");	
	}

	hidden [void] Initialize([bool] $CreateResourcesIfNotExists)
	{
		if([string]::IsNullOrWhiteSpace($this.UniqueRunId))
		{
			$this.UniqueRunId = $(Get-Date -format "yyyyMMdd_HHmmss");
		}

		# this function to check and set access permission
		$this.SetControlStatePermission();

		#Reset attestation index file and set attestation index file present flag to get fresh index file from storage
		$this.ControlStateIndexer = $null;
		$this.IsControlStateIndexerPresent = $true
	}

	# fetch allowed group for attestation from setting file and check user is member of this group and set acccess permission 
	hidden [void] SetControlStatePermission()
	{
	    try
	      {	
	    	$this.HasControlStateWritePermissions = 1
	    	#$this.HasControlStateReadPermissions = 0
     
           #$url= "https://vssps.dev.azure.com/{0}/_apis/graph/groups?api-version=5.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
           #$groupsObj = [WebRequestHelper]::InvokeGetWebRequest($url);
	    	#$allowedGrpForAtt = $this.ControlSettings.AllowAttestationByGroups | where { $_.ResourceType -eq "Organization" } | select-object -property GroupNames 
	    	#
	    	#$groupsObj = $groupsObj | where { $allowedGrpForAtt.GroupNames -contains $_.displayName }
    
           #$apiURL = "https://dev.azure.com/{0}/_apis/Contribution/HierarchyQuery?api-version=5.0-preview" -f $($this.SubscriptionContext.SubscriptionName);
    
	    	#foreach ($group in $groupsObj)
	    	#{ 
           # $descriptor = $group.descriptor;
           # $inputbody =  '{"contributionIds":["ms.vss-admin-web.org-admin-members-data-provider"],"dataProviderContext":{"properties":{"subjectDescriptor":"","sourcePage":{"url":"","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute"}}}}}' | ConvertFrom-Json
           #
           # $inputbody.dataProviderContext.properties.subjectDescriptor = $descriptor;
           # $inputbody.dataProviderContext.properties.sourcePage.url = "https://dev.azure.com/$($this.SubscriptionContext.SubscriptionName)/_settings/groups?subjectDescriptor=$($descriptor)";
	    	# $groupMembersObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);
	    	# $users = $groupMembersObj.dataProviders."ms.vss-admin-web.org-admin-members-data-provider".identities | where {$_.subjectKind -eq "user"}
			# $this.HasControlStateWritePermissions = 1
			# return;
	    	# if($null -ne $users){
	    	# 	$currentUser = "v-arbagh@microsoft.com" #[ContextHelper]::GetCurrentSessionUser();
           #     $grpmember = ($users | where { $_.mailAddress -eq $currentUser } );
           #     if ($null -ne $grpmember ) {
	    	# 	     $this.HasControlStateWritePermissions = 1
	    	# 	     return;
           #     }	
	    	# }
	    	#		
	    	#}
	      }
	      catch
	      {
	      	$this.HasControlStateWritePermissions = 0
	      }
	}
	
	hidden [bool] ComputeControlStateIndexer()
	{
		try {
			$AzSKTemp = Join-Path $([Constants]::AzSKAppFolderPath) "Temp" | Join-Path -ChildPath $this.UniqueRunId | Join-Path -ChildPath "ServerControlState";
			if(-not (Test-Path -Path $AzSKTemp))
			{
				New-Item -ItemType Directory -Path $AzSKTemp -Force | Out-Null
			}
		$indexerObject = Get-ChildItem -Path (Join-Path $AzSKTemp $($this.IndexerBlobName)) -Force -ErrorAction Stop | Get-Content | ConvertFrom-Json
		
		}
		catch {
			#Write-Host $_
		}

		#Cache code: Fetch index file only if index file is null and it is present on storage blob
		if(-not $this.ControlStateIndexer -and $this.IsControlStateIndexerPresent)
		{		
			#Attestation index blob is not preset then return
			[ControlStateIndexer[]] $indexerObjects = @();
			$this.ControlStateIndexer  = $indexerObjects

			$AzSKTemp = Join-Path $([Constants]::AzSKAppFolderPath) "Temp" | Join-Path -ChildPath $this.UniqueRunId | Join-Path -ChildPath "ServerControlState";
			if(-not (Test-Path -Path $AzSKTemp))
			{
				New-Item -ItemType Directory -Path $AzSKTemp -Force | Out-Null
			}

			$indexerObject = @();
			$loopValue = $this.retryCount;
			while($loopValue -gt 0)
			{
				$loopValue = $loopValue - 1;
				try
				{
					$rmContext = [ContextHelper]::GetCurrentContext();
					$user = "";
					$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
				   
					try
					{
					   $uri = [Constants]::StorageUri -f $this.SubscriptionContext.subscriptionid, $this.SubscriptionContext.subscriptionid, $this.IndexerBlobName 
					   $webRequestResult = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
					   $indexerObject =  $webRequestResult.value.value | ConvertFrom-Json;
					   $loopValue = 0;
					}
					catch{
						#Attestation index blob is not preset then return
						$this.IsControlStateIndexerPresent = $false
						return $true;
					}
					
				}
				catch
				{
					#eat this exception and retry
				}
			}
			$this.ControlStateIndexer += $indexerObject;
		}
		
		return $true;
	}

	hidden [PSObject] GetControlState([string] $id, [string] $resourceType, [string] $resourceName)
	{
		try
		{
			$this.resourceType = $resourceType;
			$this.resourceName = $resourceName
			[ControlState[]] $controlStates = @();
			$retVal = $this.ComputeControlStateIndexer();

			if($null -ne $this.ControlStateIndexer -and  $retVal)
			{
				$indexes = @();
				$indexes += $this.ControlStateIndexer
				$hashId = [Helpers]::ComputeHash($id)
				$selectedIndex = $indexes | Where-Object { $_.HashId -eq $hashId}
				
				if(($selectedIndex | Measure-Object).Count -gt 0)
				{
					$hashId = $selectedIndex.HashId | Select-Object -Unique
					$controlStateBlobName = $hashId + ".json"

					$ControlStatesJson = $null;
					$ControlStatesJson = $this.GetExtStorageContent($controlStateBlobName) | ConvertFrom-Json;
					if($ControlStatesJson )
					{
				    	$retVal = $true;
					}
					else {
					    $retVal = $false;
					}

					#$ControlStatesJson = Get-ChildItem -Path (Join-Path $AzSKTemp $controlStateBlobName) -Force | Get-Content | ConvertFrom-Json 
					if($null -ne $ControlStatesJson)
					{					
						$ControlStatesJson | ForEach-Object {
							try
							{
								$controlState = [ControlState] $_
								$controlStates += $controlState;								
							}
							catch 
							{
								[EventBase]::PublishGenericException($_);
							}
						}
					}
				}
			}
			return $controlStates;
		}
		catch{
			[EventBase]::PublishGenericException($_);
			return $null;
		}
	}

	hidden [void] SetControlState([string] $id, [ControlState[]] $controlStates, [bool] $Override, [string] $resourceType, [string] $resourceName)
	{	
		$this.resourceType = $resourceType;	
		$this.resourceName = $resourceName;
		$AzSKTemp = Join-Path $([Constants]::AzSKAppFolderPath) "Temp" | Join-Path -ChildPath $this.UniqueRunId | Join-Path -ChildPath "ServerControlState";				
		if(-not (Test-Path $(Join-Path $AzSKTemp "ControlState")))
		{
			New-Item -ItemType Directory -Path $(Join-Path $AzSKTemp "ControlState") -ErrorAction Stop | Out-Null
		}
		else
		{
			Remove-Item -Path $(Join-Path $AzSKTemp "ControlState" | Join-Path -ChildPath '*' ) -Force -Recurse 
		}
        
		$hash = [Helpers]::ComputeHash($id) 
		$indexerPath = Join-Path $AzSKTemp "ControlState" | Join-Path -ChildPath $this.IndexerBlobName;
		if(-not (Test-Path -Path (Join-Path $AzSKTemp "ControlState")))
		{
			New-Item -ItemType Directory -Path (Join-Path $AzSKTemp "ControlState") -Force
		}
		$fileName = Join-Path $AzSKTemp "ControlState" | Join-Path -ChildPath ($hash+".json");
		
		#Filter out the "Passed" controls
		$finalControlStates = $controlStates | Where-Object { $_.ActualVerificationResult -ne [VerificationResult]::Passed};
		if(($finalControlStates | Measure-Object).Count -gt 0)
		{
			if($Override)
			{
				# in the case of override, just persist what is evaluated in the current context. No merging with older data
				$this.UpdateControlIndexer($id, $finalControlStates, $false);
				$finalControlStates = $finalControlStates | Where-Object { $_.State};
			}
			else
			{
				#merge with the exiting if found
				$persistedControlStates = $this.GetPersistedControlStates("$hash.json");
				$finalControlStates = $this.MergeControlStates($persistedControlStates, $finalControlStates);
				$this.UpdateControlIndexer($id, $finalControlStates, $false);
				#TODO
			}
		}
		else
		{
			#purge would remove the entry from the control indexer and also purge the stale state json.
			$this.PurgeControlState($id);
		}
		if(($finalControlStates|Measure-Object).Count -gt 0)
		{
			[JsonHelper]::ConvertToJsonCustom($finalControlStates) | Out-File $fileName -Force		
		}

		if($null -ne $this.ControlStateIndexer)
		{				
			[JsonHelper]::ConvertToJsonCustom($this.ControlStateIndexer) | Out-File $indexerPath -Force
			$controlStateArray = Get-ChildItem -Path (Join-Path $AzSKTemp "ControlState")
			$controlStateArray | ForEach-Object {
			    $state = $_;
			    try
			    {
			    	$this.UploadExtStorage($state.FullName);
			    }
			    catch
			    {
			    	$_
			    	#eat this exception and retry
			    }
			}
		}
	}

	[void] UploadExtStorage( $FullName )
	{
		$fileContent = Get-Content -Path $FullName -raw  
		$fileName = $FullName.split('\')[-1];
		 
		$collectionName = "";
		if($this.resourceType -eq "Organization" -or $fileName -eq $this.IndexerBlobName)
		{
			$collectionName = $this.SubscriptionContext.subscriptionid;
		}
		else {
			$collectionName = $this.resourceName 
		}

		$rmContext = [ContextHelper]::GetCurrentContext();
		$user = "";
		$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
	   
		$body = @{"id" = "$fileName"; "__etag" = -1; "value"= $fileContent;} | ConvertTo-Json
		$uri = [Constants]::StorageUri -f $this.SubscriptionContext.subscriptionid, $collectionName, $fileName  
		try {
		$webRequestResult = Invoke-RestMethod -Uri $uri -Method Put -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $body

		if ($fileName -eq $this.IndexerBlobName) {
		   $this.IsControlStateIndexerPresent = $true;
		 }   
	   }
		catch {Write-Host $_}
	}

	[PSObject] GetExtStorageContent($fileName)
	{
		$collectionName = "";
		if($this.resourceType -eq "Organization" -or $fileName -eq $this.IndexerBlobName)
		{
			$collectionName = $this.SubscriptionContext.subscriptionid;
		}
		else {
			$collectionName = $this.resourceName  
		}

		$rmContext = [ContextHelper]::GetCurrentContext();
		$user = "";
		$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
		
		try
		{
		   $uri = [Constants]::StorageUri -f $this.SubscriptionContext.subscriptionid, $collectionName, $fileName 
		   $webRequestResult = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
		   return $webRequestResult.value.value
		}
		catch{
			return $null;
		}
	}

	[void] RemoveExtStorageContent($fileName)
	{
		$collectionName = "";
		if($this.resourceType -eq "Organization" -or $fileName -eq $this.IndexerBlobName)
		{
			$collectionName = $this.SubscriptionContext.subscriptionid;
		}
		else {
			$collectionName = $this.resourceName  
		}

		$rmContext = [ContextHelper]::GetCurrentContext();
		$user = "";
		$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
		
		try
		{
		   $uri = [Constants]::StorageUri -f $this.SubscriptionContext.subscriptionid, $collectionName, $fileName 
		   $webRequestResult = Invoke-RestMethod -Uri $uri -Method Delete -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
		}
		catch{
		}
	}

	hidden [void] PurgeControlState([string] $id)
	{		
		$AzSKTemp = Join-Path $([Constants]::AzSKAppFolderPath) "Temp" | Join-Path -ChildPath $this.UniqueRunId | Join-Path -ChildPath "ServerControlState";				
		if(-not (Test-Path $(Join-Path $AzSKTemp "ControlState")))
		{
			New-Item -ItemType Directory -Path (Join-Path $AzSKTemp "ControlState") -ErrorAction Stop | Out-Null
		}
		else
		{
			Remove-Item -Path $(Join-Path $AzSKTemp "ControlState" | Join-Path -ChildPath '*') -Force -Recurse
		}

		$hash = [Helpers]::ComputeHash($id);
		$indexerPath = Join-Path $AzSKTemp "ControlState" | Join-Path -ChildPath $this.IndexerBlobName ;
		$fileName = Join-Path $AzSKTemp "ControlState" | Join-Path -ChildPath ("$hash.json");
		
		$this.UpdateControlIndexer($id, $null, $true);
		if($null -ne $this.ControlStateIndexer)
		{				
			[JsonHelper]::ConvertToJsonCustom($this.ControlStateIndexer) | Out-File $indexerPath -Force
			$controlStateArray = Get-ChildItem -Path (Join-Path $AzSKTemp "ControlState");				
			$controlStateArray | ForEach-Object {
				$state = $_
				$loopValue = $this.retryCount;
				while($loopValue -gt 0)
				{
					$loopValue = $loopValue - 1;
					try
					{
						$this.UploadExtStorage($state.FullName);
						$loopValue = 0;
					}
					catch
					{
						#eat this exception and retry
					}
				}
			}
		}
		try
		{
			$hashFile = "$hash.json";
			$this.RemoveExtStorageContent($hashFile)
		}
		catch
		{
			#eat this exception and retry
		}	
	}

	hidden [ControlState[]] GetPersistedControlStates([string] $controlStateBlobName)
	{
		$AzSKTemp = Join-Path $([Constants]::AzSKAppFolderPath) "Temp" | Join-Path -ChildPath $this.UniqueRunId | Join-Path -ChildPath "ServerControlState";
		if(-not (Test-Path (Join-Path $AzSKTemp "ExistingControlStates")))
		{
			New-Item -ItemType Directory -Path (Join-Path $AzSKTemp "ExistingControlStates") -ErrorAction Stop | Out-Null
		}
	
		[ControlState[]] $ControlStatesJson = @()

		$loopValue = $this.retryCount;
		while($loopValue -gt 0)
		{
			$loopValue = $loopValue - 1;
			try
			{
				#$ControlStatesJson = @()
				$ControlStatesJson = $this.GetExtStorageContent($controlStateBlobName) | ConvertFrom-Json;
				$loopValue = 0;
			}
			catch
			{
				#$ControlStatesJson = @()
				#eat this exception and retry
			}
		}

		return $ControlStatesJson
	}

	hidden [ControlState[]] MergeControlStates([ControlState[]] $persistedControlStates,[ControlState[]] $controlStates)
	{
		[ControlState[]] $computedControlStates = $controlStates;
		if(($computedControlStates | Measure-Object).Count -le 0)
		{
			$computedControlStates = @();
		}
		if(($persistedControlStates | Measure-Object).Count -gt 0)
		{
			$persistedControlStates | ForEach-Object {
				$controlState = $_;
				if(($computedControlStates | Where-Object { ($_.InternalId -eq $controlState.InternalId) -and ($_.ChildResourceName -eq $controlState.ChildResourceName) } | Measure-Object).Count -le 0)
				{
					$computedControlStates += $controlState;
				}
			}
		}
		#remove the control states with null state which would be in the case of clear attestation.
		$computedControlStates = $computedControlStates | Where-Object { $_.State}

		return $computedControlStates;
	}

	hidden [void] UpdateControlIndexer([string] $id, [ControlState[]] $controlStates, [bool] $ToBeDeleted)
	{
		$this.ControlStateIndexer = $null;
		$retVal = $this.ComputeControlStateIndexer();

		if($retVal)
		{				
			$tempHash = [Helpers]::ComputeHash($id);
			#take the current indexer value
			$filteredIndexerObject = $this.ControlStateIndexer | Where-Object { $_.HashId -eq $tempHash}
			#remove the current index from the list
			$filteredIndexerObject2 = $this.ControlStateIndexer | Where-Object { $_.HashId -ne $tempHash}
			$this.ControlStateIndexer = @();
			$this.ControlStateIndexer += $filteredIndexerObject2
			if(-not $ToBeDeleted)
			{	
				$currentIndexObject = $null;
				#check if there is an existing index and the controlstates are present for that index resource
				if(($filteredIndexerObject | Measure-Object).Count -gt 0 -and ($controlStates | Measure-Object).Count -gt 0)
				{
					$currentIndexObject = $filteredIndexerObject;
					if(($filteredIndexerObject | Measure-Object).Count -gt 1)
					{
						$currentIndexObject = $filteredIndexerObject | Select-Object -Last 1
					}					
					$currentIndexObject.ExpiryTime = [DateTime]::UtcNow.AddMonths(3);
					$currentIndexObject.AttestedBy = [ContextHelper]::GetCurrentSessionUser();
					$currentIndexObject.AttestedDate = [DateTime]::UtcNow;
					$currentIndexObject.Version = "1.0";
				}
				elseif(($controlStates | Measure-Object).Count -gt 0)
				{
					$currentIndexObject = [ControlStateIndexer]::new();
					$currentIndexObject.ResourceId = $id
					$currentIndexObject.HashId = $tempHash;
					$currentIndexObject.ExpiryTime = [DateTime]::UtcNow.AddMonths(3);
					$currentIndexObject.AttestedBy = [ContextHelper]::GetCurrentSessionUser();
					$currentIndexObject.AttestedDate = [DateTime]::UtcNow;
					$currentIndexObject.Version = "1.0";
				}
				if($null -ne $currentIndexObject)
				{
					$this.ControlStateIndexer += $currentIndexObject;			
				}
			}
		}
	}
	
	[bool] HasControlStateReadAccessPermissions()
	{
		if($this.HasControlStateReadPermissions -le 0)
		{
			return $false;
		}
		else
		{
			return $true;
		}
	}

	[void] SetControlStateReadAccessPermissions([int] $value)
	{
		$this.HasControlStateReadPermissions  = $value
	}

	[void] SetControlStateWriteAccessPermissions([int] $value)
	{
		$this.HasControlStateWritePermissions  = $value
	}

	[bool] HasControlStateWriteAccessPermissions()
	{		
		if($this.HasControlStateWritePermissions -le 0)
		{
			return $false;
		}
		else
		{
			return $true;
		}
	}

	[bool] GetControlStatePermission([string] $featureName, [string] $resourceName)
	{
	    try
	      {	
	    	$this.HasControlStateWritePermissions = 0
	 
			$allowedGrpForOrgAtt = $this.ControlSettings.AllowAttestationByGroups | where { $_.ResourceType -eq "Organization" } | select-object -property GroupNames 
	    	
            $url= "https://vssps.dev.azure.com/{0}/_apis/graph/groups?api-version=5.1-preview.1" -f $($this.SubscriptionContext.SubscriptionName);
			$groupsOrgObj = [WebRequestHelper]::InvokeGetWebRequest($url);
			$groupsOrgObj = $groupsOrgObj | where { $allowedGrpForOrgAtt.GroupNames -contains $_.displayName }

			if($this.CheckGroupMember($groupsOrgObj.descriptor)){
				return $true;
			}

			if($featureName -ne "Organization")
			{
			   $allowedGrpForAtt = $this.ControlSettings.AllowAttestationByGroups | where { $_.ResourceType -eq $featureName } | select-object -property GroupNames 	    	
			   $url = 'https://dev.azure.com/{0}/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1' -f $($this.SubscriptionContext.SubscriptionName);
               $inputbody = '{"contributionIds":["ms.vss-admin-web.org-admin-groups-data-provider"],"dataProviderContext":{"properties":{"sourcePage":{"url":"","routeId":"ms.vss-admin-web.project-admin-hub-route","routeValues":{"project":"","adminPivot":"permissions","controller":"ContributedPage","action":"Execute"}}}}}' | ConvertFrom-Json
               $inputbody.dataProviderContext.properties.sourcePage.url = "https://dev.azure.com/$($this.SubscriptionContext.SubscriptionName)/$($resourceName)/_settings/permissions";
               $inputbody.dataProviderContext.properties.sourcePage.routeValues.Project =$resourceName;
       
			   $groupsObj = [WebRequestHelper]::InvokePostWebRequest($url,$inputbody); 
			   $groupsObj = $groupsObj.dataProviders."ms.vss-admin-web.org-admin-groups-data-provider".identities | where { $allowedGrpForAtt.GroupNames -contains $_.displayName }

	    	   foreach ($group in $groupsObj)
	    	   { 
                if($this.CheckGroupMember($group.descriptor)){
					return $true;
				}	
			   }
			}
			if($this.HasControlStateWritePermissions -gt 0)
			{
		      return $true
			}
			else
			{
				return $false
			}
	      }
	      catch
	      {
			  $this.HasControlStateWritePermissions = 0
			  return $false;
	      }
	}

	[bool] CheckGroupMember($descriptor)
	{
		$inputbody =  '{"contributionIds":["ms.vss-admin-web.org-admin-members-data-provider"],"dataProviderContext":{"properties":{"subjectDescriptor":"","sourcePage":{"url":"","routeId":"ms.vss-admin-web.collection-admin-hub-route","routeValues":{"adminPivot":"groups","controller":"ContributedPage","action":"Execute"}}}}}' | ConvertFrom-Json
	   
		$inputbody.dataProviderContext.properties.subjectDescriptor = $descriptor;
		$inputbody.dataProviderContext.properties.sourcePage.url = "https://dev.azure.com/$($this.SubscriptionContext.SubscriptionName)/_settings/groups?subjectDescriptor=$($descriptor)";
	   
		$apiURL = "https://dev.azure.com/{0}/_apis/Contribution/HierarchyQuery?api-version=5.0-preview" -f $($this.SubscriptionContext.SubscriptionName);

		$groupMembersObj = [WebRequestHelper]::InvokePostWebRequest($apiURL,$inputbody);
		$users = $groupMembersObj.dataProviders."ms.vss-admin-web.org-admin-members-data-provider".identities | where {$_.subjectKind -eq "user"}

		if($null -ne $users){
			$currentUser = [ContextHelper]::GetCurrentSessionUser();
			$grpmember = ($users | where { $_.mailAddress -eq $currentUser } );
			if ($null -ne $grpmember ) {
				 $this.HasControlStateWritePermissions = 1
				 return $true;
			}	
		}
		if($this.HasControlStateWritePermissions -gt 0)
		{
		  return $true
		}
		else
		{
			return $false
		}
	}
}