param(
    [switch]$newCertificate,
    [switch]$force
)

$moduleName = "my-mdemigration"

if(!(Test-Path -Path .\$moduleName.defaultParameters.json) -or $force) {
    Copy-Item .\$moduleName.defaultParameters.template.json -Destination .\$moduleName.defaultParameters.json
}

Copy-Item .\$moduleName.unsigned.psm1 -Destination .\$moduleName.psm1

$dnsName = "$moduleName@davidmcwee.com"
$crtName = "$moduleName.crt"
$cert = Get-ChildItem -Path Cert:\CurrentUser\My -DnsName $dnsName -ErrorAction SilentlyContinue

if(($null -eq $cert) -or ($newCertificate)) {    
    $cert = New-SelfSignedCertificate -DnsName $dnsName -Type CodeSigning -CertStoreLocation Cert:\CurrentUser\My
    Export-Certificate -Cert $cert -FilePath $crtName
    Import-Certificate -FilePath $crtName -CertStoreLocation Cert:\CurrentUser\Root
}

Set-AuthenticodeSignature .\$moduleName.psm1 -Certificate $cert