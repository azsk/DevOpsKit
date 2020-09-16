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
	hidden [PSObject] $resourceGroupName;
	hidden [PSObject] $AttestationBody;
	[bool] $IsPersistedControlStates = $false;
	[bool] $FailedDownloadForControlStateIndexer = $false
	#hidden [bool] $PrintExtStgPolicyProjErr = $true; 
	hidden [bool] $PrintParamPolicyProjErr = $true; 
	hidden [bool] $PrintAttestationRepoErr = $true; 
	hidden static [bool] $IsOrgAttestationProjectFound  = $false; # Flag to represent if Host proj(attestation repo) is avilable for org controls. FALSE => Project or Repo not yet found. 
	hidden [AzSKSettings] $AzskSettings;


	ControlStateExtension([SubscriptionContext] $subscriptionContext, [InvocationInfo] $invocationContext)
	{
		$this.SubscriptionContext = $subscriptionContext;
		$this.InvocationContext = $invocationContext;	
		
		$this.ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");	
		$this.AttestationBody = [ConfigurationManager]::LoadServerConfigFile("ADOAttestation.json");
	}

	static [string] ComputeHashX([string] $dataToHash)
	{
		return [Helpers]::ComputeHashShort($dataToHash, [Constants]::AttestationHashLen)
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
				  #FailedDownloadForControlStateIndexer is used if file present in repo then variable is false, if file not present then it goes to exception so variable value is true.
				  #If file resent in repo with no content, there will be no exception in api call and respose body will be null
				  $this.FailedDownloadForControlStateIndexer = $false
				  $webRequestResult = $this.GetRepoFileContent( $this.IndexerBlobName );
				  if($webRequestResult){
				   		$indexerObject = $webRequestResult 
				  }
				  else {
					  if ($this.FailedDownloadForControlStateIndexer -eq $false) {
						  $this.IsControlStateIndexerPresent = $true
					  }
					  else {
						$this.IsControlStateIndexerPresent = $false  
					  }
				  }
				  $loopValue = 0;
				}
				catch{
					#Attestation index blob is not preset then return
					$this.IsControlStateIndexerPresent = $false
					return $true;
				}
			}
			$this.ControlStateIndexer += $indexerObject;
		}
		
		return $true;
	}

	# set indexer for rescan post attestation
	hidden [PSObject] RescanComputeControlStateIndexer([string] $projectName, [string] $resourceType)
	{
	        #$this.resourceType is used inside the GetProject method to get the project name for organization from extension storage, also return project for other resources
		$this.resourceType = $resourceType;
		if ($resourceType -eq "Organization" -or $resourceType -eq "Project") {
			$this.resourceName = $projectName
		}
		else {
			$this.resourceGroupName = $projectName
		}
		
		[PSObject] $ControlStateIndexerForRescan = $this.GetRepoFileContent($this.IndexerBlobName );
                #setting below global variables null as needed for next resource.
		$this.resourceType = $null;
		$this.resourceName = "";
		$this.resourceGroupName = "";
		
        return $ControlStateIndexerForRescan;
	}
        #isRescan parameter is added to check if method is called from rescan.
	hidden [PSObject] GetControlState([string] $id, [string] $resourceType, [string] $resourceName, [string] $resourceGroupName, [bool] $isRescan = $false)
	{
		try
		{
			$this.resourceType = $resourceType;
			$this.resourceName = $resourceName
			$this.resourceGroupName = $resourceGroupName
			[ControlState[]] $controlStates = @();
			
			if(!$this.GetProject())
			{
				return $null;
			}
			# We reset ControlStateIndexer to null whenever we move to a new project (project context switch)
			if($this.resourceType -eq "Project" ){
			    $this.ControlStateIndexer =  $null;
			    $this.IsControlStateIndexerPresent = $true;
			}
			#getting resource.index for rescan
			[PSObject] $ControlStateIndexerForRescan = $null;
			[bool] $retVal = $true;
			if ($isRescan) {
				#this is to set project name from GetProject method
				$projectName = $resourceName;
				if ($resourceType -ne "Organization" -and $resourceType -ne "Project") {
					$projectName = $resourceGroupName
				}
				$ControlStateIndexerForRescan = $this.RescanComputeControlStateIndexer($projectName, $resourceType);
				#Above method setting below blobal variable null so settting them again.
				$this.resourceType = $resourceType;
			    $this.resourceName = $resourceName
			    $this.resourceGroupName = $resourceGroupName
			}
			else {
			    $retVal = $this.ComputeControlStateIndexer();
			}

			if(($null -ne $this.ControlStateIndexer -and  $retVal) -or $isRescan)
			{
				$indexes = @();
				if ($isRescan) {
					$indexes = $ControlStateIndexerForRescan;
				}
				else {
				    $indexes += $this.ControlStateIndexer
				}
				$hashId = [ControlStateExtension]::ComputeHashX($id)
				$selectedIndex = $indexes | Where-Object { $_.HashId -eq $hashId}
				
				if(($selectedIndex | Measure-Object).Count -gt 0)
				{
					$hashId = $selectedIndex.HashId | Select-Object -Unique
					$controlStateBlobName = $hashId + ".json"

					$ControlStatesJson = $null;
					#Fetch attestation file content from repository
					$ControlStatesJson = $this.GetRepoFileContent($controlStateBlobName)
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
			if($this.resourceType -eq "Organization" ){
			    $this.ControlStateIndexer =  $null;
			    $this.IsControlStateIndexerPresent = $true;
			}
			return $controlStates;
		}
		catch{

			if($this.resourceType -eq "Organization"){
			    $this.ControlStateIndexer = $null;
			    $this.IsControlStateIndexerPresent = $true;
			}
			[EventBase]::PublishGenericException($_);
			return $null;
		}
	}

	hidden [void] SetControlState([string] $id, [ControlState[]] $controlStates, [bool] $Override, [string] $resourceType, [string] $resourceName, [string] $resourceGroupName)
	{	
		$this.resourceType = $resourceType;	
		$this.resourceName = $resourceName;
		$this.resourceGroupName = $resourceGroupName
		
		if(!$this.GetProject())
		{
			return
		}
		
		$AzSKTemp = Join-Path $([Constants]::AzSKAppFolderPath) "Temp" | Join-Path -ChildPath $this.UniqueRunId | Join-Path -ChildPath "ServerControlState";				
		if(-not (Test-Path $(Join-Path $AzSKTemp "ControlState")))
		{
			New-Item -ItemType Directory -Path $(Join-Path $AzSKTemp "ControlState") -ErrorAction Stop | Out-Null
		}
		else
		{
			Remove-Item -Path $(Join-Path $AzSKTemp "ControlState" | Join-Path -ChildPath '*' ) -Force -Recurse 
		}
        
		$hash = [ControlStateExtension]::ComputeHashX($id) 
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
			$this.IsPersistedControlStates = $false;
			if($Override)
			{
				$this.IsPersistedControlStates = $true;
				# in the case of override, just persist what is evaluated in the current context. No merging with older data
				$this.UpdateControlIndexer($id, $finalControlStates, $false);
				$finalControlStates = $finalControlStates | Where-Object { $_.State};
			}
			else
			{
				#merge with the exiting if found
				$persistedControlStates = $this.GetPersistedControlStates("$hash.json");
				$finalControlStates = $this.MergeControlStates($persistedControlStates, $finalControlStates);

				# COmmenting this code out. We will be handling encoding-decoding to b64 at SetStateData and WriteDetailedLogs.ps1
				
				#$finalControl = @();
				##convert state data object to encoded string
				#foreach ($controls in $finalControlStates) {
				#	# checking If state.DataObject is not empty and dataobject is not encode string, if control is already attested it will have encoded string
				#	if ($controls.state.DataObject -and !($controls.state.DataObject -is [string]) ) {
				#		try {
				#			#when dataobject is empty it comes like {} and null check does not work it alwasys count 1
				#			if ($controls.state.DataObject.count -gt 0) {
				#				$stateData = $controls.state.DataObject | ConvertTo-Json -Depth 10
				#				$encodedStateData =[Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($stateData))
				#				$controls.state.DataObject = $encodedStateData;
				#			}
				#		}
				#		catch {
				#			#eat the exception
				#		}
				#	}
				#	$finalControl += $controls;
				#}
				#$finalControlStates = $finalControl;
				$this.UpdateControlIndexer($id, $finalControlStates, $false);
				
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
			    	$this.UploadFileContent($state.FullName);
			    }
			    catch
			    {
			    	$_
			    	#eat this exception and retry
			    }
			}
		}
	}

	[void] UploadFileContent( $FullName )
	{
		$fileContent = Get-Content -Path $FullName -raw  
		$fileName = $FullName.split('\')[-1];

		$projectName = $this.GetProject();

		$rmContext = [ContextHelper]::GetCurrentContext();
		$user = "";
		$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
	   
		$uri = "https://dev.azure.com/{0}/{1}/_apis/git/repositories/{2}/refs?api-version=5.0" -f $this.SubscriptionContext.subscriptionid, $projectName, [Constants]::AttestationRepo 
        try {
		$webRequest = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
		$branchId = ($webRequest.value | where {$_.name -eq 'refs/heads/master'}).ObjectId

		$uri = [Constants]::AttRepoStorageUri -f $this.SubscriptionContext.subscriptionid, $projectName, [Constants]::AttestationRepo  
		$body = $this.CreateBody($fileContent, $fileName, $branchId);
		$webRequestResult = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $body

		if ($fileName -eq $this.IndexerBlobName) {
		   $this.IsControlStateIndexerPresent = $true;
		 }   
	   }
		catch {
			$repoName = [Constants]::AttestationRepo
			Write-Host "Error: Attestation denied.`nThis may be because: `n  (a) $($repoName) repository is not present in the project `n  (b) you do not have write permission on the repository. `n" -ForegroundColor Red
			Write-Host "See more at https://aka.ms/adoscanner (search for 'ADOScanner_Attestation' on the page). `n" -ForegroundColor Yellow 
		}
	}

	
	[string] CreateBody([string] $fileContent, [string] $fileName, [string] $branchId){
		
		$body = $this.AttestationBody.Post | ConvertTo-Json -Depth 10
		$body = $body.Replace("{0}",$branchId) 

		$body = $body.Replace("{2}", $this.CreatePath($fileName))  
		if ( $this.IsControlStateIndexerPresent -and $fileName -eq $this.IndexerBlobName ) {
			$body = $body.Replace("{1}","edit") 
		}
		elseif ($this.IsPersistedControlStates -and $fileName -ne $this.IndexerBlobName ) {
			$body = $body.Replace("{1}","edit") 
		}
		else {
			$body = $body.Replace("{1}","add") 
		}

        $content = ($fileContent | ConvertTo-Json -Depth 10) -replace '^.|.$', ''
		$body = $body.Replace("{3}", $content)

		return $body;		 
	}

	[string] CreatePath($fileName){
		$path = $fileName
		if (!($this.resourceType -eq "Organization" -or $fileName -eq $this.IndexerBlobName) -and ($this.resourceType -ne "Project")) {
			$path = $this.resourceGroupName + "/" + $this.resourceType + "/" + $fileName;
		}
		elseif(!($this.resourceType -eq "Organization" -or $fileName -eq $this.IndexerBlobName))
		{
			$path = $this.resourceName + "/" + $fileName;
		}
		
		return $path;
	}

	[string] GetProject(){
		$projectName = "";
		if ($this.resourceType -eq "Organization" -or $this.resourceType -eq $null) 
		{
			if($this.InvocationContext)
			{
			#Get project name from ext storage to fetch org attestation 
			$projectName = $this.GetProjectNameFromExtStorage();
			#If not found then check if 'PolicyProject' parameter is provided in command 
			if ([string]::IsNullOrEmpty($projectName))
			{
				$projectName = $this.InvocationContext.BoundParameters["PolicyProject"]
				if ([string]::IsNullOrEmpty($projectName))
				{
					if (!$this.AzskSettings) {
						$this.AzskSettings = [ConfigurationManager]::GetLocalAzSKSettings();
					}
					$projectName = $this.AzskSettings.PolicyProject
					$enableOrgControlAttestation = $this.AzskSettings.EnableOrgControlAttestation
					if([string]::IsNullOrEmpty($projectName))
					{
						if ($this.PrintParamPolicyProjErr -eq $true -and $enableOrgControlAttestation -eq $true)
						{
							Write-Host -ForegroundColor Yellow "Could not fetch attestation-project-name. `r`n You can `r`n(a) Run Set-AzSKADOMonitoringSetting -PolicyProject '<PolicyProjectName>' or `r`n(b) Use '-PolicyProject' parameter to specify the host project containing attestation details of organization controls."
							$this.PrintParamPolicyProjErr = $false;
						}   
					}
				}
				else {
					if ([ControlStateExtension]::IsOrgAttestationProjectFound -eq $false)
					{
						#Validate if Attestation repo is available in policy project
						try 
						{
							$rmContext = [ContextHelper]::GetCurrentContext();
							$user = "";
							$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
						
							$uri = "https://dev.azure.com/{0}/{1}/_apis/git/repositories/{2}/refs?api-version=5.0" -f $this.SubscriptionContext.subscriptionid, $projectName, [Constants]::AttestationRepo 
							$webRequest = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
							[ControlStateExtension]::IsOrgAttestationProjectFound = $true # Policy project and repo found
						}
						catch {
							$projectName = "";
							if ($this.PrintAttestationRepoErr -eq $true)
							{
								Write-Host -ForegroundColor Yellow "Could not find attestation repo [$([Constants]::AttestationRepo)] in the policy project."
								$this.PrintAttestationRepoErr = $false;
							}

							# eat exception. This means attestation repo was not found
							# attestation repo is required to scan org controls and send hasrequiredaccess as true
						}
					}
				}
			}}
		}
		elseif($this.resourceType -eq "Project" )
		{
			$projectName = $this.resourceName
		}
		else {
			$projectName = $this.resourceGroupName
		}
		
		return $projectName;
	}

	[string] GetProjectNameFromExtStorage()
	{
		try {
			$rmContext = [ContextHelper]::GetCurrentContext();
		    $user = "";
		    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
		    
		    $uri = [Constants]::StorageUri -f $this.SubscriptionContext.subscriptionid, $this.SubscriptionContext.subscriptionid, [Constants]::OrgAttPrjExtFile 
			$webRequestResult = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
			#If repo is not found, we will fall into the catch block from IRM call above
			[ControlStateExtension]::IsOrgAttestationProjectFound = $true # Policy project found
			return $webRequestResult.Project
		}
		catch {
			#TODO: remove commented code
			#if ($this.PrintExtStgPolicyProjErr -eq $true)
			#{
			#	Write-Host -ForegroundColor Yellow "Could not fetch attestation-project-name from extension storage!"
			#	Write-Host -ForegroundColor Cyan "Trying to fetch host project containing attestation details of organization controls."
			#	$this.PrintExtStgPolicyProjErr = $false;
			#}			
			return $null;
		}
	}

	[bool] SetProjectInExtForOrg() {
		$projectName = $this.InvocationContext.BoundParameters["AttestationHostProjectName"]
		$rmContext = [ContextHelper]::GetCurrentContext();
		$user = "";
		$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user, $rmContext.AccessToken)))
		$fileName = [Constants]::OrgAttPrjExtFile 

		$apiURL = "https://dev.azure.com/{0}/_apis/projects?api-version=4.1" -f $($this.SubscriptionContext.SubscriptionName);
		try { 
			$responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL) ;
			$projects = $responseObj | Where-Object { $projectName -contains $_.name }

			if ($null -eq $projects) {
				Write-Host "$($projectName) Project not found: Incorrect project name or you do not have neccessary permission to access the project." -ForegroundColor Red
				return $false
			}
                   
		}
		catch {
			Write-Host "$($projectName) Project not found: Incorrect project name or you do not have neccessary permission to access the project." -ForegroundColor Red
			return $false
		}
			   
		$uri = [Constants]::StorageUri -f $this.SubscriptionContext.subscriptionid, $this.SubscriptionContext.subscriptionid, $fileName
		try {
			$webRequestResult = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo) }
			Write-Host "Project $($webRequestResult.Project) is already configured to store attestation details for organization-specific controls." -ForegroundColor Yellow
		}
		catch {
			$body = @{"id" = "$fileName"; "Project" = $projectName; } | ConvertTo-Json
			$uri = [Constants]::StorageUri -f $this.SubscriptionContext.subscriptionid, $this.SubscriptionContext.subscriptionid, $fileName  
			try {
				$webRequestResult = Invoke-RestMethod -Uri $uri -Method Put -ContentType "application/json" -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo) } -Body $body	
				return $true;
			}
			catch {	
			Write-Host "Error: Could not configure host project for attestation of org-specific controls because 'ADOSecurityScanner' extension is not installed in your organization." -ForegroundColor Red
			}
				
		}
		return $false;
	}

	[PSObject] GetRepoFileContent($fileName)
	{
		$projectName = $this.GetProject();
		$branchName =  [Constants]::AttestationBranch

		$fileName = $this.CreatePath($fileName);

		$rmContext = [ContextHelper]::GetCurrentContext();
		$user = "";
		$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
		
		try
		{
		   $uri = [Constants]::GetAttRepoStorageUri -f $this.SubscriptionContext.subscriptionid, $projectName, [Constants]::AttestationRepo, $fileName, $branchName 
		   $webRequestResult = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
           if ($webRequestResult) {
			# COmmenting this code out. We will be handling encoding-decoding to b64 at SetStateData and WriteDetailedLogs.ps1

			#if($fileName -ne $this.IndexerBlobName)
			#{   
			#    #convert back state data from encoded string
			#    $attestationData = @();
			#	foreach ($controls in $webRequestResult) 
			#	{
			#    	if($controls.State.DataObject -is [string])
			#        {
			#        	$controls.State.DataObject = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($controls.State.DataObject)) | ConvertFrom-Json
			#        }
			#    	$attestationData += $controls;
			#    }
			#    $webRequestResult = $attestationData;
		    #}
			return $webRequestResult
		   }
		   return $null;
		}
		catch{
			if ($fileName -eq  $this.IndexerBlobName) {
				$this.FailedDownloadForControlStateIndexer = $true
			}
			return $null;
		}
	}

	[void] RemoveExtStorageContent($fileName)
	{
		$projectName = $this.GetProject();
		$fileName = $this.CreatePath($fileName);

		$rmContext = [ContextHelper]::GetCurrentContext();
		$user = "";
		$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$rmContext.AccessToken)))
		
		$uri = "https://dev.azure.com/{0}/{1}/_apis/git/repositories/{2}/refs?api-version=5.0" -f $this.SubscriptionContext.subscriptionid, $projectName, [Constants]::AttestationRepo 
        $webRequest = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
		$branchId = ($webRequest.value | where {$_.name -eq 'refs/heads/master'}).ObjectId
		
		$body = $this.AttestationBody.Delete | ConvertTo-Json -Depth 10;
		$body = $body.Replace('{0}',$branchId)
		$body = $body.Replace('{1}',$fileName)

		try
		{
		   $uri = [Constants]::AttRepoStorageUri -f $this.SubscriptionContext.subscriptionid, $projectName, [Constants]::AttestationRepo  
		   $webRequestResult = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $body
		}
		catch{
			Write-Host "Could not remove attastation for: " + $fileName;
			Write-Host $_
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

		$hash = [ControlStateExtension]::ComputeHashX($id);
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
						$this.UploadFileContent($state.FullName);
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
				$ControlStatesJson = $this.GetRepoFileContent($controlStateBlobName) 
				if ($ControlStatesJson) {
					$this.IsPersistedControlStates = $true
				}
				$loopValue = 0;
			}
			catch
			{
				$this.IsPersistedControlStates = $false;
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
			$tempHash = [ControlStateExtension]::ComputeHashX($id);
			#take the current indexer value
			$filteredIndexerObject = $null;
			$filteredIndexerObject2 = $null;
			if ($this.ControlStateIndexer -and ($this.ControlStateIndexer | Measure-Object).Count -gt 0) {
				$filteredIndexerObject = $this.ControlStateIndexer | Where-Object { $_.HashId -eq $tempHash}
			    #remove the current index from the list
			    $filteredIndexerObject2 = $this.ControlStateIndexer | Where-Object { $_.HashId -ne $tempHash}
			}

			$this.ControlStateIndexer = @();
			if($filteredIndexerObject2)
			{
			  $this.ControlStateIndexer += $filteredIndexerObject2
			}
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
	    	
            $url= "https://{0}.visualstudio.com/_apis/Contribution/HierarchyQuery?api-version=5.1-preview" -f $($this.SubscriptionContext.SubscriptionName);
			$postbody="{'contributionIds':['ms.vss-admin-web.org-admin-groups-data-provider'],'dataProviderContext':{'properties':{'sourcePage':{'url':'https://$($this.SubscriptionContext.SubscriptionName).visualstudio.com/_settings/groups','routeId':'ms.vss-admin-web.collection-admin-hub-route','routeValues':{'adminPivot':'groups','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
			$groupsOrgObj = [WebRequestHelper]::InvokePostWebRequest($url,$postbody);
			$groupsOrgObj = $groupsOrgObj.dataProviders.'ms.vss-admin-web.org-admin-groups-data-provider'.identities | where { $allowedGrpForOrgAtt.GroupNames -contains $_.displayName }

			if($this.CheckGroupMemberPCA($groupsOrgObj.descriptor)){
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
                if($this.CheckGroupMemberPA($group.descriptor,$resourceName)){
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

	[bool] CheckGroupMemberPA($descriptor,[string] $resourceName)
	{
		<#
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
		}#>

		$isUserPA=[AdministratorHelper]::GetIsCurrentUserPA($descriptor,$this.SubscriptionContext.SubscriptionName,$resourceName);
		if($isUserPA -eq $true){
			$this.HasControlStateWritePermissions = 1
			return $true;
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

	[bool] CheckGroupMemberPCA($descriptor){
		$isUserPCA=[AdministratorHelper]::GetIsCurrentUserPCA($descriptor,$this.SubscriptionContext.SubscriptionName);
		if($isUserPCA -eq $true){
			$this.HasControlStateWritePermissions = 1
			return $true;
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
