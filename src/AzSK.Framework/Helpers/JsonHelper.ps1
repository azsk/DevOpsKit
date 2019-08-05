using namespace Newtonsoft.Json
Set-StrictMode -Version Latest
class JsonHelper {
    static [JsonSerializerSettings] $SerializerSettings = $null;

    hidden static [JsonSerializerSettings] GetSerializerSettings() {
        if (-not [JsonHelper]::SerializerSettings) {
            $settings = [JsonSerializerSettings]::new();
            $settings.Converters.Add([Converters.StringEnumConverter]::new());
            $settings.Formatting = [Formatting]::Indented;
            $settings.NullValueHandling = [NullValueHandling]::Ignore;
            $settings.ReferenceLoopHandling = [ReferenceLoopHandling]::Ignore;
            [JsonHelper]::SerializerSettings = $settings;
        }
        return [JsonHelper]::SerializerSettings;
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
                return [JsonConvert]::SerializeObject($list, [JsonHelper]::GetSerializerSettings());
            }

            return [JsonConvert]::SerializeObject($dataObject, [JsonHelper]::GetSerializerSettings());
        }
        return "";
    }

    static [string] ConvertToJsonCustom([PSObject] $Object, [Int]$Depth, [Int]$Layers) {
        Set-StrictMode -Off
        $res = [JsonHelper]::ConvertToJsonCustomNotStrict($Object, $Depth, $Layers, $false)
        Set-StrictMode -Version Latest
        return $res
    }

    static [string] ConvertToJsonCustom([PSObject] $Object) {
       return [JsonHelper]::ConvertToJsonCustom($Object, 10, 10);
    }

    static [string] ConvertToJsonCustomCompressed([PSObject] $Object) {
        Set-StrictMode -Off
        $res = [JsonHelper]::ConvertToJsonCustomNotStrict($Object, 10, 0, $false)
        Set-StrictMode -Version Latest
        return $res
    }

    static [string] ConvertToPson([PSObject] $Object) {
        Set-StrictMode -Off
        $res = [JsonHelper]::ConvertToPsonNotStrict($Object, 10, 10, $false, $false, (Get-Variable -Name PSVersionTable).Value.PSVersion)
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
                        [JsonHelper]::ConvertToJsonCustomNotStrict($Object[$i], $Depth - 1, $Layers - 1, $IsWind)
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
                        $Quote + $_.Key + $Quote + "$Space`:$Space" + ([JsonHelper]::ConvertToJsonCustomNotStrict($_.Value, $Depth - 1, $Layers - 1, $IsWind))
                    }
                }
            }
            ElseIf ($Object -is 'System.Collections.IList') {
                $Format = "[", ",$Space", "]"
                If ($Depth -gt 1) {
                    $Object | ForEach-Object {
                        [JsonHelper]::ConvertToJsonCustomNotStrict($_, $Depth - 1, $Layers - 1, $IsWind)
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
                        $Quote + $_.Name + $Quote + "$Space`:$Space" + ([JsonHelper]::ConvertToJsonCustomNotStrict($Object.$($_.Name), $Depth - 1, $Layers - 1, $IsWind))
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
                        [JsonHelper]::ConvertToPsonNotStrict($Object[$i], $Depth - 1, $Layers - 1, $IsWind, $Strict, $Version)
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
                        $Quote + $_.Key + $Quote + "$Space=$Space" + ([JsonHelper]::ConvertToPsonNotStrict($_.Value, $Depth - 1, $Layers - 1, $IsWind, $Strict, $Version))
                    }
                }
            }
            ElseIf ($Object -is 'System.Collections.IList') {
                $Format = "@(", ",$Space", ")"
                If ($Depth -gt 1) {
                    $Object | ForEach-Object {
                        [JsonHelper]::ConvertToPsonNotStrict($_, $Depth - 1, $Layers - 1, $IsWind, $Strict, $Version)
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
                        $Quote + $_.Name + $Quote + "$Space=$Space" + ([JsonHelper]::ConvertToPsonNotStrict($Object.$($_.Name), $Depth - 1, $Layers - 1, $IsWind, $Strict, $Version))
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

}