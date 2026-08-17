[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [string]$ConfigFile,
    [string]$ReleaseSha,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

Push-Location $repoRoot
try {
    if ($Clean) {
        & flutter clean
        if ($LASTEXITCODE -ne 0) { throw 'flutter clean failed' }
    }

    $flutterArgs = @('build', 'windows', "--$($Configuration.ToLowerInvariant())")
    if ($Configuration -eq 'Release') {
        if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
            throw 'Release builds require -ConfigFile with production dart-defines.'
        }
        $resolvedConfig = (Resolve-Path $ConfigFile).Path
        if ([string]::IsNullOrWhiteSpace($ReleaseSha)) {
            $ReleaseSha = (& git rev-parse HEAD).Trim()
        }
        if ($ReleaseSha -notmatch '^[0-9a-fA-F]{40}$') {
            throw '-ReleaseSha must be a full 40-character Git commit SHA.'
        }
        $flutterArgs += "--dart-define-from-file=$resolvedConfig"
        $flutterArgs += "--dart-define=POMODOIST_RELEASE=$ReleaseSha"
        $flutterArgs += '--dart-define=POMODOIST_BILLING_CHANNEL=stripe'
    }

    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows build failed.' }
} finally {
    Pop-Location
}
