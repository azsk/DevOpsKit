Set-StrictMode -Version Latest 
class WebRequestHelper {
   
	hidden static [string] $AzureManagementUri = "https://management.azure.com/";
	hidden static [string] $GraphApiUri = "https://graph.windows.net/";
	hidden static [string] $ClassicManagementUri = "https://management.core.windows.net/";

    static [System.Object[]] InvokeGetWebRequest([string] $uri, [Hashtable] $headers) 
	{
        return [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, $uri, $headers, $null);
    }

	static [System.Object[]] InvokeGetWebRequest([string] $uri) 
	{	
        return [WebRequestHelper]::InvokeGetWebRequest($uri, [WebRequestHelper]::GetAuthHeaderFromUri($uri));
    }

	hidden static [Hashtable] GetAuthHeaderFromUri([string] $uri)
	{
		[System.Uri] $validatedUri = $null;
        if([System.Uri]::TryCreate($uri, [System.UriKind]::Absolute, [ref] $validatedUri))
		{
			return @{
				"Authorization"= ("Bearer " + [Helpers]::GetAccessToken($validatedUri.GetLeftPart([System.UriPartial]::Authority))); 
				"Content-Type"="application/json"
			};

		}
		
		return @{ "Content-Type"="application/json" };
	}

	static [System.Object[]] InvokePostWebRequest([string] $uri, [Hashtable] $headers, [System.Object] $body) 
	{
        return [WebRequestHelper]::InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod]::Post, $uri, $headers, $body);
	}

	static [System.Object[]] InvokePostWebRequest([string] $uri, [System.Object] $body) 
	{
        return [WebRequestHelper]::InvokePostWebRequest($uri, [WebRequestHelper]::GetAuthHeaderFromUri($uri), $body);
	}

	static [System.Object[]] InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod] $method, [string] $uri, [System.Object] $body) 
	{
        return [WebRequestHelper]::InvokeWebRequest($method, $uri, [WebRequestHelper]::GetAuthHeaderFromUri($uri), $body);
	}

    static [System.Object[]] InvokeWebRequest([Microsoft.PowerShell.Commands.WebRequestMethod] $method, [string] $uri, [Hashtable] $headers, [System.Object] $body) 
	{
       
        $outputValues = @();
		[System.Uri] $validatedUri = $null;
        while ([System.Uri]::TryCreate($uri, [System.UriKind]::Absolute, [ref] $validatedUri)) 
		{
			[int] $retryCount = 3
			$success = $false;
			while($retryCount -gt 0 -and -not $success)
			{
				$retryCount = $retryCount -1;
				try
				{
					$requestResult = $null;
			
					if ($method -eq [Microsoft.PowerShell.Commands.WebRequestMethod]::Get) 
					{
						$requestResult = Invoke-WebRequest -Method $method -Uri $validatedUri -Headers $headers -UseBasicParsing
					}
					elseif ($method -eq [Microsoft.PowerShell.Commands.WebRequestMethod]::Post -or $method -eq [Microsoft.PowerShell.Commands.WebRequestMethod]::Put) 
					{
						$requestResult = Invoke-WebRequest -Method $method -Uri $validatedUri -Headers $headers -Body ($body | ConvertTo-Json -Depth 10 -Compress) -UseBasicParsing
					}	
					else 
					{
						throw [System.ArgumentException] ("The web request method type '$method' is not supported.")
					}		
			
					if ($null -ne $requestResult -and $requestResult.StatusCode -ge 200 -and $requestResult.StatusCode -le 399) {
						if ($null -ne $requestResult.Content) {
							$json = (ConvertFrom-Json $requestResult.Content)
							if ($null -ne $json) {
								if (($json | Get-Member -Name "value") -and $json.value) {
									$outputValues += $json.value;
								}
								else {
									$outputValues += $json;
								}
						
								if (($json | Get-Member -Name "nextLink") -and $json.nextLink) {
									$uri = $json.nextLink
								}
								else {
									$uri = [string]::Empty;
								}
							}
						}
					}
					$success = $true;
				}
				catch
				{
					#eat the exception until it is in retry mode and throw once the retry is done
					if($retryCount -eq 0)
					{
						if([Helpers]::CheckMember($_,"Exception.Response.StatusCode") -and  $_.Exception.Response.StatusCode -eq "Forbidden"){
							throw ([SuppressedException]::new(("You do not have permission to view the requested resource."), [SuppressedExceptionType]::InvalidOperation))
						}
						elseif ([Helpers]::CheckMember($_,"Exception.Message")){
							throw ([SuppressedException]::new(($_.Exception.Message.ToString()), [SuppressedExceptionType]::InvalidOperation))
						}
						else {
							throw;
						}
					}					
				}
			}
        }

        return $outputValues;
    }

}
