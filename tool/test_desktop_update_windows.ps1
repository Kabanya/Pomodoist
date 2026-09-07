# Executes the exact helper bundled in Dart with real Windows fixture executables.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $root 'lib/features/updates/update_install_scripts.dart') -Raw
$match = [regex]::Match($source, "(?s)const windowsUpdateScript = r'''\r?\n(.*?)''';")
if (-not $match.Success) { throw 'Could not extract bundled Windows helper.' }
$base = Join-Path ([IO.Path]::GetTempPath()) ("Pomodoist updater's test " + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $base | Out-Null
$appSource = @'
using System;
using System.IO;
public class FixtureApp {
  public static int Main() {
    string marker = Environment.GetEnvironmentVariable("POMODOIST_UPDATE_READY_FILE");
    if (!String.IsNullOrEmpty(marker)) File.WriteAllText(marker, "started");
    File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "launched"), "yes");
    return 0;
  }
}
'@
$installerSource = @'
using System;
using System.IO;
public class FixtureInstaller {
  public static int Main(string[] args) {
    string dir = null;
    foreach (string arg in args) if (arg.StartsWith("/DIR=")) dir = arg.Substring(5).Trim('"');
    if (String.IsNullOrEmpty(dir) || !Array.Exists(args, x => x == "/NORESTART") ||
        !Array.Exists(args, x => x == "/NOCLOSEAPPLICATIONS")) return 64;
    File.WriteAllText(Path.Combine(dir, "version"), "new");
    string mode = Environment.GetEnvironmentVariable("POMODOIST_UPDATER_TEST_MODE");
    if (mode == "fail") return 7;
    if (mode == "broken") File.WriteAllText(Path.Combine(dir, "pomodoist.exe"), "not an executable");
    return 0;
  }
}
'@
function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}
try {
  $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
  foreach ($entry in @(@('app', $appSource), @('installer', $installerSource))) {
    $cs = Join-Path $base ($entry[0] + '.cs')
    $exe = Join-Path $base ($entry[0] + '.exe')
    [IO.File]::WriteAllText($cs, $entry[1])
    & $compiler /nologo /target:exe "/out:$exe" $cs
    if ($LASTEXITCODE -ne 0) { throw 'Fixture compilation failed.' }
  }
  $checks = 0
  foreach ($mode in @('success', 'fail', 'broken', 'hash', 'cancel')) {
    $case = Join-Path $base $mode
    $install = Join-Path $case 'Pomodoist'
    $stage = Join-Path $case '.pomodoist-update-test'
    New-Item -ItemType Directory -Path $install, $stage | Out-Null
    $app = Join-Path $install 'pomodoist.exe'
    $installer = Join-Path $stage 'Pomodoist-Setup.exe'
    Copy-Item -LiteralPath (Join-Path $base 'app.exe') -Destination $app
    Copy-Item -LiteralPath (Join-Path $base 'installer.exe') -Destination $installer
    [IO.File]::WriteAllText((Join-Path $install 'version'), 'old')
    $data = Join-Path $case 'user-data'
    [IO.File]::WriteAllText($data, 'tasks settings auth')
    $helper = Join-Path $stage 'install.ps1'
    [IO.File]::WriteAllText($helper, $match.Groups[1].Value)
    $hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
    if ($mode -eq 'hash') { $hash = '0' * 64 }
    $env:POMODOIST_UPDATER_TEST_MODE = $mode
    $parentId = 2147483647
    if ($mode -eq 'cancel') {
      $parentId = $PID
      [IO.File]::WriteAllText((Join-Path $stage 'cancel'), 'cancel')
    }
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper `
      -ParentProcessId $parentId -ApplicationPath $app -InstallerPath $installer -Sha256 $hash
    $code = $LASTEXITCODE
    if ($mode -eq 'success') {
      Assert-True ($code -eq 0) 'Successful update helper failed.'
      Assert-True ((Get-Content -LiteralPath (Join-Path $install 'version') -Raw) -eq 'new') 'New version not installed.'
      Assert-True ((Get-Content -LiteralPath (Join-Path $stage 'result') -Raw).Trim() -eq 'success') 'Missing successful health check.'
    } else {
      Assert-True ($code -ne 0) "Expected rejection for $mode."
      Assert-True ((Get-Content -LiteralPath (Join-Path $install 'version') -Raw) -eq 'old') "Old version not preserved for $mode."
      Assert-True ((Get-FileHash -LiteralPath $app).Hash -eq (Get-FileHash -LiteralPath (Join-Path $base 'app.exe')).Hash) "Old executable not restored for $mode."
    }
    Assert-True ((Get-Content -LiteralPath $data -Raw) -eq 'tasks settings auth') 'User data was modified.'
    $checks++
    Write-Host "PASS: Windows helper $mode"
  }
  Write-Host "$checks Windows integration scenarios passed."
} finally {
  Remove-Item Env:POMODOIST_UPDATER_TEST_MODE -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 500
  Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}

# Expected negative-case exit codes were asserted above. Do not leak the final
# fixture's nonzero exit code into GitHub Actions' PowerShell wrapper.
exit 0
