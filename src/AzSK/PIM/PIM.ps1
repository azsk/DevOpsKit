Set-StrictMode -Version Latest

function Set-AzSKPIMConfiguration { 
    Param
    (
        [switch]
        [Parameter(Mandatory = $false, ParameterSetName = "Activate", HelpMessage = "This switch is required to activate a PIM eligible role.")]
        [Alias("amr")]
	    $ActivateMyRole,

        [switch]
        [Parameter(Mandatory = $false, ParameterSetName = "Deactivate", HelpMessage = "This switch is required to activate a PIM eligible role.")]
        [Alias("dmr")]
	    $DeactivateMyRole,

        [switch]
        [Parameter(Mandatory = $false, ParameterSetName = "Assign", HelpMessage = "This switch is required to assign a PIM eligible role.")]
        [Alias("ar")]
	    $AssignRole,

		
        [switch]
        [Parameter(Mandatory = $true, ParameterSetName = "AssignEligibleforPermanentAssignments", HelpMessage = "This switch is required to assign a PIM eligible role.")]
        [Alias("cpa")]
        $AssignEligibleforPermanentAssignments,


        [switch]
        [Parameter(Mandatory = $true, ParameterSetName = "RemovePermanentAssignment", HelpMessage = "This switch is required to assign a PIM eligible role.")]
        [Alias("rpa")]
	    $RemovePermanentAssignments,

        
        [switch]
        [Parameter(Mandatory = $true, ParameterSetName = "ExtendExpiringAssignments", HelpMessage = "This switch is required to extend an expring PIM eligible role.")]
        [Alias("exa")]
        $ExtendExpiringAssignments,
      

        [Parameter(Mandatory = $true, ParameterSetName = "Default")]
        [Parameter(Mandatory = $true, ParameterSetName = "Activate")]
        [Parameter(Mandatory = $true, ParameterSetName = "Deactivate")]
        [Parameter(Mandatory = $true, ParameterSetName = "Assign")]
        [Parameter(Mandatory = $true, ParameterSetName = "AssignEligibleforPermanentAssignments")]
        [Parameter(Mandatory = $true, ParameterSetName = "RemovePermanentAssignment")]
        [Parameter(Mandatory = $true, ParameterSetName = "ExtendExpiringAssignments")]
        [ValidateNotNullOrEmpty()]
        [Alias("sid")]
        [string]
        $SubscriptionId,

        [Parameter(Mandatory = $false, ParameterSetName = "Activate")]
        [Parameter(Mandatory = $false, ParameterSetName = "Deactivate")]
        [Parameter(Mandatory = $false, ParameterSetName = "Assign")]
        [Parameter(Mandatory = $false, ParameterSetName = "AssignEligibleforPermanentAssignments")]
        [Parameter(Mandatory = $false, ParameterSetName = "RemovePermanentAssignment")]
        [Parameter(Mandatory = $false, ParameterSetName = "ExtendExpiringAssignments")]
        [ValidateNotNullOrEmpty()]
        [Alias("rgn")]
        [string]
        $ResourceGroupName,

        [Parameter(Mandatory = $false, ParameterSetName = "Activate")]
        [Parameter(Mandatory = $false, ParameterSetName = "Deactivate")]
        [Parameter(Mandatory = $false, ParameterSetName = "Assign")]
        [Parameter(Mandatory = $false, ParameterSetName = "AssignEligibleforPermanentAssignments")]
        [Parameter(Mandatory = $false, ParameterSetName = "RemovePermanentAssignment")]
        [Parameter(Mandatory = $false, ParameterSetName = "ExtendExpiringAssignments")]
        [ValidateNotNullOrEmpty()]
        [Alias("rn")]
        [string]
        $ResourceName,

        [Parameter(Mandatory = $true, ParameterSetName = "Activate")]
        [ValidateNotNullOrEmpty()]
        [int]
	    [Alias("dih")]
	    $DurationInHours,
		
        [Parameter(Mandatory = $true, ParameterSetName = "Assign")]
        [Parameter(Mandatory = $true, ParameterSetName = "AssignEligibleforPermanentAssignments")]
        [Parameter(Mandatory = $true, ParameterSetName = "ExtendExpiringAssignments")]
        [ValidateNotNullOrEmpty()]
        [Alias("did")]
	    [int]
        $DurationInDays,

        [Parameter(Mandatory = $true, ParameterSetName = "ExtendExpiringAssignments")]
        [int]
        [Alias("eid")]
        $ExpiringInDays,

        [Parameter(Mandatory = $true, ParameterSetName = "Activate")]
        [ValidateNotNullOrEmpty()]
        [Alias("jst")]
	    [string]
        $Justification,
        
        [Parameter(Mandatory = $true, ParameterSetName = "Assign")]
        [Parameter(Mandatory = $true, ParameterSetName = "Activate")]
        [Parameter(Mandatory = $true, ParameterSetName = "Deactivate")]
        [ValidateNotNullOrEmpty()]
	    [Alias("rln")]
        [string]
        $RoleName,

        [Parameter(Mandatory = $true, ParameterSetName = "AssignEligibleforPermanentAssignments")]
        [Parameter(Mandatory = $true, ParameterSetName = "RemovePermanentAssignment")]
        [Parameter(Mandatory = $true, ParameterSetName = "ExtendExpiringAssignments")]
        [ValidateNotNullOrEmpty()]
	    [Alias("rlns")]
        [string[]]
        $RoleNames,

        [Parameter(Mandatory = $true, ParameterSetName = "Assign")]
        [Alias("GroupName")]
        [ValidateNotNullOrEmpty()]
	    [Alias("pn")]
        [string]
        $PrincipalName,

        
        [Parameter(Mandatory = $false, ParameterSetName = "RemovePermanentAssignment")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("MatchingEligibleAssignments", "AllExceptMe")]
	    [Alias("raf")]
        [string]
        $RemoveAssignmentFor,

        [Parameter(Mandatory = $false, ParameterSetName = "RemovePermanentAssignment")]
        [Parameter(Mandatory = $false, ParameterSetName = "AssignEligibleforPermanentAssignments")]
        [Parameter(Mandatory = $false, ParameterSetName = "ExtendExpiringAssignments")]		
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
            elseif ($PSCmdlet.ParameterSetName -eq 'AssignEligibleforPermanentAssignments') {
                $pimconfig.InvokeFunction($pimconfig.AssignPIMforPermanentAssignemnts, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $DurationInDays, $Force))
            }	
            elseif ($PSCmdlet.ParameterSetName -eq 'RemovePermanentAssignment') {
                $pimconfig.InvokeFunction($pimconfig.RemovePermanentAssignments, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $RemoveAssignmentFor, $Force))
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ExtendExpiringAssignments') {
                $pimconfig.InvokeFunction($pimconfig.ExtendSoonToExpireAssignments, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $ExpiringInDays, $DurationInDays, $Force))
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
        [Alias("lmer")]
	    $ListMyEligibleRoles,

        [string]
        [Parameter(Mandatory = $true, ParameterSetName = "ListPermanentAssignments", HelpMessage = "This switch is required to list all permanent assignment.")]
        [Parameter(Mandatory = $true, ParameterSetName = "ListPIMAssignments", HelpMessage = "This switch is required to list all PIM eligible assignment.")]
        [Parameter(Mandatory = $true, ParameterSetName = "ListSoonToExpireAssignments")]
        [Alias("sid")]
        $SubscriptionId,

        [Parameter(Mandatory = $false, ParameterSetName = "ListPermanentAssignments", HelpMessage = "This switch is required to list all permanent assignment.")]
        [Parameter(Mandatory = $false, ParameterSetName = "ListPIMAssignments", HelpMessage = "This switch is required to list all PIM eligible assignment.")]
        [Parameter(Mandatory = $false, ParameterSetName = "ListSoonToExpireAssignments")]
        [ValidateNotNullOrEmpty()]
        [Alias("rgn")]
        [string]
        $ResourceGroupName,

        [Parameter(Mandatory = $false, ParameterSetName = "ListPermanentAssignments", HelpMessage = "This switch is required to list all permanent assignment.")]
        [Parameter(Mandatory = $false, ParameterSetName = "ListPIMAssignments", HelpMessage = "This switch is required to list all PIM eligible assignment.")]
        [Parameter(Mandatory = $false, ParameterSetName = "ListSoonToExpireAssignments")]
        [Alias("rn")]
        [string]
        $ResourceName,

        [switch]
        [Parameter(Mandatory = $false, ParameterSetName = "ListPermanentAssignments", HelpMessage = "This switch is required to list all permanent assignment.")]
        [Alias("lpa")]
	    $ListPermanentAssignments,

        [switch]
        [Parameter(Mandatory = $false, ParameterSetName = "ListPIMAssignments", HelpMessage = "This switch is required to list all PIM eligible assignment.")]
        [Alias("lpima")]
	    $ListPIMAssignments,

        [switch]
        [Parameter(Mandatory = $false, ParameterSetName = "ListSoonToExpireAssignments", HelpMessage = "This switch is required to list PIM eligible assignment that are about to expire in n days.")]
        [Alias("lsea")]
        $ListSoonToExpireAssignments,

        [Parameter(Mandatory = $false, ParameterSetName = "ListPermanentAssignments", HelpMessage = "This switch is required to list all permanent assignment.")]
        [Parameter(Mandatory = $false, ParameterSetName = "ListPIMAssignments", HelpMessage = "This switch is required to list all PIM eligible assignment.")]
        [Parameter(Mandatory = $true, ParameterSetName = "ListSoonToExpireAssignments")]
        [ValidateNotNullOrEmpty()]
        [Alias("rlns")]
        [string[]]
        $RoleNames,
        
        [switch]
		[Parameter(Mandatory = $false, HelpMessage = "Switch to specify whether to open output folder or not.")]
	    [Alias("dnof")]
	    $DoNotOpenOutputFolder,
        
        [Parameter(Mandatory = $true, ParameterSetName = "ListSoonToExpireAssignments")]
        [int]
        [Alias("eid")]
        $ExpiringInDays

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
            elseif ($PSCmdlet.ParameterSetName -eq 'ListSoonToExpireAssignments') {
                $pimconfig.InvokeFunction($pimconfig.ListSoonToExpireAssignments, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $ExpiringInDays))
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

