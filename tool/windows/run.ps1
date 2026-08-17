[CmdletBinding()]
param(
    [string]$ConfigFile
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$flutterArgs = @('run', '-d', 'windows')
if (-not [string]::IsNullOrWhiteSpace($ConfigFile)) {
    $flutterArgs += "--dart-define-from-file=$((Resolve-Path $ConfigFile).Path)"
}

Push-Location $repoRoot
try {
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows run failed.' }
} finally {
    Pop-Location
}
