import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/files_dependencies.dart';
import 'package:pomodoist/data/repositories/files/files_repository_contract.dart';
import 'package:pomodoist/domain/models/files/file_attachment.dart';
import 'package:pomodoist/ui/files/view_models/files_view_model.dart';

class _Repository implements FilesRepositoryContract {
  int calls = 0;
  Future<String> Function(int) response = (call) async =>
      'https://files.test/$call';
  @override
  Future<String> downloadUrl(String attachmentId, {bool preview = false}) {
    expect(preview, isTrue);
    return response(++calls);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FileAttachment file() => FileAttachment(
  id: 'image',
  name: 'image.png',
  contentType: 'image/png',
  bytes: 100,
  createdAt: DateTime.utc(2026),
  authorName: '',
  createdBy: 'owner',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unchanged attachment snapshots share a preview request', () async {
    final repository = _Repository();
    final container = ProviderContainer(
      overrides: [filesRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final first = filePreviewProvider(file().previewKey);
    final second = filePreviewProvider(file().previewKey);
    container.listen(first, (_, _) {});
    container.listen(second, (_, _) {});
    await Future.wait([
      container.read(first.future),
      container.read(second.future),
    ]);
    expect(repository.calls, 1);
  });

  test('temporary URL failure recovers with one delayed retry', () {
    fakeAsync((async) {
      final repository = _Repository()
        ..response = (call) async {
          if (call == 1) throw const FileFailure('network');
          return 'https://files.test/fresh';
        };
      final container = ProviderContainer(
        overrides: [filesRepositoryProvider.overrideWithValue(repository)],
      );
      final provider = filePreviewProvider(file().previewKey);
      container.listen(provider, (_, _) {});
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(container.read(provider).value, 'https://files.test/fresh');
      container.dispose();
    });
  });
  test(
    'expired image retries once, ignores stale errors and refresh resets limit',
    () {
      fakeAsync((async) {
        final repository = _Repository();
        final container = ProviderContainer(
          overrides: [filesRepositoryProvider.overrideWithValue(repository)],
        );
        final provider = filePreviewProvider(file().previewKey);
        container.listen(provider, (_, _) {});
        async.flushMicrotasks();
        final controller = container.read(provider.notifier);
        controller.imageFailed(
          'https://files.test/1',
          StateError('expired'),
          null,
        );
        controller.imageFailed(
          'https://files.test/1',
          StateError('duplicate'),
          null,
        );
        async.elapse(const Duration(milliseconds: 999));
        expect(repository.calls, 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(container.read(provider).value, 'https://files.test/2');
        controller.imageFailed(
          'https://files.test/1',
          StateError('late'),
          null,
        );
        expect(container.read(provider).value, 'https://files.test/2');
        controller.imageFailed(
          'https://files.test/2',
          StateError('bad bytes'),
          null,
        );
        async.elapse(const Duration(seconds: 5));
        expect(repository.calls, 2);
        expect(container.read(provider).hasError, isTrue);
        container.invalidate(provider);
        async.elapse(Duration.zero);
        expect(container.read(provider).value, 'https://files.test/3');
        container
            .read(provider.notifier)
            .imageFailed('https://files.test/3', StateError('offline'), null);
        async.elapse(const Duration(seconds: 1));
        expect(container.read(provider).value, 'https://files.test/4');
        container.dispose();
        async.flushMicrotasks();
      });
    },
  );

  test(
    'permanent URL failure stops after one retry and disposal cancels retry',
    () {
      fakeAsync((async) {
        final repository = _Repository()
          ..response = (_) async => throw const FileFailure('network');
        final container = ProviderContainer(
          overrides: [filesRepositoryProvider.overrideWithValue(repository)],
        );
        final provider = filePreviewProvider(file().previewKey);
        container.listen(provider, (_, _) {});
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        expect(repository.calls, 2);
        expect(container.read(provider).hasError, isTrue);
        container.invalidate(provider);
        async.elapse(Duration.zero);
        expect(repository.calls, 3);
        container.dispose();
        async.elapse(const Duration(seconds: 5));
        expect(repository.calls, 3);
      });
    },
  );

  test(
    'session replacement ignores late responses and cancels old retries',
    () {
      fakeAsync((async) {
        final pending = Completer<String>();
        final old = _Repository()..response = (_) => pending.future;
        final next = _Repository()
          ..response = (_) async => 'https://files.test/new-account';
        final container = ProviderContainer(
          overrides: [filesRepositoryProvider.overrideWithValue(old)],
        );
        final provider = filePreviewProvider(file().previewKey);
        container.listen(provider, (_, _) {});
        async.flushMicrotasks();
        container.updateOverrides([
          filesRepositoryProvider.overrideWithValue(next),
        ]);
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        pending.complete('https://files.test/old-account');
        async.flushMicrotasks();
        expect(
          container.read(provider).value,
          'https://files.test/new-account',
        );
        container
            .read(provider.notifier)
            .imageFailed(
              'https://files.test/new-account',
              StateError('offline'),
              null,
            );
        container.updateOverrides([
          filesRepositoryProvider.overrideWithValue(null),
        ]);
        async.elapse(const Duration(seconds: 5));
        expect(container.read(provider).value, isNull);
        expect(next.calls, 1);
        container.dispose();
        async.flushMicrotasks();
      });
    },
  );
  test(
    'removing one consumer retains cache until the last consumer leaves',
    () {
      fakeAsync((async) {
        final repository = _Repository();
        final container = ProviderContainer(
          overrides: [filesRepositoryProvider.overrideWithValue(repository)],
        );
        final provider = filePreviewProvider(file().previewKey);
        final first = container.listen(provider, (_, _) {});
        final second = container.listen(provider, (_, _) {});
        async.flushMicrotasks();
        const image = NetworkImage('https://files.test/1');
        final cache = PaintingBinding.instance.imageCache;
        cache.putIfAbsent(
          image,
          () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future),
        );
        expect(cache.containsKey(image), isTrue);
        first.close();
        async.elapse(Duration.zero);
        expect(cache.containsKey(image), isTrue);
        expect(repository.calls, 1);
        second.close();
        async.elapse(Duration.zero);
        expect(cache.containsKey(image), isFalse);
        container.dispose();
      });
    },
  );

  test('Files refresh renews its previews without resetting other targets', () {
    fakeAsync((async) {
      final repository = _Repository();
      const target = FileTarget(taskId: 'task');
      final container = ProviderContainer(
        overrides: [
          filesRepositoryProvider.overrideWithValue(repository),
          filesProvider(target).overrideWith((ref) => Stream.value([file()])),
        ],
      );
      container.listen(filesProvider(target), (_, _) {});
      final provider = filePreviewProvider(file().previewKey);
      final other = filePreviewProvider((
        scopeId: 'other',
        attachmentId: 'image',
      ));
      container.listen(provider, (_, _) {});
      container.listen(other, (_, _) {});
      async.flushMicrotasks();
      final otherUrl = container.read(other).value;
      container.read(filesViewModelProvider(target).notifier).refresh();
      async.elapse(Duration.zero);
      expect(repository.calls, 3);
      expect(container.read(provider).value, 'https://files.test/3');
      expect(container.read(other).value, otherUrl);
      container.dispose();
      async.flushMicrotasks();
    });
  });
}
