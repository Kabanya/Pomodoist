// Bundled helpers, not downloaded code. Arguments are passed as an argv vector.
// Keep these scripts independently executable: tool tests run these exact bytes.
const linuxUpdateScript = r'''
#!/bin/sh
set -eu
umask 077
[ "$#" -eq 4 ] || exit 64
parent=$1
target=$2
payload=$3
expected=$4
case "$parent" in ''|*[!0-9]*|0|1) exit 64 ;; esac
case "$target" in /*) ;; *) exit 64 ;; esac
[ -f "$target" ] && [ ! -L "$target" ] || exit 65
[ -f "$payload" ] && [ ! -L "$payload" ] || exit 65
stage=$(CDPATH= cd -- "$(dirname -- "$payload")" && pwd -P)
appdir=$(CDPATH= cd -- "$(dirname -- "$target")" && pwd -P)
case "$stage" in "$appdir"/.pomodoist-update-*) ;; *) exit 65 ;; esac
[ "$(dirname -- "$stage")" = "$appdir" ] || exit 65
[ "${#expected}" -eq 64 ] || exit 65
case "$expected" in *[!a-fA-F0-9]*) exit 65 ;; esac
actual=$(sha256sum < "$payload")
actual=${actual%% *}
[ "$actual" = "$expected" ] || exit 66
# Never inherit paths into the old AppImage's soon-to-be-unmounted AppDir.
unset APPIMAGE APPDIR ARGV0 OWD LD_LIBRARY_PATH LD_PRELOAD
unset GSETTINGS_SCHEMA_DIR GIO_EXTRA_MODULES GDK_PIXBUF_MODULE_FILE GTK_PATH
lock="$target.update-lock"
if ! mkdir -- "$lock" 2>/dev/null; then
  # Recover only our own stale lock, not an arbitrary directory or symlink.
  [ -d "$lock" ] && [ ! -L "$lock" ] && [ -f "$lock/pid" ] || exit 73
  owner=$(cat -- "$lock/pid")
  case "$owner" in ''|*[!0-9]*|0|1) exit 73 ;; esac
  kill -0 "$owner" 2>/dev/null && exit 73
  rm -- "$lock/pid"
  rmdir -- "$lock"
  mkdir -- "$lock"
fi
printf '%s\n' "$$" > "$lock/pid"
backup="$stage/previous.AppImage"
replaced=false
finished=false
child=''
cleanup() {
  code=$?
  trap - EXIT HUP INT TERM
  if [ "$finished" != true ]; then
    printf 'failed\n' > "$stage/result"
    if [ "$replaced" = true ]; then
      if [ -n "$child" ]; then
        kill "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
      fi
      # Rename back on the same filesystem. Never remove the target first.
      if mv -f -- "$backup" "$target"; then
        POMODOIST_UPDATE_ERROR=1 "$target" >/dev/null 2>&1 &
      fi
    fi
  fi
  rm -f -- "$lock/pid"
  rmdir -- "$lock" 2>/dev/null || true
  if [ "$finished" = true ]; then printf 'success\n' > "$stage/result"; fi
  exit "$code"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
printf 'ready\n' > "$stage/ready"
tries=0
while kill -0 "$parent" 2>/dev/null; do
  [ ! -e "$stage/cancel" ] || exit 75
  tries=$((tries + 1))
  [ "$tries" -lt 120 ] || exit 75
  sleep 1
done
[ ! -e "$stage/cancel" ] || exit 75
# Check again after the old process exits, before touching its executable.
actual=$(sha256sum < "$payload")
[ "${actual%% *}" = "$expected" ] || exit 66
chmod 755 -- "$payload"
# A hardlink is fast and survives an interruption; copy on filesystems without it.
ln -- "$target" "$backup" 2>/dev/null || cp -p -- "$target" "$backup"
sync
mv -f -- "$payload" "$target"
replaced=true
sync
POMODOIST_UPDATE_READY_FILE="$stage/started" "$target" > "$stage/startup.log" 2>&1 &
child=$!
tries=0
while [ ! -f "$stage/started" ]; do
  kill -0 "$child" 2>/dev/null || exit 70
  tries=$((tries + 1))
  [ "$tries" -lt 60 ] || exit 70
  sleep 1
done
finished=true
rm -f -- "$backup" || true
''';

const windowsUpdateScript = r'''
param(
  [Parameter(Mandatory=$true)][int]$ParentProcessId,
  [Parameter(Mandatory=$true)][string]$ApplicationPath,
  [Parameter(Mandatory=$true)][string]$InstallerPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$Sha256
)
$ErrorActionPreference = 'Stop'
$stage = Split-Path -Parent $InstallerPath
$installDir = Split-Path -Parent $ApplicationPath
$backup = Join-Path $stage 'previous'
$lock = $null
$changed = $false
$started = $null
$oldExited = $false
$finished = $false
try {
  if ($ParentProcessId -le 1 -or
      -not [IO.Path]::IsPathRooted($ApplicationPath) -or
      -not [IO.Path]::IsPathRooted($InstallerPath) -or
      [IO.Path]::GetFileName($ApplicationPath) -ine 'pomodoist.exe' -or
      -not (Test-Path -LiteralPath $ApplicationPath -PathType Leaf) -or
      -not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
    throw 'Invalid update paths or process.'
  }
  foreach ($path in @($installDir, $ApplicationPath, $InstallerPath, $stage)) {
    if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) {
      throw 'Updates through reparse points are not supported.'
    }
  }
  if ((Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash -ine $Sha256) {
    throw 'Installer SHA-256 mismatch.'
  }
  $lock = [IO.File]::Open($installDir + '.update-lock',
    [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  'ready' | Set-Content -LiteralPath (Join-Path $stage 'ready')
  $deadline = [DateTime]::UtcNow.AddSeconds(120)
  while (Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue) {
    if ((Test-Path -LiteralPath (Join-Path $stage 'cancel')) -or
        [DateTime]::UtcNow -gt $deadline) { throw 'Application exit was cancelled.' }
    Start-Sleep -Milliseconds 200
  }
  if (Test-Path -LiteralPath (Join-Path $stage 'cancel')) {
    throw 'Application exit was cancelled.'
  }
  $oldExited = $true
  if ((Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash -ine $Sha256) {
    throw 'Installer changed after verification.'
  }
  # Never force-close another application instance or overwrite locked files.
  $others = @(Get-Process -Name 'pomodoist' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -ieq $ApplicationPath })
  if ($others.Count -gt 0) { throw 'Another Pomodoist instance is still running.' }
  Copy-Item -LiteralPath $installDir -Destination $backup -Recurse
  $changed = $true
  $arguments = @('/SILENT', '/SUPPRESSMSGBOXES', '/SP-', '/NORESTART',
    '/NOCLOSEAPPLICATIONS', '/NORESTARTAPPLICATIONS', '/RESTARTEXITCODE=3010',
    ('/DIR="' + $installDir + '"'), ('/LOG="' + (Join-Path $stage 'install.log') + '"'))
  $installer = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru
  if ($installer.ExitCode -ne 0) {
    throw ('Installer failed or requires a reboot: ' + $installer.ExitCode)
  }
  $env:POMODOIST_UPDATE_READY_FILE = Join-Path $stage 'started'
  $started = Start-Process -FilePath $ApplicationPath -WorkingDirectory $installDir -PassThru
  Remove-Item Env:POMODOIST_UPDATE_READY_FILE
  $deadline = [DateTime]::UtcNow.AddSeconds(60)
  while (-not (Test-Path -LiteralPath (Join-Path $stage 'started'))) {
    if ($started.HasExited -or [DateTime]::UtcNow -gt $deadline) {
      throw 'The updated application did not start.'
    }
    Start-Sleep -Milliseconds 200
  }
  # Cleanup failure must not roll back an application that started successfully.
  Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
  $finished = $true
} catch {
  $_ | Out-String | Set-Content -LiteralPath (Join-Path $stage 'error.log')
  'failed' | Set-Content -LiteralPath (Join-Path $stage 'result')
  if ($changed) {
    if ($null -ne $started -and -not $started.HasExited) {
      Stop-Process -Id $started.Id -Force -ErrorAction SilentlyContinue
      $started.WaitForExit()
    }
    # The old binary and all bundled libraries were copied before installation.
    # Keep both copies on restore failure for recovery; never delete the backup.
    $failed = Join-Path $stage 'failed-install'
    Move-Item -LiteralPath $installDir -Destination $failed
    Move-Item -LiteralPath $backup -Destination $installDir
  }
  if ($oldExited -and (Test-Path -LiteralPath $ApplicationPath)) {
    $env:POMODOIST_UPDATE_ERROR = '1'
    Remove-Item Env:POMODOIST_UPDATE_READY_FILE -ErrorAction SilentlyContinue
    Start-Process -FilePath $ApplicationPath -WorkingDirectory $installDir
  }
  exit 1
} finally {
  if ($null -ne $lock) { $lock.Dispose() }
  if ($finished) { 'success' | Set-Content -LiteralPath (Join-Path $stage 'result') }
}
''';
