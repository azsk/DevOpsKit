Set-StrictMode -Version Latest 
class WriteDetailedLog: FileOutputBase
{
    hidden static [WriteDetailedLog] $Instance = $null;
    static [WriteDetailedLog] GetInstance()
    {
        if ( $null -eq  [WriteDetailedLog]::Instance)
        {
            [WriteDetailedLog]::Instance = [WriteDetailedLog]::new();
        }
    
        return [WriteDetailedLog]::Instance
    }

    [void] RegisterEvents()
    {
        $this.UnregisterEvents();       

        $this.RegisterEvent([AzSKRootEvent]::GenerateRunIdentifier, {
            $currentInstance = [WriteDetailedLog]::GetInstance();
            try 
            {
                $currentInstance.SetRunIdentifier([AzSKRootEventArgument] ($Event.SourceArgs | Select-Object -First 1));                         
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

        $this.RegisterEvent([SVTEvent]::EvaluationStarted, {
            $currentInstance = [WriteDetailedLog]::GetInstance();
            try 
            {
				if($Event.SourceArgs.IsResource())
				{
					$currentInstance.SetFilePath($Event.SourceArgs.SubscriptionContext, $Event.SourceArgs.ResourceContext.ResourceGroupName, ($Event.SourceArgs.FeatureName + ".LOG"));            
					$startHeading = ([Constants]::ModuleStartHeading -f $Event.SourceArgs.FeatureName, $Event.SourceArgs.ResourceContext.ResourceGroupName, $Event.SourceArgs.ResourceContext.ResourceName);
				}
				else
				{
					$currentInstance.SetFilePath($Event.SourceArgs.SubscriptionContext, $Event.SourceArgs.SubscriptionContext.SubscriptionName, ($Event.SourceArgs.FeatureName + ".LOG"));            
					$startHeading = ([Constants]::ModuleStartHeadingSub -f $Event.SourceArgs.FeatureName, $Event.SourceArgs.SubscriptionContext.SubscriptionName, $Event.SourceArgs.SubscriptionContext.SubscriptionId);
				}
				$currentInstance.AddOutputLog($startHeading);
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });
        
        $this.RegisterEvent([SVTEvent]::EvaluationCompleted, {
            $currentInstance = [WriteDetailedLog]::GetInstance();
            try 
            {
				$props = $Event.SourceArgs[0];
				if($props)
				{
					if($props.IsResource())
					{
						$currentInstance.AddOutputLog(([Constants]::CompletedAnalysis  -f $props.FeatureName, $props.ResourceContext.ResourceGroupName, $props.ResourceContext.ResourceName));
					}
					else
					{
						$currentInstance.AddOutputLog(([Constants]::CompletedAnalysisSub  -f $props.FeatureName, $props.SubscriptionContext.SubscriptionName, $props.SubscriptionContext.SubscriptionId));
					}
				}
				else
				{
					$currentInstance.AddOutputLog([Constants]::SingleDashLine + "`r`nNo detailed data found.`r`n" + [Constants]::DoubleDashLine);
				}
                $currentInstance.AddOutputLog([Constants]::HashLine);
            
                $currentInstance.FilePath = "";
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

        $this.RegisterEvent([SVTEvent]::ControlStarted, {
            $currentInstance = [WriteDetailedLog]::GetInstance();
            try 
            {
                $currentInstance.AddOutputLog([Constants]::DoubleDashLine);
                $currentInstance.AddOutputLog("[$($Event.SourceArgs.ControlItem.ControlID)]: $($Event.SourceArgs.ControlItem.Description)");
                $currentInstance.AddOutputLog([Constants]::SingleDashLine);
                if($Event.SourceArgs.IsResource())
				{
					$currentInstance.AddOutputLog(("Checking: [{0}]-[$($Event.SourceArgs.ControlItem.Description)] for resource [{1}]" -f 
							$Event.SourceArgs.FeatureName, 
							$Event.SourceArgs.ResourceContext.ResourceName), 
						$true);  
				}
				else
				{
					$currentInstance.AddOutputLog(("Checking: [{0}]-[$($Event.SourceArgs.ControlItem.Description)] for subscription [{1}]" -f 
                        $Event.SourceArgs.FeatureName, 
                        $Event.SourceArgs.SubscriptionContext.SubscriptionName), 
                    $true);  
				}
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });


        $this.RegisterEvent([SVTEvent]::ControlCompleted, {
            $currentInstance = [WriteDetailedLog]::GetInstance();     
            try 
            {
                $currentInstance.WriteControlResult([SVTEventContext] ($Event.SourceArgs | Select-Object -First 1 ));
                $currentInstance.AddOutputLog(([Constants]::DoubleDashLine + " `r`n"));
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

		$this.RegisterEvent([AzSKRootEvent]::CommandProcessing, {
            $currentInstance = [WriteDetailedLog]::GetInstance();
            try 
            {
				if($Event.SourceArgs.Messages)
				{
					$currentInstance.SetFilePath($Event.SourceArgs.SubscriptionContext, $Event.SourceArgs.SubscriptionContext.SubscriptionName, "Detailed.LOG");
					$Event.SourceArgs.Messages | ForEach-Object {
						$currentInstance.AddOutputLog($_);
					}
				}
			}
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });

		$this.RegisterEvent([AzSKRootEvent]::CommandCompleted, {
            $currentInstance = [WriteDetailedLog]::GetInstance();
            try 
            {
				if($Event.SourceArgs.Messages)
				{
					$currentInstance.SetFilePath($Event.SourceArgs.SubscriptionContext, $Event.SourceArgs.SubscriptionContext.SubscriptionName, "Detailed.LOG");
					$Event.SourceArgs.Messages | ForEach-Object {
						$currentInstance.AddOutputLog($_);
					}
				}
                $currentInstance.FilePath = "";
            }
            catch 
            {
                $currentInstance.PublishException($_);
            }
        });
    }

    hidden [void] AddOutputLog([string] $message, [bool] $includeTimeStamp)   
    {
        if([string]::IsNullOrEmpty($message) -or [string]::IsNullOrEmpty($this.FilePath))
        {
            return;
        }
             
        if($includeTimeStamp)
        {
            $message = (Get-Date -format "MM\/dd\/yyyy HH:mm:ss") + "-" + $message
        }

        Add-Content -Value $message -Path $this.FilePath        
    } 

    hidden [void] AddOutputLog([string] $message)   
    {
       $this.AddOutputLog($message, $false);  
    } 

	hidden [void] AddOutputLog([MessageData] $messageData)
	{
		if($messageData)
		{
			if (-not [string]::IsNullOrEmpty($messageData.Message)) 
			{
				$this.AddOutputLog($messageData.Message);
				#$this.AddOutputLog("`r`n" + $messageData.Message);
			}
			
			if ($messageData.DataObject) {
				if (-not [string]::IsNullOrEmpty($messageData.Message)) 
				{
					#$this.AddOutputLog("`r`n");
				}
				$this.AddOutputLog([Helpers]::ConvertObjectToString($messageData.DataObject, $false));                    
			}
			
		}
	}

    hidden [void] WriteControlResult([SVTEventContext] $eventContext)
    {
		if($eventContext.ControlResults -and $eventContext.ControlResults.Count -ne 0)
		{
			$controlDesc = $eventContext.ControlItem.Description;
			$eventContext.ControlResults | Foreach-Object {
				if(-not [string]::IsNullOrWhiteSpace($_.ChildResourceName))
				{
					$this.AddOutputLog("`r`n"+([Constants]::SingleDashLine));
					$this.AddOutputLog(("Checking: [{0}]-[$controlDesc] for resource [{1}]" -f 
							 $eventContext.FeatureName, 
							 $_.ChildResourceName), 
						$true);
				}			

				$_.Messages | ForEach-Object {
					$this.AddOutputLog($_);
				}
			
				# Add attestation data to log
				if($_.StateManagement -and $_.StateManagement.AttestedStateData)
				{
					$this.AddOutputLog([Constants]::SingleDashLine);					

					$stateObject = $_.StateManagement.AttestedStateData;
					$this.AddOutputLog("Justification: $($stateObject.Justification)");
					$this.AddOutputLog("Attested by: [$($stateObject.AttestedBy)] on [$($stateObject.AttestedDate)]");
					if($_.AttestationStatus -eq [AttestationStatus]::None)
					{
						$this.AddOutputLog("**State drift occurred**: The attested state doesn't match with the current state. Attestation status has been reset.");
						if(-not [string]::IsNullOrWhiteSpace($stateObject.Message))
						{
							$this.AddOutputLog($stateObject.Message);
						}

						if ($stateObject.DataObject) 
						{							
							$this.AddOutputLog("Attestation Data");
							$this.AddOutputLog([Helpers]::ConvertObjectToString($stateObject.DataObject, $false));                    
						}
					}
					else
					{
						$this.AddOutputLog("Attestation status: [$($_.AttestationStatus)]");
					}
					if($_.VerificationResult -eq [VerificationResult]::NotScanned)
					{
						if($stateObject.DataObject)
						{
							$this.AddOutputLog("Attestation Data");
							$this.AddOutputLog("Attested Data:"+[Helpers]::ConvertObjectToString($stateObject.DataObject, $false));              
						}
						else
						{
							$this.AddOutputLog("Attested Data: None");    
						}
						if(![string]::IsNullOrWhiteSpace($stateObject.ExpiryDate))
						{
							$this.AddOutputLog("Attestation expiry date: [$($stateObject.ExpiryDate)]");
						}
					}
				}

				#$this.AddOutputLog("`r`n");
				if($_.VerificationResult -ne [VerificationResult]::NotScanned)
				{
					$this.AddOutputLog([Constants]::SingleDashLine);

					if($eventContext.IsResource())
					{
						$resourceName = $eventContext.ResourceContext.ResourceName;
						if(-not [string]::IsNullOrWhiteSpace($_.ChildResourceName))
						{
							$resourceName = $_.ChildResourceName;
						}

						$this.AddOutputLog(("**{3}**: [{0}]-[{2}] for resource: [{1}]" -f 
								$eventContext.FeatureName, 
								$resourceName, 
								$eventContext.ControlItem.Description, 
								$_.VerificationResult.ToString()));      
					}
					else
					{		
						$this.AddOutputLog(("**{3}**: [{0}]-[{2}] for subscription: [{1}]" -f 
								$eventContext.FeatureName, 
								$eventContext.SubscriptionContext.SubscriptionName, 
								$eventContext.ControlItem.Description, 
								$_.VerificationResult.ToString()));     
					}
				}
			}
		}
		else
		{
			#$this.AddOutputLog("`r`n");
			$this.AddOutputLog([Constants]::SingleDashLine);
			$this.AddOutputLog(("**Disabled**: [{0}]-[{1}]" -f 
                        $eventContext.FeatureName, 
                        $eventContext.ControlItem.Description));
		}      

        $this.AddOutputLog([Constants]::SingleDashLine);
    } 
}
