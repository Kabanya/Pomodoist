#!/usr/bin/env python3
"""Stage Pomodoist's localized App Store release with the asc CLI."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
COPY = ROOT / 'docs/localization/stores/apple'
APP_ID = '6794391064'
PLATFORMS = ('IOS', 'MAC_OS')
LOCALES = {
    'en': 'en-US', 'ru': 'ru', 'de': 'de-DE', 'es': 'es-ES', 'fr': 'fr-FR',
    'ar': 'ar-SA', 'zh': 'zh-Hans', 'pt-BR': 'pt-BR', 'ja': 'ja', 'ko': 'ko',
}
DISPLAYS = (
    ('IOS', 'iphone', 'APP_IPHONE_61', 10),
    ('IOS', 'ipad', 'APP_IPAD_PRO_3GEN_129', 10),
    ('IOS', 'watch', 'APP_WATCH_SERIES_10', 3),
    ('MAC_OS', 'mac', 'APP_DESKTOP', 10),
)


def asc(*args, env=None, capture=False):
    result = subprocess.run(
        ['asc', *map(str, args), '--output', 'json'],
        cwd=ROOT, env={**(env or os.environ), 'ASC_TELEMETRY_DISABLED': '1'},
        check=True, text=True, stdout=subprocess.PIPE if capture else None,
    )
    if capture:
        return json.loads(result.stdout)


def require_locales(actual, expected, label):
    if actual != expected:
        raise ValueError(f'{label}: missing {sorted(expected - actual)}, extra {sorted(actual - expected)}')


def prepare_metadata(directory, version):
    language_file = ROOT / 'apps/flutter/lib/domain/models/settings/app_language.dart'
    tags = set(re.findall(r"^  \w+\('([^']+)',", language_file.read_text(), re.M))
    require_locales(set(LOCALES), tags, 'AppLanguage mapping')
    expected = set(LOCALES.values())
    require_locales({path.stem for path in COPY.glob('*.json')}, expected, 'Store copy')
    notes = json.loads((COPY / 'whats-new' / f'{version}.json').read_text())
    require_locales(set(notes), expected, 'Release notes')

    for platform in PLATFORMS:
        base = directory / platform
        info_dir = base / 'app-info'
        version_dir = base / 'version' / version
        info_dir.mkdir(parents=True)
        version_dir.mkdir(parents=True)
        for locale in LOCALES.values():
            copy = json.loads((COPY / f'{locale}.json').read_text())
            info = {
                'name': 'Pomodoist',
                'subtitle': copy['subtitle'],
                'privacyPolicyUrl': 'https://pomodoist.com/privacy/',
            }
            metadata = {
                'description': copy['description'],
                'keywords': copy['keywords'],
                'supportUrl': 'https://pomodoist.com/',
                'marketingUrl': 'https://pomodoist.com/',
                'whatsNew': notes[locale],
                'promotionalText': copy['macPromotionalText' if platform == 'MAC_OS' else 'promotionalText'],
            }
            if not notes[locale].strip() or len(copy['keywords'].encode()) > 100:
                raise ValueError(f'{locale}: release notes required and keywords limited to 100 UTF-8 bytes')
            for folder, fields in ((info_dir, info), (version_dir, metadata)):
                (folder / f'{locale}.json').write_text(json.dumps(fields, ensure_ascii=False) + '\n')
        asc('metadata', 'validate', '--dir', base, '--subscription-app')


def check_screenshots(root):
    errors = []
    for _, device, display, count in DISPLAYS:
        device_root = root / device
        dirs = {path.name for path in device_root.iterdir() if path.is_dir()} if device_root.is_dir() else set()
        unexpected = dirs - set(LOCALES.values())
        if unexpected:
            errors.append(f'{device}: unexpected locale directories {sorted(unexpected)}')
        seen = {}
        for locale in LOCALES.values():
            folder = device_root / locale
            files = sorted(folder.glob('*.png'))
            if len(files) != count or any(
                not path.name.startswith(f'{index:02}-') for index, path in enumerate(files, 1)
            ):
                errors.append(f'{device}/{locale}: expected {count} numbered PNGs, found {len(files)}')
                continue
            if set(folder.iterdir()) != set(files):
                errors.append(f'{device}/{locale}: directory must contain only final PNGs')
                continue
            for path in files:
                data = path.read_bytes()
                if data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR' or data[24:26] != b'\x08\x02':
                    errors.append(f'{path}: expected opaque 8-bit RGB PNG')
                digest = hashlib.sha256(data).digest()
                previous = seen.setdefault(digest, path)
                if previous != path:
                    errors.append(f'{path}: duplicates {previous}')
    if errors:
        raise ValueError('Screenshot matrix is incomplete:\n  ' + '\n  '.join(errors))
    for _, device, display, _ in DISPLAYS:
        for locale in LOCALES.values():
            asc('screenshots', 'validate', '--path', root / device / locale, '--device-type', display)


def auth(args, temp):
    setup = [args.dart, 'tool/env_setup.dart']
    options = ['--env', args.private_config]
    key_path = temp / 'AuthKey.p8'
    subprocess.run([*setup, 'write-asc-key', *options, '--output', str(key_path)], cwd=ROOT, check=True)
    env = {**os.environ, 'ASC_BYPASS_KEYCHAIN': '1', 'ASC_PRIVATE_KEY_PATH': str(key_path)}
    for key in ('ASC_KEY_ID', 'ASC_ISSUER_ID'):
        env[key] = subprocess.check_output([*setup, 'value', *options, '--key', key], cwd=ROOT, text=True)
    return env


def screenshot_status(versions, env):
    result = {}
    for platform in PLATFORMS:
        response = asc('screenshots', 'list', '--version-id', versions[platform]['id'], env=env, capture=True)
        result[platform] = {
            loc['locale']: {
                row['set']['attributes']['screenshotDisplayType']: row['screenshots']
                for row in loc['sets']
            }
            for loc in response['localizations']
        }
    return result


def is_complete(screenshot):
    return screenshot['attributes']['assetDeliveryState']['state'] == 'COMPLETE'


def screenshot_commands(args, target, remote):
    for platform, device, display, count in DISPLAYS:
        for locale in LOCALES.values():
            existing = remote[platform][locale].get(display, [])
            folder = args.screenshots / device / locale
            if locale == 'en-US' and len(existing) == count and all(map(is_complete, existing)):
                continue
            local_md5 = [hashlib.md5(path.read_bytes()).hexdigest() for path in sorted(folder.glob('*.png'))]
            remote_md5 = [row['attributes']['sourceFileChecksum'] for row in existing]
            if not all(map(is_complete, existing)) or remote_md5 != local_md5[:len(existing)]:
                raise ValueError(f'{device}/{locale}: existing screenshots differ from the ordered local set or are still processing.')
            if remote_md5 != local_md5:
                yield ('screenshots', 'upload', *target, '--platform', platform, '--locale', locale,
                       '--device-type', display, '--path', folder, '--skip-existing', '--concurrency', '3')


def run(args, temp):
    if args.mode in ('check', 'metadata'):
        prepare_metadata(temp, args.version)
    if args.mode in ('check', 'screenshots'):
        check_screenshots(args.screenshots)
    if args.mode == 'check':
        return

    env = auth(args, temp)
    target = ('--app', APP_ID, '--version', args.version)
    if args.mode == 'draft':
        for platform in PLATFORMS:
            asc('versions', 'create', *target, '--platform', platform,
                '--release-type', 'MANUAL', '--if-exists', 'skip', env=env)
        return

    versions = asc('versions', 'list', *target, '--paginate', env=env, capture=True)['data']
    drafts = {row['attributes']['platform']: row for row in versions}
    if set(PLATFORMS) - drafts.keys():
        raise ValueError(f'Expected both iOS and macOS versions for {args.version}.')
    for platform in PLATFORMS:
        attrs = drafts[platform]['attributes']
        state = attrs.get('appVersionState') or attrs['appStoreState']
        if args.mode != 'status' and (state != 'PREPARE_FOR_SUBMISSION' or attrs['releaseType'] != 'MANUAL'):
            raise ValueError(f'{platform} {args.version}: expected a draft with manual release, got {state}.')
        print(f'{platform} {args.version}: {state}', flush=True)

    if args.mode in ('status', 'screenshots'):
        remote = screenshot_status(drafts, env)
    if args.mode == 'status':
        for platform, device, display, count in DISPLAYS:
            for locale, sets in sorted(remote[platform].items()):
                rows = sets.get(display, [])
                ready = sum(map(is_complete, rows))
                print(f'{device}/{locale}: {ready}/{count} complete ({len(rows)} uploaded)')
        return

    if args.mode == 'metadata':
        commands = [
            ('metadata', 'push', *target, '--platform', platform, '--dir', temp / platform,
             '--if-exists', 'update') for platform in PLATFORMS
        ]
    elif args.mode == 'screenshots':
        for platform in PLATFORMS:
            require_locales(set(remote[platform]), set(LOCALES.values()), f'{platform} draft')
        commands = list(screenshot_commands(args, target, remote))
    else:
        for platform in PLATFORMS:
            asc('versions', 'attach-build', *target, '--platform', platform,
                '--build-number', args.build, '--wait', env=env)
        return
    for command in commands:
        asc(*command, '--dry-run', env=env)
    if args.apply:
        for command in commands:
            asc(*command, env=env)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('check', 'status', 'draft', 'metadata', 'screenshots', 'attach'))
    parser.add_argument('--version', required=True)
    parser.add_argument('--build')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--screenshots', type=Path, required=True)
    parser.add_argument('--dart', required=True)
    parser.add_argument('--private-config', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
        parser.error('--version must be X.Y.Z')
    if args.mode in ('draft', 'attach') and not args.apply:
        parser.error(f'{args.mode} requires --apply')
    if args.mode == 'attach' and not re.fullmatch(r'\d+', args.build or ''):
        parser.error('attach requires an exact numeric --build')
    try:
        with tempfile.TemporaryDirectory(prefix='pomodoist-app-store-') as tmp:
            run(args, Path(tmp))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
