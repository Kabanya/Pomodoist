import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/services/audio/focus_sound_preview_player.dart';

final focusSoundPreviewPlayerProvider =
    Provider.autoDispose<FocusSoundPreviewPlayer>((ref) {
      final player = AssetFocusSoundPreviewPlayer();
      ref.onDispose(() => unawaited(player.dispose()));
      return player;
    });
