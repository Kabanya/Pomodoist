#!/usr/bin/env python3
"""Prepare the package manifest and pinned source dependencies in an F-Droid checkout."""
import hashlib
import io
from pathlib import Path
import re
import sys
import tarfile
from urllib.request import urlopen
import zipfile

LOCAL_PACKAGES = ('in_app_purchase', 'thermion_flutter')
OVERLAY = 'third_party/fdroid'
SQLITE_PATH = 'third_party/fdroid/sqlite'
SQLITE_ARCHIVE = 'sqlite-amalgamation-3530200'
SQLITE_SHA256 = '8a310d0a16c7a90cacd4c884e70faa51c902afed2a89f63aaa0126ab83558a32'


def replace_once(text: str, before: str, after: str) -> str:
    if text.count(before) != 1:
        raise ValueError(f'Expected exactly one occurrence of {before!r}')
    return text.replace(before, after, 1)


def fdroid_pubspec(pubspec: str) -> str:
    if re.search(r'^hooks:', pubspec, re.MULTILINE):
        raise ValueError('The Flutter manifest already declares hooks. Update the F-Droid overlay.')
    for package in LOCAL_PACKAGES:
        dependency = re.search(rf'^  {package}: \S+$', pubspec, re.MULTILINE)
        if dependency is None:
            raise ValueError(f'Expected {package} in the upstream manifest.')
        pubspec = replace_once(
            pubspec, dependency[0], f'  {package}:\n    path: {OVERLAY}/{package}',
        )
    for desktop_asset in ('manifest.json', 'pomo.glb.gz'):
        pubspec = replace_once(pubspec, f'    - assets/pomo/model/{desktop_asset}\n', '')
    return pubspec.rstrip() + f'''

hooks:
  user_defines:
    sqlite3:
      source: source
      path: {SQLITE_PATH}/sqlite3.c
    thermion_dart:
      # The 3D companion is desktop-only. Avoid the Android Filament download.
      skip_native_build: true
'''


def fdroid_lock(lock: str) -> tuple[str, dict[str, tuple[str, str]]]:
    packages = {}
    for package in LOCAL_PACKAGES:
        entry = re.search(rf'^  {package}:\n(?:^    .*\n)+', lock, re.MULTILINE)
        if entry is None:
            raise ValueError(f'Expected {package} in pubspec.lock.')
        version = re.search(r'^    version: "([0-9.]+)"$', entry[0], re.MULTILINE)
        sha256 = re.search(r'^      sha256: "?([0-9a-f]{64})"?$', entry[0], re.MULTILINE)
        if version is None or sha256 is None:
            raise ValueError(f'Expected a locked version and digest for {package}.')
        packages[package] = (version[1], sha256[1])
        replacement = f'''  {package}:
    dependency: "direct main"
    description:
      path: "{OVERLAY}/{package}"
      relative: true
    source: path
    version: "{version[1]}"
'''
        lock = replace_once(lock, entry[0], replacement)
    android = re.search(r'^  in_app_purchase_android:\n(?:^    .*\n)+', lock, re.MULTILINE)
    if android is None:
        raise ValueError('Expected in_app_purchase_android in pubspec.lock.')
    return replace_once(lock, android[0], ''), packages


def patch_purchase_source(pubspec: str, dart_source: str) -> tuple[str, str]:
    pubspec = replace_once(
        pubspec, '      android:\n        default_package: in_app_purchase_android\n', '',
    )
    dependency = re.search(r'^  in_app_purchase_android: \S+\n', pubspec, re.MULTILINE)
    if dependency is None:
        raise ValueError('Expected the Android plugin dependency in in_app_purchase.')
    pubspec = replace_once(pubspec, dependency[0], '')
    dart_source = replace_once(
        dart_source, "import 'package:in_app_purchase_android/in_app_purchase_android.dart';\n", '',
    )
    dart_source = replace_once(
        dart_source,
        'InAppPurchaseAndroidPlatform.registerPlatform();',
        "throw UnsupportedError('Native purchases are unavailable in this distribution.');",
    )
    return pubspec, dart_source


def download(url: str, expected_sha256: str) -> bytes:
    with urlopen(url, timeout=60) as response:
        contents = response.read()
    if hashlib.sha256(contents).hexdigest() != expected_sha256:
        raise ValueError(f'SHA-256 mismatch for {url}')
    return contents


def prepare(app_root: Path) -> None:
    manifest = app_root / 'pubspec.yaml'
    lockfile = app_root / 'pubspec.lock'
    manifest_text = fdroid_pubspec(manifest.read_text())
    lock_text, packages = fdroid_lock(lockfile.read_text())
    for package, (version, sha256) in packages.items():
        contents = download(f'https://pub.dev/api/archives/{package}-{version}.tar.gz', sha256)
        root = app_root / OVERLAY / package
        with tarfile.open(fileobj=io.BytesIO(contents)) as archive:
            # Only ship the Dart library and its license. The Android native
            # plugins and upstream example apps do not enter the build tree.
            for member in archive.getmembers():
                name = Path(member.name)
                if not member.isfile() or name.is_absolute() or '..' in name.parts:
                    continue
                if name.parts[:1] != ('lib',) and name not in (Path('LICENSE'), Path('pubspec.yaml')):
                    continue
                destination = root / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as source:
                    destination.write_bytes(source.read())
        spec = root / 'pubspec.yaml'
        if package == 'in_app_purchase':
            dart = root / 'lib/in_app_purchase.dart'
            patched_spec, patched_dart = patch_purchase_source(spec.read_text(), dart.read_text())
            dart.write_text(patched_dart)
        else:
            patched_spec = replace_once(
                spec.read_text(),
                '      android:\n        pluginClass: ThermionFlutterPlugin\n'
                '        package: dev.thermion.android\n',
                '',
            )
        spec.write_text(patched_spec)

    sqlite_zip = download(f'https://sqlite.org/2026/{SQLITE_ARCHIVE}.zip', SQLITE_SHA256)
    sqlite_root = app_root / SQLITE_PATH
    sqlite_root.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(sqlite_zip)) as archive:
        for filename in ('sqlite3.c', 'sqlite3.h'):
            (sqlite_root / filename).write_bytes(archive.read(f'{SQLITE_ARCHIVE}/{filename}'))
    manifest.write_text(manifest_text)
    lockfile.write_text(lock_text)


if __name__ == '__main__':
    prepare(Path(sys.argv[1]).resolve())
