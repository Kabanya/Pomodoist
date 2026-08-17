[CmdletBinding()]
param(
    [string]$Source
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
$requiredLines = @(
    'AppId=com.finchforge.pomodoist',
    'DefaultDirName={localappdata}\Programs\Pomodoist',
    'PrivilegesRequired=lowest',
    'PrivilegesRequiredOverridesAllowed=',
    'MinVersion=10.0.19041',
    'ArchitecturesAllowed=x64compatible',
    'ArchitecturesInstallIn64BitMode=x64compatible',
    'OutputBaseFilename=Pomodoist-Setup',
    'DisableStartupPrompt=yes',
    'DisableWelcomePage=yes',
    'DisableDirPage=yes',
    'DisableProgramGroupPage=yes',
    'DisableFinishedPage=yes',
    'AllowCancelDuringInstall=no',
    'ChangesAssociations=yes',
    'Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs',
    'Name: "{autoprograms}\Pomodoist"; Filename: "{app}\pomodoist.exe"; WorkingDir: "{app}"; AppUserModelID: "com.finchforge.pomodoist"; AppUserModelToastActivatorCLSID: "8681f633-939c-46f5-84cc-18f295e4382c"',
    'Root: HKA; Subkey: "Software\Classes\pomodoist"; ValueType: string; ValueName: ""; ValueData: "URL:Pomodoist Protocol"; Flags: uninsdeletekey',
    'Root: HKA; Subkey: "Software\Classes\pomodoist"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""',
    'Root: HKA; Subkey: "Software\Classes\pomodoist\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\pomodoist.exe"" ""%1"""',
    'Filename: "{app}\pomodoist.exe"; WorkingDir: "{app}"; Flags: nowait skipifsilent',
    'if CurPageID = wpReady then',
    'PostMessage(WizardForm.NextButton.Handle, BM_CLICK, 0, 0);'
)

foreach ($requiredLine in $requiredLines) {
    if ($lines -cnotcontains $requiredLine) {
        throw "Installer contract violation: expected $requiredLine"
    }
}

Write-Output 'Windows installer source contract verified.'
