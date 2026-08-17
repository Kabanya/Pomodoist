[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Installer,
    [switch]$Interactive,
    [switch]$KeepInstalled
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Installer -PathType Leaf)) {
    throw "Installer was not found: $Installer"
}
$installerPath = (Resolve-Path -LiteralPath $Installer).Path
$installDirectory = Join-Path $env:LOCALAPPDATA 'Programs\Pomodoist'
$installedExecutable = Join-Path $installDirectory 'pomodoist.exe'
$protocolRegistryPath = 'HKCU:\Software\Classes\pomodoist'
$protocolCommandPath = Join-Path $protocolRegistryPath 'shell\open\command'
$shortcutPath = Join-Path `
    $env:APPDATA `
    'Microsoft\Windows\Start Menu\Programs\Pomodoist.lnk'
$uninstallRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\com.finchforge.pomodoist_is1'
$upgradeMarker = Join-Path $installDirectory '.installer-smoke-marker'
$existingUninstaller = Get-ChildItem `
    -LiteralPath $installDirectory `
    -Filter 'unins*.exe' `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1
$hadExistingInstall = $null -ne $existingUninstaller
if ($hadExistingInstall -and -not $KeepInstalled) {
    throw 'Pomodoist is already installed; refusing to remove an existing user installation.'
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
        throw 'Pomodoist uninstaller was not created.'
    }
    $uninstall = Start-Process `
        -FilePath $uninstaller.FullName `
        -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') `
        -Wait `
        -PassThru
    if ($uninstall.ExitCode -ne 0) {
        throw "Pomodoist uninstaller exited with code $($uninstall.ExitCode)."
    }
    if (Test-Path -LiteralPath $protocolRegistryPath) {
        throw 'The pomodoist protocol registration remained after uninstall.'
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
        throw 'The pomodoist protocol was not registered for the current user.'
    }
    $actualProtocolCommand = (Get-ItemProperty -LiteralPath $protocolCommandPath).'(default)'
    $expectedProtocolCommand = "`"$installedExecutable`" `"%1`""
    if ($actualProtocolCommand -cne $expectedProtocolCommand) {
        throw "Unexpected protocol command: $actualProtocolCommand"
    }
    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
        throw 'Pomodoist Start Menu shortcut was not created.'
    }
    if (-not (Test-Path -LiteralPath $uninstallRegistryPath)) {
        throw 'Pomodoist uninstall registration was not created for the current user.'
    }

    $shell = New-Object -ComObject Shell.Application
    $shortcutFolder = $shell.Namespace((Split-Path $shortcutPath))
    $shortcut = $shortcutFolder.ParseName((Split-Path $shortcutPath -Leaf))
    $appUserModelId = $shortcut.ExtendedProperty('System.AppUserModel.ID')
    $toastActivator = $shortcut.ExtendedProperty(
        'System.AppUserModel.ToastActivatorCLSID'
    ).ToString().Trim('{}')
    if ($appUserModelId -cne 'com.finchforge.pomodoist') {
        throw "Unexpected shortcut AppUserModelID: $appUserModelId"
    }
    if ($toastActivator -ine '8681f633-939c-46f5-84cc-18f295e4382c') {
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

    $existingProcessIds = @(Get-InstalledProcesses | ForEach-Object Id)
    Start-Process 'pomodoist://focus'
    $process = Wait-ForInstalledProcess -ExcludedProcessIds $existingProcessIds

    $bodySucceeded = $true
    if ($KeepInstalled) {
        Remove-Item -LiteralPath $upgradeMarker -Force -ErrorAction SilentlyContinue
        Write-Output "Pomodoist is installed and running (PID $($process.Id))."
    } else {
        Write-Output 'Pomodoist installer smoke test passed.'
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
