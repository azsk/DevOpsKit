using namespace System.Management.Automation
Set-StrictMode -Version Latest 

class SPNInfo: CommandBase
{    
	hidden $GraphOwnedObjectsAPIUri = [string]::Empty
	SPNInfo([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext) 
    { 
		$this.DoNotOpenOutputFolder = $true;
		$this.GraphOwnedObjectsAPIUri = 'https://graph.microsoft.com/v1.0/me/ownedObjects';
	}
	
	GetSPNInfo()
	{
		$ownedSPNs = @()
		$usedSPNs = @()
		$notInUsedSPNs = @()
		$rmContext = [ContextHelper]::GetCurrentRMContext();
        $this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nFetching SPN(s) Details...`r`n" + [Constants]::DoubleDashLine);
		#Get all owned SPNs
        $ownedSPNDetails = $this.GetOwnedSPNList();
		#Get SPNs start with AzSK_CA
		if($null -ne $ownedSPNDetails)
		{
			#Filter OwnedSPN start with AzSK_CA
			$ownedSPNs = $ownedSPNDetails | Where-Object { $_.displayName -like "AzSK_CA*"}
		}
		
		if($null -ne $ownedSPNs -and ($ownedSPNs | Measure-Object).Count -ne 0)
        {
			#Add subscriptionName and subscriptionId in ownedSPNs list
			$ownedSPNsObject = $this.CreateOwnedSPNObject($ownedSPNs.appId,$rmContext)
			#Get SPNsResponse which contain list of used SPNs
            $SPNsResponse = [RemoteApiHelper]::FetchUsedSPNList($ownedSPNsObject);
		    #Convert SPNsResponse into usedSPNs, which contain list of CA used SPNs 
		    if($null -ne $SPNsResponse)
			{
				$SPNsResponse | ConvertFrom-Json | where-object { $usedSPNs += $_ }
			}
			#Get list of notInUsedSPNs, which contain list of not in CA used SPNs
			if(($null -ne $usedSPNs) -and ($usedSPNs | Measure-Object).Count -ne 0)
			{
				$notInUsedSPNs = $ownedSPNs | where-object { $_.appId -notin $usedSPNs.appId }
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
			$uri=$this.GraphOwnedObjectsAPIUri;
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

	[PSObject] CreateOwnedSPNObject($ownedSPNApplicationId,$rmcontext)
	{
		$ownedSPNObject = "" | Select-Object SubscriptionId, SubscriptionName, UserSPNAppIds
		$ownedSPNObject.SubscriptionId = $rmcontext.Subscription.Id
		$ownedSPNObject.SubscriptionName = $rmcontext.Subscription.Name
		$ownedSPNObject.UserSPNAppIds = $ownedSPNApplicationId
		return ($ownedSPNObject);
	}

}