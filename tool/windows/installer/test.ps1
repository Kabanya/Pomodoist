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
    $versionResources = Join-Path $versionRepo 'windows\runner\resources'
    New-Item -ItemType Directory -Force $versionTools, $versionResources | Out-Null
    Copy-Item -LiteralPath $buildScript -Destination $versionTools
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Pomodoist.iss') -Destination $versionTools
    Copy-Item -LiteralPath (Join-Path $repoRoot 'windows\runner\resources\app_icon.ico') -Destination $versionResources
    Set-Content -LiteralPath (Join-Path $versionRepo 'pubspec.yaml') -Value 'version: 1.2.3-rc.1+91'
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
