#!/usr/bin/env python3
"""Capture real SwiftUI Watch views in a dedicated, disposable simulator.

Build the isolated watch target described in the storefront README first.
The fixture app never activates WatchConnectivity or opens a user account.
"""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'build/localized-watch'
ASSETS = ROOT / 'design/app-store/localized/raw/watch'
LOCALES = json.loads((ROOT / 'docs/localization/stores/apple/fixtures/screenshot-tasks.json').read_text())
APP = WORK / 'products/Debug-watchsimulator/PomodoistWatch.app'


def sim(*args, **kwargs):
    return subprocess.run(['xcrun', 'simctl', *args], check=True, **kwargs)


def main():
    device = (WORK / 'simulator-id.txt').read_text().strip()
    assert device, 'Create a dedicated Watch simulator first'
    with (APP / 'Info.plist').open('rb') as stream:
        app_id = plistlib.load(stream)['CFBundleIdentifier']
    sim('install', device, str(APP))
    for locale, tasks in LOCALES.items():
        folder = ASSETS / locale
        folder.mkdir(parents=True, exist_ok=True)
        for name, screen in [('01-voice-input', 'voice'), ('02-tasks', 'tasks'), ('03-focus', 'focus')]:
            subprocess.run(['xcrun', 'simctl', 'terminate', device, app_id], capture_output=True)
            env = {**os.environ,
                   'SIMCTL_CHILD_STORE_CAPTURE_LOCALE': locale,
                   'SIMCTL_CHILD_STORE_CAPTURE_SCREEN': screen,
                   'SIMCTL_CHILD_STORE_CAPTURE_TASKS': json.dumps(tasks, ensure_ascii=False)}
            sim('launch', device, app_id, '-AppleLanguages', f'({locale})', '-AppleLocale', locale.replace('-', '_'), env=env, capture_output=True)
            # A native Watch launch is asynchronous; allow the SwiftUI tree to paint.
            time.sleep(2)
            output = folder / f'{name}.png'
            sim('io', device, 'screenshot', str(output), capture_output=True)
            assert output.read_bytes()[:8] == b'\x89PNG\r\n\x1a\n'
            (folder / f'{name}.json').write_text(json.dumps({
                'locale': locale, 'device': 'watch', 'screen': screen,
                'texts': tasks, 'fixture': 'isolated offline WatchSnapshot',
                'source': 'production SwiftUI views in a dedicated simulator',
            }, ensure_ascii=False) + '\n')
        print(f'watch/{locale}: 3 native captures', flush=True)


if __name__ == '__main__':
    main()
