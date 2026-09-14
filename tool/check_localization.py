#!/usr/bin/env python3
"""Validate shipping locale catalogs, placeholders, native resources and store fields."""
import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
base = json.loads((root / 'apps/flutter/lib/l10n/app_en.arb').read_text())
keys = {key for key in base if not key.startswith('@')}
for path in (root / 'apps/flutter/lib/l10n').glob('app_*.arb'):
    data = json.loads(path.read_text())
    if path.stem == 'app_pt_BR':
        assert data['@@locale'] == 'pt_BR' and len(data) == 1, path
        continue
    assert {key for key in data if not key.startswith('@')} == keys, path
    for key in keys:
        assert isinstance(data[key], str) and data[key].strip(), (path, key)
        # ICU argument names, including select/plural. Flutter gen-l10n validates grammar.
        arguments = lambda value: set(re.findall(r'\{\s*([a-zA-Z]\w*)\s*[,}]', value))
        expected = set(base.get('@' + key, {}).get('placeholders', {}))
        assert expected <= arguments(data[key]), (path, key, 'arguments')
        for token in re.findall(r'https?://[^\s{}]+', base[key]):
            assert token in data[key], (path, key, token)
watch = json.loads((root / 'apps/flutter/ios/PomodoistWatch/Localizable.xcstrings').read_text())['strings']
for key, record in watch.items():
    for locale in ['pt-BR', 'ja', 'ko']:
        assert record['localizations'][locale]['stringUnit']['value'].strip(), (key, locale)
resources = root / 'apps/flutter/apple/Localization'
native_sets = []
for locale in ['pt-BR', 'ja', 'ko']:
    path = resources / f'{locale}.lproj/Localizable.strings'
    native_sets.append(set(re.findall(r'^"(.*?)" = ', path.read_text(), re.M)))
    assert 'NSMicrophoneUsageDescription' in (resources / f'{locale}.lproj/InfoPlist.strings').read_text()
    for platform in ['ios', 'macos']:
        assert f'{locale}.lproj/Localizable.strings' in (root / 'apps/flutter' / platform / 'Runner.xcodeproj/project.pbxproj').read_text()
assert len(native_sets[0]) > 40 and all(value == native_sets[0] for value in native_sets)
for locale in ['pt-BR', 'ja', 'ko']:
    data = json.loads((root / f'docs/localization/stores/{locale}.json').read_text())
    for store in ['appStore', 'macAppStore']:
        for field, limit in {'name': 30, 'subtitle': 30, 'promotionalText': 170, 'description': 4000, 'keywords': 100, 'releaseNotes': 4000}.items():
            assert 0 < len(data[store][field]) <= limit, (locale, store, field, len(data[store][field]))
        assert len(data[store]['keywords'].encode()) <= 100, (locale, 'keyword bytes')
    for field, limit in {'name': 30, 'shortDescription': 80, 'description': 4000, 'releaseNotes': 500}.items():
        assert 0 < len(data['googlePlay'][field]) <= limit, (locale, field)
    assert len(data['chromeWebStore']['shortDescription']) <= 132, locale
    for product in data['purchases'].values():
        assert len(product['name']) <= 30 and len(product['description']) <= 45, (locale, product)
print(f'Localization contracts passed: {len(keys)} ARB keys, {len(watch)} Watch keys, {len(native_sets[0])} native keys, 3 store packages.')
