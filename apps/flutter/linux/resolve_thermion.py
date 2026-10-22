#!/usr/bin/env python3
"""Find Thermion headers using the Flutter application's resolved package map."""
import json
from pathlib import Path
import sys
from urllib.parse import unquote, urljoin, urlparse


def resolve_package(config: Path) -> Path:
    packages = json.loads(config.read_text())['packages']
    package = next((item for item in packages if item['name'] == 'thermion_dart'), None)
    if package is None:
        raise ValueError('thermion_dart is absent; run flutter pub get first')
    uri = urlparse(urljoin(config.absolute().as_uri(), package['rootUri']))
    if uri.scheme != 'file' or uri.netloc not in ('', 'localhost'):
        raise ValueError('thermion_dart must resolve to a local file URI')
    root = Path(unquote(uri.path))
    if not (root / 'native/include/Log.hpp').is_file():
        raise ValueError('thermion_dart native headers are missing')
    return root


if __name__ == '__main__':
    try:
        print(resolve_package(Path(sys.argv[1])))
    except (OSError, ValueError, KeyError, IndexError) as error:
        print(f'Thermion package configuration error: {error}', file=sys.stderr)
        sys.exit(1)
