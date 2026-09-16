import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from check_architecture import check, cycles, dart_target, dependencies


class ArchitectureTests(unittest.TestCase):
    def test_cycles_include_exports_and_self_imports(self):
        self.assertEqual(cycles({'a': {'b'}, 'b': {'a'}, 'c': {'c'}, 'd': set()}), [['a', 'b'], ['c']])

    def test_conditional_imports_are_all_checked(self):
        with TemporaryDirectory() as directory:
            file = Path(directory) / 'a.dart'
            file.write_text("import 'stub.dart' if (dart.library.io) 'native.dart';\nexport 'model.dart';")
            self.assertEqual(dependencies(file), ['stub.dart', 'native.dart', 'model.dart'])

    def test_relative_imports_above_lib_are_clamped(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            files = {
                'apps/flutter/lib/app/app_l10n.dart': '',
                'apps/flutter/lib/features/collaboration/presentation/over_deep.dart':
                    "import '../../../../../../app/app_l10n.dart';",
                'server/core-manifest.json': '{"helpers":[],"functions":[],"baselineMigrations":[]}',
            }
            for name, source in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
            (root / 'server/supabase/functions').mkdir(parents=True)
            self.assertEqual(check(root), [])
            lib = root / 'apps/flutter/lib'
            source = lib / 'features/collaboration/presentation/over_deep.dart'
            for depth in range(3, 7):
                self.assertEqual(dart_target(lib, source, '../' * depth + 'app/app_l10n.dart').resolve(),
                                 (lib / 'app/app_l10n.dart').resolve())
            self.assertEqual(dart_target(lib, lib / 'main.dart', '../../app/app_l10n.dart').resolve(),
                             (lib / 'app/app_l10n.dart').resolve())

    def test_missing_imports_are_reported_after_clamping(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            files = {
                'apps/flutter/lib/app/app_l10n.dart': '',
                'apps/flutter/lib/features/presentation/exact.dart': "import '../../../app/app_l10n.dart';",
                'apps/flutter/lib/features/presentation/deep.dart': "import '../../../../app/app_l10n.dart';",
                'apps/flutter/lib/features/presentation/clamped_missing.dart':
                    "import '../../../../missing/nothing.dart';",
                'apps/flutter/lib/features/presentation/broken.dart': "import '../../../missing/nothing.dart';",
                'apps/flutter/lib/features/presentation/package_missing.dart':
                    "import 'package:pomodoist/missing/nothing.dart';",
                'server/supabase/functions/_shared/shared.ts': 'export const shared = true;',
                'server/supabase/functions/strict.ts': 'export { shared } from "../../../missing/shared.ts";',
                'server/core-manifest.json': '{"helpers":["shared.ts"],"functions":[],"baselineMigrations":[]}',
            }
            for name, content in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            failures = check(root)
            self.assertEqual([failure for failure in failures if 'missing import' not in failure], [])
            self.assertEqual(sorted(failure.split(': missing import ')[1] for failure in failures),
                             sorted(['../../../missing/nothing.dart',
                                     '../../../../missing/nothing.dart',
                                     'package:pomodoist/missing/nothing.dart',
                                     '../../../missing/shared.ts']))

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
