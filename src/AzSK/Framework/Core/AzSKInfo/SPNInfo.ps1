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
		$this.PublishCustomMessage([Constants]::DoubleDashLine + "`r`nFetching SPN(s) Details...`r`n" + [Constants]::DoubleDashLine);
		#Get all owned SPNs
		$ownedSPNDetails = $this.GetOwnedSPNList();
		try
		{
			#Get SPNs start with AzSK_CA
			if($null -ne $ownedSPNDetails)
			{
				#Filter OwnedSPN start with AzSK_CA
				$ownedSPNs = $ownedSPNDetails | Where-Object { $_.displayName -like "AzSK_CA*"}
			}
			
			if($null -ne $ownedSPNs -and ($ownedSPNs | Measure-Object).Count -ne 0)
			{
				#Get SPNsResponse which contain list of used SPNs
				$SPNsResponse = [RemoteApiHelper]::FetchUsedSPNList($ownedSPNs.appId);
				#Convert SPNsResponse into usedSPNs, which contain list of CA used SPNs (active SPNs)
				if(($null -ne $SPNsResponse) -and ($SPNsResponse -ne "ERROR") -and ( ($SPNsResponse | Get-Member StatusCode) -and  $SPNsResponse.StatusCode -eq 202))
				{
					$SPNsResponse | ConvertFrom-Json | where-object { $usedSPNs += $_ }
					#Get list of notInUsedSPNs, which contain list of SPNs which are currently not being used by CA 
					if(($null -ne $usedSPNs) -and ($usedSPNs | Measure-Object).Count -ne 0)
					{
                        # Get display name of the application id
                        $usedSPNs | ForEach-Object { 
                            
                            $appId = $_.appId;
                            $displayName = ($ownedSPNs | where-object { $appId -eq $_.appId } | Select-Object displayName).displayName;
                            $_ | Add-Member -MemberType NoteProperty -Name displayName -Value $displayName;
                        }

                        # Filter list of unused SPNs
						$notInUsedSPNs = $ownedSPNs | where-object { $_.appId -notin $usedSPNs.appId }
					}
					else 
					{
						$notInUsedSPNs = $ownedSPNs;
					}
					
					$this.PublishCustomMessage("`r`nSPN(s) owned by you which are currently being used by CA:`r`n",[MessageType]::Default)
						
					if(($usedSPNs | Measure-Object).Count -eq 0)
					{
						$this.PublishCustomMessage("`r`n`r`nCurrently there is no SPN owned by you, which is being used by CA.", [MessageType]::Warning);
					}
					else
					{
						$this.PublishCustomMessage($($usedSPNs | Format-Table @{Label = "ApplicationId"; Expression = { $_.appId } }, @{Label = "ApplicationDisplayName"; Expression = { $_.displayName } },@{Label = "SubscriptionId"; Expression = { $_.subscriptionId }},@{Label = "SubscriptionName"; Expression = { $_.subscriptionName } } -AutoSize -Wrap | Out-String), [MessageType]::Default)
					}
			
					$this.PublishCustomMessage([Constants]::SingleDashLine, [MessageType]::Default);
			
					$this.PublishCustomMessage("`r`nSPN(s) owned by you which have not been used by CA in last 7 days:`r`n",[MessageType]::Default)
					$this.PublishCustomMessage($($NotInUsedSPNs | Format-Table @{Label = "ApplicationId"; Expression = { $_.appId }},@{Label = "ApplicationDisplayName"; Expression = { $_.displayName } } -AutoSize | Out-String), [MessageType]::Default);
				}
				else
				{
					$this.PublishCustomMessage("`r`nUnable to validate SPN(s) details. StatusMessage [$($SPNsResponse)]`r`n", [MessageType]::Error)
				}
				
			}
			else
			{
				$this.PublishCustomMessage("`r`nCurrently there is no SPN owned by you, which is being used by CA.`r`n" + [Constants]::SingleDashLine, [MessageType]::Default)
			}
		}
		catch
		{
			$ExceptionMessage = $_;
			if ([Helpers]::CheckMember($_,"Exception.Message"))
            {
				$ExceptionMessage = $_.Exception.Message.ToString()
			}
			
			$this.PublishCustomMessage("`r`nUnable to validate SPN(s) details. StatusMessage [$($ExceptionMessage)]`r`n", [MessageType]::Error)
		}
    }

	# This function returns the list of AD application owned by current user
	[PSObject] GetOwnedSPNList()
	{
		# TODO: Move this to control setting file 
		$filterOwnedObjectsType = @("#microsoft.graph.application", "#microsoft.graph.servicePrincipal");
		$ownedSPNDetails = @()
		$result = ""
		try
        {
			$ResourceAppIdURI = [WebRequestHelper]::GetADGraphURL()
			$accessToken = [ContextHelper]::GetAccessToken($ResourceAppIdURI)
			$header = "Bearer " + $accessToken
			$headers = @{"Authorization"=$header;"Content-Type"="application/json";}
			$uri=$this.GraphOwnedObjectsAPIUri;
			
            # @odata.nextLink handled in the web request
            $responseContent = [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $headers, $null, [string]::Empty, @{})
			$ownedSPNDetails = $responseContent | Where-Object { $filterOwnedObjectsType -contains $_."@odata.type"} | Select-Object -Property displayName,appId -Unique 
    		return @($ownedSPNDetails);
			
        }
        catch 
        {	
			# Exception get handle in base class
            throw $_
        }
	} 

}