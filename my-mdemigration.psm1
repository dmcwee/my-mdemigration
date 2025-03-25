function Get-Policy {
    param(
        [string]$OsFamily,
        [string]$FileName)

    $mPath = (Get-Module -Name my-mdemigration).path
    $jPath = $mPath.Replace("my-mdemigration.psm1", "$OsFamily\$FileName")
    $jsonObject = Read-JsonFile -FilePath $jPath

    return $jsonObject
}

function Import-MyMdeExclusions {
    param(
        [Parameter(Mandatory=$true)][string]$ExclusionFile,
        [Parameter(Mandatory=$true)][string]$PolicyName,
        [string]$PolicyDescription = "",
        [string]$ClientId = "be5c1f31-9107-404f-b377-5c41ec77a124",
        [string]$TenantId = "63cac711-f1e5-4a8d-b1bd-e3d1bfd471a2",
        [ValidateSet("Mac","Linux","Windows")][string]$OsFamily,
        [ValidateSet("Directory","Process","FileExt")][string]$ExclusionType
    )

    if($PSBoundParameters['Debug']) {
        Write-Debug "Changing DebugPreference from $DebugPreference to 'Continue'"
        $DebugPreference = 'Continue'
    }

    $policy = New-MyMdeExclusions -ExclusionFile $ExclusionFile -PolicyName $PolicyName -PolicyDescription $PolicyDescription -OsFamily $OsFamily -ExclusionType $ExclusionType
    $body = $policy | ConvertTo-Json -Depth 12 -Compress
    Write-Debug "*** START BODY ***" -
    Write-Debug "$body"
    Write-Debug "*** END BODY ***"

    if($PSBoundParameters['Debug']) {
        Write-JsonFile -PolicyObject $policy
    }

    Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Scopes DeviceManagementConfiguration.ReadWrite.All
    Invoke-MgGraphRequest -Method POST -Uri https://graph.microsoft.com/beta/deviceManagement/configurationPolicies -Body $body -ContentType "application/json"
}

function New-MyMdeExclusions {
    param(
        [Parameter(Mandatory=$true)][string]$ExclusionFile,
        [Parameter(Mandatory=$true)][string]$PolicyName,
        [string]$PolicyDescription = "",
        [ValidateSet("Mac","Linux","Windows")][string]$OsFamily = "Windows",
        [ValidateSet("Directory","File","FileExt","Process")][string]$ExclusionType = "Directory"
    )

    $policy = Get-Policy $OsFamily -FileName "Exclusions\BasePolicy.json"
    $policy.name = $PolicyName
    $policy.description = $PolicyDescription

    $exclusionTemplates = Get-Policy $OsFamily -FileName "Exclusions\ExclusionPolicies.json"

    if (Test-Path $ExclusionFile) {
        Get-Content $ExclusionFile | ForEach-Object { 
            Write-Debug "Exclusion Line: $_"
            $exclusion = $exclusionTemplates.$ExclusionType
            $str = $($_).ToString()

            if($OsFamily -eq "Windows") {
                $exclusion.settingInstance.simpleSettingCollectionValue[0].value = $str
            } else {
                if($ExclusionType -eq "Directory" -or $ExclusionType -eq "File") {
                    Write-Debug "Updating a directory exclusion value with $str"
                        $exclusion.children[0].choiceSettingValue.children[1].simpleSettingValue.value = $str
                } else {
                    Write-Debug "Updating a fileExt or Process exclusion value with $str"
                    $exclusion.children[0].choiceSettingValue.children[0].simpleSettingValue.value = $str
                }
            }

            Write-Debug "Adding exclusion to groupSettingsCollectionValue $($policy.settings[0].settingInstance.groupSettingCollectionValue.Count)"
            $policy.settings[0].settingInstance.groupSettingCollectionValue += $exclusion
            Write-Debug "Exclusion was added to groupSettingsCollectionValue $($policy.settings[0].settingInstance.groupSettingCollectionValue.Count)"
        }

        return $policy

    } else {
        Write-Error "File not found: $ExclusionFile"
    }
}

function New-MyMdeExclusionsFile {
    param(
        [Parameter(Mandatory=$true)][string]$ExclusionFile,
        [Parameter(Mandatory=$true)][string]$PolicyName,
        [string]$PolicyDescription = "",
        [ValidateSet("Mac","Linux","Windows")][string]$OsFamily = "Windows",
        [ValidateSet("Directory","File","FileExt","Process")][string]$ExclusionType = "Directory"
    )

    if($PSBoundParameters['Debug']) {
        Write-Debug "Changing DebugPreference from $DebugPreference to 'Continue'"
        $DebugPreference = 'Continue'
    }

    $policy = New-MyMdeExclusions -ExclusionFile $ExclusionFile -PolicyName $PolicyName -PolicyDescription $PolicyDescription -OsFamily $OsFamily -ExclusionType $ExclusionType

    Write-JsonFile -PolicyObject $policy
}

function Read-JsonFile {
    param (
        [string]$FilePath
    )
    
    Write-Debug "Request to read file: $FilePath"
    if (Test-Path $FilePath) {
        Write-Debug "File $FilePath exists and will be read."
        $jsonContent = Get-Content $FilePath -Raw
        $jsonObject = $jsonContent | ConvertFrom-Json
        return $jsonObject
    } else {
        Write-Error "JSON file not found: $FilePath"
    }
}

function Write-JsonFile {
    param (
        $PolicyObject
    )

    # Convert the policy object to JSON and write it to a file
    Write-Debug "Converting Policy to JSON object"
    $policyJson = $policy | ConvertTo-Json -Depth 12 -Compress

    $outputFilePath = Join-Path -Path (Get-Location) -ChildPath "$($PolicyObject.name).json"
    $policyJson | Out-File -FilePath $outputFilePath

    Write-Debug "Policy written to $outputFilePath"
}