[CmdletBinding()]
param(
    [string]$Source
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $PSScriptRoot '..\flavors.ps1')

if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Join-Path $PSScriptRoot 'Pomodoist.iss'
}

if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    throw "Installer source was not found: $Source"
}
$contents = Get-Content -Raw -LiteralPath $Source
$lines = @(
    $contents -split '\r?\n' |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

# One source file compiles all three installers, so every identity value has to
# arrive through /D. These lines prove the placeholders reach the settings that
# define the install, the shortcut and the URL scheme.
$requiredLines = @(
    'AppId={#AppIdentifier}',
    'AppName={#AppDisplayName}',
    'AppVerName={#AppDisplayName} {#AppVersion}',
    'DefaultDirName={localappdata}\Programs\{#AppDisplayName}',
    'DefaultGroupName={#AppDisplayName}',
    'PrivilegesRequired=lowest',
    'PrivilegesRequiredOverridesAllowed=',
    'MinVersion=10.0.19041',
    'ArchitecturesAllowed=x64compatible',
    'ArchitecturesInstallIn64BitMode=x64compatible',
    'OutputBaseFilename={#SetupBaseFilename}',
    'UninstallDisplayName={#AppDisplayName}',
    'VersionInfoDescription={#AppDisplayName} installer',
    'VersionInfoProductName={#AppDisplayName}',
    'DisableStartupPrompt=yes',
    'DisableWelcomePage=yes',
    'DisableDirPage=yes',
    'DisableProgramGroupPage=yes',
    'DisableFinishedPage=yes',
    'AllowCancelDuringInstall=no',
    'ChangesAssociations=yes',
    'Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs',
    'Name: "{autoprograms}\{#AppDisplayName}"; Filename: "{app}\pomodoist.exe"; WorkingDir: "{app}"; AppUserModelID: "{#AppIdentifier}"; AppUserModelToastActivatorCLSID: "{#AppToastGuid}"',
    'Root: HKA; Subkey: "Software\Classes\{#AppUrlScheme}"; ValueType: string; ValueName: ""; ValueData: "URL:{#AppDisplayName} Protocol"; Flags: uninsdeletekey',
    'Root: HKA; Subkey: "Software\Classes\{#AppUrlScheme}"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""',
    'Root: HKA; Subkey: "Software\Classes\{#AppUrlScheme}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\pomodoist.exe"" ""%1"""',
    'Filename: "{app}\pomodoist.exe"; WorkingDir: "{app}"; Flags: nowait skipifsilent',
    'if CurPageID = wpReady then',
    'PostMessage(WizardForm.NextButton.Handle, BM_CLICK, 0, 0);'
)

foreach ($requiredLine in $requiredLines) {
    if ($lines -cnotcontains $requiredLine) {
        throw "Installer contract violation: expected $requiredLine"
    }
}

# A hardcoded production value would make every flavor compile a production
# installer, which is the failure the placeholders exist to prevent.
$forbiddenFragments = @(
    'AppId=com.finchforge.pomodoist',
    'Programs\Pomodoist',
    'OutputBaseFilename=Pomodoist-Setup',
    'Software\Classes\pomodoist',
    'Name: "{autoprograms}\Pomodoist"'
)

foreach ($forbiddenFragment in $forbiddenFragments) {
    if ($contents.Contains($forbiddenFragment)) {
        throw "Installer contract violation: the flavor identity must come from /D, but the source hardcodes $forbiddenFragment"
    }
}

function Assert-FileContains {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not (Get-Content -Raw -LiteralPath $Path).Contains($Expected)) {
        throw "$Message`nExpected to contain: $Expected`nFile: $Path"
    }
}

# The flavor table is deliberately duplicated: the Dart model is what the running
# application believes, the CMake table is what the runner compiles, and the
# PowerShell table in this directory is what the build and packaging scripts
# read. No job here compiles a Windows runner, so the copies are compared
# textually; a drift between any two of them is the exact bug the flavors exist
# to prevent.
$dartFlavorModel = Join-Path $repoRoot 'apps\flutter\lib\domain\models\app_flavor.dart'
$cmakeFlavorTable = Join-Path $repoRoot 'apps\flutter\windows\CMakeLists.txt'
$installerBuildScript = Join-Path $PSScriptRoot 'build.ps1'
foreach ($identityFile in @($dartFlavorModel, $cmakeFlavorTable, $installerBuildScript)) {
    if (-not (Test-Path -LiteralPath $identityFile -PathType Leaf)) {
        throw "Flavor identity file was not found: $identityFile"
    }
}

foreach ($flavorName in @($PomodoistFlavors.Keys)) {
    $flavorConfig = $PomodoistFlavors[$flavorName]
    foreach ($dartValue in @(
            $flavorConfig.DisplayName,
            $flavorConfig.ApplicationId,
            $flavorConfig.UrlScheme,
            $flavorConfig.ToastGuid,
            $flavorConfig.EntryPoint
        )) {
        Assert-FileContains `
            -Path $dartFlavorModel `
            -Expected "'$dartValue'" `
            -Message "The $flavorName flavor's '$dartValue' is missing from app_flavor.dart."
    }

    $cmakeVariables = [ordered]@{
        POMODOIST_FLAVOR_DISPLAY_NAME = $flavorConfig.DisplayName
        POMODOIST_FLAVOR_APPLICATION_ID = $flavorConfig.ApplicationId
        POMODOIST_FLAVOR_URL_SCHEME = $flavorConfig.UrlScheme
        POMODOIST_FLAVOR_TOAST_GUID = $flavorConfig.ToastGuid
        POMODOIST_FLAVOR_WINDOW_CLASS = $flavorConfig.WindowClass
    }
    foreach ($cmakeVariable in @($cmakeVariables.Keys)) {
        Assert-FileContains `
            -Path $cmakeFlavorTable `
            -Expected "set($cmakeVariable `"$($cmakeVariables[$cmakeVariable])`")" `
            -Message "The $flavorName flavor's $cmakeVariable is missing from windows/CMakeLists.txt."
    }
    Assert-FileContains `
        -Path $cmakeFlavorTable `
        -Expected "POMODOIST_FLAVOR_NAME STREQUAL `"$flavorName`"" `
        -Message "windows/CMakeLists.txt does not select the $flavorName flavor."
}

# The installer build script turns the table into /D arguments and the source
# file consumes them, so both halves of that hand-off are checked.
foreach ($compilerArgument in @(
        '/DAppIdentifier=$($flavorConfig.ApplicationId)',
        '/DAppDisplayName=$($flavorConfig.DisplayName)',
        '/DAppUrlScheme=$($flavorConfig.UrlScheme)',
        '/DAppToastGuid=$($flavorConfig.ToastGuid)',
        '/DSetupBaseFilename=$($flavorConfig.SetupBaseName)'
    )) {
    Assert-FileContains `
        -Path $installerBuildScript `
        -Expected $compilerArgument `
        -Message 'The installer build script must forward every flavor identity value to Inno Setup.'
}
foreach ($placeholder in @(
        '{#AppIdentifier}',
        '{#AppDisplayName}',
        '{#AppUrlScheme}',
        '{#AppToastGuid}',
        '{#SetupBaseFilename}'
    )) {
    if (-not $contents.Contains($placeholder)) {
        throw "Installer contract violation: $placeholder is never used by the installer source."
    }
}

# The scripts that install and exercise a build have to read the same table, or
# they would verify the production identity against a development installation.
foreach ($identityScript in @(
        (Join-Path $PSScriptRoot 'smoke.ps1'),
        (Join-Path $PSScriptRoot '..\test_deep_link_forwarding.ps1')
    )) {
    Assert-FileContains `
        -Path $identityScript `
        -Expected 'Get-PomodoistFlavor' `
        -Message 'Every script that exercises an installed build must resolve its identity from flavors.ps1.'
}

Write-Output 'Windows installer source contract verified.'
