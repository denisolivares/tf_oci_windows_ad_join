#ps1_sysnative

# Template variables
$user = '${instance_user}'
$password = "Trov@dor3nses" # '${instance_password}'
$computerName = '${instance_name}'

#Denis
$LogFile = 'c:\instance_ps1_log.log'

# Log function
function Log($message) {
    $ldt = get-date -f "yyyy-MM-dd hh:mm:ss,fff"
    "$ldt - $message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

Log "Changing $user password"
net user $user $password
Log "Changed $user password"

Write-Output "Configuring WinRM"
# Allow unencrypted if you wish to use http 5985 endpoint
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# Create a self-signed certificate to configure WinRM for HTTPS
$cert = New-SelfSignedCertificate -CertStoreLocation 'Cert:\LocalMachine\My' -DnsName $computerName
Write-Output "Self-signed SSL certificate generated with details: $cert"

$valueSet = @{
    Hostname = $computerName
    CertificateThumbprint = $cert.Thumbprint
}

$selectorSet = @{
    Transport = "HTTPS"
    Address = "*"
}

# Remove any prior HTTPS listener
$listeners = Get-ChildItem WSMan:\localhost\Listener
If (!($listeners | Where {$_.Keys -like "TRANSPORT=HTTPS"}))
{
    Remove-WSManInstance -ResourceURI 'winrm/config/Listener' -SelectorSet $selectorSet
}

Write-Output "Enabling HTTPS listener"
New-WSManInstance -ResourceURI 'winrm/config/Listener' -SelectorSet $selectorSet -ValueSet $valueSet
Write-Output "Enabled HTTPS listener"

Write-Output "Configured WinRM"
Log "Configured WinRM"
Log "############ End Of cloudinit.ps1 ############"