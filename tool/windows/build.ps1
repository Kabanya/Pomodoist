[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Profile', 'Release')]
    [string]$Configuration = 'Debug',
    [ValidateSet('production', 'development', 'staging')]
    [string]$Flavor = 'production',
    [string]$ConfigFile,
    [string]$Target,
    [string]$ReleaseSha,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'flavors.ps1')

if (-not [string]::IsNullOrWhiteSpace($ConfigFile) -and -not [System.IO.Path]::IsPathRooted($ConfigFile)) {
    $ConfigFile = Join-Path $repoRoot $ConfigFile
}

$Flavor = $Flavor.Trim().ToLowerInvariant()
$flavorConfig = Get-PomodoistFlavor -Flavor $Flavor

# The entry point and the flavor have to name the same environment: the app
# rejects a build whose entry point and compile-time flavor disagree, so the
# mismatch is reported here where the fix is obvious.
if ([string]::IsNullOrWhiteSpace($Target)) {
    $Target = $flavorConfig.EntryPoint
} else {
    $targetFlavor = Get-PomodoistFlavorForEntryPoint -EntryPoint $Target
    if ($null -eq $targetFlavor) {
        $knownTargets = @(
            $PomodoistFlavors.Keys | ForEach-Object { $PomodoistFlavors[$_].EntryPoint }
        ) -join ', '
        throw "-Target must be one of $knownTargets; got '$Target'."
    }
    if ($targetFlavor -cne $Flavor) {
        throw (
            "-Target '$Target' belongs to the $targetFlavor flavor, " +
            "but -Flavor $Flavor was requested. Pass -Flavor $targetFlavor."
        )
    }
}

function Invoke-DesktopReleaseConfigValidation {
    param([Parameter(Mandatory = $true)][string]$Path)

    $maximumAttempts = 3
    for ($attempt = 1; $attempt -le $maximumAttempts; $attempt++) {
        & dart (Join-Path $repoRoot 'tool\desktop_release_config.dart') --config $Path
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

Push-Location (Join-Path $repoRoot 'apps\flutter')
try {
    & (Join-Path $PSScriptRoot 'link-build.ps1')
    if ($Clean) {
        & flutter clean
        if ($LASTEXITCODE -ne 0) { throw 'flutter clean failed' }
        cmd /c rmdir "$repoRoot\apps\flutter\build" 2>$null
        Remove-Item -LiteralPath (Join-Path $repoRoot 'build\flutter') -Recurse -Force -ErrorAction SilentlyContinue
        cmd /c rmdir "$repoRoot\apps\flutter\.dart_tool" 2>$null
        Remove-Item -LiteralPath (Join-Path $repoRoot 'build\dart_tool') -Recurse -Force -ErrorAction SilentlyContinue
        & (Join-Path $PSScriptRoot 'link-build.ps1')
    }

    $resolvedConfig = $null
    if (-not [string]::IsNullOrWhiteSpace($ConfigFile)) {
        $resolvedConfig = (Resolve-Path $ConfigFile).Path
    }

    # --flavor is always passed, production included. Flutter inserts the flavor
    # into the output directory, and the packaging and release scripts resolve
    # the flavor's directory, so the two only agree while every build names its
    # flavor.
    $flutterArgs = @(
        'build', 'windows', "--$($Configuration.ToLowerInvariant())",
        '--flavor', $Flavor,
        '--target', $Target
    )
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
            throw 'Release builds require -ConfigFile with the dart-defines of their environment.'
        }
        if ($Flavor -ceq 'production') {
            # The production release is the only one that ships to users, so it
            # is the only one that has to prove its configuration is the
            # production one. A development or staging build legitimately names
            # a different environment, which this validator rejects.
            Invoke-DesktopReleaseConfigValidation -Path $resolvedConfig
            $flutterArgs += '--dart-define=POMODOIST_BILLING_CHANNEL=stripe'
        }
    }

    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows build failed.' }
} finally {
    Pop-Location
}
