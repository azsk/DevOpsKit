try
{
	Write-Host "Starting the auto-update process..." -ForegroundColor Cyan
	Get-Process | Where-Object { ($_.Name -eq 'powershell' -or $_.Name -eq 'powershell_ise' -or $_.Name -eq 'powershelltoolsprocesshost') -and $_.Id -ne $PID} | Stop-Process 
	##installurl##
	Write-Host "Completed the auto-update process successfully!" -ForegroundColor Green
}
catch
{
	Write-Host "There was an error during the auto-update process. Please update manually by running '##installurl##' " -ForegroundColor Red
	Write-Host "DetailedError:`n $_"
}
finally
{
	$option = Read-Host "Press [Enter] to close this session..."
}
#exit



