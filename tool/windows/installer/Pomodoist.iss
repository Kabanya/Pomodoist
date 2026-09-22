; Inno Setup script for the Pomodoist Windows installer.
;
; Every flavor-specific value is supplied by build.ps1 through /D, because the
; same script has to produce the production, staging and development installers.
; The flavor table lives in build.ps1; the guards below make a missing /D fail
; loudly at compile time instead of silently producing a production installer.
;
; Production supplies exactly the values this file used to hardcode, so its
; output is unchanged.

#ifndef AppVersion
  #error AppVersion must be provided by build.ps1
#endif
#ifndef AppNumericVersion
  #error AppNumericVersion must be provided by build.ps1
#endif
#ifndef SourceDir
  #error SourceDir must be provided by build.ps1
#endif
#ifndef OutputDir
  #error OutputDir must be provided by build.ps1
#endif
#ifndef SetupIcon
  #error SetupIcon must be provided by build.ps1
#endif
#ifndef AppIdentifier
  #error AppIdentifier must be provided by build.ps1
#endif
#ifndef AppDisplayName
  #error AppDisplayName must be provided by build.ps1
#endif
#ifndef AppUrlScheme
  #error AppUrlScheme must be provided by build.ps1
#endif
#ifndef AppToastGuid
  #error AppToastGuid must be provided by build.ps1
#endif
#ifndef SetupBaseFilename
  #error SetupBaseFilename must be provided by build.ps1
#endif

[Setup]
; AppId doubles as the uninstall registry key, so the three flavors get three
; independent entries and can be uninstalled separately.
AppId={#AppIdentifier}
AppName={#AppDisplayName}
AppVersion={#AppVersion}
AppVerName={#AppDisplayName} {#AppVersion}
AppPublisher=FinchForge LLC
AppPublisherURL=https://pomodoist.com
AppSupportURL=https://github.com/Kabanya/Pomodoist/issues
AppUpdatesURL=https://github.com/Kabanya/Pomodoist/releases
AppCopyright=Copyright (C) 2026 FinchForge LLC. Licensed under AGPL-3.0-only.
DefaultDirName={localappdata}\Programs\{#AppDisplayName}
DefaultGroupName={#AppDisplayName}
UsePreviousAppDir=no
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=
MinVersion=10.0.19041
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#SetupBaseFilename}
SetupIconFile={#SetupIcon}
UninstallDisplayName={#AppDisplayName}
UninstallDisplayIcon={app}\pomodoist.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
DisableStartupPrompt=yes
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=no
DisableFinishedPage=yes
AllowCancelDuringInstall=no
CloseApplications=yes
RestartApplications=no
RestartIfNeededByRun=no
ChangesAssociations=yes
SetupLogging=yes
VersionInfoCompany=FinchForge LLC
VersionInfoCopyright=Copyright (C) 2026 FinchForge LLC. Licensed under AGPL-3.0-only.
VersionInfoDescription={#AppDisplayName} installer
VersionInfoProductName={#AppDisplayName}
VersionInfoProductVersion={#AppNumericVersion}
VersionInfoVersion={#AppNumericVersion}
VersionInfoProductTextVersion={#AppVersion}
VersionInfoTextVersion={#AppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; The AppUserModelID has to equal the id the runner sets on itself, and the
; toast activator CLSID has to match the one the app registers, or the toast
; identity resolves to nothing. Both are flavor-specific so that three installs
; raise three distinguishable sets of notifications.
Name: "{autoprograms}\{#AppDisplayName}"; Filename: "{app}\pomodoist.exe"; WorkingDir: "{app}"; AppUserModelID: "{#AppIdentifier}"; AppUserModelToastActivatorCLSID: "{#AppToastGuid}"

[Registry]
; Each flavor claims its own URL scheme, so the three installs can coexist and
; each one's links resolve to it alone.
Root: HKA; Subkey: "Software\Classes\{#AppUrlScheme}"; ValueType: string; ValueName: ""; ValueData: "URL:{#AppDisplayName} Protocol"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\{#AppUrlScheme}"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\{#AppUrlScheme}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\pomodoist.exe,0"
Root: HKA; Subkey: "Software\Classes\{#AppUrlScheme}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\pomodoist.exe"" ""%1"""

[Run]
Filename: "{app}\pomodoist.exe"; WorkingDir: "{app}"; Flags: nowait skipifsilent

[Code]
const
  BM_CLICK = $00F5;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpReady then
  begin
    WizardForm.Visible := False;
    PostMessage(WizardForm.NextButton.Handle, BM_CLICK, 0, 0);
  end;
end;
