// Resolved-Dart architecture checker.
//
// Complements root `tool/check_architecture.py`: that checker reads import
// directives, this one resolves the element model. It therefore sees re-exports,
// typedefs, generic wrappers, extension members and inferred provider result
// types, and classifies a class by its declaration instead of its file name.
//
// Run from `apps/flutter` after dependency resolution:
//   ../../.fvm/flutter_sdk/bin/dart run tool/check_architecture_types.dart
//
// Exit code is non-zero when a violation is found. Diagnostics are stable and
// contain `path:line:column: rule: symbol (detail)`.
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Package names that may not be referenced by domain code, UI or repository
/// contracts. Flutter framework packages are intentionally absent: widgets use
/// keyboard, focus and rendering services directly.
const sdkPackages = {
  'app_account',
  'app_links',
  'app_voice',
  'audioplayers',
  'dbus',
  'dio',
  'drift',
  'drift_flutter',
  'flutter_local_notifications',
  'http',
  'in_app_purchase',
  'in_app_purchase_storekit',
  'path_provider',
  'record',
  'sentry_flutter',
  'shared_preferences',
  'sqlite3',
  'supabase_flutter',
};

/// Framework and SDK packages domain code must not depend on at all.
const domainBannedPackages = {
  'app_account',
  'drift',
  'flutter',
  'flutter_riverpod',
};

enum ArchitectureRule {
  domainBoundary('domain-boundary'),
  viewBoundary('view-boundary'),
  viewModelBoundary('view-model-boundary'),
  providerInference('provider-inference'),
  publicContract('public-contract'),
  repositoryBoundary('repository-boundary');

  const ArchitectureRule(this.id);

  final String id;
}

enum DeclaredKind {
  sdkPackage('SDK package'),
  generatedRow('generated Drift row'),
  sourceAdapter('source adapter'),
  concreteRepository('concrete repository'),
  abstractRepository('repository contract'),
  viewModel('ViewModel'),
  other('declaration');

  const DeclaredKind(this.label);

  final String label;
}

class ArchitectureDiagnostic implements Comparable<ArchitectureDiagnostic> {
  ArchitectureDiagnostic({
    required this.path,
    required this.line,
    required this.column,
    required this.rule,
    required this.symbol,
    required this.detail,
  });

  final String path;
  final int line;
  final int column;
  final ArchitectureRule rule;
  final String symbol;
  final String detail;

  String format(String rootPath) {
    final relative = path.startsWith('$rootPath/')
        ? path.substring(rootPath.length + 1)
        : path;
    return '$relative:$line:$column: ${rule.id}: $symbol ($detail)';
  }

  @override
  int compareTo(ArchitectureDiagnostic other) {
    final byPath = path.compareTo(other.path);
    if (byPath != 0) return byPath;
    final byLine = line.compareTo(other.line);
    if (byLine != 0) return byLine;
    final byColumn = column.compareTo(other.column);
    if (byColumn != 0) return byColumn;
    final byRule = rule.id.compareTo(other.rule.id);
    if (byRule != 0) return byRule;
    return symbol.compareTo(other.symbol);
  }
}

/// Resolves a Dart library file to its path relative to the analyzed package
/// `lib/` directory, regardless of whether the element was reached through a
/// relative import, a `package:pomodoist/` import or a re-export.
class _DeclaredLocation {
  const _DeclaredLocation({
    required this.relative,
    required this.packageName,
    required this.kind,
    required this.sameLibrary,
  });

  final String relative;
  final String? packageName;
  final DeclaredKind kind;
  final bool sameLibrary;
}

class ArchitectureTypeChecker {
  ArchitectureTypeChecker({required this.libPath, String? rootPath})
    : rootPath = rootPath ?? Directory.current.absolute.path;

  final String libPath;
  final String rootPath;

  late final String _libAbsolute = Directory(libPath).absolute.path;
  late final String _packageLibAbsolute = Directory(
    '$rootPath/lib',
  ).absolute.path;

  static bool isHandwrittenSource(String path) {
    if (!path.endsWith('.dart')) return false;
    if (path.endsWith('.g.dart') || path.endsWith('.freezed.dart')) {
      return false;
    }
    if (path.contains('/generated/')) return false;
    if (path.contains('/.dart_tool/') || path.contains('/build/')) return false;
    if (path.contains('/localization/app_localizations')) return false;
    return true;
  }

  /// Every handwritten `.dart` library under [libPath], sorted for determinism.
  static List<String> sourceFiles(String libPath) {
    final directory = Directory(libPath);
    if (!directory.existsSync()) return const [];
    final files =
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => file.absolute.path)
            .where(isHandwrittenSource)
            .toList()
          ..sort();
    return files;
  }

  Future<List<ArchitectureDiagnostic>> analyze(List<String> paths) async {
    final sorted = paths.toList()..sort();
    if (sorted.isEmpty) return const [];
    final collection = AnalysisContextCollection(
      includedPaths: [_libAbsolute],
      sdkPath: _dartSdkPath(),
    );
    final diagnostics = <ArchitectureDiagnostic>[];
    try {
      for (final path in sorted) {
        final result = await collection
            .contextFor(path)
            .currentSession
            .getResolvedUnit(path);
        if (result is! ResolvedUnitResult) continue;
        result.unit.accept(_UnitVisitor(this, result, diagnostics));
      }
    } finally {
      await collection.dispose();
    }
    diagnostics.sort();
    return diagnostics;
  }

  _DeclaredLocation? _declaredLocation(
    Element element,
    LibraryElement? currentLibrary,
  ) {
    var base = element.baseElement;
    if (base is PrefixElement || base is LibraryElement) return null;
    final library = base.library;
    if (library == null) return null;
    final uri = library.uri;
    final sameLibrary = currentLibrary != null && library == currentLibrary;
    String? relative;
    String? packageName;
    if (uri.scheme == 'package') {
      packageName = uri.pathSegments.first;
      if (packageName == 'pomodoist') {
        relative = uri.pathSegments.skip(1).join('/');
      }
    }
    if (relative == null) {
      final fullName = library.firstFragment.source.fullName;
      if (fullName.startsWith('$_libAbsolute/')) {
        relative = fullName.substring(_libAbsolute.length + 1);
      } else if (fullName.startsWith('$_packageLibAbsolute/')) {
        relative = fullName.substring(_packageLibAbsolute.length + 1);
      }
    }
    if (relative == null) {
      return packageName == null
          ? null
          : _DeclaredLocation(
              relative: '',
              packageName: packageName,
              kind: sdkPackages.contains(packageName)
                  ? DeclaredKind.sdkPackage
                  : DeclaredKind.other,
              sameLibrary: sameLibrary,
            );
    }
    final kind = _kindOf(relative, packageName, base);
    return _DeclaredLocation(
      relative: relative,
      packageName: packageName,
      kind: kind,
      sameLibrary: sameLibrary,
    );
  }

  DeclaredKind _kindOf(String relative, String? packageName, Element element) {
    if (packageName != null &&
        packageName != 'pomodoist' &&
        sdkPackages.contains(packageName)) {
      return DeclaredKind.sdkPackage;
    }
    final parts = relative.split('/');
    if (parts.length >= 4 &&
        parts[0] == 'data' &&
        parts[1] == 'services' &&
        parts[2] == 'local' &&
        parts[3] == 'database') {
      return DeclaredKind.generatedRow;
    }
    if (parts.length >= 2 && parts[0] == 'data' && parts[1] == 'services') {
      return DeclaredKind.sourceAdapter;
    }
    if (parts.length >= 2 && parts[0] == 'data' && parts[1] == 'repositories') {
      if (element is ClassElement) {
        // Any abstract class in the repository area is a contract, even when
        // its name does not end in `Repository` (for example `TaskDecomposer`).
        if (element.isAbstract) return DeclaredKind.abstractRepository;
        if (isRepositoryShape(element)) {
          return DeclaredKind.concreteRepository;
        }
      }
      return DeclaredKind.other;
    }
    if (parts.isNotEmpty &&
        parts[0] == 'ui' &&
        element is InterfaceElement &&
        isViewModelClass(element)) {
      return DeclaredKind.viewModel;
    }
    return DeclaredKind.other;
  }

  /// A class is repository-shaped when its name ends in `Repository` or it
  /// implements a repository contract. The check uses declarations, so
  /// `TaskDecomposer` (an abstract contract) and a concrete class named
  /// `*Repository` are classified by what they are, not by their file name.
  static bool isRepositoryShape(InterfaceElement element) {
    if (element.name?.endsWith('Repository') ?? false) return true;
    if (element is ClassElement &&
        element.isAbstract &&
        element.library.firstFragment.source.fullName.contains(
          '/data/repositories/',
        )) {
      return true;
    }
    for (final supertype in element.allSupertypes) {
      if (supertype.element.name?.endsWith('Repository') ?? false) return true;
      final contract = supertype.element;
      if (contract is ClassElement &&
          contract.isAbstract &&
          contract.library.firstFragment.source.fullName.contains(
            '/data/repositories/',
          )) {
        return true;
      }
    }
    return false;
  }

  static bool isViewModelClass(InterfaceElement element) {
    for (final supertype in element.allSupertypes) {
      final name = supertype.element.name;
      final library = supertype.element.library.uri;
      final package = library.scheme == 'package'
          ? library.pathSegments.first
          : null;
      if (package == 'flutter_riverpod' || package == 'riverpod') {
        if (name == 'Notifier' ||
            name == 'AsyncNotifier' ||
            name == 'StreamNotifier') {
          return true;
        }
      }
      if (package == 'flutter' && name == 'ChangeNotifier') return true;
      if (package == 'state_notifier' && name == 'StateNotifier') return true;
    }
    return false;
  }

  static bool isConcreteRepositoryElement(Element element) =>
      element is ClassElement &&
      !element.isAbstract &&
      isRepositoryShape(element);
}

class _UnitVisitor extends RecursiveAstVisitor<void> {
  _UnitVisitor(this.checker, this.resolved, this.diagnostics);

  final ArchitectureTypeChecker checker;
  final ResolvedUnitResult resolved;
  final List<ArchitectureDiagnostic> diagnostics;

  LibraryElement get _library => resolved.libraryElement;

  String get _relative => _currentRelative ??= _relativeFor(resolved.path);

  String? _currentRelative;

  String _relativeFor(String path) {
    final lib = checker._libAbsolute;
    final packageLib = checker._packageLibAbsolute;
    if (path.startsWith('$lib/')) return path.substring(lib.length + 1);
    if (path.startsWith('$packageLib/')) {
      return path.substring(packageLib.length + 1);
    }
    return path;
  }

  bool _insideAbstractRepository = false;
  ClassElement? _repositoryOwner;

  bool get _isDomain => _relative.startsWith('domain/');

  bool get _isUi => _relative.startsWith('ui/');

  bool get _isViewModelFile => _relative.contains('/view_models/');

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    final wasInsideAbstractRepository = _insideAbstractRepository;
    final previousOwner = _repositoryOwner;
    if (element != null &&
        !element.isAbstract &&
        _relative.startsWith('data/repositories/') &&
        ArchitectureTypeChecker.isRepositoryShape(element)) {
      _repositoryOwner = element;
    }
    if (element != null &&
        element.isAbstract &&
        _relative.startsWith('data/repositories/')) {
      _insideAbstractRepository = true;
    }
    super.visitClassDeclaration(node);
    _insideAbstractRepository = wasInsideAbstractRepository;
    _repositoryOwner = previousOwner;
  }

  @override
  void visitCommentReference(CommentReference node) {
    // Documentation references are not dependencies.
  }

  @override
  void visitNamedType(NamedType node) {
    final element = node.element;
    if (element != null) {
      _classifyReference(element, node.offset);
    }
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element != null) {
      _classifyReference(element, node.offset);
    }
    super.visitSimpleIdentifier(node);
  }

  void _classifyReference(Element element, int offset) {
    final declared = checker._declaredLocation(element, _library);
    if (declared == null || declared.sameLibrary) return;
    if (_isDomain &&
        _relative.startsWith('domain/use_cases/') &&
        _enclosesAbstractRepository(element)) {
      return;
    }
    final owner = _repositoryOwner;
    if (owner != null && declared.relative.startsWith('data/repositories/')) {
      Element? target = element;
      while (target != null && target is! ClassElement) {
        target = target.enclosingElement;
      }
      if (target is ClassElement &&
          (target.isAbstract ||
              ArchitectureTypeChecker.isRepositoryShape(target)) &&
          !owner.allSupertypes.any((type) => type.element == target)) {
        _reportOffset(
          offset,
          ArchitectureRule.repositoryBoundary,
          element.name ?? element.displayName,
          'separate repository ${target.name}',
        );
      }
    }
    final rule = _ruleFor(declared);
    if (rule == null) return;
    final symbol = element.name ?? element.displayName;
    _reportOffset(offset, rule, symbol, _detail(declared, declared.kind));
  }

  /// `true` when the referenced member belongs to an abstract repository
  /// contract, so a use case calling `TaskRepository.createTask` stays legal.
  bool _enclosesAbstractRepository(Element element) {
    Element? current = element;
    while (current != null) {
      if (current is ClassElement &&
          current.isAbstract &&
          ArchitectureTypeChecker.isRepositoryShape(current)) {
        return true;
      }
      current = current.enclosingElement;
    }
    return false;
  }

  ArchitectureRule? _ruleFor(_DeclaredLocation declared) {
    final kind = declared.kind;
    if (_isDomain) {
      final targetParts = declared.relative.split('/');
      final external =
          kind != DeclaredKind.other ||
          (targetParts.isNotEmpty &&
              const {
                'data',
                'ui',
                'config',
                'routing',
              }.contains(targetParts.first)) ||
          domainBannedPackages.contains(declared.packageName);
      if (!external) return null;
      final allowed =
          _relative.startsWith('domain/use_cases/') &&
          (kind == DeclaredKind.abstractRepository ||
              declared.relative ==
                  'data/repositories/local/local_transaction.dart');
      return allowed ? null : ArchitectureRule.domainBoundary;
    }
    if (_insideAbstractRepository) {
      if (domainBannedPackages.contains(declared.packageName) ||
          kind == DeclaredKind.sdkPackage ||
          kind == DeclaredKind.generatedRow ||
          kind == DeclaredKind.sourceAdapter) {
        return ArchitectureRule.publicContract;
      }
    }
    if (_isUi) {
      if (kind == DeclaredKind.sdkPackage ||
          kind == DeclaredKind.generatedRow ||
          kind == DeclaredKind.sourceAdapter) {
        return _isViewModelFile
            ? ArchitectureRule.viewModelBoundary
            : ArchitectureRule.viewBoundary;
      }
      if (declared.relative.startsWith('data/repositories/')) {
        if (kind == DeclaredKind.concreteRepository) {
          return _isViewModelFile
              ? ArchitectureRule.viewModelBoundary
              : ArchitectureRule.viewBoundary;
        }
        return null;
      }
      if (_isViewModelFile && kind == DeclaredKind.viewModel) {
        return ArchitectureRule.viewModelBoundary;
      }
    }
    return null;
  }

  String _detail(_DeclaredLocation declared, DeclaredKind kind) {
    if (kind == DeclaredKind.viewModel) {
      return 'another ViewModel reached from $_relative';
    }
    return '${kind.label} declared in ${declared.relative}';
  }

  void _reportOffset(
    int offset,
    ArchitectureRule rule,
    String symbol,
    String detail,
  ) {
    final location = resolved.lineInfo.getLocation(offset);
    diagnostics.add(
      ArchitectureDiagnostic(
        path: resolved.path,
        line: location.lineNumber,
        column: location.columnNumber,
        rule: rule,
        symbol: symbol,
        detail: detail,
      ),
    );
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!_isUi) {
      super.visitMethodInvocation(node);
      return;
    }
    final name = node.methodName.name;
    if (name == 'read' || name == 'watch' || name == 'select') {
      final target = node.target;
      if (target != null && _isRefExpression(target)) {
        final type = node.staticType;
        if (type != null) {
          _walkProviderResult(type, node, 'ref.$name');
        }
      }
    }
    super.visitMethodInvocation(node);
  }

  bool _isRefExpression(Expression expression) {
    if (expression is SimpleIdentifier && expression.name == 'ref') {
      return true;
    }
    final element = expression.staticType?.element;
    if (element == null) return false;
    final name = element.name;
    final library = element.library?.uri;
    if (library?.scheme != 'package') return false;
    final package = library!.pathSegments.first;
    return (package == 'flutter_riverpod' || package == 'riverpod') &&
        (name == 'Ref' || name == 'WidgetRef');
  }

  void _walkProviderResult(DartType type, AstNode anchor, String source) {
    final seen = <DartType>{};
    void visit(DartType? value) {
      if (value == null || !seen.add(value)) return;
      if (value is InvalidType || value is DynamicType) return;
      if (value is InterfaceType) {
        final element = value.element;
        final declared = checker._declaredLocation(element, _library);
        final kind = declared?.kind;
        if (declared != null &&
            !declared.sameLibrary &&
            kind != null &&
            kind != DeclaredKind.other &&
            kind != DeclaredKind.abstractRepository &&
            // Widgets dispatch typed actions on their own ViewModel; only
            // ViewModels reaching another ViewModel are a boundary violation.
            (kind != DeclaredKind.viewModel || _isViewModelFile)) {
          _reportOffset(
            anchor.offset,
            ArchitectureRule.providerInference,
            element.name ?? element.displayName,
            '${kind.label} inferred from $source in $_relative',
          );
        }
        for (final argument in value.typeArguments) {
          visit(argument);
        }
        return;
      }
      if (value is RecordType) {
        for (final field in value.positionalFields) {
          visit(field.type);
        }
        for (final field in value.namedFields) {
          visit(field.type);
        }
        return;
      }
      if (value is FunctionType) {
        visit(value.returnType);
        for (final parameter in value.formalParameters) {
          visit(parameter.type);
        }
      }
    }

    visit(type);
  }
}

/// Locates the Dart SDK for analyzer contexts.
///
/// `dart run` resolves it next to the running executable, but `flutter test`
/// runs under `flutter_tester`, whose analyzer default points at the engine
/// cache instead of `bin/cache/dart-sdk`.
String? _dartSdkPath() {
  bool isSdk(String path) =>
      File('$path/version').existsSync() &&
      (File('$path/lib/libraries.json').existsSync() ||
          File('$path/lib/_internal/libraries.dart').existsSync());
  final fromEnvironment = Platform.environment['DART_SDK'];
  if (fromEnvironment != null && isSdk(fromEnvironment)) {
    return fromEnvironment;
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final candidate = '$flutterRoot/bin/cache/dart-sdk';
    if (isSdk(candidate)) return candidate;
  }
  var directory = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 6; depth++) {
    if (isSdk(directory.path)) return directory.path;
    final flutterCandidate = '${directory.path}/bin/cache/dart-sdk';
    if (isSdk(flutterCandidate)) return flutterCandidate;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return null;
}

String _usage() =>
    'usage: dart run tool/check_architecture_types.dart [--root <package dir>]';

Future<void> main(List<String> arguments) async {
  var root = Directory.current.absolute.path;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--root') {
      if (index + 1 >= arguments.length) {
        stderr.writeln(_usage());
        exitCode = 64;
        return;
      }
      root = File(arguments[++index]).absolute.path;
    } else if (argument == '--help' || argument == '-h') {
      stdout.writeln(_usage());
      return;
    } else {
      stderr.writeln('Unknown argument: $argument');
      stderr.writeln(_usage());
      exitCode = 64;
      return;
    }
  }
  final libPath = '$root/lib';
  final files = ArchitectureTypeChecker.sourceFiles(libPath);
  if (files.isEmpty) {
    stderr.writeln('No handwritten Dart source found under $libPath');
    exitCode = 66;
    return;
  }
  final checker = ArchitectureTypeChecker(libPath: libPath, rootPath: root);
  final diagnostics = await checker.analyze(files);
  for (final diagnostic in diagnostics) {
    stdout.writeln(diagnostic.format(root));
  }
  if (diagnostics.isEmpty) {
    stdout.writeln(
      'Resolved Dart symbol boundaries passed for ${files.length} libraries.',
    );
    return;
  }
  stderr.writeln(
    '${diagnostics.length} violation(s) in '
    '${diagnostics.map((diagnostic) => diagnostic.path).toSet().length} file(s).',
  );
  exitCode = 1;
}
