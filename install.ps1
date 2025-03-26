param(
    [switch]$force
)

$moduleName = "my-mdemigration"

if(!(Test-Path -Path .\$moduleName.defaultParameters.json) -or $force) {
    Copy-Item .\$moduleName.defaultParameters.template.json -Destination .\$moduleName.defaultParameters.json -Force
}

if(!(Test-Path -Path .\$moduleName.psm1) -or $force) {
    Copy-Item .\$moduleName.unsigned.psm1 -Destination .\$moduleName.psm1

    $dnsName = "$moduleName@davidmcwee.com"
    $cert = Get-ChildItem -Path Cert:\CurrentUser\My -DnsName $dnsName -ErrorAction SilentlyContinue
    if(($null -eq $cert) -or ($force)) {
        $crtName = "$moduleName.crt"
        $cert = New-SelfSignedCertificate -DnsName $dnsName -Type CodeSigning -CertStoreLocation Cert:\CurrentUser\My
        Export-Certificate -Cert $cert -FilePath $crtName
        Import-Certificate -FilePath $crtName -CertStoreLocation Cert:\CurrentUser\Root
    }

    Set-AuthenticodeSignature .\$moduleName.psm1 -Certificate $cert
}