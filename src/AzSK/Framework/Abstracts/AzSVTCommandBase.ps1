<#
.Description
	Base class for SVT classes being called from PS commands
	Provides functionality to fire events/operations at command levels like command started, 
	command completed and perform operation like generate run-identifier, invoke auto module update, 
	open log folder at the end of commmand execution etc
#>
using namespace System.Management.Automation
Set-StrictMode -Version Latest
class AzSVTCommandBase: SVTCommandBase {
    
    #Region Constructor
    AzSVTCommandBase([string] $subscriptionId, [InvocationInfo] $invocationContext):
    Base($subscriptionId, $invocationContext) {

        [Helpers]::AbstractClass($this, [AzSVTCommandBase]);
        
        $this.CheckAndDisableAzTelemetry()
       
        $this.AttestationUniqueRunId = $(Get-Date -format "yyyyMMdd_HHmmss");
        #Fetching the resourceInventory once for each SVT command execution
        [ResourceInventory]::Clear();

         #Initiate Compliance State
         $this.InitializeControlState();
         #Create necessary resources to save compliance data in user's subscription
         #<TODO Perf Issue - ComplianceReportHelper fetch RG/Storage. Then creates RG/Storage/table if not exists. Check permissions for write etc>
         if($this.IsLocalComplianceStoreEnabled)
         {
            if($null -eq $this.ComplianceReportHelper)
            {
                #Reset cached compliance report helper instance for accessing first fetch
                [ComplianceReportHelper]::Instance = $null
                $this.ComplianceReportHelper = [ComplianceReportHelper]::GetInstance($this.SubscriptionContext, $this.GetCurrentModuleVersion());                  
            }
            if(-not $this.ComplianceReportHelper.HaveRequiredPermissions())
            {
                $this.IsLocalComplianceStoreEnabled = $false;
            }
         }
    }
    #EndRegion

    hidden [void] ClearSingletons()
    {
        #clear ASC security status
        #[SecurityCenterHelper]::ASCSecurityStatus = $null;
        [SecurityCenterHelper]::Recommendations = $null;
    }

    #Az Related command started events 
     [void] CommandStartedExt() {
         
        $this.ValidateAttestationParameters();
        #<TODO Framework: Find the purpose of function and move to respective place
        $this.ClearSingletons();

        $this.InitializeControlState();
    }

	[void] PostCommandStartedAction()
	{
		$isPolicyInitiativeEnabled = [FeatureFlightingManager]::GetFeatureStatus("EnableAzurePolicyBasedScan",$($this.SubscriptionContext.SubscriptionId))
        if($isPolicyInitiativeEnabled)
        {
            $this.PostPolicyComplianceTelemetry()        
        }
	}
    [void] PostPolicyComplianceTelemetry()
	{
		[CustomData] $customData = [CustomData]::new();
		$customData.Name = "PolicyComplianceTelemetry";		
		$customData.Value = $this.SubscriptionContext.SubscriptionId;
		$this.PublishCustomData($customData);			
    }
    
    [void] CommandErrorExt([System.Management.Automation.ErrorRecord] $exception) {
        $this.CheckAndEnableAzTelemetry()
    }

    [void] CommandCompletedExt([SVTEventContext[]] $arguments) {
        $this.CheckAndEnableAzTelemetry()
    }

    [ComplianceStateTableEntity[]] FetchComplianceStateData([string] $resourceId)
	{
        [ComplianceStateTableEntity[]] $ComplianceStateData = @();
        if($this.IsLocalComplianceStoreEnabled)
        {
            if($null -ne $this.ComplianceReportHelper)
            {
                [string[]] $partitionKeys = @();                
                $partitionKey = [Helpers]::ComputeHash($resourceId.ToLower());                
                $partitionKeys += $partitionKey
                $ComplianceStateData = $this.ComplianceReportHelper.GetSubscriptionComplianceReport($partitionKeys);            
            }
        }
        return $ComplianceStateData;
	}

    [void] InitializeControlState() {
        if (-not $this.ControlStateExt) {
            $this.ControlStateExt = [ControlStateExtension]::new($this.SubscriptionContext, $this.InvocationContext);
            $this.ControlStateExt.UniqueRunId = $this.AttestationUniqueRunId
            $this.ControlStateExt.Initialize($false);
            $this.UserHasStateAccess = $this.ControlStateExt.HasControlStateReadAccessPermissions();
        }
    }

    [void] PostCommandCompletedAction([SVTEventContext[]] $arguments) {
        if ($this.AttestationOptions -ne $null -and $this.AttestationOptions.AttestControls -ne [AttestControls]::None) {
            try {
                [SVTControlAttestation] $svtControlAttestation = [SVTControlAttestation]::new($arguments, $this.AttestationOptions, $this.SubscriptionContext, $this.InvocationContext);
                #The current context user would be able to read the storage blob only if he has minimum of contributor access.
                if ($svtControlAttestation.controlStateExtension.HasControlStateReadAccessPermissions()) {
                    if (-not [string]::IsNullOrWhiteSpace($this.AttestationOptions.JustificationText) -or $this.AttestationOptions.IsBulkClearModeOn) {
                        $this.PublishCustomMessage([Constants]::HashLine + "`n`nStarting Control Attestation workflow in bulk mode...`n`n");
                    }
                    else {
                        $this.PublishCustomMessage([Constants]::HashLine + "`n`nStarting Control Attestation workflow...`n`n");
                    }
                    [MessageData] $data = [MessageData]@{
                        Message     = ([Constants]::SingleDashLine + "`nWarning: `nPlease use utmost discretion when attesting controls. In particular, when choosing to not fix a failing control, you are taking accountability that nothing will go wrong even though security is not correctly/fully configured. `nAlso, please ensure that you provide an apt justification for each attested control to capture the rationale behind your decision.`n");
                        MessageType = [MessageType]::Warning;
                    };
                    $this.PublishCustomMessage($data)
                    $response = ""
                    while ($response.Trim() -ne "y" -and $response.Trim() -ne "n") {
                        if (-not [string]::IsNullOrEmpty($response)) {
                            Write-Host "Please select appropriate option."
                        }
                        $response = Read-Host "Do you want to continue (Y/N)"
                    }
                    if ($response.Trim() -eq "y") {
                        $svtControlAttestation.StartControlAttestation();
                    }
                    else {
                        $this.PublishCustomMessage("Exiting the control attestation process.")
                    }
                }
                else {
                    [MessageData] $data = [MessageData]@{
                        Message     = "You don't have the required permissions to perform control attestation. If you'd like to perform control attestation, please request your subscription owner to grant you 'Contributor' access to the '$([ConfigurationManager]::GetAzSKConfigData().AzSKRGName)' resource group. `nNote: If your permissions were elevated recently, please run the 'DisConnect-AzAccount' command to clear the Azure cache and try again.";
                        MessageType = [MessageType]::Error;
                    };
                    $this.PublishCustomMessage($data)
                }
            }
            catch {
                $this.CommandError($_);
            }
        }
    }

    hidden [void] CheckAndDisableAzTelemetry()
	{
		#Disable Az telemetry setting until scan is completed.
		#This has been added to improve the performarnce of scan commands
		#Telemetry will be re-enabled once scan is completed
        Disable-AzDataCollection  | Out-Null

    }
    
    hidden [void] CheckAndEnableAzTelemetry()
    {
        #Enabled Az telemetry which got disabled at the start of command
        Enable-AzDataCollection  | Out-Null
    }

    #Function to validate attestations parameters for BulkClear, multiple Control Ids, and baseline controls flag
    hidden [void] ValidateAttestationParameters()
    {
        if ($null -ne $this.AttestationOptions -and $this.AttestationOptions.AttestControls -eq [AttestControls]::NotAttested -and $this.AttestationOptions.IsBulkClearModeOn) {
            throw [SuppressedException] ("The 'BulkClear' option does not apply to 'NotAttested' controls.`n")
        }
        #check to limit multi controlids in the bulk attestation mode
        $ctrlIds = $this.ConvertToStringArray($this.ControlIdString);
        # Block scan if both ControlsIds and UBC/UPBC parameters contain values 
        if($null -ne $ctrlIds -and $ctrlIds.Count -gt 0 -and ($this.UseBaselineControls -or $this.UsePreviewBaselineControls)){
            throw [SuppressedException] ("Both the parameters 'ControlIds' and 'UseBaselineControls/UsePreviewBaselineControls' contain values. `nYou should use only one of these parameters.`n")
        }

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
    }
    hidden [void] ResourceScan([psobject]$resource,[string]$eventName) {
        $isResourceScanStartEndTelemetryEnabled = [FeatureFlightingManager]::GetFeatureStatus("EnableResourceScanStartEndTelemetry",$($this.SubscriptionContext.SubscriptionId))
        if($isResourceScanStartEndTelemetryEnabled)
        {
            try{
            $resourceDetails=@{
						ResourceId = $resource.ResourceId
						ResourceName = $resource.ResourceName
						ResourceType = $resource.ResourceType
						Location = $resource.Location
						ResourceGroupName = $resource.ResourceGroupName
						SubscriptionId = $this.SubscriptionContext.SubscriptionId
						PartialScanIdentifier = $this.PartialScanIdentifier
						RunIdentifier = $this.RunIdentifier
					}
                [AIOrgTelemetryHelper]::TrackEvent($eventName,$resourceDetails, $null)
            }
            catch{
                # telemetry send fails
            }
        }	
        
    }
}
