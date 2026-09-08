import 'update_release.dart';

enum UpdatePhase { idle, checking, available, downloading, verifying, installing, upToDate, failed }

typedef UpdateProgress = void Function(UpdatePhase phase, double? fraction);

class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class UpdateSource {
  Future<UpdateOffer?> findUpdate({required UpdateVersion current,
    required UpdateTarget target, required UpdateChannel channel});
  void dispose();
}

abstract class UpdateInstaller {
  UpdateTarget? get target;
  String? get unavailableReason;
  Future<String?> acknowledgeStartup();
  Future<void> install(UpdateOffer offer, UpdateProgress progress);
  void dispose();
}

class SavedUpdatePreferences {
  const SavedUpdatePreferences({this.channel = UpdateChannel.stable,
    this.seenTags = const {}});
  final UpdateChannel channel;
  final Set<String> seenTags;
}

abstract class UpdatePreferences {
  Future<SavedUpdatePreferences> load();
  Future<void> setChannel(UpdateChannel channel);
  Future<void> markSeen(Set<String> tags);
}
