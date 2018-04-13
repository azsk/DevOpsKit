Set-StrictMode -Version Latest

class FixControlConfigResolver: EventBase
{
	[string] $FolderPath = "";
	[string] $ConfigFilePath = "";
	[string] $InputFilePath = "";
	hidden [FixControlConfig[]] $FileContent = $null;

	[FixControlConfig[]] $FixControlResult = $null;

	[bool] $SubscriptionControls = $false;
	hidden [bool] $IsModified = $false;
	
	[string[]] $SubscriptionIds = @();
	[string[]] $ResourceGroupNames = @();
	[string[]] $ResourceTypes = @();
	[string[]] $ResourceTypeNames = @();
	[string[]] $ResourceNames = @();
	[string[]] $ControlIds = @();

	FixControlConfigResolver([string] $parameterFilePath, [string] $subscriptionIds, [string] $controlIds, [bool] $subscriptionControls)
	{
		$this.ParseParameterFile($parameterFilePath);
		$this.SubscriptionControls = $subscriptionControls;
		$this.SubscriptionIds += $this.ConvertToStringArray($subscriptionIds);
		$this.ControlIds += $this.ConvertToStringArray($controlIds);

		if($this.SubscriptionIds.Count -ne 0 -or $this.ControlIds.Count -ne 0)
		{
			# set the flag to true so that a copy of file will get generated
			$this.IsModified = $true;
		}
	}

	FixControlConfigResolver([string] $parameterFilePath, [string] $subscriptionIds, [string] $resourceGroupNames, [string] $resourceTypes, [string] $resourceTypeNames, [string] $resourceNames, [string] $controlIds)
	{
		$this.ParseParameterFile($parameterFilePath);
		$this.SubscriptionIds += $this.ConvertToStringArray($subscriptionIds);
		$this.ResourceGroupNames += $this.ConvertToStringArray($resourceGroupNames);
		$this.ResourceTypes += $this.ConvertToStringArray($resourceTypes);
		$this.ResourceTypeNames += $this.ConvertToStringArray($resourceTypeNames);
		$this.ResourceNames += $this.ConvertToStringArray($resourceNames);
		$this.ControlIds += $this.ConvertToStringArray($controlIds);

		if($this.SubscriptionIds.Count -ne 0 -or
			$this.ResourceGroupNames.Count -ne 0 -or
			$this.ResourceTypes.Count -ne 0 -or
			$this.ResourceTypeNames.Count -ne 0 -or
			$this.ResourceNames.Count -ne 0 -or
			$this.ControlIds.Count -ne 0)
		{
			# set the flag to true so that a copy of file will get generated
			$this.IsModified = $true;
		}
	}

	hidden [void] ParseParameterFile([string] $parameterFilePath)
	{
		if(-not [string]::IsNullOrEmpty($parameterFilePath))
        {
			$rawContent = @();
			if(Test-Path -Path $parameterFilePath)
			{
				$rawContent += (Get-Content -Raw -Path $parameterFilePath) | ConvertFrom-Json
			}
			else 
			{
				throw [SuppressedException] "Unable to find the parameter file [$parameterFilePath]";
			}

			if($rawContent.Count -ne 0)
			{
				$this.FileContent = @();
				$rawContent | ForEach-Object {
					try
					{
						$this.FileContent += [FixControlConfig] $_;
					}
					catch
					{
						$this.PublishException($_);
					}
				};
			}
		
			if(-not ($this.FileContent -and $this.FileContent.Count -ne 0))
			{
				throw [SuppressedException] "Parameter file [$parameterFilePath] is empty";
			}
			$this.FolderPath = [System.IO.Path]::GetDirectoryName($parameterFilePath) ;
			$this.InputFilePath = $parameterFilePath;
        }
		else
		{
			throw ([SuppressedException]::new(("The parameter 'ParameterFilePath' is null or empty."), [SuppressedExceptionType]::NullArgument))
		}
	}

	[FixControlConfig[]] GetFixControlParameters()
	{
		if(-not $this.FixControlResult)
		{	
			$this.PublishCustomMessage("Validating FixControl configuration file...");
			$this.FixControlResult = @();

			$this.FileContent | Where-Object { ($this.SubscriptionIds.Count -eq 0) -or ($this.SubscriptionIds -contains $_.SubscriptionContext.SubscriptionId) } | 
			ForEach-Object {
				$sub = $_;
				$subControls = @();
				$resourceGroups = @();
				
				if($this.SubscriptionControls)
				{
					# Subscription controls
					$subControls += $this.ProcessControls($sub.SubscriptionControls, $sub.SubscriptionContext, $null, $null);
				}
				else
				{
					# Process Resources
					$sub.ResourceGroups | Where-Object { ($this.ResourceGroupNames.Count -eq 0) -or ($this.ResourceGroupNames -contains $_.ResourceGroupName) } | 
					ForEach-Object {
						$resourceGroup = $_;
						$resources = @();

						$resourceGroup.Resources | 
							Where-Object { ($this.ResourceTypes.Count -eq 0) -or ($this.ResourceTypes -contains $_.ResourceType) } | 
							Where-Object { ($this.ResourceTypeNames.Count -eq 0) -or ($this.ResourceTypeNames -contains $_.ResourceTypeName) } | 
							Where-Object { ($this.ResourceNames.Count -eq 0) -or ($this.ResourceNames -contains $_.ResourceName) } | 
							ForEach-Object {
								$resource = $_;
								$controls = @();

								if(-not [string]::IsNullOrWhiteSpace($resource.ResourceTypeName))
								{
									$resource.ResourceTypeMapping = ([SVTMapping]::Mapping |
												Where-Object { $_.ResourceTypeName -eq $resource.ResourceTypeName } |
												Select-Object -First 1);
								}

								if($resource.ResourceTypeMapping)
								{
									$controls += $this.ProcessControls($resource.Controls, $sub.SubscriptionContext, $resourceGroup, $resource);
								
									if($controls.Count -ne 0)
									{
										$resource.Controls = @();
										$resource.Controls += $controls;
										$resources += $resource;
									}
								}
								else
								{
									$this.PublishCustomMessage("The parameter 'ResourceTypeName' is invalid in file.`r`nNo fix will be applied for [Resource: $($resource.ResourceName)] [ResourceGroup: $($resourceGroup.ResourceGroupName)]", [MessageType]::Error);
								}
							};

						if($resources.Count -ne 0)
						{
							$resourceGroup.Resources = @();
							$resourceGroup.Resources += $resources;
							$resourceGroups += $resourceGroup;
						}
					};
				}

				if($resourceGroups.Count -ne 0 -or $subControls.Count -ne 0)
				{
					$sub.SubscriptionControls = @();
					$sub.SubscriptionControls += $subControls;
					$sub.ResourceGroups = @();
					$sub.ResourceGroups += $resourceGroups;
					$this.FixControlResult += $sub;
				}
			};

			if($this.FixControlResult.Count -eq 0)
			{
				throw ([SuppressedException]::new(("There are no controls to fix in the parameter file."), [SuppressedExceptionType]::InvalidOperation))
			}
			
			$this.PublishCustomMessage("Validation completed", [MessageType]::Update);

			if($this.IsModified)
			{
				$this.PublishCustomMessage("Saving the parameter file with the input values...");
				$this.ConfigFilePath = $this.FolderPath + "\FixControlConfig-" + $this.GenerateRunIdentifier() + ".json";
				[Helpers]::ConvertToJsonCustom($this.FixControlResult, 15, 15) | Out-File $this.ConfigFilePath
				$this.PublishCustomMessage("Parameter file has been saved to: '$($this.ConfigFilePath)'");
			}
			else
			{
				$this.ConfigFilePath = $this.InputFilePath;
			}
		}

		return $this.FixControlResult;
	}

	hidden [ControlParam[]] ProcessControls([ControlParam[]] $controls, [SubscriptionContext] $subContext, [ResourceGroupConfig] $resourceGroup, [ResourceConfig] $resource)
	{
		[ControlParam[]] $resultControls = @();

		if($controls -and $controls.Count -ne 0)
		{
			$controls | Where-Object { $_.Enabled -and (($this.ControlIds.Count -eq 0) -or ($this.ControlIds -contains $_.ControlID)) } |
			ForEach-Object {
				$control = $_;

				$printHeader = $true;
				$printFooter = $false;
				$control.ChildResourceParams |
				ForEach-Object {
					$childParam = $_;

					$nullParams = @();
					if($childParam.Parameters)
					{
						$nullParams += [Helpers]::GetProperties($childParam.Parameters) | Where-Object { -not $childParam.Parameters.$_ };
					}
							
					if($nullParams.Count -ne 0)
					{
						$message = "";
						# Print header
						if($printHeader)
						{
							$printHeader = $false;
							$printFooter = $true;
							
							$message += [Constants]::DoubleDashLine;
							$message += "`nSome additional values are required to fix the control"
							$message += "`n" + [Constants]::SingleDashLine;
							$message += "`nSubscription`t`t: $($subContext.SubscriptionName) [$($subContext.SubscriptionId)]";
							if($resourceGroup)
							{
								$message += "`nResource Group`t`t: $($resourceGroup.ResourceGroupName)";
								if($resource)
								{
									$message += "`nResource Type Name`t: $($resource.ResourceTypeName)";
									$message += "`nResource Name`t`t: $($resource.ResourceName)";
								}
							}
							$message += "`nControlId`t`t`t: $($control.ControlId)";
							$message += "`nControlSeverity`t`t: $($control.ControlSeverity)";
							$message += "`nDescription`t`t`t: $($control.Description)";
						}
						#else
						#{
						if(-not [string]::IsNullOrWhiteSpace($childParam.ChildResourceName))
						{
							if(-not [string]::IsNullOrWhiteSpace($message))
							{
								$message += "`n";
							}
							$message += "Child Resource Name`t`t: $($childParam.ChildResourceName)";
						}
						#}
						$this.IsModified = $true;
						$message += "`n`nPlease provide valid inputs for following..."
						$this.PublishCustomMessage($message);

						$nullParams | ForEach-Object {
							$userValue = "";
							while([string]::IsNullOrWhiteSpace($userValue))
							{
								$userValue = Read-Host "$_"
								$userValue = $userValue.Trim();
							}
							$childParam.Parameters.$_ = $userValue;
						};
					}
				};
				if($printFooter)
				{
					$this.PublishCustomMessage([Constants]::DoubleDashLine);
				}

				$resultControls += $control;	
			};
		}
		return $resultControls;
	}
}

