using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class EnvironmentInfo: CommandBase
{    

	EnvironmentInfo([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext) 
    { 
		$this.DoNotOpenOutputFolder = $true;
	}
	
	GetEnvironmentInfo()
	{
		$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nFetching configuration details from the host machine...`r`n" + [Constants]::DoubleDashLine);

		$loadedModules = (Get-Module | Select-Object -Property Name, Description, Version, Path);
		$this.PublishCustomMessage("`n`n");
		$this.PublishCustomMessage("Loaded PowerShell modules", [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString($loadedModules, $true), [MessageType]::Default);
		$this.PublishCustomMessage("`r`n" +[Constants]::DoubleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage("`n`n");
		$rmContext = [ContextHelper]::GetCurrentRMContext();
		$this.PublishCustomMessage("Logged-in user context", [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString(($rmContext.Account | Select-Object -Property Id, Type), $true), [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage("`n`n");
		$this.PublishCustomMessage("`r`nAzSK Settings`r`n" + [Constants]::SingleDashLine, [MessageType]::Default);
		$settings = [ConfigurationManager]::GetLocalAzSKSettings();
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString($settings, $true), [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage("`n`n");
		$this.PublishCustomMessage("`r`nAzSK Configurations`r`n" + [Constants]::SingleDashLine, [MessageType]::Default);
		$configurations = [ConfigurationManager]::GetAzSKConfigData();
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString($configurations, $true), [MessageType]::Default);
		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage("`n`n"); 
		$this.PublishCustomMessage("`r`nAz context`r`n" + [Constants]::SingleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage([Helpers]::ConvertObjectToString(($rmContext | Select-Object -Property Subscription, Tenant), $false), [MessageType]::Default);

		$this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
		$this.PublishCustomMessage("`r`nSPN Info`r`n" + [Constants]::SingleDashLine, [MessageType]::Default)
		$SPNList = [RemoteApiHelper]::GetSPNList("");
		$TelemetrySPNApplicationId = $this.GetSPNApplicationId($SPNList);
		$ownedSPNDetails = $this.GetOwnedSPNList();
		$CAUsedSPNApplicationId = $this.GetUsedSPN($ownedSPNDetails,$TelemetrySPNApplicationId);
		$NotInCAUsedSPNApplicationId = $this.GetUnusedSPN($CAUsedSPNApplicationId,$ownedSPNDetails);
        
        $this.PublishCustomMessage("`r`nSPN used in CA`r`n" + [Constants]::SingleDashLine, [MessageType]::Default)
		$this.PublishCustomMessage($CAUsedSPNApplicationId, [MessageType]::Default);
		
        $this.PublishCustomMessage("`r`nSPN not used in CA`r`n" + [Constants]::SingleDashLine, [MessageType]::Default)
        $this.PublishCustomMessage($NotInCAUsedSPNApplicationId.appId, [MessageType]::Default);
	}

	[PSObject] GetOwnedSPNList()
	{
		$ownedSPNDetails = @();
		$accessToken = Get-AzSKAccessToken -ResourceAppIdURI "https://graph.microsoft.com";
		$validatedUri = 'https://graph.microsoft.com/v1.0/me/ownedObjects';
		$access = invoke-webrequest -Uri $validatedUri -Headers @{"Authorization" = "Bearer $accessToken"} -method Get -ContentType "application/json" -UseBasicParsing
		$access_content = $access.Content | convertfrom-json;
		$ownedSPNDetails = $access_content.value | Select-Object -Property appDisplayName,appId

		return ($ownedSPNDetails);

	} 

	[PSObject] GetSPNApplicationId($SPNApplicationId)
	{
		$TelemetrySPNApplicationId = @();
		$SPNApplicationId = $SPNApplicationId | convertfrom-json;
        foreach ($item in $SPNApplicationId.tables.rows) 
        {
        	$TelemetrySPNApplicationId += $item;
        }
		return ($TelemetrySPNApplicationId);
	} 

	[PSObject] GetUsedSPN($ownedSPNDetails,$TelemetrySPNApplicationId)
	{
		$CAUsedSPNApplicationId = @();
		foreach ($SPNId in $ownedSPNDetails) 
		{
			if($SPNId.appId -in $TelemetrySPNApplicationId)
			{
				$CAUsedSPNApplicationId += $SPNId;
			}
			
		}
		return ($CAUsedSPNApplicationId);
	}

	[PSObject] GetUnusedSPN($CAUsedSPNApplicationId,$ownedSPNDetails)
	{
		$NotInCAUsedSPNApplicationId = @();
		foreach ($SPNId in $ownedSPNDetails) 
		{
			if($SPNId.appId -notin $CAUsedSPNApplicationId)
			{
				$NotInCAUsedSPNApplicationId += $SPNId;
			}
			
		}
		return ($NotInCAUsedSPNApplicationId);
	}
}