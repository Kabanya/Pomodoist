import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/audio/focus_sound_player.dart';
import 'package:pomodoist/data/services/audio/focus_sound_preview_player.dart';
import 'package:pomodoist/domain/models/focus/focus_sound_set.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh timer plays the Soft kalimba start cue', () async {
    final audio = RecordingAudioPlayer();
    final player = AssetFocusSoundPlayer(player: audio);
    await player.play(FocusSoundCue.start);
    expect(audio.paths, ['sounds/soft_kalimba/focus_start.wav']);
    expect(audio.volumes, [0.55]);
    await player.dispose();
  });

  test('each family routes all timer events to its own four assets', () async {
    final audio = RecordingAudioPlayer();
    var family = FocusSoundSet.softKalimba;
    final player = AssetFocusSoundPlayer(
      player: audio,
      readSoundSet: () async => family,
    );
    for (final entry in {
      FocusSoundSet.softKalimba: 'soft_kalimba',
      FocusSoundSet.neonPulse: 'neon_pulse',
      FocusSoundSet.orbitBloom: 'orbit_bloom',
    }.entries) {
      family = entry.key;
      for (final cue in [
        FocusSoundCue.start,
        FocusSoundCue.pause,
        FocusSoundCue.resume,
        FocusSoundCue.complete,
      ]) {
        await player.play(cue);
      }
      expect(audio.paths.sublist(audio.paths.length - 4), [
        'sounds/${entry.value}/focus_start.wav',
        'sounds/${entry.value}/focus_pause.wav',
        'sounds/${entry.value}/focus_resume.wav',
        'sounds/${entry.value}/focus_complete.wav',
      ]);
    }
    expect(audio.volumes, everyElement(0.55));
    await player.dispose();
  });

  test(
    'first playback waits for hydration and disposal cancels pending audio',
    () async {
      final audio = RecordingAudioPlayer();
      final restored = Completer<FocusSoundSet>();
      final player = AssetFocusSoundPlayer(
        player: audio,
        readSoundSet: () => restored.future,
      );
      final playing = player.play(FocusSoundCue.complete);
      await Future<void>.delayed(Duration.zero);
      expect(audio.paths, isEmpty);
      restored.complete(FocusSoundSet.orbitBloom);
      await playing;
      expect(audio.paths, ['sounds/orbit_bloom/focus_complete.wav']);
      await player.dispose();
      await player.play(FocusSoundCue.start);
      expect(audio.paths, hasLength(1));
    },
  );

  test('preview uses separate audio with no timer haptics', () async {
    final haptics = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final timerAudio = RecordingAudioPlayer();
    final previewAudio = RecordingAudioPlayer();
    final timer = AssetFocusSoundPlayer(player: timerAudio);
    final preview = AssetFocusSoundPreviewPlayer(player: previewAudio);
    await timer.play(FocusSoundCue.start);
    final timerHaptics = haptics.length;
    await preview.preview(FocusSoundSet.neonPulse);
    await preview.preview(FocusSoundSet.orbitBloom);
    expect(previewAudio.paths, [
      'sounds/neon_pulse/focus_complete.wav',
      'sounds/orbit_bloom/focus_complete.wav',
    ]);
    expect(previewAudio.volumes, [0.55, 0.55]);
    expect(timerAudio.paths, ['sounds/soft_kalimba/focus_start.wav']);
    expect(timerAudio.stops, 0);
    expect(haptics, hasLength(timerHaptics));
    expect(previewAudio.stops, 2);
    await preview.stop();
    expect(previewAudio.stops, 3);
    await preview.dispose();
    expect(previewAudio.disposals, 1);
    await timer.dispose();
  });

  test(
    'leaving settings during preparation prevents late preview playback',
    () async {
      final audio = RecordingAudioPlayer()..stopping = Completer<void>();
      final preview = AssetFocusSoundPreviewPlayer(player: audio);
      final playing = preview.preview(FocusSoundSet.orbitBloom);
      await Future<void>.delayed(Duration.zero);
      final stopping = preview.stop();
      audio.stopping!.complete();
      await Future.wait([playing, stopping]);
      expect(audio.paths, isEmpty);
      await preview.dispose();
      await preview.preview(FocusSoundSet.neonPulse);
      expect(audio.paths, isEmpty);
      expect(audio.disposals, 1);
    },
  );

  test(
    'preview logs the failed stage and preserves the platform error',
    () async {
      final messages = <String?>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => messages.add(message);
      addTearDown(() => debugPrint = previousDebugPrint);
      final error = PlatformException(
        code: 'LinuxAudioError',
        message: 'Unable to set the pipeline to GST_STATE_READY.',
      );
      final audio = RecordingAudioPlayer()..playError = error;
      final preview = AssetFocusSoundPreviewPlayer(player: audio);
      await expectLater(
        preview.preview(FocusSoundSet.softKalimba),
        throwsA(same(error)),
      );
      expect(messages.join('\n'), contains('soft_kalimba'));
      expect(messages.join('\n'), contains('play'));
      expect(messages.join('\n'), contains('LinuxAudioError'));
      expect(messages.join('\n'), contains('GST_STATE_READY'));

      // A failed audition must not poison the queue for the next attempt.
      audio.playError = null;
      await preview.preview(FocusSoundSet.neonPulse);
      expect(audio.paths.last, 'sounds/neon_pulse/focus_complete.wav');
      await preview.dispose();
    },
  );
}

class RecordingAudioPlayer implements AudioPlayer {
  final paths = <String>[];
  final volumes = <double?>[];
  int stops = 0;
  int disposals = 0;
  Completer<void>? stopping;
  Object? playError;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    if (playError case final error?) throw error;
    paths.add((source as AssetSource).path);
    volumes.add(volume);
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopping?.future;
  }

  @override
  Future<void> dispose() async => disposals++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
