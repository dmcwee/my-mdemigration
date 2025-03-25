param(
    [switch]$force
)

$moduleName = "my-mdemigration"

if(!(Test-Path -Path .\$moduleName.defaultParameters.json) -or $force) {
    Copy-Item .\$moduleName.defaultParameters.template.json -Destination .\$moduleName.defaultParameters.json -Force
}

if(!(Test-Path -Path .\$moduleName.psm1) -or $force) {
    Copy-Item .\$moduleName.unsigned.psm1 -Destination .\$moduleName.psm1

    $cert = Get-ChildItem -Path Cert:\CurrentUser\My -DnsName $moduleName@davidmcwee.com -ErrorAction SilentlyContinue
    if(($null -eq $tCert) -or ($force)) {
        $cert = New-SelfSignedCertificate -DnsName $moduleName@davidmcwee.com -Type CodeSigning -CertStoreLocation Cert:\CurrentUser\My
        Export-Certificate -Cert $cert -FilePath $moduleName.crt
        Import-Certificate -FilePath .\$moduleName.crt -CertStoreLocation Cert:\CurrentUser\Root
    }

    Set-AuthenticodeSignature .\$moduleName.psm1 -Certificate $cert
}