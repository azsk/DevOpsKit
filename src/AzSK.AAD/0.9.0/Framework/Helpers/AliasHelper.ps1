[CommandHelper]::Mapping | ForEach-Object {
	$commandName = $_.Verb + '-' + $_.Noun
	$alias = $_.ShortName
	Set-Alias -Name $alias -Value $commandName -ErrorAction SilentlyContinue
	Export-ModuleMember -Alias $alias -Function $commandName
}
Export-ModuleMember -Alias "*AzSK*" -Function "*"
