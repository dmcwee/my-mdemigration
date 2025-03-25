# My-MdeMigration

```bash
                               _             _                 _   _             
  /\/\  _   _        /\/\   __| | ___  /\/\ (_) __ _ _ __ __ _| |_(_) ___  _ __  
 /    \| | | |_____ /    \ / _` |/ _ \/    \| |/ _` | '__/ _` | __| |/ _ \| '_ \ 
/ /\/\ \ |_| |_____/ /\/\ \ (_| |  __/ /\/\ \ | (_| | | | (_| | |_| | (_) | | | |
\/    \/\__, |     \/    \/\__,_|\___\/    \/_|\__, |_|  \__,_|\__|_|\___/|_| |_|
        |___/                                  |___/                             
```

## Required Modules

Microsoft Graph Powershell SDK must be installed in order to utilize this module.

```powershell
[ps]> Install-Module Microsoft.Graph -Scope AllUsers -Repository PSGallery -Force
```

## Install My-MdeMigration Module

The module folder includes an install script to create a self signed certificate and sign the module. The
install must be run in a powershell window with `bypass` or another permissive execution policy. After running
the install script the module can be run with an execution policy that allows for self signed certificates.

```powershell
[PowerShell Module Folder]> install.ps1
```

## After Installation

The next items outline actions you should perform after install the My-MdeMigration module.

### Register an Entra Application

You should use a registered application in your organization's Entra Tenant to limit and monitor the scopes
used by My-MdeMigration module. Follow [these instructions](https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands?view=graph-powershell-1.0#use-delegated-access-with-a-custom-application-for-microsoft-graph-powershell) to create a local application.

### Configure the Default Parameters

In the My-MdeMigration module folder the file my-mdemigration.defaultparameters.json should be updated with
the client id and tenant id from your Entra Application registration. While this is not required it will make
running the `Import` command easer as you will not need to specify the Client or Tenant ID each time you run this
command.

## Usage

Currently the primary use case for My-MdeMigration module is to accelerate the ability of organizations to create
Microsoft Defender Antivirus Exclusion policies.

### Import-MyMdeExclusions

The Import-MyMdeExclusions accepts a file with a list, one entry per line, of exclusion (File Extension, Directory, File, Process) and will 
generate a valid Microsoft Defender Antivirus Exclusion policy in the MDE service.

**Note:** Running in Debug will cause a JSON file of the policy to be generated in the local directory.

### New-MyMdeExclusionsFile

The New-MyMdeExclusionsFile accepts a file with a list, one entry per line, of exclusion (File Extension, Directory, File, Process) and will
generate a valid JSON file that represents a Microsoft Defender Antivirus Exclusion policy in the local directory.
