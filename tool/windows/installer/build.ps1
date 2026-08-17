[CmdletBinding()]
param(
    [string]$BuildDirectory = 'build\windows\x64\runner\Release',
    [string]$OutputDirectory = 'build\windows\installer',
    [string]$CompilerPath,
    [string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

function Resolve-RepositoryPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function Find-InnoCompiler {
    $command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'))
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'))
    }
    foreach ($programFiles in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
        if ([string]::IsNullOrWhiteSpace($programFiles)) { continue }
        $candidates.Add((Join-Path $programFiles 'Inno Setup 7\ISCC.exe'))
        $candidates.Add((Join-Path $programFiles 'Inno Setup 6\ISCC.exe'))
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'ISCC.exe was not found. Install Inno Setup 6.4 or newer.'
}

$buildPath = Resolve-RepositoryPath $BuildDirectory
if (-not (Test-Path -LiteralPath $buildPath -PathType Container)) {
    throw "Flutter Windows build directory was not found: $buildPath"
}
foreach ($relativePath in @('pomodoist.exe', 'flutter_windows.dll', 'data')) {
    $requiredPath = Join-Path $buildPath $relativePath
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Flutter Windows build is incomplete; missing $relativePath"
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
    $versionMatch = [regex]::Match(
        (Get-Content -Raw -LiteralPath $pubspecPath),
        '(?m)^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$'
    )
    if (-not $versionMatch.Success) {
        throw 'pubspec.yaml must contain version: X.Y.Z+N'
    }
    $Version = $versionMatch.Groups[1].Value
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw '-Version must use X.Y.Z format.'
}

$outputPath = Resolve-RepositoryPath $OutputDirectory
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
$installerPath = Join-Path $outputPath 'Pomodoist-Setup.exe'
$checksumPath = "$installerPath.sha256"
foreach ($generatedPath in @($installerPath, $checksumPath)) {
    if (Test-Path -LiteralPath $generatedPath) {
        Remove-Item -LiteralPath $generatedPath -Force
    }
}

if ([string]::IsNullOrWhiteSpace($CompilerPath)) {
    $CompilerPath = Find-InnoCompiler
} else {
    $CompilerPath = (Resolve-Path -LiteralPath $CompilerPath).Path
}

$sourcePath = Join-Path $PSScriptRoot 'Pomodoist.iss'
$iconPath = Join-Path $repoRoot 'windows\runner\resources\app_icon.ico'
foreach ($requiredPath in @($sourcePath, $iconPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Installer input was not found: $requiredPath"
    }
}

$compilerArguments = @(
    "/DAppVersion=$Version",
    "/DSourceDir=$buildPath",
    "/DOutputDir=$outputPath",
    "/DSetupIcon=$iconPath",
    $sourcePath
)
& $CompilerPath @compilerArguments
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compiler failed with exit code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Inno Setup did not produce $installerPath"
}

$hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
[System.IO.File]::WriteAllText(
    $checksumPath,
    "$hash *Pomodoist-Setup.exe`n",
    [System.Text.Encoding]::ASCII
)

Write-Output $installerPath
