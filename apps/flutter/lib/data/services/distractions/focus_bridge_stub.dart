import 'package:shared_preferences/shared_preferences.dart';

class FocusBridge {
  FocusBridge({
    required String owner,
    required String flavor,
    required Future<Map<String, dynamic>> Function() state,
    required Future<Map<String, dynamic>> Function(Map<String, dynamic>)
    command,
    SharedPreferences? preferences,
    int? listenPort,
  });
  int get port => 0;
  String? get pairingCode => null;
  String? error;
  String pair() => throw UnsupportedError('Desktop pairing is unavailable.');
  Future<void> start() async {}
  Future<void> revoke() async {}
  Future<void> dispose() async {}
}
