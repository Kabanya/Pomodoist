#!/usr/bin/env python3
"""Check the reset recipe on temporary files, without touching macOS state."""

import os
from pathlib import Path
import subprocess
import tempfile


project = Path(__file__).resolve().parent.parent
dry_run = subprocess.run(
    ["make", "--no-print-directory", "--dry-run", "macos-reset"],
    cwd=project, capture_output=True, text=True,
)
assert dry_run.returncode == 0, dry_run.stderr
recipe = dry_run.stdout
# Redirect the expanded recipe, never the real HOME environment variable.
recipe = recipe.replace("${HOME", "${POMODOIST_TEST_HOME").replace(
    "$HOME", "$POMODOIST_TEST_HOME"
)

with tempfile.TemporaryDirectory(prefix="pomodoist reset ") as temporary:
    root = Path(temporary)
    native = root / "bin"
    native.mkdir()
    for command, body in {
        "uname": 'echo "$POMODOIST_TEST_PLATFORM"',
        "pgrep": 'exit "$POMODOIST_TEST_PGREP"',
        "defaults": 'echo "defaults $*" >> "$POMODOIST_TEST_LOG"; exit 1',
        "tccutil": 'echo "tccutil $*" >> "$POMODOIST_TEST_LOG"',
        "rm": '''
for argument in "$@"; do
    case "$argument" in
        -rf|-f|"$POMODOIST_TEST_ROOT"/*) ;;
        *) echo 'Refusing deletion outside the temporary directory' >&2; exit 99 ;;
    esac
done
exec /bin/rm "$@"
''',
    }.items():
        executable = native / command
        executable.write_text("#!/bin/sh\n" + body + "\n")
        executable.chmod(0o755)

    data_home = root / "user data"
    app = "com.finchforge.pomodoist"
    deleted = [
        f"Library/Containers/{app}/Data/Documents/pomodoist.sqlite",
        f"Library/Containers/{app}/Data/Library/Preferences/{app}.plist",
        f"Library/Containers/{app}/Data/Library/Application Support/{app}/voice.wav",
        f"Library/Containers/{app}.focuswidget/Data/Library/Caches/snapshot",
        "Library/Group Containers/group.com.pomodoist/focus-snapshot-v1.json",
        "Library/Group Containers/group.com.pomodoist/Library/Preferences/group.com.pomodoist.plist",
        f"Library/Preferences/{app}.plist",
        f"Library/Application Support/{app}/session",
        f"Library/Caches/{app}/cache",
        f"Library/Saved Application State/{app}.savedState/window",
        "Documents/pomodoist.sqlite",
        "Documents/pomodoist.sqlite-wal",
        "Documents/pomodoist.sqlite-shm",
    ]
    kept = [
        "Documents/unrelated.txt",
        "Documents/pomodoist.sqlite.backup",
        "Library/Containers/com.example.other/Data/file",
        f"Library/Containers/{app}/.com.apple.containermanagerd.metadata.plist",
        "Library/Group Containers/group.com.pomodoist/.com.apple.containermanagerd.metadata.plist",
    ]
    for relative in deleted + kept:
        file = data_home / relative
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text("keep or reset")
    # Sandboxed Library folders contain links into the user's shared Library.
    (data_home / f"Library/Containers/{app}/Data/shared").symlink_to(
        data_home / "Documents", target_is_directory=True,
    )

    log = root / "native.log"
    environment = dict(os.environ, PATH=f"{native}:/usr/bin:/bin",
                       POMODOIST_TEST_HOME=str(data_home),
                       POMODOIST_TEST_ROOT=str(root),
                       POMODOIST_TEST_LOG=str(log))
    for platform, pgrep_status, reset_home in [
        ("Linux", "1", str(data_home)),
        ("Darwin", "0", str(data_home)),
        ("Darwin", "1", ""),
        ("Darwin", "1", "/"),
        ("Darwin", "1", str(data_home)),
        ("Darwin", "1", str(data_home)),
    ]:
        environment.update(POMODOIST_TEST_PLATFORM=platform,
                           POMODOIST_TEST_PGREP=pgrep_status,
                           POMODOIST_TEST_HOME=reset_home)
        result = subprocess.run(["/bin/sh", "-e", "-c", recipe],
                                env=environment, capture_output=True, text=True)
        blocked = platform != "Darwin" or pgrep_status == "0" or reset_home in ("", "/")
        assert (result.returncode != 0) == blocked, result.stdout + result.stderr
        assert all((data_home / item).exists() == blocked for item in deleted)
        assert all((data_home / item).is_file() for item in kept)
        if blocked:
            assert not log.exists(), "Native settings changed before validation"
        else:
            assert f"tccutil reset All {app}\n" in log.read_text()

print("macOS reset check passed: guards, cleanup scope, symlinks and repeat runs.")
