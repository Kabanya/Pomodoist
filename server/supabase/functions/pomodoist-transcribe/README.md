# Non-Apple voice transcription

Linux, Windows, Android and **all browsers** record through `record` and submit
WAV audio to the authenticated `pomodoist-transcribe` Edge Function. Native iOS
and macOS continue using the unchanged `app_voice` Apple Speech implementation.
The existing recording/loading/retry UI, transcript analysis and task creation
remain the same, including the existing UI entitlement gate. The new backend
requires a signed-in account but does not add separate purchase verification;
local Apple speech does not acquire a new server dependency.

## Server configuration and deployment

Configure **only backend secrets/environment** (Supabase function secrets or
`server/.env` for the Docker stack). Never use Flutter `--dart-define`, the root
client environment template, web runtime config, or a client settings field for
these values.

| Variable | Default / purpose |
| --- | --- |
| `OPENROUTER_API_KEY` | Required server credential; existing `POMODOIST_OPENROUTER_API_KEY` is a fallback. |
| `OPENROUTER_TRANSCRIPTION_MODEL` | `openai/whisper-large-v3-turbo` |
| `VOICE_TRANSCRIPTION_PROVIDER` | `openrouter`; unsupported values fail closed. Future providers only need a server adapter, not voice UI changes. |
| `VOICE_TRANSCRIPTION_MAX_BYTES` | `12582912` (12 MiB decoded audio; configurable up to 25 MiB server-side). |
| `VOICE_TRANSCRIPTION_MAX_SECONDS` | `300` for actual PCM WAV samples; the application records at most five minutes. |
| `VOICE_TRANSCRIPTION_TIMEOUT_MS` | `55000` including response consumption; maximum 60000. |

Deploy `pomodoist-transcribe` together with the client. The Docker functions image
copies the function automatically; rebuild/recreate the functions service after
changing its code or environment. For hosted Supabase, deploy the new function
using `server/supabase/config.toml`. Its handler validates the bearer token with
Auth `getUser()` even though gateway `verify_jwt` is disabled for compatibility
with asymmetric JWTs. Missing/invalid sessions, anonymous users and missing
provider credentials cannot invoke OpenRouter. No service-role credential is
used by this function. Protect provider spend with an OpenRouter key budget and
deployment-level rate limits; this endpoint follows the existing authenticated
voice backend boundary rather than introducing a separate billing system.

Ensure any external reverse proxy allows at least **17 MiB JSON request bodies**
and a request timeout of at least **75 seconds**. The client uses the existing
account connection; no new public endpoint or model configuration is required.
Increasing only the server limit does not increase the current client's 12 MiB
upload bound or five-minute recording UI limit.

## Wire protocol and validation

The client sends JSON `{input_audio: {data: "<base64>", format: "wav"}, locale?}`
using `AccountClient.invokeFunction`. The server calls
`https://openrouter.ai/api/v1/audio/transcriptions` with JSON
`{model, input_audio, language?}` and the **server's** API key. Successful responses
are `{ok: true, text}`; failures are `{ok: false, code, error, retryable}`.
Client-supplied model, URL, API key and duration fields are not trusted.

WAV, WebM, MP3, M4A/MP4, Ogg, FLAC and AAC uploads have bounded base64 and container
signature validation. WAV additionally validates the header and actual duration;
compressed formats rely on the provider for decoding/duration validation. The
app deliberately records a single portable format (16 kHz, mono PCM WAV), without
transcoding: five minutes is approximately 9.6 MB before base64. Empty/malformed
transcripts, invalid audio, rate limits, provider errors, network failures and
both header/body timeouts return sanitized errors. Redirects are disabled for
the credential-bearing provider request. Audio, transcript text, tokens and
provider response bodies are never logged or included in error diagnostics.

## Local audio lifecycle and platform prerequisites

Native recordings and locale/account metadata are retained in the application
support directory until success, explicit close/discard, or recording again.
Failures can be retried without asking the microphone to re-record. Account
ownership is checked before uploads. Controller/overlay disposal aborts the local
attempt without discarding recoverable audio; a late provider response cannot
replace a newer attempt. HTTP cancellation is not exposed by `AccountClient`, so
in-flight server work may still finish or hit its timeout after local cancellation.

Browser retries retain independent audio bytes **only in the current page's
memory**, including across overlay/controller disposal. Reloading/closing the tab
loses that pending recording; audio is never written to browser localStorage.
Record in a secure context (HTTPS or localhost) and grant the site's microphone
permission. Browsers on Apple devices use this backend path as well.

Linux requires the `record_linux` runtime tools: `parecord`, `pactl`, and `ffmpeg`
(for example, `pulseaudio-utils ffmpeg` on Debian/Ubuntu, or `libpulse ffmpeg` on
Arch). A compatible PulseAudio server or PipeWire PulseAudio compatibility layer
must be running. These are host dependencies, not newly bundled AppImage binaries.
Windows needs microphone access for desktop apps; its recovery button opens the
microphone privacy settings. Android already declares `RECORD_AUDIO`; permanent
permission denial can be recovered through the app's system settings. The adapter
does not request storage access or Apple Speech/Siri permissions on these platforms.

## Verification

```sh
deno test --config server/supabase/deno.json server/supabase/functions/pomodoist-transcribe
flutter test test/backend_voice_test.dart test/voice_recording_store_test.dart test/quick_add_voice_test.dart
flutter test --platform chrome web_test/voice_recording_store_test.dart
flutter build web --debug
```

The server tests exercise the actual handler with an injected provider transport,
including a complete five-minute WAV, authentication, validation, configuration,
limits, sanitized errors and timeouts. Flutter tests cover transcript events,
permission denial, retry preservation, explicit/late cancellation, pending audio
restoration, account isolation, platform selection and the recording timer.
Browser storage tests verify survival after the recorder revokes its blob URL.

Before release, test real microphones on Linux/Windows/Android and Chrome/Firefox/
Safari over HTTPS: allow/deny permission, record a short phrase and a full five
minutes, stop, create a task, go offline and retry, close/discard while processing,
and verify iOS/macOS still use native recognition. Live OpenRouter calls require
an operator-supplied key and are not made by unit tests.

Protocol references (checked for this implementation):
- https://openrouter.ai/blog/tutorials/transcription-on-openrouter/
- https://openrouter.ai/openai/whisper-large-v3-turbo
- https://pub.dev/packages/record/versions/6.2.1
