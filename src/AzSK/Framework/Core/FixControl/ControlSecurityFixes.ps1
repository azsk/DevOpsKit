Set-StrictMode -Version Latest 

class ControlSecurityFixes: CommandBase
{    
	hidden [string] $ParameterFilePath = "";
	hidden [string[]] $FolderPaths = @();
	[bool] $Force = $false;

	[FixControlConfig] $FixControlParam;

	ControlSecurityFixes([string] $subscriptionId, [InvocationInfo] $invocationContext, [FixControlConfig] $fixControlParam, [string] $parameterFilePath): 
        Base($subscriptionId, $invocationContext)
    { 
		if(-not $fixControlParam)
		{
            throw [System.ArgumentException] ("The argument 'fixControlParam' is null");
		}
		$this.FixControlParam = $fixControlParam;

		if(-not [string]::IsNullOrEmpty($parameterFilePath))
        {
			$this.ParameterFilePath = $parameterFilePath;
			$this.FolderPaths += [System.IO.Path]::GetDirectoryName($parameterFilePath) + "\Services\";
			$this.FolderPaths += "$PSScriptRoot\Services\";
		}
		else
		{
			throw [System.ArgumentException] "The parameter 'parameterFilePath' is null or empty."
		}
	}

	[string] $ImpactText = "FixControlImpact";
	[string] $ControlsText = "Controls";
	[string] $TotalText = "Total";
	[string] $MarkerText = "--------";

	hidden [void] UpdateSummaryCount([PSObject[]] $summary, [ControlParam[]] $controls)
	{
		if($controls -and $controls.Count -ne 0)
		{
			$totalRow = $summary | Where-Object { $_.$($this.ImpactText) -eq $this.TotalText } | Select-Object -First 1;

			$controls | Group-Object { $_.$($this.ImpactText) } |
			ForEach-Object {
				$item = $_;
				$currentRow = $summary | Where-Object { $_.$($this.ImpactText) -eq $item.Name } | Select-Object -First 1;
				if($currentRow)
				{
					$currentRow.$($this.ControlsText) += $item.Count;
				}

				if($totalRow)
				{
					$totalRow.$($this.ControlsText) += $item.Count;
				}
			};
		}
	}

	hidden [void] PrintFixControlImpact()
	{
		$summary = @();
		[Enum]::GetNames([FixControlImpact]) |
		ForEach-Object {
			$row = [PSObject]::new();
			Add-Member -InputObject $row -Name $this.ImpactText -MemberType NoteProperty -Value $_.ToString()
			Add-Member -InputObject $row -Name $this.ControlsText -MemberType NoteProperty -Value 0
			$summary += $row;
		};

		$markerRow = [PSObject]::new();
		Add-Member -InputObject $markerRow -Name $this.ImpactText -MemberType NoteProperty -Value $this.MarkerText
		Add-Member -InputObject $markerRow -Name $this.ControlsText -MemberType NoteProperty -Value $this.MarkerText
		$summary += $markerRow;

		$totalRow = [PSObject]::new();
		Add-Member -InputObject $totalRow -Name $this.ImpactText -MemberType NoteProperty -Value $this.TotalText
		Add-Member -InputObject $totalRow -Name $this.ControlsText -MemberType NoteProperty -Value 0
		$summary += $totalRow;

		if($this.FixControlParam.SubscriptionControls.Count -ne 0)
		{
			$this.UpdateSummaryCount($summary, $this.FixControlParam.SubscriptionControls);			
		}

		if($this.FixControlParam.ResourceGroups.Count -ne 0)
		{
			$this.FixControlParam.ResourceGroups | ForEach-Object {
				$_.Resources | ForEach-Object {
					$resource = $_.Controls;
					$this.UpdateSummaryCount($summary, $_.Controls);			
				};
			};
		}

		$this.PublishCustomMessage(" `r`n" + ($summary | Format-Table | Out-String), [MessageType]::Info);
	}

	[MessageData[]] ImplementFix()
    {
		$this.PrintFixControlImpact();
		[MessageData[]] $messages = @();

		$this.PublishCustomMessage([MessageData]::new(" `nRunning this command will make changes to your Azure subscription/resource configurations in order to fix/remediate security controls. Please confirm that you have reviewed the proposed changes.", [MessageType]::Warning));
		$response = ""
		if($this.Force)
		{
			$response = "y";
			$this.PublishCustomMessage([MessageData]::new("User consent has been supressed by -Force parameter.", [MessageType]::Warning));
		}

		while($response -ne "y" -and $response -ne "n")
		{
			if(-not [string]::IsNullOrEmpty($response))
			{
				Write-Host "Please select appropriate option."
			}
			$response = Read-Host "Do you want to continue (Y/N)?"
			$response = $response.Trim()
		}
		if($response -eq "y")
		{
			$this.PublishCustomMessage("User has provided consent to implement the control fixes.");
			$this.PublishCustomMessage([Constants]::DoubleDashLine);
			$this.PublishCustomMessage("Started implementing control recommendations");
			$this.PublishCustomMessage("[SubscriptionId: $($this.FixControlParam.SubscriptionContext.SubscriptionId)] [SubscriptionName: $($this.FixControlParam.SubscriptionContext.SubscriptionName)]");
		
			# SSCore Fixes
			if($this.FixControlParam.SubscriptionControls.Count -ne 0)
			{
				$exceptionMessage = "Exception for subscription: [SubscriptionName: $($this.SubscriptionContext.SubscriptionName)] [SubscriptionId: $($this.SubscriptionContext.SubscriptionId)]"
				$wrapperObj = [ArrayWrapper]::new($this.FixControlParam.SubscriptionControls);
				$messages += $this.FixAllControls([SVTMapping]::SubscriptionMapping, $wrapperObj, [string] $exceptionMessage)
			}

			# Resource fixes
			if($this.FixControlParam.ResourceGroups.Count -ne 0)
			{
				$totalResources = 0;
				[int] $currentCount = 0;
				$this.FixControlParam.ResourceGroups | ForEach-Object { $totalResources += $_.Resources.Count };
				$this.FixControlParam.ResourceGroups | ForEach-Object {
					$resourceGroup = $_;
					$resourceGroup.Resources | ForEach-Object {
						$resource = $_;
						$exceptionMessage = "Exception for resource: [ResourceType: $($resource.ResourceTypeMapping.ResourceTypeName)] [ResourceGroupName: $($resourceGroup.ResourceGroupName)] [ResourceName: $($resource.ResourceName)]"
						$currentCount += 1;
						if($totalResources -gt 1)
						{
							$this.PublishCustomMessage(" `r`nFixing resource [$currentCount/$totalResources] ");
						}

						$messages += $this.FixAllControls($_.ResourceTypeMapping, @($resource, $resourceGroup.ResourceGroupName), [string] $exceptionMessage)
					};
				};
			}
		}
		else
		{
			$this.PublishCustomMessage("The command execution aborted.")
		}

		return $messages;
    }

	[MessageData[]] FixAllControls([SubscriptionMapping] $typeMapping, [PSObject[]] $argumentList, [string] $exceptionMessage)
	{
		[MessageData[]] $messages = @();
		try 
		{
			if(-not $argumentList)
			{
				$argumentList = @();
			}

			foreach ($path in $this.FolderPaths) {
				$fileToLoad = $path + $typeMapping.FixFileName;
				if(Test-Path -Path $fileToLoad)
				{
					. $fileToLoad
					break;
				}
			}
			
			$svtFixObject = $null;
			$fixClassName = $typeMapping.FixClassName;
			try
			{	
				$args = @();
				$args += $this.SubscriptionContext.SubscriptionId;
				$args += $argumentList;
				$svtFixObject = New-Object -TypeName $fixClassName -ArgumentList $args
			}
			catch
			{
				$this.PublishCustomMessage($exceptionMessage);
				if($_.Exception.InnerException)
				{
					# Unwrapping the first layer of exception which is added by New-Object function
					$this.CommandError($_.Exception.InnerException.ErrorRecord);
				}
				else
				{
					$this.CommandError($_);
				}
			}

			if($svtFixObject)
			{
				$messages += $svtFixObject.FixAllControls();
			}

			# Register/Deregister all listeners to cleanup the memory
			[ListenerHelper]::RegisterListeners();
		}
		catch 
		{
			$this.PublishCustomMessage($exceptionMessage);
			$this.CommandError($_);
		}
		return $messages;
	}
}
