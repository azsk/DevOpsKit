Set-StrictMode -Version Latest 

class ManagementCertificate
{
	[string] $CertThumbprint
	[string] $SubjectName
	[string] $Issuer
	[PSObject] $Created
	[PSObject] $ExpiryDate
	[string] $IsExpired
	[PSObject] $Difference	
	[bool] $Whitelisted

	hidden static [ManagementCertificate[]] ListManagementCertificates([PSObject] $certObjects)
	{
		[ManagementCertificate[]] $certs = @()
		$certObjects | ForEach-Object{               
							[ManagementCertificate] $certObject = [ManagementCertificate]::new();
							$b64cert = $_.SubscriptionCertificateData                               
                            $certData = [System.Convert]::FromBase64String($b64Cert)                                                                      
                            $certX = [System.Security.Cryptography.X509Certificates.X509Certificate2]($certData)   
                            $certObject.ExpiryDate = $certX.NotAfter.ToString("yyyy-MM-dd HH:mm:ss")
                            $certObject.CertThumbprint = $_.SubscriptionCertificateThumbprint
                            $certObject.SubjectName = $certX.Subject
                            $certObject.Issuer = $certX.Issuer
                            $certObject.Created = $_.Created
                            $certObject.IsExpired = "False"
                            $certObject.Difference = New-TimeSpan -Start ([datetime]$certX.NotBefore) -End ([datetime]$certX.NotAfter)
                            if([System.DateTime]::UtcNow -ge $certX.NotAfter)
                            {
                                $certObject.IsExpired = "True"
                            }
							#Has to be moved to new configuration model
							$certObject.Whitelisted = $false							
                            $certs += $certObject
                        }
		return $certs;
	}
}