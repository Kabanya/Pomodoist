"""Public Make commands select the named environment without running builds."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MakeEnvironmentsTest(unittest.TestCase):
    def dry_run(self, target):
        return subprocess.check_output(
            ['make', '--no-print-directory', '-n', target, 'DART=true',
             'POMODOIST_RELEASE=test', 'ASC_KEY_ID=test', 'ASC_ISSUER_ID=test'],
            cwd=ROOT, text=True, stderr=subprocess.STDOUT)

    def test_environment_precedes_mode(self):
        for platform in ['macos', 'linux', 'windows', 'web', 'android', 'ios', 'ipad']:
            modes = ['debug'] if platform == 'android' else ['debug', 'profile']
            if platform in ['macos', 'linux', 'windows', 'web']:
                modes.append('release')
            for environment in ['development', 'staging', 'production']:
                for mode in modes:
                    with self.subTest(platform=platform, environment=environment, mode=mode):
                        command = self.dry_run(f'{platform}-{environment}-{mode}')
                        entry = 'lib/main.dart' if environment == 'production' else f'lib/main_{environment}.dart'
                        self.assertIn(entry, command)
                        if platform != 'web':
                            self.assertRegex(command, rf'(?:--flavor |[^\w]-Flavor )"?{environment}')
                        if platform in ['ios', 'ipad']:
                            self.assertIn('--debug', command)

    def test_explicit_watch_and_testflight(self):
        for environment in ['development', 'staging', 'production']:
            for mode in ['debug', 'profile']:
                command = self.dry_run(f'watch-{environment}-{mode}')
                configuration = mode.title() + ('' if environment == 'production' else f'-{environment.title()}')
                self.assertIn(f'-configuration "{configuration}"', command)
                suffix = {'development': '.dev', 'staging': '.stg', 'production': ''}[environment]
                self.assertIn(f'com.finchforge.pomodoist{suffix}.watchkitapp', command)
        for environment in ['staging', 'production']:
            for platform in ['ios', 'macos', 'all']:
                command = self.dry_run(f'{platform}-{environment}-testflight')
                self.assertIn(f'--flavor "{environment}"', command)

    def test_help_inventory_and_removed_spellings(self):
        database = subprocess.run(['make', '-qp', 'DART=true'], cwd=ROOT, capture_output=True, text=True).stdout
        targets = set(re.findall(r'^([^\s:#=]+):', database, re.M))
        help_text = subprocess.check_output(['make', 'help', 'DART=true'], cwd=ROOT, text=True)
        for command in re.findall(r'make ([\w-]+)', help_text):
            self.assertIn(command, targets)
        self.assertFalse(any(re.match(r'(?:macos|linux|windows|android|web)-(?:debug|profile|release|appimage|install|installer|dmg|provision)-(?:development|staging|production)$', target) for target in targets))
        for target in ['chrome-staging-debug', 'chrome-staging-run', 'chrome-production-release',
                       'telegram-staging-debug', 'telegram-staging-local', 'telegram-production-release',
                       'telegram-staging-deploy', 'telegram-production-deploy']:
            self.assertIn(target, targets)


if __name__ == '__main__':
    unittest.main()
