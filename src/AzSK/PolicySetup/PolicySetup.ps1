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
		[Alias("sid","HostSubscriptionId","hsid","s")]
		$SubscriptionId,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "Custom")]
        [string]
		[Alias("rgl")]
		$ResourceGroupLocation = "EastUS",

		[Parameter(Mandatory = $true, ParameterSetName = "Custom", HelpMessage="Resource group name for resource name")]
        [string]
		[Alias("rgn")]
		$ResourceGroupName,

		[Parameter(Mandatory = $true, ParameterSetName = "Custom", HelpMessage="Specify the name for policy storage account")]
        [string]
		[Alias("san")]
		$StorageAccountName,

		[Parameter(Mandatory = $true, ParameterSetName = "Custom", HelpMessage="Specify the name for application insight where telemetry data will be pushed")]
        [string]
		[Alias("ainame")]
		$AppInsightName,

		[Parameter(Mandatory = $false, ParameterSetName = "Custom")]
        [string]
		[Alias("ail")]
		$AppInsightLocation = "EastUS",

		[Parameter(Mandatory = $false, ParameterSetName = "Custom")]
        [string]
		[Alias("mdl")]
		$MonitoringDashboardLocation,

		[Parameter(Mandatory = $true, ParameterSetName = "Default", HelpMessage="The name of your organization. The value will be used to generate names of Azure resources being created as part of policy setup. This should be alphanumeric.")]
		[Parameter(Mandatory = $true, ParameterSetName = "Custom", HelpMessage="The name of your organization. The value will be used to generate names of Azure resources being created as part of policy setup. This should be alphanumeric.")]
        [string]
		[Alias("oname")]
		$OrgName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [string]
		[Alias("dname")]
		$DepartmentName,

		[Parameter(Mandatory = $false, ParameterSetName = "Custom")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Alias("PolicyFolderName","pfp")]
		[string]
		$PolicyFolderPath,

		[switch]
		[Parameter(Mandatory = $false, ParameterSetName = "Custom", HelpMessage = "Switch to specify whether to open output folder.")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Switch to specify whether to open output folder.")]
		[Alias("dnof")]
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
			$policy = [PolicySetup]::new($SubscriptionId, $PSCmdlet.MyInvocation, $OrgName, $DepartmentName,$ResourceGroupName, $StorageAccountName, $AppInsightName, $AppInsightLocation, $ResourceGroupLocation,$MonitoringDashboardLocation, $PolicyFolderPath);
			if ($policy) 
			{
				return $policy.InvokeFunction($policy.InstallPolicy);
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

	.PARAMETER SubscriptionId
		Subscription ID of the Azure subscription in which organization policy is stored.
	.PARAMETER OrgName
			The name of your organization. The value will be used to generate names of Azure resources being created as part of policy setup. This should be alphanumeric.
	.PARAMETER ResourceGroupName
			Resource group name for resource name.
	.PARAMETER StorageAccountName
			Specify the name for policy storage account
	.PARAMETER MonitoringDashboardLocation
			Location of Azure shared dashboard to monitor your organization adoption to AzSK
	#>
	
	[OutputType([String])]
	Param
	(
		[string]
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Default")]
		[Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Custom")] 
		[Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Extensions")]       
		[ValidateNotNullOrEmpty()]
		[Alias("sid","HostSubscriptionId","hsid","s")]
		$SubscriptionId,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "Custom")]
        [string]
		[Alias("rgl")]
		$ResourceGroupLocation,

		[Parameter(Mandatory = $true, ParameterSetName = "Custom")]
		[Parameter(Mandatory = $false, ParameterSetName = "Extensions")]     
        [string]
		[Alias("rgn")]
		$ResourceGroupName,

		[Parameter(Mandatory = $true, ParameterSetName = "Custom")]
		[Parameter(Mandatory = $false, ParameterSetName = "Extensions")]       
        [string]
		[Alias("san")]
		$StorageAccountName,

		[Parameter(Mandatory = $false, ParameterSetName = "Custom")]
        [string]
		[Alias("ainame")]
		$AppInsightName,

		[Parameter(Mandatory = $false)]
        [string]
		[Alias("ail")]
		$AppInsightLocation,

		[Parameter(Mandatory = $true, ParameterSetName = "Custom")]

		[string]
		[Alias("mdl")]
		$MonitoringDashboardLocation,

		[Parameter(Mandatory = $true, ParameterSetName = "Default")]
		[Parameter(Mandatory = $true, ParameterSetName = "Custom")]
		[Parameter(Mandatory = $true,  ParameterSetName = "Extensions")]        
        [string]
		[Alias("oname")]
		$OrgName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]        
		[Parameter(Mandatory = $false, ParameterSetName = "Extensions")]
        [string]
		[Alias("dname")]
		$DepartmentName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "Custom")]
		[Parameter(Mandatory = $true,  ParameterSetName = "Extensions")]
		[string]
		[Alias("PolicyFolderName","pfp")]
		$PolicyFolderPath,
		
		[Parameter(Mandatory = $true,  ParameterSetName = "Extensions")]
		[switch]
		$Extensions,

		[ValidateSet("CARunbooks", "AzSKRootConfig","MonitoringDashboard","OrgAzSKVersion", "All")]
		[Parameter(Mandatory = $false, ParameterSetName = "Custom", HelpMessage = "Override base configurations setup by AzSK.")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Override base configurations setup by AzSK.")]
		[Alias("oride")]
		$OverrideBaseConfig = [OverrideConfigurationType]::None,

		[switch]
		[Parameter(Mandatory = $false, ParameterSetName = "Custom", HelpMessage = "Switch to specify whether to open output folder.")]
		[Parameter(Mandatory = $false, ParameterSetName = "Default", HelpMessage = "Switch to specify whether to open output folder.")]
		[Alias("dnof")]
		[Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Extensions")]
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
			$policy = [PolicySetup]::new($SubscriptionId, $PSCmdlet.MyInvocation, $OrgName, $DepartmentName,$ResourceGroupName,$StorageAccountName,$AppInsightName, $null, $null,$MonitoringDashboardLocation, $PolicyFolderPath);
			if($policy)
			{
				$policy.IsUpdateSwitchOn = $true
				if($Extensions)
				{
					return $policy.InvokeFunction($policy.UpdateExtensions)
				}
				else {
				$policy.OverrideConfiguration = $OverrideBaseConfig				
				return $policy.InvokeFunction($policy.InstallPolicy);
				}
				
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


function Get-AzSKOrganizationPolicyStatus
{
	<#
	.SYNOPSIS
	This command is intended to be used by central Organization team to check health of custom Org policy
	.DESCRIPTION
	This command is intended to be used by central Organization team to check health of custom Org policy
	#>
	[OutputType([String])]
	Param
	(
		[string]
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Default")]
		[Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Custom")]
		[Parameter(Mandatory = $true, Position = 0, ParameterSetName = "DownloadPolicy")]
		[ValidateNotNullOrEmpty()]
		[Alias("sid","HostSubscriptionId","hsid","s")]
		$SubscriptionId,

		[Parameter(Mandatory = $true, ParameterSetName = "Default")]
		[Parameter(Mandatory = $true, ParameterSetName = "Custom")]
		[Parameter(Mandatory = $true, ParameterSetName = "DownloadPolicy")]
        [string]
		[Alias("oname")]
		$OrgName,

		[Parameter(Mandatory = $false, ParameterSetName = "Default")]
		[Parameter(Mandatory = $false, ParameterSetName = "DownloadPolicy")]
        [string]
		[Alias("dname")]
		$DepartmentName,

		[Parameter(Mandatory = $true, ParameterSetName = "Custom")]
		[Parameter(Mandatory = $false, ParameterSetName = "DownloadPolicy")]
        [string]
		[Alias("rgn")]
		$ResourceGroupName,

		[Parameter(Mandatory = $true, ParameterSetName = "Custom")]
		[Parameter(Mandatory = $false, ParameterSetName = "DownloadPolicy")]
        [string]
		[Alias("san")]
		$StorageAccountName,

		[Parameter(Mandatory = $false, ParameterSetName = "Custom")]
        [string]
		[Alias("ainame")]
		$AppInsightName,

		[Parameter(Mandatory = $true, ParameterSetName = "DownloadPolicy")]
        [switch]
		[Alias("dpol")]
		$DownloadPolicy,

		[Parameter(Mandatory = $true, ParameterSetName = "DownloadPolicy")]
		[Parameter(Mandatory = $true, ParameterSetName = "LocalPolicyCheck")]
		[string]
		[Alias("PolicyFolderName","pfp")]
		$PolicyFolderPath
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
			$policy = [PolicySetup]::new($SubscriptionId, $PSCmdlet.MyInvocation, $OrgName, $DepartmentName,$ResourceGroupName,$StorageAccountName,$AppInsightName, $null, $null,$null, $PolicyFolderPath);
			if ($policy)
			{
				$policy.IsUpdateSwitchOn = $false
				if($DownloadPolicy)
				{
					$policyList = $policy.InvokeFunction($policy.DownloadPolicies);
				}
				else {
					return $policy.InvokeFunction($policy.CheckPolicyHealth);
				}
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
