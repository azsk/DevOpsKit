Set-StrictMode -Version Latest 
class ActiveDirectoryHelper {

		static [PSObject] GetADAppServicePrincipalByAppId($ApplicationId)
		{
			$TenantId = ([Helpers]::GetCurrentRMContext()).Tenant.Id
			$ApiVersion = "1.6"
			$GraphApiUrl = [WebRequestHelper]::GraphApiUri + $TenantId + "/servicePrincipals/{0}?api-version=$ApiVersion"
			$uri = [string]::Format($GraphApiUrl + "&`$filter=(appId eq '{1}')", [string]::Empty , $ApplicationId);
			$resultObject = [WebRequestHelper]::InvokeGetWebRequest($uri);
			
			#this returns array of objects. Actual object is present at 1st index
			if($resultObject)
			{
				return $resultObject[0]
			}
			else
			{
				return $null
			}
			
		}

		static [void] UpdateADAppServicePrincipalCredential(
			$ApplicationID,
			[System.Security.Cryptography.X509Certificates.X509Certificate2]
			$PublicCert,
			[System.DateTime]
			$NotBefore = (Get-Date).AddDays(-1),
			[System.DateTime]
			$NotAfter = $NotBefore.AddMonths(6),
			[string]
			$Delete = "False"
		)
		{
			#Initialization
			$TenantId = ([Helpers]::GetCurrentRMContext()).Tenant.Id
			$ApiVersion = "1.6"
			$GraphApiUrl = [WebRequestHelper]::GraphApiUri + $TenantId + "/servicePrincipals/{0}?api-version=$ApiVersion"
			$addMode = $False;
			$startDateString = $NotBefore.ToString("O");
			$endDateString = $NotAfter.ToString("O");

			if($Delete -eq "False")
			{
				if(-not $PublicCert)
				{
					throw "Public Certificate cannot be null"
				}
			}

			$servicePrincipal =  [ActiveDirectoryHelper]::GetADAppServicePrincipalByAppId($ApplicationID)

			if($Delete -eq "False")
			{
				if($null -eq $servicePrincipal)
				{
					$addMode = $True;
					$servicePrincipal = New-Object -TypeName PSObject;
					$servicePrincipal | Add-Member -MemberType NoteProperty -Name appId -Value $ApplicationID -PassThru
				}

				$publicCertString = [System.Convert]::ToBase64String($PublicCert.GetRawCertData());

				$credentialObject = New-Object -TypeName PSObject
				$credentialObject | Add-Member -MemberType NoteProperty -Name endDate -Value $endDateString -PassThru `
									| Add-Member -MemberType NoteProperty -Name startDate -Value $startDateString -PassThru

				$credentialObject | Add-Member -MemberType NoteProperty -Name type -Value "AsymmetricX509Cert" -PassThru `
										| Add-Member -MemberType NoteProperty -Name usage -Value "Verify" -PassThru `
										| Add-Member -MemberType NoteProperty -Name value -Value $publicCertString

				if ([bool](Get-Member -InputObject $servicePrincipal -Name "keyCredentials"))
				{
					[System.Collections.ArrayList]$keys = $servicePrincipal.keyCredentials
					$credentialList = $keys.Add($credentialObject)
					$servicePrincipal.keyCredentials = $keys
				}
				else
				{
					$servicePrincipal | Add-Member -MemberType NoteProperty -Name keyCredentials -Value @($credentialObject)
				}
			}
			elseif($Delete -eq "True")
			{	
				$servicePrincipal.keyCredentials = $servicePrincipal.keyCredentials | Where-Object { 
					[System.DateTime]::Parse($_.startDate).ToUniversalTime() -ne $NotBefore.ToUniversalTime() `
					-and [System.DateTime]::Parse($_.endDate).ToUniversalTime() -ne $NotAfter.ToUniversalTime() `
				} 
			}
			elseif($Delete -eq "All")
			{
				$servicePrincipal.keyCredentials = @()
			}
			$servicePrincipal = $servicePrincipal | Select-Object * -ExcludeProperty "requiredResourceAccess"  

			$body = ConvertTo-Json -InputObject $servicePrincipal
			$operation = [string]::Empty;
			$requestUri = [string]::Empty;
			$GraphAPIAccessToken = Get-AzSKAccessToken -ResourceAppIdURI "https://graph.windows.net/";
			if($addMode)
			{
				$operation = "POST";
				$requestUri = [string]::Format($GraphApiUrl, [string]::Empty);
			}
			else
			{
				$operation = "PATCH";
				$requestUri = [string]::Format($GraphApiUrl, $servicePrincipal.objectId);
			}

			$updateResult = Invoke-RestMethod `
							-Method $operation `
							-Uri $requestUri `
							-Headers @{ Authorization = "Bearer " + $GraphAPIAccessToken } `
							-ContentType "application/json" `
							-Body $body `
							-UseBasicParsing

			if($null -eq $updateResult)
			{
				 Throw "There was a problem while updating the service principal with new certificate"    
			}
	}

		static [PSObject] GetADAppByAppId($ApplicationId)
		{
			$TenantId = ([Helpers]::GetCurrentRMContext()).Tenant.Id
			$ApiVersion = "1.6"
			$GraphApiUrl = [WebRequestHelper]::GraphApiUri + $TenantId + "/applications/{0}?api-version=$ApiVersion"
			$uri = [string]::Format($GraphApiUrl + "&`$filter=(appId eq '{1}')", [string]::Empty , $ApplicationId);
			$resultObject = [WebRequestHelper]::InvokeGetWebRequest($uri);
			
			#this returns array of objects. Actual object is present at 1st index
			if($resultObject)
			{
				return $resultObject[0]
			}
			else
			{
				return $null
			}
			
		}
		
		static [void] UpdateADAppCredential(
			$ApplicationID,
			[System.Security.Cryptography.X509Certificates.X509Certificate2]
			$PublicCert,
			[System.DateTime]
			$NotBefore = (Get-Date).AddDays(-1),
			[System.DateTime]
			$NotAfter = $NotBefore.AddMonths(6),
			[string]
			$Delete = "False"
		)
		{
			#Initialization
			$TenantId = ([Helpers]::GetCurrentRMContext()).Tenant.Id
			$ApiVersion = "1.6"
			$GraphApiUrl = [WebRequestHelper]::GraphApiUri + $TenantId + "/applications/{0}?api-version=$ApiVersion"
			$startDateString = $NotBefore.ToString("O");
			$endDateString = $NotAfter.ToString("O");

			if($Delete -eq "False")
			{
				if(-not $PublicCert)
				{
					throw "Public Certificate cannot be null"
				}
			}

			$ADApplication =  [ActiveDirectoryHelper]::GetADAppByAppId($ApplicationID)
			if($Delete -eq "False")
			{
				$publicCertString = [System.Convert]::ToBase64String($PublicCert.GetRawCertData());

				$credentialObject = New-Object -TypeName PSObject
				$credentialObject | Add-Member -MemberType NoteProperty -Name endDate -Value $endDateString -PassThru `
									| Add-Member -MemberType NoteProperty -Name startDate -Value $startDateString -PassThru

				$credentialObject | Add-Member -MemberType NoteProperty -Name type -Value "AsymmetricX509Cert" -PassThru `
										| Add-Member -MemberType NoteProperty -Name usage -Value "Verify" -PassThru `
                                        | Add-Member -MemberType NoteProperty -Name value -Value $publicCertString
                if ([bool](Get-Member -InputObject $ADApplication -Name "keyCredentials"))
				{
					[System.Collections.ArrayList]$keys = $ADApplication.keyCredentials
					$keys.Add($credentialObject)
					$ADApplication.keyCredentials = $keys
				}
				else
				{
					$ADApplication | Add-Member -MemberType NoteProperty -Name keyCredentials -Value @($credentialObject)
				}
			}
			elseif($Delete -eq "True")
			{	
				$ADApplication.keyCredentials = $ADApplication.keyCredentials | Where-Object { 
					[System.DateTime]::Parse($_.startDate).ToUniversalTime() -ne $NotBefore.ToUniversalTime() `
					-and [System.DateTime]::Parse($_.endDate).ToUniversalTime() -ne $NotAfter.ToUniversalTime() `
				} 
			}
			elseif($Delete -eq "All")
			{
				$ADApplication.keyCredentials = @()
			}
		    $finalCredsObject = $ADApplication | Select-Object -Property keyCredentials
			$body = ConvertTo-Json -InputObject $finalCredsObject 
			$operation = [string]::Empty;
			$requestUri = [string]::Empty;
			$GraphAPIAccessToken = Get-AzSKAccessToken -ResourceAppIdURI "https://graph.windows.net/";
			$operation = "PATCH";
			$requestUri = [string]::Format($GraphApiUrl, $ADApplication.objectId);
			$updateResult = Invoke-RestMethod `
							-Method $operation `
							-Uri $requestUri `
							-Headers @{ Authorization = "Bearer " + $GraphAPIAccessToken } `
							-ContentType "application/json" `
							-Body $body `
							-UseBasicParsing

			if($null -eq $updateResult)
			{
				 Throw "There was a problem while updating the service principal with new certificate"    
			}
	}

		static [PSObject] NewSelfSignedCertificate($AppName,$CertStartDate,$CertEndDate,$Provider)
		{
				$newCertificate = New-SelfSignedCertificate -DnsName $AppName `
																	-Subject "CN=$AppName" `
																	-CertStoreLocation Cert:\CurrentUser\My `
																	-KeyExportPolicy Exportable `
																	-NotBefore $CertStartDate `
																	-NotAfter $CertEndDate `
																	-Type DocumentEncryptionCert `
																	-KeyUsage DataEncipherment `
																	-KeySpec KeyExchange `
																	-KeyUsageProperty Decrypt `
																	-Provider $Provider `
																	-ErrorAction Stop 
				return $newCertificate
		}
}
