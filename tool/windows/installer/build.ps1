[CmdletBinding()]
param(
    [ValidateSet('production', 'development', 'staging')]
    [string]$Flavor = 'production',
    [string]$BuildDirectory,
    [string]$OutputDirectory = 'build\flutter\windows\installer',
    [string]$CompilerPath,
    [string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $PSScriptRoot '..\flavors.ps1')

$Flavor = $Flavor.Trim().ToLowerInvariant()
$flavorConfig = Get-PomodoistFlavor -Flavor $Flavor

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

# Each flavor is packaged from the directory Flutter writes when that flavor is
# built, so the three installers never package each other's bundle.
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = $flavorConfig.BuildDirectory
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

$number = '(?:0|[1-9][0-9]*)'
$versionPattern = "$number\.$number\.$number(?:-rc\.$number)?"
if ([string]::IsNullOrWhiteSpace($Version)) {
    $pubspecPath = Join-Path $repoRoot 'apps\flutter\pubspec.yaml'
    $versionMatch = [regex]::Match(
        (Get-Content -Raw -LiteralPath $pubspecPath),
        "(?m)^version:[ \t]*($versionPattern)\+[0-9]+[ \t]*\r?$"
    )
    if (-not $versionMatch.Success) {
        throw 'pubspec.yaml must contain version: X.Y.Z+N or X.Y.Z-rc.N+N'
    }
    $Version = $versionMatch.Groups[1].Value
}
if ($Version -cnotmatch "^$versionPattern\z") {
    throw '-Version must use X.Y.Z or X.Y.Z-rc.N format without leading zeros.'
}
$numericVersion = ($Version -split '-', 2)[0] + '.0'

$outputPath = Resolve-RepositoryPath $OutputDirectory
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
$installerName = "$($flavorConfig.SetupBaseName).exe"
$installerPath = Join-Path $outputPath $installerName
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
$iconPath = Join-Path `
    $repoRoot `
    "apps\flutter\windows\runner\resources\$($flavorConfig.IconFileName)"
foreach ($requiredPath in @($sourcePath, $iconPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Installer input was not found: $requiredPath"
    }
}

$compilerArguments = @(
    "/DAppVersion=$Version",
    "/DAppNumericVersion=$numericVersion",
    "/DSourceDir=$buildPath",
    "/DOutputDir=$outputPath",
    "/DSetupIcon=$iconPath",
    "/DAppIdentifier=$($flavorConfig.ApplicationId)",
    "/DAppDisplayName=$($flavorConfig.DisplayName)",
    "/DAppUrlScheme=$($flavorConfig.UrlScheme)",
    "/DAppToastGuid=$($flavorConfig.ToastGuid)",
    "/DSetupBaseFilename=$($flavorConfig.SetupBaseName)",
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
    "$hash *$installerName`n",
    [System.Text.Encoding]::ASCII
)

Write-Output $installerPath
