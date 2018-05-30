Set-StrictMode -Version Latest
function Install-AzSKOrganizationPolicy
{
	<#
	.SYNOPSIS
	This command is intended to be used by central Organization team to setup Organization specific policies
	.DESCRIPTION
	This command is intended to be used by central Organization team to setup Organization specific policies

	.PARAMETER SubscriptionId
		Subscription ID of the Azure subscription in which organization policy store will be created.
	.PARAMETER OrgName
			The name of your organization. The value will be used to generate names of Azure resources being created as part of policy setup. This should be alphanumeric.
	.PARAMETER DepartmentName
			The name of a department in your organization. If provided, this value is concatenated to the org name parameter. This should be alphanumeric.
	.PARAMETER PolicyFolderPath
			The local folder in which the policy files capturing org-specific changes will be stored for reference. This location can be used to manage policy files.
	.PARAMETER ResourceGroupLocation
			The location in which the Azure resources for hosting the policy will be created.
	.PARAMETER ResourceGroupName
			Resource group name for resource name.
	.PARAMETER StorageAccountName
			Specify the name for policy storage account
	.PARAMETER AppInsightName
			Specify the name for application insight where telemetry data will be pushed
	.PARAMETER DoNotOpenOutputFolder
		Switch to specify whether to open output folder.

	#>
	
	[OutputType([String])]
	Param
	(
		[string]
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Default", HelpMessage="Subscription ID of the Azure subscription in which organization policy store will be created.")]
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Custom", HelpMessage="Subscription ID of the Azure subscription in which organization policy store will be created.")]
		[ValidateNotNullOrEmpty()]
		$SubscriptionId,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "Custom")]
        [string]
		$ResourceGroupLocation = "EastUS",

		[Parameter(Mandatory = $true, ParameterSetName = "Custom", HelpMessage="Resource group name for resource name")]
        [string]
		$ResourceGroupName,

		[Parameter(Mandatory = $true, ParameterSetName = "Custom", HelpMessage="Specify the name for policy storage account")]
        [string]
		$StorageAccountName,

		[Parameter(Mandatory = $true, ParameterSetName = "Custom", HelpMessage="Specify the name for application insight where telemetry data will be pushed")]
        [string]
		$AppInsightName,

		[Parameter(Mandatory = $false, ParameterSetName = "Custom")]
        [string]
		$AppInsightLocation = "EastUS",

		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage="The name of your organization. The value will be used to generate names of Azure resources being created as part of policy setup. This should be alphanumeric.")]
		[Parameter(Mandatory = $true, ParameterSetName = "Custom", HelpMessage="The name of your organization. The value will be used to generate names of Azure resources being created as part of policy setup. This should be alphanumeric.")]
        [string]
		$OrgName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [string]
		$DepartmentName,

		[Parameter(Mandatory = $false, ParameterSetName = "Custom")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Alias("PolicyFolderName")]
		[string]
		$PolicyFolderPath,

		[switch]
		[Parameter(Mandatory = $false, ParameterSetName = "Custom", HelpMessage = "Switch to specify whether to open output folder.")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Switch to specify whether to open output folder.")]
		$DoNotOpenOutputFolder

    )

	Begin
	{
		[CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
		[ListenerHelper]::RegisterListeners();
	}
	Process
	{
		try 
		{
			$policy = [PolicySetup]::new($SubscriptionId, $PSCmdlet.MyInvocation, $OrgName, $DepartmentName,$ResourceGroupName, $StorageAccountName, $AppInsightName, $AppInsightLocation, $ResourceGroupLocation, $PolicyFolderPath, [Constants]::NewModuleName);
			if ($policy) 
			{
				$moduleName = [Constants]::NewModuleName;
				return $policy.InvokeFunction($policy.InstallPolicy, @($moduleName));
			}
		}
		catch 
		{
			[EventBase]::PublishGenericException($_);
		}  
	}
	End
	{
		[ListenerHelper]::UnregisterListeners();
	}
}


function Update-AzSKOrganizationPolicy
{
	<#
	.SYNOPSIS
	This command is intended to be used by central Organization team to setup Organization specific policies
	.DESCRIPTION
	This command is intended to be used by central Organization team to setup Organization specific policies

	#>
	
	[OutputType([String])]
	Param
	(
		[string]
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Default")]
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Custom")]
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Migrate")]
		[ValidateNotNullOrEmpty()]
		$SubscriptionId,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "Custom")]
        [Parameter(Mandatory = $false, ParameterSetName = "Migrate")]
        [string]
		$ResourceGroupLocation,

		[Parameter(Mandatory = $true, ParameterSetName = "Custom")]
        [Parameter(Mandatory = $false, ParameterSetName = "Migrate")]
        [string]
		$ResourceGroupName,

		[Parameter(Mandatory = $true, ParameterSetName = "Custom")]
        [Parameter(Mandatory = $false, ParameterSetName = "Migrate")]
        [string]
		$StorageAccountName,

        [Parameter(Mandatory = $false, ParameterSetName = "Migrate")]
        [string]
		$AppInsightName,

		[Parameter(Mandatory = $false, ParameterSetName = "Migrate")]
        [string]
		$AppInsightLocation,

		[Parameter(Mandatory = $true, ParameterSetName = "Default")]
		[Parameter(Mandatory = $true, ParameterSetName = "Custom")]
        [Parameter(Mandatory = $true, ParameterSetName = "Migrate")]
        [string]
		$OrgName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [Parameter(Mandatory = $false, ParameterSetName = "Migrate")]
        [string]
		$DepartmentName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "Custom")]
		[Alias("PolicyFolderName")]
		[string]
		$PolicyFolderPath,
		
		[Parameter(Mandatory = $true, ParameterSetName = "Migrate")]
		[switch]
		$Migrate,

		[Parameter(Mandatory = $false, ParameterSetName = "Migrate")]
		[string]
		$MigrationScriptPath,

		[switch]
		[Parameter(Mandatory = $false, ParameterSetName = "Custom", HelpMessage = "Switch to specify whether to open output folder.")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Switch to specify whether to open output folder.")]
		[Parameter(Mandatory = $false, ParameterSetName = "Migrate", HelpMessage = "Switch to specify whether to open output folder.")]
		$DoNotOpenOutputFolder
    )
	Begin
	{
		[CommandHelper]::BeginCommand($PSCmdlet.MyInvocation);
		[ListenerHelper]::RegisterListeners();
	}
	Process
	{
		try 
		{		
			if($Migrate)
			{				
				$oldPolicy = [PolicySetup]::new($SubscriptionId, $PSCmdlet.MyInvocation, $OrgName, $DepartmentName, $null , $null, $null, $null, $ResourceGroupLocation, $PolicyFolderPath, [Constants]::OldModuleName);
				$computedAppInsightLocation = $AppInsightLocation;
				if([string]::IsNullOrWhiteSpace($computedAppInsightLocation))
				{
					$computedAppInsightLocation = $oldPolicy.AppInsightLocation;
				}
				$computedRGLocation = $ResourceGroupLocation;
				if([string]::IsNullOrWhiteSpace($computedRGLocation))
				{
					$computedRGLocation = $oldPolicy.ResourceGroupLocation;
				}
				$newPolicy = [PolicySetup]::new($SubscriptionId, $PSCmdlet.MyInvocation, $OrgName, $DepartmentName, $ResourceGroupName, $StorageAccountName, $AppInsightName, $computedAppInsightLocation, $computedRGLocation, $PolicyFolderPath, [Constants]::NewModuleName);	
				return $newPolicy.InvokeFunction($newPolicy.MigratePolicy, @($oldPolicy));
			}			
			$policy = [PolicySetup]::new($SubscriptionId, $PSCmdlet.MyInvocation, $OrgName, $DepartmentName,$ResourceGroupName,$StorageAccountName,$AppInsightName, $AppInsightLocation, $ResourceGroupLocation, $PolicyFolderPath, [Constants]::NewModuleName);
			if ($policy) 
			{				
				$moduleName = [Constants]::NewModuleName
				return $policy.InvokeFunction($policy.InstallPolicy, @($moduleName));
			}
		}
		catch 
		{
			[EventBase]::PublishGenericException($_);
		}  
	}
	End
	{
		[ListenerHelper]::UnregisterListeners();
	}
}
