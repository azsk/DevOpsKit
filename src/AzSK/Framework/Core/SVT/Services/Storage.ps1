using namespace Microsoft.Azure.Management.Storage.Models
using namespace Microsoft.WindowsAzure.Storage.Shared.Protocol
Set-StrictMode -Version Latest 
class Storage: SVTBase
{       
	hidden [PSObject] $ResourceObject;
	hidden [bool] $LockExists = $false;

    Storage([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
                 Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
        $this.GetResourceObject();
    }

    Storage([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject = Get-AzureRmStorageAccount -Name $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName -ErrorAction Stop
                                                         
            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
        }
        return $this.ResourceObject;
    }

	[ControlItem[]] ApplyServiceFilters([ControlItem[]] $controls)
	{
		if($controls.Count -eq 0)
		{
			return $controls;
		}

		$result = @();

		if([Helpers]::CheckMember($this.ResourceObject, "Sku.Tier") -and $this.ResourceObject.Sku.Tier -eq "Premium")
		{
            $result += $controls | Where-Object {$_.Tags -contains "PremiumSku" }
		}
		else{
			$result += $controls | Where-Object {$_.Tags -contains "StandardSku" }
		}

		
		if([Helpers]::CheckMember($this.ResourceObject, "Kind") -and ($this.ResourceObject.Kind -eq "BlobStorage"))
		{
            $result = $result | Where-Object {$_.Tags -contains "BlobStorage" }
		}
		else{
			$result = $result | Where-Object {$_.Tags -contains "GeneralPurposeStorage" }
		}
		
		$recourcelocktype = Get-AzureRmResourceLock -ResourceName $this.ResourceContext.ResourceName -ResourceGroupName $this.ResourceContext.ResourceGroupName -ResourceType $this.ResourceContext.ResourceType
		if($recourcelocktype)
		{
			if($this.ResourceContext.ResourceGroupName -eq [OldConstants]::AzSDKRGName)
			{
				$result = $result | Where-Object {$_.Tags -notcontains "ResourceLocked" }
			}
			$this.LockExists = $true;
		}
				
		return $result;
	}

    hidden [ControlResult] CheckStorageContainerPublicAccessTurnOff([ControlResult] $controlResult)
    {
		$allContainers = @();
		try
		{
			$allContainers += Get-AzureStorageContainer -Context $this.ResourceObject.Context -ErrorAction Stop
		}
		catch
		{
			if(([Helpers]::CheckMember($_.Exception,"Response") -and  ($_.Exception).Response.StatusCode -eq [System.Net.HttpStatusCode]::Forbidden) -or $this.LockExists)
            {
				#Setting this property ensures that this control result will not be considered for the central telemetry, as control does not have the required permissions.
				$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
                $controlResult.AddMessage([VerificationResult]::Manual, ($_.Exception).Message);	
				return $controlResult
            }
            else
            {
                throw $_
            }
		}

		#Containers other than private
        $publicContainers = $allContainers | Where-Object { $_.PublicAccess -ne  [Microsoft.WindowsAzure.Storage.Blob.BlobContainerPublicAccessType]::Off }
			
		if(($publicContainers | Measure-Object ).Count -eq 0)
        {
			$controlResult.AddMessage([VerificationResult]::Passed, "No containers were found that have public (anonymous) access in this storage account.");
        }                 
        else
        {
			$controlResult.EnableFixControl = $true;
            $controlResult.AddMessage([VerificationResult]::Failed  , 
				                      [MessageData]::new("Remove public access from following containers. Total - $(($publicContainers | Measure-Object ).Count)", ($publicContainers | Select-Object -Property Name, PublicAccess)));  
        }

        return $controlResult;
    }

	hidden [ControlResult] CheckStorageEnableDiagnosticsLog([ControlResult] $controlResult)
		{
			#Checking for storage kind 
			$serviceMapping = $this.ControlSettings.StorageKindMapping | Where-Object { $_.Kind -eq $this.ResourceObject.Kind } | Select-Object -First 1;
			 if(-not $serviceMapping)
			 {
				#Currently only 'General purpose' or 'Blob storage' account kind is present 
				#If new storage kind is introduced code needs to be updated as per new storage kind
				$controlResult.AddMessage("Storage Account kind is not supported");
				return $controlResult; 
			 }

			#Checking for applicable sku
			$daignosticsSkuMapping = $this.ControlSettings.StorageDiagnosticsSkuMapping | Where-Object { $_ -eq $this.ResourceObject.Sku.Name } | Select-Object -First 1;
			if(-not $daignosticsSkuMapping)
			{
				#Diagnostics settings are not available for premium storage.
				$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("Diagnostics settings are not supported for Sku Tier - [$($this.ResourceObject.Sku.Name)]")); 
			    return $controlResult; 
			}

			try{
					$result = $true
					#Check Metrics diagnostics log property
					$serviceMapping.DiagnosticsLogServices | 
					ForEach-Object {
							#Diagnostic logging is not available for File service.
							$result = $this.GetServiceLoggingProperty($_, $controlResult) -and $result ;
					}

					#Check Metrics logging property
					$serviceMapping.Services | 
					ForEach-Object {
							$result = $this.GetServiceMetricsProperty($_, $controlResult) -and $result ;
					}

					if($result){
						  $controlResult.VerificationResult = [VerificationResult]::Passed
					}
					else{
						$controlResult.EnableFixControl = $true;
						$controlResult.VerificationResult = [VerificationResult]::Failed
					}
			}
			catch{
				     #With Reader Role exception will be thrown.
				    if(([Helpers]::CheckMember($_.Exception,"Response") -and  ($_.Exception).Response.StatusCode -eq [System.Net.HttpStatusCode]::Forbidden) -or $this.LockExists)
                    {
						#Setting this property ensures that this control result will not be considered for the central telemetry, as control does not have the required permissions.
						$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
                        $controlResult.AddMessage(($_.Exception).Message);
                        return $controlResult
                    }
                    else
                    {
                        throw $_
                    }
			}	
			return $controlResult;
		}

    hidden [ControlResult] CheckStorageGeoRedundantReplication([ControlResult] $controlResult)
     {
		 if($null -ne $this.ResourceObject.Sku.Tier -and $null -ne $this.ResourceObject.Sku.Name){
		      $controlResult.AddMessage("Current storage sku tier is - [$($this.ResourceObject.Sku.Tier)] and sku name is - [$($this.ResourceObject.Sku.Name)]"); 
		 }
		 else{
			  $controlResult.AddMessage("Unable to get sku details for - [$($this.ResourceContext.ResourceName)]"); 
			  return $controlResult
		 }
		 
		 if($this.ResourceObject.Sku.Tier -eq [SkuTier]::Standard){
			 
			 $isGeoRedundantSku = $this.ControlSettings.StorageGeoRedundantSku | Where-Object { $_ -eq $this.ResourceObject.Sku.Name } | Select-Object -First 1;

			 if($isGeoRedundantSku){
				   $controlResult.VerificationResult = [VerificationResult]::Passed
			 }
			 else {
					$controlResult.EnableFixControl = $true;
					$controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Geo-Replication is turned OFF for this storage account. GRS ensures availability in the face of regional catastrophes. You should review its applicability to your business data and storage scenario.")); 				    
			 }
		 }
		 else{
			   $controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("A premium storage account supports only locally redundant storage as the replication option"));  
		 }
		 return $controlResult;  
	 }

	hidden [ControlResult] CheckStorageBlobEncryptionEnabled([ControlResult] $controlResult)
     {
		 if($null -ne $this.ResourceObject.Encryption)
		 {
		if([Helpers]::CheckMember($this.ResourceObject,"Encryption.services.blob.Enabled"))
			{
						if($null -eq $this.ResourceObject.Encryption.Services.Blob.Enabled ){
							$controlResult.EnableFixControl = $true;
							$controlResult.AddMessage([MessageData]::new("Unable to get blob encryption settings"))
							return $controlResult;
						}
						if($this.ResourceObject.Encryption.Services.Blob.Enabled -eq $true){
							$controlResult.VerificationResult = [VerificationResult]::Passed
						}
						else{
							$controlResult.EnableFixControl = $true;
							$controlResult.VerificationResult = [VerificationResult]::Failed
						}
				}
			else{
							$controlResult.EnableFixControl = $true;
							$controlResult.VerificationResult = [VerificationResult]::Failed
						}	
		 }
		 else
		 {
			 $controlResult.EnableFixControl = $true;
			 $controlResult.AddMessage([MessageData]::new("Storage blob encryption is not enabled"))
			 $controlResult.VerificationResult = [VerificationResult]::Failed
		 }
		 return $controlResult;  
	 }

	hidden [ControlResult] CheckStorageFileEncryptionEnabled([ControlResult] $controlResult)
     {
		 if($null -ne $this.ResourceObject.Sku.Tier -and $null -ne $this.ResourceObject.Sku.Name){
		      $controlResult.AddMessage("Current storage sku tier is - [$($this.ResourceObject.Sku.Tier)] and sku name is - [$($this.ResourceObject.Sku.Name)]"); 
		 }
		 else{
			  $controlResult.AddMessage("Unable to get sku details for - [$($this.ResourceContext.ResourceName)]"); 
			  return $controlResult
		 }

		 if($this.ResourceObject.Sku.Tier -eq [SkuTier]::Standard){
				 if($null -ne $this.ResourceObject.Encryption)
				 {
					if([Helpers]::CheckMember($this.ResourceObject.Encryption, "Services")){
					  if([Helpers]::CheckMember($this.ResourceObject.Encryption.Services, "File")){
						if($null -eq $this.ResourceObject.Encryption.Services.File )
						{
						$controlResult.EnableFixControl = $true;
						$controlResult.AddMessage([VerificationResult]::Failed, "Unable to get file encryption settings")
						return $controlResult;
						}
						else
						{
						if($this.ResourceObject.Encryption.Services.File.Enabled -eq $true)
						{
							$controlResult.VerificationResult = [VerificationResult]::Passed
						}
						else
						{
							$controlResult.EnableFixControl = $true;
							$controlResult.VerificationResult = [VerificationResult]::Failed
						}
					}
				}
				 else{
							$controlResult.EnableFixControl = $true;
							$controlResult.VerificationResult = [VerificationResult]::Failed
				 }
			 }
			 else{
				 	$controlResult.EnableFixControl = $true;
				    $controlResult.VerificationResult = [VerificationResult]::Failed
			 }
		 }
		 else
		 {
			 $controlResult.EnableFixControl = $true;
			 $controlResult.AddMessage([MessageData]::new("Storage file encryption is not enabled"))
			 $controlResult.VerificationResult = [VerificationResult]::Failed
		 }
		 
		 
		 }
		 else{
			$controlResult.AddMessage([VerificationResult]::Passed, "File type encryption is not applicable for premium storage acccount.");  
		 }
		 
		 return $controlResult;  
	 }

	hidden [ControlResult] CheckStorageMetricAlert([ControlResult] $controlResult)
    {
		$serviceMapping = $this.ControlSettings.StorageKindMapping | Where-Object { $_.Kind -eq $this.ResourceObject.Kind } | Select-Object -First 1;
        
		if(-not $serviceMapping)
		{
			#Currently only 'General purpose' or 'Blob storage' account kind is present 
			#If new storage kind is introduced code needs to be updated as per new storage kind
			$controlResult.AddMessage("Storage Account kind is not supported");
			return $controlResult; 
		}

		#Checking for applicable sku
		$daignosticsSkuMapping = $this.ControlSettings.StorageAlertSkuMapping | Where-Object { $_ -eq $this.ResourceObject.Sku.Name } | Select-Object -First 1;
		if(-not $daignosticsSkuMapping)
		{
			#Metrics or logging capability not enabled for premium storage and zone redundant storage account.
			$controlResult.AddMessage([VerificationResult]::Passed, [MessageData]::new("Diagnostics settings are not supported for Sku Tier - [$($this.ResourceObject.Sku.Name)]")); 
			return $controlResult; 
		}

        $result = $true;
		
		try {
			$serviceMapping.Services | 
			ForEach-Object {
            	$result = $this.CheckMetricAlertConfiguration($this.ControlSettings.MetricAlert.Storage, $controlResult, ("/services/" + $_)) -and $result ;
        	}	
		}
		catch {
			if(([Helpers]::CheckMember($_.Exception,"Response") -and  ($_.Exception).Response.StatusCode -eq [System.Net.HttpStatusCode]::Forbidden) -or $this.LockExists)
			{
				#Setting this property ensures that this control result will not be considered for the central telemetry, as control does not have the required permissions.
				$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
				$controlResult.AddMessage(($_.Exception).Message);
				return $controlResult
			}
			else
			{
				throw $_
			}
		}        

        if($result)
		{
			$controlResult.VerificationResult = [VerificationResult]::Passed
		}
		else
		{
			$controlResult.EnableFixControl = $true;
			$controlResult.VerificationResult = [VerificationResult]::Manual
			$controlResult.AddMessage([MessageData]::new("Configure 'AnonymousSuccess' metric alert on your storage account to track anonymous activity. Threshold count and window duration should be minimum according to your business use case."))
		}

		return $controlResult;  
	 }

	hidden [boolean] GetServiceLoggingProperty([string] $serviceType, [ControlResult] $controlResult)
		{
			$loggingProperty = Get-AzureStorageServiceLoggingProperty -ServiceType $ServiceType -Context $this.ResourceObject.Context -ErrorAction Stop
			if($null -ne $loggingProperty){
				#Check For Retention day's
				if($loggingProperty.LoggingOperations -eq [LoggingOperations]::All -and (($loggingProperty.RetentionDays -eq $this.ControlSettings.Diagnostics_RetentionPeriod_Forever) -or ($loggingProperty.RetentionDays -eq $this.ControlSettings.Diagnostics_RetentionPeriod_Min))){
						return $True
				} 
				else{
						$controlResult.AddMessage("Diagnostics settings($($serviceType) logs) is either disabled OR not retaining logs for at least $($this.ControlSettings.Diagnostics_RetentionPeriod_Min) days for service type - [$($serviceType)]")
						return $false
				}
			}
			else
			{
                 $controlResult.AddMessage("Diagnostics settings($($serviceType) logs) is disabled for service type - [$($serviceType)]")
				 return $false
			}
		}

	hidden [boolean] GetServiceMetricsProperty([string] $serviceType,[ControlResult] $controlResult)
		{
			$serviceMetricsProperty= Get-AzureStorageServiceMetricsProperty -MetricsType Hour -ServiceType $ServiceType -Context $this.ResourceObject.Context  -ErrorAction Stop
			if($null -ne $serviceMetricsProperty){
				#Check for Retention day's
				if($serviceMetricsProperty.MetricsLevel -eq [MetricsLevel]::ServiceAndApi -and (($serviceMetricsProperty.RetentionDays -eq $this.ControlSettings.Diagnostics_RetentionPeriod_Min) -or ($serviceMetricsProperty.RetentionDays -eq $this.ControlSettings.Diagnostics_RetentionPeriod_Forever)))
				{
					return $True
				}
				else
				{
					$controlResult.AddMessage("Diagnostics settings($($serviceType) aggregate metrics, $($serviceType) per API metrics) is either disabled OR not retaining logs for at least $($this.ControlSettings.Diagnostics_RetentionPeriod_Min) days for service type - [$($serviceType)]")
					return $false				       
				}
			}
			else
			{
                 $controlResult.AddMessage("Diagnostics settings($($serviceType) aggregate metrics, $($serviceType) per API metrics) is disabled for service type - [$($serviceType)]")
				 return $false
			}
		}

	hidden [ControlResult] CheckStorageEncryptionInTransit([ControlResult] $controlResult)
		{

			if($null -ne $this.ResourceObject.EnableHttpsTrafficOnly){
				if($this.ResourceObject.EnableHttpsTrafficOnly -eq $true){
				$controlResult.VerificationResult = [VerificationResult]::Passed
			    $controlResult.AddMessage([MessageData]::new("Storage secure transfer is enabled"))
				}
				else{
				$controlResult.EnableFixControl = $true;
				$controlResult.VerificationResult = [VerificationResult]::Failed
				$controlResult.AddMessage([MessageData]::new("Storage secure transfer is not enabled"))
				}
			}
			else{
				$controlResult.EnableFixControl = $true;
				$controlResult.AddMessage([MessageData]::new("Storage secure transfer is not enabled"))
				$controlResult.VerificationResult = [VerificationResult]::Failed
			}
			return $controlResult;
		}
	hidden [ControlResult] CheckStorageCORSAllowed([ControlResult] $controlResult)
		{		 
		 $corsRules = @();	
		  try
		  {
			#Currently only 'General purpose' or 'Blob storage' account kind is present 
			#If new storage kind is introduced code needs to be updated as per new storage kind	
			if($this.ResourceObject.Kind -eq "BlobStorage"){
				$corsRules+= Get-AzureStorageCORSRule -Context $this.ResourceObject.Context -ServiceType Blob -ErrorAction Stop
			}
			else{
				"Blob","File","Table","Queue"|ForEach-Object {$corsRules +=Get-AzureStorageCORSRule -Context $this.ResourceObject.Context -ServiceType $_ -ErrorAction Stop}
			}			   		   		   
			if($corsRules.Count -eq 0){
				$controlResult.AddMessage([VerificationResult]::Passed,[MessageData]::new("The CORS feature has not been enabled on this storage account."));
				}
		   else{
		       
				$allowAllOrigins = @($corsRules | ForEach-Object{$_.AllowedOrigins.Contains("*")}).Contains($true)
				$allowAllMethods = @($corsRules | ForEach-Object{$_.AllowedMethods.Count}).Contains(7)	
				$controlResult.SetStateData("Following CORS rule(s) are defined in storage:",$corsRules);
				if($allowAllOrigins){
					$controlResult.AddMessage([VerificationResult]::Failed,[MessageData]::new("CORS rule is defined in storage with access from all origins ('*')"));
					}
				elseif(-not $allowAllOrigins -and $allowAllMethods){
					$controlResult.AddMessage([VerificationResult]::Verify,[MessageData]::new("CORS rule is defined in storage with all type of request methods(verbs) and access from specific origins"));
					}
				elseif(-not $allowAllOrigins -and -not $allowAllMethods){
					$controlResult.AddMessage([VerificationResult]::Verify,[MessageData]::new("CORS rule is defined in storage with specific request methods(verbs) and access from specific origins"));
					}
				}		   		   			 
		  }
		  catch
		  {
			 #With Reader Role exception will be thrown.
				    if(([Helpers]::CheckMember($_.Exception,"Response") -and  ($_.Exception).Response.StatusCode -eq [System.Net.HttpStatusCode]::Forbidden) -or $this.LockExists)
                    {
						#As control does not have the required permissions
						$controlResult.CurrentSessionContext.Permissions.HasRequiredAccess = $false;
                        $controlResult.AddMessage(($_.Exception).Message);
                        return $controlResult
                    }
                    else
                    {
                        throw $_
                    }
		  }
		return $controlResult;
		}
}
