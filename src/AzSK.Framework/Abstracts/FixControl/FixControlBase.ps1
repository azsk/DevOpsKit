Set-StrictMode -Version Latest 
class FixControlBase: AzSKRoot
{
    hidden [SVTConfig] $SVTConfig
    hidden [PSObject] $ControlSettings
	hidden [ControlParam[]] $Controls = @();

    FixControlBase([string] $subscriptionId): 
        Base($subscriptionId)
    { 
		[Helpers]::AbstractClass($this, [FixControlBase]); 
	}
	
    hidden [void] LoadSvtConfig([string] $controlsJsonFileName)
    {
		if ([string]::IsNullOrEmpty($controlsJsonFileName))
		{
            throw [System.ArgumentException] ("JSON file name is null or empty");    
        }

        $this.ControlSettings = $this.LoadServerConfigFile("ControlSettings.json");

        if (-not $this.SVTConfig) 
		{
            $this.SVTConfig = [ConfigurationManager]::GetSVTConfig($controlsJsonFileName); 
        }
    }

    [bool] ValidateMaintenanceState()
    {  
        if ($this.SVTConfig.IsMaintenanceMode) 
		{
            $this.PublishCustomMessage(([ConfigurationManager]::GetAzSKConfigData().MaintenanceMessage -f $this.SVTConfig.FeatureName), [MessageType]::Warning);
        }
        return $this.SVTConfig.IsMaintenanceMode;
    }  

    [MessageData[]] FixAllControls()
    {
		[MessageData[]] $messages = @();
        if (-not $this.ValidateMaintenanceState()) 
		{
			if($this.Controls.Count -ne 0)
			{
				$messages += $this.FixStarted();
				# Group and sort the list by FixControlImpact
				
				$this.Controls | Group-Object { $_.FixControlImpact } | Sort-Object @{ Expression = { [Enum]::Parse([FixControlImpact], $_.Name) }; Descending = $true } |
				ForEach-Object { 
					$messages += $this.PublishCustomMessage(" `r`n[FixControlImpact: $($_.Name)] [Total: $($_.Count)]");

					$_.Group | ForEach-Object {
						$controlParam = $_;
						$controlItem = $this.SVTConfig.Controls | Where-Object { $_.Id -eq $controlParam.Id } | Select-Object -First 1
						if($controlItem)
						{
							if($controlItem.FixControl -and (-not [string]::IsNullOrEmpty($controlItem.FixControl.FixMethodName)))
							{
								$messages += $this.RunFixControl($controlParam, $controlItem);
							}
							else
							{
								$messages += $this.PublishCustomMessage("The ControlId [$($controlParam.ControlID)] does not support automated fixing of control. Please follow the recommendation mentioned in the evaluation summary/csv file.", [MessageType]::Error);
							}
						}
						else
						{
							$messages += $this.PublishCustomMessage("The parameter Id [$($controlParam.Id)] is not valid. Please contact support team.", [MessageType]::Error);
						}
					};	
					$messages += $this.PublishCustomMessage([Constants]::SingleDashLine);
				};
				$messages += $this.FixCompleted();
			}
			else
			{
				$this.PublishCustomMessage("No controls are available to fix.", [MessageType]::Error);
			}
        }
		return $messages;
    }

	[MessageData[]] FixStarted()
	{ 
		return @();
	}

	[MessageData[]] FixCompleted()
	{ 
		return @();
	}

    hidden [MessageData[]] RunFixControl([ControlParam] $controlParam, [ControlItem] $controlItem)
    {
		[MessageData[]] $messages = @();
        
		if($controlItem.Enabled -eq $false)
        {
			$messages += $this.PublishCustomMessage("The ControlId [$($controlParam.ControlID)] is disabled.", [MessageType]::Warning);
        }
        else 
        {
			$messages += [MessageData]::new([Constants]::SingleDashLine);
			$messages += $this.PublishCustomMessage("Fixing: [$($controlParam.ControlID)]");
            $methodName = $controlItem.FixControl.FixMethodName.Trim();
			if((Get-Member -InputObject $this -Name $methodName -MemberType Method | Measure-Object).Count -ne 0)
			{
				$controlParam.ChildResourceParams | ForEach-Object {
					try 
					{
						if([string]::IsNullOrWhiteSpace($_.ChildResourceName))
						{
							$messages += $this.$methodName($_.Parameters);     
						}
						else
						{
							$messages += $this.$methodName($_.Parameters, $_.ChildResourceName);     
						}
					}
					catch 
					{
						$this.PublishException($_);                
					}
				};					
			}
			else
			{
				$messages += $this.PublishCustomMessage("The class [$($this.GetType().Name)] does not contain a method [$methodName]. Please contact support team.", [MessageType]::Error);
			}
        }
    
		return $messages;
    }

}
