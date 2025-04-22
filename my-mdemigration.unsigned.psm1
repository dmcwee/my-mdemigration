<#
 .Synopsis
 Internal Function - Converts the exported policy setting into a ChoiceSettingValue policy.

 .Description
 Converts the exported policy setting into a ChoiceSettingValue policy.

 .Parameter Setting
 A single instance of a Choice Setting Value exported policy Setting
#>
function ConvertTo-ChoiceSettingValue {
    param(
        $Setting
    )

    $builtInPath = Get-MyModuleFilePath -Path "Export\PolicyParts.json"
    Write-Debug "Asking to read $builtInPath"
    $policyParts = Read-JsonFile -FilePath $builtInPath -ErrorAction Stop

    $choiceSettingValue = $policyParts.choiceSettingValue
    $choiceSettingValue.settingInstance.choiceSettingValue.children = $Setting.settingInstance.choiceSettingValue.children
    $choiceSettingValue.settingInstance.choiceSettingValue.settingValueTemplateReference = ConvertTo-SettingValueTemplateReference $Setting.settingInstance.choiceSettingValue.settingValueTemplateReference
    $choiceSettingValue.settingInstance.choiceSettingValue.value = $Setting.settingInstance.choiceSettingValue.value
    $choiceSettingValue.settingInstance.settingDefinitionId = $Setting.settingInstance.settingDefinitionId
    $choiceSettingValue.settingInstance.settingInstanceTemplateReference = $Setting.settingInstance.settingInstanceTemplateReference

    return $choiceSettingValue
}

<#
 .Synopsis
 Internal Function - Converts the exported setting value reference to a SettingValueTemplateReference

 .Description
 Converts the exported setting value reference to a SettingValueTemplateReference

 .Parameter SettingValueReference
 A single instance of a Setting Value Template Reference exported policy Setting
#>
function ConvertTo-SettingValueTemplateReference {
    param($SettingValueReference)

    if($null -ne $SettingValueReference) {
        return @{
            settingValueTemplateId = $SettingValueReference.settingValueTemplateId
        }
    }
    else {
        return $null
    }
}

<#
 .Synopsis
 Internal Function - Converts the exported policy settings into a SimpleSetting policy.

 .Description
 Converts the exported policy settings into a SimpleSetting policy.

 .Parameter Setting
 A single instance of a Simple Setting policy Setting
#>
function ConvertTo-SimpleSettingInstance {
    param(
        $Setting
    )

    return @{
        id = $Setting.Id
        settingInstance = $Setting.settingInstance
    }
}

<#
 .Synopsis
 Internal Function - Converts an exported setting into the proper policy setting type

 .Description
 Converts the exported policy settings into the correct types used to create/import the policy.

 .Parameter ExportSettings
 The exported Policy Settings from the Get-MyMdePolicySettings
#>
function ConvertTo-PolicySettings {
    param(
        $ExportSettings
    )

    $settings = @()
    foreach($setting in $ExportSettings) {
        Write-Debug "SettingInstance: '$setting'"
        if($setting.settingInstance."@odata.type" -eq "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance") {
            $settings += ConvertTo-ChoiceSettingValue $setting
        }
        elseif ($setting.settingInstance."@odata.type" -eq "#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance" -or
            $setting.settingInstance."@odata.type" -eq "#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance" -or
            $setting.settingInstance."@odata.type" -eq "#microsoft.graph.deviceManagementConfigurationSimpleSettingCollectionInstance"
        ) {
            $settings += ConvertTo-SimpleSettingInstance $setting
        }
        else {
            Write-Warning "Setting type '$($setting.settingInstance."@odata.type")' is unhandled and being omitted"
        }
    }
    return $settings
}

<#
 .Synopsis
 Export MDE Policies from the specified tenant

 .Description
 Exports the MDE Policies in a tenant and writes them in a JSON format that can be 
 used by the Import-MyPolicy to import the policy to a new or to the same tenant

 .Parameter OutputPath
 The folder path location where the policies will be written

  .Parameter ClientId
 The Client Id of the Module in Entra

 .Parameter TenantId
 The Tenant Id of the Entra Tenant where the module is registered

#>
function Export-MyMdePolicies {
    param(
        [string]$OutputPath,
        [string]$ClientId,
        [string]$TenantId
    )

    if($PSBoundParameters['Debug']) {
        Write-Debug "Changing DebugPreference from $DebugPreference to 'Continue'"
        $DebugPreference = 'Continue'
    }

    $policies = Get-MyMdePolicies -ClientId $ClientId -TenantId $TenantId
    $policiesJson = ConvertTo-Json $policies -Depth 12 -Compress
    $policiesObj = ConvertFrom-Json $policiesJson

    foreach($policy in $policiesObj) {
        $settings = Get-MyMdePolicySettings -PolicyId $($policy.id) -ClientId $ClientId -TenantId $TenantId
        $settingsJson = ConvertTo-Json $settings -Depth 12 -Compress
        $settingsObj = ConvertFrom-Json $settingsJson
        Write-Debug "*** settingsObj ***"
        Write-Debug $settingsJson
        Write-Debug "***    end      ***"

        $exportSettings = @()
        $exportSettings += ConvertTo-PolicySettings -ExportSettings $settingsObj
        Write-Debug "*** exportSettings ***"
        Write-Debug $(ConvertTo-Json $exportSettings -Depth 12 -Compress)
        Write-Debug "***      end       ***"

        $devicePolicy = @{
            name = $policy.name
            description = $policy.description
            settings = $exportSettings
            platforms = $policy.platforms
            technologies = $policy.technologies
            templateReference = @{
                templateId = $policy.templateReference.templateId
            }
        }

        Write-Debug "Converting Policy to JSON object"
        $policyJson = $devicePolicy | ConvertTo-Json -Depth 12 -Compress

        $outputFilePath = "$OutputPath\$($devicePolicy.name).json"
        $policyJson | Out-File -FilePath $outputFilePath
    }
}
Export-ModuleMember -Function Export-MyMdePolicies

<#
 .Synopsis
 Internal function - Accepts the string to check against a group of exclusions

 .Description
 Accepts the string to check against a group of exclusions

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
 Internal Function - List the Device Management Policies in the tenant

 .Description
 List the Device Management Policies in the tenant. This is primarily an internal function, but may be 
 exposed for testing purposes.

 .Parameter ClientId

 .Parameter TenantId
#>
function Get-MyMdePolicies {
    param(
        [string]$ClientId,
        [string]$TenantId
    )

    $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
    Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Scopes DeviceManagementConfiguration.ReadWrite.All -NoWelcome
    $policies = Invoke-MgGraphRequest -Method GET -Uri $uri
    return $policies.value
}
# Export-ModuleMember -Function Get-MyMdePolicies

<#
 .Synopsis
 Internal Function - List the Device Management Policy's settings

 .Description
 List the Device Management Policy's settings. This is primarily an internal function, but may be 
 exposed for testing purposes.

 .Parameter PolicyId
 The ID of the policy the settings will be retrieved for

 .Parameter ClientId

 .Parameter TenantId
#>
function Get-MyMdePolicySettings {
    param(
        [string]$PolicyId,
        [string]$ClientId,
        [string]$TenantId
    )

    $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$PolicyId/settings"
    Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Scopes DeviceManagementConfiguration.ReadWrite.All -NoWelcome
    $settings = Invoke-MgGraphRequest -Method GET -Uri $uri
    return $settings.value
}
# Export-ModuleMember -Function Get-MyMdePolicySettings

<#
 .Synopsis
 Internal Function - Generates a path to files installed with the module

 .Description
 Generates a path to files installed with the module

 .Parameter Path
 Function to consistently generate a path to a file held in the module's install location

#>
function Get-MyModuleFilePath {
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
 Read the Base or ExclusionPolicies JSON files deployed with the module

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
    $jPath = Get-MyModuleFilePath -Path $path 
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

 .Parameter TenantId
 The Tenant Id of the Entra Tenant where the module is registered

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
            $builtInPath = Get-MyModuleFilePath -Path "Policies\BuiltIn.json"
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
                $defaultMatch = ($null -ne $match)
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
            $builtInPath = Get-MyModuleFilePath -Path "Policies\BuiltIn.json"
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
                $defaultMatch = ($null -ne $match)
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
    $pPath = Get-MyModuleFilePath -Path $path

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

        $builtInPath = Get-MyModuleFilePath -Path "Policies\BuiltIn.json"
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

        $builtInPath = Get-MyModuleFilePath -Path "Policies\BuiltIn.json"
        Write-Debug "Asking to read $builtInPath"
        $builtInPolicies = Read-JsonFile -FilePath $builtInPath -ErrorAction Stop
        foreach ($row in $content) {
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
 Internal Function -Write an output to a JSON file

 .Description
 Write a Policy Object to a specific JSON file

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