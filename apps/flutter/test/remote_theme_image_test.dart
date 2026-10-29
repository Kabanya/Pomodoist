import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/agent_settings/remote_theme_image.dart';
import 'package:pomodoist/domain/models/settings/theme_image.dart';

void main() {
  test('accepts public HTTPS URLs without credentials', () {
    expect(
      () => validateRemoteThemeImageUrl(
        Uri.parse('https://images.unsplash.com/photo?q=1'),
      ),
      returnsNormally,
    );
    for (final url in [
      'http://images.unsplash.com/photo',
      'https://u:p@images.unsplash.com/a',
      'https://localhost/a',
      'https://127.0.0.1/a',
      'https://10.0.0.1/a',
      'https://192.168.1.1/a',
      'https://[::1]/a',
      'https://router.local/a',
      'https://2130706433/a',
      'https://host.invalid/a',
      'https://example.com:444/a',
    ]) {
      expect(
        () => validateRemoteThemeImageUrl(Uri.parse(url)),
        throwsFormatException,
        reason: url,
      );
    }
  });
  test(
    'rejects streaming responses beyond limit before adding the chunk',
    () async {
      await expectLater(
        readRemoteThemeImage(
          Stream.fromIterable([Uint8List(4), Uint8List(5)]),
          maxBytes: 8,
        ),
        throwsA(isA<ThemeImageTooLargeException>()),
      );
      expect(
        await readRemoteThemeImage(
          Stream.value(Uint8List.fromList([1, 2, 3])),
          maxBytes: 3,
        ),
        [1, 2, 3],
      );
    },
  );
  test('rejects empty downloads and stops failed streams', () async {
    await expectLater(
      readRemoteThemeImage(const Stream.empty()),
      throwsFormatException,
    );
    await expectLater(
      readRemoteThemeImage(Stream.error(StateError('network'))),
      throwsStateError,
    );
  });
}
