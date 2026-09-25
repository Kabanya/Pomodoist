#!/usr/bin/env python3
"""Check simulator launcher recipes with fake Xcode bundles; never open an app."""

import os
from pathlib import Path
import subprocess
import tempfile


project = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="pomodoist simulator ") as temporary:
    root = Path(temporary)
    native = root / "bin"
    native.mkdir()
    developer = root / "Xcode.app/Contents/Developer"
    simulator = developer / "Applications/Simulator.app"
    hub = developer.parent / "Applications/DeviceHub.app"
    simulator.mkdir(parents=True)
    for command, body in {
        "xcode-select": 'printf "%s\\n" "$TEST_DEVELOPER_DIR"',
        "open": 'printf "%s\\n" "$@" > "$TEST_OPEN_LOG"',
    }.items():
        executable = native / command
        executable.write_text("#!/bin/sh\n" + body + "\n")
        executable.chmod(0o755)
    log = root / "open.log"
    env = dict(os.environ, PATH=f"{native}:{os.environ['PATH']}",
               TEST_DEVELOPER_DIR=str(developer), TEST_OPEN_LOG=str(log))
    for expected in (simulator, hub):
        if expected == hub:
            hub.mkdir(parents=True)
            simulator.rmdir()
        for target in ("ios-debug", "ios-profile", "ipad-debug", "ipad-profile",
                       "watch-debug", "watch-profile"):
            result = subprocess.run(
                ["make", "--no-print-directory", "--dry-run", target],
                cwd=project, env=env, capture_output=True, text=True, check=True,
            )
            lines = result.stdout.replace("\\\n", " ").splitlines()
            launchers = [line for line in lines if "open -a " in line]
            assert len(launchers) == 1, result.stdout
            subprocess.run(["/bin/sh", "-c", launchers[0]], env=env, check=True)
            arguments = log.read_text().splitlines()
            assert arguments[0] == "-a", target
            assert Path(arguments[1]).resolve() == expected.resolve(), target

print("Simulator launcher checks passed (6 targets, 2 Xcode layouts).")
