#!/usr/bin/env python3
"""Trusted release selection, immutable GHCR images and serialized Coolify rollout.

Only Python's standard library is needed. Credentials are read from the process
 environment and never included in reports or exception bodies.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

REPOSITORY = 'Kabanya/Pomodoist'
IMAGE = 'ghcr.io/kabanya/pomodoist-web'
BRANCHES = {'staging': 'develop', 'production': 'main'}
SHA_RE = re.compile(r'[0-9a-f]{40}')
DIGEST_RE = re.compile(r'sha256:[0-9a-f]{64}')
TERMINAL = {'finished', 'failed', 'cancelled', 'canceled', 'cancelled-by-user'}


class TransientAPIError(RuntimeError):
    """A remote control-plane outage that is safe to retry while polling."""



def full_sha(value):
    if not SHA_RE.fullmatch(value or ''):
        raise ValueError('A full lowercase release SHA is required')
    return value


def select_release(event, kind):
    if kind == 'workflow_run':
        run = event['workflow_run']
        if (run['event'] != 'push' or run['conclusion'] != 'success'
                or run['head_repository']['full_name'].lower() != REPOSITORY.lower()):
            raise ValueError('Only successful Validate pushes from the source repository are accepted')
        branch = run['head_branch']
        environment = next((env for env, name in BRANCHES.items() if name == branch), None)
        if environment is None:
            raise ValueError('Release branch must be main or develop')
        return environment, branch, full_sha(run['head_sha'])
    if kind != 'workflow_dispatch':
        raise ValueError('Unsupported event')
    inputs = event['inputs']
    environment = inputs['environment']
    if environment not in BRANCHES:
        raise ValueError('Unknown release environment')
    return environment, BRANCHES[environment], full_sha(inputs['sha'])


def gh(path):
    return json.loads(subprocess.check_output(['gh', 'api', path], text=True))


def is_latest(branch, sha):
    return gh(f'repos/{REPOSITORY}/commits/{branch}')['sha'] == sha


def require_validation(branch, sha):
    # workflow_run is only a wakeup signal: independently verify the exact SHA.
    runs = gh(f'repos/{REPOSITORY}/actions/workflows/validate.yml/runs?head_sha={sha}&event=push&per_page=100')['workflow_runs']
    if not any(run['head_sha'] == sha and run['head_branch'] == branch
               and run['event'] == 'push' and run['conclusion'] == 'success'
               and run['head_repository']['full_name'].lower() == REPOSITORY.lower()
               for run in runs):
        raise ValueError('The selected SHA has no successful push Validate on this branch')


def registry_digest(tag):
    """Return None only for a genuinely absent manifest, never on auth/network errors."""
    full_sha(tag)
    token = os.environ['GH_TOKEN']
    basic = base64.b64encode(f'{os.environ.get("GITHUB_ACTOR", "Kabanya")}:{token}'.encode()).decode()
    request = urllib.request.Request('https://ghcr.io/token?service=ghcr.io&scope=repository:kabanya/pomodoist-web:pull',
                                     headers={'Authorization': f'Basic {basic}'})
    with urllib.request.urlopen(request, timeout=30) as response:
        bearer = json.load(response)['token']
    request = urllib.request.Request(f'https://ghcr.io/v2/kabanya/pomodoist-web/manifests/{tag}',
        headers={'Authorization': f'Bearer {bearer}',
                 'Accept': 'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json'}, method='HEAD')
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            digest = response.headers['Docker-Content-Digest']
            if not DIGEST_RE.fullmatch(digest or ''):
                raise RuntimeError('Registry did not return an image digest')
            return digest
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise RuntimeError(f'Registry manifest lookup failed: HTTP {error.code}') from None


class Coolify:
    def __init__(self, url, token):
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != 'https' or parsed.hostname in ('localhost', '127.0.0.1'):
            raise ValueError('Coolify requires the existing public HTTPS endpoint')
        self.base = urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, '/api/v1', '', ''))
        self.token = token

    def request(self, method, path, body=None):
        request = urllib.request.Request(self.base + path, method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={'Authorization': f'Bearer {self.token}', 'Content-Type': 'application/json', 'Accept': 'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            failure = TransientAPIError if error.code in (408, 429, 500, 502, 503, 504) else RuntimeError
            raise failure(f'Coolify {method} {path}: HTTP {error.code}') from None

    def active_deployments(self, uuid):
        result = self.request('GET', f'/deployments/applications/{uuid}?take=100')
        deployments = result.get('deployments', []) if isinstance(result, dict) else result
        return [d['deployment_uuid'] for d in deployments if d['status'] not in TERMINAL]

    def digest(self, tag):
        digest = registry_digest(tag)
        if digest is None:
            raise RuntimeError('Previous image is unavailable; refusing an unrecoverable rollout')
        return digest


def observe_url(url):
    nonce = time.time_ns()
    with urllib.request.urlopen(url.rstrip('/') + f'/healthz?ci={nonce}', timeout=10) as response:
        if response.status != 200:
            raise RuntimeError('Health check did not return HTTP 200')
    with urllib.request.urlopen(url.rstrip('/') + f'/version.json?ci={nonce}', timeout=10) as response:
        return json.load(response)


def save_report(report):
    Path('web-deployment.json').write_text(json.dumps(report, indent=2) + '\n')


def deploy(api, uuid, sha, digest, latest, observe, preflight, timeout=300):
    full_sha(sha)
    if not DIGEST_RE.fullmatch(digest):
        raise ValueError('A registry digest is required')
    if not latest():
        raise ValueError('Release superseded before preflight')
    preflight()
    app = api.request('GET', f'/applications/{uuid}')
    previous_tag = app['docker_registry_image_tag']
    previous_release = full_sha(observe()['release'])
    # A mismatched baseline is already broken; do not compound it.
    if previous_tag != previous_release or app['docker_registry_image_name'] != IMAGE:
        raise ValueError('Previous image and running release do not form a recoverable pair')
    previous_digest = api.digest(previous_tag) if hasattr(api, 'digest') else None
    report = {'requested_sha': sha, 'digest': digest, 'application': uuid,
              'previous': {'tag': previous_tag, 'digest': previous_digest, 'release': previous_release}}
    save_report(report)
    if hasattr(api, 'active_deployments') and api.active_deployments(uuid):
        raise ValueError('An external deployment is already active; refusing to race it')
    active_deployment = None
    start_ambiguous = False
    # Last branch check is immediately before the first mutation.
    if not latest():
        raise ValueError('Release superseded after preflight')

    def configure(tag, release):
        api.request('PATCH', f'/applications/{uuid}', {'docker_registry_image_tag': tag})
        api.request('PATCH', f'/applications/{uuid}/envs/bulk', {'data': [{
            'key': 'POMODOIST_RELEASE', 'value': release, 'is_buildtime': False,
            'is_runtime': True, 'is_preview': False}]})

    def start_and_wait(expected):
        nonlocal active_deployment, start_ambiguous
        start_ambiguous = True
        started = api.request('POST', f'/applications/{uuid}/start')
        deployment = started.get('deployment_uuid')
        if not deployment:
            raise RuntimeError('Coolify did not identify the queued deployment')
        active_deployment = deployment
        start_ambiguous = False
        deadline = time.monotonic() + timeout
        last = 'pending'
        while True:
            try:
                status = api.request('GET', f'/deployments/{deployment}')['status']
                if status in TERMINAL:
                    active_deployment = None
                if status in TERMINAL - {'finished'}:
                    raise RuntimeError(f'Coolify deployment {deployment} {status}')
                if status == 'finished':
                    actual = observe()
                    if actual['release'] == expected:
                        return deployment
                    last = 'unexpected release SHA'
                else:
                    last = status
            except (urllib.error.URLError, TimeoutError, ConnectionError, KeyError, TransientAPIError) as error:
                last = type(error).__name__
            if time.monotonic() >= deadline:
                raise RuntimeError(f'Deployment {deployment} verification timed out: {last}')
            time.sleep(min(5, max(0, deadline - time.monotonic())))

    def drain_before_rollback():
        # Coolify deduplicates active Docker Image starts independently of tag.
        # A lost POST response may still have queued a job: recover its UUID.
        pending = [active_deployment] if active_deployment else []
        if start_ambiguous:
            if not hasattr(api, 'active_deployments'):
                raise RuntimeError('Cannot recover an ambiguous deployment start')
            pending.extend(api.active_deployments(uuid))
        for deployment in set(pending):
            deadline = time.monotonic() + 60
            cancellation_sent = False
            while True:
                try:
                    status = api.request('GET', f'/deployments/{deployment}')['status']
                    if status in TERMINAL:
                        break
                    if not cancellation_sent:
                        try:
                            api.request('POST', f'/deployments/{deployment}/cancel')
                        except RuntimeError:
                            # Cancellation races a natural completion (HTTP 400).
                            # Only a confirmed terminal state makes restoration safe.
                            if api.request('GET', f'/deployments/{deployment}')['status'] in TERMINAL:
                                break
                            raise
                        cancellation_sent = True
                except (urllib.error.URLError, TimeoutError, ConnectionError, TransientAPIError):
                    pass
                if time.monotonic() >= deadline:
                    raise RuntimeError('Active deployment could not be stopped; refusing competing rollback')
                time.sleep(1)

    try:
        configure(sha, sha)
        report['deployment'] = start_and_wait(sha)
        report['status'] = 'success'
    except Exception as error:
        report['status'] = 'failed'
        # Restore both fields even if the second PATCH or start failed.
        try:
            drain_before_rollback()
            configure(previous_tag, previous_release)
            report['rollback_deployment'] = start_and_wait(previous_release)
            report['rollback'] = 'success'
        except Exception as rollback_error:
            report['rollback'] = 'failed'
            save_report(report)
            raise RuntimeError(f'Rollout failed ({type(error).__name__}); rollback needs operator attention ({type(rollback_error).__name__})') from None
        save_report(report)
        raise RuntimeError(f'Rollout failed and previous release restored: {error}') from None
    save_report(report)
    return report


def smoke(image, sha):
    """The exact same prebuilt image must support both runtime environments."""
    for environment in ('staging', 'production'):
        web = 'https://app-test.pomodoist.com' if environment == 'staging' else 'https://app.pomodoist.com'
        supabase = 'https://supabase-test.pomodoist.com' if environment == 'staging' else 'https://ewauihswbwduvklrozke.supabase.co'
        args = ['docker', 'run', '--detach', '--publish', '127.0.0.1::8080']
        for key, value in {'POMODOIST_ENVIRONMENT': environment, 'POMODOIST_RELEASE': sha,
                           'POMODOIST_WEB_URL': web, 'SUPABASE_URL': supabase,
                           'SUPABASE_ANON_KEY': 'ci-public-placeholder', 'TURNSTILE_SITE_KEY': 'ci-public-placeholder'}.items():
            args += ['--env', f'{key}={value}']
        container = subprocess.check_output(args + [image], text=True).strip()
        try:
            port = subprocess.check_output(['docker', 'port', container, '8080'], text=True).strip().rsplit(':', 1)[1]
            url = f'http://127.0.0.1:{port}'
            for attempt in range(30):
                try:
                    actual = observe_url(url)
                    assert actual == {'environment': environment, 'release': sha}, actual
                    break
                except (urllib.error.URLError, TimeoutError, ConnectionError):
                    if attempt == 29:
                        raise
                    time.sleep(1)
            config = urllib.request.urlopen(url + '/config.js', timeout=10).read().decode()
            assert supabase in config and web in config
            for path in ('/main.dart.js.map', '/.env', '/GoogleOAuth.env'):
                try:
                    urllib.request.urlopen(url + path, timeout=10)
                except urllib.error.HTTPError as error:
                    assert error.code == 404
                else:
                    raise AssertionError(f'Private artifact is served: {path}')
            maps = subprocess.check_output(['docker', 'exec', container, 'find', '/usr/share/nginx/html', '-name', '*.map'], text=True)
            assert not maps.strip(), 'Source maps in runtime image'
        finally:
            subprocess.run(['docker', 'rm', '--force', container], check=True, stdout=subprocess.DEVNULL)
    rejected = subprocess.run(['docker', 'run', '--rm', '--env', 'POMODOIST_ENVIRONMENT=staging',
        '--env', 'POMODOIST_RELEASE=' + ('0' * 40 if sha != '0' * 40 else '1' * 40),
        '--env', 'POMODOIST_WEB_URL=https://app-test.pomodoist.com',
        '--env', 'SUPABASE_URL=https://supabase-test.pomodoist.com',
        '--env', 'SUPABASE_ANON_KEY=ci-public-placeholder', image], capture_output=True, text=True)
    assert rejected.returncode != 0 and 'does not match this image' in rejected.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['select', 'head', 'lookup', 'smoke', 'deploy'])
    parser.add_argument('--sha')
    parser.add_argument('--branch')
    parser.add_argument('--digest')
    args = parser.parse_args()
    if args.command == 'select':
        environment, branch, sha = select_release(json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text()), os.environ['GITHUB_EVENT_NAME'])
        require_validation(branch, sha)
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'environment={environment}\nbranch={branch}\nsha={sha}\n')
        return
    sha = full_sha(args.sha)
    if args.command == 'head':
        if not is_latest(args.branch, sha):
            raise ValueError('Release superseded; no deployment performed')
    elif args.command == 'lookup':
        digest = registry_digest(sha)
        if gh('users/Kabanya/packages/container/pomodoist-web')['visibility'] != 'private':
            raise RuntimeError('The web image package must remain private')
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'exists={str(digest is not None).lower()}\ndigest={digest or ""}\n')
    elif args.command == 'smoke':
        smoke(f'{IMAGE}:{sha}', sha)
    else:
        require_validation(args.branch, sha)
        def preflight():
            if registry_digest(sha) != args.digest:
                raise RuntimeError('The immutable tag no longer resolves to the tested digest')
        report = deploy(Coolify(os.environ['COOLIFY_URL'], os.environ['COOLIFY_IMAGE_TOKEN']),
            os.environ['COOLIFY_IMAGE_UUID'], sha, args.digest,
            lambda: is_latest(args.branch, sha), lambda: observe_url(os.environ['WEB_URL']), preflight)
        print(json.dumps(report))


if __name__ == '__main__':
    main()
