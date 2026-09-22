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
