[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Bundle,
    [Parameter(Mandatory)]
    [string]$Publisher,
    [Parameter(Mandatory)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$bundlePath = (Resolve-Path $Bundle).Path
$verifyPath = [System.IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'build\windows\verify-bundle')
)
if (-not $verifyPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Bundle verification path escaped the repository.'
}

$kitsBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
function Find-WindowsSdkTool([string]$Name) {
    $tool = Get-ChildItem -LiteralPath $kitsBin -Filter $Name -Recurse |
        Where-Object { $_.FullName -match "\\x64\\$([regex]::Escape($Name))$" } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($null -eq $tool) { throw "$Name was not found in Windows Kits." }
    return $tool.FullName
}

$signature = Get-AuthenticodeSignature -LiteralPath $bundlePath
if ($signature.Status -ne 'Valid') {
    throw "Bundle signature is not trusted: $($signature.Status)"
}
if ($signature.SignerCertificate.Subject -ne $Publisher) {
    throw "Signed publisher '$($signature.SignerCertificate.Subject)' does not match '$Publisher'."
}

$signTool = Find-WindowsSdkTool 'signtool.exe'
& $signTool verify /pa /all /v $bundlePath
if ($LASTEXITCODE -ne 0) { throw 'SignTool verification failed.' }

if (Test-Path -LiteralPath $verifyPath) {
    Remove-Item -LiteralPath $verifyPath -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $verifyPath | Out-Null
$makeAppx = Find-WindowsSdkTool 'makeappx.exe'
& $makeAppx unbundle /p $bundlePath /d $verifyPath /o
if ($LASTEXITCODE -ne 0) { throw 'MakeAppx could not unbundle the release.' }

$architectures = [System.Collections.Generic.HashSet[string]]::new()
$packages = Get-ChildItem -LiteralPath $verifyPath -Filter *.msix
if ($packages.Count -ne 2) { throw "Expected two MSIX slices, found $($packages.Count)." }

foreach ($package in $packages) {
    $slicePath = Join-Path $verifyPath $package.BaseName
    & $makeAppx unpack /p $package.FullName /d $slicePath /o | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not unpack $($package.Name)." }
    [xml]$manifest = Get-Content -Raw -LiteralPath (Join-Path $slicePath 'AppxManifest.xml')
    $identity = $manifest.Package.Identity
    if ($identity.Name -ne 'com.finchforge.pomodoist') { throw 'Unexpected package identity.' }
    if ($identity.Publisher -ne $Publisher) { throw 'Manifest publisher mismatch.' }
    if ($identity.Version -ne $Version) { throw 'Manifest version mismatch.' }
    [void]$architectures.Add($identity.ProcessorArchitecture)

    $family = $manifest.Package.Dependencies.TargetDeviceFamily
    if ($family.MinVersion -ne '10.0.19041.0') { throw 'Unexpected minimum Windows version.' }
    $protocol = $manifest.SelectSingleNode("//*[local-name()='Protocol' and @Name='pomodoist']")
    if ($null -eq $protocol) { throw 'pomodoist protocol activation is missing.' }
}

if (-not $architectures.SetEquals([string[]]@('x64', 'arm64'))) {
    throw "Unexpected bundle architectures: $($architectures -join ', ')."
}
Write-Output "Verified $bundlePath ($Version; x64, arm64; $Publisher)"
