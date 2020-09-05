Set-StrictMode -Version Latest 
class ActiveDirectoryHelper {

       

		static [PSObject] GetADAppServicePrincipalByAppId($ApplicationId)
		{
			$TenantId = ([ContextHelper]::GetCurrentRMContext()).Tenant.Id
			$ApiVersion = "1.6"
			$GraphUri = [WebRequestHelper]::GetGraphUrl()
			$GraphApiUrl = $GraphUri + $TenantId + "/servicePrincipals/{0}?api-version=$ApiVersion"
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
			$TenantId = ([ContextHelper]::GetCurrentRMContext()).Tenant.Id
			$ApiVersion = "1.6"
			$GraphUri = [WebRequestHelper]::GetGraphUrl()
			$GraphApiUrl = $GraphUri + $TenantId + "/servicePrincipals/{0}?api-version=$ApiVersion"
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
			$ResourceAppIdURI = [WebRequestHelper]::GetGraphUrl()
			$GraphAPIAccessToken = Get-AzSKAccessToken -ResourceAppIdURI $ResourceAppIdURI;
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
			$TenantId = ([ContextHelper]::GetCurrentRMContext()).Tenant.Id
			$ApiVersion = "1.6"
			$GraphUri = [WebRequestHelper]::GetGraphUrl()
			$GraphApiUrl = $GraphUri + $TenantId + "/applications/{0}?api-version=$ApiVersion"
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
			$TenantId = ([ContextHelper]::GetCurrentRMContext()).Tenant.Id
			$ApiVersion = "1.6"
			$GraphUri = [WebRequestHelper]::GetGraphUrl()
			$GraphApiUrl = $GraphUri + $TenantId + "/applications/{0}?api-version=$ApiVersion"
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

            if($Delete -eq "Select")
            {
                
               # Collecting all Certificates -> Old + Latest Certificates
               [System.Collections.ArrayList]$AllCerts = $ADApplication.keyCredentials

               # Filtering out the latest Certificate among all Certificates
               [System.Collections.ArrayList]$latestCert = @($AllCerts | Where-Object { 
					[System.DateTime]::Parse($_.startDate).ToUniversalTime() -eq $NotBefore.ToUniversalTime() `
					-and [System.DateTime]::Parse($_.endDate).ToUniversalTime() -eq $NotAfter.ToUniversalTime() 
				})

                # Filtering out the Older Certificates associated with CA SPN
                [System.Collections.ArrayList]$OldCerts = @($AllCerts | Where-Object { $latestCert -notcontains $_ })
                Write-host "We found the following older credentials associated with [$($ADApplication.displayname)]:" -ForegroundColor Yellow
                
                # Displaying older Certificates in form of table               
                $display= $OldCerts|Format-Table -Property  @{name="Index";expression={$OldCerts.IndexOf($_)}},@{name="Thumbprint";expression={$_.customKeyIdentifier}},@{name="EndDate(MM/dd/yyyy)";expression={([datetime] $_.endDate).ToString("MM/dd/yyyy")}} | Out-String
                Write-Host $display

                Write-host "Before Deleting make sure that the Certificates are not used anywhere else!!!" -ForegroundColor Yellow
                Write-Host "Please select an action from below: `n[A]: Delete All`n[N]: Delete None`n[S]: Delete Selected" -ForegroundColor Cyan         
                
                # Initializing an empty array list to add certificates for deletion
                [System.Collections.ArrayList] $removedCerts = @() 
                
                $userChoice=""
                while($userChoice -ne 'A' -and $userChoice -ne 'N' -and $userChoice -ne 'S')
                {
                 $userChoice = Read-Host "User Choice"
                    if(-not [string]::IsNullOrWhiteSpace($userChoice))
				    {
					$userChoice = $userChoice.Trim();
				    }
                }

                # Variable used for taking confirmation for any/all Certificate deletion.
                $confirmation=""

                switch ($userChoice.ToUpper())
                {                    
			        "A" #DeleteAll
			        {	
                      while($confirmation.ToUpper() -ne 'Y' -and $confirmation.ToUpper() -ne 'N')
                      {
                      $confirmation = Read-Host "Do you want to delete all Certificates ? (Y/N)"
                       if(-not [string]::IsNullOrWhiteSpace($confirmation))
				         {
					        $confirmation = $confirmation.Trim();
				         }
                      } 
                      if($confirmation.ToUpper() -eq 'Y')
                      { 
                      Write-Host "Deleting All certificates. This may take few min..." -ForegroundColor Yellow			
			          $ADApplication.keyCredentials = $latestCert
                      }
                      else
                      {
                      Write-Host "No Certificates are deleted." -ForegroundColor Yellow
                      }
                       break  				
			        }
			        "N" #None
			        {
                        Write-Host "No Certificates are deleted." -ForegroundColor Yellow                   
			            break
			        }
			        "S" #Select
			        {
                      do{  
                            # flag used for validating the indexes entered by user.
                            $validIndexFlag=$true

                            $invalidindexes=""
                            $indexs=Read-Host "Enter comma separated index(s) from the above table:"
                            $indexs = $indexs.Trim();
                            if([string]::IsNullOrWhiteSpace($indexs) -or $indexs -eq ',')
                            {
                            Write-Host "You have entered blank values, please enter a valid index."  -ForegroundColor Yellow 
                            $validIndexFlag=$false                     
                            }
                            else
                            {
                             $indexArray = $indexs.Split(',',[System.StringSplitOptions]::RemoveEmptyEntries).Trim()
                             $indexArray | ForEach-Object{
                                                             $i=$_
                                                             try
                                                             {
                                                              #Using Array index property to validate whether the index is valid or not.
                                                              if($OldCerts[$i]){ }
                                                             }
                                                             catch
                                                             {
                                                                $validIndexFlag = $false

                                                                # Collecting all invalid indexes and making a comma separated string like '1,2,'
                                                                # so that same string can be displayed in case of invalid indexes 
                                                                $invalidindexes += $i+","
                                                             }
                                                         }
                             if($validIndexFlag)
                              {
                                    # All indexes are valid.
                                    $OldCerts | ForEach-Object { 
                                                                        if($indexArray -contains $OldCerts.IndexOf($_))
                                                                         {
                                                                            $removedCerts.add($OldCerts[$OldCerts.IndexOf($_)])
                                                                         }
                                                    
                                                                 }

                                         Write-Host "Certificates selected for deletion: " -ForegroundColor Cyan 
                                         $output=$removedCerts|Format-Table -Property @{name="Thumbprint";expression={$_.customKeyIdentifier}} | Out-String 
                                         Write-Host $output
                                    while($confirmation.ToUpper() -ne 'Y' -and $confirmation.ToUpper() -ne 'N')
                                     {
                                      $confirmation = Read-Host "Do you want to delete the selected Certificates ? (Y/N)"
                                      if(-not [string]::IsNullOrWhiteSpace($confirmation))
				                         {
					                       $confirmation = $confirmation.Trim();
				                         }
                                     } 
                                    if($confirmation.ToUpper() -eq 'Y')
                                    { 
                                         
                                         $ADApplication.keyCredentials	= $AllCerts | Where-Object { $removedCerts -notcontains $_ }
                                         Write-Host "Selected Certificates are deleted." -ForegroundColor Yellow
                                    }
                                    else
                                    {
                                        Write-Host "No Certificates are deleted." -ForegroundColor Yellow
                                    }

                               
                             }
                             else
                             {
                                # All/ Any index is/are invalid
                                Write-Host "Please provide valid index(s) from above table." -ForegroundColor Yellow

                                #Checking the count of invalid indexes so that valid message ( for 1 or many invalid indexes) can be displayed.
                                if($invalidindexes.Split(',',[System.StringSplitOptions]::RemoveEmptyEntries).count -eq 1)
                                {
                                   # Printing invalidindexes string without last comma => 1, => 1
                                   Write-Host " $(-join$invalidindexes[0..($invalidindexes.Length-2)]) is not a valid index. "
                                }
                                else
                                {
                                   # Printing invalidindexes string without last comma => 1,2, => 1,2
                                   Write-Host " $(-join$invalidindexes[0..($invalidindexes.Length-2)]) are not valid indexes. "
                                }
                                Write-Host "No Certificates are deleted !!!" -ForegroundColor Yellow
                             } 
                         } 
                        }while(-not($validIndexFlag))
                             break
			        }
                    Default {
                                Write-Host "You have entered incorrect choice. Please enter valid choice." -ForegroundColor Yellow
                             }
                }
                 
                

            }
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
					-and [System.DateTime]::Parse($_.endDate).ToUniversalTime() -ne $NotAfter.ToUniversalTime() 
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
			$ResourceAppIdURI = [WebRequestHelper]::GetGraphUrl()
			$GraphAPIAccessToken = Get-AzSKAccessToken -ResourceAppIdURI $ResourceAppIdURI;
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
