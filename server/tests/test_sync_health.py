import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import datetime as dt

spec = importlib.util.spec_from_file_location('sync_health', Path(__file__).parents[1] / 'scripts/sync_health.py')
health = importlib.util.module_from_spec(spec)
spec.loader.exec_module(health)


class SyncHealthTest(unittest.TestCase):
    def test_fresh_database_is_allowed_only_before_migrations(self):
        with patch.object(health, 'run', side_effect=['db\n', '']):
            result = health.snapshot('db', dt.datetime.now(dt.timezone.utc), allow_new=True)
            self.assertFalse(result['existing'])
        with patch.object(health, 'run', side_effect=['db\n', '']):
            with self.assertRaises(RuntimeError):
                health.snapshot('db', dt.datetime.now(dt.timezone.utc))

    def test_aggregate_gate_retains_existing_debt_but_rejects_regressions(self):
        before = {'malformed': 3, 'errors_per_minute': 2}
        self.assertEqual(health.regressions(before, before), [])
        self.assertEqual(health.regressions(before, {'malformed': 1, 'errors_per_minute': 0}), [])
        self.assertEqual(health.regressions(before, {'malformed': 4, 'errors_per_minute': 3}),
                         ['malformed', 'errors_per_minute'])
        self.assertTrue(health.VALIDATION_ERROR.search('2026 ERROR:  Invalid habit field'))
        self.assertFalse(health.VALIDATION_ERROR.search('STATEMENT: Invalid habit field'))
