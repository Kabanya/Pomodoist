[CmdletBinding()]
param(
    [ValidateSet('production', 'development', 'staging')]
    [string]$Flavor = 'production',
    [string]$ConfigFile,
    [string]$Target
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'flavors.ps1')

if (-not [string]::IsNullOrWhiteSpace($ConfigFile) -and -not [System.IO.Path]::IsPathRooted($ConfigFile)) {
    $ConfigFile = Join-Path $repoRoot $ConfigFile
}

$Flavor = $Flavor.Trim().ToLowerInvariant()
$flavorConfig = Get-PomodoistFlavor -Flavor $Flavor

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

# Without --flavor the running build reports the production identity, so a
# staging or development run would present the production window title, taskbar
# button and deep-link scheme.
$flutterArgs = @('run', '-d', 'windows', '--flavor', $Flavor, '--target', $Target)
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
