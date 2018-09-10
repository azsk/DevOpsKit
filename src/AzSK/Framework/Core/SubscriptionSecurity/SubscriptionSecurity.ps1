using namespace System.Management.Automation
Set-StrictMode -Version Latest 

# The class serves as an intermediate class to call multiple subscription security module classes

class SubscriptionSecurity: CommandBase
{    
	[string] $Tags
	SubscriptionSecurity([string] $subscriptionId, [InvocationInfo] $invocationContext, [string] $tags): 
        Base($subscriptionId, $invocationContext)
    { 
		$this.Tags = $tags;
	}
	SubscriptionSecurity([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext)
    {}
	[MessageData[]] SetSubscriptionSecurity(
		# Inputs for Security Center
		[string] $securityContactEmails, [string] $securityPhoneNumber, 
		# Inputs for Alerts
		[string] $targetResourceGroup, [string] $alertResourceGroupLocation
	)
    {	
		[MessageData[]] $messages = @();		

		#Create all the required AzSK Resources if missing
		try
		{
			$this.SetupAzSKResources();
		}
		catch
		{
			$this.CommandError($_);
		}
		# Set up Security Center
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nConfiguring Security Center`r`n" + [Constants]::DoubleDashLine);
			$secCenter = [SecurityCenter]::new($this.SubscriptionContext.SubscriptionId, $securityContactEmails, $securityPhoneNumber);
			if ($secCenter) 
			{
				$updatePolicies = $true;
				$updateSecurityContacts = $true;
				$updateProvisioningSettings = $true;
				$messages += $secCenter.SetPolicies($updateProvisioningSettings,$updatePolicies,$updateSecurityContacts);
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted Security Center configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  
		
		# Set up RBAC
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nSetting up subscription RBAC`r`n" + [Constants]::DoubleDashLine);
			$rbac = [RBAC]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $this.Tags);
			if ($rbac) 
			{
				$messages += $rbac.SetRBACAccounts();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted subscription RBAC configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		# Set up ARM policies
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nSetting up ARM policies`r`n" + [Constants]::DoubleDashLine);
			$armPolicy = [ARMPolicy]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $this.Tags, $false);
			if ($armPolicy) 
			{
				$messages += $armPolicy.SetARMPolicies();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted ARM policy configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		# Set up Alerts
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nSetting up Alerts`r`n" + [Constants]::DoubleDashLine);
			$alert = [Alerts]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $this.Tags);
			if ($alert) 
			{
				$messages += $alert.SetAlerts($targetResourceGroup, $securityContactEmails,$null,$alertResourceGroupLocation);
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted Alerts configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		return $messages;
    }
	
	[MessageData[]] RemoveSubscriptionSecurity([bool] $deleteResourceGroup, [string] $alertNames)
    {	
		[MessageData[]] $messages = @();

		# Remove ARM policies
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nRemoving ARM policies`r`n" + [Constants]::DoubleDashLine);
			$armPolicy = [ARMPolicy]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $this.Tags, $false);
			if ($armPolicy) 
			{
				$messages += $armPolicy.RemoveARMPolicies();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nRemoved ARM policies`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		# Remove Alerts
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nRemoving Alerts`r`n" + [Constants]::DoubleDashLine);
			$alert = [Alerts]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $this.Tags);
			if ($alert) 
			{
				$messages += $alert.RemoveAlerts($deleteResourceGroup, $alertNames);
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nRemoved Alerts`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		return $messages;
    }

	[MessageData[]] UpdateSubscriptionSecurity()
    {	
		[MessageData[]] $messages = @();

		#Adding all mandatory tags 
		$mandatoryTags = [string]::Join(",", [ConfigurationManager]::GetAzSKConfigData().SubscriptionMandatoryTags);

		#Create all the required AzSK Resources if missing
		try
		{
			$this.SetupAzSKResources();
		}
		catch
		{
			$this.CommandError($_);
		}
		# Set up Alerts
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nUpdating Alerts...`r`n" + [Constants]::DoubleDashLine);
			$alert = [Alerts]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $mandatoryTags);
			if ($alert) 
			{
				#calling alert method with default params i.e. without security contanct email and phone number
				$messages += $alert.SetAlerts();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted updates for Alerts configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }
		
		# Set up Security Center
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nUpdating Security Center configuration...`r`n" + [Constants]::DoubleDashLine);
			$secCenter = [SecurityCenter]::new($this.SubscriptionContext.SubscriptionId);
			if ($secCenter) 
			{
				$updatePolicies = $true;
				$updateSecurityContacts = $false;
				$updateProvisioningSettings = $true;
				#calling the ASC policy method with default params i.e. without ASC security poc email and phone number
				$messages += $secCenter.SetPolicies($updateProvisioningSettings,$updatePolicies,$updateSecurityContacts);
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted updates for Security Center configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  
		
		# Set up RBAC
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nUpdating subscription RBAC with required central accounts...`r`n" + [Constants]::DoubleDashLine);
			$rbac = [RBAC]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $mandatoryTags);
			if ($rbac) 
			{
				#calling the rbac command to set the subscription with all the required approved accounts
				$messages += $rbac.SetRBACAccounts();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted updates for subscription RBAC configuration for central mandatory accounts`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		# Remove RBAC
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nUpdating subscription RBAC to remove any deprecated accounts...`r`n" + [Constants]::DoubleDashLine);
			$rbac = [RBAC]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $null);
			if ($rbac) 
			{
				#calling the rbac command to set the subscription with all the required approved accounts
				$messages += $rbac.RemoveRBACAccounts();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted updates for subscription RBAC configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  

		# Set up ARM policies
		try 
        {
			$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nUpdating ARM policies...`r`n" + [Constants]::DoubleDashLine);
			$armPolicy = [ARMPolicy]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext, $mandatoryTags, $false);
			if ($armPolicy) 
			{
				$messages += $armPolicy.SetARMPolicies();
				$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted updates for ARM policy configuration`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);
			} 
		}
        catch 
        {
			$this.CommandError($_);
        }  
		  

		#Update CA
		$caAccount = [CCAutomation]::new($this.SubscriptionContext.SubscriptionId, $this.InvocationContext);
		if ($caAccount) 
		{
			#Passing parameter FixRuntimeAccount, RenewCertificate and FixModules as false by default
			$messages += $caAccount.UpdateAzSKContinuousAssurance($false, $false, $false, $false);
		}
		return $messages;
    }

	[MessageData[]] SetupAzSKResources()
	{
		[MessageData[]] $messages = @();

		$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nValidating the required resources for AzSK...`r`n" + [Constants]::DoubleDashLine);
		#Check for the presence of AzSK RG
		$azskRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		$azskLocation = [ConfigurationManager]::GetAzSKConfigData().AzSKLocation;
		try 
        {
			$storageAccountName = ([Constants]::StorageAccountPreName + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"))
			$StorageAccountInstance = [StorageHelper]::new($this.SubscriptionContext.SubscriptionId, $azskRGName, $azskLocation, $storageAccountName);
			$StorageAccountInstance.CreateStorageContainerIfNotExists([Constants]::AttestationDataContainerName)
			$StorageAccountInstance.CreateStorageContainerIfNotExists([Constants]::CAScanOutputLogsContainerName)
			$StorageAccountInstance.CreateStorageContainerIfNotExists([Constants]::CAScanProgressSnapshotsContainerName)						
		}
		catch
		{
			$this.CommandError($_);
		}		
		$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nCompleted validating all the required resources for AzSK.`r`n" + [Constants]::DoubleDashLine, [MessageType]::Update);

		return $messages;
	}
}
