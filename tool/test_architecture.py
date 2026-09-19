import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from check_architecture import check, cycles, dart_target, dependencies


class ArchitectureTests(unittest.TestCase):
    def test_mvvm_boundaries_reject_data_access_from_views(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            files = {
                'server/core-manifest.json': '{"helpers":[],"functions":[]}',
                'apps/flutter/lib/data/repositories/tasks/task_repository.dart': '',
                'apps/flutter/lib/data/repositories/focus/focus_repository.dart':
                    "import '../tasks/task_repository.dart';",
                'apps/flutter/lib/config/dependencies.dart': '',
                'apps/flutter/lib/ui/tasks/widgets/task_screen.dart':
                    "import 'package:pomodoist/data/repositories/tasks/task_repository.dart';\n"
                    "import 'package:pomodoist/config/dependencies.dart';",
                'apps/flutter/lib/data/services/api.dart':
                    "import 'package:pomodoist/ui/tasks/widgets/task_screen.dart';",
            }
            for name, source in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
            (root / 'server/supabase/functions').mkdir(parents=True)
            failures = '\n'.join(check(root))
            self.assertIn('view depends on data/composition', failures)
            self.assertIn('repository depends on another repository', failures)
            self.assertIn('data depends on UI/composition', failures)

    def test_mvvm_boundaries_reject_hidden_and_reverse_dependencies(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            files = {
                'server/core-manifest.json': '{"helpers":[],"functions":[]}',
                'apps/flutter/lib/data/repositories/tasks/task_repository.dart': '',
                'apps/flutter/lib/data/services/local/database.dart':
                    "import '../../repositories/tasks/task_repository.dart';",
                'apps/flutter/lib/data/repositories/tasks/drift_tasks.dart':
                    "import 'package:flutter_riverpod/flutter_riverpod.dart';",
                'apps/flutter/lib/ui/tasks/view_models/task_vm.dart': '',
                'apps/flutter/lib/ui/search/view_models/search_vm.dart':
                    "export '../../tasks/view_models/task_vm.dart';\n"
                    "import 'package:shared_preferences/shared_preferences.dart';\n"
                    "import '../../../data/services/local/database.dart';",
                'apps/flutter/lib/ui/tasks/widgets/task_screen.dart':
                    "part 'task_screen_actions.dart';",
                'apps/flutter/lib/ui/tasks/widgets/task_screen_actions.dart':
                    "part of 'task_screen.dart';",
                'apps/flutter/lib/utils/hidden_ui.dart':
                    "export '../ui/tasks/widgets/task_screen.dart';",
            }
            for name, source in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
            (root / 'server/supabase/functions').mkdir(parents=True)
            failures = '\n'.join(check(root))
            self.assertIn('service depends on repository', failures)
            self.assertIn('lower layer depends on Riverpod', failures)
            self.assertIn('view model depends on another view model', failures)
            self.assertIn('view model depends on infrastructure', failures)
            self.assertIn('utility depends on application/framework', failures)
            self.assertNotIn('missing import task_screen.dart', failures)
            graph_dependencies = dependencies(
                root / 'apps/flutter/lib/ui/tasks/widgets/task_screen.dart',
            )
            self.assertEqual(graph_dependencies, ['task_screen_actions.dart'])

    def test_repository_contracts_do_not_expose_infrastructure(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            files = {
                'server/core-manifest.json': '{"helpers":[],"functions":[]}',
                'apps/flutter/lib/data/services/local/database.dart': '',
                'apps/flutter/lib/data/repositories/tasks/task_repository.dart':
                    "import 'package:drift/drift.dart';\n"
                    "import '../../services/local/database.dart';\n"
                    'abstract interface class TaskRepository {}',
            }
            for name, source in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
            (root / 'server/supabase/functions').mkdir(parents=True)
            failures = '\n'.join(check(root))
            self.assertIn('repository contract depends on infrastructure', failures)

    def test_use_cases_may_depend_on_repository_contracts(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            files = {
                'server/core-manifest.json': '{"helpers":[],"functions":[]}',
                'apps/flutter/lib/data/repositories/tasks/task_repository.dart': '',
                'apps/flutter/lib/domain/use_cases/complete_task.dart':
                    "import '../../data/repositories/tasks/task_repository.dart';",
                'apps/flutter/lib/domain/models/task.dart': '',
            }
            for name, source in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
            (root / 'server/supabase/functions').mkdir(parents=True)
            self.assertEqual(check(root), [])

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
                'apps/flutter/lib/domain/models/tasks/model.dart': "import 'package:flutter/widgets.dart';",
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
            (root / 'apps/flutter/lib/domain/models/tasks/model.dart').unlink()
            (root / 'apps/flutter/lib').rename(root / 'moved-lib')
            self.assertIn('Missing source directory: apps/flutter/lib', check(root))


if __name__ == '__main__':
    unittest.main()
