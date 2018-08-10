Set-StrictMode -Version Latest

class SVTResourceResolver: AzSKRoot
{
    [string[]] $ResourceNames = @();
    [string] $ResourceType = "";
    [ResourceTypeName] $ResourceTypeName = [ResourceTypeName]::All;
	[Hashtable] $Tag = $null;
    [string] $TagName = "";
    [string] $TagValue = "";
	hidden [string[]] $ResourceGroups = @();

	[SVTResource[]] $SVTResources = @();
	
	# Indicates to fetch all resource groups
	SVTResourceResolver([string] $subscriptionId):
		Base($subscriptionId)
	{ }

	SVTResourceResolver([string] $subscriptionId, [string] $resourceGroupNames, [string] $resourceNames, [string] $resourceType, [ResourceTypeName] $resourceTypeName):
		Base($subscriptionId)
	{
		$this.ResourceType = $resourceType;
		$this.ResourceTypeName = $resourceTypeName;

		#throw if user has set params for ResourceTypeName and ResourceType
		#Default value of ResourceTypeName is All.
		if($this.ResourceTypeName -ne [ResourceTypeName]::All -and -not [string]::IsNullOrWhiteSpace($this.ResourceType)){
			throw [SuppressedException] "Both the parameters 'ResourceTypeName' and 'ResourceType' contains values. You should use only one of these parameters."
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
	}

	[void] LoadAzureResources()
	{
		#Lazy load the SVT resource array
		if($this.SVTResources.Count -eq 0)
		{
			$resources = @();
			$EnableDevOpsKitSetupCheck = [ConfigurationManager]::GetAzSKConfigData().EnableDevOpsKitSetupCheck;
			$AzSKCfgResource=$null
			if($EnableDevOpsKitSetupCheck)
			{
				$settings = [ConfigurationManager]::GetAzSKSettings();
				[string] $omsSource = $settings.OMSSource;
				if([string]::IsNullOrWhiteSpace($omsSource) -or $omsSource -eq "SDL"){					
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

			if($resources.Count -eq 0)
			{
				throw ([SuppressedException]::new(("Could not find any resources that match the specified criteria."), [SuppressedExceptionType]::InvalidOperation))
			}

			$allResourceTypes = [string[]] [ConfigurationManager]::LoadServerConfigFile("AllResourceTypes.json");

			$erVnetResourceGroups = $null;
			if($null -ne $AzSKCfgResource)
			{
				$this.SVTResources+=$AzSKCfgResource
			}		

			$resources | Where-Object { $this.ResourceNames.Count -le 1 -or $this.ResourceNames -contains $_.Name} | ForEach-Object {
				$resource = $_
				$svtResource = [SVTResource]::new();
				$svtResource.ResourceId = $resource.ResourceId;
				$svtResource.ResourceGroupName = $resource.ResourceGroupName;
				$svtResource.ResourceName = $resource.Name;
				$svtResource.ResourceType = $resource.ResourceType;
				$svtResource.Location = $resource.Location;

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

				# Checking if Vnet is ErVNet or not
				if($svtResource.ResourceTypeMapping -and $svtResource.ResourceTypeMapping.ResourceTypeName -eq [SVTMapping]::VirtualNetworkTypeName)
				{
					if(-not $erVnetResourceGroups)
					{
						$erVnetResourceGroups = $this.ConvertToStringArray([ConfigurationManager]::GetAzSKConfigData().ERvNetResourceGroupNames);
					}

					# Check if the resource group name corresponds to ERvNet
					if(($erVnetResourceGroups -contains $svtResource.ResourceGroupName) -or ([Helpers]::IsvNetExpressRouteConnected($svtResource.ResourceName, $svtResource.ResourceGroupName)))
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
		$expression = "Get-AzureRmResource";

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
		elseif((-not [string]::IsNullOrEmpty($this.TagName)) -and (-not [string]::IsNullOrEmpty($this.TagValue)))
		{
			$expression += " -TagName '$($this.TagName)' -TagValue '$($this.TagValue)'" ;
		}

		$result = @();
		$expressionResult = Invoke-Expression $expression
		if($expressionResult)
		{
			$result += $expressionResult
		}
		return $result;
	}
	
}

