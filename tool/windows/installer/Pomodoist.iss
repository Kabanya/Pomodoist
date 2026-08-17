#ifndef AppVersion
  #error AppVersion must be provided by build.ps1
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

[Setup]
AppId=com.finchforge.pomodoist
AppName=Pomodoist
AppVersion={#AppVersion}
AppVerName=Pomodoist {#AppVersion}
AppPublisher=FinchForge LLC
AppPublisherURL=https://pomodoist.com
AppSupportURL=https://github.com/Kabanya/Pomodoist/issues
AppUpdatesURL=https://github.com/Kabanya/Pomodoist/releases
AppCopyright=Copyright (C) 2026 FinchForge LLC. Licensed under AGPL-3.0-only.
DefaultDirName={localappdata}\Programs\Pomodoist
DefaultGroupName=Pomodoist
UsePreviousAppDir=no
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=
MinVersion=10.0.19041
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Pomodoist-Setup
SetupIconFile={#SetupIcon}
UninstallDisplayName=Pomodoist
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
VersionInfoDescription=Pomodoist installer
VersionInfoProductName=Pomodoist
VersionInfoProductVersion={#AppVersion}
VersionInfoVersion={#AppVersion}

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Pomodoist"; Filename: "{app}\pomodoist.exe"; WorkingDir: "{app}"; AppUserModelID: "com.finchforge.pomodoist"; AppUserModelToastActivatorCLSID: "8681f633-939c-46f5-84cc-18f295e4382c"

[Registry]
Root: HKA; Subkey: "Software\Classes\pomodoist"; ValueType: string; ValueName: ""; ValueData: "URL:Pomodoist Protocol"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\pomodoist"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\pomodoist\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\pomodoist.exe,0"
Root: HKA; Subkey: "Software\Classes\pomodoist\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\pomodoist.exe"" ""%1"""

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
