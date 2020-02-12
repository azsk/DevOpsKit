Set-StrictMode -Version Latest

function Set-AzSKPIMConfiguration { 
    <#
    	  .SYNOPSIS
            This command enables to manage access, roles and assignments on azure resources
        .DESCRIPTION
            This command provides a quicker way to perform Privileged Identity Management (PIM) operations and enables you to manage access to important Azure subscriptions, resource groups and resources. 
        .PARAMETER ActivateMyRole
            Use this switch to activate your own PIM role on specific Subscription/ ResourceGroup/ Resource
        .PARAMETER ApplyConditionalAccessPolicyForRoleActivation
            Use this parameter to enable/disable ConditionalAccess policies for a role
        .PARAMETER AssignEligibleforPermanentAssignments
            Use this switch to convert permanent access to PIM at Subscription/ ResourceGroup/ Resource level. Using this switch will only mirror existing permanent assignments for a given role on a scope. To remove the permanents assignments, run Set-AzSKPIMConfiguration -RemovePermanentAssignments -Subscription $subid  -RoleName $role 
        .PARAMETER AssignRole
            Use this switch to assign PIM role on specific Subscription/ ResourceGroup/ Resource by providing UPNS in '-PrincipalName'. Make sure you have admin privileges for assigning role.
        .PARAMETER ConfigureRoleSettings
            Use this switch to modify settings specific to a role. For example, ExpireEligibleAssignmentsInDays, RequireJustificationOnActivation, RequireMFAOnActivation, MaximumActivationDuration. Make sure you have admin privileges for updating  role settings.
        .PARAMETER DeactivateMyRole
            Use this switch to deactivate PIM activated role on specific Subscription/ ResourceGroup/ Resource
        .PARAMETER DoNotOpenOutputFolder
            Use this switch to  specify whether to open output folder or not.
        .PARAMETER DurationInDays 
            Use this parameter while assigning or extending PIM roles to specify number of days assignment should be available or extended.
        .PARAMETER DurationInHours 
            Use this parameter while activating PIM to provide duration for role activation.
        .PARAMETER ExpireEligibleAssignmentsInDays 
            Use this parameter along with -ConfigureRoleSettings to configure maximum number of days of expiry for a role for which PIM assignment can be done for the given role on the scope .
        .PARAMETER ExpiringInDays 
            Use this parameter with ListSoonToExpireAssignments, ExtendExpiringAssignments to filter result based on number of days
        .PARAMETER ExtendExpiringAssignments
            Switch to extend PIM assignments for a role.
        .PARAMETER Force
            Bypass consent to modify PIM access on Azure resources.
        .PARAMETER Justification 
            Use this option to provide an apt justification with proper business reason.
        .PARAMETER MaximumActivationDuration 
            Use this switch along with -ConfigureRoleSettings to configure maximum number of hours for activation of a role.
        .PARAMETER PrincipalNames 
            PrincipalNames is for providing user's principal name.
        .PARAMETER RemoveAssignmentFor 
            Use this switch by providing value "AllExceptMe" or "MatchingEligibleAssignments" to remove permamnet assignment. 
        .PARAMETER RemovePermanentAssignments
            Enables users to convert permanent assignment to PIM role.
        .PARAMETER RemovePIMAssignment
            Enables users to remove assigned PIM role on specific Subscription/ ResourceGroup/ Resource by providing PrincipalName.
        .PARAMETER RequireJustificationOnActivation 
            Use this switch along with -ConfigureRoleSettings to configure if justification is required for activating PIM role.
        .PARAMETER RequireMFAOnActivation
            Use this switch along with -ConfigureRoleSettings to configure if user requires Azure MFA for activating PIM role.
        .PARAMETER ResourceGroupName
            ResourceGroups for which the security evaluation has to be performed. Comma separated values are supported. Wildcards are not permitted. By default, the command gets all resources in the subscription.
        .PARAMETER ResourceName
            Gets a resource with the specified name. Comma separated values are supported. Wildcards/like searches are not permitted. By default, the command gets all resources in the subscription.
        .PARAMETER RoleName 
            This parameter is required to filter results based on rolename, only single role name can be passed in the parameter.
        .PARAMETER RoleNames 
            This parameter is required to filter results based on roles, this parameter is used where multiple role names can be passed for the given combination of parameters.
        .PARAMETER SubscriptionId
            Subscription id for which the security evaluation has to be performed.
	    
    #>
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
        [Parameter(Mandatory = $false, ParameterSetName = "RemovePIMAssignment", HelpMessage = "This switch is required to remove a PIM eligible role.")]
        [Alias("ras")]
        $RemovePIMAssignment,

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
        [Parameter(Mandatory = $true, ParameterSetName = "ExtendExpiringAssignmentForUsers", HelpMessage = "This switch is required to extend an expring PIM eligible role.")]
        [Alias("exa")]
        $ExtendExpiringAssignments,

        [switch]
        [Parameter(Mandatory = $true, ParameterSetName = "ConfigureRoleSettings", HelpMessage = "This switch is used to configure role settings for a role on a resource.")]
        [Alias("crs")]
        $ConfigureRoleSettings,
      

        [Parameter(Mandatory = $true, ParameterSetName = "Default")]
        [Parameter(Mandatory = $true, ParameterSetName = "Activate")]
        [Parameter(Mandatory = $true, ParameterSetName = "Deactivate")]
        [Parameter(Mandatory = $true, ParameterSetName = "Assign")]
        [Parameter(Mandatory = $true, ParameterSetName = "RemovePIMAssignment")]
        [Parameter(Mandatory = $true, ParameterSetName = "AssignEligibleforPermanentAssignments")]
        [Parameter(Mandatory = $true, ParameterSetName = "RemovePermanentAssignment")]
        [Parameter(Mandatory = $true, ParameterSetName = "ExtendExpiringAssignments")]
        [Parameter(Mandatory = $true, ParameterSetName = "ExtendExpiringAssignmentForUsers")]
        [Parameter(Mandatory = $true, ParameterSetName = "ConfigureRoleSettings")]
        [ValidateNotNullOrEmpty()]
        [Alias("sid")]
        [string]
        $SubscriptionId,

        [Parameter(Mandatory = $false, ParameterSetName = "Activate")]
        [Parameter(Mandatory = $false, ParameterSetName = "Deactivate")]
        [Parameter(Mandatory = $false, ParameterSetName = "Assign")]
        [Parameter(Mandatory = $false, ParameterSetName = "RemovePIMAssignment")]
        [Parameter(Mandatory = $false, ParameterSetName = "AssignEligibleforPermanentAssignments")]
        [Parameter(Mandatory = $false, ParameterSetName = "RemovePermanentAssignment")]
        [Parameter(Mandatory = $false, ParameterSetName = "ExtendExpiringAssignments")]
        [Parameter(Mandatory = $false, ParameterSetName = "ExtendExpiringAssignmentForUsers")]
        [Parameter(Mandatory = $false, ParameterSetName = "ConfigureRoleSettings")]
        [ValidateNotNullOrEmpty()]
        [Alias("rgn")]
        [string]
        $ResourceGroupName,

        [Parameter(Mandatory = $false, ParameterSetName = "Activate")]
        [Parameter(Mandatory = $false, ParameterSetName = "Deactivate")]
        [Parameter(Mandatory = $false, ParameterSetName = "Assign")]
        [Parameter(Mandatory = $false, ParameterSetName = "RemovePIMAssignment")]
        [Parameter(Mandatory = $false, ParameterSetName = "AssignEligibleforPermanentAssignments")]
        [Parameter(Mandatory = $false, ParameterSetName = "RemovePermanentAssignment")]
        [Parameter(Mandatory = $false, ParameterSetName = "ExtendExpiringAssignments")]
        [Parameter(Mandatory = $false, ParameterSetName = "ExtendExpiringAssignmentForUsers")]
        [Parameter(Mandatory = $false, ParameterSetName = "ConfigureRoleSettings")]
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
        [Parameter(Mandatory = $true, ParameterSetName = "ExtendExpiringAssignmentForUsers")]
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
        [Parameter(Mandatory = $true, ParameterSetName = "RemovePIMAssignment")]
        [Parameter(Mandatory = $true, ParameterSetName = "Activate")]
        [Parameter(Mandatory = $true, ParameterSetName = "Deactivate")]
        [Parameter(Mandatory = $true, ParameterSetName = "ConfigureRoleSettings")]
        [Parameter(Mandatory = $true, ParameterSetName = "ExtendExpiringAssignmentForUsers")]
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
        [Parameter(Mandatory = $true, ParameterSetName = "RemovePIMAssignment")]
        [Parameter(Mandatory = $true, ParameterSetName = "ExtendExpiringAssignmentForUsers")]
        [Parameter(Mandatory = $false, ParameterSetName = "AssignEligibleforPermanentAssignments")]
        [Parameter(Mandatory = $false, ParameterSetName = "RemovePermanentAssignment")]
        [ValidateNotNullOrEmpty()]
	    [Alias("pn","PrincipalName","GroupName")]
        [string[]]
        $PrincipalNames,

        
        [Parameter(Mandatory = $false, ParameterSetName = "RemovePermanentAssignment")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("MatchingEligibleAssignments", "AllExceptMe")]
	    [Alias("raf")]
        [string]
        $RemoveAssignmentFor,


        [Parameter(Mandatory = $false, ParameterSetName = "ConfigureRoleSettings")]
        [int]
        $ExpireEligibleAssignmentsInDays =-1,

        [Parameter(Mandatory = $false, ParameterSetName = "ConfigureRoleSettings")]
        [bool]
        $RequireJustificationOnActivation = $true,

        [Parameter(Mandatory = $false, ParameterSetName = "ConfigureRoleSettings")]
        [int]
        $MaximumActivationDuration = -1, 

        [Parameter(Mandatory = $false, ParameterSetName = "ConfigureRoleSettings")]
        [bool]
        $RequireMFAOnActivation,

        [Parameter(Mandatory = $false, ParameterSetName = "ConfigureRoleSettings")]
        [bool]
        $ApplyConditionalAccessPolicyForRoleActivation,
        [Alias("ApplyConditonalAccessPolicyForRoleActivation")]

        [Parameter(Mandatory = $false, ParameterSetName = "RemovePermanentAssignment")]
        [Parameter(Mandatory = $false, ParameterSetName = "AssignEligibleforPermanentAssignments")]
        [Parameter(Mandatory = $false, ParameterSetName = "ExtendExpiringAssignments")]		
        [Parameter(Mandatory = $false, ParameterSetName = "RemovePIMAssignment")]
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
                $pimconfig.InvokeFunction($pimconfig.AssignExtendPIMRoleForUser, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName, $PrincipalNames, $DurationInDays, $false, $false, $false))
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'RemovePIMAssignment') {				
                $pimconfig.InvokeFunction($pimconfig.AssignExtendPIMRoleForUser, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName, $PrincipalNames, $DurationInDays, $false, $Force, $true))
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'AssignEligibleforPermanentAssignments') {
                $pimconfig.InvokeFunction($pimconfig.AssignPIMforPermanentAssignemnts, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $DurationInDays, $PrincipalNames, $Force))
            }	
            elseif ($PSCmdlet.ParameterSetName -eq 'RemovePermanentAssignment') {
                $pimconfig.InvokeFunction($pimconfig.RemovePermanentAssignments, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $RemoveAssignmentFor, $PrincipalNames, $Force))
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ExtendExpiringAssignments') {
                $pimconfig.InvokeFunction($pimconfig.ExtendSoonToExpireAssignments, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleNames, $ExpiringInDays, $DurationInDays, $Force))
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ConfigureRoleSettings')
            {
                if($null -ne $PSCmdlet.MyInvocation.BoundParameters["RequireMFAOnActivation"] -and $null -ne $PSCmdlet.MyInvocation.BoundParameters["ApplyConditionalAccessPolicyForRoleActivation"])
                {
                    throw [SuppressedException] "'RequireMFAOnActivation' and 'ApplyConditionalAccessPolicyForRoleActivation' are exclusive switches. Please use only one of them in the command"   
                    return;
                }
                elseif ($null -ne $PSCmdlet.MyInvocation.BoundParameters["RequireMFAOnActivation"]) 
                {
                    if($RequireMFAOnActivation)
                    {
                      #Both CA and MFA can not be applied simultaneously      
                     $pimconfig.InvokeFunction($pimconfig.ConfigureRoleSettings,@($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName, $ExpireEligibleAssignmentsInDays, $RequireJustificationOnActivation, $MaximumActivationDuration, $true, $false));
                    }  
                    else 
                    {
                        $pimconfig.InvokeFunction($pimconfig.ConfigureRoleSettings,@($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName, $ExpireEligibleAssignmentsInDays, $RequireJustificationOnActivation, $MaximumActivationDuration,  $false, $null));
                    }  
                }
                elseif ($null -ne $PSCmdlet.MyInvocation.BoundParameters["ApplyConditionalAccessPolicyForRoleActivation"])
                {
                    if($ApplyConditionalAccessPolicyForRoleActivation)
                    {
                      #Both Conditional Access policy and MFA can not be applied simultaneously      
                     $pimconfig.InvokeFunction($pimconfig.ConfigureRoleSettings,@($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName, $ExpireEligibleAssignmentsInDays, $RequireJustificationOnActivation, $MaximumActivationDuration, $false, $true));
                    }  
                    else 
                    {
                        $pimconfig.InvokeFunction($pimconfig.ConfigureRoleSettings,@($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName, $ExpireEligibleAssignmentsInDays, $RequireJustificationOnActivation, $MaximumActivationDuration, $null, $false));
                    }  
                }
                    
                else 
                {
                    $pimconfig.InvokeFunction($pimconfig.ConfigureRoleSettings,@($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName, $ExpireEligibleAssignmentsInDays, $RequireJustificationOnActivation, $MaximumActivationDuration, $false, $false))
                }
                               
                
            }	
            elseif($PSCmdlet.ParameterSetName -eq'ExtendExpiringAssignmentForUsers')
            {
                $pimconfig.InvokeFunction($pimconfig.AssignExtendPIMRoleForUser, @($SubscriptionId, $ResourceGroupName, $ResourceName, $RoleName, $PrincipalNames, $DurationInDays, $true ,$false, $false))
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
    <#
    	    .SYNOPSIS
                This command enables to manage access, roles and assignments on azure resources
            .DESCRIPTION
                This command provides a quicker way to perform Privileged Identity Management (PIM) operations and enables you to manage access to important Azure subscriptions, resource groups and resources. 
	    .PARAMETER DoNotOpenOutputFolder
	        Use this switch to  specify whether to open output folder or not.
	    .PARAMETER ExpiringInDays 
	        Use this switch with ListSoonToExpireAssignments, ExtendExpiringAssignments to filter result based on number of days
	    .PARAMETER ListMyEligibleRoles
	        This switch provides list all PIM eligible roles assigned to you.
	    .PARAMETER ListPermanentAssignments
	        This switch is required to list all permanent assignment.
	    .PARAMETER ListPIMAssignments
	       This switch is required to list all PIM eligible assignment.
	    .PARAMETER ListSoonToExpireAssignments
	       This switch is required to list PIM eligible assignment that are about to expire in n days.
	    .PARAMETER ResourceGroupName
	        ResourceGroups for which the security evaluation has to be performed. Comma separated values are supported. Wildcards are not permitted. By default, the command gets all resources in the subscription.
	    .PARAMETER ResourceName
	        Gets a resource with the specified name. Comma separated values are supported. Wildcards/like searches are not permitted. By default, the command gets all resources in the subscription.
	    .PARAMETER RoleNames 
	        This parameter is required to filter results based on roles, this parameter is used where multiple role names can be passed for the given combination of parameters.
	    .PARAMETER SubscriptionId
	        Subscription id for which the security evaluation has to be performed.
    #>
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

