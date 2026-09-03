[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Profile', 'Release')]
    [string]$Configuration = 'Debug',
    [string]$ConfigFile,
    [string]$ReleaseSha,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Invoke-DesktopReleaseConfigValidation {
    param([Parameter(Mandatory = $true)][string]$Path)

    $maximumAttempts = 3
    for ($attempt = 1; $attempt -le $maximumAttempts; $attempt++) {
        & dart tool/desktop_release_config.dart --config $Path
        $validationExitCode = $LASTEXITCODE
        if ($validationExitCode -eq 0) {
            return
        }
        if ($validationExitCode -ne 255 -or $attempt -eq $maximumAttempts) {
            throw 'Desktop production configuration validation failed.'
        }

        Write-Warning (
            "Desktop build hook failed with exit code 255. " +
            "Retrying ($attempt/$maximumAttempts)..."
        )
        Start-Sleep -Seconds $attempt
    }
}

Push-Location $repoRoot
try {
    if ($Clean) {
        & flutter clean
        if ($LASTEXITCODE -ne 0) { throw 'flutter clean failed' }
        $buildDirectory = Join-Path $repoRoot 'build'
        if (Test-Path -LiteralPath $buildDirectory) {
            throw "flutter clean did not remove $buildDirectory. Close processes using the build directory and retry."
        }
    }

    $resolvedConfig = $null
    if (-not [string]::IsNullOrWhiteSpace($ConfigFile)) {
        $resolvedConfig = (Resolve-Path $ConfigFile).Path
    }

    $flutterArgs = @('build', 'windows', "--$($Configuration.ToLowerInvariant())")
    if ($null -ne $resolvedConfig) {
        $flutterArgs += "--dart-define-from-file=$resolvedConfig"
    }
    if ([string]::IsNullOrWhiteSpace($ReleaseSha)) {
        $ReleaseSha = (& git rev-parse HEAD).Trim()
    }
    if ($ReleaseSha -notmatch '^[0-9a-fA-F]{40}$') {
        throw '-ReleaseSha must be a full 40-character Git commit SHA.'
    }
    $flutterArgs += "--dart-define=POMODOIST_RELEASE=$ReleaseSha"
    if ($Configuration -eq 'Release') {
        if ($null -eq $resolvedConfig) {
            throw 'Release builds require -ConfigFile with production dart-defines.'
        }
        Invoke-DesktopReleaseConfigValidation -Path $resolvedConfig
        $flutterArgs += '--dart-define=POMODOIST_BILLING_CHANNEL=stripe'
    }

    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows build failed.' }
} finally {
    Pop-Location
}
