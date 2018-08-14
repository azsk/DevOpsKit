using namespace System.Management.Automation
Set-StrictMode -Version Latest
# Base class for all classes being called from PS commands
# Provides functionality to fire important events at command call
class CommandBase: AzSKRoot {
    [string[]] $FilterTags = @();
	[bool] $DoNotOpenOutputFolder = $false;
	[bool] $Force = $false
	[bool] $IsLocalComplianceStoreEnabled = $false
    CommandBase([string] $subscriptionId, [InvocationInfo] $invocationContext):
    Base($subscriptionId) {
        [Helpers]::AbstractClass($this, [CommandBase]);
        if (-not $invocationContext) {
            throw [System.ArgumentException] ("The argument 'invocationContext' is null. Pass the `$PSCmdlet.MyInvocation from PowerShell command.");
        }
        $this.InvocationContext = $invocationContext;
		[PrivacyNotice]::ValidatePrivacyAcceptance()

		if($null -ne $this.InvocationContext.BoundParameters["DoNotOpenOutputFolder"])
		{
			$this.DoNotOpenOutputFolder = $this.InvocationContext.BoundParameters["DoNotOpenOutputFolder"];
		}
		if($null -ne $this.InvocationContext.BoundParameters["Force"])
		{
			$this.Force = $this.InvocationContext.BoundParameters["Force"];
		}		
		#Validate if command is getting run with correct Org Policy
		$IsTagSettingRequired=$this.ValidateOrgPolicyOnSubscription($this.Force)
		#Validate if policy url token is getting expired 
		$onlinePolicyStoreUrl = [ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl
		if([Helpers]::IsSASTokenUpdateRequired($onlinePolicyStoreUrl))
		{
			#Check if CA Setup Runbook URL token is valid and update it with local policy token
			$CASetupRunbookUrl = [ConfigurationManager]::GetAzSKConfigData().CASetupRunbookURL
			if(-not [Helpers]::IsSASTokenUpdateRequired($CASetupRunbookUrl))
			{
				[ConfigurationManager]::GetAzSKSettings().OnlinePolicyStoreUrl = [Helpers]::GetUriWithUpdatedSASToken($onlinePolicyStoreUrl,$CASetupRunbookUrl)				
				[AzSKSettings]::Update([ConfigurationManager]::GetAzSKSettings())
			}
			else
			{
				[EventBase]::PublishGenericCustomMessage("Org policy settings is getting expired. Please run installer(IWR) command to update with latest policy. ", [MessageType]::Warning);
			}
		}

		 #Validate if command has AzSK component write permission
		$commandMetadata= $this.GetCommandMetadata()
		if(([Helpers]::CheckMember($commandMetadata,"HasAzSKComponentWritePermission")) -and  $commandMetadata.HasAzSKComponentWritePermission -and ($IsTagSettingRequired -or $this.Force))
		{
			#If command is running with Org-neutral Policy or switch Org policy, Set Org Policy tag on subscription
			$this.SetOrgPolicyTag($this.Force)
		}	

		$azskConfigComplianceFlag = [ConfigurationManager]::GetAzSKConfigData().StoreComplianceSummaryInUserSubscriptions;	
        $localSettingComplianceFlag = [ConfigurationManager]::GetAzSKSettings().StoreComplianceSummaryInUserSubscriptions;
        #return if feature is turned off at server config
        if($azskConfigComplianceFlag -or $localSettingComplianceFlag) 
		{
			$this.IsLocalComplianceStoreEnabled = $true
		}     
		#clear azsk storage instance
		[StorageHelper]::AzSKStorageHelperInstance = $null;

    }

    [void] CommandStarted() {
        $this.PublishAzSKRootEvent([AzSKRootEvent]::CommandStarted, $this.CheckModuleVersion());
    }

    [void] CommandError([System.Management.Automation.ErrorRecord] $exception) {
        [AzSKRootEventArgument] $arguments = $this.CreateRootEventArgumentObject();
        $arguments.ExceptionMessage = $exception;

        $this.PublishEvent([AzSKRootEvent]::CommandError, $arguments);
    }

    [void] CommandCompleted([MessageData[]] $messages) {
        $this.PublishAzSKRootEvent([AzSKRootEvent]::CommandCompleted, $messages);
    }

    [string] InvokeFunction([PSMethod] $methodToCall) {
        return $this.InvokeFunction($methodToCall, @());
    }

    [string] InvokeFunction([PSMethod] $methodToCall, [System.Object[]] $arguments) {
        if (-not $methodToCall) {
            throw [System.ArgumentException] ("The argument 'methodToCall' is null. Pass the reference of method to call. e.g.: [YourClass]::new().YourMethod");
        }

		# Reset cached context
		[Helpers]::ResetCurrentRMContext()

        $this.PublishRunIdentifier($this.InvocationContext);
		[AIOrgTelemetryHelper]::TrackCommandExecution("Command Started",
			@{"RunIdentifier" = $this.RunIdentifier}, @{}, $this.InvocationContext);
        $sw = [System.Diagnostics.Stopwatch]::StartNew();
        $isExecutionSuccessful = $true
        $this.CommandStarted();
		$this.PostCommandStartedAction();
        $methodResult = @();
        try {
           $methodResult = $methodToCall.Invoke($arguments);
        }
        catch {
            $isExecutionSuccessful = $true
            # Unwrapping the first layer of exception which is added by Invoke function
			[AIOrgTelemetryHelper]::TrackCommandExecution("Command Errored",
				@{"RunIdentifier" = $this.RunIdentifier; "ErrorRecord"= $_.Exception.InnerException.ErrorRecord},
				@{"TimeTakenInMs" = $sw.ElapsedMilliseconds; "SuccessCount" = 0},
				$this.InvocationContext);
            $this.CommandError($_.Exception.InnerException.ErrorRecord);
        }

        $this.CommandCompleted($methodResult);
		[AIOrgTelemetryHelper]::TrackCommandExecution("Command Completed",
			@{"RunIdentifier" = $this.RunIdentifier},
			@{"TimeTakenInMs" = $sw.ElapsedMilliseconds; "SuccessCount" = 1},
			$this.InvocationContext)
        $this.PostCommandCompletedAction($methodResult);

        $folderPath = $this.GetOutputFolderPath();

        #Generate PDF report
        $GeneratePDFReport = $this.InvocationContext.BoundParameters["GeneratePDF"];

        try {
            if (-not [string]::IsNullOrEmpty($folderpath)) {
                switch ($GeneratePDFReport) {
                    None {
                        # Do nothing
                    }
                    Landscape {
                        [AzSKPDFExtension]::GeneratePDF($folderpath, $this.SubscriptionContext, $this.InvocationContext, $true);
                    }
                    Portrait {
                        [AzSKPDFExtension]::GeneratePDF($folderpath, $this.SubscriptionContext, $this.InvocationContext, $false);
                    }
                }
            }
        }
        catch {
            # Unwrapping the first layer of exception which is added by Invoke function
            $this.CommandError($_);
        }

        $AttestControlParamFound = $this.InvocationContext.BoundParameters["AttestControls"];
		if($null -eq $AttestControlParamFound)
		{
			if((-not $this.DoNotOpenOutputFolder) -and (-not [string]::IsNullOrEmpty($folderPath)))
			{
				try
				{
					Invoke-Item -Path $folderPath;
				}
				catch
				{
					#ignore if any exception occurs
				}
			}
		}
        return $folderPath;

		# Call clear temp folder function.
    }

	[void] PostCommandStartedAction()
	{
		
	}

    [string] GetOutputFolderPath() {
        return [WriteFolderPath]::GetInstance().FolderPath;
    }


    [void] CheckModuleVersion() {
		 
		$currentModuleVersion = [System.Version] $this.GetCurrentModuleVersion()
		$serverVersion = [System.Version] ([ConfigurationManager]::GetAzSKConfigData().GetLatestAzSKVersion($this.GetModuleName()));
		$currentModuleVersion = [System.Version] $this.GetCurrentModuleVersion() 
        if($currentModuleVersion -ne "0.0.0.0" -and $serverVersion -gt $this.GetCurrentModuleVersion()) {
			$this.RunningLatestPSModule = $false;
			$this.InvokeAutoUpdate()
			$this.PublishCustomMessage(([Constants]::VersionCheckMessage -f $serverVersion), [MessageType]::Warning);
			$this.PublishCustomMessage(([ConfigurationManager]::GetAzSKConfigData().InstallationCommand + "`r`n"), [MessageType]::Update);
			$this.PublishCustomMessage([Constants]::VersionWarningMessage, [MessageType]::Warning);

			$serverVersions = @()
			[ConfigurationManager]::GetAzSKConfigData().GetAzSKVersionList($this.GetModuleName()) | ForEach-Object { 
				#Take major and minor version and ignore build version for comparision
			   $serverVersions+= [System.Version] ("$($_.Major)" +"." + "$($_.Minor)")
			 }			
			$serverVersions =  $serverVersions | Select-Object -Unique
			$latestVersionList = $serverVersions | Where-Object {$_ -gt $currentModuleVersion}
			if(($latestVersionList | Measure-Object).Count -gt [ConfigurationManager]::GetAzSKConfigData().BackwardCompatibleVersionCount)
			{
				throw ([SuppressedException]::new(("Your version of AzSK is too old. Please update now!"),[SuppressedExceptionType]::Generic))
			}
		}
		
		$psGalleryVersion = [System.Version] ([ConfigurationManager]::GetAzSKConfigData().GetAzSKLatestPSGalleryVersion($this.GetModuleName()));			
		if($psGalleryVersion -ne $serverVersion)
		{
			$serverVersions = @()
			[ConfigurationManager]::GetAzSKConfigData().GetAzSKVersionList($this.GetModuleName()) | ForEach-Object { 
				#Take major and minor version and ignore build version for comparision
			   $serverVersions+= [System.Version] ("$($_.Major)" +"." + "$($_.Minor)")
			 }			
			$serverVersions =  $serverVersions | Select-Object -Unique
			$latestVersionAvailableFromGallery = $serverVersions | Where-Object {$_ -gt $serverVersion}
			if(($latestVersionAvailableFromGallery | Measure-Object).Count -gt [ConfigurationManager]::GetAzSKConfigData().BackwardCompatibleVersionCount)
			{
				$this.PublishCustomMessage("Your Org AzSK version[$serverVersion] is too old. Consider updating it to latest available version[$psGalleryVersion].",[MessageType]::Error);
			}
		}
		
    }

	[void] InvokeAutoUpdate()
	{
		$AutoUpdateSwitch= [ConfigurationManager]::GetAzSKSettings().AutoUpdateSwitch;
		$AutoUpdateCommand = [ConfigurationManager]::GetAzSKSettings().AutoUpdateCommand;

		if($AutoUpdateSwitch -ne [AutoUpdate]::On)
		{
			if($AutoUpdateSwitch -eq [AutoUpdate]::NotSet)
			{
				Write-Host "Auto-update for AzSK is currently not enabled for your machine. To set it, run the command below:" -ForegroundColor Yellow
				Write-Host "Set-AzSKPolicySettings -AutoUpdate On`n" -ForegroundColor Green
			}
			return;
		}

		#Step 1: Get the list of active running powershell prcesses including the current running PS Session
		$PSProcesses = Get-Process | Where-Object { ($_.Name -eq 'powershell' -or $_.Name -eq 'powershell_ise' -or $_.Name -eq 'powershelltoolsprocesshost')}

		$userChoice = ""
		if(($PSProcesses | Measure-Object).Count -ge 1)
		{			
			Write-Host "A new version of AzSK is available. Starting the auto-update workflow...`nTo prepare for auto-update, please:`n`t a) Save your work from all active PS sessions including the current one and`n`t b) Close all PS sessions other than the current one. " -ForegroundColor Cyan
		}

		#User choice that captures the decision to close the active PS Sessions
		$secondUserChoice =""
		$InvalidOption = $true;
		while($InvalidOption)
		{
			if([string]::IsNullOrWhiteSpace($userChoice) -or ($userChoice.Trim() -ne 'y' -and $userChoice.Trim() -ne 'n'))
			{
			    $userChoice = Read-Host "Continue (Y/N)"
				if([string]::IsNullOrWhiteSpace($userChoice) -or ($userChoice.Trim() -ne 'y' -and $userChoice.Trim() -ne 'n'))
				{
					Write-Host "Enter the valid option." -ForegroundColor Yellow
				}
				continue;
			}
			elseif($userChoice.Trim() -eq 'n')
			{
				$InvalidOption = $false;
			}
			elseif($userChoice.Trim() -eq 'y')
			{
				#Get the number of PS active sessions
				$PSProcesses = Get-Process | Where-Object { ($_.Name -eq 'powershell' -or $_.Name -eq 'powershell_ise' -or $_.Name -eq 'powershelltoolsprocesshost') -and $_.Id -ne $PID}
				if(($PSProcesses | Measure-Object).Count -gt 0)
				{
					Write-Host "`nThe following other PS sessions are still active. Please save your work and close them. You can also use Task Manager to close these sessions." -ForegroundColor Yellow
					Write-Host ($PSProcesses | Select-Object Id, ProcessName, Path | Out-String)
					$secondUserChoice = Read-Host "Continue (Y/N)"
				}
				elseif(($PSProcesses | Measure-Object).Count -eq 0)
				{
					Write-Host "`nThe current PS session will be closed now. Have you saved your work?" -ForegroundColor Yellow
					$secondUserChoice = Read-Host "Continue (Y/N)"
				}
				if(-not [string]::IsNullOrWhiteSpace($secondUserChoice) -and `
				(($PSProcesses | Measure-Object).Count -eq 0 -and $secondUserChoice.Trim() -eq 'y') -or `
				$secondUserChoice.Trim() -eq 'n')
				{
					$InvalidOption = $false;
				}
			}
		}
		#Check if the first user want to continue with auto-update using userChoice field and then check if user still wants to continue with auto-update after finding the active PS sessions.
		#In either case it is no it would exit the auto-update process
		if($userChoice.Trim() -eq "n" -or $secondUserChoice.Trim() -eq 'n')
		{			
			Write-Host "Exiting auto-update workflow. To disable auto-update permanently, run the command below:" -ForegroundColor Yellow
			Write-Host "Set-AzSKPolicySettings -AutoUpdate Off`n" -ForegroundColor Green
			return
		}
		$AzSKTemp = [Constants]::AzSKAppFolderPath + "\Temp\";
		try
		{
			$fileName = "au_" + $(get-date).ToUniversalTime().ToString("yyyyMMdd_HHmmss") + ".ps1";

			$autoUpdateContent = [ConfigurationHelper]::LoadOfflineConfigFile("ModuleAutoUpdate.ps1");
			if(-not (Test-Path -Path $AzSKTemp))
			{
				mkdir -Path $AzSKTemp -Force
			}
			Remove-Item -Path "$AzSKTemp\au_*" -Force -Recurse -ErrorAction SilentlyContinue

			$autoUpdateContent = $autoUpdateContent.Replace("##installurl##",$AutoUpdateCommand);
			$autoUpdateContent | Out-File "$AzSKTemp\$fileName" -Force

			Start-Process -WindowStyle Normal -FilePath "powershell.exe" -ArgumentList "$AzSKTemp\$fileName"
		}
		catch
		{
			$this.CommandError($_.Exception.InnerException.ErrorRecord);
		}
	}

    [void] CommandProgress([int] $totalItems, [int] $currentItem) {
        $this.CommandProgress($totalItems, $currentItem, 1);
    }

    [void] CommandProgress([int] $totalItems, [int] $currentItem, [int] $granularity) {
        if ($totalItems -gt 0) {
            # $granularity indicates the number of items after which percentage progress will be printed
            # Set the max granularity to total items
            if ($granularity -gt $totalItems) {
                $granularity = $totalItems;
            }

            # Conditions for posting progress: 0%, 100% and based on granularity
            if ($currentItem -eq 0 -or $currentItem -eq $totalItems -or (($currentItem % $granularity) -eq 0)) {
                $this.PublishCustomMessage("$([int](($currentItem / $totalItems) * 100))% Completed");
            }
        }
    }

    # Dummy function declaration to define the function signature
    [void] PostCommandCompletedAction([MessageData[]] $messages)
	{ }
	
	[bool] ValidateOrgPolicyOnSubscription([bool] $Force)
	{
		$AzSKConfigData = [ConfigurationManager]::GetAzSKConfigData()
		$tagsOnSub =  [Helpers]::GetResourceGroupTags($AzSKConfigData.AzSKRGName)
		$IsTagSettingRequired = $false 
		if($tagsOnSub)
		{
			$SubOrgTag= $tagsOnSub.GetEnumerator() | Where-Object {$_.Name -like "AzSKOrgName*"}
			
			if(($SubOrgTag | Measure-Object).Count -gt 0)
			{
			  $OrgName =$SubOrgTag.Name.Split("_")[1]   				
			  if(-not [string]::IsNullOrWhiteSpace($OrgName) -and  $OrgName -ne $AzSKConfigData.PolicyOrgName)
			  {
				if($AzSKConfigData.PolicyOrgName -eq "org-neutral")
				{
					throw [SuppressedException]::new("The current subscription has been configured with DevOps kit policy for the '$OrgName' Org, However the DevOps kit command is running with a different ('$($AzSKConfigData.PolicyOrgName)') Org policy. `nPlease review FAQ at: https://aka.ms/devopskit/orgpolicy/faq and correct this condition depending upon which context(manual,CICD,CA scan) you are seeing this error. If FAQ does not help to resolve the issue, please contact your Org policy Owner ($($SubOrgTag.Value)).",[SuppressedExceptionType]::Generic)
					
				}
				else
				{	
					if(-not $Force)
					{
						$this.PublishCustomMessage("Warning: The current subscription has been configured with DevOps kit policy for the '$OrgName' Org, However the DevOps kit command is running with a different ('$($AzSKConfigData.PolicyOrgName)') Org policy. `nPlease review FAQ at: https://aka.ms/devopskit/orgpolicy/faq and correct this condition depending upon which context(manual,CICD,CA scan) you are seeing this error. If FAQ does not help to resolve the issue, please contact your Org policy Owner ($($SubOrgTag.Value)).",[MessageType]::Warning);
						$IsTagSettingRequired = $false
					}					
				}
				}                
			  }
			  elseif($AzSKConfigData.PolicyOrgName -ne "org-neutral"){				
					$IsTagSettingRequired =$true			
			}			 
		}
		else {
			$IsTagSettingRequired = $true
		}
		return $IsTagSettingRequired	
	}

	[void] SetOrgPolicyTag([bool] $Force)
	{
		try
		{
			$AzSKConfigData = [ConfigurationManager]::GetAzSKConfigData()
			$tagsOnSub =  [Helpers]::GetResourceGroupTags($AzSKConfigData.AzSKRGName) 
			if($tagsOnSub)
			{
				$SubOrgTag= $tagsOnSub.GetEnumerator() | Where-Object {$_.Name -like "AzSKOrgName*"}			
				if(
                    (($SubOrgTag | Measure-Object).Count -eq 0 -and $AzSKConfigData.PolicyOrgName -ne "org-neutral") -or 
                    (($SubOrgTag | Measure-Object).Count -gt 0 -and $AzSKConfigData.PolicyOrgName -ne "org-neutral" -and $AzSKConfigData.PolicyOrgName -ne $SubOrgTag.Value -and $Force))
				{
					if(($SubOrgTag | Measure-Object).Count -gt 0)
					{
						$SubOrgTag | ForEach-Object{
							[Helpers]::SetResourceGroupTags($AzSKConfigData.AzSKRGName,@{$_.Name=$_.Value}, $true)               
						}
					}
					$TagName = [Constants]::OrgPolicyTagPrefix +$AzSKConfigData.PolicyOrgName
					$SupportMail = $AzSKConfigData.SupportDL
					if(-not [string]::IsNullOrWhiteSpace($SupportMail) -and  [Constants]::SupportDL -eq $SupportMail)
					{
						$SupportMail = "Not Available"
					}   
					[Helpers]::SetResourceGroupTags($AzSKConfigData.AzSKRGName,@{$TagName=$SupportMail}, $false)                
									
				}
                					
			}
		}
		catch{
			# Exception occurred during setting tag. This is kept blank intentionaly to avoid flow break
		}
	}
}
