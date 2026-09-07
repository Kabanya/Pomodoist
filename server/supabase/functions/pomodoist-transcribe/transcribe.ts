/** Authenticated audio proxy. Provider credentials stay server-side. */
export type TranscriptionDeps = {
  env: { get(key: string): string | undefined };
  authenticate(authorization: string): Promise<string | null>;
  fetch: typeof fetch;
};

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};
const endpoint = "https://openrouter.ai/api/v1/audio/transcriptions";
const defaultModel = "openai/whisper-large-v3-turbo";
const formats = new Set(["wav", "webm", "mp3", "m4a", "mp4", "ogg", "flac", "aac"]);

class VoiceHttpError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
  }
}
function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status, headers: { ...headers, "Content-Type": "application/json" },
  });
}
function invalidAudio(): never {
  throw new VoiceHttpError(400, "invalid_audio", "The recording is empty, invalid or unsupported.");
}
function setting(deps: TranscriptionDeps, key: string, fallback: number, ceiling: number) {
  const raw = deps.env.get(key)?.trim();
  const value = raw ? Number(raw) : fallback;
  if (!Number.isSafeInteger(value) || value <= 0 || value > ceiling) {
    throw new VoiceHttpError(503, "transcription_unavailable", "Voice transcription is not configured correctly.");
  }
  return value;
}
function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown> : null;
}

/** Bound streaming bodies too; Content-Length alone is not a security boundary. */
async function readBounded(stream: ReadableStream<Uint8Array> | null, limit: number) {
  if (!stream) return "";
  const reader = stream.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let size = 0;
  let text = "";
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) {
        await reader.cancel();
        throw new VoiceHttpError(413, "recording_too_large", "The recording exceeds the upload limit.");
      }
      text += decoder.decode(value, { stream: true });
    }
    return text + decoder.decode();
  } finally {
    reader.releaseLock();
  }
}

function validateAudio(data: string, format: string, maxBytes: number, maxSeconds: number) {
  if (!data || data.length > Math.ceil(maxBytes / 3) * 4) {
    if (!data) invalidAudio();
    throw new VoiceHttpError(413, "recording_too_large", "The recording exceeds the upload limit.");
  }
  // Avoid a repeated-group regexp: multi-minute base64 can overflow V8's stack.
  if (data.length % 4 !== 0 || /[^A-Za-z0-9+/=]/.test(data)) invalidAudio();
  const padding = data.indexOf("=");
  if (padding >= 0 && !/^[A-Za-z0-9+/]{2,3}={1,2}$/.test(data.slice(-4))) invalidAudio();
  if (padding >= 0 && padding < data.length - 2) invalidAudio();
  const binary = atob(data);
  if (binary.length > maxBytes) {
    throw new VoiceHttpError(413, "recording_too_large", "The recording exceeds the upload limit.");
  }
  if (binary.length < 8) invalidAudio();
  const byte = (offset: number) => binary.charCodeAt(offset);
  const matches = (offset: number, value: string) => binary.slice(offset, offset + value.length) === value;
  const compatible = format === "wav" ? matches(0, "RIFF") && matches(8, "WAVE")
    : format === "webm" ? [0x1a, 0x45, 0xdf, 0xa3].every((v, i) => byte(i) === v)
    : format === "mp3" ? matches(0, "ID3") || (byte(0) === 0xff && (byte(1) & 0xe0) === 0xe0)
    : format === "m4a" || format === "mp4" ? matches(4, "ftyp")
    : format === "ogg" ? matches(0, "OggS")
    : format === "flac" ? matches(0, "fLaC")
    : format === "aac" ? byte(0) === 0xff && (byte(1) & 0xf6) === 0xf0
    : false;
  if (!compatible) invalidAudio();
  if (format !== "wav") return; // Compressed containers are fully validated upstream.

  // Our recorder emits PCM WAV. Measure its actual samples, not a client duration.
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < bytes.length; index++) bytes[index] = byte(index);
  const view = new DataView(bytes.buffer);
  if (bytes.length < 44 || view.getUint32(4, true) + 8 !== bytes.length) invalidAudio();
  let byteRate = 0;
  let dataSize = 0;
  for (let offset = 12; offset + 8 <= bytes.length;) {
    const length = view.getUint32(offset + 4, true);
    const start = offset + 8;
    if (start + length > bytes.length) invalidAudio();
    if (matches(offset, "fmt ")) {
      if (length < 16) invalidAudio();
      const encoding = view.getUint16(start, true);
      const channels = view.getUint16(start + 2, true);
      const sampleRate = view.getUint32(start + 4, true);
      const bits = view.getUint16(start + 14, true);
      byteRate = view.getUint32(start + 8, true);
      const block = channels * bits / 8;
      if (![1, 3].includes(encoding) || channels < 1 || channels > 8 ||
        sampleRate < 8000 || sampleRate > 192000 || ![8, 16, 24, 32, 64].includes(bits) ||
        view.getUint16(start + 12, true) !== block || byteRate !== sampleRate * block) invalidAudio();
    } else if (matches(offset, "data")) {
      dataSize += length;
    }
    offset = start + length + (length % 2);
  }
  if (!byteRate || !dataSize) invalidAudio();
  if (dataSize / byteRate > maxSeconds + 0.05) {
    throw new VoiceHttpError(413, "recording_too_long", "The recording exceeds the duration limit.");
  }
}

async function transcribe(
  deps: TranscriptionDeps,
  apiKey: string,
  payload: Record<string, unknown>,
  timeoutMs: number,
) {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      reject(new VoiceHttpError(504, "transcription_timeout", "Transcription timed out. Please retry the saved recording."));
      controller.abort();
    }, timeoutMs);
  });
  try {
    return await Promise.race([timeout, (async () => {
      const response = await deps.fetch(endpoint, {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: controller.signal,
        redirect: "error", // Never forward credentials to a redirected host.
      });
      if (!response.ok) {
        await response.body?.cancel(); // Do not log/return provider bodies or diagnostics.
        if (response.status === 429) throw new VoiceHttpError(429, "transcription_rate_limited", "Transcription is busy. Please retry the saved recording.");
        if ([401, 402, 403].includes(response.status)) throw new VoiceHttpError(503, "transcription_unavailable", "Voice transcription is temporarily unavailable.");
        if (response.status === 413) throw new VoiceHttpError(413, "recording_too_large", "The provider cannot accept a recording this large.");
        if ([400, 415, 422].includes(response.status)) invalidAudio();
        throw new VoiceHttpError(502, "transcription_failed", "The transcription provider is unavailable. Please retry.");
      }
      let result: Record<string, unknown> | null;
      try {
        result = object(JSON.parse(await readBounded(response.body, 128 * 1024)));
      } catch {
        throw new VoiceHttpError(502, "invalid_transcript", "The provider returned an invalid transcript. Please retry.");
      }
      const text = typeof result?.text === "string" ? result.text.trim() : "";
      if (!text || text.length > 32768) {
        throw new VoiceHttpError(502, "invalid_transcript", "No usable speech was recognized. Please retry the saved recording.");
      }
      return text;
    })()]);
  } finally {
    clearTimeout(timer);
    controller.abort();
  }
}

export async function handleVoiceTranscription(req: Request, deps: TranscriptionDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (req.method !== "POST") return json({ ok: false, code: "method_not_allowed", error: "Use POST." }, 405);
  try {
    const authorization = req.headers.get("Authorization") ?? "";
    if (!/^Bearer\s+\S+$/i.test(authorization)) {
      throw new VoiceHttpError(401, "unauthorized", "Sign in to use voice transcription.");
    }
    let userId: string | null;
    try { userId = await deps.authenticate(authorization); }
    catch { throw new VoiceHttpError(503, "authentication_unavailable", "Account verification is temporarily unavailable."); }
    if (!userId) throw new VoiceHttpError(401, "unauthorized", "Sign in to use voice transcription.");

    const provider = deps.env.get("VOICE_TRANSCRIPTION_PROVIDER")?.trim() || "openrouter";
    const apiKey = deps.env.get("OPENROUTER_API_KEY")?.trim() || deps.env.get("POMODOIST_OPENROUTER_API_KEY")?.trim();
    if (provider !== "openrouter" || !apiKey) {
      throw new VoiceHttpError(503, "transcription_unavailable", "Voice transcription is not configured on this server.");
    }
    const maxBytes = setting(deps, "VOICE_TRANSCRIPTION_MAX_BYTES", 12 * 1024 * 1024, 25 * 1024 * 1024);
    const maxSeconds = setting(deps, "VOICE_TRANSCRIPTION_MAX_SECONDS", 300, 3600);
    const timeoutMs = setting(deps, "VOICE_TRANSCRIPTION_TIMEOUT_MS", 55000, 60000);
    const bodyLimit = Math.ceil(maxBytes / 3) * 4 + 4096;
    if (Number(req.headers.get("Content-Length")) > bodyLimit) {
      throw new VoiceHttpError(413, "recording_too_large", "The recording exceeds the upload limit.");
    }
    if (!req.headers.get("Content-Type")?.toLowerCase().startsWith("application/json")) {
      throw new VoiceHttpError(415, "invalid_content_type", "Use application/json with input_audio.");
    }
    let body: Record<string, unknown> | null;
    try { body = object(JSON.parse(await readBounded(req.body, bodyLimit))); }
    catch (error) {
      if (error instanceof VoiceHttpError) throw error;
      throw new VoiceHttpError(400, "invalid_request", "Request body must be valid JSON.");
    }
    const audio = object(body?.input_audio);
    if (!audio || typeof audio.data !== "string" || typeof audio.format !== "string" || !formats.has(audio.format)) invalidAudio();
    const locale = body?.locale;
    if (locale != null && (typeof locale !== "string" || !/^[a-zA-Z]{2,3}(?:[-_][a-zA-Z0-9]{2,8})*$/.test(locale))) {
      throw new VoiceHttpError(400, "invalid_locale", "Use a valid language tag.");
    }
    validateAudio(audio.data, audio.format, maxBytes, maxSeconds);
    const model = deps.env.get("OPENROUTER_TRANSCRIPTION_MODEL")?.trim() || defaultModel;
    const text = await transcribe(deps, apiKey, {
      model,
      input_audio: { data: audio.data, format: audio.format },
      ...(typeof locale === "string" ? { language: locale.split(/[-_]/)[0].toLowerCase() } : {}),
    }, timeoutMs);
    return json({ ok: true, text });
  } catch (error) {
    const failure = error instanceof VoiceHttpError ? error
      : new VoiceHttpError(502, "transcription_failed", "Voice transcription failed. Please retry the saved recording.");
    return json({ ok: false, code: failure.code, error: failure.message, retryable: failure.status === 429 || failure.status >= 500 }, failure.status);
  }
}
