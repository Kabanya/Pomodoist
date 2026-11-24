#!/usr/bin/env python3
"""Render fdroiddata metadata for a checked-out source ref."""
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def git(*args: str) -> str:
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True).strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ref', help='stable vX.Y.Z tag, or a Git ref with --test')
    parser.add_argument('--test', action='store_true', help='render a recipe for a local verification checkout')
    args = parser.parse_args()
    if not args.test and not re.fullmatch(r'v\d+\.\d+\.\d+', args.ref):
        parser.error('Use a stable vX.Y.Z tag for submission.')
    ref = args.ref if args.test else f'refs/tags/{args.ref}'
    commit = git('rev-parse', '--verify', f'{ref}^{{commit}}')
    pubspec = git('show', f'{commit}:apps/flutter/pubspec.yaml')
    version = re.search(r'^version: (\d+\.\d+\.\d+)\+([1-9]\d*)$', pubspec, re.MULTILINE)
    if version is None or (not args.test and version[1] != args.ref[1:]):
        parser.error('The source version must match the stable tag and include a versionCode.')
    flutter = json.loads(git('show', f'{commit}:.fvmrc'))['flutter']
    template = git('show', f'{commit}:tool/android/fdroid-metadata.yml.in')
    for key, value in {
        'COMMIT': commit, 'VERSION_NAME': version[1],
        'VERSION_CODE': version[2], 'FLUTTER_VERSION': flutter,
    }.items():
        template = template.replace(f'@{key}@', value)
    print(template, end='')


if __name__ == '__main__':
    main()
