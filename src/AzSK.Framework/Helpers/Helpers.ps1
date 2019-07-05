using namespace Newtonsoft.Json
using namespace Microsoft.Azure.Commands.Common.Authentication.Abstractions
using namespace Microsoft.Azure.Commands.Common.Authentication
using namespace Microsoft.Azure.Management.Storage.Models
Set-StrictMode -Version Latest
class Helpers {

    hidden static [PSObject] LoadOfflineConfigFile([string] $fileName, [bool] $parseJson) {
		$rootConfigPath = [Constants]::AzSKAppFolderPath ;
		return [Helpers]::LoadOfflineConfigFile($fileName, $true,$rootConfigPath);
	}
    hidden static [PSObject] LoadOfflineConfigFile([string] $fileName, [bool] $parseJson, $path) {
		#Load file from AzSK App folder
		$rootConfigPath = $path ;	
        
		$extension = [System.IO.Path]::GetExtension($fileName);

		$filePath = $null
		if(Test-Path -Path $rootConfigPath)
		{
			$filePath = (Get-ChildItem $rootConfigPath -Name -Recurse -Include $fileName) | Select-Object -First 1 
		}
        #If file not present in App folder load settings from Configurations in Module folder 
        if (!$filePath) {
            $rootConfigPath = Join-Path (Get-Item $PSScriptRoot).Parent.FullName "Configurations";
            $filePath = (Get-ChildItem $rootConfigPath -Name -Recurse -Include $fileName) | Select-Object -First 1 
        }

        if ($filePath)
		{
			if($parseJson)
			{
				if($extension -eq ".json" -or $extension -eq ".lawsview")
				{
					$fileContent = (Get-Content -Raw -Path ($rootConfigPath + $filePath)) | ConvertFrom-Json
				}
				else
				{
					$fileContent = (Get-Content -Raw -Path ($rootConfigPath + $filePath)) 
				}
			}
			else
			{
				$fileContent = (Get-Content -Raw -Path ($rootConfigPath + $filePath)) 
			}
        }
        else {
            throw "Unable to find the specified file '$fileName'"          
        }
        if (-not $fileContent) {
            throw "The specified file '$fileName' is empty"                                  
        }

        return $fileContent;
    }


    static AbstractClass($obj, $classType) {
        $type = $obj.GetType()
        if ($type -eq $classType) {
            throw("Class '$type' must be inherited")
        }
    }

    static [string] SanitizeFolderName($folderPath) {
        return ($folderPath -replace '[<>:"/\\\[\]|?*]', '');
    }

    static [string] ConvertObjectToString([PSObject] $dataObject, [bool] $defaultPsOutput) {
        [string] $msg = "";
        if ($dataObject) {
            if ($dataObject.GetType().FullName -eq "System.Management.Automation.ErrorRecord") {
				if($dataObject.Exception -is [SuppressedException])
				{
					$msg = $dataObject.Exception.ConvertToString();
				}
				else
				{
					if ($defaultPsOutput)
					{
						$msg = $dataObject.ToString();
					}
					else
					{
						$msg = ($dataObject | Out-String) + "`r`nStackTrace: " + $dataObject. ScriptStackTrace
					}
				}                
            }
            else {
                if ($defaultPsOutput -or $dataObject.GetType() -eq [string]) {
                    $msg = $dataObject | Out-String;
                }
                else {
                    try {
                        #$msg = $dataObject | ConvertTo-Json -Depth 5 | Out-String;
                        #$msg = [JsonHelper]::ConvertToJsonCustom($dataObject);
                        $msg = [JsonHelper]::ConvertToPson($dataObject);
                    }
                    catch {
                        $e = $_
                        $msg = $dataObject | Format-List | Out-String;
                    }

                    $msg = $msg.Trim();
                    #$msg = $msg.TrimStart("`r`n");
                }
            }
        }

        return $msg.Trim("`r`n");
    }

    static [bool] CompareObject($referenceObject, $differenceObject) {
        return [Helpers]::CompareObject($referenceObject, $differenceObject, $false)
    }

    static [bool] CompareObject($referenceObject, $differenceObject, [bool] $strictComparison) {
        $result = $true;

        if ($null -ne $referenceObject) {
            if ($null -ne $differenceObject) {
                if ($referenceObject -is "Array") {
                    if ($differenceObject -is "Array") {
                        if ((-not $strictComparison) -or ($referenceObject.Count -eq $differenceObject.Count)) {
                            foreach ($refObject in $referenceObject) {
                                $arrayResult = $false;
                                foreach ($diffObject in $differenceObject) {
										$arrayResult = [Helpers]::CompareObject($refObject, $diffObject, $strictComparison);
                                    if ($arrayResult) {
                                        break;
                                    }
                                }

                                $result = $result -and $arrayResult
                                if (-not $arrayResult) {
                                    break;
                                }
                            }
                        }
                        else {
                            $result = $false;
                        }
                    }
                    else {
                        $result = $false;
                    }
                }
                # Condition for all primitive types
                elseif ($referenceObject -is "string" -or $referenceObject -is "ValueType") {
                    # For primitive types, use default comparer
						$result = $result -and (((Compare-Object $referenceObject $differenceObject) | Where-Object { $_.SideIndicator -eq "<=" } | Measure-Object).Count -eq 0)
					
                }
                else {
						$result = $result -and [Helpers]::CompareObjectProperties($referenceObject, $differenceObject, $strictComparison)  
                }
            }
            else {
                $result = $false;
            }
        }
        elseif ($null -eq $differenceObject) {
            $result = $true;
        }
        else {
            $result = $false;
        }

        return $result;
    }

    hidden static [bool] CompareObjectProperties($referenceObject, $differenceObject, [bool] $strictComparison) {
        $result = $true;
        $refProps = @();
        $diffProps = @();
        $refProps += [Helpers]::GetProperties($referenceObject);
        $diffProps += [Helpers]::GetProperties($differenceObject);

        if ((-not $strictComparison) -or ($refProps.Count -eq $diffProps.Count)) {
            foreach ($propName in $refProps) {
                $refProp = $referenceObject.$propName;

                if (-not [string]::IsNullOrWhiteSpace(($diffProps | Where-Object { $_ -eq $propName } | Select-Object -First 1))) {
                    $compareProp = $differenceObject.$propName;

                    if ($null -ne $refProp) {
                        if ($null -ne $compareProp) {			
								$result = $result -and [Helpers]::CompareObject($refProp, $compareProp, $strictComparison);
                        }
                        else {
                            $result = $result -and $false;
                        }
                    }
                    elseif ($null -eq $compareProp) {
                        $result = $result -and $true;
                    }
                    else {
                        $result = $result -and $false;
                    }
                }
                else {
                    $result = $false;
                }

                if (-not $result) {
                    break;
                }
            }
        }
        else {
            $result = $false;
        }


        return $result;
    }

	static [bool] CompareObject($referenceObject, $differenceObject, [bool] $strictComparison,$AttestComparisionType) {
        $result = $true;

        if ($null -ne $referenceObject) {
            if ($null -ne $differenceObject) {
                if ($referenceObject -is "Array") {
                    if ($differenceObject -is "Array") {
                        if ((-not $strictComparison) -or ($referenceObject.Count -eq $differenceObject.Count)) {
                            foreach ($refObject in $referenceObject) {
                                $arrayResult = $false;
                                foreach ($diffObject in $differenceObject) {
									if($AttestComparisionType -eq [ComparisionType]::NumLesserOrEqual)
									{
										$arrayResult = [Helpers]::CompareObject($refObject, $diffObject, $strictComparison,$AttestComparisionType);
									}
									else
									{
										$arrayResult = [Helpers]::CompareObject($refObject, $diffObject, $strictComparison);
									}
                                    if ($arrayResult) {
                                        break;
                                    }
                                }

                                $result = $result -and $arrayResult
                                if (-not $arrayResult) {
                                    break;
                                }
                            }
                        }
                        else {
                            $result = $false;
                        }
                    }
                    else {
                        $result = $false;
                    }
                }
                # Condition for all primitive types
                elseif ($referenceObject -is "string" -or $referenceObject -is "ValueType") {
                    # For primitive types, use default comparer
					if($AttestComparisionType -eq [ComparisionType]::NumLesserOrEqual)
					{
						$result = $result -and  ($referenceObject -ge $differenceObject)
					}
					else
					{
						$result = $result -and (((Compare-Object $referenceObject $differenceObject) | Where-Object { $_.SideIndicator -eq "<=" } | Measure-Object).Count -eq 0)
					}
                    
                }
                else {
					if($AttestComparisionType -eq [ComparisionType]::NumLesserOrEqual)
					{
						$result = $result -and [Helpers]::CompareObjectProperties($referenceObject, $differenceObject, $strictComparison,$AttestComparisionType)
					}
					else
					{
						$result = $result -and [Helpers]::CompareObjectProperties($referenceObject, $differenceObject, $strictComparison)
					}
                    
                }
            }
            else {
                $result = $false;
            }
        }
        elseif ($null -eq $differenceObject) {
            $result = $true;
        }
        else {
            $result = $false;
        }

        return $result;
    }

    hidden static [bool] CompareObjectProperties($referenceObject, $differenceObject, [bool] $strictComparison,$AttestComparisionType) {
        $result = $true;
        $refProps = @();
        $diffProps = @();
        $refProps += [Helpers]::GetProperties($referenceObject);
        $diffProps += [Helpers]::GetProperties($differenceObject);

        if ((-not $strictComparison) -or ($refProps.Count -eq $diffProps.Count)) {
            foreach ($propName in $refProps) {
                $refProp = $referenceObject.$propName;

                if (-not [string]::IsNullOrWhiteSpace(($diffProps | Where-Object { $_ -eq $propName } | Select-Object -First 1))) {
                    $compareProp = $differenceObject.$propName;

                    if ($null -ne $refProp) {
                        if ($null -ne $compareProp) {
							if($AttestComparisionType -eq [ComparisionType]::NumLesserOrEqual)
							{
								$result = $result -and [Helpers]::CompareObject($refProp, $compareProp, $strictComparison,$AttestComparisionType);
							}
							else
							{
								$result = $result -and [Helpers]::CompareObject($refProp, $compareProp, $strictComparison);
							}
                            
                        }
                        else {
                            $result = $result -and $false;
                        }
                    }
                    elseif ($null -eq $compareProp) {
                        $result = $result -and $true;
                    }
                    else {
                        $result = $result -and $false;
                    }
                }
                else {
                    $result = $false;
                }

                if (-not $result) {
                    break;
                }
            }
        }
        else {
            $result = $false;
        }


        return $result;
    }

    static [string[]] GetProperties($object) {
        $props = @();
		if($object)
		{
			if ($object -is "Hashtable") {
				$object.Keys | ForEach-Object {
					$props += $_;
				};
			}
			else {
				($object | Get-Member -MemberType Properties) |
					ForEach-Object {
					$props += $_.Name;
				};
			}
		}
        return $props;
    }

    static [bool] CompareObjectOld($referenceObject, $differenceObject) {
        $result = $true;

        if ($null -ne $referenceObject) {
            if ($null -ne $differenceObject) {
                ($referenceObject | Get-Member -MemberType Properties) |
                    ForEach-Object {
                    $refProp = $referenceObject."$($_.Name)";

                    if ($differenceObject | Get-Member -Name $_.Name) {
                        $compareProp = $differenceObject."$($_.Name)";

                        if ($null -ne $refProp) {
                            if ($null -ne $compareProp) {
                                if ($refProp.GetType().Name -eq "PSCustomObject") {
                                    $result = $result -and [Helpers]::CompareObjectOld($refProp, $compareProp);
                                }
                                else {
                                    $result = $result -and (((Compare-Object $refProp $compareProp) | Where-Object { $_.SideIndicator -eq "<=" } | Measure-Object).Count -eq 0)
                                }
                            }
                            else {
                                $result = $result -and $false;
                            }
                        }
                        elseif ($null -eq $compareProp) {
                            $result = $result -and $true;
                        }
                        else {
                            $result = $result -and $false;
                        }
                    }
                    else {
                        $result = $false;
                    }
                }
            }
            else {
                $result = $false;
            }
        }
        elseif ($null -eq $differenceObject) {
            $result = $true;
        }
        else {
            $result = $false;
        }

        return $result;
    }

    static [bool] CheckMember([PSObject] $refObject, [string] $memberPath)
	{
		return [Helpers]::CheckMember($refObject, $memberPath, $true);
	}

    static [bool] CheckMember([PSObject] $refObject, [string] $memberPath, [bool] $checkNull)
	{
        [bool]$result = $false;
        if ($refObject) {
            $properties = @();
            $properties += $memberPath.Split(".");

            if ($properties.Count -gt 0) {
                $currentItem = $properties.Get(0);
                if (-not [string]::IsNullOrWhiteSpace($currentItem)) {
                    if ($refObject | Get-Member -Name $currentItem)
					{
						if ($properties.Count -gt 1)
						{
							if($refObject.$currentItem)
							{
								$result = $true;
								$result = $result -and [Helpers]::CheckMember($refObject.$currentItem, [string]::Join(".", $properties[1..($properties.length - 1)]));
							}
						}
						else
						{
							if($checkNull)
							{
								if($refObject.$currentItem)
								{
									$result = $true;
								}
							}
							else
							{
								$result = $true;
							}
						}
                    }
                }
            }
        }
        return $result;
    }

    static [PSObject] SelectMembers([PSObject] $refObject, [string[]] $memberPaths) {
        $result = $null;
        if ($null -ne $refObject) {
            if ($refObject -is "Array") {
                $result = @();
                $refObject | ForEach-Object {
                    $memberValue = [Helpers]::SelectMembers($_, $memberPaths);
                    if ($null -ne $memberValue) {
                        $result += $memberValue;
                    }
                };
            }
            else {
                $processedMemberPaths = @();
                $objectProps = [Helpers]::GetProperties($refObject);
                if ($objectProps.Count -ne 0 -and $null -ne $memberPaths -and $memberPaths.Count -ne 0) {
                    $memberPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                        ForEach-Object {
                        $splitPaths = @();
                        $splitPaths += $_.Split(".");
                        $firstMemberPath = $splitPaths.Get(0);
                        if (-not [string]::IsNullOrWhiteSpace($firstMemberPath) -and $objectProps.Contains($firstMemberPath)) {
                            $pathObject = $processedMemberPaths | Where-Object { $_.MemberPath -eq $firstMemberPath } | Select-Object -First 1;

                            if (-not $pathObject) {
                                $pathObject = @{
                                    MemberPath = $firstMemberPath;
                                    ChildPaths = @();
                                };
                                $processedMemberPaths += $pathObject;
                            }

                            # Count > 1 indicates that it has child path
                            if ($splitPaths.Count -gt 1) {
                                $pathObject.ChildPaths += [string]::Join(".", $splitPaths[1..($splitPaths.length - 1)]);
                            }
                        }
                    };
                }

                if ($processedMemberPaths.Count -ne 0) {
                    $processedMemberPaths | ForEach-Object {
                        $memberValue = $null;

                        if ($_.ChildPaths.Count -eq 0) {
                            $memberValue = $refObject."$($_.MemberPath)";
                        }
                        else {
                            $memberValue = [Helpers]::SelectMembers($refObject."$($_.MemberPath)", $_.ChildPaths);
                        }

                        if ($null -ne $memberValue) {
                            if ($null -eq $result) {
                                $result = New-Object PSObject;
                            }

                            $result | Add-Member -MemberType NoteProperty -Name ($_.MemberPath) -Value $memberValue;
                        }
                    };
                }
                else {
                    $result = $refObject;
                }
            }
        }

        return $result;
    }
    
    static [string] FetchTagsString([PSObject]$TagsHashTable)
    {
        [string] $tagsString = "";
        try {
            if(($TagsHashTable | Measure-Object).Count -gt 0)
            {
                $TagsHashTable.Keys | ForEach-Object {
                    $key = $_;
                    $value = $TagsHashTable[$key];
                    $tagsString = $tagsString + "$($key):$($value);";                
                }
            }   
        }
        catch {
            #eat exception as if not able to fetch tags, it would return empty instead of breaking the flow
        }        
        return $tagsString;
    }

    static [string] ComputeHash([String] $data) {
        $HashValue = [System.Text.StringBuilder]::new()
        [System.Security.Cryptography.HashAlgorithm]::Create("SHA256").ComputeHash([System.Text.Encoding]::UTF8.GetBytes($data))| ForEach-Object {
            [void]$HashValue.Append($_.ToString("x"))
        }
        return $HashValue.ToString()
    }

    static [VerificationResult] EvaluateVerificationResult([VerificationResult] $verificationResult, [AttestationStatus] $attestationStatus) {
        [VerificationResult] $result = $verificationResult;
        # No action required if Attestation status is None OR verification result is Passed
        if ($attestationStatus -ne [AttestationStatus]::None -or $verificationResult -ne [VerificationResult]::Passed) {
            # Changing State Machine logic
            #if($verificationResult -eq [VerificationResult]::Verify -or $verificationResult -eq [VerificationResult]::Manual)
            #{
            switch ($attestationStatus) {
                ([AttestationStatus]::NotAnIssue) {
                    $result = [VerificationResult]::Passed;
                    break;
                }               
				([AttestationStatus]::WillNotFix) {
                    $result = [VerificationResult]::Exception;
                    break;
                }
				([AttestationStatus]::WillFixLater) {
                    $result = [VerificationResult]::Remediate;
                    break;
                }
				([AttestationStatus]::NotApplicable) {
                    $result = [VerificationResult]::Passed;
                    break;
                }
                ([AttestationStatus]::StateConfirmed) {
                    $result = [VerificationResult]::Passed;
                    break;
                }
            }
            #}
            #elseif($verificationResult -eq [VerificationResult]::Failed -or $verificationResult -eq [VerificationResult]::Error)
            #{
            #	$result = [VerificationResult]::RiskAck;
            #}
        }
        return $result;
    }

    static [PSObject] NewSecurePassword() {
        #create password
        $randomBytes = New-Object Byte[] 32
        $provider = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
        $provider.GetBytes($randomBytes)
        $provider.Dispose()
        $pwstring = [System.Convert]::ToBase64String($randomBytes)
        $newPassword = new-object securestring
        $pwstring.ToCharArray() | ForEach-Object {
            $newPassword.AppendChar($_)
        }
		$encryptedPassword = ConvertFrom-SecureString -SecureString $newPassword -Key (1..16)
		$securePassword = ConvertTo-SecureString -String $encryptedPassword -Key (1..16)
		return $securePassword
	}

	static [PSObject] DeepCopy([PSObject] $inputObject)
	{
		$memoryStream = New-Object System.IO.MemoryStream
		$binaryFormatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
		$binaryFormatter.Serialize($memoryStream, $inputObject)
		$memoryStream.Position = 0
		$dataDeep = $binaryFormatter.Deserialize($memoryStream)
		$memoryStream.Close()
		return $dataDeep 
	}



	static [bool] ValidateEmail([string]$address){
		$validAddress = ($address -as [System.Net.Mail.MailAddress])
		return ($null -ne $validAddress -and  $validAddress.Address -eq $address )
	}

	#Returns invalid email list
	static [string[]] ValidateEmailList([string[]]$emailList )
	{
		$invalidEmails = @();
		   $emailList | ForEach-Object {
			if(-not [Helpers]::ValidateEmail($_))
			{
				$invalidEmails += $_
			}
		}
		return $invalidEmails
    }
    
    static [Object] MergeObjects([Object] $source,[Object] $extend, [string] $idName)
	{
        $idPropName = "Id";
        if(-not [string]::IsNullOrWhiteSpace($idName))
        {
            $idPropName = $idName;
        }
		if($source.GetType().Name -eq "PSCustomObject" -and $extend.GetType().Name -eq "PSCustomObject"){
			foreach($Property in $extend | Get-Member -type NoteProperty, Property){
				if(-not [Helpers]::CheckMember($source,$Property.Name,$false)){
				  $source | Add-Member -MemberType NoteProperty -Value $extend.$($Property.Name) -Name $Property.Name `
				}
				$source.$($Property.Name) = [Helpers]::MergeObjects($source.$($Property.Name), $extend.$($Property.Name), $idName)
			}
		}
		elseif($source.GetType().Name -eq "Object[]" -and $extend.GetType().Name -eq "Object[]"){
			if([Helpers]::IsPSObjectArray($source) -or [Helpers]::IsPSObjectArray($extend))
			{
			   foreach($extendArrElement in $extend)  {
                     $PropertyId = $extendArrElement | Get-Member -type NoteProperty, Property | Where-Object { $_.Name -eq $idPropName}  | Select-Object -First 1
                     if(($PropertyId | Measure-Object).Count -gt 0)
                     {
                         $PropertyId = $PropertyId | Select-Object -First 1
                     }
                     else {
                        $PropertyId = $extendArrElement | Get-Member -type NoteProperty, Property | Select-Object -First 1
                     }                     
					 $sourceElement = $source | Where-Object { $_.$($PropertyId.Name) -eq $extendArrElement.$($PropertyId.Name) }   
					 if($sourceElement)
					 {                    
                        $sourceElement =  [Helpers]::MergeObjects($sourceElement, $extendArrElement, $idName)
					 }
					 else
					 {
						$source +=$extendArrElement
					 }                 
				}
			}
			else
			{
				$source = ($source + $extend)  | Select-Object -Unique  
			}
		}
		else{
		   $source = $extend;
		}
		return $source
	}


	static [Object] MergeObjects([Object] $source,[Object] $extend)
	{
		return [Helpers]::MergeObjects($source,$extend,"");
	}

	static [Bool] IsPSObjectArray($arrayObj)
	{
		if(($arrayObj | Measure-Object).Count -gt 0)
		{
			$firstElement = $arrayObj | Select-Object -First 1
			if($firstElement.GetType().Name -eq "PSCustomObject")
			{
				return $true
			}
			else
			{
				return $false
			}
		}
		else
		{
			return $false
		}
	}

	#BOM replace function 
	static [void] RemoveUtf8BOM([System.IO.FileInfo] $file)
	{
		[Helpers]::SetUtf8Encoding($file);
		if($file)
		{
			$byteBuffer = New-Object System.Byte[] 3
			$reader = $file.OpenRead()
			$bytesRead = $reader.Read($byteBuffer, 0, 3);
			if ($bytesRead -eq 3 -and
				$byteBuffer[0] -eq 239 -and
				$byteBuffer[1] -eq 187 -and
				$byteBuffer[2] -eq 191)
			{
				$tempFile = [System.IO.Path]::GetTempFileName()
				$writer = [System.IO.File]::OpenWrite($tempFile)
				$reader.CopyTo($writer)
				$writer.Dispose()
				$reader.Dispose()
				Move-Item -Path $tempFile -Destination $file.FullName -Force
			}
			else
			{
				$reader.Dispose()
			}
		}
	}

	static [void] SetUtf8Encoding([System.IO.FileInfo] $file)
	{
		if($file)
		{
			$fileContent = Get-Content -Path $file.FullName;
			if($fileContent)
			{
				Out-File -InputObject $fileContent -Force -FilePath $file.FullName -Encoding utf8
			}
		}
	}

	static [void] CleanupLocalFolder($folderPath)
	{
		try
		{
			if(Test-Path $folderPath)
			{
				Remove-Item -Path $folderPath -Recurse -Force -ErrorAction Stop | Out-Null
			}
		}
		catch{
			#this call happens from finally block. Try to clean the files, if it don't happen it would get cleaned in the next attempt
		}	
    }	
   
    static [void] CreateFolderIfNotExist($FolderPath,$MakeFolderEmpty)
    {
        if(-not (Test-Path $FolderPath))
		{
			New-Item -ItemType Directory -Path $FolderPath -ErrorAction Stop | Out-Null
        }
        elseif($MakeFolderEmpty)
        {
            Remove-Item -Path "$FolderPath*" -Force -Recurse
        }
    }

    Static [string] GetSubString($CotentString, $Pattern)
    {
        return  [regex]::match($CotentString, $pattern).Groups[1].Value
    }

    #TODO: Currently this function is specific to Org PolicyHealth Check. Need to make generic
    Static [string] IsStringEmpty($String)
    {
        if([string]::IsNullOrEmpty($String))
        {
            return "Not Available"
        }
        else 
        {
            $String= $String.Split("?")[0]
            return $String
        }
    }

    Static [bool] IsSASTokenUpdateRequired($policyUrl)
	{
        [System.Uri] $validatedUri = $null;
        $IsSASTokenUpdateRequired = $false
        
        if([System.Uri]::TryCreate($policyUrl, [System.UriKind]::Absolute, [ref] $validatedUri) -and $validatedUri.Query.Contains("&se="))
        {
            $pattern = '&se=(.*?)T'
            [DateTime] $expiryDate = Get-Date 
            if([DateTime]::TryParse([Helpers]::GetSubString($($validatedUri.Query),$pattern),[ref] $expiryDate))
            {
               if($expiryDate.AddDays(-[Constants]::SASTokenExpiryReminderInDays) -lt [DateTime]::UtcNow)
               {
                   $IsSASTokenUpdateRequired = $true
               }
            }
        }
        return $IsSASTokenUpdateRequired
    }

    Static [string] GetUriWithUpdatedSASToken($policyUrl, $updateUrl)
	{
        [System.Uri] $validatedUri = $null;
        $UpdatedUrl = $policyUrl

        if([System.Uri]::TryCreate($policyUrl, [System.UriKind]::Absolute, [ref] $validatedUri) -and $validatedUri.Query.Contains("&se=") -and [System.Uri]::TryCreate($policyUrl, [System.UriKind]::Absolute, [ref] $validatedUri))
        {

            $UpdatedUrl = $policyUrl.Split("?")[0] + "?" + $updateUrl.Split("?")[1]

        }
        return $UpdatedUrl
    }

    static [string] CreateSharedKey([string] $StringToSign,[string] $ResourceName,[string] $AccessKey)
	{
        $KeyBytes = [System.Convert]::FromBase64String($AccessKey)
        $HMAC = New-Object System.Security.Cryptography.HMACSHA256
        $HMAC.Key = $KeyBytes
        $UnsignedBytes = [System.Text.Encoding]::UTF8.GetBytes($StringToSign)
        $KeyHash = $HMAC.ComputeHash($UnsignedBytes)
        $SignedString = [System.Convert]::ToBase64String($KeyHash)
        $sharedKey = $ResourceName+":"+$SignedString
        return $sharedKey    	
    }
}

