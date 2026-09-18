import shutil
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool/deploy/web'))

import check_build_contract as contract


class WebBuildContractTests(unittest.TestCase):
    """The checker is the only proof that the web image stays env-independent.

    A checker that only ever passes proves nothing, so every invariant is
    exercised against a mutated copy of the real files.
    """

    def setUp(self):
        self._directory = TemporaryDirectory()
        self.root = Path(self._directory.name)
        for name in [contract.DOCKERFILE, contract.ENTRYPOINT,
                     contract.BUILD_ARGS, contract.COMPOSE,
                     *contract.BUILD_SITE_NAMES]:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)

    def tearDown(self):
        self._directory.cleanup()

    def edit(self, name, old, new):
        path = self.root / name
        text = path.read_text()
        self.assertIn(old, text, f'{name} no longer contains {old!r}')
        path.write_text(text.replace(old, new, 1))

    def assert_rejected(self, needle):
        failures = contract.check(self.root)
        self.assertTrue(any(needle in message for message in failures),
                        f'contract accepted a violation; failures: {failures}')

    def test_repository_tree_holds(self):
        self.assertEqual(contract.check(self.root), [])

    def test_runtime_variable_without_a_declaration_is_rejected(self):
        self.edit(contract.DOCKERFILE, 'ARG TURNSTILE_SITE_KEY\n', '')
        self.assert_rejected('declares ARG')

    def test_runtime_variable_dropped_from_the_guard_is_rejected(self):
        self.edit(contract.DOCKERFILE,
                  'SUPABASE_ANON_KEY TURNSTILE_SITE_KEY', 'TURNSTILE_SITE_KEY')
        self.assert_rejected('does not reject an injected build argument')

    def test_missing_guard_loop_is_rejected(self):
        self.edit(contract.DOCKERFILE, '''RUN for name in POMODOIST_ENVIRONMENT POMODOIST_RELEASE POMODOIST_WEB_URL \\
      SUPABASE_URL SUPABASE_ANON_KEY TURNSTILE_SITE_KEY SENTRY_DSN; do \\
      value="$(printenv "$name" || true)"; \\
      if [ -n "$value" ]; then \\
        echo "build argument $name must stay a runtime environment variable" >&2; \\
        exit 1; \\
      fi; \\
    done
''', '')
        self.assert_rejected('has no guard rejecting a build argument')

    def test_guard_set_that_stops_covering_every_runtime_variable_is_rejected(
            self):
        original = contract.GUARDED_ARGS
        contract.GUARDED_ARGS = original - {'SENTRY_DSN'}
        try:
            self.assert_rejected('GUARDED_ARGS no longer covers')
        finally:
            contract.GUARDED_ARGS = original

    def test_static_build_arg_missing_from_versioned_file_is_rejected(self):
        self.edit(contract.BUILD_ARGS,
                  'POMODOIST_BILLING_CHANNEL=stripe\n', '')
        self.assert_rejected(f'{contract.BUILD_ARGS} records')

    def test_pinned_release_sha_is_rejected(self):
        self.edit(contract.BUILD_ARGS, 'POMODOIST_BILLING_CHANNEL=stripe\n',
                  'POMODOIST_BILLING_CHANNEL=stripe\n'
                  'RELEASE_SHA=0123456789abcdef0123456789abcdef01234567\n')
        self.assert_rejected(f'{contract.BUILD_ARGS} pins RELEASE_SHA')

    def test_unguarded_billing_channel_is_rejected(self):
        self.edit(contract.DOCKERFILE,
                  '[ "$POMODOIST_BILLING_CHANNEL" = stripe ]', 'true')
        self.assert_rejected('does not guard POMODOIST_BILLING_CHANNEL')

    def test_compose_without_release_sha_is_rejected(self):
        self.edit(contract.COMPOSE,
                  '        RELEASE_SHA: ${POMODOIST_RELEASE:?run make setup first}\n',
                  '')
        self.assert_rejected(f'{contract.COMPOSE} web build args are')

    def test_compose_dropping_a_runtime_variable_is_rejected(self):
        self.edit(contract.COMPOSE,
                  '      TURNSTILE_SITE_KEY: ${TURNSTILE_SITE_KEY:-}\n',
                  '')
        self.assert_rejected('does not pass the runtime environment')

    def test_build_site_without_release_sha_is_rejected(self):
        self.edit('tool/export_web_sourcemaps.sh',
                  '  --build-arg "RELEASE_SHA=$release" \\\n', '')
        self.assert_rejected('does not pass')

    def test_build_site_passing_an_extra_argument_is_rejected(self):
        self.edit('tool/export_web_sourcemaps.sh',
                  '  --build-arg "RELEASE_SHA=$release" \\\n',
                  '  --build-arg "RELEASE_SHA=$release" \\\n'
                  '  --build-arg POMODOIST_ENVIRONMENT=production \\\n')
        self.assert_rejected('which the image does not accept')

    def test_build_site_losing_the_static_channel_is_rejected(self):
        self.edit('tool/export_web_sourcemaps.sh',
                  '  --build-arg POMODOIST_BILLING_CHANNEL=stripe \\\n',
                  '  --build-arg POMODOIST_BILLING_CHANNEL=storekit \\\n')
        self.assert_rejected('does not build with POMODOIST_BILLING_CHANNEL')

    def test_build_script_dropping_the_versioned_file_is_rejected(self):
        self.edit('tool/deploy/web/build_image.sh',
                  '. "$repo_root/tool/deploy/web/build-args.env"\n', '')
        self.assert_rejected(
            f'{contract.BUILD_SITE_NAMES[0]} does not build with '
            'POMODOIST_BILLING_CHANNEL')

    def test_entrypoint_no_longer_requiring_a_variable_is_rejected(self):
        self.edit(contract.ENTRYPOINT,
                  "[ -n \"${SUPABASE_ANON_KEY:-}\" ] || fail "
                  "'SUPABASE_ANON_KEY is required'\n", '')
        self.assert_rejected('no longer requires')


if __name__ == '__main__':
    unittest.main()
