using namespace Newtonsoft.Json
using namespace Microsoft.Azure.Commands.Common.Authentication.Abstractions
using namespace Microsoft.Azure.Commands.Common.Authentication
using namespace Microsoft.Azure.Management.Storage.Models
Set-StrictMode -Version Latest
class Helpers {

	static hidden [PSObject] $currentRMContext;

	hidden static [PSObject] GetCurrentRMContext()
	{
		if (-not [Helpers]::currentRMContext)
		{
			$rmContext = Get-AzureRmContext -ErrorAction Stop

			if ((-not $rmContext) -or ($rmContext -and (-not $rmContext.Subscription -or -not $rmContext.Account))) {
				[EventBase]::PublishGenericCustomMessage("No active Azure login session found. Initiating login flow...", [MessageType]::Warning);

				$rmLogin = Connect-AzureRmAccount
				if ($rmLogin) {
					$rmContext = $rmLogin.Context;
				}
			}

			[Helpers]::currentRMContext = $rmContext
		}

		return [Helpers]::currentRMContext
	}

	hidden static [void] ResetCurrentRMContext()
	{
		[Helpers]::currentRMContext = $null
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
                        #$msg = [Helpers]::ConvertToJsonCustom($dataObject);
                        $msg = [Helpers]::ConvertToPson($dataObject);
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

    static [JsonSerializerSettings] $SerializerSettings = $null;
    hidden static [JsonSerializerSettings] GetSerializerSettings() {
        if (-not [Helpers]::SerializerSettings) {
            $settings = [JsonSerializerSettings]::new();
            $settings.Converters.Add([Converters.StringEnumConverter]::new());
            $settings.Formatting = [Formatting]::Indented;
            $settings.NullValueHandling = [NullValueHandling]::Ignore;
            $settings.ReferenceLoopHandling = [ReferenceLoopHandling]::Ignore;
            [Helpers]::SerializerSettings = $settings;
        }
        return [Helpers]::SerializerSettings;
    }

    static [string] ConvertToJson([PSObject] $dataObject) {
        if ($dataObject) {
            if ($dataObject.GetType() -eq [System.Object[]] -and $dataObject.Count -ne 0) {
                $list = New-Object -TypeName "System.Collections.Generic.List[$($dataObject[0].GetType().fullname)]";
                $dataObject | ForEach-Object {
                    if ($_) {
                        $list.Add($_);
                    }
                }
                return [JsonConvert]::SerializeObject($list, [Helpers]::GetSerializerSettings());
            }

            return [JsonConvert]::SerializeObject($dataObject, [Helpers]::GetSerializerSettings());
        }
        return "";
    }

	static [string] ConvertToJsonCustom([PSObject] $Object, [Int]$Depth, [Int]$Layers) {
        Set-StrictMode -Off
        $res = [Helpers]::ConvertToJsonCustomNotStrict($Object, $Depth, $Layers, $false)
        Set-StrictMode -Version Latest
        return $res
    }

    static [string] ConvertToJsonCustom([PSObject] $Object) {
       return [Helpers]::ConvertToJsonCustom($Object, 10, 10);
    }

    static [string] ConvertToJsonCustomCompressed([PSObject] $Object) {
        Set-StrictMode -Off
        $res = [Helpers]::ConvertToJsonCustomNotStrict($Object, 10, 0, $false)
        Set-StrictMode -Version Latest
        return $res
    }

    static [string] ConvertToPson([PSObject] $Object) {
        Set-StrictMode -Off
        $res = [Helpers]::ConvertToPsonNotStrict($Object, 10, 10, $false, $false, (Get-Variable -Name PSVersionTable).Value.PSVersion)
        Set-StrictMode -Version Latest
        return $res
    }

    static [string] ConvertToJsonCustomNotStrict([PSObject] $Object, [Int]$Depth, [Int]$Layers, [bool]$IsWind) {
        $Format = $Null
        $Quote = If ($Depth -le 0) {""}
        Else {""""}
        $Space = If ($Layers -le 0) {""}
        Else {" "}
        If ($null-eq $Object) { return "null"}
        Else {
            $JSON = If ($Object -is "Array") {
                $Format = "[", ",$Space", "]"
                If ($Depth -gt 1) {
                    For ($i = 0; $i -lt $Object.Count; $i++) {
                        [Helpers]::ConvertToJsonCustomNotStrict($Object[$i], $Depth - 1, $Layers - 1, $IsWind)
                    }
                }
            }
            ElseIf ($Object -is "Xml") {
                $String = New-Object System.IO.StringWriter
                $Object.Save($String)
                $Xml = "'" + ([String]$String).Replace("`'", "&apos;") + "'"
                If ($Layers -le 0) {
                    ($Xml -Replace "\r\n\s*", "") -Replace "\s+", " "
                }
                ElseIf ($Layers -eq 1) {
                    $Xml
                }
                Else {
                    $Xml.Replace("`r`n", "`r`n    ")
                }
                $String.Dispose()
            }
            ElseIf ($Object -is "Enum") {
                "$Quote$($Object.ToString())$Quote"
            }
            ElseIf ($Object -is "DateTime") {
                "$Quote$($Object.ToString("o"))$Quote"
            }
            ElseIf ($Object -is "TimeSpan") {
                "$Quote$($Object.ToString())$Quote"
            }
            ElseIf ($Object -is "String") {
                $Object = ConvertTo-Json $Object -Depth 1
                "$Object"
            }
            ElseIf ($Object -is "Boolean") {
                If ($Object) {"true"}
                Else {"false"}
            }
            ElseIf ($Object -is "Char") {
                "$Quote$Object$Quote"
            }
            ElseIf ($Object -is "guid") {
                "$Quote$Object$Quote"
            }
            ElseIf ($Object -is "ValueType") {
                $Object
            }
            ElseIf ($Object -is [System.Collections.IDictionary]) {
                If ($null -eq $Object.Keys) {
                    return "null"
                }
                $Format = "{", ",$Space", "}"
                If ($Depth -gt 1) {
                    $Object.GetEnumerator() | ForEach-Object {
                        $Quote + $_.Key + $Quote + "$Space`:$Space" + ([Helpers]::ConvertToJsonCustomNotStrict($_.Value, $Depth - 1, $Layers - 1, $IsWind))
                    }
                }
            }
            ElseIf ($Object -is 'System.Collections.IList') {
                $Format = "[", ",$Space", "]"
                If ($Depth -gt 1) {
                    $Object | ForEach-Object {
                        [Helpers]::ConvertToJsonCustomNotStrict($_, $Depth - 1, $Layers - 1, $IsWind)
                    }
                }
            }
            ElseIf ($Object -is "Object") {
                If ($Object -is "System.Management.Automation.ErrorRecord" -and !$IsWind) {
                    $Depth = 3
                    $Layers = 3
                    $IsWind = $true
                }
                $Format = "{", ",$Space", "}"
                If ($Depth -gt 1) {
                    Get-Member -InputObject $Object -MemberType Properties | ForEach-Object {
                        $Quote + $_.Name + $Quote + "$Space`:$Space" + ([Helpers]::ConvertToJsonCustomNotStrict($Object.$($_.Name), $Depth - 1, $Layers - 1, $IsWind))
                    }
                }
            }
            Else {$Object}
            If ($Format) {
                $JSON = $Format[0] + (& {
                        If (($Layers -le 1) -or ($JSON.Count -le 0)) {
                            $JSON -Join $Format[1]
                        }
                        Else {
                            ("`r`n" + ($JSON -Join "$($Format[1])`r`n")).Replace("`r`n", "`r`n    ") + "`r`n"
                        }
                    }) + $Format[2]
            }
            return "$JSON"
        }
    }


    # Adapted from https://stackoverflow.com/questions/15139552/save-hash-table-in-powershell-object-notation-pson
    # PSON - PowerShell Object Notation
    static [string] ConvertToPsonNotStrict([PSObject] $Object, [Int]$Depth, [Int]$Layers, [bool]$IsWind, [bool]$Strict, [Version]$Version) {
        $Format = $Null
        $Quote = If ($Depth -le 0) {""}
        Else {""""}
        $Space = If ($Layers -le 0) {""}
        Else {" "}
        If ($null -eq $Object) {
            return "`$Null"
        }
        Else {
            $Type = "[" + $Object.GetType().Name + "]"
            $PSON = If ($Object -is "Array") {
                $Format = "@(", ",$Space", ")"
                If ($Depth -gt 1) {
                    For ($i = 0; $i -lt $Object.Count; $i++) {
                        [Helpers]::ConvertToPsonNotStrict($Object[$i], $Depth - 1, $Layers - 1, $IsWind, $Strict, $Version)
                    }
                }
            }
            ElseIf ($Object -is "Xml") {
                $Type = "[Xml]"
                $String = New-Object System.IO.StringWriter
                $Object.Save($String)
                $Xml = "'" + ([String]$String).Replace("`'", "&apos;") + "'"
                If ($Layers -le 0) {
                    ($Xml -Replace "\r\n\s*", "") -Replace "\s+", " "
                }
                ElseIf ($Layers -eq 1) {
                    $Xml
                }
                Else {
                    $Xml.Replace("`r`n", "`r`n    ")
                }
                $String.Dispose()
            }
            ElseIf ($Object -is "Enum") {
                "$Quote$($Object.ToString())$Quote"
            }
            ElseIf ($Object -is "DateTime") {
                "$Quote$($Object.ToString('s'))$Quote"
            }
            ElseIf ($Object -is "TimeSpan") {
                "$Quote$($Object.ToString())$Quote"
            }
            ElseIf ($Object -is "String") {
                0..11 | ForEach-Object {
                    $Object = $Object.Replace([String]"```'""`0`a`b`f`n`r`t`v`$"[$_], ('`' + '`''"0abfnrtv$'[$_]))}; "$Quote$Object$Quote"
            }
            ElseIf ($Object -is "Boolean") {
                If ($Object) {"`$True"}
                Else {"`$False"}
            }
            ElseIf ($Object -is "Char") {
                If ($Strict) {[Int]$Object}
                Else {"$Quote$Object$Quote"}
            }
            ElseIf ($Object -is "guid") {
                "$Quote$Object$Quote"
            }
            ElseIf ($Object -is "ValueType") {
                $Object
            }
            ElseIf ($Object -is [System.Collections.IDictionary]) {
                If ($null -eq $Object.Keys) {
                    return "`$Null"
                }
                If ($Type -eq "[OrderedDictionary]") {$Type = "[Ordered]"}
                $Format = "@{", ";$Space", "}"
                If ($Depth -gt 1) {
                    $Object.GetEnumerator() | ForEach-Object {
                        $Quote + $_.Key + $Quote + "$Space=$Space" + ([Helpers]::ConvertToPsonNotStrict($_.Value, $Depth - 1, $Layers - 1, $IsWind, $Strict, $Version))
                    }
                }
            }
            ElseIf ($Object -is 'System.Collections.IList') {
                $Format = "@(", ",$Space", ")"
                If ($Depth -gt 1) {
                    $Object | ForEach-Object {
                        [Helpers]::ConvertToPsonNotStrict($_, $Depth - 1, $Layers - 1, $IsWind, $Strict, $Version)
                    }
                }
            }
            ElseIf ($Object -is "Object") {
                If ($Object -is "System.Management.Automation.ErrorRecord" -and !$IsWind) {
                    $Depth = 3
                    $Layers = 3
                    $IsWind = $true
                }
                If ($Version -le [Version]"2.0") {$Type = "New-Object PSObject -Property "}
                $Format = "@{", ";$Space", "}"
                If ($Depth -gt 1) {
                    Get-Member -InputObject $Object -MemberType Properties | ForEach-Object {
                        $Quote + $_.Name + $Quote + "$Space=$Space" + ([Helpers]::ConvertToPsonNotStrict($Object.$($_.Name), $Depth - 1, $Layers - 1, $IsWind, $Strict, $Version))
                    }
                }
            }
            Else {$Object}
            If ($Format) {
                $PSON = $Format[0] + (& {
                        If (($Layers -le 1) -or ($PSON.Count -le 0)) {
                            $PSON -Join $Format[1]
                        }
                        Else {
                            ("`r`n" + ($PSON -Join "$($Format[1])`r`n")).Replace("`r`n", "`r`n    ") + "`r`n"
                        }
                    }) + $Format[2]
            }
            If ($Strict) {
                return "$Type$PSON"
            }
            Else {
                return "$PSON"
            }
        }
    }

    static [string] GetAccessToken([string] $resourceAppIdUri, [string] $tenantId) {
        $rmContext = [Helpers]::GetCurrentRMContext()

        if (-not $rmContext) {
			throw ([SuppressedException]::new(("No Azure login found"), [SuppressedExceptionType]::InvalidOperation))
        }

        if ([string]::IsNullOrEmpty($tenantId) -and [Helpers]::CheckMember($rmContext, "Tenant")) {
            $tenantId = $rmContext.Tenant.Id
        }

        $allEndpoints = @();
        $resourceConstant = [AzureEnvironment+Endpoint] |
            Get-Member -Static -MemberType Properties |
            Where-Object {
            $endpoint = [AzureEnvironmentExtensions]::GetEndpoint($rmContext.Environment, $_.Name)
            $allEndpoints += $endpoint;
            (-not [string]::IsNullOrWhiteSpace($endpoint) -and ($endpoint.Trimend('/') -eq $resourceAppIdUri.Trimend('/')))
        } | Select-Object -First 1

        if (-not $resourceConstant) {
			throw ([SuppressedException]::new(("The resource URL [$resourceAppIdUri] is not supported. Supported values are: " + ($allEndpoints -join ", ")), [SuppressedExceptionType]::InvalidOperation))
        }

        $authResult = [AzureSession]::Instance.AuthenticationFactory.Authenticate(
            $rmContext.Account,
            $rmContext.Environment,
            $tenantId,
            [System.Security.SecureString] $null,
            [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Auto,$null,
            $resourceConstant.Name);

        if (-not ($authResult -and (-not [string]::IsNullOrWhiteSpace($authResult.AccessToken)))) {
			throw ([SuppressedException]::new(("Unable to get access token. Authentication Failed."), [SuppressedExceptionType]::Generic))
        }

        return $authResult.AccessToken;
    }

    static [string] GetAccessToken([string] $resourceAppIdUri) {
        return [Helpers]::GetAccessToken($resourceAppIdUri, "");
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

    static [PSObject] NewAzskCompliantStorage([string]$StorageName, [Kind]$StorageKind,[string]$ResourceGroup,[string]$Location) {
        $storageSku = [Constants]::NewStorageSku
        $storageObject = $null
        try {
            #register resource providers
            [Helpers]::RegisterResourceProviderIfNotRegistered("Microsoft.Storage");
            [Helpers]::RegisterResourceProviderIfNotRegistered("microsoft.insights");

            #create storage
            $status = Get-AzureRmStorageAccountNameAvailability -Name $StorageName
            if($null -ne $status -and  $status.NameAvailable -eq $true)
            {
                $newStorage = New-AzureRmStorageAccount -ResourceGroupName $ResourceGroup `
                    -Name $StorageName `
                    -Type $storageSku `
                    -Location $Location `
                    -Kind $StorageKind `
                    -AccessTier Cool `
                    -EnableHttpsTrafficOnly $true `
                    -ErrorAction Stop

                $retryAccount = 0
                do {
                    $storageObject = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageName -ErrorAction SilentlyContinue
                    Start-Sleep -seconds 2
                    $retryAccount++
                }while (!$storageObject -and $retryAccount -ne 6)

                if ($storageObject) {                                       

                    #set diagnostics on
                    $currentContext = $storageObject.Context
                    Set-AzureStorageServiceLoggingProperty -ServiceType Blob -LoggingOperations All -Context $currentContext -RetentionDays 365 -PassThru -ErrorAction Stop
                    Set-AzureStorageServiceMetricsProperty -MetricsType Hour -ServiceType Blob -Context $currentContext -MetricsLevel ServiceAndApi -RetentionDays 365 -PassThru -ErrorAction Stop
                }
            }
            else
            {
                throw ([SuppressedException]::new(("The specified name for the storage account is not available. Please rerun this command to try a different name."), [SuppressedExceptionType]::Generic));          
            }
        }
        catch {
            [EventBase]::PublishGenericException($_);
            $storageObject = $null
            #clean-up storage if error occurs
            if ((Get-AzureRmResource -ResourceGroupName $ResourceGroup -Name $StorageName|Measure-Object).Count -gt 0) {
                Remove-AzureRmStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageName -Force -ErrorAction SilentlyContinue
            }
        }
        return $storageObject
    }
    static [PSObject] NewAzskCompliantStorage([string]$StorageName, [string]$ResourceGroup, [string]$Location) {
      return [Helpers]::NewAzskCompliantStorage($StorageName,[Constants]::NewStorageKind,[string]$ResourceGroup,[string]$Location)
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

	static [void] SetResourceGroupTags([string]$RGName, [PSObject]$TagsHashTable, [bool] $Remove) {
		[Helpers]::SetResourceGroupTags($RGName, $TagsHashTable, $Remove, $true) 
	}

	static [void] SetResourceGroupTags([string]$RGName, [PSObject]$TagsHashTable, [bool] $Remove, [bool] $update) {
		$azskResourceGroup = Get-AzureRmResourceGroup -Name $RGName -ErrorAction SilentlyContinue;
		if(($azskResourceGroup | Measure-Object).Count -gt 0)
		{
			$tags = $azskResourceGroup.Tags;
			if($null -eq $tags)
			{
				$tags = @{}
			}
			if(($TagsHashTable | Measure-Object).Count -gt 0)
			{
				$TagsHashTable.Keys | ForEach-Object {
					$key = $_;
					if($tags.ContainsKey($key))
					{
						if($update)
						{
							$tags[$key] = $TagsHashTable[$key];
						}
						if($Remove)
						{
							$tags.Remove($key);
						}
					}
					elseif(-not $Remove)
					{
						$tags.Add($key, $TagsHashTable[$key])
					}
				}
			}
			try
			{
				Set-AzureRmResourceGroup -Name $RGName -Tag $tags -ErrorAction Stop
			}
			catch
			{
				[EventBase]::PublishGenericCustomMessage(" `r`nError occured while adding tag(s) on resource group [$RGName]. $($_.Exception)", [MessageType]::Warning);
			}
		}
    }

	static [void] SetResourceTags([string] $ResourceId, [PSObject] $TagsHashTable, [bool] $Remove, [bool] $update) {
		$azskResource = Get-AzureRmResource -ResourceId $ResourceId -ErrorAction SilentlyContinue;
		if(($azskResource | Measure-Object).Count -gt 0)
		{
			$tags = $azskResource.Tags;
			if($null -eq $tags)
			{
				$tags = @{}
			}
			if(($TagsHashTable | Measure-Object).Count -gt 0)
			{
				$TagsHashTable.Keys | ForEach-Object {
					$key = $_;
					if($tags.ContainsKey($key))
					{
						if($update)
						{
							$tags[$key] = $TagsHashTable[$key];
						}
						if($Remove)
						{
							$tags.Remove($key);
						}
					}
					elseif(-not $Remove)
					{
						$tags.Add($key, $TagsHashTable[$key])
					}
				}
			}			
			try
			{
				Set-AzureRmResource -ResourceId $ResourceId -Tag $tags -Force -ErrorAction Stop
			}
			catch
			{
				[EventBase]::PublishGenericCustomMessage(" `r`nError occured while adding tag(s) on resource [$ResourceId]. $($_.Exception)", [MessageType]::Warning);
			}
		}
    }

	static [PSObject] GetResourceGroupTags([string]$RGName)
	{
		$azskResourceGroup = Get-AzureRmResourceGroup -Name $RGName -ErrorAction SilentlyContinue;
		$tags = @{}
		if(($azskResourceGroup | Measure-Object).Count -gt 0)
		{
			$tags = $azskResourceGroup.Tags;
			if($null -eq $tags)
			{
				$tags = @{}
			}
		}
		return $tags 
	}

	static [string] GetResourceGroupTag([string]$RGName, [string] $tagName)
	{
		$azskResourceGroup = Get-AzureRmResourceGroup -Name $RGName -ErrorAction SilentlyContinue;
		$tags = @{}
		if(($azskResourceGroup | Measure-Object).Count -gt 0)
		{
			$tags = $azskResourceGroup.Tags;
			if(($tags | Measure-Object).Count -gt 0)
			{
				return $tags[$tagName];
			}
		}
		return ""; 
	}



    static [bool] NewAzSKResourceGroup([string]$ResourceGroup, [string]$Location, [string] $Version) {
        try {
            [Hashtable] $RGTags = @{};
            if ([string]::IsNullOrWhiteSpace($Version))
			 {
               $version= [Constants]::AzSKCurrentModuleVersion
            }
                $RGTags += @{
                    "AzSKVersion" = $Version;
                    "CreationTime" = $(get-date).ToUniversalTime().ToString("yyyyMMdd_HHmmss");
                }
            
            $newRG = New-AzureRmResourceGroup -Name $ResourceGroup -Location $Location `
                -Tag $RGTags `
                -ErrorAction Stop

            return $true
        }
        catch {
			#return as false in the case of exception. Caller of this function is taking care if the value is false
            return $false
        }

    }

    static [void] CreateNewResourceGroupIfNotExists([string]$ResourceGroup, [string]$Location, [string] $Version) 
    {
       if((Get-AzureRmResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0)
	    {
		    [Helpers]::NewAzSKResourceGroup($ResourceGroup,$Location,$Version)
	    }  
    }

    static [string] ComputeHash([String] $data) {
        $HashValue = [System.Text.StringBuilder]::new()
        [System.Security.Cryptography.HashAlgorithm]::Create("SHA256").ComputeHash([System.Text.Encoding]::UTF8.GetBytes($data))| ForEach-Object {
            [void]$HashValue.Append($_.ToString("x"))
        }
        return $HashValue.ToString()
    }

    static [string] GetCurrentSessionUser() {
        $context = [Helpers]::GetCurrentRMContext()
        if ($null -ne $context) {
            return $context.Account.Id
        }
        else {
            return "NO_ACTIVE_SESSION"
        }
    }
	static [string[]] GetCurrentUserRoleAtSubscriptionScope([string] $SubscriptionId)
	{
		$signInId = [Helpers]::GetCurrentSessionUser()
		#Ignore errors in case user doesn't have subscription scope role/not authorized to perform role assignment read
		$roleAssignments = @();
		#same tenant
		$roleAssignments += Get-AzureRmRoleAssignment -Scope "/subscriptions/$SubscriptionId" -IncludeClassicAdministrators -ErrorAction SilentlyContinue | Where-Object { ($_.SignInName -like '*#EXT#@*.onmicrosoft.com' -and $_.SignInName.Split("#EXT#")[0] -eq ($signInId -replace "@","_")) -or $_.SignInName -eq $signInId }

		$userRoles = @();
		if(($roleAssignments | Measure-Object).Count -gt 0)
		{
			$roleAssignments | ForEach-Object{
				$userRoles += ($_.RoleDefinitionName.Split(";"));
			}
			return $userRoles;
		}
		else
		{
			return $null
		}
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

	static [void] RegisterResourceProviderIfNotRegistered([string] $provideNamespace)
	{
		if([string]::IsNullOrWhiteSpace($provideNamespace))
		{
			throw [System.ArgumentException] "The argument '$provideNamespace' is null or empty";
		}

		# Check if provider is registered or not
		if(-not [Helpers]::IsProviderRegistered($provideNamespace))
		{
			[EventBase]::PublishGenericCustomMessage(" `r`nThe resource provider: [$provideNamespace] is not registered on the subscription. `r`nRegistering resource provider, this can take up to a minute...", [MessageType]::Warning);

			Register-AzureRmResourceProvider -ProviderNamespace $provideNamespace

			$retryCount = 10;
			while($retryCount -ne 0 -and (-not [Helpers]::IsProviderRegistered($provideNamespace)))
			{
				$timeout = 10
				Start-Sleep -Seconds $timeout
				$retryCount--;
				#[EventBase]::PublishGenericCustomMessage("Checking resource provider status every $timeout seconds...");
			}

			if(-not [Helpers]::IsProviderRegistered($provideNamespace))
			{
				throw ([SuppressedException]::new(("Resource provider: [$provideNamespace] registration failed. `r`nTry registering the resource provider from Azure Portal --> your Subscription --> Resource Providers --> $provideNamespace --> Register"), [SuppressedExceptionType]::Generic))
			}
			else
			{
				[EventBase]::PublishGenericCustomMessage("Resource provider: [$provideNamespace] registration successful.`r`n ", [MessageType]::Update);
			}
		}
	}

	hidden static [bool] IsProviderRegistered([string] $provideNamespace)
	{
		return ((Get-AzureRmResourceProvider -ProviderNamespace $provideNamespace | Where-Object { $_.RegistrationState -ne "Registered" } | Measure-Object).Count -eq 0);
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

	static [bool] IsvNetExpressRouteConnected($resourceName, $resourceGroupName)
	{
		$result = $false;
		$gateways = @();
		$gateways += Get-AzureRmVirtualNetworkGateway -ResourceGroupName $resourceGroupName | Where-Object { $_.GatewayType -eq "ExpressRoute" }
		if($gateways.Count -ne 0)
		{
			$vNet = Get-AzureRmVirtualNetwork -Name $resourceName -ResourceGroupName $resourceGroupName 
			if($vnet)
			{
				$subnetIds = @();
				$vnet | ForEach-Object {
					if($_.Subnets)
					{
						$subnetIds += $_.Subnets | Select-Object -Property Id | Select-Object -ExpandProperty Id
					}
				};
            
				if($subnetIds.Count -ne 0)
				{
					$gateways | ForEach-Object {
						$result = $result -or (($_.IpConfigurations | Where-Object { $subnetIds -contains $_.Subnet.Id } | Measure-Object).Count -ne 0);
					};
				}
			}
		}
		return $result; 
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
	static [void] SetSPNPermission($Scope,$ApplicationId,$Role)
	{
		$assignedRole = $null
		$retryCount = 0;
		While($null -eq $assignedRole -and $retryCount -le 6)
		{
			#Assign RBAC to SPN - contributor at RG
			New-AzureRMRoleAssignment -Scope $Scope -RoleDefinitionName $Role -ServicePrincipalName $ApplicationId -ErrorAction SilentlyContinue | Out-Null
			Start-Sleep -Seconds 10
			$assignedRole = Get-AzureRmRoleAssignment -ServicePrincipalName $ApplicationId -Scope $Scope -RoleDefinitionName $Role -ErrorAction SilentlyContinue
			$retryCount++;
		}
		if($null -eq $assignedRole -and $retryCount -gt 6)
		{
			throw ([SuppressedException]::new(("SPN permission could not be set"), [SuppressedExceptionType]::InvalidOperation))
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
   
    static [string] CreateStorageAccountSharedKey([string] $StringToSign,[string] $AccountName,[string] $AccessKey)
	{
        $KeyBytes = [System.Convert]::FromBase64String($AccessKey)
        $HMAC = New-Object System.Security.Cryptography.HMACSHA256
        $HMAC.Key = $KeyBytes
        $UnsignedBytes = [System.Text.Encoding]::UTF8.GetBytes($StringToSign)
        $KeyHash = $HMAC.ComputeHash($UnsignedBytes)
        $SignedString = [System.Convert]::ToBase64String($KeyHash)
        $sharedKey = $AccountName+":"+$SignedString
        return $sharedKey    	
    }

    static [void] CreateFolderIfNotExist($FolderPath,$MakeFolderEmpty)
    {
        if(-not (Test-Path $FolderPath))
		{
			mkdir -Path $FolderPath -ErrorAction Stop | Out-Null
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
}

