<#
.Description
	Base class for all command classes. 
	Provides functionality to fire events/operations at command levels like command started, 
	command completed and perform operation like generate run-identifier, invoke auto module update, 
	open log folder at the end of commmand execution etc
#>
using namespace System.Management.Automation
Set-StrictMode -Version Latest

class CommandBase: AzSKRoot {

	#Region: Properties 
    [string[]] $FilterTags = @();
	[bool] $DoNotOpenOutputFolder = $false;
	[bool] $Force = $false
	#EndRegion

	#Region: Constructor 
    CommandBase([string] $subscriptionId, [InvocationInfo] $invocationContext):
    Base($subscriptionId) {

        [Helpers]::AbstractClass($this, [CommandBase]);
		
		if (-not $invocationContext) {
            throw [System.ArgumentException] ("The argument 'invocationContext' is null. Pass the `$PSCmdlet.MyInvocation from PowerShell command.");
		}
		
		$this.InvocationContext = $invocationContext;
		
		#Validate if privacy is accepted by user
		[PrivacyNotice]::ValidatePrivacyAcceptance()

		#Initialize common parameter sets
		if($null -ne $this.InvocationContext.BoundParameters["DoNotOpenOutputFolder"])
		{
			$this.DoNotOpenOutputFolder = $this.InvocationContext.BoundParameters["DoNotOpenOutputFolder"];
		}
		if($null -ne $this.InvocationContext.BoundParameters["Force"])
		{
			$this.Force = $this.InvocationContext.BoundParameters["Force"];
		}

		#Check multiple AzSK* module should not be loaded in same session
		$this.CheckMultipleAzSKModuleLoaded();	
	}
	#EndRegion

	#Region: Command level listerner events 
    [void] CommandStarted() {
        $this.PublishAzSKRootEvent([AzSKRootEvent]::CommandStarted, $this.CheckModuleVersion());
	}
	
	[void] PostCommandStartedAction()
	{
		
	}

    [void] CommandError([System.Management.Automation.ErrorRecord] $exception) {
        [AzSKRootEventArgument] $arguments = $this.CreateRootEventArgumentObject();
        $arguments.ExceptionMessage = $exception;

        $this.PublishEvent([AzSKRootEvent]::CommandError, $arguments);
    }

    [void] CommandCompleted([MessageData[]] $messages) {
        $this.PublishAzSKRootEvent([AzSKRootEvent]::CommandCompleted, $messages);
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
    [void] PostCommandCompletedAction([SVTEventContext[]] $arguments)
	{ }

	[void] PostCommandCompletedAction([MessageData[]] $messages)
	{ }
	#EndRegion

	#Region: Helper function to invoke function based on method name. 
	# This is method called from command(GRS/GSS etc) files and resposinble for printing command start/end messages using listeners  
    [string] InvokeFunction([PSMethod] $methodToCall) {
        return $this.InvokeFunction($methodToCall, @());
    }

    [string] InvokeFunction([PSMethod] $methodToCall, [System.Object[]] $arguments) {
        if (-not $methodToCall) {
            throw [System.ArgumentException] ("The argument 'methodToCall' is null. Pass the reference of method to call. e.g.: [YourClass]::new().YourMethod");
		}
		#if attestation then rescan the controls
		if ($null -eq $arguments)
		{
			$folderPath = $this.GetOutputFolderPath();
			$methodResult = $methodToCall.Invoke(@());
            #$this.CommandCompleted($methodResult); this will update CSV but issue is there will be duplicate entries
			if(-not $this.DoNotOpenOutputFolder) {
				if (Test-Path $folderPath) {
					Invoke-Item -Path $folderPath;
				}
			}
		}
        else {

		# Reset cached context <TODO Framework: Fix Dependancy on RM module>
		[ContextHelper]::ResetCurrentContext()

		# Publish runidentifier(YYYYMMDD_HHMMSS) used by all listener as identifier for scan,creating log folder 
		$this.PublishRunIdentifier($this.InvocationContext);
		
		# <TODO Framework: Move command time calculation methods to AIOrgTelmetry Listener>
		
		[AIOrgTelemetryHelper]::TrackCommandExecution("Command Started",
			@{"RunIdentifier" = $this.RunIdentifier}, @{}, $this.InvocationContext);
        $sw = [System.Diagnostics.Stopwatch]::StartNew();
		
		# Publish command init events
        $this.CommandStarted();
		$this.PostCommandStartedAction();

		# Invoke method with arguments
        $methodResult = @();
        try {
           $methodResult = $methodToCall.Invoke($arguments);
        }
        catch {
            # Unwrapping the first layer of exception which is added by Invoke function
			[AIOrgTelemetryHelper]::TrackCommandExecution("Command Errored",
				@{"RunIdentifier" = $this.RunIdentifier; "ErrorRecord"= $_.Exception.InnerException.ErrorRecord},
				@{"TimeTakenInMs" = $sw.ElapsedMilliseconds; "SuccessCount" = 0},
				$this.InvocationContext);
            $this.CommandError($_.Exception.InnerException.ErrorRecord);
		}
		

		
		$folderPath = $this.GetOutputFolderPath();

		#the next two bug log classes have been called here as we need all the control results at one place for
		#dumping them in json file and auto closing them(to minimize api calls and auto close them in batches)
		#if bug logging is enabled and path is valid, create the JSON file for bugs
		if($this.InvocationContext.BoundParameters["AutoBugLog"] -and [BugLogPathManager]::GetIsPathValid()){
			[PublishToJSON]::new($methodResult,$folderPath)
		}

		#auto close passed bugs
		if($this.InvocationContext.BoundParameters["AutoBugLog"]){
			#call the AutoCloseBugManager
			$AutoClose=[AutoCloseBugManager]::new($this.SubscriptionContext,$methodResult);
			$AutoClose.AutoCloseBug($methodResult)
		}
		# Publish command complete events
        $this.CommandCompleted($methodResult);
		[AIOrgTelemetryHelper]::TrackCommandExecution("Command Completed",
			@{"RunIdentifier" = $this.RunIdentifier},
			@{"TimeTakenInMs" = $sw.ElapsedMilliseconds; "SuccessCount" = 1},
			$this.InvocationContext)
        $this.PostCommandCompletedAction($methodResult);


		# <TODO Framework: Move PDF generation method based on listener>
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

		# 
        $AttestControlParamFound = $this.InvocationContext.BoundParameters["AttestControls"];
		if($null -eq $AttestControlParamFound)
		{
			#If controls are attested then open folder when rescan of attested controls is complete
			$controlAttested = $false
			if( ([FeatureFlightingManager]::GetFeatureStatus("EnableScanAfterAttestation","*"))) { 
				#Global variable "AttestationValue" is set to true when one or more controls are attested in current scan
				#Ignore if variable AttestationValue is not found
				if (Get-Variable AttestationValue -Scope Global -ErrorAction Ignore){
					if ( $Global:AttestationValue){
						$controlAttested = $true
					}
				}
			}

			if ( !$controlAttested){
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
	}
	}
        return $folderPath;
	}
	#EndRegion

	

	
	# Function to get output log folder from WriteFolder listener 
    [string] GetOutputFolderPath() {
        return [WriteFolderPath]::GetInstance().FolderPath;
    }

	# <TODO Framework: Move to module helper class>
	# Function to validate module version based on Org policy and showcase warning for update or block commands if version is less than last two minor version
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
				throw ([SuppressedException]::new(("Your version of $([Constants]::AzSKModuleName) is too old. Please update now!"),[SuppressedExceptionType]::Generic))
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
				$this.PublishCustomMessage("Your Org AzSK version [$serverVersion] is too old. It must be updated to latest available version [$psGalleryVersion].",[MessageType]::Error);
			}
		}
		
	}
	
	# <TODO Framework: Move to module helper class>
	# Funtion to execute module auto update flow based on switch
	[void] InvokeAutoUpdate()
	{
		$AutoUpdateSwitch= [ConfigurationManager]::GetAzSKSettings().AutoUpdateSwitch;
		$AutoUpdateCommand = [ConfigurationManager]::GetAzSKSettings().AutoUpdateCommand;

		if($AutoUpdateSwitch -ne [AutoUpdate]::On)
		{
			if($AutoUpdateSwitch -eq [AutoUpdate]::NotSet)
			{
				$AutoUpdateMsg = [Constants]::AutoUpdateMessage 
				Write-Host $AutoUpdateMsg -ForegroundColor Yellow
			}
			return;
		}

		#Step 1: Get the list of active running powershell prcesses including the current running PS Session
		$PSProcesses = Get-Process | Where-Object { ($_.Name -eq 'powershell' -or $_.Name -eq 'powershell_ise' -or $_.Name -eq 'powershelltoolsprocesshost')}

		$userChoice = ""
		if(($PSProcesses | Measure-Object).Count -ge 1)
		{			
			Write-Host([Constants]::ModuleAutoUpdateAvailableMsg) -ForegroundColor Cyan;
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
			Write-Host "Set-AzSKADOPolicySettings -AutoUpdate Off`n" -ForegroundColor Green
			return
		}
		$AzSKTemp = Join-Path $([Constants]::AzSKAppFolderPath) "Temp";
		try
		{
			$fileName = "au_" + $(get-date).ToUniversalTime().ToString("yyyyMMdd_HHmmss") + ".ps1";

			$autoUpdateContent = [ConfigurationHelper]::LoadOfflineConfigFile("ModuleAutoUpdate.ps1");
			if(-not (Test-Path -Path $AzSKTemp))
			{
				New-Item -Path $AzSKTemp -ItemType Directory -Force
			}
			Remove-Item -Path (Join-Path $AzSKTemp "au_*") -Force -Recurse -ErrorAction SilentlyContinue

			$autoUpdateContent = $autoUpdateContent.Replace("##installurl##",$AutoUpdateCommand);
			$autoUpdateContent | Out-File (Join-Path $AzSKTemp $fileName) -Force

			Start-Process -WindowStyle Normal -FilePath "powershell.exe" -ArgumentList (Join-Path $AzSKTemp $fileName)
		}
		catch
		{
			$this.CommandError($_.Exception.InnerException.ErrorRecord);
		}
	}

	[void] CheckMultipleAzSKModuleLoaded(){
		$loadedAzSKModules= Get-Module | Where-Object { $_.Name -like "AzSK*"};
		if($null -ne $loadedAzSKModules -and ($loadedAzSKModules| Measure-Object).Count -gt 1){
			throw [SuppressedException]::new("ERROR: Multiple AzSK modules loaded in same session, this will lead to issues when running AzSK cmdlets.",[SuppressedExceptionType]::Generic)
		}
	}
}
