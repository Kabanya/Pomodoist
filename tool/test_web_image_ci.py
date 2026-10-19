"""Deployment regressions: wrong origin, stale versions and failed replacement."""
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

MODULE = Path(__file__).parent / 'deploy/web/image_ci.py'
spec = importlib.util.spec_from_file_location('image_ci', MODULE)
ci = importlib.util.module_from_spec(spec) if MODULE.exists() else None
if ci:
    spec.loader.exec_module(ci)

SHA = 'a' * 40
PREVIOUS = 'b' * 40
DIGEST = 'sha256:' + 'c' * 64


class FakeAPI:
    """Remote API stand-in: requests mutate the application, like Coolify."""
    def __init__(self):
        self.app = {'docker_registry_image_name': 'ghcr.io/kabanya/pomodoist-web',
                    'docker_registry_image_tag': PREVIOUS}
        self.release = PREVIOUS
        self.deployments = []
        self.fail_new = False
        self.fail_pull = False
        self.mutations = []

    def request(self, method, path, body=None):
        if method == 'GET' and path == '/applications/app':
            return dict(self.app)
        if method == 'PATCH' and path == '/applications/app':
            self.mutations.append((path, body))
            self.app.update(body)
            return {'uuid': 'app'}
        if method == 'PATCH' and path == '/applications/app/envs/bulk':
            self.mutations.append((path, body))
            self.release = body['data'][0]['value']
            return {'message': 'Environment variables updated.'}
        if method == 'POST' and path == '/applications/app/start':
            number = len(self.deployments)
            self.deployments.append((self.app['docker_registry_image_tag'], self.release))
            return {'deployment_uuid': str(number)}
        if method == 'GET' and path.startswith('/deployments/'):
            return {'status': 'failed' if self.fail_new and len(self.deployments) == 1 else 'finished'}
        raise AssertionError((method, path, body))


class ImageCITest(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(ci, 'image deployment controller has not been implemented')
        reporter = patch.object(ci, 'save_report')
        reporter.start()
        self.addCleanup(reporter.stop)

    def test_container_startup_connection_reset_is_retried(self):
        from types import SimpleNamespace
        def output(args, **kwargs):
            if args[1] == 'port':
                return '127.0.0.1:12345'
            if args[1] == 'exec':
                return ''
            return 'container'
        def urlopen(url, **kwargs):
            if url.endswith('/config.js'):
                return SimpleNamespace(read=lambda: (
                    b'https://app-test.pomodoist.com https://supabase-test.pomodoist.com '
                    b'https://app.pomodoist.com https://ewauihswbwduvklrozke.supabase.co'))
            raise ci.urllib.error.HTTPError(url, 404, 'absent', {}, None)
        responses = [ConnectionResetError('nginx starting'),
                     {'environment': 'staging', 'release': SHA},
                     {'environment': 'production', 'release': SHA}]
        with patch.object(ci, 'observe_url', side_effect=responses) as observe, \
             patch.object(ci.urllib.request, 'urlopen', side_effect=urlopen), \
             patch.object(ci.subprocess, 'check_output', side_effect=output), \
             patch.object(ci.subprocess, 'run', return_value=SimpleNamespace(
                 returncode=1, stderr='does not match this image')), \
             patch.object(ci.time, 'sleep') as sleep:
            ci.smoke('image', SHA)
        self.assertEqual(observe.call_count, 3)
        sleep.assert_called_once_with(1)

    def test_rejects_pull_requests_and_foreign_repositories(self):
        event = {'workflow_run': {'event': 'pull_request', 'conclusion': 'success',
                  'head_branch': 'main', 'head_sha': SHA,
                  'head_repository': {'full_name': 'Kabanya/Pomodoist'}}}
        with self.assertRaises(ValueError):
            ci.select_release(event, 'workflow_run')
        event['workflow_run']['event'] = 'push'
        event['workflow_run']['head_repository']['full_name'] = 'attacker/Pomodoist'
        with self.assertRaises(ValueError):
            ci.select_release(event, 'workflow_run')

    def test_requires_successful_validation_and_known_branch(self):
        event = {'workflow_run': {'event': 'push', 'conclusion': 'failure',
                  'head_branch': 'main', 'head_sha': SHA,
                  'head_repository': {'full_name': 'Kabanya/Pomodoist'}}}
        with self.assertRaises(ValueError):
            ci.select_release(event, 'workflow_run')
        event['workflow_run']['conclusion'] = 'success'
        self.assertEqual(ci.select_release(event, 'workflow_run'), ('production', 'main', SHA))
        event['workflow_run']['head_branch'] = 'develop'
        self.assertEqual(ci.select_release(event, 'workflow_run'), ('staging', 'develop', SHA))
        event['workflow_run']['head_branch'] = 'feature/x'
        with self.assertRaises(ValueError):
            ci.select_release(event, 'workflow_run')

    def test_manual_selection_requires_explicit_validated_sha(self):
        event = {'inputs': {'environment': 'staging', 'sha': SHA, 'deploy': False}}
        self.assertEqual(ci.select_release(event, 'workflow_dispatch'), ('staging', 'develop', SHA))
        event['inputs']['sha'] = 'main'
        with self.assertRaises(ValueError):
            ci.select_release(event, 'workflow_dispatch')

    def test_manual_sha_without_successful_validate_is_rejected(self):
        with patch.object(ci, 'gh', return_value={'workflow_runs': []}):
            with self.assertRaises(ValueError):
                ci.require_validation('develop', SHA)

    def test_success_on_another_branch_does_not_validate_sha(self):
        run = {'head_sha': SHA, 'head_branch': 'main', 'event': 'push',
               'conclusion': 'success', 'head_repository': {'full_name': 'Kabanya/Pomodoist'}}
        with patch.object(ci, 'gh', return_value={'workflow_runs': [run]}):
            with self.assertRaises(ValueError):
                ci.require_validation('develop', SHA)

    def test_partial_configuration_write_is_restored_before_start(self):
        api = FakeAPI()
        original = api.request
        fail_once = [True]
        def request(method, path, body=None):
            if path.endswith('/envs/bulk') and fail_once[0]:
                fail_once[0] = False
                raise RuntimeError('temporary write failure')
            return original(method, path, body)
        api.request = request
        with self.assertRaises(RuntimeError):
            ci.deploy(api, 'app', SHA, DIGEST, lambda: True,
                      lambda: {'release': api.release}, lambda: None, timeout=0)
        self.assertEqual(api.deployments, [(PREVIOUS, PREVIOUS)])

    def test_inconsistent_previous_release_is_not_overwritten(self):
        api = FakeAPI()
        with self.assertRaises(ValueError):
            ci.deploy(api, 'app', SHA, DIGEST, lambda: True,
                      lambda: {'release': SHA}, lambda: None, timeout=0)
        self.assertEqual(api.mutations, [])

    def test_stale_commit_never_changes_application(self):
        api = FakeAPI()
        with self.assertRaises(ValueError):
            ci.deploy(api, 'app', SHA, DIGEST, lambda: False,
                      lambda: {'release': PREVIOUS}, lambda: None, timeout=0)
        self.assertEqual(api.mutations, [])

    def test_release_and_image_are_switched_before_start(self):
        api = FakeAPI()
        ci.deploy(api, 'app', SHA, DIGEST, lambda: True,
                  lambda: {'release': api.release}, lambda: None, timeout=0)
        self.assertEqual(api.deployments, [(SHA, SHA)])
        self.assertEqual(api.app['docker_registry_image_tag'], SHA)

    def test_failed_health_restores_previous_image_and_release(self):
        api = FakeAPI()
        observed = iter([{'release': PREVIOUS}, {'release': 'wrong'}, {'release': PREVIOUS}])
        with self.assertRaises(RuntimeError):
            ci.deploy(api, 'app', SHA, DIGEST, lambda: True,
                      lambda: next(observed), lambda: None, timeout=0)
        self.assertEqual(api.deployments, [(SHA, SHA), (PREVIOUS, PREVIOUS)])
        self.assertEqual(api.release, PREVIOUS)

    def test_failed_coolify_deployment_rolls_back(self):
        api = FakeAPI()
        api.fail_new = True
        with self.assertRaises(RuntimeError):
            ci.deploy(api, 'app', SHA, DIGEST, lambda: True,
                      lambda: {'release': api.release}, lambda: None, timeout=0)
        self.assertEqual(api.deployments, [(SHA, SHA), (PREVIOUS, PREVIOUS)])

    def test_timed_out_remote_job_is_cancelled_before_rollback(self):
        api = FakeAPI()
        original = api.request
        active = [False]
        cancelled = []
        def request(method, path, body=None):
            if method == 'POST' and path.endswith('/start'):
                if active[0]:
                    return {'message': 'Deployment already queued for this commit.'}
                active[0] = True
            if method == 'POST' and path == '/deployments/0/cancel':
                active[0] = False
                cancelled.append('0')
                return {'message': 'cancelled'}
            if method == 'GET' and path == '/deployments/0':
                return {'status': 'in_progress' if active[0] else 'cancelled-by-user'}
            if method == 'GET' and path == '/deployments/1':
                active[0] = False
                return {'status': 'finished'}
            return original(method, path, body)
        api.request = request
        with self.assertRaises(RuntimeError):
            ci.deploy(api, 'app', SHA, DIGEST, lambda: True,
                      lambda: {'release': api.release}, lambda: None, timeout=0)
        self.assertEqual(cancelled, ['0'])
        self.assertEqual(api.deployments, [(SHA, SHA), (PREVIOUS, PREVIOUS)])

    def test_transient_poll_error_does_not_restart_healthy_rollout(self):
        api = FakeAPI()
        original = api.request
        first = [True]
        def request(method, path, body=None):
            if method == 'GET' and path.startswith('/deployments/') and first[0]:
                first[0] = False
                raise ci.TransientAPIError('HTTP 503')
            return original(method, path, body)
        api.request = request
        with patch.object(ci.time, 'sleep'):
            ci.deploy(api, 'app', SHA, DIGEST, lambda: True,
                      lambda: {'release': api.release}, lambda: None, timeout=1)
        self.assertEqual(api.deployments, [(SHA, SHA)])

    def test_coolify_cancelled_by_user_is_terminal(self):
        api = FakeAPI()
        original = api.request
        def request(method, path, body=None):
            if method == 'GET' and path == '/deployments/0':
                return {'status': 'cancelled-by-user'}
            return original(method, path, body)
        api.request = request
        with patch.object(ci.time, 'sleep') as sleep:
            with self.assertRaisesRegex(RuntimeError, 'Coolify deployment 0 cancelled-by-user'):
                ci.deploy(api, 'app', SHA, DIGEST, lambda: True,
                          lambda: {'release': api.release}, lambda: None, timeout=0)
        sleep.assert_not_called()
        self.assertEqual(api.deployments, [(SHA, SHA), (PREVIOUS, PREVIOUS)])

    def test_lost_start_response_is_recovered_and_cancelled_before_restore(self):
        api = FakeAPI()
        original = api.request
        active = [False]
        api.active_deployments = lambda uuid: ['0'] if active[0] else []
        cancelled = []
        def request(method, path, body=None):
            if method == 'POST' and path.endswith('/start') and not api.deployments:
                original(method, path, body)
                active[0] = True
                raise ci.urllib.error.URLError('start response lost')
            if method == 'POST' and path == '/deployments/0/cancel':
                active[0] = False
                cancelled.append('0')
                return {}
            if method == 'GET' and path == '/deployments/0':
                return {'status': 'in_progress' if active[0] else 'cancelled-by-user'}
            return original(method, path, body)
        api.request = request
        with self.assertRaises(RuntimeError):
            ci.deploy(api, 'app', SHA, DIGEST, lambda: True,
                      lambda: {'release': api.release}, lambda: None, timeout=0)
        self.assertEqual(cancelled, ['0'])
        self.assertEqual(api.deployments, [(SHA, SHA), (PREVIOUS, PREVIOUS)])

    def test_job_finishing_during_cancellation_still_allows_rollback(self):
        api = FakeAPI()
        original = api.request
        finished = [False]
        def request(method, path, body=None):
            if method == 'GET' and path == '/deployments/0':
                return {'status': 'finished' if finished[0] else 'in_progress'}
            if method == 'POST' and path == '/deployments/0/cancel':
                finished[0] = True
                raise RuntimeError('Cannot cancel: HTTP 400, already finished')
            return original(method, path, body)
        api.request = request
        with self.assertRaises(RuntimeError):
            ci.deploy(api, 'app', SHA, DIGEST, lambda: True,
                      lambda: {'release': api.release}, lambda: None, timeout=0)
        self.assertEqual(api.deployments, [(SHA, SHA), (PREVIOUS, PREVIOUS)])

    def test_failed_pull_does_not_mutate_application(self):
        api = FakeAPI()
        def cannot_pull():
            raise RuntimeError('registry unavailable')
        with self.assertRaises(RuntimeError):
            ci.deploy(api, 'app', SHA, DIGEST, lambda: True,
                      lambda: {'release': PREVIOUS}, cannot_pull, timeout=0)
        self.assertEqual(api.mutations, [])

    def test_stale_commit_after_preflight_does_not_mutate(self):
        api = FakeAPI()
        fresh = iter([True, False])
        with self.assertRaises(ValueError):
            ci.deploy(api, 'app', SHA, DIGEST, lambda: next(fresh),
                      lambda: {'release': PREVIOUS}, lambda: None, timeout=0)
        self.assertEqual(api.mutations, [])


if __name__ == '__main__':
    unittest.main()
