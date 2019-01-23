Set-StrictMode -Version Latest 
class WriteFixControlFiles: FileOutputBase
{   
    hidden static [WriteFixControlFiles] $Instance = $null;
    hidden static [string] $FixFolderPath = "FixControlScripts";
    hidden static [string] $FixFilePath = "\Core\FixControl\Services\";
    
    hidden static [string] $RunScriptMessage = "# AzSK repair function uses files from the 'Services' sub-folder in this folder";
	 hidden static [string] $RunAzureServicesSecurity = '
# Repair Azure resources
Repair-AzSKAzureServicesSecurity `
	-ParameterFilePath "$PSScriptRoot\FixControlConfig.json" #`
	#-ResourceGroupNames "" `
	#-ResourceTypeNames "" `
	#-ResourceNames "" `
	#-ControlIds ""';
    hidden static [string] $RunSubscriptionSecurity = '
# Repair Azure subscription
Repair-AzSKSubscriptionSecurity `
	-ParameterFilePath "$PSScriptRoot\FixControlConfig.json" #`
	#-ControlIds ""';

    static [WriteFixControlFiles] GetInstance()
    {
        if ( $null -eq [WriteFixControlFiles]::Instance)
        {
            [WriteFixControlFiles]::Instance = [WriteFixControlFiles]::new();
        }
    
        return [WriteFixControlFiles]::Instance
    }

    [void] RegisterEvents()
    {
        $this.UnregisterEvents();       

        $this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
            $currentInstance = [WriteFixControlFiles]::GetInstance();
            try 
            {
                $currentInstance.SetRunIdentifier([AzSKRootEventArgument] ($Event.SourceArgs | Select-Object -First 1));            
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

        $this.RegisterEvent([SVTEvent]::CommandCompleted, {
            $currentInstance = [WriteFixControlFiles]::GetInstance();
            try 
            {
				$currentInstance.CommandCompletedAction($Event.SourceArgs);
                $currentInstance.FilePath = "";
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });
    }

	hidden [SVTEventContext[]] GetFixControlEventContext([SVTEventContext[]] $arguments, [ref]$fixFileNames)
	{
		$resultContext = @();
		$fixFileNames.Value = @();

		$arguments | Where-Object { $_.ControlItem.Enabled -and ($null -ne $_.ControlItem.FixControl) -and $_.ControlResults -and $_.ControlResults.Count -ne 0 } | 
		ForEach-Object {
			$eventContext = $_;

			if(($eventContext.ControlResults | Where-Object { $_.EnableFixControl } | Measure-Object).Count -ne 0)
			{
				$mapping = $null;
				if($eventContext.IsResource())
				{
					$mapping = ([SVTMapping]::Mapping | 
								Where-Object { $_.ResourceTypeName -eq $eventContext.ResourceContext.ResourceTypeName } | 
								Select-Object -First 1);
				}
				else
				{
					$mapping = [SVTMapping]::SubscriptionMapping;
				}
				
				if($mapping -and (-not [string]::IsNullOrWhiteSpace($mapping.FixFileName)) -and (-not [string]::IsNullOrWhiteSpace($mapping.FixClassName)))
				{
					$resultContext += $eventContext;
					if($fixFileNames.Value -notcontains $mapping.FixFileName)
					{
						$fixFileNames.Value += $mapping.FixFileName;
					}
				}
			}
		};

		return $resultContext;
	}

	hidden [void] InitializeFolder([SubscriptionContext] $subContext, [string[]] $fixControlFileNames, [string] $runScriptContent)
	{
		$this.SetFolderPath($subContext);
		Copy-Item ("$PSScriptRoot\" + [WriteFixControlFiles]::FixFolderPath) $this.FolderPath -Recurse

        $this.SetFilePath($subContext, [WriteFixControlFiles]::FixFolderPath, "RunFixScript.ps1");
		Add-Content -Value $runScriptContent -Path $this.FilePath

        $this.SetFilePath($subContext, [WriteFixControlFiles]::FixFolderPath, "FixControlConfig.json");
				
		$parentFolderPath = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName;
		$parentFolderPath += [WriteFixControlFiles]::FixFilePath;
		$fixControlFileNames | ForEach-Object {
			mkdir -Path ($this.FolderPath + "\Services\") | Out-Null
			Copy-Item ($parentFolderPath + $_) ($this.FolderPath + "\Services\" + $_)
		};
	}

	[void] CommandCompletedAction([SVTEventContext[]] $arguments)
	{
		if($arguments -and $arguments.Count -ne 0)
		{
			$fixControlEventContext = @();
			[string[]] $fixControlFileNames = @();

			$fixControlEventContext += $this.GetFixControlEventContext($arguments, [ref]$fixControlFileNames);

			if($fixControlEventContext.Count -ne 0)
			{
				$output = @();
				$hasSubControls = $false;
				$hasResourceControls = $false;

				$fixControlEventContext | Group-Object { $_.SubscriptionContext.SubscriptionId } | 
				ForEach-Object {
					$sub = $_.Group;
					$subObject = [FixControlConfig]@{
						SubscriptionContext = $sub[0].SubscriptionContext;
					};
					$output += $subObject;

					$sub | Where-Object { -not $_.IsResource() } |
					ForEach-Object {
						$hasSubControls = $true;
						$subObject.SubscriptionControls += $this.CreateControlParam($_);
					};

					$sub | Where-Object { $_.IsResource() } | Group-Object { $_.ResourceContext.ResourceGroupName } | 
					ForEach-Object {
						$rgObject = [ResourceGroupConfig]@{
							ResourceGroupName = $_.Name;
						};
						$hasResourceControls = $true;
						$subObject.ResourceGroups += $rgObject;
						$_.Group | Group-Object { $_.ResourceContext.ResourceName } |
						ForEach-Object {
							$resource = $_.Group[0];
							$resObject = [ResourceConfig]@{
								ResourceName = $resource.ResourceContext.ResourceName;
								ResourceType = $resource.ResourceContext.ResourceType;
								ResourceTypeName = $resource.ResourceContext.ResourceTypeName;									
							};

							$rgObject.Resources += $resObject;

							$resObject.Controls += $this.CreateControlParam($_.Group);
						};
					};
				};

				if($output.Count -ne 0)
				{
					$runScriptContent = [WriteFixControlFiles]::RunScriptMessage;
					if($hasSubControls)
					{
						$runScriptContent += [WriteFixControlFiles]::RunSubscriptionSecurity;
					}

					if($hasResourceControls)
					{
						$runScriptContent += [WriteFixControlFiles]::RunAzureServicesSecurity;
					}

					$this.InitializeFolder(($fixControlEventContext | Select-Object -First 1).SubscriptionContext, $fixControlFileNames, $runScriptContent);
					[Helpers]::ConvertToJsonCustom($output, 15, 15) | Out-File $this.FilePath
				}				
			}			
		}
	}

	hidden [ControlParam[]] CreateControlParam([SVTEventContext[]] $resources)
	{
		$result = @();
		$resources | Group-Object { $_.ControlItem.Id } |
		ForEach-Object {
			$context = $_.Group[0];
			$controlObject = [ControlParam]@{
				ControlID = $context.ControlItem.ControlID;
				Id = $context.ControlItem.Id;
				ControlSeverity = $context.ControlItem.ControlSeverity;
				FixControlImpact = $context.ControlItem.FixControl.FixControlImpact;
				Description = $context.ControlItem.Description;
				Enabled = $context.ControlItem.Enabled;						
			};

			$result += $controlObject;

			$_.Group | ForEach-Object {
				$_.ControlResults | Where-Object { $_.EnableFixControl } | ForEach-Object {
					$controlObject.ChildResourceParams += [ChildResourceParam]@{
						ChildResourceName = $_.ChildResourceName;
						Parameters = $_.FixControlParameters;
					};
				};
			};
		};
		return $result;
	}
}
