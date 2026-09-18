[CmdletBinding()]
param(
    [string]$ConfigFile,
    [string]$Target = 'lib/main.dart'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not [string]::IsNullOrWhiteSpace($ConfigFile) -and -not [System.IO.Path]::IsPathRooted($ConfigFile)) {
    $ConfigFile = Join-Path $repoRoot $ConfigFile
}

$flutterArgs = @('run', '-d', 'windows', '--target', $Target)
if (-not [string]::IsNullOrWhiteSpace($ConfigFile)) {
    $flutterArgs += "--dart-define-from-file=$((Resolve-Path $ConfigFile).Path)"
}

Push-Location (Join-Path $repoRoot 'apps\flutter')
try {
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows run failed.' }
} finally {
    Pop-Location
}
