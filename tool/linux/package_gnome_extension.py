#!/usr/bin/env python3
"""Build the offline, reproducible Pomo GNOME extension payload using stdlib only."""
import argparse
import json
from pathlib import Path
import shutil
import tempfile
import zipfile

UUID = 'pomo@pomodoist.com'
SUPPORTED_SHELLS = {'46', '50', '51'}


def runtime_files(source: Path) -> list[Path]:
    source = Path(source)
    metadata_path = source / 'metadata.json'
    if not metadata_path.is_file() or not (source / 'extension.js').is_file():
        raise ValueError('Pomo extension metadata and entrypoint are required')
    metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
    if metadata.get('uuid') != UUID:
        raise ValueError('Unexpected extension UUID')
    version = metadata.get('version')
    if type(version) is not int or version < 1:
        raise ValueError('Extension version must be a positive integer')
    shells = metadata.get('shell-version')
    if (not isinstance(shells, list) or any(type(item) is not str for item in shells)
            or set(shells) != SUPPORTED_SHELLS):
        raise ValueError('Declare only the supported GNOME 46, 50 and 51 targets')
    result = []
    for path in sorted(source.rglob('*')):
        relative = path.relative_to(source)
        if any(part == 'tests' or part.startswith('.') for part in relative.parts):
            continue
        if path.is_symlink():
            raise ValueError(f'Extension sources cannot contain symlinks: {relative}')
        if path.is_file() and (path.suffix in {'.js', '.json', '.md', '.xml'}
                               or path.name == 'LICENSE'):
            result.append(path)
    return result


def build_extension_bundle(source: Path, output: Path, sources_out: Path | None = None) -> None:
    source, output = Path(source), Path(output)
    files = runtime_files(source)
    if sources_out is not None:
        sources_out = Path(sources_out)
        if sources_out.name != UUID or sources_out.is_symlink():
            raise ValueError('Source destination must be a real directory named with the extension UUID')
        if source.resolve() == sources_out.resolve():
            raise ValueError('Source and installed source directories must differ')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.pomo-extension-', dir=output.parent) as temporary:
        staged = Path(temporary) / 'extension.zip'
        with zipfile.ZipFile(staged, 'w', compression=zipfile.ZIP_DEFLATED,
                             compresslevel=9) as archive:
            for path in files:
                entry = zipfile.ZipInfo(path.relative_to(source).as_posix(), (1980, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = 0o100644 << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, path.read_bytes(), compresslevel=9)
        if sources_out is not None:
            copied = Path(temporary) / UUID
            copied.mkdir()
            for path in files:
                target = copied / path.relative_to(source)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
            sources_out.parent.mkdir(parents=True, exist_ok=True)
            if sources_out.exists():
                shutil.rmtree(sources_out)
            shutil.move(str(copied), str(sources_out))
        staged.replace(output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sources-out', type=Path)
    args = parser.parse_args()
    try:
        build_extension_bundle(args.source, args.output, args.sources_out)
    except (ValueError, OSError) as error:
        parser.exit(1, f'Cannot package the Pomo extension: {error}\n')


if __name__ == '__main__':
    main()
