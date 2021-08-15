﻿using namespace System.Management.Automation
Set-StrictMode -Version Latest
# Base class for SVT classes being called from PS commands
# Provides functionality to fire important events at command call
class SVTCommandBase: CommandBase {
    [string[]] $ExcludeTags = @();
    [string[]] $ControlIds = @();
	[string[]] $ExcludeControlIds = @();
    [string] $ControlIdString = "";
	[string] $ExcludeControlIdString = "";
    [bool] $UsePartialCommits;
    [bool] $UseBaselineControls;
    [PSObject] $CentralStorageAccount;
	[string] $PartialScanIdentifier = [string]::Empty;
    #hidden [ControlStateExtension] $ControlStateExt;
    hidden [bool] $UserHasStateAccess = $false;
    [bool] $GenerateFixScript = $false;
	[bool] $IncludeUserComments = $false;
    [AttestationOptions] $AttestationOptions;
    hidden [string] $AttestationUniqueRunId;
    

    SVTCommandBase([string] $tenantId, [InvocationInfo] $invocationContext):
    Base($tenantId, $invocationContext) {
        [Helpers]::AbstractClass($this, [SVTCommandBase]);
        $this.CheckAndDisableAzureRMTelemetry()
        $this.AttestationUniqueRunId = $(Get-Date -format "yyyyMMdd_HHmmss");
        #Fetching the resourceInventory once for each SVT command execution
        [ResourceInventory]::Clear();
    }

    hidden [SVTEventContext] CreateSVTEventContextObject() {
        return [SVTEventContext]@{
            TenantContext = $this.TenantContext;
            PartialScanIdentifier = $this.PartialScanIdentifier
            };
    }

    hidden [void] ClearSingletons()
    {
    }

    hidden [void] CommandStarted() {

        $this.ClearSingletons();

        [SVTEventContext] $arg = $this.CreateSVTEventContextObject();
        $this.InitializeControlState();        
        $versionMessage = $this.CheckModuleVersion();
        if ($versionMessage) {
            $arg.Messages += $versionMessage;
        }

        if ($null -ne $this.AttestationOptions -and $this.AttestationOptions.AttestControls -eq [AttestControls]::NotAttested -and $this.AttestationOptions.IsBulkClearModeOn) {
            throw [SuppressedException] ("The 'BulkClear' option does not apply to 'NotAttested' controls.`n")
        }
        #check to limit multi controlids in the bulk attestation mode
        $ctrlIds = $this.ConvertToStringArray($this.ControlIdString);
        if ($null -ne $this.AttestationOptions -and (-not [string]::IsNullOrWhiteSpace($this.AttestationOptions.JustificationText) -or $this.AttestationOptions.IsBulkClearModeOn) -and ($ctrlIds.Count -gt 1 -or $this.UseBaselineControls)) {
			if($this.UseBaselineControls)
			{
				throw [SuppressedException] ("UseBaselineControls flag should not be passed in case of Bulk attestation. This results in multiple controls. `nBulk attestation mode supports only one controlId at a time.`n")
			}
			else
			{
				throw [SuppressedException] ("Multiple controlIds specified. `nBulk attestation mode supports only one controlId at a time.`n")
			}			
        }
        
        #Create necessary resources to save compliance data in user's subscription
	    $this.PublishEvent([SVTEvent]::CommandStarted, $arg);
    }

	[void] PostCommandStartedAction()
	{
		$isPolicyInitiativeEnabled = [FeatureFlightingManager]::GetFeatureStatus("EnableAzurePolicyBasedScan",$($this.TenantContext.tenantId))
        if($isPolicyInitiativeEnabled)
        {
            $this.PostPolicyComplianceTelemetry()        
        }
	}
    [void] PostPolicyComplianceTelemetry()
	{
		[CustomData] $customData = [CustomData]::new();
		$customData.Name = "PolicyComplianceTelemetry";		
		$customData.Value = $this.TenantContext.tenantId;
		$this.PublishCustomData($customData);			
	}
    hidden [void] CommandError([System.Management.Automation.ErrorRecord] $exception) {
        [SVTEventContext] $arg = $this.CreateSVTEventContextObject();
        $arg.ExceptionMessage = $exception;

        $this.PublishEvent([SVTEvent]::CommandError, $arg);
        $this.CheckAndEnableAzureRMTelemetry()
    }

    hidden [void] CommandCompleted([SVTEventContext[]] $arguments) {
        $this.PublishEvent([SVTEvent]::CommandCompleted, $arguments);
        $this.CheckAndEnableAzureRMTelemetry()
    }

    [string] EvaluateControlStatus() {
        return ([CommandBase]$this).InvokeFunction($this.RunAllControls);
    }

    # Dummy function declaration to define the function signature
    # Function is supposed to override in derived class
    hidden [SVTEventContext[]] RunAllControls() {
        return @();
    }

    hidden [void] SetSVTBaseProperties([PSObject] $svtObject) {
        $svtObject.FilterTags = $this.ConvertToStringArray($this.FilterTags);
        $svtObject.ExcludeTags = $this.ConvertToStringArray($this.ExcludeTags);
        $svtObject.ControlIds += $this.ControlIds;
        $svtObject.ControlIds += $this.ConvertToStringArray($this.ControlIdString);
		$svtObject.ExcludeControlIds += $this.ExcludeControlIds;
        $svtObject.ExcludeControlIds += $this.ConvertToStringArray($this.ExcludeControlIdString);
        $svtObject.GenerateFixScript = $this.GenerateFixScript;
        $svtObject.InvocationContext = $this.InvocationContext;
        # ToDo: Assumption: usercomment will only work when storage report feature flag is enable
        #$resourceId = $svtObject.GetResourceId(); 
		#$svtObject.ComplianceStateData = $this.FetchComplianceStateData($resourceId);

        #Include Server Side Exclude Tags
        $svtObject.ExcludeTags += [ConfigurationManager]::GetAzSKConfigData().DefaultControlExculdeTags

        #Include Server Side Filter Tags
        $svtObject.FilterTags += [ConfigurationManager]::GetAzSKConfigData().DefaultControlFiltersTags

		#Set Partial Unique Identifier
		if($svtObject.ResourceContext)
		{
			$svtObject.PartialScanIdentifier =$this.PartialScanIdentifier
		}
		
        # ToDo: Utilize exiting functions
        $this.InitializeControlState();
        #$svtObject.ControlStateExt = $this.ControlStateExt;
    }

    hidden [void] InitializeControlState() {
        # if (-not $this.ControlStateExt) {
        #     $this.ControlStateExt = [ControlStateExtension]::new($this.TenantContext, $this.InvocationContext);
        #     $this.ControlStateExt.UniqueRunId = $this.AttestationUniqueRunId
        #     $this.ControlStateExt.Initialize($false);
        #     $this.UserHasStateAccess = $this.ControlStateExt.HasControlStateReadAccessPermissions();
        # }
    }

    [void] PostCommandCompletedAction([SVTEventContext[]] $arguments) {
        #TODO: Attestation for AAD controls?
        # if ($this.AttestationOptions -ne $null -and $this.AttestationOptions.AttestControls -ne [AttestControls]::None) {
        #     try {
        #         [SVTControlAttestation] $svtControlAttestation = [SVTControlAttestation]::new($arguments, $this.AttestationOptions, $this.TenantContext, $this.InvocationContext);
        #         #The current context user would be able to read the storage blob only if he has minimum of contributor access.
        #         if ($svtControlAttestation.controlStateExtension.HasControlStateReadAccessPermissions()) {
        #             if (-not [string]::IsNullOrWhiteSpace($this.AttestationOptions.JustificationText) -or $this.AttestationOptions.IsBulkClearModeOn) {
        #                 $this.PublishCustomMessage([Constants]::HashLine + "`n`nStarting Control Attestation workflow in bulk mode...`n`n");
        #             }
        #             else {
        #                 $this.PublishCustomMessage([Constants]::HashLine + "`n`nStarting Control Attestation workflow...`n`n");
        #             }
        #             [MessageData] $data = [MessageData]@{
        #                 Message     = ([Constants]::SingleDashLine + "`nWarning: `nPlease use utmost discretion when attesting controls. In particular, when choosing to not fix a failing control, you are taking accountability that nothing will go wrong even though security is not correctly/fully configured. `nAlso, please ensure that you provide an apt justification for each attested control to capture the rationale behind your decision.`n");
        #                 MessageType = [MessageType]::Warning;
        #             };
        #             $this.PublishCustomMessage($data)
        #             $response = ""
        #             while ($response.Trim() -ne "y" -and $response.Trim() -ne "n") {
        #                 if (-not [string]::IsNullOrEmpty($response)) {
        #                     Write-Host "Please select appropriate option."
        #                 }
        #                 $response = Read-Host "Do you want to continue (Y/N)"
        #             }
        #             if ($response.Trim() -eq "y") {
        #                 $svtControlAttestation.StartControlAttestation();
        #             }
        #             else {
        #                 $this.PublishCustomMessage("Exiting the control attestation process.")
        #             }
        #         }
        #         else {
        #             [MessageData] $data = [MessageData]@{
        #                 Message     = "You don't have the required permissions to perform control attestation. If you'd like to perform control attestation, please request your subscription owner to grant you 'Contributor' access to the '$([ConfigurationManager]::GetAzSKConfigData().AzSKRGName)' resource group.";
        #                 MessageType = [MessageType]::Error;
        #             };
        #             $this.PublishCustomMessage($data)
        #         }
        #     }
        #     catch {
        #         $this.CommandError($_);
        #     }
        # }
    }

    hidden [void] CheckAndDisableAzureRMTelemetry()
	{
		#Disable AzureRM telemetry setting until scan is completed.
		#This has been added to improve the performarnce of scan commands
        #Telemetry will be re-enabled once scan is completed
       # BUGBUG  Write-Warning("Disabling AzureRm/Az telemetry - investigate why needed?")		
		$dataCollectionPath = "$env:APPDATA\Windows Azure Powershell\AzurePSDataCollectionProfile.json"
		if(Test-Path -Path $dataCollectionPath)
		{
			$dataCollectionProfile = Get-Content -path $dataCollectionPath | ConvertFrom-Json
			if($dataCollectionProfile.enableAzureDataCollection)
			{	
				#Keep settings in 
				$AzureRMDataCollectionSettingFolderpath= [Constants]::AzSKAppFolderPath + "\AzureRMDataCollectionSettings"
				if(-not (Test-Path -Path $AzureRMDataCollectionSettingFolderpath))
				{
					mkdir -Path $AzureRMDataCollectionSettingFolderpath -Force
                }
                
				$AzureRMDataCollectionFilePath = $AzureRMDataCollectionSettingFolderpath + "\AzurePSDataCollectionProfile.json"
                if(-not (Test-Path -Path $AzureRMDataCollectionFilePath))
				{
                    Copy-Item $dataCollectionPath $AzureRMDataCollectionFilePath					
                }
				Disable-AzDataCollection  | Out-Null
			}
		}
    }
    
    hidden [void] CheckAndEnableAzureRMTelemetry()
    {
        #Enabled AzureRM telemetry which got disabled at the start of command
        $AzureRMDataCollectionSettingFilepath= [Constants]::AzSKAppFolderPath + "\AzureRMDataCollectionSettings\AzurePSDataCollectionProfile.json"
        if(Test-Path -Path $AzureRMDataCollectionSettingFilepath)
        {
            $dataCollectionProfile = Get-Content -path $AzureRMDataCollectionSettingFilepath | ConvertFrom-Json
            if($dataCollectionProfile -and $dataCollectionProfile.enableAzureDataCollection)
            {
                Enable-AzDataCollection  | Out-Null
            }
        }

    }

    hidden [void] RemoveOldAzSDKRG()
    {
        $scanSource = [AzSKSettings]::GetInstance().GetScanSource();
        if($scanSource -eq "SDL" -or [string]::IsNullOrWhiteSpace($scanSource))
        {
            $olderRG = Get-AzResourceGroup -Name $([OldConstants]::AzSDKRGName) -ErrorAction SilentlyContinue
            if($null -ne $olderRG)
            {
                $resources = Get-AzResource -ResourceGroupName $([OldConstants]::AzSDKRGName)
                try {
                    $azsdkRGScope = "/subscriptions/$($this.TenantContext.tenantId)/resourceGroups/$([OldConstants]::AzSDKRGName)"
                    $resourceLocks = @();
                    $resourceLocks += Get-AzResourceLock -Scope $azsdkRGScope -ErrorAction Stop
                    if($resourceLocks.Count -gt 0)
                    {
                        $resourceLocks | ForEach-Object {
                            Remove-AzResourceLock -LockId $_.LockId -Force -ErrorAction Stop
                        }                 
                    }

                    if(($resources | Measure-Object).Count -gt 0)
                    {
                        $otherResources = $resources | Where-Object { -not ($_.Name -like "$([OldConstants]::StorageAccountPreName)*")} 
                        if(($otherResources | Measure-Object).Count -gt 0)
                        {
                            Write-Host "WARNING: Found non DevOps Kit resources under older RG [$([OldConstants]::AzSDKRGName)] as shown below:" -ForegroundColor Yellow
                            $otherResources
                            Write-Host "We are about to delete the older resource group including all the resources inside." -ForegroundColor Yellow
                            $option = Read-Host "Do you want to continue (Y/N) ?";
                            $option = $option.Trim();
                            While($option -ne "y" -and $option -ne "n")
                            {
                                Write-Host "Provide correct option (Y/N)."
                                $option = Read-Host "Do you want to continue (Y/N) ?";
                                $option = $option.Trim();
                            }
                            if($option -eq "y")
                            {
                                Remove-AzResourceGroup -Name $([OldConstants]::AzSDKRGName) -Force -AsJob
                            }
                        }
                        else
                        {
                            Remove-AzResourceGroup -Name $([OldConstants]::AzSDKRGName) -Force -AsJob                            
                        }
                    }
                    else 
                    {
                        Remove-AzResourceGroup -Name $([OldConstants]::AzSDKRGName) -Force -AsJob
                    }
                }
                catch {
                    #eat exception
                }  
            }          
        }
    }
}
