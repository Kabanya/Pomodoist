[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('x64', 'arm64')]
    [string]$Architecture,
    [Parameter(Mandatory)]
    [string]$Publisher,
    [Parameter(Mandatory)]
    [string]$Tag,
    [int]$PreviousBuildNumber = -1,
    [string]$OutputDirectory = 'build\windows\msix'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$outputPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputDirectory))
$metadataArgs = @(
    'run', 'tool/windows_release_config.dart', 'metadata',
    '--pubspec', 'pubspec.yaml',
    '--tag', $Tag
)
if ($PreviousBuildNumber -ge 0) {
    $metadataArgs += @('--previous-build', $PreviousBuildNumber.ToString())
}

Push-Location $repoRoot
try {
    $metadataJson = & dart @metadataArgs
    if ($LASTEXITCODE -ne 0) { throw 'Windows release metadata validation failed.' }
    $metadata = $metadataJson | ConvertFrom-Json
    New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

    & dart run msix:create `
        --release `
        --build-windows false `
        --architecture $Architecture `
        --version $metadata.msixVersion `
        --publisher $Publisher `
        --output-path $outputPath `
        --output-name "Pomodoist_$Architecture" `
        --sign-msix false `
        --install-certificate false
    if ($LASTEXITCODE -ne 0) { throw 'Unsigned MSIX packaging failed.' }
} finally {
    Pop-Location
}
