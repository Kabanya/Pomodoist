import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_architecture_types.dart';

void main() {
  final rootPath = Directory.current.absolute.path;
  final fixturesPath = '$rootPath/test/architecture/fixtures';

  Future<List<ArchitectureDiagnostic>> check(String fixture) {
    final libPath = '$fixturesPath/$fixture/lib';
    return ArchitectureTypeChecker(
      libPath: libPath,
      rootPath: rootPath,
    ).analyze(ArchitectureTypeChecker.sourceFiles(libPath));
  }

  // Resolve each fixture tree once; every case reads the same diagnostics.
  final negative = check('negative');
  final positive = check('positive');

  bool has(
    List<ArchitectureDiagnostic> diagnostics, {
    required String file,
    required ArchitectureRule rule,
    required String symbol,
  }) => diagnostics.any(
    (diagnostic) =>
        diagnostic.path.endsWith(file) &&
        diagnostic.rule == rule &&
        diagnostic.symbol == symbol,
  );

  test(
    'rejects a concrete implementation of a non-suffix repository contract',
    () async {
      expect(
        (await negative).any((d) => d.path.endsWith('decomposer_vm.dart')),
        isTrue,
      );
    },
  );
  test(
    'rejects calls to a separate repository contract in the same area',
    () async {
      expect(
        (await negative).any((d) => d.path.endsWith('calling_repository.dart')),
        isTrue,
      );
    },
  );

  test('repository contracts cannot expose Flutter state', () async {
    expect(
      has(
        await negative,
        file: 'framework_repository.dart',
        rule: ArchitectureRule.publicContract,
        symbol: 'ChangeNotifier',
      ),
      isTrue,
    );
  });

  test('positive fixtures stay within symbol boundaries', () async {
    final diagnostics = await positive;
    expect(
      diagnostics,
      isEmpty,
      reason: diagnostics.map((d) => d.format(rootPath)).join('\n'),
    );
  });

  test(
    'view model reaching a concrete repository through a provider',
    () async {
      final diagnostics = await negative;
      expect(
        has(
          diagnostics,
          file: 'ui/tasks/view_models/concrete_repository_vm.dart',
          rule: ArchitectureRule.providerInference,
          symbol: 'DriftTaskRepository',
        ),
        isTrue,
      );
    },
  );

  test('view model referencing a concrete repository directly', () async {
    final diagnostics = await negative;
    expect(
      has(
        diagnostics,
        file: 'ui/tasks/view_models/direct_import_vm.dart',
        rule: ArchitectureRule.viewModelBoundary,
        symbol: 'DriftTaskRepository',
      ),
      isTrue,
    );
  });

  test('AccountClient inferred from a provider', () async {
    final diagnostics = await negative;
    expect(
      has(
        diagnostics,
        file: 'ui/tasks/view_models/account_client_vm.dart',
        rule: ArchitectureRule.providerInference,
        symbol: 'AccountClient',
      ),
      isTrue,
    );
  });

  test('generated Drift row inferred from a provider', () async {
    final diagnostics = await negative;
    expect(
      has(
        diagnostics,
        file: 'ui/tasks/view_models/drift_row_vm.dart',
        rule: ArchitectureRule.providerInference,
        symbol: 'TaskRow',
      ),
      isTrue,
    );
  });

  test('source adapter inferred from a provider', () async {
    final diagnostics = await negative;
    expect(
      has(
        diagnostics,
        file: 'ui/tasks/view_models/source_adapter_vm.dart',
        rule: ArchitectureRule.providerInference,
        symbol: 'EmailAuthController',
      ),
      isTrue,
    );
  });

  test('another ViewModel reached through a provider', () async {
    final diagnostics = await negative;
    expect(
      has(
        diagnostics,
        file: 'ui/tasks/view_models/other_vm_vm.dart',
        rule: ArchitectureRule.providerInference,
        symbol: 'AnotherViewModel',
      ),
      isTrue,
    );
  });

  test('typedef alias cannot hide a concrete repository', () async {
    final diagnostics = await negative;
    expect(
      has(
        diagnostics,
        file: 'ui/tasks/view_models/typedef_vm.dart',
        rule: ArchitectureRule.providerInference,
        symbol: 'DriftTaskRepository',
      ),
      isTrue,
    );
  });

  test('generic wrapper cannot hide a concrete repository', () async {
    final diagnostics = await negative;
    expect(
      has(
        diagnostics,
        file: 'ui/tasks/view_models/generic_wrapper_vm.dart',
        rule: ArchitectureRule.providerInference,
        symbol: 'DriftTaskRepository',
      ),
      isTrue,
    );
  });

  test('extension member declared in a service is rejected', () async {
    final diagnostics = await negative;
    expect(
      diagnostics.any(
        (diagnostic) =>
            diagnostic.path.endsWith(
              'ui/tasks/view_models/extension_vm.dart',
            ) &&
            diagnostic.rule == ArchitectureRule.viewModelBoundary &&
            (diagnostic.symbol == 'toolLength' ||
                diagnostic.symbol == 'RepositoryTools'),
      ),
      isTrue,
    );
  });

  test('re-exported concrete repository is rejected', () async {
    final diagnostics = await negative;
    expect(
      has(
        diagnostics,
        file: 'ui/tasks/view_models/reexport_vm.dart',
        rule: ArchitectureRule.providerInference,
        symbol: 'DriftTaskRepository',
      ),
      isTrue,
    );
  });

  test('concrete class named *Repository without _impl suffix', () async {
    final diagnostics = await negative;
    expect(
      has(
        diagnostics,
        file: 'ui/tasks/view_models/legacy_named_vm.dart',
        rule: ArchitectureRule.providerInference,
        symbol: 'LegacyTasksRepository',
      ),
      isTrue,
    );
  });

  test('domain referencing UI is rejected', () async {
    final diagnostics = await negative;
    expect(
      has(
        diagnostics,
        file: 'domain/models/leaky_task.dart',
        rule: ArchitectureRule.domainBoundary,
        symbol: 'FixtureScreen',
      ),
      isTrue,
    );
  });

  test('domain referencing a generated Drift row is rejected', () async {
    final diagnostics = await negative;
    expect(
      has(
        diagnostics,
        file: 'domain/models/leaky_row.dart',
        rule: ArchitectureRule.domainBoundary,
        symbol: 'TaskRow',
      ),
      isTrue,
    );
  });

  test('repository contract referencing a generated row is rejected', () async {
    final diagnostics = await negative;
    expect(
      has(
        diagnostics,
        file: 'data/repositories/tasks/row_contract_repository.dart',
        rule: ArchitectureRule.publicContract,
        symbol: 'TaskRow',
      ),
      isTrue,
    );
  });

  test('widget referencing a source adapter is rejected', () async {
    final diagnostics = await negative;
    expect(
      has(
        diagnostics,
        file: 'ui/tasks/widgets/leaky_widget.dart',
        rule: ArchitectureRule.viewBoundary,
        symbol: 'EmailAuthController',
      ),
      isTrue,
    );
  });

  test('part files resolve to their owning library', () async {
    final diagnostics = await check('negative');
    expect(
      has(
        diagnostics,
        file: 'ui/tasks/view_models/part_vm_actions.dart',
        rule: ArchitectureRule.providerInference,
        symbol: 'DriftTaskRepository',
      ),
      isTrue,
    );
  });

  test('diagnostics contain file, line, symbol and rule', () async {
    final diagnostics = await negative;
    final diagnostic = diagnostics.firstWhere(
      (candidate) =>
          candidate.path.endsWith(
            'ui/tasks/view_models/concrete_repository_vm.dart',
          ) &&
          candidate.rule == ArchitectureRule.providerInference,
    );
    final formatted = diagnostic.format(rootPath);
    expect(formatted, contains('concrete_repository_vm.dart:'));
    expect(diagnostic.line, greaterThan(0));
    expect(diagnostic.column, greaterThan(0));
    expect(formatted, contains('provider-inference'));
    expect(formatted, contains('DriftTaskRepository'));
  });
}
