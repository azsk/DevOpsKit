Set-StrictMode -Version Latest

function Set-AzSKPIMConfiguration { 
    Param
    (
        [switch]
        [Parameter(Mandatory = $false, ParameterSetName = "Activate", HelpMessage = "This switch is required to activate a PIM eligible role.")]
        $ActivateMyRole,

        [switch]
        [Parameter(Mandatory = $false, ParameterSetName = "Deactivate", HelpMessage = "This switch is required to activate a PIM eligible role.")]
        $DeactivateMyRole,

        [switch]
        [Parameter(Mandatory = $false, ParameterSetName = "Assign", HelpMessage = "This switch is required to assign a PIM eligible role.")]
        $AssignRole,

		
        [switch]
        [Parameter(Mandatory = $true, ParameterSetName = "ConvertPermanentAssignmentToPIM", HelpMessage = "This switch is required to assign a PIM eligible role.")]
        $ConvertPermanentAssignmentsToPIM,

        [switch]
        [Parameter(Mandatory = $true, ParameterSetName = "RemovePermanentAssignment", HelpMessage = "This switch is required to assign a PIM eligible role.")]
        $RemovePermanentAssignments,

        [Parameter(Mandatory = $true, ParameterSetName = "Default")]
        [Parameter(Mandatory = $true, ParameterSetName = "Activate")]
        [Parameter(Mandatory = $true, ParameterSetName = "Deactivate")]
        [Parameter(Mandatory = $true, ParameterSetName = "Assign")]
        [Parameter(Mandatory = $true, ParameterSetName = "ConvertPermanentAssignmentToPIM")]
        [Parameter(Mandatory = $true, ParameterSetName = "RemovePermanentAssignment")]
        [ValidateNotNullOrEmpty()]
        [string]
        $SubscriptionId,

        [Parameter(Mandatory = $false, ParameterSetName = "Activate")]
        [Parameter(Mandatory = $false, ParameterSetName = "Deactivate")]
        [Parameter(Mandatory = $false, ParameterSetName = "Assign")]
        [Parameter(Mandatory = $false, ParameterSetName = "ConvertPermanentAssignmentToPIM")]
        [Parameter(Mandatory = $false, ParameterSetName = "RemovePermanentAssignment")]
        [ValidateNotNullOrEmpty()]
        [string]
        $ResourceGroupName,

        [Parameter(Mandatory = $false, ParameterSetName = "Activate")]
        [Parameter(Mandatory = $false, ParameterSetName = "Deactivate")]
        [Parameter(Mandatory = $false, ParameterSetName = "Assign")]
        [Parameter(Mandatory = $false, ParameterSetName = "ConvertPermanentAssignmentToPIM")]
        [Parameter(Mandatory = $false, ParameterSetName = "RemovePermanentAssignment")]
        [ValidateNotNullOrEmpty()]
        [string]
        $ResourceName,

        [Parameter(Mandatory = $true, ParameterSetName = "Activate")]
        [ValidateNotNullOrEmpty()]
        [int]
		$DurationInHours,
		
        [Parameter(Mandatory = $true, ParameterSetName = "Assign")]
        [Parameter(Mandatory = $true, ParameterSetName = "ConvertPermanentAssignmentToPIM")]
        [ValidateNotNullOrEmpty()]
        [int]
        $DurationInDays,

        [Parameter(Mandatory = $true, ParameterSetName = "Activate")]
        [ValidateNotNullOrEmpty()]
        [string]
        $Justification,
        
        [Parameter(Mandatory = $true, ParameterSetName = "Assign")]
        [Parameter(Mandatory = $true, ParameterSetName = "Activate")]
        [Parameter(Mandatory = $true, ParameterSetName = "Deactivate")]
        [ValidateNotNullOrEmpty()]
        [string]
        $RoleName,

        [Parameter(Mandatory = $true, ParameterSetName = "ConvertPermanentAssignmentToPIM")]
        [Parameter(Mandatory = $true, ParameterSetName = "RemovePermanentAssignment")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $RoleNames,

        [Parameter(Mandatory = $true, ParameterSetName = "Assign")]
        [ValidateNotNullOrEmpty()]
        [string]
        $PrincipalName,

        [Parameter(Mandatory = $false, ParameterSetName = "RemovePermanentAssignment")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("MatchingEligibleAssignments", "AllExceptMe")]
        [string]
        $RemoveAssignmentFor,

        [Parameter(Mandatory = $false, ParameterSetName = "RemovePermanentAssignment")]
		[Parameter(Mandatory = $false, ParameterSetName = "ConvertPermanentAssignmentToPIM")]		
		[switch]
		[Alias("f")]
        $Force,
        
        [switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder or not.")]
		[Alias("dnof")]
		$DoNotOpenOutputFolder
    )
    Begin {
        [CommandHelper]::BeginCommand($MyInvocation);
        [AzListenerHelper]::RegisterListeners();
    }
    Process {
        try {
			
            $pimconfig = [PIM]::new([Constants]::BlankSubscriptionId, $MyInvocation);
            if ($PSCmdlet.ParameterSetName -eq 'Activate') {
                $pimconfig.InvokeFunction($pimconfig.Activate, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName, $Justification, $DurationInHours))
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'Deactivate') {	
                $pimconfig.InvokeFunction($pimconfig.Deactivate, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName))
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'Assign') {				
                $pimconfig.InvokeFunction($pimconfig.AssignPIMRole, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName, $PrincipalName, $DurationInDays))
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ConvertPermanentAssignmentToPIM') {
                $pimconfig.InvokeFunction($pimconfig.TransitionFromPermanentRolesToPIM, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $DurationInDays, $Force))
            }	
            elseif ($PSCmdlet.ParameterSetName -eq 'RemovePermanentAssignment') {
                $pimconfig.InvokeFunction($pimconfig.RemovePermanentAssignments, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $RemoveAssignmentFor, $Force))
            }			
            else {
                Write-Output("Invalid Parameter Set")	
            }		
			
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }  
    }
    End {
        [AzListenerHelper]::UnregisterListeners();
    }

}
function Get-AzSKPIMConfiguration {	
    Param
    (
        [switch]
        [Parameter(Mandatory = $false, ParameterSetName = "ListMyRole", HelpMessage = "This switch is required to activate a PIM eligible role.")]
        $ListMyEligibleRoles,

        [string]
        [Parameter(Mandatory = $true, ParameterSetName = "ListPermanentAssignments", HelpMessage = "This switch is required to list all permanent assignment.")]
        [Parameter(Mandatory = $true, ParameterSetName = "ListPIMAssignments", HelpMessage = "This switch is required to list all PIM eligible assignment.")]
        $SubscriptionId,

        [Parameter(Mandatory = $false, ParameterSetName = "ListPermanentAssignments", HelpMessage = "This switch is required to list all permanent assignment.")]
        [Parameter(Mandatory = $false, ParameterSetName = "ListPIMAssignments", HelpMessage = "This switch is required to list all PIM eligible assignment.")]
        [ValidateNotNullOrEmpty()]
        [string]
        $ResourceGroupName,

        [Parameter(Mandatory = $false, ParameterSetName = "ListPermanentAssignments", HelpMessage = "This switch is required to list all permanent assignment.")]
        [Parameter(Mandatory = $false, ParameterSetName = "ListPIMAssignments", HelpMessage = "This switch is required to list all PIM eligible assignment.")]
        [string]
        $ResourceName,

        [switch]
        [Parameter(Mandatory = $false, ParameterSetName = "ListPermanentAssignments", HelpMessage = "This switch is required to list all permanent assignment.")]
        $ListPermanentAssignments,

        [switch]
        [Parameter(Mandatory = $false, ParameterSetName = "ListPIMAssignments", HelpMessage = "This switch is required to list all PIM eligible assignment.")]
        $ListPIMAssignments,

        [Parameter(Mandatory = $false, ParameterSetName = "ListPermanentAssignments", HelpMessage = "This switch is required to list all permanent assignment.")]
        [Parameter(Mandatory = $false, ParameterSetName = "ListPIMAssignments", HelpMessage = "This switch is required to list all PIM eligible assignment.")]
        [ValidateNotNullOrEmpty()]
        [string[]]
		$RoleNames,
        
        [switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder or not.")]
		[Alias("dnof")]
		$DoNotOpenOutputFolder

    )
    Begin {
        [CommandHelper]::BeginCommand($MyInvocation);
        [AzListenerHelper]::RegisterListeners();
    }
    Process {
        try {
            if (-not $SubscriptionId) {
                $SubscriptionId = [Constants]::BlankSubscriptionId
            }
            $pimconfig = [PIM]::new([Constants]::BlankSubscriptionId, $MyInvocation);
            if ($PSCmdlet.ParameterSetName -eq 'ListMyRole') {
				$pimconfig.InvokeFunction($pimconfig.ListMyEligibleRoles)		
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ListPermanentAssignments') {
                $pimconfig.InvokeFunction($pimconfig.ListAssignment, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $true))
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ListPIMAssignments') {
                $pimconfig.InvokeFunction($pimconfig.ListAssignment, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $false))
            }
            else {
				
            }
        }
        catch {
            [EventBase]::PublishGenericException($_);
        }
    }
    End {
        [AzListenerHelper]::UnregisterListeners();
    }
}

