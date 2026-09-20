#!/usr/bin/env python3
"""Check handwritten dependency boundaries and cycles without extra packages."""
from pathlib import Path
import argparse
import json
import re

DART_DIRECTIVE = re.compile(
    r'^\s*(?:import|export|part(?!\s+of\b))\s+(.*?);',
    re.M | re.S,
)
TS_IMPORT = re.compile(r'^\s*(?:import|export)\s+(?:[^;]*?\sfrom\s*)?[\'"]([^\'"]+)[\'"]', re.M)

# Kernel/SDK packages no view, view model or repository contract may depend on.
# `tool/check_architecture_types.dart` keeps the same list.
INFRASTRUCTURE_PACKAGES = (
    'package:drift/', 'package:drift_flutter/',
    'package:supabase_flutter/', 'package:app_account/',
    'package:app_voice/', 'package:dio/', 'package:http/',
    'package:shared_preferences/', 'package:in_app_purchase/',
    'package:in_app_purchase_storekit/', 'package:record/',
    'package:flutter_local_notifications/', 'package:audioplayers/',
    'package:path_provider/', 'package:sqlite3/', 'package:app_links/',
    'package:dbus/', 'package:sentry_flutter/',
)
ABSTRACT_REPOSITORY = re.compile(r'abstract\s+(?:interface\s+)?class\s+\w+')
CONCRETE_REPOSITORY = re.compile(r'\bclass\s+\w*Repository\b')


def dart_target(lib, path, name):
    """Resolve a relative Dart URI the way the SDK does.

    The SDK resolves relative URIs against the importing file's directory but
    clamps the walk at the package `lib/` root: a leading `../` at the root
    stays at the root instead of failing. An over-deep `../../../../app/x.dart`
    therefore still names `lib/app/x.dart`.
    """
    relative = path.parent.relative_to(lib)
    for part in Path(name).parts:
        relative = relative.parent if part == '..' else relative / part
    return lib / relative


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
             and not p.match('*/localization/app_localizations*.dart')]
    for path in paths:
        graph[path] = set()
    for path in paths:
        source_text = path.read_text()
        for name in dependencies(path):
            if name.startswith('package:pomodoist/'):
                target = app / name.removeprefix('package:pomodoist/')
            elif ':' not in name and path.is_relative_to(app):
                target = dart_target(app, path, name)
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
            if path.is_relative_to(app):
                source = path.relative_to(app)
                destination = target.relative_to(app) if target and target.is_relative_to(app) else None
                source_parts = source.parts
                target_parts = destination.parts if destination else ()
                target_text = ''
                if target is not None and target.is_file():
                    target_text = target.read_text()
                target_contract = (
                    target_parts[:2] == ('data', 'repositories')
                    and ABSTRACT_REPOSITORY.search(target_text) is not None
                )
                target_concrete_repository = (
                    target_parts[:2] == ('data', 'repositories')
                    and not target_contract
                    and CONCRETE_REPOSITORY.search(target_text) is not None
                )
                view = source_parts[0] == 'ui' and 'view_models' not in source_parts
                view_model = source_parts[0] == 'ui' and 'view_models' in source_parts
                infrastructure = name.startswith(INFRASTRUCTURE_PACKAGES)
                repository_contract = (
                    source_parts[:2] == ('data', 'repositories')
                    and ABSTRACT_REPOSITORY.search(source_text) is not None
                )
                if view and (infrastructure or target_parts[:1] in [('data',), ('config',)]):
                    errors.append(f'{path.relative_to(root)}: view depends on data/composition: {name}')
                if (view_model
                        and (infrastructure
                             or target_parts[:2] == ('data', 'services')
                             or target_concrete_repository)):
                    errors.append(f'{path.relative_to(root)}: view model depends on infrastructure: {name}')
                if (repository_contract
                        and (name.startswith(('package:flutter/', 'package:flutter_riverpod/'))
                             or infrastructure
                             or target_parts[:2] == ('data', 'services'))):
                    errors.append(f'{path.relative_to(root)}: repository contract depends on infrastructure: {name}')
                if source_parts[0] == 'data' and target_parts[:1] in [('ui',), ('config',), ('routing',)]:
                    errors.append(f'{path.relative_to(root)}: data depends on UI/composition: {name}')
                if (source_parts[:2] == ('data', 'services')
                        and target_parts[:2] == ('data', 'repositories')):
                    errors.append(f'{path.relative_to(root)}: service depends on repository: {name}')
                if (source_parts[:2] == ('data', 'services')
                        and target_parts[:2] == ('domain', 'use_cases')):
                    errors.append(f'{path.relative_to(root)}: service depends on use case: {name}')
                if source_parts[0] == 'data' and name.startswith('package:flutter_riverpod/'):
                    errors.append(f'{path.relative_to(root)}: lower layer depends on Riverpod: {name}')
                if (source_parts[0] == 'utils'
                        and ((destination is not None
                              and target_parts[:1] != ('utils',))
                             or (destination is None
                                 and not name.startswith('dart:')))):
                    errors.append(f'{path.relative_to(root)}: utility depends on application/framework: {name}')
                if (source_parts[:2] == ('data', 'repositories')
                        and target_parts[:2] == ('data', 'repositories')
                        and target != path):
                    contract_names = re.findall(r'abstract\s+(?:interface\s+)?class\s+(\w+)', target_text)
                    own_contract = any(re.search(r'\b(?:implements|extends)\s+' + re.escape(contract) + r'\b', source_text)
                                       for contract in contract_names)
                    repository_target = (target_contract or target_concrete_repository
                                         or target.name.endswith('_repository.dart'))
                    if repository_target and not own_contract:
                        errors.append(f'{path.relative_to(root)}: repository depends on another repository: {name}')
                if (source_parts[:2] == ('ui', source_parts[1] if len(source_parts) > 1 else '')
                        and 'view_models' in source_parts
                        and target_parts[:1] == ('ui',)
                        and 'view_models' in target_parts
                        and destination != source
                        and (destination.name.endswith(('_view_model.dart', '_vm.dart'))
                             or re.search(r'extends\s+(?:\w*Notifier|ChangeNotifier)\b', target_text))):
                    errors.append(f'{path.relative_to(root)}: view model depends on another view model: {name}')
            if path.is_relative_to(app) and path.relative_to(app).parts[:1] == ('domain',):
                domain_parts = path.relative_to(app).parts
                forbidden = name.startswith(('package:flutter/', 'package:flutter_riverpod/', 'package:drift/', 'package:app_account/'))
                if target and target.is_relative_to(app):
                    rel = target.relative_to(app)
                    target_abstract_repository = (
                        rel.parts[:2] == ('data', 'repositories')
                        and ABSTRACT_REPOSITORY.search(target_text) is not None
                    )
                    repository_contract = (
                        domain_parts[:2] == ('domain', 'use_cases')
                        and target_abstract_repository
                    )
                    pure_contract = (
                        domain_parts[:2] == ('domain', 'use_cases')
                        and str(rel) == 'data/repositories/local/local_transaction.dart'
                    )
                    forbidden |= (
                        rel.parts[0] in ('app', 'ui', 'config', 'routing')
                        or str(rel).startswith('core/db/')
                        or ('data' in rel.parts and not (repository_contract or pure_contract))
                        or 'presentation' in rel.parts
                    )
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
