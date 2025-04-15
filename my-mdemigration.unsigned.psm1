<#
 .Synopsis
 Internal function that accepts the string to check against a group of exclusions

 .Description
 Internal function that accepts the string to check against a group of exclusions

 .Parameter ExclusionGroups
 This object contains groups of MDE's default exclusion regular expressions to determine if InputString 
 would be covered by the MDE Default exclusions.

 .Parameter InputString
 This should be a path to check against the default MDE exclusion folders, processes, and file extensions.

#>
function Get-MyMatchingExclusionGroup {
    param(
        $ExclusionGroups,
        [Parameter(Mandatory=$true)][string]$InputString,
        [switch]$ReturnWarning
    )

    foreach ($group in $ExclusionGroups) {
        foreach ($regex in $group.paths) {
            if ($InputString -match $regex) {
                Write-Debug "Match found in group: $($group.name)"
                return $group.name
            }
        }

        foreach ($regex in $group.warn) {
            if($InputString -match $regex) {
                if($returnWarning) {
                    return $group.name
                } else {
                    Write-Warning "The exclusion '$InputString' is not part of the default exclusions but may not be recommended."
                }
            }
        }
    }

    # If no match is found, return null
    return $null
}

<#
 .Synopsis
 Internal Function to generate a path to files installed with the module

 .Description
 Internal Function to generate a path to files installed with the module

 .Parameter Path
 Function to consistently generate a path to a file held in the module's install location

#>
function Get-ModuleFilePath {
    param(
        [string]$Path
    )

    $mPath = (Get-Module -Name my-mdemigration).path
    $fPath = $mPath.Replace("my-mdemigration.psm1", "$Path")

    return $fPath
}

<#
 .Synopsis
 Internal Function - Read the Base or ExclusionPolicies JSON files deployed with the module

 .Description

 .Parameter OsFamily
 Operating system the policy is being created for

 .Parameter FileName
 The name of the internal json file (BasePolicy or ExclusionPolicies)

#>
function Get-Policy {
    param(
        [string]$OsFamily,
        [string]$FileName)

    $path = "$OsFamily\$FileName"
    $jPath = Get-ModuleFilePath -Path $path 
    $jsonObject = Read-JsonFile -FilePath $jPath

    return $jsonObject
}

<#
 .Synopsis
 Read a JSON file with default parameters and add them to the PSDefaultParameterValues

 .Description
 Read a JSON file with default parameters and add them to the PSDefaultParameterValues

 .Parameter ParamFile
 A JSON file that contains/defines default parameters. Common for this module would be ClientId and TenantId

#>
function Import-MyDefaultParameters {
    param(
        [string]$ParamFile
    )

    Write-Debug "Import-MyDefaultParameters"
    $json = Read-JsonFile -FilePath $ParamFile

    $json.defaultParameters | ForEach-Object {
        $key = $_.function + ":" + $_.variable
        $value = $_.value
        Write-Host "Adding $key=$($_.value) to PSDefaultParameterValues."

        $PSDefaultParameterValues.Add($key, $value)
    }
}
# Export-ModuleMember -Function Import-MyDefaultParameters

<#
 .Synopsis
 This function imports a Device Management policy.

 .Description
 This function allows a Device Management policy stored in a JSON file to be imported into the specified environment.

 .Parameter PolicyFile
 JSON file that contains a MDE Device Management Policy

 .Parameter PolicyName
 When provided this value overrides the Policy Name

 .Parameter PolicyDescription
 When Provided this value overrides the Policy Description

 .Parameter ClientId
 The Client Id of the Module in Entra
#>
function Import-MyPolicy {
    param(
        [Parameter(Mandatory=$true)][string]$PolicyFile,
        [string]$PolicyName = "",
        [string]$PolicyDescription = "",
        [string]$ClientId = "",
        [string]$TenantId = ""
    )

    if($PSBoundParameters['Debug']) {
        Write-Debug "Changing DebugPreference from $DebugPreference to 'Continue'"
        $DebugPreference = 'Continue'
    }

    $policy = Read-JsonFile -FilePath $PolicyFile -ErrorAction Stop
    if($PolicyName -ne ""){
        $policy.name = $PolicyName
    }

    if($PolicyDescription -ne ""){
        $policy.description = $PolicyDescription
    }

    $body = $policy | ConvertTo-Json -Depth 12 -Compress
    Write-Debug "*** START BODY ***"
    Write-Debug "$body"
    Write-Debug "*** END BODY ***"

    Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Scopes DeviceManagementConfiguration.ReadWrite.All -NoWelcome
    Invoke-MgGraphRequest -Method POST -Uri https://graph.microsoft.com/beta/deviceManagement/configurationPolicies -Body $body -ContentType "application/json"
}
Export-ModuleMember -Function Import-MyPolicy

<#
 .Synopsis
 Import MDE Exclusions from a CSV File

 .Description
 This function generates an AV Exclusion Policy based on a list of exclusions in a file where each line is a unique exclusion

 .Parameter ExclusionFile
 File with an exclusion value per line

 .Parameter PolicyName
 Name of the Policy when created in the portal

 .Parameter PolicyDescription
 Description of the Policy in the portal

 .Parameter ClientId
 The ClientId from Entra where the module is registered

 .Parameter TenantId
 The TenantId from Entra where the module is registered

 .Parameter OsFamily
 The OS the exclusion policy is targeting

 .Parameter ExclusionType
 The type of exclusions stored in the file

#>
function Import-MyMdeExclusions {
    param(
        [Parameter(Mandatory=$true)][string]$ExclusionFile,
        [Parameter(Mandatory=$true)][string]$PolicyName,
        [string]$PolicyDescription = "",
        [string]$ClientId = "",
        [string]$TenantId = "",
        [ValidateSet("Mac","Linux","Windows")][string]$OsFamily,
        [ValidateSet("Directory","Process","FileExt")][string]$ExclusionType,
        [switch]$ExcludeDefaults
    )

    if($PSBoundParameters['Debug']) {
        Write-Debug "Changing DebugPreference from $DebugPreference to 'Continue'"
        $DebugPreference = 'Continue'
    }

    if (Test-Path $ExclusionFile) {
        $lineContent = Get-Content -Path $ExclusionFile
        $policy = New-MyBasePolicy -PolicyName $PolicyName -PolicyDescription $PolicyDescription -OsFamily $OsFamily

        $builtInPolicies = $null
        if($ExcludeDefaults) {
            $builtInPath = Get-ModuleFilePath -Path "Policies\BuiltIn.json"
            Write-Debug "Asking to read $builtInPath"
            $builtInPolicies = Read-JsonFile -FilePath $builtInPath -ErrorAction Stop
        }

        $firstDrop = $true
        foreach($row in $lineContent) { 
            $exclusionText = $($row).ToString()
            Write-Debug "Exclusion Line: $str"
            $defaultMatch = $false
            
            if($ExcludeDefaults) {
                $match = Get-MyMatchingExclusionGroup -ExclusionGroups $builtInPolicies -InputString $exclusionText -ReturnWarning
                $defaultMatch = ($match -ne $null)
                Write-Debug "Exclusion '$exclusionText' default match result '$defaultMatch'."
            }

            if($defaultMatch -ne $true) {
                $exclusion = New-MyExclusionSetting -ExclusionValue $exclusionText -ExclusionType $ExclusionType -OsFamily $OsFamily
                if($OsFamily -eq "Windows") {
                    Write-Debug "Searching for setting in policy"
                    $matchingSettingInstance = $policy.settings | Where-Object {
                        $_.settingInstance.settingDefinitionId -eq $exclusion.settingInstance.settingDefinitionId
                    }

                    if($null -eq $matchingSettingInstance){
                        Write-Debug "No settingInstance found for $($exclusion.settingInstance.settingDefinitionId)"
                        $policy.settings += $exclusion
                    }
                    else {
                        Write-Debug "Adding $($exclusion.value.value) to the simpleSettingCollectionValue"
                        $matchingSettingInstance.settingInstance.simpleSettingCollectionValue += $exclusion.settingInstance.simpleSettingCollectionValue[0];
                    }
                } else {
                    Write-Debug "Adding exclusion to groupSettingsCollectionValue $($policy.settings[0].settingInstance.groupSettingCollectionValue.Count)"
                    $policy.settings[0].settingInstance.groupSettingCollectionValue += $exclusion
                }
            }
            else {
                if($firstDrop -eq $true) {
                    Write-Warning "At least one exclusion path is being dropped from the policy '$PolicyName'."
                    $firstDrop = $false
                }
            }
        }

        $body = $policy | ConvertTo-Json -Depth 12 -Compress
        Write-Debug "*** START BODY ***"
        Write-Debug "$body"
        Write-Debug "*** END BODY ***"

        if($PSBoundParameters['Debug']) {
            Write-JsonFile -PolicyObject $policy
        }

        Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Scopes DeviceManagementConfiguration.ReadWrite.All -NoWelcome
        Invoke-MgGraphRequest -Method POST -Uri https://graph.microsoft.com/beta/deviceManagement/configurationPolicies -Body $body -ContentType "application/json"
    } else {
        Write-Error "File not found: $ExclusionFile"
    }
}
Export-ModuleMember -Function Import-MyMdeExclusions

<#
 .Synopsis
 Import an MDE Policy from a CSV file's content

 .Description
 Imports an MDE Device Management Policy based on the content of a CSV file

 .Parameter CsvFile
 The file path of the CSV file that contains the MDE Exclusion Paths and Types

 .Parameter PolicyName
 The name of the Policy when created in the portal

 .Parameter PolicyDescription
 Description of the Policy in the portal

 .Parameter ClientId
 The ClientId from Entra where the module is registered

 .Parameter TenantId
 The TenantId from Entra where the module is registered

 .Parameter OsFamily
 The OS the exclusion policy is targeting
#>
function Import-MyMdeCsvExclusions {
    param(
        [Parameter(Mandatory=$true)][string]$CsvFile,
        [Parameter(Mandatory=$true)][string]$PolicyName,
        [string]$PolicyDescription = "",
        [string]$ClientId = "",
        [string]$TenantId = "",
        [ValidateSet("Mac","Linux","Windows")][string]$OsFamily,
        [switch]$ExcludeDefaults
    )

    if($PSBoundParameters['Debug']) {
        Write-Debug "Changing DebugPreference from $DebugPreference to 'Continue'"
        $DebugPreference = 'Continue'
    }

    $firstDrop = $true
    if (Test-Path $CsvFile) {
        $csvContent = Import-Csv -Path $CsvFile
        $policy = New-MyBasePolicy -PolicyName $PolicyName -PolicyDescription $PolicyDescription -OsFamily $OsFamily

        $builtInPolicies = $null
        if($ExcludeDefaults) {
            $builtInPath = Get-ModuleFilePath -Path "Policies\BuiltIn.json"
            Write-Debug "Asking to read $builtInPath"
            $builtInPolicies = Read-JsonFile -FilePath $builtInPath -ErrorAction Stop
        }

        foreach ($row in $csvContent) {
            $exclusionText = $row.Exclusion
            $exclusionType = $row.ExclusionType
            Write-Debug "Adding a $exclusionType with value $exclusionText"

            $defaultMatch = $false
            
            if($ExcludeDefaults) {
                $match = Get-MyMatchingExclusionGroup -ExclusionGroups $builtInPolicies -InputString $exclusionText -ReturnWarning
                $defaultMatch = ($match -ne $null)
                Write-Debug "Exclusion '$exclusionText' default match result '$defaultMatch'."
            }

            if($defaultMatch -ne $true) {
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
                    Write-Debug "Adding exclusion to groupSettingsCollectionValue $($policy.settings[0].settingInstance.groupSettingCollectionValue.Count)"
                    $policy.settings[0].settingInstance.groupSettingCollectionValue += $exclusion
                }
            }
            else {
                if($firstDrop -eq $true) {
                    Write-Warning "At least one exclusion path is being dropped from the policy '$PolicyName'."
                    $firstDrop = $false
                }
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
Export-ModuleMember -Function Import-MyMdeCsvExclusions

<#
 .Synopsis
 Import default exclusions for various products

 .Description

 .Parameter DefaultProduct
 Currently only SQL is supported

 .Parameter PolicyName
 The name of the Policy when created in the portal

 .Parameter PolicyDescription
 Description of the Policy in the portal

 .Parameter ClientId
 The ClientId from Entra where the module is registered

 .Parameter TenantId
 The TenantId from Entra where the module is registered

 .Parameter OsFamily
 The OS the exclusion policy is targeting
#>
function Import-MyMdeDefaultExclusions {
    param(
        [ValidateSet("Sql")][string]$DefaultProduct,
        [string]$PolicyName = "My-MdeMigration Default Policy",
        [string]$PolicyDescription = "",
        [string]$ClientId = "",
        [string]$TenantId = "",
        [ValidateSet("Mac","Linux","Windows")][string]$OsFamily
    )

    $path = "Policies\$DefaultProduct.csv"
    $pPath = Get-ModuleFilePath -Path $path

    Import-MyMdeCsvExclusions -CsvFile $pPath -PolicyName $PolicyName -PolicyDescription $PolicyDescription -ClientId $ClientId -TenantId $TenantId -OsFamily $OsFamily
}
Export-ModuleMember -Function Import-MyMdeDefaultExclusions

<#
 .Synopsis
 Internal Function to read the base policy file

 .Parameter PolicyName
 The name of the Policy when created in the portal

 .Parameter PolicyDescription
 Description of the Policy in the portal

 .Parameter OsFamily
 The OS the exclusion policy is targeting

#>
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

<#
 .Synopsis
 Internal Function to create an Exclusion Setting

 .Parameter ExclusionValue
 The exclusion value

 .Parameter ExclusionType
 The type of exclusion like a Directory, File, FileExt, or Process

 .Parameter OsFamily
 The OS the exclusion is targeting

#>
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

<#
Unnecessary Functions

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
#>

<#
 .Synopsis
 Internal Function to Read a JSON file and return it as an Object

 .Description
 Internal Function to Read a JSON file and return it as an Object

 .Parameter FilePath
 Path to the JSON file

#>
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

<#
 .Synopsis
 Test a set of exclusions from the ExclusionFile against the built in exclusions

 .Description

 .Parameter ExclusionFile
 File path of a file including exclusions to be compared against the default exclusions for the specified OS

 .Parameter OsFamily
 The OS the exclusion is targeting

#>
function Test-MyCsvExclusions {
    param (
        [Parameter(Mandatory=$true)][string]$CsvFile,
        [ValidateSet("Mac","Linux","Windows")][string]$OsFamily,
        [switch]$IncludeWarnings
    )

    if($PSBoundParameters['Debug']) {
        Write-Debug "Changing DebugPreference from $DebugPreference to 'Continue'"
        $DebugPreference = 'Continue'
    }

    if (Test-Path $CsvFile) {
        $csvContent = Import-Csv -Path $CsvFile

        $builtInPath = Get-ModuleFilePath -Path "Policies\BuiltIn.json"
        Write-Debug "Asking to read $builtInPath"
        $builtInPolicies = Read-JsonFile -FilePath $builtInPath -ErrorAction Stop
        foreach ($row in $csvContent) {
            $exclusionText = $row.Exclusion

            $groupMatch = Get-MyMatchingExclusionGroup -ExclusionGroups $builtInPolicies -InputString $exclusionText -ReturnWarning:$IncludeWarnings

            if($null -eq $groupMatch){
                Write-Host "The exclusion text $exclusionText is unique"
            }
            else {
                Write-Host "The exclusion text $exclusionText is part of the $groupMatch default exclusions."
            }
        }
    }
    else {
        Write-Error "The $ExclusionFile does not exist."
    }
}
Export-ModuleMember -Function Test-MyCsvExclusions

<#
 .Synopsis
 Test a set of exclusions from the ExclusionFile against the built in exclusions

 .Description

 .Parameter ExclusionFile
 File path of a file including exclusions to be compared against the default exclusions for the specified OS

 .Parameter OsFamily
 The OS the exclusion is targeting

#>
function Test-MyExclusions {
    param (
        [Parameter(Mandatory=$true)][string]$ExclusionFile,
        [ValidateSet("Mac","Linux","Windows")][string]$OsFamily
    )

    if($PSBoundParameters['Debug']) {
        Write-Debug "Changing DebugPreference from $DebugPreference to 'Continue'"
        $DebugPreference = 'Continue'
    }

    if (Test-Path $ExclusionFile) {
        $content = Get-Content -Path $ExclusionFile

        $builtInPath = Get-ModuleFilePath -Path "Policies\BuiltIn.json"
        Write-Debug "Asking to read $builtInPath"
        $builtInPolicies = Read-JsonFile -FilePath $builtInPath -ErrorAction Stop
        foreach ($row in $csvContent) {
            $exclusionText = $row

            $groupMatch = Get-MyMatchingExclusionGroup -ExclusionGroups $builtInPolicies -InputString $exclusionText

            if($null -eq $groupMatch){
                Write-Host "The exclusion text $exclusionText is unique"
            }
            else {
                Write-Host "The exclusion text $exclusionText is part of the $groupMatch default exclusions."
            }
        }
    }
    else {
        Write-Error "The $ExclusionFile does not exist."
    }
}
Export-ModuleMember -Function Test-MyExclusions

<#
 .Synopsis
 Internal Function to write an output to a JSON file

 .Description
 Internal function to write a Policy Object to a specific JSON file

 .Parameter PolicyObject
 The Exclusion policy object that should be written to a JSON output file

#>
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