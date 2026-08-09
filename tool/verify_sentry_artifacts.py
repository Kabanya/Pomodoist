#!/usr/bin/env python3
import json
import pathlib
import re
import sys


if len(sys.argv) != 5:
    raise SystemExit(
        "usage: verify_sentry_artifacts.py "
        "<runtime-js> <exported-js> <source-map> <repository-root>"
    )

runtime_js = pathlib.Path(sys.argv[1])
exported_js = pathlib.Path(sys.argv[2])
source_map_path = pathlib.Path(sys.argv[3])
try:
    repository_root = pathlib.Path(sys.argv[4]).absolute().resolve(strict=True)
except (FileNotFoundError, OSError):
    raise SystemExit("repository root is unavailable")
if not repository_root.is_dir():
    raise SystemExit("repository root is not a directory")

runtime_bytes = runtime_js.read_bytes()
exported_bytes = exported_js.read_bytes()
if runtime_bytes != exported_bytes:
    raise SystemExit("runtime JS differs from exported JS")

debug_matches = re.findall(rb"//# debugId=([0-9a-f-]{36})", runtime_bytes)
if len(debug_matches) != 1:
    raise SystemExit("runtime JS must contain exactly one Debug ID")
debug_id = debug_matches[0].decode("ascii")

source_map = json.loads(source_map_path.read_text())
if source_map.get("debug_id") != debug_id:
    raise SystemExit("JavaScript and source-map Debug IDs differ")

sources = source_map.get("sources")
contents = source_map.get("sourcesContent")
if not isinstance(sources, list) or not isinstance(contents, list):
    raise SystemExit("source map does not contain embedded source content")
if len(sources) != len(contents):
    raise SystemExit("sourcesContent is not aligned with sources")

first_party = 0
main_source_index = None


def canonical_first_party_source(relative, display_path):
    relative_path = pathlib.Path(relative)
    if relative_path.is_absolute() or ".." in relative_path.parts:
        raise SystemExit(f"invalid first-party source path: {display_path}")
    current = repository_root
    for component in relative_path.parts:
        current = current / component
        if current.is_symlink():
            raise SystemExit(
                f"symlinked first-party sources are forbidden: {display_path}"
            )
        if not current.exists():
            raise SystemExit(f"first-party source is missing: {display_path}")
    try:
        canonical = current.resolve(strict=True)
    except (FileNotFoundError, OSError):
        raise SystemExit(f"first-party source is unavailable: {display_path}")
    if repository_root not in canonical.parents or not canonical.is_file():
        raise SystemExit(f"first-party source escapes repository: {display_path}")
    return canonical


for index, (source, content) in enumerate(zip(sources, contents)):
    if not isinstance(source, str):
        raise SystemExit("source-map source is not a string")
    if pathlib.PurePosixPath(source).is_absolute() or pathlib.PureWindowsPath(
        source
    ).is_absolute():
        raise SystemExit(f"source map contains an absolute source path: {source}")
    if source.startswith("../../../lib/"):
        relative = source[len("../../../") :]
        first_party += 1
        if relative == "lib/main.dart":
            main_source_index = index
    else:
        if content is not None:
            raise SystemExit(f"non-lib source content must be null: {source}")
        continue

    expected_path = canonical_first_party_source(relative, source)
    if content != expected_path.read_text():
        raise SystemExit(f"embedded source content differs: {source}")

if main_source_index is None:
    raise SystemExit("expected Pomodoist lib sources were not embedded")
if "Future<void> main()" not in contents[main_source_index]:
    raise SystemExit("lib/main.dart content is not resolvable")


_B64 = {char: index for index, char in enumerate(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")}


def decode_vlq(segment):
    values = []
    value = 0
    shift = 0
    for char in segment:
        digit = _B64[char]
        value += (digit & 31) << shift
        if digit & 32:
            shift += 5
            continue
        negative = value & 1
        decoded = value >> 1
        values.append(-decoded if negative else decoded)
        value = 0
        shift = 0
    if shift:
        raise SystemExit("invalid VLQ mapping")
    return values


source_index = 0
source_line = 0
source_column = 0
name_index = 0
resolve_position = None
for generated_line, line in enumerate(source_map["mappings"].split(";"), 1):
    generated_column = 0
    for segment in line.split(","):
        if not segment:
            continue
        values = decode_vlq(segment)
        generated_column += values[0]
        if len(values) < 4:
            continue
        source_index += values[1]
        source_line += values[2]
        source_column += values[3]
        if len(values) == 5:
            name_index += values[4]
        if source_index == main_source_index:
            resolve_position = (generated_line, generated_column + 1)
            break
    if resolve_position:
        break

if resolve_position is None:
    raise SystemExit("no generated mapping resolves to lib/main.dart")

print(f"debug-id={debug_id}")
print(f"first-party-sources={first_party}")
print(f"resolve-position={resolve_position[0]}:{resolve_position[1]}")
