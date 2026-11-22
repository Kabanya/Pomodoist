import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CustomModelKeyStore {
  CustomModelKeyStore({this.sessionOnly = kIsWeb});

  final bool sessionOnly;
  final _memory = <String, String>{};
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
    // Direct-download and local macOS builds can use the login Keychain
    // without a provisioning profile or a shared access group.
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  Future<String?> read(String name) async =>
      sessionOnly ? _memory[name] : _storage.read(key: name);

  Future<void> write(String name, String? value) async {
    if (sessionOnly) {
      if (value == null) {
        _memory.remove(name);
      } else {
        _memory[name] = value;
      }
    } else if (value == null) {
      await _storage.delete(key: name);
    } else {
      await _storage.write(key: name, value: value);
    }
  }
}
