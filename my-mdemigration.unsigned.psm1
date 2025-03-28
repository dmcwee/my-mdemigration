function Import-MyDefaultParameters {
    param(
        [string]$ParamFile
    )

    if (Test-Path $ParamFile) {
        Write-Debug "Import-MyDefaultParameters file $ParamFile is valid and being imported"
        $json = Read-JsonFile -FilePath $ParamFile

        $counter = 0
        $json.defaultParameters | ForEach-Object {
            $key = $_.function + ":" + $_.variable
            Write-Debug "Adding $key=$($_.value) to PSDefaultParameterValues."

            $PSDefaultParameterValues[$key] = $_.value
            $counter = $counter +1
        }
        Write-Debug "Added $counter default parameters"
    } else {
        Write-Error "File $ParamFile does not exist."
    }
}

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
        [string]$ClientId = "",
        [string]$TenantId = "",
        [ValidateSet("Mac","Linux","Windows")][string]$OsFamily,
        [ValidateSet("Directory","Process","FileExt")][string]$ExclusionType
    )

    if($PSBoundParameters['Debug']) {
        Write-Debug "Changing DebugPreference from $DebugPreference to 'Continue'"
        $DebugPreference = 'Continue'
    }

    $policy = New-MyMdeExclusions -ExclusionFile $ExclusionFile -PolicyName $PolicyName -PolicyDescription $PolicyDescription -OsFamily $OsFamily -ExclusionType $ExclusionType
    $body = $policy | ConvertTo-Json -Depth 12 -Compress
    Write-Debug "*** START BODY ***"
    Write-Debug "$body"
    Write-Debug "*** END BODY ***"

    if($PSBoundParameters['Debug']) {
        Write-JsonFile -PolicyObject $policy
    }

    Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Scopes DeviceManagementConfiguration.ReadWrite.All -NoWelcome
    Invoke-MgGraphRequest -Method POST -Uri https://graph.microsoft.com/beta/deviceManagement/configurationPolicies -Body $body -ContentType "application/json"
}

function Import-MyMdeCsvExclusions {
    param(
        [Parameter(Mandatory=$true)][string]$CsvFile,
        [Parameter(Mandatory=$true)][string]$PolicyName,
        [string]$PolicyDescription = "",
        [string]$ClientId = "",
        [string]$TenantId = "",
        [ValidateSet("Mac","Linux","Windows")][string]$OsFamily
    )

    if($PSBoundParameters['Debug']) {
        Write-Debug "Changing DebugPreference from $DebugPreference to 'Continue'"
        $DebugPreference = 'Continue'
    }

    if (Test-Path $CsvFile) {
        $csvContent = Import-Csv -Path $CsvFile
        $policy = New-MyBasePolicy -PolicyName $PolicyName -PolicyDescription $PolicyDescription -OsFamily $OsFamily

        foreach ($row in $csvContent) {
            $exclusionText = $row.Exclusion
            $exclusionType = $row.ExclusionType
            Write-Debug "Adding a $exclusionType with value $exclusionText"

            $exclusion = New-MyExclusionSetting -ExclusionValue $exclusionText -ExclusionType $exclusionType -OsFamily $OsFamily
            if($OsFamily -eq "Windows") {
                Write-Debug "Searching for setting in policy"
                $matchingSettingInstance = $policy.settings | Where-Object {
                    $_.settingInstance.settingDefinitionId -eq $exclusion.settingInstance.settingDefinitionId
                }

                if($null -eq $matchingSettingInstance) {
                    Write-Debug "No settingInstance found for $($exclusion.settingInstance.settingDefinitionId)"
                    $policy.settings += $exclusion
                }
                else {
                    Write-Debug "Adding $($exclusion.value.value) to the simpleSettingCollectionValue"
                    $matchingSettingInstance.settingInstance.simpleSettingCollectionValue += $exclusion.settingInstance.simpleSettingCollectionValue[0];
                }
                
            } else {
                $policy.settings[0].settingInstance.groupSettingCollectionValue += $exclusion
            }
        }

        $body = $policy | ConvertTo-Json -Depth 12 -Compress
        Write-Debug "*** START BODY ***"
        Write-Debug "$body"
        Write-Debug "*** END BODY ***"

        if($PSBoundParameters['Debug']) {
            Write-JsonFile -PolicyObject $policy
        }

        Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Scopes DeviceManagementConfiguration.ReadWrite.All
        Invoke-MgGraphRequest -Method POST -Uri https://graph.microsoft.com/beta/deviceManagement/configurationPolicies -Body $body -ContentType "application/json"
    } else {
        Write-Error "CSV file not found: $CsvFile"
    }
}

function New-MyBasePolicy {
    param(
        [Parameter(Mandatory=$true)][string]$PolicyName,
        [string]$PolicyDescription = "",
        [ValidateSet("Mac","Linux","Windows")][string]$OsFamily = "Windows"
    )

    $policy = Get-Policy $OsFamily -FileName "Exclusions\BasePolicy.json"
    $policy.name = $PolicyName
    $policy.description = $PolicyDescription

    return $policy
}

function New-MyExclusionSetting {
    param(
        [Parameter(Mandatory=$true)][string]$ExclusionValue,
        [ValidateSet("Directory","File","FileExt","Process")][string]$ExclusionType = "Directory",
        [ValidateSet("Mac","Linux","Windows")][string]$OsFamily = "Windows"
    )

    #https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates('8a17a1e5-3df4-4e07-9d20-3878267a79b8_1')/settingTemplates?$expand=settingDefinitions&top=1000

    $exclusionTemplates = Get-Policy $OsFamily -FileName "Exclusions\ExclusionPolicies.json"
    $exclusion = $exclusionTemplates.$ExclusionType

    if($OsFamily -eq "Windows") {
        $exclusion.settingInstance.simpleSettingCollectionValue[0].value = $ExclusionValue
    } else {
        if($ExclusionType -eq "Directory" -or $ExclusionType -eq "File") {
            Write-Debug "Updating a directory exclusion value with $ExclusionValue"
            $exclusion.children[0].choiceSettingValue.children[1].simpleSettingValue.value = $ExclusionValue
        } else {
            Write-Debug "Updating a fileExt or Process exclusion value with $ExclusionValue"
            $exclusion.children[0].choiceSettingValue.children[0].simpleSettingValue.value = $ExclusionValue
        }
    }

    return $exclusion
}

function New-MyMdeExclusions {
    param(
        [Parameter(Mandatory=$true)][string]$ExclusionFile,
        [Parameter(Mandatory=$true)][string]$PolicyName,
        [string]$PolicyDescription = "",
        [ValidateSet("Mac","Linux","Windows")][string]$OsFamily = "Windows",
        [ValidateSet("Directory","File","FileExt","Process")][string]$ExclusionType = "Directory"
    )

    $policy = New-MyBasePolicy -PolicyName $PolicyName -PolicyDescription $PolicyDescription -OsFamily $OsFamily

    $exclusionTemplates = Get-Policy $OsFamily -FileName "Exclusions\ExclusionPolicies.json"

    if (Test-Path $ExclusionFile) {
        Get-Content $ExclusionFile | ForEach-Object { 
            Write-Debug "Exclusion Line: $_"
            $exclusion = $exclusionTemplates.$ExclusionType
            $str = $($_).ToString()

            if($OsFamily -eq "Windows") {
                $exclusion.settingInstance.simpleSettingCollectionValue[0].value = $str
                $policy.settings += $exclusion
            } else {
                if($ExclusionType -eq "Directory" -or $ExclusionType -eq "File") {
                    Write-Debug "Updating a directory exclusion value with $str"
                        $exclusion.children[0].choiceSettingValue.children[1].simpleSettingValue.value = $str
                } else {
                    Write-Debug "Updating a fileExt or Process exclusion value with $str"
                    $exclusion.children[0].choiceSettingValue.children[0].simpleSettingValue.value = $str
                }

                Write-Debug "Adding exclusion to groupSettingsCollectionValue $($policy.settings[0].settingInstance.groupSettingCollectionValue.Count)"
                $policy.settings[0].settingInstance.groupSettingCollectionValue += $exclusion
                Write-Debug "Exclusion was added to groupSettingsCollectionValue $($policy.settings[0].settingInstance.groupSettingCollectionValue.Count)"
            }
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

$mPath = (Get-Module -Name My-MdeMigration).path
$jPath = $mPath.Replace("My-MdeMigration.psm1", "my-mdemigration.defaultParameters.json")
$json = (Get-Content $jPath -raw -ErrorAction SilentlyContinue) | ConvertFrom-Json

Import-MyDefaultParameters -ParamFile $jPath