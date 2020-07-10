Set-StrictMode -Version Latest

class SVTResourceResolver: AzSKRoot
{
	[string[]] $ResourceNames = @();
    [string] $ResourceType = "";
    [ResourceTypeName] $ResourceTypeName = [ResourceTypeName]::All;
	[Hashtable] $Tag = $null;
    [string] $TagName = "";
    [string[]] $TagValue = "";
	hidden [string[]] $ResourceGroups = @();
	[ResourceTypeName] $ExcludeResourceTypeName = [ResourceTypeName]::All;
	[string[]] $ExcludeResourceNames=@();
	[SVTResource[]] $ExcludedResources=@();
	[string] $ExcludeResourceWarningMessage=[string]::Empty
	[string[]] $ExcludeResourceGroupNames=@();
	[string[]] $ExcludedResourceGroupNames=@();
	[string] $ExcludeResourceGroupWarningMessage=[string]::Empty
	[SVTResource[]] $SVTResources = @();
	[int] $SVTResourcesFoundCount=0;
	
	
	# Indicates to fetch all resource groups
	SVTResourceResolver([string] $subscriptionId):
		Base($subscriptionId)
	{ }

	SVTResourceResolver([string] $subscriptionId, [string] $resourceGroupNames, [string] $resourceNames, [string] $resourceType, [ResourceTypeName] $resourceTypeName, [ResourceTypeName] $excludeResourceTypeName = [ResourceTypeName]::All, [string] $excludeResourceName , [string] $excludeResourceGroupName):
		Base($subscriptionId)
	{
		$this.ResourceType = $resourceType;
		$this.ResourceTypeName = $resourceTypeName;
		$this.ExcludeResourceTypeName = $excludeResourceTypeName;
		

		#throw if user has set params for ResourceTypeName and ResourceType
		#Default value of ResourceTypeName is All.
		if($this.ResourceTypeName -ne [ResourceTypeName]::All -and -not [string]::IsNullOrWhiteSpace($this.ResourceType)){
			throw [SuppressedException] "Both the parameters 'ResourceTypeName' and 'ResourceType' contain values. You should use only one of these parameters."
		}

		if($this.ResourceTypeName -ne [ResourceTypeName]::All -and $this.ExcludeResourceTypeName -ne [ResourceTypeName]::All){
			throw [SuppressedException] "Both the parameters 'ResourceTypeName' and 'ExcludeResourceTypeName' contain values. You should use only one of these parameters."
		}

		if(-not [string]::IsNullOrEmpty($resourceGroupNames))
        {
			$this.ResourceGroups += $this.ConvertToStringArray($resourceGroupNames);

			if ($this.ResourceGroups.Count -eq 0)
			{
				throw [SuppressedException] "The parameter 'ResourceGroupNames' does not contain any string."
			}
        }		
		if(-not [string]::IsNullOrEmpty($resourceNames))
		{
			$this.ResourceNames += $this.ConvertToStringArray($resourceNames)
			if ($this.ResourceNames.Count -eq 0)
			{
				throw [SuppressedException] "The parameter 'ResourceNames' does not contain any string."
			}
		}
		if(-not [string]::IsNullOrEmpty($excludeResourceName))
		{
			if([string]::IsNullOrEmpty($resourceNames))
			{
				$this.ExcludeResourceNames += $this.ConvertToStringArray($excludeResourceName)
				if ($this.ExcludeResourceNames.Count -eq 0)
				{
					throw [SuppressedException] "The parameter 'ExcludeResourceNames' does not contain any string."
				}
			}
			else 
			{
				 throw [SuppressedException] "Both the parameters 'ResourceNames' and 'ExcludeResourceNames' contain values. You should use only one of these parameters."
			}	
		}
		if(-not [string]::IsNullOrEmpty($excludeResourceGroupName))
		{
			if([string]::IsNullOrEmpty($resourceGroupNames))
			{
				$this.ExcludeResourceGroupNames += $this.ConvertToStringArray($excludeResourceGroupName)
				if ($this.ExcludeResourceGroupNames.Count -eq 0)
				{
					throw [SuppressedException] "The parameter 'ExcludeResourceGroupNames' does not contain any string."
				}
			}
			else 
			{
				throw [SuppressedException] "Both the parameters 'ResourceGroupNames' and 'ExcludeResourceGroupNames' contain values. You should use only one of these parameters."
			}	
		}

		
	}

	[void] LoadAzureResources()
	{
		$ControlSettings = [ConfigurationManager]::LoadServerConfigFile("ControlSettings.json");
		#Lazy load the SVT resource array
		if($this.SVTResources.Count -eq 0)
		{
			$resources = @();
			$EnableDevOpsKitSetupCheck = [ConfigurationManager]::GetAzSKConfigData().EnableDevOpsKitSetupCheck;
			$AzSKCfgResource=$null
			if($EnableDevOpsKitSetupCheck)
			{
				$settings = [ConfigurationManager]::GetAzSKSettings();
				[string] $laSource = $settings.LASource;
				if([string]::IsNullOrWhiteSpace($laSource) -or $laSource -eq "SDL"){					
					$AzSKCfgResource= [SVTResource]::new();
					$AzSKCfgResource.ResourceId = 'AzSKCfg';
					$AzSKCfgResource.ResourceGroupName = 'AzSKCfg';
					$AzSKCfgResource.ResourceName = 'AzSKCfg';
					$AzSKCfgResource.ResourceType = 'AzSKCfg';
					$AzSKCfgResource.Location = 'CentralUS';
					$AzSKCfgResource.ResourceTypeMapping = ([SVTMapping]::Mapping |
												Where-Object { $_.ResourceType -eq 'AzSKCfg' } |
												Select-Object -First 1);
					#This is to handle the case where user passes ResourceTypeName as 'AzSKCfg'
					if($this.ResourceTypeName -eq 'AzSKCfg')
					{
						$resources+=$AzSKCfgResource
						$AzSKCfgResource=$null 
					}
				}
				else
				{
					$AzSKCfgResource=$null 
				}
			}
			
			#Fetch Resources from Azure
			if($this.ResourceGroups.Count -eq 0 -or ($this.ResourceGroups.Count -eq 1 -and $this.ResourceGroups[0].Trim() -eq "*"))
			{
				#Target resource group param is not passed. Pass appropriate input params
				$resources += $this.FindAzureRmResource("");
				
			}
			else
			{
				#Fetch resources for all resource groups
				$this.ResourceGroups |
				ForEach-Object {
					$resouresFound = $this.FindAzureRmResource($_);

					if(($resouresFound | Measure-Object).Count -eq 0)
					{
						$this.PublishCustomMessage("Could not find any resources to scan under Resource Group [$_]", [MessageType]::Warning);
					}
					else
					{
						$resources += $resouresFound;
					}
				}
			}
			
			
			if(($resources | Measure-Object).Count -eq 0)
			{
				throw ([SuppressedException]::new(("Could not find any resources that match the specified criteria."), [SuppressedExceptionType]::InvalidOperation))
			}

			$allResourceTypes = [string[]] [ConfigurationManager]::LoadServerConfigFile("AllResourceTypes.json");

			$erVnetResourceGroups = $null;
			if($null -ne $AzSKCfgResource)
			{
				$this.SVTResources+=$AzSKCfgResource
			}		

			
			$resources | Where-Object { $this.ResourceNames.Count -le 1 -or $this.ResourceNames -contains $_.Name  } | ForEach-Object {
				$resource = $_
				$svtResource = [SVTResource]::new();
				$svtResource.ResourceId = $resource.ResourceId;
				$svtResource.ResourceGroupName = $resource.ResourceGroupName;
				$svtResource.ResourceName = $resource.Name;
				$svtResource.ResourceType = $resource.ResourceType;
				$svtResource.Location = $resource.Location;
				$svtResource.ResourceDetails = $_

				if($this.ResourceTypeName -ne [ResourceTypeName]::All)
				{
					$svtResource.ResourceTypeMapping = ([SVTMapping]::Mapping |
											Where-Object { $_.ResourceTypeName -eq $this.ResourceTypeName } |
											Select-Object -First 1);
				}
				else
				{
					$svtResource.ResourceTypeMapping = ([SVTMapping]::Mapping |
											Where-Object { $_.ResourceType -eq $resource.ResourceType } |
											Select-Object -First 1);
				}
				# Exclude resource type 

				# Exclude resource type 

				if($this.ExcludeResourceTypeName -ne [ResourceTypeName]::All)
				{
					$svtResource.ResourceTypeMapping = ([SVTMapping]::Mapping |
											Where-Object { $_.ResourceType -eq $resource.ResourceType -and $_.ResourceTypeName -ne $this.ExcludeResourceTypeName } |
											Select-Object -First 1);
				}

				# Checking if Vnet is ErVNet or not
				if($svtResource.ResourceTypeMapping -and $svtResource.ResourceTypeMapping.ResourceTypeName -eq [SVTMapping]::VirtualNetworkTypeName)
				{
					if(-not $erVnetResourceGroups)
					{
						$erVnetResourceGroups = $this.ConvertToStringArray([ConfigurationManager]::GetAzSKConfigData().ERvNetResourceGroupNames);
					}

					# Check if the resource group name corresponds to ERvNet
					if(($erVnetResourceGroups -contains $svtResource.ResourceGroupName) -or ([ResourceHelper]::IsvNetExpressRouteConnected($svtResource.ResourceName, $svtResource.ResourceGroupName)))
					{
						# Set the ERvNet type
						$svtResource.ResourceTypeMapping = ([SVTMapping]::Mapping |
											Where-Object { $_.ResourceTypeName -eq [SVTMapping]::ERvNetTypeName } |
											Select-Object -First 1);
					}
				}
				$ignoredType = $false;
				# Added APIConnectionTypeName in condition to explicitly exclude APIConnection (LogicApp connector) type while scanning
				# APIConnection (LogicApp connector) will be only scanned when logic app is being scanned.
				if(-not $svtResource.ResourceTypeMapping -or $svtResource.ResourceTypeMapping.ResourceTypeName -eq [SVTMapping]::APIConnectionTypeName)
				{
					$ignoredType = [string]::IsNullOrEmpty(($allResourceTypes | Where-Object { $_ -eq $resource.ResourceType } | Select-Object -First 1));
				}

				if(-not $ignoredType)
				{
					$this.SVTResources += $svtResource;
				}

				#filtering IPAddress resource
				if([Helpers]::CheckMember($ControlSettings,"PublicIpAddress") `
						-and [Helpers]::CheckMember($ControlSettings.PublicIpAddress,"EnablePublicIpResource"))
				{
					if($ControlSettings.PublicIpAddress.EnablePublicIpResource -ne "true")
				 {
					$filter = ($this.SVTResources | Where-Object { $_.ResourceType -ne 'Microsoft.Network/publicIPAddresses'});
					$this.SVTResources = $filter;
				 }
				}
				
			}
			$this.SVTResourcesFoundCount = ($this.SVTResources | Measure-Object).Count
				
			if((($this.ExcludeResourceGroupNames | Measure-Object).Count -gt 0) -or (($this.ExcludeResourceNames)| Measure-Object).Count -gt 0 -or (($this.ExcludeResourceTypeName) -ne 'All'))
			{
				$this.SVTResources = $this.ApplyResourceFilter($this.SVTResources)
			}
			
				
		}
	}

	hidden [SVTResource] CreateSVTResource([string] $ConnectionResourceId,[string] $ResourceGroupName, [string] $ConnectionResourceName, [string] $ResourceType, [string] $Location, [string] $MappingName)
	{
		$svtResource = [SVTResource]::new();
		$svtResource.ResourceId = $ConnectionResourceId; 
		$svtResource.ResourceGroupName = $ResourceGroupName;
		$svtResource.ResourceName = $ConnectionResourceName
		$svtResource.ResourceType = $ResourceType; # 
		$svtResource.Location = $Location;
		$svtResource.ResourceTypeMapping = ([SVTMapping]::Mapping |
						Where-Object { $_.ResourceTypeName -eq $MappingName } |
						Select-Object -First 1);

		return $svtResource;
	}

	hidden [System.Object[]] FindAzureRmResource([string] $resourceGroupName)
	{
		$expression = "Get-AzResource";

		if(-not [string]::IsNullOrEmpty($resourceGroupName))
		{
			$expression += " -ResourceGroupName '$resourceGroupName' " ;
		}

		if([string]::IsNullOrEmpty($this.ResourceType) -and ($this.ResourceTypeName -ne [ResourceTypeName]::All))
		{
			$mapping = ([SVTMapping]::Mapping |
                                    Where-Object { $_.ResourceTypeName -eq $this.ResourceTypeName.ToString() } |
                                    Select-Object -First 1);
			if($mapping)
			{
				$this.ResourceType = $mapping.ResourceType;
			}
		}

		if(-not [string]::IsNullOrEmpty($this.ResourceType))
		{
			$expression += " -ResourceType '$($this.ResourceType)' " ;
		}

		if($this.ResourceNames.Count -eq 1)
		{
			$expression += " -Name '$($this.ResourceNames[0])' " ;
		}
		
		if($this.Tag -and $this.Tag.Count -ne 0)
		{
			$tagValues = "";
			$this.Tag.GetEnumerator() |
			ForEach-Object {
				$tagValues += "'$($_.Name)'='$($_.Value)'; "
			};

			$expression += " -Tag @{ $tagValues }" ;

		}
		$result = @();
		$expressionResult = Invoke-Expression $expression
		if($expressionResult)
		{
			$result += $expressionResult
		}
		
		#To filter result based on just TagName if TagValue is not provided
		if(-not [string]::IsNullOrEmpty($this.TagName))
		{
				$result = $result | Where-Object {$null -ne $_.Tags -and ($null -ne $_.Tags.Keys )}
				if ([string]::IsNullOrEmpty($this.TagValue))
				{
					$result = $result | Where-Object{($_.Tags.GetEnumerator() | Where-Object {$_.Key -eq $this.TagName })}
				}
				else {
					$this.TagValue= $this.ConvertToStringArray($this.TagValue)
					$result = $result | Where-Object{($_.Tags.GetEnumerator() | Where-Object {$_.Key -eq $this.TagName -and $_.Value -in $this.TagValue })}
				}
		}		
		 
		return $result;
	}
	#method to filter SVT resources based on exclude flags
	hidden [SVTResource[]] ApplyResourceFilter($resources)
	{
			
		$ResourceFilterMessage=[string]::Empty
		$ResourceGroupFilterMessage=[string]::Empty
		#First remove resource from the RGs specified in -ExcludeResourceGroupNames
		if(($this.ExcludeResourceGroupNames | Measure-Object).Count )
		{
			$matchingRGs= $this.ExcludeResourceGroupNames | Where-Object{$_ -in $resources.ResourceGroupName}
			$nonExistingRGS = $this.ExcludeResourceGroupNames | Where-Object{$_ -notin $matchingRGs}
			if(($nonExistingRGS| Measure-Object).Count -gt 0)
			{
				#print the message saying these RGS provided in excludeRGS are not found
				$NonExistingRGMessage=$nonExistingRGS -join "`n`t "
				$ResourceGroupFilterMessage+=[string]::Format("Warning: Did not find following resource groups requested for exclusion:	`n`t {0}",$NonExistingRGMessage);
			}
			if(($matchingRGs| Measure-Object).Count -gt 0 )
			{
				if(($this.ExcludeResourceNames | Measure-Object).Count)
				{
					$coincidingResources = $resources | Where-Object {$_.ResourceName -in $this.ExcludeResourceNames -and $_.ResourceGroupName -in $matchingRGs}
					if(($coincidingResources| Measure-Object).Count -gt 0)
					{
						$this.ExcludeResourceNames = $this.ExcludeResourceNames | Where-Object {$_ -notin $coincidingResources.ResourceName}
					}
				}
				$excludedRes= $resources| Where-Object{$_.ResourceGroupName -in $matchingRGs}
				$this.ExcludedResources+=$excludedRes
				$this.ExcludedResourceGroupNames+=$matchingRGs
			}
			else 
			{
				$this.ExcludedResourceGroupNames=$null
				#no matching resource group found to be exclude
			}
			
		}
		
		#Remove resources specified in -ExcludeResourceNames
		if(($this.ExcludeResourceNames | Measure-Object).Count)
		{
			# check if resources specified in -xrns exist. If not then show a warning for those resources.
			$ResourcesToExclude =$this.ExcludeResourceNames
			$NonExistingResource = $this.ExcludeResourceNames | Where-Object { $_ -notin $resources.ResourceName}
			if(($NonExistingResource | Measure-Object).Count -gt 0 )
			{
				$ResourcesToExclude = $this.ExcludeResourceNames | Where-Object{ $_ -notin $NonExistingResource }
				$NonExistingResourceMessage=$NonExistingResource -join "	`n`t "
				$ResourceFilterMessage+=[string]::Format("Warning: Did not find the following resources requested for exclusion: `n`t {0}",$NonExistingResourceMessage );
			}	
			#check if duplicate resources names if exist in -xrns
			$matchingResources = $resources | Where-Object { $_.ResourceName -in $this.ExcludeResourceNames}
			if(($ResourcesToExclude| Measure-Object).Count -gt 0)
			{
				if(($matchingResources | Measure-Object).Count -gt 0)
				{
					$duplicateResourceNames= $matchingResources | Group-Object -Property ResourceName 
					$duplicateResourceNames = $duplicateResourceNames | Where-Object { $_.Count -gt 1} 
					if(($duplicateResourceNames| Measure-Object).Count -gt 0 )
					{
						$duplicateResources=""
						$duplicates=$resources | Where-Object{$_.ResourceName -in $duplicateResourceNames.Name}|Select-Object -Property ResourceName,ResourceGroupName,ResourceTypeMapping
						$ResourceFilterMessage+="`nWarning: Multiple matches for the following resources found. All matching resources will be excluded.`n"
						$duplicates|ForEach-Object{
							$duplicateResources+=[string]::Format("	 {0}(RG: {1}, TypeName: {2})`n",($_.ResourceName),($_.ResourceGroupName),($_.ResourceTypeMapping.ResourceTypeName))
						}
						$ResourceFilterMessage+=$duplicateResources
					}
					$this.ExcludedResources += $matchingResources
				}
				
			}
					
		}
		# Exclude resources for the type specified in ExcludeResourceType
		if($this.ExcludeResourceTypeName -ne [ResourceTypeName]::All)
		{
										
			$resources| ForEach-Object{
				if($null -ne $_.ResourceTypeMapping )
				{
					if($_.ResourceTypeMapping.ResourceTypeName -eq $this.ExcludeResourceTypeName)
					{
						$this.ExcludedResources+=$_
					}
				}
			}
		
		}
			
		$resources=$resources| Where-Object {$_ -notin $this.ExcludedResources} 
		$this.ExcludeResourceWarningMessage=$ResourceFilterMessage;
		$this.ExcludeResourceGroupWarningMessage=$ResourceGroupFilterMessage;
		return $resources
	
	}
	
}

