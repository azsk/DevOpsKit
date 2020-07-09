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
        $rmContext = [ContextHelper]::GetCurrentRMContext();
        $this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nFetching SPN(s) Details...`r`n" + [Constants]::DoubleDashLine);
		#$this.PublishCustomMessage("`r`nSPNs Info`r`n" + [Constants]::SingleDashLine, [MessageType]::Default)
		#Get all owned SPNs
        $ownedSPNDetails = $this.GetOwnedSPNList();
		#Get SPNs start with AzSK_CA
        $ownedSPNs = $this.FilterOwnedSPNStartWithAzSK($ownedSPNDetails);
		
        if($ownedSPNs -ne $null -and ($ownedSPNs | Measure-Object).Count -ne 0)
        {
			#Add subscriptionName and subscriptionId in ownedSPNs list
			$ownedSPNsObject = $this.CreateOwnedSPNObject($ownedSPNs.appId,$rmContext)
			#Get SPNsResponse which contain list of used SPNs
            $SPNsResponse = [RemoteApiHelper]::FetchUsedSPNList($ownedSPNsObject);
		    #Convert SPNsResponse into usedSPNs, which contain list of CA used SPNs 
		    $usedSPNs = $this.GetUsedSPNs($SPNsResponse);
		    #Get list of notInUsedSPNs, which contain list of not in CA used SPNs
			
			#If usedSPN count is 0 then no need to call GetUnusedSPNs()
			if(($usedSPNs | Measure-Object).Count -ne 0 -and $usedSPNs.appId -ne $null)
			{
				$notInUsedSPNs = $this.GetUnusedSPNs($usedSPNs,$ownedSPNs);
			}
			else 
			{
				$notInUsedSPNs = $ownedSPNs;
			}
			
            $this.PublishCustomMessage("`r`nSPN(s) owned by you which are currently being used by CA :`r`n",[MessageType]::Default) # + [Constants]::SingleDashLine, [MessageType]::Default
                
            if(($usedSPNs | Measure-Object).Count -eq 0)
            {
                $this.PublishCustomMessage("`r`nCurrently there is no SPN owned by you, which is being used by CA.", [MessageType]::Warning);
            }
            else
            {
                $this.PublishCustomMessage($($usedSPNs | Format-Table @{Label = "ApplicationId"; Expression = { $_.appId } },@{Label = "SubscriptionId"; Expression = { $_.subscriptionId }} -AutoSize -Wrap | Out-String), [MessageType]::Default)
            }
        
            $this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);
        
            $this.PublishCustomMessage("`r`nSPN(s) owned by you which are no longer being used by CA :`r`n",[MessageType]::Default) # + [Constants]::SingleDashLine, [MessageType]::Default
            $this.PublishCustomMessage($($NotInUsedSPNs | Format-Table @{Label = "ApplicationId"; Expression = { $_.appId }},@{Label = "SPN DisplayName"; Expression = { $_.displayName } } -AutoSize | Out-String), [MessageType]::Default);
        }
        else
        {
            $this.PublishCustomMessage("`r`nCurrently there is no SPN owned by you, which is being used by CA.`r`n" + [Constants]::SingleDashLine, [MessageType]::Default)
        }
        
    }

	[PSObject] GetOwnedSPNList()
	{
		$ownedSPNDetails = @()
		$result = ""
		try
        {
			$ResourceAppIdURI = [WebRequestHelper]::GetADGraphURL()
			$accessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
			$header = "Bearer " + $accessToken
			$headers = @{"Authorization"=$header;"Content-Type"="application/json";}
			$uri=$this.validatedUri;
			$result = [WebRequestHelper]::InvokeGetWebRequest($uri, $headers); 
			$ownedSPNDetails = $result | Select-Object -Property displayName,appId -Unique 
    		return ($ownedSPNDetails);
			
        }
        catch 
        {	
			#Exception get handle in base class
            throw $_
        }
	} 

	[PSObject] GetUsedSPNs($SPNsResponseObject)
	{
		$usedSPNs = @();
		if($null -ne  $SPNsResponseObject)
		{
			$parsedSPNsList = $SPNsResponseObject | convertfrom-json;
			foreach ($item in $parsedSPNsList) 
			{
				$usedSPNs += $item;
			}
		}
		return ($usedSPNs);
	}


	[PSObject] FilterOwnedSPNStartWithAzSK($ownedSPNDetails)
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
				if($SPNId.appId -notin $usedSPNs.appId)
				{
					$notInUsedSPNs += $SPNId;
				}
				
			}
		}
		return ($notInUsedSPNs);
	}

	[PSObject] CreateOwnedSPNObject($ownedSPNApplicationId,$rmcontext)
	{
		$ownedSPNObject = "" | Select-Object subscriptionId, subscriptionName, userSPNAppId
		$ownedSPNObject.subscriptionId = $rmcontext.Subscription.Id
		$ownedSPNObject.subscriptionName = $rmcontext.Subscription.Name
		$ownedSPNObject.userSPNAppId = $ownedSPNApplicationId
		return ($ownedSPNObject);
	}

}