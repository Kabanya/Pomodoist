# Flavor identity shared by the Windows build, packaging and installer scripts.
#
# The table mirrors apps/flutter/lib/domain/models/app_flavor.dart; change both
# together. Every value here is frozen, so a flavor can be recognized by a
# running build, by its shortcut and by its installer.
#
# The flavor is passed to `flutter build windows --flavor <name>`, which is what
# makes Flutter write FLUTTER_APP_FLAVOR into the CMake configuration and insert
# the flavor segment into the build directory. `production` is the fallback when
# no flavor is named, matching a bare `flutter build windows`.
#
# This file is dot-sourced, never executed, and only defines data and functions.

$PomodoistFlavors = [ordered]@{
    production = [ordered]@{
        DisplayName    = 'Pomodoist'
        ApplicationId  = 'com.finchforge.pomodoist'
        UrlScheme      = 'pomodoist'
        ToastGuid      = '8681f633-939c-46f5-84cc-18f295e4382c'
        WindowClass    = 'FLUTTER_RUNNER_WIN32_WINDOW'
        EntryPoint     = 'lib/main.dart'
        IconFileName   = 'app_icon.ico'
        SetupBaseName  = 'Pomodoist-Setup'
        BuildDirectory = 'build\flutter\windows\x64\production\runner\Release'
    }
    staging = [ordered]@{
        DisplayName    = 'Pomodoist Stg'
        ApplicationId  = 'com.finchforge.pomodoist.stg'
        UrlScheme      = 'pomodoist-stg'
        ToastGuid      = 'b3c1d7a2-5e64-4f18-9a0b-2d7c6e1f8a34'
        WindowClass    = 'FLUTTER_RUNNER_WIN32_WINDOW_POMODOIST_STG'
        EntryPoint     = 'lib/main_staging.dart'
        IconFileName   = 'app_icon_staging.ico'
        SetupBaseName  = 'Pomodoist-Staging-Setup'
        BuildDirectory = 'build\flutter\windows\x64\staging\runner\Release'
    }
    development = [ordered]@{
        DisplayName    = 'Pomodoist Dev'
        ApplicationId  = 'com.finchforge.pomodoist.dev'
        UrlScheme      = 'pomodoist-dev'
        ToastGuid      = 'c4d2e8b3-6f75-4029-ab1c-3e8d7f209b45'
        WindowClass    = 'FLUTTER_RUNNER_WIN32_WINDOW_POMODOIST_DEV'
        EntryPoint     = 'lib/main_development.dart'
        IconFileName   = 'app_icon_development.ico'
        SetupBaseName  = 'Pomodoist-Development-Setup'
        BuildDirectory = 'build\flutter\windows\x64\development\runner\Release'
    }
}

# Returns the identity of the named flavor, or throws on an unrecognized name.
function Get-PomodoistFlavor {
    param([Parameter(Mandatory)][string]$Flavor)

    $normalized = $Flavor.Trim().ToLowerInvariant()
    if (-not $PomodoistFlavors.Contains($normalized)) {
        throw "Unknown Pomodoist flavor '$Flavor'. Use production, staging or development."
    }
    return $PomodoistFlavors[$normalized]
}

# Returns the name of the flavor that owns the given entry point, or $null when
# no flavor claims it.
function Get-PomodoistFlavorForEntryPoint {
    param([Parameter(Mandatory)][string]$EntryPoint)

    $candidate = $EntryPoint.Trim()
    foreach ($name in @($PomodoistFlavors.Keys)) {
        if ($PomodoistFlavors[$name].EntryPoint -ieq $candidate) {
            return $name
        }
    }
    return $null
}

# Deletes a reparse point without touching what it points at.
#
# Remove-Item follows a link and would delete the contents of its target, so the
# link has to be removed through the file system API. cmd.exe's `rmdir` removes
# only the link, but $ErrorActionPreference = 'Stop' turns every message it
# writes to stderr into a terminating error, and it reports an invalid directory
# name whenever the target is missing - the dangling state this repository has
# to repair after a fresh checkout and after `flutter clean`. The file system
# API never resolves the target; it reports a missing target per link, which the
# callers tolerate.
function Remove-PomodoistReparsePoint {
    param([Parameter(Mandatory)][string]$Path)

    [System.IO.Directory]::Delete($Path, $false)
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
}

# Replaces the named path with a reparse point at $Target.
function Set-PomodoistReparsePoint {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target,
        [switch]$Junction
    )

    New-Item -ItemType Directory -Force -Path $Target | Out-Null

    # An existing link that already names $Target is correct and stays.
    $attributes = $null
    try {
        $attributes = [System.IO.File]::GetAttributes($Path)
    } catch [System.IO.FileNotFoundException] {
    } catch [System.IO.DirectoryNotFoundException] {
    }
    if ($null -ne $attributes) {
        $resolved = $null
        if ($attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $resolved = (Get-Item -LiteralPath $Path -Force).Target
            if ($resolved -is [array]) { $resolved = $resolved[0] }
        }
        if ($resolved -ceq $Target) { return }
        Remove-PomodoistReparsePoint $Path
        # The link is gone even when the removal reported a missing target, so
        # anything still on the name is a plain entry left by an earlier
        # checkout and is cleared without following a link.
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($Junction) {
        New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
    } else {
        New-Item -ItemType SymbolicLink -Path $Path -Target $Target | Out-Null
    }
}
