import 'package:app_account/app_account.dart';
import 'package:app_voice/app_voice.dart';


/// Authenticated backend transport for recorded voice transcription.
final class AccountVoiceBackend {
  AccountVoiceBackend(this._account);

  final AccountClient? Function() _account;
  bool _disposed = false;

  Future<Object?> call(Map<String, Object?> body) async {
    final account = _account();
    if (_disposed || account == null || account.currentUserId == null) {
      throw const VoiceRecognitionException(
        'speech_unavailable',
        'Sign in to use voice transcription.',
      );
    }
    return (await account.invokeFunction(
      'pomodoist-transcribe',
      body: body,
    )).data;
  }

  void dispose() => _disposed = true;
}
