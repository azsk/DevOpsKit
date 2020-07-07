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
		$this.PublishCustomMessage("`r`nSPNs Info`r`n" + [Constants]::SingleDashLine, [MessageType]::Default)
		#Get all owned SPNs
        $ownedSPNDetails = $this.GetOwnedSPNList();
		#Get SPNs start with AzSK_CA
        $ownedSPNs = $this.GetOwnedSPNStartWithAzSK($ownedSPNDetails); #if owned spn is 0 then no need to make api call at backend
		#Get HttpsResponse which conrain CA used SPNs
        
        if($ownedSPNs.count -ne 0 -and $ownedSPNs -ne $null)
        {
            $SPNs = [RemoteApiHelper]::GetSPNList($ownedSPNs.appId);# sendSPNs start with AzSK,SPNList[CAUsedSPN]
		    #Get CAUsedSPNs
		    $usedSPNs = $this.GetUsedSPNs($SPNs);
		    #Get Not in CA Used SPNs
		    $notInUsedSPNs = $this.GetUnusedSPNs($usedSPNs,$ownedSPNs);
        
            #$this.PublishCustomMessage("`r`nSPN used in CA`r`n`n" + [Constants]::SingleDashLine, [MessageType]::Default)
        
            $this.PublishCustomMessage("`r`nSPN used in CA`r`n`n" + [Constants]::SingleDashLine, [MessageType]::Default)
                
            if($usedSPNs.count -le 1)
            {
                $this.PublishCustomMessage("Count : 0", [MessageType]::Default);
            }
            else
            {
                $this.PublishCustomMessage($($usedSPNs | Format-Table @{Label = "SPNApplicationId"; Expression = { $_.appId } },@{Label = "SubscriptionId"; Expression = { $_.subscriptionId }} -AutoSize -Wrap | Out-String), [MessageType]::Default)
            }
        
            $this.PublishCustomMessage([Constants]::DoubleDashLine, [MessageType]::Default);
        
            $this.PublishCustomMessage("`r`nSPN not used in CA`r`n`n" + [Constants]::SingleDashLine, [MessageType]::Default)
            $this.PublishCustomMessage($($NotInUsedSPNs | Format-Table @{Label = "ApplicationId"; Expression = { $_.appId }},@{Label = "SPNDisplayName"; Expression = { $_.displayName } } -AutoSize | Out-String), [MessageType]::Default);
        }
        else
        {
            $this.PublishCustomMessage("`r`nNo Owned SPNs found`r`n" + [Constants]::SingleDashLine, [MessageType]::Default)
        }
        
    }

	[PSObject] GetOwnedSPNList()
	{
		$ownedSPNDetails = @();
		$result = ""
		try
        {
            $accessToken = Get-AzSKAccessToken -ResourceAppIdURI "https://graph.microsoft.com";
		    $validatedUri = 'https://graph.microsoft.com/v1.0/me/ownedObjects';
		    $result = invoke-webrequest -Uri $validatedUri -Headers @{"Authorization" = "Bearer $accessToken"} -method Get -ContentType "application/json" -UseBasicParsing
		    if($null -ne $result -and $result.StatusCode -eq 200)
            {
                $result_content = $result.Content | convertfrom-json;
    		    $ownedSPNDetails = $result_content.value | Select-Object -Property displayName,appId -Unique 
    		    return ($ownedSPNDetails);
            }
            else
            {
                return ($null)#[Throw message]
            }
        }
        catch 
        {
            throw $_
        }
	} 

	[PSObject] GetUsedSPNs($SPNApplicationId)
	{
		$TelemetrySPNApplicationId = @();
		if($null -ne  $SPNApplicationId)
		{
			$SPNApplicationId = $SPNApplicationId | convertfrom-json;
			foreach ($item in $SPNApplicationId) 
			{
				$TelemetrySPNApplicationId += $item;
			}
		}
		return ($TelemetrySPNApplicationId);
	}


	[PSObject] GetOwnedSPNStartWithAzSK($ownedSPNDetails)
	{
		$OwnedSPNUsedInCA = @();
		if($null -ne  $ownedSPNDetails)
		{
			foreach ($ownedSPN in $ownedSPNDetails) 
			{
				if($ownedSPN.displayName -like 'AzSK_CA*')
				{
					$OwnedSPNUsedInCA += $ownedSPN;
				}
			}
		}
		return ($OwnedSPNUsedInCA);
	} 

	
	[PSObject] GetUnusedSPNs($usedSPNs,$ownedSPNs)
	{
		$NotInCAUsedSPNs = @();
		if($null -ne $ownedSPNs)
		{
			foreach ($SPNId in $ownedSPNs) 
			{
				if($SPNId -notin $usedSPNs)
				{
					$NotInCAUsedSPNs += $SPNId;
				}
				
			}
		}
		return ($NotInCAUsedSPNs);
	}
}