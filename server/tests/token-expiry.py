#!/usr/bin/env python3
"""Exercise the Flutter client against short-lived, real local GoTrue sessions."""
import collections
import http.client
import http.server
import json
import os
import pathlib
import shutil
import sys
import subprocess
import tempfile
import threading
import time
import urllib.request
import urllib.error
import uuid

if sys.argv[1:] != ['--local']:
    raise SystemExit('Pass --local to create disposable fixtures in the local self-hosted stack')
ROOT = pathlib.Path(__file__).resolve().parents[2]
workspace = pathlib.Path(os.environ.get('POMODOIST_AUTH_EXPIRY_TEST_WORKSPACE', ROOT / 'apps/flutter')).resolve()
flutter = ROOT / '.fvm/flutter_sdk/bin/flutter'
if not flutter.is_file():
    raise SystemExit('Install the repository-pinned Flutter SDK first')
config = json.loads(subprocess.check_output(['docker', 'inspect', 'pomodoist-selfhost-auth']))[0]
env = dict(value.split('=', 1) for value in config['Config']['Env'] if '=' in value)
network = next(iter(config['NetworkSettings']['Networks']))
keys = json.loads(subprocess.check_output(['node', '--input-type=module', '-e', "import {readFileSync} from 'node:fs'; import {parseEnv} from 'node:util'; const e=parseEnv(readFileSync('server/.env','utf8')); process.stdout.write(JSON.stringify({anon:e.ANON_KEY,service:e.SERVICE_ROLE_KEY}));"], cwd=ROOT))
name = 'codex-pomodoist-auth-expiry-' + uuid.uuid4().hex[:8]
private = pathlib.Path(tempfile.mkdtemp(prefix='pomodoist-auth-expiry-config-'))
env.update({'GOTRUE_JWT_EXP': '40', 'GOTRUE_SECURITY_CAPTCHA_ENABLED': 'false', 'GOTRUE_EXTERNAL_GOOGLE_ENABLED': 'false', 'GOTRUE_SMTP_HOST': '127.0.0.1', 'GOTRUE_SMTP_PORT': '1'})
envfile = private / 'auth.env'
envfile.write_text('\n'.join(key + '=' + value for key, value in env.items()) + '\n')
envfile.chmod(0o600)
counts = collections.Counter()
created_users = set()
server = None

try:
    subprocess.run(['docker', 'run', '-d', '--name', name, '--network', network, '--env-file', str(envfile), '-p', '127.0.0.1::9999', config['Image']], check=True, stdout=subprocess.DEVNULL)
    envfile.unlink()
    port = int(subprocess.check_output(['docker', 'port', name, '9999/tcp'], text=True).strip().rsplit(':', 1)[1])
    for attempt in range(100):
        try:
            with urllib.request.urlopen(f'http://127.0.0.1:{port}/health', timeout=1) as response:
                if response.status == 200:
                    break
        except Exception:
            time.sleep(.1)
    else:
        raise RuntimeError('Isolated Auth did not become healthy')

    class Proxy(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'
        def log_message(self, *args):
            pass
        def forward(self):
            auth = self.path.startswith('/auth/v1/')
            if not auth:
                self.send_error(404)
                return
            path = self.path[len('/auth/v1'):] if auth else self.path
            upstream = http.client.HTTPConnection('127.0.0.1', port if auth else 55421, timeout=20)
            body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
            headers = {key: value for key, value in self.headers.items() if key.lower() not in {'host', 'connection', 'transfer-encoding'}}
            try:
                upstream.request(self.command, path, body, headers)
                response = upstream.getresponse()
                content = response.read()
                if auth and self.command == 'POST' and path == '/admin/users' and response.status == 200:
                    created = json.loads(content)
                    if created.get('email', '').startswith('token-expiry-') and created.get('email', '').endswith('@example.invalid'):
                        created_users.add(created['id'])
                if auth:
                    route = path.split('?')[0]
                    if route.startswith('/admin/users/'):
                        route = '/admin/users/:fixture'
                    counts[f'{self.command} {route} {response.status}'] += 1
                self.send_response(response.status)
                for key, value in response.getheaders():
                    if key.lower() not in {'content-length', 'transfer-encoding', 'connection'}:
                        self.send_header(key, value)
                self.send_header('Content-Length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
            finally:
                upstream.close()
        do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_OPTIONS = forward

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Proxy)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    test_env = os.environ.copy()
    test_env.update({'POMODOIST_AUTH_EXPIRY_TEST_URL': f'http://127.0.0.1:{server.server_port}', 'POMODOIST_AUTH_EXPIRY_TEST_ANON_KEY': keys['anon'], 'POMODOIST_AUTH_EXPIRY_TEST_SERVICE_KEY': keys['service']})
    print('Isolated loopback GoTrue ready; JWT lifetime 40 seconds; original Auth unchanged', flush=True)
    started = time.monotonic()
    result = subprocess.run([str(flutter), 'test', '--no-pub', 'test/live_token_expiry_test.dart', '--reporter', 'expanded'], cwd=workspace, env=test_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=240)
    print(result.stdout, end='')
    passed = result.returncode == 0 and 'All tests passed!' in result.stdout
    print(json.dumps({'passed': passed, 'durationMs': round((time.monotonic() - started) * 1000), 'authResponses': dict(counts)}))
    if not passed:
        raise SystemExit(1)
finally:
    for user_id in created_users:
        try:
            request = urllib.request.Request(f'http://127.0.0.1:{port}/admin/users/{user_id}', method='DELETE', headers={'Authorization': 'Bearer ' + keys['service']})
            with urllib.request.urlopen(request, timeout=5) as response:
                pass
        except urllib.error.HTTPError as error:
            if error.code != 404:
                print('Fixture cleanup failed:', error.code, flush=True)
        except (urllib.error.URLError, TimeoutError):
            print('Fixture cleanup failed: local Auth unavailable', flush=True)
    if server:
        server.shutdown()
        server.server_close()
    subprocess.run(['docker', 'rm', '-f', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    shutil.rmtree(private)
