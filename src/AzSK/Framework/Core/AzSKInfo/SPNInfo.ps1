using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class SPNInfo: CommandBase
{    

	SPNInfo([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext) 
    { 
		$this.DoNotOpenOutputFolder = $true;
	}
	
	GetSPNInfo()
	{
        $this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nFetching SPN Details...`r`n" + [Constants]::DoubleDashLine);
		$this.PublishCustomMessage("`r`nSPN Info`r`n" + [Constants]::SingleDashLine, [MessageType]::Default)
		$SPNList = [RemoteApiHelper]::GetSPNList();
		$TelemetrySPNApplicationId = $this.GetSPNApplicationId($SPNList);
		$ownedSPNDetails = $this.GetOwnedSPNList();
		$CAUsedSPNApplicationId = $this.GetUsedSPN($ownedSPNDetails,$TelemetrySPNApplicationId);
		$NotInCAUsedSPNApplicationId = $this.GetUnusedSPN($CAUsedSPNApplicationId,$ownedSPNDetails);
        
        $this.PublishCustomMessage("`r`nSPN used in CA`r`n" + [Constants]::SingleDashLine, [MessageType]::Default)
        $this.PublishCustomMessage($($CAUsedSPNApplicationId | Format-Table @{Label = "SPNDisplayName"; Expression = { $_.displayName } },@{Label = "ApplicationId"; Expression = { $_.appId }} | Out-String), [MessageType]::Default)

        $this.PublishCustomMessage("`r`nSPN not used in CA`r`n" + [Constants]::SingleDashLine, [MessageType]::Default)
        $this.PublishCustomMessage($($NotInCAUsedSPNApplicationId | Format-Table @{Label = "SPNDisplayName"; Expression = { $_.displayName } },@{Label = "ApplicationId"; Expression = { $_.appId }} | Out-String), [MessageType]::Default);
        
    }

	[PSObject] GetOwnedSPNList()
	{
		$ownedSPNDetails = @();
		$accessToken = Get-AzSKAccessToken -ResourceAppIdURI "https://graph.microsoft.com";
		$validatedUri = 'https://graph.microsoft.com/v1.0/me/ownedObjects';
		$access = invoke-webrequest -Uri $validatedUri -Headers @{"Authorization" = "Bearer $accessToken"} -method Get -ContentType "application/json" -UseBasicParsing
		$access_content = $access.Content | convertfrom-json;
		
		$ownedSPNDetails = $access_content.value | Select-Object -Property displayName,appId -Unique

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