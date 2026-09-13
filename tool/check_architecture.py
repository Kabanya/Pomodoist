#!/usr/bin/env python3
"""Check handwritten dependency boundaries and cycles without extra packages."""
from pathlib import Path
import argparse
import json
import re

DART_DIRECTIVE = re.compile(r'^\s*(?:import|export)\s+(.*?);', re.M | re.S)
TS_IMPORT = re.compile(r'^\s*(?:import|export)\s+(?:[^;]*?\sfrom\s*)?[\'"]([^\'"]+)[\'"]', re.M)


def dependencies(path):
    source = path.read_text()
    if path.suffix == '.dart':
        return [name for directive in DART_DIRECTIVE.findall(source)
                for name in re.findall(r'[\'"]([^\'"]+)[\'"]', directive)]
    return TS_IMPORT.findall(source)


def cycles(graph):
    indices, low, stack, active, result = {}, {}, [], set(), []

    def visit(node):
        indices[node] = low[node] = len(indices)
        stack.append(node)
        active.add(node)
        for target in graph[node]:
            if target not in indices:
                visit(target)
                low[node] = min(low[node], low[target])
            elif target in active:
                low[node] = min(low[node], indices[target])
        if low[node] == indices[node]:
            group = []
            while True:
                target = stack.pop()
                active.remove(target)
                group.append(target)
                if target == node:
                    break
            if len(group) > 1 or node in graph[node]:
                result.append(sorted(group))

    for node in graph:
        if node not in indices:
            visit(node)
    return result


def check(root):
    root = root.resolve()
    app = root / 'apps/flutter/lib'
    server = root / 'server/supabase/functions'
    errors, graph = [], {}
    for directory in (app, server):
        if not directory.is_dir():
            errors.append(f'Missing source directory: {directory.relative_to(root)}')
    paths = list(app.rglob('*.dart')) + list(server.rglob('*.ts'))
    paths = [p for p in paths if not p.name.endswith(('.g.dart', '_test.ts'))
             and not p.match('*/l10n/app_localizations*.dart')]
    for path in paths:
        graph[path] = set()
    for path in paths:
        for name in dependencies(path):
            if name.startswith('package:pomodoist/'):
                target = app / name.removeprefix('package:pomodoist/')
            elif name.startswith('.'):
                target = path.parent / name
            else:
                target = None
            if target is not None:
                target = target.resolve()
                if not target.exists():
                    errors.append(f'{path.relative_to(root)}: missing import {name}')
                if target in graph:
                    graph[path].add(target)
            if path.is_relative_to(app) and 'domain' in path.relative_to(app).parts:
                forbidden = name.startswith(('package:flutter/', 'package:flutter_riverpod/', 'package:drift/', 'package:app_account/'))
                if target and target.is_relative_to(app):
                    rel = target.relative_to(app)
                    forbidden |= rel.parts[0] == 'app' or str(rel).startswith('core/db/') or any(p in rel.parts for p in ['data', 'presentation'])
                if forbidden:
                    errors.append(f'{path.relative_to(root)}: domain depends on infrastructure/UI: {name}')
            if path.parent == server / '_shared' and target and target.is_relative_to(server) and target.parent != server / '_shared':
                errors.append(f'{path.relative_to(root)}: shared code imports adapter: {name}')
    for group in cycles(graph):
        errors.append('Dependency cycle: ' + ', '.join(str(p.relative_to(root)) for p in group))
    manifest = json.loads((root / 'server/core-manifest.json').read_text())
    helpers = set(manifest['helpers'])
    for name in helpers:
        helper = server / '_shared' / name
        if not re.fullmatch(r'[a-z][a-z0-9_]*\.ts', name) or not helper.is_file():
            errors.append(f'Invalid or missing manifest helper: {name}')
            continue
    packaged = [server / '_shared' / name for name in helpers]
    for name in manifest['functions']:
        if not (server / name / 'index.ts').is_file():
            errors.append(f'Manifest function has no entrypoint: {name}')
        packaged.extend((server / name).rglob('*.ts'))
    for path in packaged:
        if not path.is_file():
            continue
        for dependency in dependencies(path):
            target = (path.parent / dependency).resolve()
            if dependency.startswith('.') and target.parent == server / '_shared' and target.name not in helpers:
                errors.append(f'Manifest omits {target.name} required by {path.relative_to(server)}')
    return errors


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    failures = check(parser.parse_args().root)
    if failures:
        raise SystemExit('\n'.join(failures))
    print('Architecture boundaries, dependency cycles and manifest closure passed.')
