import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/updates/update_installer_io.dart';
import 'package:pomodoist/domain/models/updates/update_release.dart';

class _HelperProcess implements Process {
  final input = StreamController<List<int>>();
  final inputClosed = Completer<void>();
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();

  _HelperProcess() {
    input.stream.listen((_) {}, onDone: inputClosed.complete);
  }

  @override
  late final IOSink stdin = IOSink(input.sink);
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  Future<int> get exitCode => throw StateError('Must not await helper exit');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LogFile implements File {
  final _bytes = StreamController<List<int>>();
  late final Future<String> text;

  _LogFile() {
    text = _bytes.stream.transform(utf8.decoder).join();
  }

  @override
  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) {
    return IOSink(_bytes.sink, encoding: encoding);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final os in UpdateOS.values) {
    test(
      '${os.name} helper uses compatible launch and preserves diagnostics',
      () async {
        final stage = Directory('updater-unit');
        final logs = <String, _LogFile>{};
        final process = _HelperProcess();
        addTearDown(() async {
          await process.stdin.close();
        });
        ProcessStartMode? actualMode;
        await IOOverrides.runZoned(
          () => startUpdateHelper(
            os == UpdateOS.windows ? 'powershell.exe' : '/bin/sh',
            const ['a path with spaces', "a'quoted-path"],
            os: os,
            stage: stage,
            environment: const {'UPDATE_TEST': 'value'},
            startProcess:
                (
                  command,
                  arguments, {
                  workingDirectory,
                  environment,
                  includeParentEnvironment = true,
                  runInShell = false,
                  mode = ProcessStartMode.normal,
                }) async {
                  actualMode = mode;
                  expect(arguments, ['a path with spaces', "a'quoted-path"]);
                  expect(workingDirectory, stage.path);
                  expect(environment, {'UPDATE_TEST': 'value'});
                  expect(includeParentEnvironment, isFalse);
                  expect(runInShell, isFalse);
                  return process;
                },
          ),
          createFile: (path) => logs.putIfAbsent(path, _LogFile.new),
        );
        expect(
          actualMode,
          os == UpdateOS.windows
              ? ProcessStartMode.normal
              : ProcessStartMode.detached,
        );
        if (os == UpdateOS.windows) {
          await process.inputClosed.future;
          // A failure before the PowerShell script starts must still be recorded.
          process.output.add(utf8.encode('startup output\n'));
          process.errors.add(utf8.encode('PowerShell startup failed\n'));
          await Future.wait([process.output.close(), process.errors.close()]);
          expect(logs, hasLength(2));
          final stdoutLog = logs.entries
              .singleWhere((entry) => entry.key.endsWith('helper-stdout.log'))
              .value;
          final stderrLog = logs.entries
              .singleWhere((entry) => entry.key.endsWith('helper-stderr.log'))
              .value;
          expect(await stdoutLog.text, 'startup output\n');
          expect(await stderrLog.text, 'PowerShell startup failed\n');
        } else {
          expect(process.output.hasListener, isFalse);
          expect(process.errors.hasListener, isFalse);
          expect(logs, isEmpty);
        }
      },
    );
  }
}
