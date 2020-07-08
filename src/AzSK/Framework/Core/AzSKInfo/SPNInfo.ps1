using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class SPNInfo: CommandBase
{    
	hidden $validatedUri = [string]::Empty
	SPNInfo([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext) 
    { 
		$this.DoNotOpenOutputFolder = $true;
		$this.validatedUri = 'https://graph.microsoft.com/v1.0/me/ownedObjects';
	}
	
	GetSPNInfo()
	{
        $this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nFetching SPNs Details...`r`n" + [Constants]::DoubleDashLine);
		$this.PublishCustomMessage("`r`nSPNs Info`r`n" + [Constants]::SingleDashLine, [MessageType]::Default)
		#Get all owned SPNs
        $ownedSPNDetails = $this.GetOwnedSPNList();
		#Get SPNs start with AzSK_CA
        $ownedSPNs = $this.GetOwnedSPNStartWithAzSK($ownedSPNDetails);
		
        if($ownedSPNs.count -ne 0 -and $ownedSPNs -ne $null)
        {
			#Get Http response which contain used SPNs applicationId
            $SPNs = [RemoteApiHelper]::GetSPNList($ownedSPNs.appId);
		    #Convert HttpResponse from json and Get CAUsedSPNs 
		    $usedSPNs = $this.GetUsedSPNs($SPNs);
		    #Get Not in CA Used SPNs
		    $notInUsedSPNs = $this.GetUnusedSPNs($usedSPNs,$ownedSPNs);
        
            $this.PublishCustomMessage("`r`nIn CA used SPNs`r`n`n" + [Constants]::SingleDashLine, [MessageType]::Default)
                
            if($usedSPNs.count -le 1)
            {
                $this.PublishCustomMessage("Count : 0", [MessageType]::Default);
            }
            else
            {
                $this.PublishCustomMessage($($usedSPNs | Format-Table @{Label = "SPNApplicationId"; Expression = { $_.appId } },@{Label = "SubscriptionId"; Expression = { $_.subscriptionId }} -AutoSize -Wrap | Out-String), [MessageType]::Default)
            }
        
            $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);
        
            $this.PublishCustomMessage("`r`nNot in CA used SPNs`r`n`n" + [Constants]::SingleDashLine, [MessageType]::Default)
            $this.PublishCustomMessage($($NotInUsedSPNs | Format-Table @{Label = "ApplicationId"; Expression = { $_.appId }},@{Label = "SPNDisplayName"; Expression = { $_.displayName } } -AutoSize | Out-String), [MessageType]::Default);
        }
        else
        {
            $this.PublishCustomMessage("`r`nNo CA using SPNs found`r`n" + [Constants]::SingleDashLine, [MessageType]::Default)
        }
        
    }

	[PSObject] GetOwnedSPNList()
	{
		$ownedSPNDetails = @()
		$result = ""
		try
        {
			$ResourceAppIdURI = [WebRequestHelper]::GetUserSPNsUrl()
			$accessToken = Get-AzSKAccessToken -ResourceAppIdURI $ResourceAppIdURI
			
			$header = "Bearer " + $accessToken
			$headers = @{"Authorization"=$header;"Content-Type"="application/json";}

		    $uri = $this.validatedUri;
		    $result = invoke-webrequest -Uri $uri -Headers $headers -method Get -UseBasicParsing
			if($null -ne $result -and $result.StatusCode -eq 200)
            {
                $result_content = $result.Content | convertfrom-json;
    		    $ownedSPNDetails = $result_content.value | Select-Object -Property displayName,appId -Unique 
    		    return ($ownedSPNDetails);
			}
			else {
				return($null);
			}
        }
        catch 
        {
            throw $_
        }
	} 

	[PSObject] GetUsedSPNs($SPNApplicationId)
	{
		$usedSPNs = @();
		if($null -ne  $SPNApplicationId)
		{
			$SPNApplicationId = $SPNApplicationId | convertfrom-json;
			foreach ($item in $SPNApplicationId) 
			{
				$usedSPNs += $item;
			}
		}
		return ($usedSPNs);
	}


	[PSObject] GetOwnedSPNStartWithAzSK($ownedSPNDetails)
	{
		$ownedSPNUsedInCA = @();
		if($null -ne  $ownedSPNDetails)
		{
			foreach ($ownedSPN in $ownedSPNDetails) 
			{
				if($ownedSPN.displayName -like 'AzSK_CA*')
				{
					$ownedSPNUsedInCA += $ownedSPN;
				}
			}
		}
		return ($ownedSPNUsedInCA);
	} 

	
	[PSObject] GetUnusedSPNs($usedSPNs,$ownedSPNs)
	{
		$notInUsedSPNs = @();
		if($null -ne $ownedSPNs)
		{
			foreach ($SPNId in $ownedSPNs) 
			{
				if($SPNId -notin $usedSPNs)
				{
					$notInUsedSPNs += $SPNId;
				}
				
			}
		}
		return ($notInUsedSPNs);
	}
}