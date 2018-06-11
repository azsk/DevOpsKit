using namespace System.Management.Automation
Set-StrictMode -Version Latest
# Base class for all classes being called from PS commands
# Provides functionality to fire important events at command call
class CommandBase: AzSKRoot {
    [string[]] $FilterTags = @();
	[bool] $DoNotOpenOutputFolder = $false;
	[bool] $Force = $false
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
		$IsTagSettingRequired=$this.ValidateOrgPolicyOnSubscription()
		 #Validate if command has AzSK component write permission
		if($this.GetCommandMetadata().HasAzSKComponentWritePermission -and ($IsTagSettingRequired -or $this.Force))
		{
			#If command is running with Org-neutral Policy or switch Org policy, Set Org Policy tag on subscription
			$this.SetOrgPolicyTag()
		}		
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
		#block if the migration is not completed
		$IsMigrateSwitchPassed = $this.InvocationContext.BoundParameters["Migrate"];
		$isMigrationCompleted = [UserSubscriptionDataHelper]::IsMigrationCompleted($this.SubscriptionContext.SubscriptionId);
		if($isMigrationCompleted -ne "COMP")
		{
			$MigrationWarning = [ConfigurationManager]::GetAzSKConfigData().MigrationWarning;			
			$isLatestRequired = $this.IsLatestVersionRequired();
			if($isLatestRequired)
			{
				throw ([SuppressedException]::new($MigrationWarning,[SuppressedExceptionType]::Generic))
			}
			elseif(-not $IsMigrateSwitchPassed)
			{
				if($this.InvocationContext.BoundParameters["AttestControls"] -or $this.InvocationContext.BoundParameters["ControlsToAttest"])
				{
					throw ([SuppressedException]::new($MigrationWarning,[SuppressedExceptionType]::Generic))
				}
				else
				{
					Write-Host "WARNING: $MigrationWarning" -ForegroundColor Yellow
				}
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
	
	[bool] ValidateOrgPolicyOnSubscription()
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
					throw [SuppressedException]::new("Currently command is running with policy '$($AzSKConfigData.PolicyOrgName)', instead it is expected to be run with policy '$OrgName'. Please contact Org policy owner ($($SubOrgTag.Value)) for getting policy setup url.",[SuppressedExceptionType]::Generic)
				}
				else
				{					   
					$this.PublishCustomMessage("Currently command is running with policy '$($AzSKConfigData.PolicyOrgName)', instead it is expected to be run with policy '$OrgName'. Please contact Org policy owner '$($SubOrgTag.Value)' for getting policy setup url. If you want to update subscription for policy '$($AzSKConfigData.PolicyOrgName)', run Set-AzSKSubscriptionSecurity or Update-AzSKSubscriptionSecurity with -Force parameter.",[MessageType]::Warning);
					$IsTagSettingRequired = $false
				}
				}                
			  }			 
		}
		else {
			$IsTagSettingRequired = $true
		}
		return $IsTagSettingRequired	
	}

	[void] SetOrgPolicyTag()
	{
		try
		{
			$AzSKConfigData = [ConfigurationManager]::GetAzSKConfigData()
			$tagsOnSub =  [Helpers]::GetResourceGroupTags($AzSKConfigData.AzSKRGName) 
			if($tagsOnSub)
			{
				$SubOrgTag= $tagsOnSub.GetEnumerator() | Where-Object {$_.Name -like "AzSKOrgName*"}			
				if(($SubOrgTag | Measure-Object).Count -eq 0)
				{
					if($AzSKConfigData.PolicyOrgName -ne "org-neutral")
					{
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
		}
		catch{
			# Exception occurred during setting tag. This is kept blank intentionaly to avoid flow break
		}
	}
}
