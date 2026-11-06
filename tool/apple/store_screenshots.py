#!/usr/bin/env python3
"""Generate local store covers; this command never contacts App Store Connect."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / 'tool/apple'
CONFIG = json.loads((TOOL / 'store-screenshots.json').read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args, **kwargs):
    kwargs.setdefault('cwd', ROOT)
    subprocess.run(list(map(str, args)), check=True, **kwargs)


def generate(output, devices, locales, ui_locale):
    output.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, 'TZ': CONFIG['timeZone'], 'LC_ALL': 'en_US.UTF-8'}
    captures = locales if ui_locale == 'localized' else [ui_locale]
    flutter = ROOT / '.fvm/flutter_sdk/bin/flutter'
    run([flutter, 'test', 'tool/store_capture_test.dart', '--no-pub',
         '--reporter', 'expanded',
         '--dart-define=STORE_CAPTURE_LOCALES=' + ','.join(captures),
         '--dart-define=STORE_CAPTURE_DEVICES=' + ','.join(devices),
         '--dart-define=STORE_CAPTURE_OUTPUT=' + str(output / 'raw')],
        env=env, cwd=ROOT / 'apps/flutter')
    run(['node', TOOL / 'render_localized_screenshots.cjs'], env={
        **env, 'STORE_OUTPUT': str(output), 'STORE_UI_LOCALE': ui_locale,
        'STORE_RENDER_DEVICES': ','.join(devices),
        'STORE_RENDER_LOCALES': ','.join(locales),
    })
    rendered = json.loads((output / 'render-checks.json').read_text())
    rows = rendered['results']
    assert len(rows) == len(devices) * len(locales) * len(CONFIG['slides'])
    for row in rows:
        assert digest(output / row['file']) == row['sha256'], row['file']
        assert digest(output / row['source']) == row['sourceSha256'], row['source']
    sources = sorted({row['source'] for row in rows})
    provenance = {name: json.loads((output / name).with_suffix('.json').read_text())
                  for name in sources}
    source_paths = [ROOT / '.fvmrc', ROOT / 'apps/flutter/pubspec.lock',
                    ROOT / 'apps/flutter/tool/store_capture_test.dart',
                    ROOT / 'apps/flutter/test/support/test_app.dart']
    source_paths += list((ROOT / 'apps/flutter/lib').rglob('*.dart'))
    source_paths += list((ROOT / 'apps/flutter/lib').rglob('*.arb'))
    source_paths += [path for path in TOOL.rglob('*') if path.is_file()
                     and 'node_modules' not in path.parts
                     and '__pycache__' not in path.parts
                     and path.suffix in {'.py', '.json', '.cjs', '.html', '.css'}]
    source_hashes = {str(path.relative_to(ROOT)): digest(path) for path in sorted(source_paths)}
    fonts = [Path('/System/Library/Fonts/Supplemental/Georgia.ttf'),
             Path('/System/Library/Fonts/Helvetica.ttc'),
             Path('/System/Library/Fonts/Hiragino Sans GB.ttc'),
             Path('/System/Library/Fonts/AppleSDGothicNeo.ttc'),
             Path('/System/Library/Fonts/GeezaPro.ttc')]
    manifest = {
        'schemaVersion': 1, 'captureDate': CONFIG['captureDate'],
        'timeZone': CONFIG['timeZone'], 'uiLocale': ui_locale,
        'environment': {'macOS': platform.mac_ver()[0], 'architecture': platform.machine(),
                        'node': subprocess.check_output(['node', '--version'], text=True).strip(),
                        'browser': rendered['browser'], 'sharp': rendered['sharp'],
                        'fonts': {font.name: digest(font) for font in fonts}},
        'sourceHashes': source_hashes, 'captures': provenance, 'results': rows,
    }
    (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    return manifest


def compare(first, second):
    changed = [row['file'] for row, other in zip(first['results'], second['results'])
               if row != other]
    sources, other_sources = first.get('sourceHashes', {}), second.get('sourceHashes', {})
    changed_sources = [name for name in sorted(sources.keys() | other_sources.keys())
                       if sources.get(name) != other_sources.get(name)]
    changed_captures = [name for name in sorted(first.get('captures', {}))
                        if first['captures'][name] != second.get('captures', {}).get(name)]
    assert first == second, (f'Capture/render verification changed: images={changed}; '
                             f'sources={changed_sources}; text={changed_captures}')


def package(output, manifest):
    with zipfile.ZipFile(output / 'covers.zip', 'w', zipfile.ZIP_STORED) as archive:
        for name in sorted([row['file'] for row in manifest['results']] + ['manifest.json']):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            archive.writestr(info, (output / name).read_bytes())
    # A local gallery is an output artifact, never an upload asset.
    from html import escape
    cards = ''.join(f'<figure><a href="{escape(row["file"])}"><img loading="lazy" src="{escape(row["file"])}"></a>'
                    f'<figcaption>{escape(row["locale"])} · {escape(Path(row["file"]).stem)}</figcaption></figure>'
                    for row in manifest['results'])
    (output / 'index.html').write_text('<!doctype html><meta charset="utf-8"><title>Pomodoist store covers</title>'
        '<style>body{background:#151515;color:#eee;font:14px system-ui;margin:24px}'
        'main{display:flex;flex-wrap:wrap;gap:24px}figure{margin:0;width:220px}'
        'img{width:220px;height:auto}figcaption{padding:10px 0}</style>'
        f'<h1>Pomodoist · {len(manifest["results"])} covers</h1><main>{cards}</main>')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--devices', default='iphone', help='iphone,ipad,mac (comma-separated)')
    parser.add_argument('--locales', default=','.join(CONFIG['locales']))
    parser.add_argument('--ui-locale', default='en-US', choices=[*CONFIG['locales'], 'localized'])
    parser.add_argument('--output', type=Path, default=ROOT / 'output/app-store-screenshots')
    parser.add_argument('--verify', action='store_true', help='Capture/render twice and require identical hashes and provenance')
    args = parser.parse_args()
    devices, locales = args.devices.split(','), args.locales.split(',')
    if len(set(devices)) != len(devices) or not set(devices) <= {'iphone', 'ipad', 'mac'}:
        parser.error('Select unique devices from iphone,ipad,mac; Watch uses its native capture workflow')
    if len(set(locales)) != len(locales) or not set(locales) <= set(CONFIG['locales']):
        parser.error('Select unique shipping locales from store-screenshots.json')
    if platform.system() != 'Darwin':
        parser.error('This capture recipe uses macOS system fonts')
    output = args.output.resolve()
    with tempfile.TemporaryDirectory(prefix='pomodoist-store-assets-') as temporary:
        first = Path(temporary) / 'first'
        manifest = generate(first, devices, locales, args.ui_locale)
        if args.verify:
            second = Path(temporary) / 'second'
            compare(manifest, generate(second, devices, locales, args.ui_locale))
            print('PASS: independent captures and renders are byte-identical', flush=True)
        package(first, manifest)
        output.mkdir(parents=True, exist_ok=True)
        # Publish only after the whole selected matrix and optional repeat check pass.
        shutil.copytree(first, output, dirs_exist_ok=True)
        print(f'PASS: {len(manifest["results"])} local covers → {output}', flush=True)


if __name__ == '__main__':
    main()
