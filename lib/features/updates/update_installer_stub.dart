import 'update_contracts.dart';
import 'update_release.dart';

UpdateInstaller createUpdateInstaller() => _UnsupportedUpdateInstaller();

class _UnsupportedUpdateInstaller implements UpdateInstaller {
  @override
  UpdateTarget? get target => null;
  @override
  String? get unavailableReason => null;
  @override
  Future<String?> acknowledgeStartup() async => null;
  @override
  Future<void> install(UpdateOffer offer, UpdateProgress progress) async =>
      throw const UpdateFailure('Desktop updates are not supported on this platform.');
  @override
  void dispose() {}
}
