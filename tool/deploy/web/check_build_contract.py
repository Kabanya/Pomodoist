#!/usr/bin/env python3
"""Prove the web image is environment-independent and built from versioned args.

Coolify builds `tool/deploy/web/Dockerfile` on its own infrastructure, so the
build arguments cannot live only in that dashboard: nothing in the repository
would notice when they drift. This checker reads the Dockerfile, the versioned
`build-args.env`, every in-repository build site and the self-hosted compose
service, and fails when the "one image plus runtime environment" assumption
stops holding.

Run it from anywhere: `python3 tool/deploy/web/check_build_contract.py`.
"""
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[3]

# The only two build arguments the image may accept. Everything that differs
# between staging, production and self-hosted has to arrive as container
# environment variables instead.
STATIC_ARGS = {'POMODOIST_BILLING_CHANNEL': 'stripe'}
DYNAMIC_ARGS = {'RELEASE_SHA'}
EXPECTED_ARGS = set(STATIC_ARGS) | DYNAMIC_ARGS

# Names the runtime reads. None of them may be frozen into the image.
RUNTIME_ONLY = {
    'POMODOIST_ENVIRONMENT',
    'POMODOIST_RELEASE',
    'POMODOIST_WEB_URL',
    'SUPABASE_URL',
    'SUPABASE_ANON_KEY',
    'TURNSTILE_SITE_KEY',
    'SENTRY_DSN',
}

# Names the Dockerfile must declare and then refuse as non-empty build
# arguments. Coolify injects a build argument for every dashboard variable
# marked "buildtime"; the guard turns such an injection into a failed build
# instead of an image that has one environment frozen into it. Keeping the
# guarded set equal to RUNTIME_ONLY is what stops the guard from being
# bypassed by dropping a declaration.
GUARDED_ARGS = RUNTIME_ONLY
GUARD_LOOP = re.compile(r'for name in ([^;]+);', re.M)
GUARD_FAILURE = 'must stay a runtime environment variable'

BUILD_SITE_NAMES = [
    'tool/deploy/web/build_image.sh',
    'tool/export_web_sourcemaps.sh',
    'tool/test_sentry_artifacts.sh',
    'tool/test_web_container.sh',
]

ARG_DECLARATION = re.compile(r'^\s*ARG\s+([A-Za-z_][A-Za-z0-9_]*)', re.M)
BUILD_ARG = re.compile(r'--build-arg[= ]"?([A-Za-z_][A-Za-z0-9_]*)')
DART_DEFINE = re.compile(r'--dart-define=([A-Za-z_][A-Za-z0-9_]*)')
RUNTIME_REQUIRED = re.compile(
    r'^\s*\[\s*-n\s+"\$\{([A-Za-z_][A-Za-z0-9_]*):-?\}"\s*\]', re.M)

DOCKERFILE = 'tool/deploy/web/Dockerfile'
ENTRYPOINT = 'tool/deploy/web/entrypoint.sh'
BUILD_ARGS = 'tool/deploy/web/build-args.env'
COMPOSE = 'server/compose.yaml'

failures = []
root = ROOT


def fail(message):
    failures.append(message)


def read(path):
    try:
        return (root / path).read_text()
    except OSError as error:
        fail(f'cannot read {path}: {error}')
        return ''


def service_block(compose, name):
    """Return the text of one top-level service, or None."""
    lines = compose.splitlines()
    try:
        start = next(i for i, line in enumerate(lines)
                     if re.fullmatch(rf'  {re.escape(name)}:', line))
    except StopIteration:
        return None
    block = []
    for line in lines[start + 1:]:
        if line.strip() and not line.startswith('    '):
            break
        block.append(line)
    return '\n'.join(block)


def mapping_entries(block, key):
    """Return the `key: value` pairs of one nested mapping inside `block`."""
    lines = block.splitlines()
    try:
        start = next(i for i, line in enumerate(lines)
                     if re.fullmatch(rf'\s+{re.escape(key)}:', line))
    except StopIteration:
        return None
    indent = len(lines[start]) - len(lines[start].lstrip())
    entries = {}
    for line in lines[start + 1:]:
        if not line.strip():
            continue
        current = len(line) - len(line.lstrip())
        if current <= indent:
            break
        match = re.fullmatch(r'\s*([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)\s*', line)
        if match:
            entries[match.group(1)] = match.group(2)
    return entries


def check_dockerfile():
    dockerfile = read(DOCKERFILE)
    if not dockerfile:
        return

    declared = set(ARG_DECLARATION.findall(dockerfile))
    if declared != EXPECTED_ARGS | GUARDED_ARGS:
        fail(f'{DOCKERFILE} declares ARG {sorted(declared)}; '
             f'expected exactly {sorted(EXPECTED_ARGS | GUARDED_ARGS)}. Every '
             'runtime variable needs a declaration, otherwise the guard cannot '
             'tell an injected value from an unset one')

    if GUARDED_ARGS != RUNTIME_ONLY:
        fail('GUARDED_ARGS no longer covers every runtime variable, so the '
             'Dockerfile guard cannot be trusted')

    guarded = {name for group in GUARD_LOOP.findall(dockerfile)
               for name in group.split()}
    missing = sorted(GUARDED_ARGS - guarded)
    if GUARD_FAILURE not in dockerfile:
        fail(f'{DOCKERFILE} has no guard rejecting a build argument that '
             'carries a runtime value')
    elif missing:
        fail(f'{DOCKERFILE} does not reject an injected build argument for '
             f'{missing}')

    defines = set(DART_DEFINE.findall(dockerfile))
    if defines != set(STATIC_ARGS):
        fail(f'{DOCKERFILE} compiles with --dart-define '
             f'{sorted(defines)}; the web image may only fix '
             f'{sorted(STATIC_ARGS)} at build time')

    for name, value in STATIC_ARGS.items():
        guard = f'[ "${name}" = {value} ]'
        if guard not in dockerfile:
            fail(f'{DOCKERFILE} does not guard {name} == '
                 f'{value}')

    if not re.search(r"grep -Eq '\^\[0-9a-f\]\{40\}\$'", dockerfile):
        fail(f'{DOCKERFILE} does not validate RELEASE_SHA '
             'as a full lowercase Git SHA')


def check_build_args_file():
    text = read(BUILD_ARGS)
    if not text:
        return

    values = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if '=' not in line:
            fail(f'{BUILD_ARGS} has a malformed line: {line}')
            continue
        name, value = line.split('=', 1)
        values[name.strip()] = value.strip()

    if values != STATIC_ARGS:
        fail(f'{BUILD_ARGS} records {values}; expected '
             f'{STATIC_ARGS}')

    for name in DYNAMIC_ARGS:
        if name in values:
            fail(f'{BUILD_ARGS} pins {name}, which must come '
                 'from the deployed commit instead')


def check_compose():
    compose = read(COMPOSE)
    if not compose:
        return

    web = service_block(compose, 'web')
    if web is None:
        fail(f'{COMPOSE} has no web service')
        return

    if 'dockerfile: tool/deploy/web/Dockerfile' not in web:
        fail(f'{COMPOSE} web service does not build '
             'tool/deploy/web/Dockerfile')

    args = mapping_entries(web, 'args')
    if args is None:
        fail(f'{COMPOSE} web service declares no build args')
        args = {}
    if set(args) != EXPECTED_ARGS:
        fail(f'{COMPOSE} web build args are {sorted(args)}; '
             f'expected {sorted(EXPECTED_ARGS)}')
    for name, value in STATIC_ARGS.items():
        if args.get(name) != value:
            fail(f'{COMPOSE} web build arg {name} is '
                 f'{args.get(name)!r}; expected {value!r}')
    if 'POMODOIST_RELEASE' not in args.get('RELEASE_SHA', ''):
        fail(f'{COMPOSE} web build arg RELEASE_SHA must come '
             'from POMODOIST_RELEASE')

    environment = mapping_entries(web, 'environment') or {}
    if not RUNTIME_ONLY.issubset(environment):
        missing = sorted(RUNTIME_ONLY - set(environment))
        fail(f'{COMPOSE} web service does not pass the '
             f'runtime environment: {missing}')


def check_entrypoint():
    text = read(ENTRYPOINT)
    if not text:
        return

    required = set(RUNTIME_REQUIRED.findall(text))
    expected = RUNTIME_ONLY - {'SENTRY_DSN'}
    if not expected.issubset(required):
        fail(f'{ENTRYPOINT} no longer requires '
             f'{sorted(expected - required)} at startup')

    compose = read(COMPOSE)
    web = service_block(compose, 'web') if compose else None
    environment = mapping_entries(web, 'environment') if web else None
    if environment is not None:
        unread = sorted(set(environment) - RUNTIME_ONLY)
        if unread:
            fail(f'{COMPOSE} passes {unread} to the web '
                 'container, but the entrypoint never reads them')


def check_build_sites():
    for name in BUILD_SITE_NAMES:
        text = read(name)
        if not text:
            continue
        if 'tool/deploy/web/Dockerfile' not in text:
            fail(f'{name} does not build tool/deploy/web/Dockerfile')

        passed = set(BUILD_ARG.findall(text))
        unexpected = passed - EXPECTED_ARGS
        if unexpected:
            fail(f'{name} passes build args {sorted(unexpected)}, which the '
                 'image does not accept')
        if DYNAMIC_ARGS - passed:
            fail(f'{name} does not pass {sorted(DYNAMIC_ARGS - passed)}')
        channel = STATIC_ARGS['POMODOIST_BILLING_CHANNEL']
        values = re.findall(
            r'--build-arg[= ]"?POMODOIST_BILLING_CHANNEL=([^"\s\\]+)', text)
        if channel in values:
            continue
        # A script may forward the value from build-args.env instead of
        # repeating the literal, as long as it really sources that file.
        if values == ['$POMODOIST_BILLING_CHANNEL'] and \
                'tool/deploy/web/build-args.env' in text:
            continue
        fail(f'{name} does not build with POMODOIST_BILLING_CHANNEL={channel} '
             f'(found {values})')


def check(tree=ROOT):
    """Return the contract violations under `tree`, empty when it holds."""
    global root, failures
    previous_root, previous_failures = root, failures
    root, failures = tree, []
    try:
        for step in (check_dockerfile, check_build_args_file, check_compose,
                     check_entrypoint, check_build_sites):
            step()
        return list(failures)
    finally:
        root, failures = previous_root, previous_failures


def main():
    messages = check()
    if messages:
        for message in messages:
            print(f'FAIL: {message}', file=sys.stderr)
        return 1
    print('Web image build contract holds: '
          f'{sorted(EXPECTED_ARGS)} from versioned sources, runtime '
          f'configuration limited to {sorted(RUNTIME_ONLY)}.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
