import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from check_architecture import check, cycles, dependencies


class ArchitectureTests(unittest.TestCase):
    def test_cycles_include_exports_and_self_imports(self):
        self.assertEqual(cycles({'a': {'b'}, 'b': {'a'}, 'c': {'c'}, 'd': set()}), [['a', 'b'], ['c']])

    def test_conditional_imports_are_all_checked(self):
        with TemporaryDirectory() as directory:
            file = Path(directory) / 'a.dart'
            file.write_text("import 'stub.dart' if (dart.library.io) 'native.dart';\nexport 'model.dart';")
            self.assertEqual(dependencies(file), ['stub.dart', 'native.dart', 'model.dart'])

    def test_forbidden_dependencies_and_manifest_gaps_fail(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            files = {
                'apps/flutter/lib/features/tasks/domain/model.dart': "import 'package:flutter/widgets.dart';",
                'server/supabase/functions/_shared/shared.ts': 'export { run } from "../endpoint/index.ts";',
                'server/supabase/functions/endpoint/index.ts': 'import "../_shared/omitted.ts"; export const run = 1;',
                'server/supabase/functions/_shared/omitted.ts': 'export const omitted = true;',
                'server/core-manifest.json': '{"helpers":["missing.ts","shared.ts"],"functions":["endpoint"],"baselineMigrations":[]}',
            }
            for name, source in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
            failures = '\n'.join(check(root))
            self.assertIn('domain depends on infrastructure/UI', failures)
            self.assertIn('shared code imports adapter', failures)
            self.assertIn('missing manifest helper', failures)
            self.assertIn('Manifest omits omitted.ts required by endpoint/index.ts', failures)
            (root / 'apps/flutter/lib/features/tasks/domain/model.dart').unlink()
            (root / 'apps/flutter/lib').rename(root / 'moved-lib')
            self.assertIn('Missing source directory: apps/flutter/lib', check(root))


if __name__ == '__main__':
    unittest.main()
