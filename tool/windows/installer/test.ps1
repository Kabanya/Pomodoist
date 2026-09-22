[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$testRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'build\windows\installer-test')
)
if (-not $testRoot.StartsWith(
        $repoRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw 'Installer test path escaped the repository.'
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Contains {
    param([string]$Actual, [string]$Expected, [string]$Message)
    if (-not $Actual.Contains($Expected)) {
        throw "$Message`nExpected to contain: $Expected`nActual: $Actual"
    }
}

function Assert-ContainsEither {
    param([string]$Actual, [string[]]$Expected, [string]$Message)
    foreach ($candidate in $Expected) {
        if ($Actual.Contains($candidate)) { return }
    }
    throw "$Message`nExpected to contain one of: $($Expected -join ' | ')`nActual: $Actual"
}

function Assert-ThrowsContaining {
    param(
        [scriptblock]$Action,
        [string]$Expected,
        [string]$Message
    )
    try {
        & $Action
    } catch {
        Assert-Contains $_.Exception.Message $Expected $Message
        return
    }
    throw "$Message`nExpected an exception containing: $Expected"
}

if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$originalLocalAppData = $env:LOCALAPPDATA
$originalPath = $env:PATH

try {
    $bundle = Join-Path $testRoot 'bundle'
    $output = Join-Path $testRoot 'output'
    $data = Join-Path $bundle 'data'
    New-Item -ItemType Directory -Force -Path $data | Out-Null
    Set-Content -LiteralPath (Join-Path $bundle 'pomodoist.exe') -Value 'runner'
    Set-Content -LiteralPath (Join-Path $bundle 'flutter_windows.dll') -Value 'runtime'
    Set-Content -LiteralPath (Join-Path $data 'fixture.txt') -Value 'data'

    $fixture = Join-Path $testRoot 'fixture.exe'
    $compilerLog = Join-Path $testRoot 'compiler-arguments.txt'
    $fakeCompiler = Join-Path $testRoot 'fake-iscc.cmd'
    Set-Content -LiteralPath $fixture -Value 'deterministic installer fixture'
    Set-Content -LiteralPath $fakeCompiler -Encoding ascii -Value @'
@echo off
echo %* > "%FAKE_INNO_LOG%"
copy /y "%FAKE_INNO_FIXTURE%" "%FAKE_INNO_OUTPUT%" >nul
exit /b 0
'@

    $env:FAKE_INNO_LOG = $compilerLog
    $env:FAKE_INNO_FIXTURE = $fixture
    $env:FAKE_INNO_OUTPUT = Join-Path $output 'Pomodoist-Setup.exe'

    $buildScript = Join-Path $PSScriptRoot 'build.ps1'
    & $buildScript `
        -BuildDirectory $bundle `
        -OutputDirectory $output `
        -CompilerPath $fakeCompiler `
        -Version '1.2.3'

    $installer = Join-Path $output 'Pomodoist-Setup.exe'
    $checksum = "$installer.sha256"
    Assert-True (Test-Path -LiteralPath $installer) 'Installer was not produced.'
    Assert-True (Test-Path -LiteralPath $checksum) 'Checksum was not produced.'

    $expectedHash = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash
    $actualHash = ((Get-Content -Raw -LiteralPath $checksum).Trim() -split ' ')[0]
    Assert-True ($actualHash -ceq $expectedHash) 'Checksum does not match installer.'

    $arguments = Get-Content -Raw -LiteralPath $compilerLog
    Assert-Contains $arguments '/DAppVersion=1.2.3' 'Version was not passed to Inno Setup.'
    Assert-Contains $arguments '/DAppNumericVersion=1.2.3.0' 'Numeric version was not passed to Inno Setup.'
    Assert-Contains $arguments "/DSourceDir=$bundle" 'Bundle path was not passed to Inno Setup.'
    Assert-Contains $arguments "/DOutputDir=$output" 'Output path was not passed to Inno Setup.'
    Assert-Contains $arguments 'Pomodoist.iss' 'Installer source was not compiled.'
    Assert-Contains $arguments '/DAppIdentifier=com.finchforge.pomodoist' 'Production identifier was not passed to Inno Setup.'
    Assert-Contains $arguments '/DAppDisplayName=Pomodoist' 'Production display name was not passed to Inno Setup.'
    Assert-Contains $arguments '/DAppUrlScheme=pomodoist' 'Production URL scheme was not passed to Inno Setup.'
    Assert-Contains $arguments '/DAppToastGuid=8681f633-939c-46f5-84cc-18f295e4382c' 'Production toast GUID was not passed to Inno Setup.'
    Assert-Contains $arguments '/DSetupBaseFilename=Pomodoist-Setup' 'Production setup name was not passed to Inno Setup.'

    # A non-production flavor has to reach the compiler with its own identity, so
    # the three installers can be installed side by side without overwriting each
    # other's shortcut, protocol handler or uninstall entry.
    $stagingInstaller = Join-Path $output 'Pomodoist-Staging-Setup.exe'
    $env:FAKE_INNO_OUTPUT = $stagingInstaller
    & $buildScript `
        -BuildDirectory $bundle `
        -OutputDirectory $output `
        -CompilerPath $fakeCompiler `
        -Version '1.2.3' `
        -Flavor staging
    Assert-True `
        (Test-Path -LiteralPath $stagingInstaller) `
        'Staging installer was not produced under its flavor name.'
    $arguments = Get-Content -Raw -LiteralPath $compilerLog
    Assert-Contains $arguments '/DAppIdentifier=com.finchforge.pomodoist.stg' 'Staging identifier was not passed to Inno Setup.'
    Assert-Contains $arguments '/DAppUrlScheme=pomodoist-stg' 'Staging URL scheme was not passed to Inno Setup.'
    Assert-Contains $arguments '/DAppToastGuid=b3c1d7a2-5e64-4f18-9a0b-2d7c6e1f8a34' 'Staging toast GUID was not passed to Inno Setup.'
    Assert-Contains $arguments '/DSetupBaseFilename=Pomodoist-Staging-Setup' 'Staging setup name was not passed to Inno Setup.'
    Assert-ContainsEither `
        $arguments `
        @('/DAppDisplayName=Pomodoist Stg', '/DAppDisplayName="Pomodoist Stg"') `
        'Staging display name was not passed to Inno Setup.'
    $stagingChecksum = "$stagingInstaller.sha256"
    Assert-True `
        (Test-Path -LiteralPath $stagingChecksum) `
        'Staging checksum was not produced.'
    Assert-Contains `
        (Get-Content -Raw -LiteralPath $stagingChecksum) `
        '*Pomodoist-Staging-Setup.exe' `
        'Staging checksum does not name the staging installer.'
    $env:FAKE_INNO_OUTPUT = Join-Path $output 'Pomodoist-Setup.exe'

    # The build script refuses a target that belongs to another flavor, which is
    # what keeps an entry point and a compile-time flavor from disagreeing. The
    # check runs before the script touches the build directories or Flutter.
    $windowsBuildScript = Join-Path $repoRoot 'tool\windows\build.ps1'
    Assert-ThrowsContaining `
        -Action { & $windowsBuildScript -Target 'lib/main_staging.dart' -Flavor development } `
        -Expected 'belongs to the staging flavor' `
        -Message 'A target from another flavor was accepted.'
    Assert-ThrowsContaining `
        -Action { & $windowsBuildScript -Target 'lib/main_unknown.dart' -Flavor development } `
        -Expected '-Target must be one of' `
        -Message 'An unknown target was accepted.'

    & $buildScript `
        -BuildDirectory $bundle `
        -OutputDirectory $output `
        -CompilerPath $fakeCompiler `
        -Version '1.2.3-rc.1'
    $arguments = Get-Content -Raw -LiteralPath $compilerLog
    Assert-Contains $arguments '/DAppVersion=1.2.3-rc.1' 'RC suffix was lost.'
    Assert-Contains $arguments '/DAppNumericVersion=1.2.3.0' 'RC numeric version is invalid.'

    $versionRepo = Join-Path $testRoot 'version-repository'
    $versionTools = Join-Path $versionRepo 'tool\windows\installer'
    $versionResources = Join-Path $versionRepo 'apps\flutter\windows\runner\resources'
    New-Item -ItemType Directory -Force $versionTools, $versionResources | Out-Null
    Copy-Item -LiteralPath $buildScript -Destination $versionTools
    # The copied script dot-sources the flavor table next to the copy, so the
    # fixture needs the real table in the position the script expects it.
    Copy-Item `
        -LiteralPath (Join-Path $PSScriptRoot '..\flavors.ps1') `
        -Destination (Join-Path $versionRepo 'tool\windows\flavors.ps1')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Pomodoist.iss') -Destination $versionTools
    Copy-Item -LiteralPath (Join-Path $repoRoot 'apps\flutter\windows\runner\resources\app_icon.ico') -Destination $versionResources
    Set-Content -LiteralPath (Join-Path $versionRepo 'apps\flutter\pubspec.yaml') -Value 'version: 1.2.3-rc.1+91'
    & (Join-Path $versionTools 'build.ps1') `
        -BuildDirectory $bundle `
        -OutputDirectory $output `
        -CompilerPath $fakeCompiler
    $arguments = Get-Content -Raw -LiteralPath $compilerLog
    Assert-Contains $arguments '/DAppVersion=1.2.3-rc.1' 'RC version was not read from pubspec.yaml.'
    Assert-Contains $arguments '/DAppNumericVersion=1.2.3.0' 'Pubspec numeric version is invalid.'

    foreach ($invalidVersion in @('v1.2.3', '1.2', '1.2.3-beta.1', '1.2.3-rc.01', '1.2.3-RC.1', '01.2.3')) {
        Assert-ThrowsContaining `
            -Action {
                & $buildScript `
                    -BuildDirectory $bundle `
                    -OutputDirectory $output `
                    -CompilerPath $fakeCompiler `
                    -Version $invalidVersion
            } `
            -Expected '-Version must use' `
            -Message "Invalid version was accepted: $invalidVersion"
    }

    $incompleteBundle = Join-Path $testRoot 'incomplete-bundle'
    New-Item -ItemType Directory -Force -Path (Join-Path $incompleteBundle 'data') |
        Out-Null
    Set-Content -LiteralPath (Join-Path $incompleteBundle 'pomodoist.exe') `
        -Value 'runner'
    Remove-Item -LiteralPath $compilerLog -Force
    Assert-ThrowsContaining `
        -Action {
            & $buildScript `
                -BuildDirectory $incompleteBundle `
                -OutputDirectory $output `
                -CompilerPath $fakeCompiler `
                -Version '1.2.3'
        } `
        -Expected 'missing flutter_windows.dll' `
        -Message 'Incomplete Flutter bundle was not rejected.'
    Assert-True `
        (-not (Test-Path -LiteralPath $compilerLog)) `
        'Compiler ran for an incomplete Flutter bundle.'

    $fakeLocalAppData = Join-Path $testRoot 'local-app-data'
    $discoveredCompiler = Join-Path `
        $fakeLocalAppData `
        'Programs\Inno Setup 6\ISCC.exe'
    New-Item -ItemType Directory -Force -Path (Split-Path $discoveredCompiler) |
        Out-Null
    Add-Type -TypeDefinition @'
using System;
using System.IO;

public static class FakeInnoCompiler
{
    public static int Main(string[] args)
    {
        File.WriteAllLines(Environment.GetEnvironmentVariable("FAKE_INNO_LOG"), args);
        File.Copy(
            Environment.GetEnvironmentVariable("FAKE_INNO_FIXTURE"),
            Environment.GetEnvironmentVariable("FAKE_INNO_OUTPUT"),
            true
        );
        return 0;
    }
}
'@ -OutputAssembly $discoveredCompiler -OutputType ConsoleApplication

    $discoveryOutput = Join-Path $testRoot 'discovery-output'
    $env:LOCALAPPDATA = $fakeLocalAppData
    $env:PATH = (($originalPath -split ';') |
        Where-Object { $_ -notmatch '(?i)Inno Setup' }) -join ';'
    $env:FAKE_INNO_OUTPUT = Join-Path $discoveryOutput 'Pomodoist-Setup.exe'
    & $buildScript `
        -BuildDirectory $bundle `
        -OutputDirectory $discoveryOutput `
        -Version '1.2.3'
    Assert-True `
        (Test-Path -LiteralPath $env:FAKE_INNO_OUTPUT) `
        'A user-scope Inno Setup compiler was not discovered.'

    $verifyContractScript = Join-Path $PSScriptRoot 'verify-contract.ps1'
    $installerSource = Join-Path $PSScriptRoot 'Pomodoist.iss'
    & $verifyContractScript
    & $verifyContractScript -Source $installerSource

    $invalidSource = Join-Path $testRoot 'invalid-Pomodoist.iss'
    (Get-Content -Raw -LiteralPath $installerSource).Replace(
        'PrivilegesRequired=lowest',
        'PrivilegesRequired=admin'
    ) | Set-Content -LiteralPath $invalidSource
    Assert-ThrowsContaining `
        -Action { & $verifyContractScript -Source $invalidSource } `
        -Expected 'PrivilegesRequired=lowest' `
        -Message 'Elevated installer source was not rejected.'

    $smokeScript = Join-Path $PSScriptRoot 'smoke.ps1'
    $missingInstaller = Join-Path $testRoot 'missing-installer.exe'
    Assert-ThrowsContaining `
        -Action { & $smokeScript -Installer $missingInstaller } `
        -Expected 'Installer was not found:' `
        -Message 'Smoke test did not reject a missing installer.'

    Write-Output 'Windows installer packaging tests passed.'
} finally {
    Remove-Item Env:FAKE_INNO_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_INNO_FIXTURE -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_INNO_OUTPUT -ErrorAction SilentlyContinue
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:PATH = $originalPath
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
