[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Installer,
    [ValidateSet('production', 'development', 'staging')]
    [string]$Flavor = 'production',
    [switch]$Interactive,
    [switch]$KeepInstalled
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Installer -PathType Leaf)) {
    throw "Installer was not found: $Installer"
}
$installerPath = (Resolve-Path -LiteralPath $Installer).Path

# The three flavors install side by side, so every path and identity this script
# checks has to come from the same table the installer was compiled from.
. (Join-Path $PSScriptRoot '..\flavors.ps1')
$flavorConfig = Get-PomodoistFlavor -Flavor $Flavor

$installDirectory = Join-Path `
    $env:LOCALAPPDATA `
    "Programs\$($flavorConfig.DisplayName)"
$installedExecutable = Join-Path $installDirectory 'pomodoist.exe'
$protocolRegistryPath = "HKCU:\Software\Classes\$($flavorConfig.UrlScheme)"
$protocolCommandPath = Join-Path $protocolRegistryPath 'shell\open\command'
$shortcutPath = Join-Path `
    $env:APPDATA `
    "Microsoft\Windows\Start Menu\Programs\$($flavorConfig.DisplayName).lnk"
$uninstallRegistryPath = Join-Path `
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' `
    "$($flavorConfig.ApplicationId)_is1"
$deepLinkUri = "$($flavorConfig.UrlScheme)://focus"
$upgradeMarker = Join-Path $installDirectory '.installer-smoke-marker'
$existingUninstaller = Get-ChildItem `
    -LiteralPath $installDirectory `
    -Filter 'unins*.exe' `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1
$hadExistingInstall = $null -ne $existingUninstaller
if ($hadExistingInstall -and -not $KeepInstalled) {
    throw "$($flavorConfig.DisplayName) is already installed; refusing to remove an existing user installation."
}
$installationMayExist = $false
$bodySucceeded = $false

function Invoke-Installer {
    param([string[]]$Arguments)

    $startParameters = @{
        FilePath = $installerPath
        PassThru = $true
    }
    if ($null -ne $Arguments -and @($Arguments).Count -gt 0) {
        $startParameters.ArgumentList = $Arguments
    }
    $process = Start-Process @startParameters
    if (-not $process.WaitForExit(60000)) {
        Stop-Process -Id $process.Id -Force
        throw "Pomodoist installer did not exit within 60 seconds."
    }
    if ($process.ExitCode -ne 0) {
        throw "Pomodoist installer exited with code $($process.ExitCode)."
    }
}

function Get-InstalledProcesses {
    return @(
        Get-Process 'pomodoist' -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    $_.Path -and $_.Path.Equals(
                        $installedExecutable,
                        [System.StringComparison]::OrdinalIgnoreCase
                    )
                } catch {
                    $false
                }
            }
    )
}

function Wait-ForInstalledProcess {
    param([int[]]$ExcludedProcessIds = @())

    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 500
        $process = Get-InstalledProcesses |
            Where-Object { $ExcludedProcessIds -notcontains $_.Id } |
            Select-Object -First 1
    } until ($null -ne $process -or [DateTime]::UtcNow -ge $deadline)
    if ($null -eq $process) {
        throw 'The installed Pomodoist executable did not launch.'
    }
    return $process
}

function Stop-InstalledProcesses {
    foreach ($process in @(Get-InstalledProcesses)) {
        $process | Stop-Process -Force
        [void]$process.WaitForExit(10000)
    }
}

function Remove-SmokeInstallation {
    if (Test-Path -LiteralPath $upgradeMarker -PathType Leaf) {
        Remove-Item -LiteralPath $upgradeMarker -Force
    }
    Stop-InstalledProcesses
    $uninstaller = Get-ChildItem `
        -LiteralPath $installDirectory `
        -Filter 'unins*.exe' `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $uninstaller) {
        throw "$($flavorConfig.DisplayName) uninstaller was not created."
    }
    $uninstall = Start-Process `
        -FilePath $uninstaller.FullName `
        -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') `
        -Wait `
        -PassThru
    if ($uninstall.ExitCode -ne 0) {
        throw "$($flavorConfig.DisplayName) uninstaller exited with code $($uninstall.ExitCode)."
    }
    if (Test-Path -LiteralPath $protocolRegistryPath) {
        throw "The $($flavorConfig.UrlScheme) protocol registration remained after uninstall."
    }
}

try {
    $installationMayExist = $true
    if ($hadExistingInstall) {
        Stop-InstalledProcesses
    }
    $firstInstallArguments = if ($Interactive) {
        @()
    } else {
        @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
    }
    Invoke-Installer -Arguments $firstInstallArguments

    if (-not (Test-Path -LiteralPath $installedExecutable -PathType Leaf)) {
        throw "Installed executable was not found: $installedExecutable"
    }
    if (-not (Test-Path -LiteralPath $protocolCommandPath)) {
        throw "The $($flavorConfig.UrlScheme) protocol was not registered for the current user."
    }
    $actualProtocolCommand = (Get-ItemProperty -LiteralPath $protocolCommandPath).'(default)'
    $expectedProtocolCommand = "`"$installedExecutable`" `"%1`""
    if ($actualProtocolCommand -cne $expectedProtocolCommand) {
        throw "Unexpected protocol command: $actualProtocolCommand"
    }
    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
        throw "$($flavorConfig.DisplayName) Start Menu shortcut was not created."
    }
    if (-not (Test-Path -LiteralPath $uninstallRegistryPath)) {
        throw "$($flavorConfig.DisplayName) uninstall registration was not created for the current user."
    }

    $shell = New-Object -ComObject Shell.Application
    $shortcutFolder = $shell.Namespace((Split-Path $shortcutPath))
    $shortcut = $shortcutFolder.ParseName((Split-Path $shortcutPath -Leaf))
    $appUserModelId = $shortcut.ExtendedProperty('System.AppUserModel.ID')
    $toastActivator = $shortcut.ExtendedProperty(
        'System.AppUserModel.ToastActivatorCLSID'
    ).ToString().Trim('{}')
    if ($appUserModelId -cne $flavorConfig.ApplicationId) {
        throw "Unexpected shortcut AppUserModelID: $appUserModelId"
    }
    if ($toastActivator -ine $flavorConfig.ToastGuid) {
        throw "Unexpected toast activator CLSID: $toastActivator"
    }

    $runningBeforeUpgrade = if ($Interactive) {
        Wait-ForInstalledProcess
    } else {
        Start-Process -FilePath $installedExecutable -PassThru
        Wait-ForInstalledProcess
    }
    $runningBeforeUpgrade | Stop-Process -Force
    [void]$runningBeforeUpgrade.WaitForExit(10000)
    Set-Content -LiteralPath $upgradeMarker -Value 'preserve'
    Invoke-Installer -Arguments @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
    if (-not (Test-Path -LiteralPath $upgradeMarker -PathType Leaf)) {
        throw 'Installer upgrade removed existing application data.'
    }

    & (Join-Path $PSScriptRoot '..\test_deep_link_forwarding.ps1') `
        -Executable $installedExecutable `
        -Flavor $Flavor

    $existingProcessIds = @(Get-InstalledProcesses | ForEach-Object Id)
    Start-Process $deepLinkUri
    $process = Wait-ForInstalledProcess -ExcludedProcessIds $existingProcessIds

    $bodySucceeded = $true
    if ($KeepInstalled) {
        Remove-Item -LiteralPath $upgradeMarker -Force -ErrorAction SilentlyContinue
        Write-Output "$($flavorConfig.DisplayName) is installed and running (PID $($process.Id))."
    } else {
        Write-Output "$($flavorConfig.DisplayName) installer smoke test passed."
    }
} finally {
    if (-not $KeepInstalled -and -not $hadExistingInstall -and $installationMayExist) {
        try {
            Remove-SmokeInstallation
        } catch {
            if ($bodySucceeded) { throw }
            Write-Warning "Smoke cleanup also failed: $($_.Exception.Message)"
        }
    }
}
