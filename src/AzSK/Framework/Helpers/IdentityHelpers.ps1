Set-StrictMode -Version Latest 

class IdentityHelpers
{

	hidden static [bool] IsServiceAccount($ObjectId, $SignInName, $ObjectType, $GraphAccessToken)
	{
		$return = $null    		
		$header = "Bearer " + $GraphAccessToken
		$RMContext = [Helpers]::GetCurrentRMContext()
		$headers = @{"Authorization"=$header;"Content-Type"="application/json"}
		$uri=""    
		$output = $null
		if($ObjectType -eq "User")
		{
			if($null -ne $ObjectId -and [System.Guid]::Empty -ne $ObjectId)
			{
				$uri = [string]::Format("https://graph.windows.net/{0}/users/{1}?api-version=1.6",$RMContext.Tenant.Id, $ObjectId)
			}
			elseif ($null -ne $SignInName) {
				$uri = [string]::Format("https://graph.windows.net/{0}/users/{1}?api-version=1.6",$RMContext.Tenant.Id, $SignInName)        
			}
			else {
				return $false
			}
		}
		elseif($ObjectType -eq "ServicePrincipal"){
			return $false
		}
		else
		{
			#in the case of coadmins
			return $false
		}
	
		$err = $null
		$result = ""
		try { 
				$result = Invoke-WebRequest -Method GET -Uri $uri -Headers $headers -UseBasicParsing
				if($result.StatusCode -ge 200 -and $result.StatusCode -le 399){
					if($null -ne $result.Content){
						$json = (ConvertFrom-Json $result.Content)
						if($null -ne $json){
							$output = $json
							if($null -ne ($json | Get-Member value) )
							{
								$output = $json.value
							}
						}
					}
					$isGuid = [IdentityHelpers]::IsADObjectGUID($output.immutableId)
					return $isGuid          
				}  
			} 
		catch{ 
			$err = $_ 
			if($null -ne $err)
			{
				if($null -ne $err.ErrorDetails.Message){
					$json = (ConvertFrom-Json $err.ErrorDetails.Message)
					if($null -ne $json){
						$return = $json
						if($json.'odata.error'.code -eq "Request_ResourceNotFound")
						{
							return $false;
						}
					}
				}
			}
		}
		return $null 
	}


	hidden static [bool] IsADObjectGUID($immutableId){        
		try {
			$decodedII = [system.convert]::frombase64string($immutableId)
			$guid = [GUID]$decodedII    
		}
		catch {
			return $false
		}
		return $true
	}
}