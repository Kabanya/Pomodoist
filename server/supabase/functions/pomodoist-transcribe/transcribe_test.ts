import assert from "node:assert/strict";
import { handleVoiceTranscription, type TranscriptionDeps } from "./transcribe.ts";

function wav(seconds = 1): Uint8Array {
  const size = seconds * 32000;
  const bytes = new Uint8Array(44 + size);
  const view = new DataView(bytes.buffer);
  const text = (offset: number, value: string) => {
    for (let i = 0; i < value.length; i++) bytes[offset + i] = value.charCodeAt(i);
  };
  text(0, "RIFF"); view.setUint32(4, 36 + size, true); text(8, "WAVE");
  text(12, "fmt "); view.setUint32(16, 16, true); view.setUint16(20, 1, true);
  view.setUint16(22, 1, true); view.setUint32(24, 16000, true);
  view.setUint32(28, 32000, true); view.setUint16(32, 2, true);
  view.setUint16(34, 16, true); text(36, "data"); view.setUint32(40, size, true);
  return bytes;
}
function encode(bytes: Uint8Array): string {
  let value = "";
  for (const byte of bytes) value += String.fromCharCode(byte);
  return btoa(value);
}
function body(bytes = wav(), format = "wav") {
  return { input_audio: { data: encode(bytes), format }, locale: "ru-RU" };
}
function request(value: unknown = body(), auth = true): Request {
  return new Request("https://example.test/functions/v1/pomodoist-transcribe", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(auth ? { Authorization: "Bearer user-token" } : {}),
    },
    body: JSON.stringify(value),
  });
}
function setup(options: {
  user?: boolean; env?: Record<string, string | undefined>; status?: number;
  result?: unknown; fetch?: typeof fetch;
} = {}) {
  const calls: { url: string; init?: RequestInit }[] = [];
  const env = { POMODOIST_OPENROUTER_API_KEY: "server-only-secret", ...options.env };
  const deps: TranscriptionDeps = {
    env: { get: (key) => env[key as keyof typeof env] },
    authenticate: async () => options.user === false ? null : "user-1",
    fetch: options.fetch ?? (async (url, init) => {
      calls.push({ url: String(url), init });
      return new Response(JSON.stringify(options.result ?? { text: "Купить молоко" }), {
        status: options.status ?? 200, headers: { "Content-Type": "application/json" },
      });
    }) as typeof fetch,
  };
  return { deps, calls };
}

Deno.test("transcribes with server credentials, default model and normalized locale", async () => {
  const { deps, calls } = setup();
  const response = await handleVoiceTranscription(request(), deps);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true, text: "Купить молоко" });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://openrouter.ai/api/v1/audio/transcriptions");
  assert.equal(new Headers(calls[0].init?.headers).get("Authorization"), "Bearer server-only-secret");
  assert.deepEqual(JSON.parse(String(calls[0].init?.body)), {
    model: "openai/whisper-large-v3-turbo", input_audio: body().input_audio, language: "ru",
  });
  assert.equal(calls[0].init?.redirect, "error");
  assert.equal(response.headers.get("Cache-Control"), "no-store");
});
Deno.test("auth is required even when an API key is configured", async () => {
  for (const withHeader of [false, true]) {
    const { deps, calls } = setup({ user: false });
    assert.equal((await handleVoiceTranscription(request(body(), withHeader), deps)).status, 401);
    assert.equal(calls.length, 0);
  }
});
Deno.test("auth service failures are sanitized", async () => {
  const { deps, calls } = setup();
  deps.authenticate = async () => { throw new Error("private auth details"); };
  const response = await handleVoiceTranscription(request(), deps);
  assert.equal(response.status, 503);
  assert.equal(calls.length, 0);
  assert.ok(!(await response.text()).includes("private auth"));
});
Deno.test("CORS preflight and non-POST requests never invoke the provider", async () => {
  const { deps, calls } = setup();
  const response = await handleVoiceTranscription(new Request("https://example.test", { method: "OPTIONS" }), deps);
  assert.equal(response.status, 204);
  assert.match(response.headers.get("Access-Control-Allow-Methods") ?? "", /POST/);
  assert.equal((await handleVoiceTranscription(new Request("https://example.test"), deps)).status, 405);
  assert.equal(calls.length, 0);
});
Deno.test("server configuration controls model; clients cannot override it", async () => {
  const { deps, calls } = setup({ env: { OPENROUTER_TRANSCRIPTION_MODEL: "openai/whisper-large-v3" } });
  const value = { ...body(), model: "untrusted/model", endpoint: "https://attacker.test", apiKey: "client-key" };
  assert.equal((await handleVoiceTranscription(request(value), deps)).status, 200);
  const forwarded = JSON.parse(String(calls[0].init?.body));
  assert.equal(forwarded.model, "openai/whisper-large-v3");
  assert.equal(forwarded.apiKey, undefined);
});
Deno.test("uses the Pomodoist server key even when a generic OpenRouter key exists", async () => {
  const { deps, calls } = setup({ env: { OPENROUTER_API_KEY: "unrelated-secret", POMODOIST_OPENROUTER_API_KEY: " existing-secret " } });
  assert.equal((await handleVoiceTranscription(request(), deps)).status, 200);
  assert.equal(new Headers(calls[0].init?.headers).get("Authorization"), "Bearer existing-secret");
});
Deno.test("missing credentials and unsupported configured providers fail closed", async () => {
  for (const env of [{ POMODOIST_OPENROUTER_API_KEY: "" }, { VOICE_TRANSCRIPTION_PROVIDER: "unknown" }]) {
    const { deps, calls } = setup({ env });
    assert.equal((await handleVoiceTranscription(request(), deps)).status, 503);
    assert.equal(calls.length, 0);
  }
});
Deno.test("rejects malformed JSON, invalid base64, empty audio and incompatible formats", async () => {
  for (const value of [null, [], {}, body(new Uint8Array()), body(wav(), "exe"),
    { input_audio: { data: "not base64!", format: "wav" } },
    { input_audio: { data: "AAAA", format: "wav" } },
    { ...body(), locale: 123 }]) {
    const { deps, calls } = setup();
    assert.equal((await handleVoiceTranscription(request(value), deps)).status, 400);
    assert.equal(calls.length, 0);
  }
  const { deps } = setup();
  const req = new Request("https://example.test", { method: "POST", headers: { Authorization: "Bearer x", "Content-Type": "application/json" }, body: "{" });
  assert.equal((await handleVoiceTranscription(req, deps)).status, 400);
});
Deno.test("rejects MIME mismatch without invoking provider", async () => {
  const { deps, calls } = setup();
  assert.equal((await handleVoiceTranscription(request(body(wav(), "webm")), deps)).status, 400);
  assert.equal(calls.length, 0);
});
Deno.test("recognizes common encoded containers without re-encoding", async () => {
  const samples: [string, number[]][] = [
    ["webm", [0x1a, 0x45, 0xdf, 0xa3, 0, 0, 0, 0]],
    ["mp3", [73, 68, 51, 4, 0, 0, 0, 0]],
    ["m4a", [0, 0, 0, 24, 102, 116, 121, 112, 77, 52, 65, 32]],
    ["ogg", [79, 103, 103, 83, 0, 0, 0, 0]],
    ["flac", [102, 76, 97, 67, 0, 0, 0, 0]],
    ["aac", [0xff, 0xf1, 0x50, 0, 0, 0, 0, 0]],
  ];
  for (const [format, bytes] of samples) {
    const { deps, calls } = setup();
    const value = body(new Uint8Array(bytes), format);
    assert.equal((await handleVoiceTranscription(request(value), deps)).status, 200, format);
    assert.deepEqual(JSON.parse(String(calls[0].init?.body)).input_audio, value.input_audio);
  }
});
Deno.test("enforces actual WAV duration rather than trusting client metadata", async () => {
  const { deps, calls } = setup({ env: { VOICE_TRANSCRIPTION_MAX_SECONDS: "1" } });
  const value = { ...body(wav(2)), durationSeconds: 0.01 };
  const response = await handleVoiceTranscription(request(value), deps);
  assert.equal(response.status, 413);
  assert.equal((await response.json()).code, "recording_too_long");
  assert.equal(calls.length, 0);
});
Deno.test("accepts exactly the application's five-minute recording limit", async () => {
  const { deps } = setup();
  assert.equal((await handleVoiceTranscription(request(body(wav(300))), deps)).status, 200);
});
Deno.test("rejects truncated WAV and inconsistent PCM format", async () => {
  const truncated = wav().slice(0, 50);
  const invalidRate = wav(); new DataView(invalidRate.buffer).setUint32(28, 0, true);
  for (const bytes of [truncated, invalidRate]) {
    const { deps, calls } = setup();
    assert.equal((await handleVoiceTranscription(request(body(bytes)), deps)).status, 400);
    assert.equal(calls.length, 0);
  }
});
Deno.test("bounds both declared and streamed request bodies", async () => {
  for (const declared of [false, true]) {
    const { deps, calls } = setup({ env: { VOICE_TRANSCRIPTION_MAX_BYTES: "64" } });
    const headers: Record<string, string> = { Authorization: "Bearer x", "Content-Type": "application/json" };
    if (declared) headers["Content-Length"] = "1000000";
    const req = new Request("https://example.test", { method: "POST", headers, body: JSON.stringify(body()) });
    assert.equal((await handleVoiceTranscription(req, deps)).status, 413);
    assert.equal(calls.length, 0);
  }
});
Deno.test("maps provider errors without exposing upstream bodies or credentials", async () => {
  for (const [status, expected] of [[400, 400], [401, 503], [402, 503], [403, 503], [413, 413], [422, 400], [429, 429], [500, 502], [503, 502]]) {
    const { deps } = setup({ status, result: { error: { message: "server-only-secret provider diagnostics" } } });
    const response = await handleVoiceTranscription(request(), deps);
    assert.equal(response.status, expected);
    assert.ok(!(await response.text()).includes("server-only-secret"));
  }
});
Deno.test("rejects empty, malformed and excessively large transcripts", async () => {
  for (const result of [{ text: "  " }, {}, { text: 5 }, { text: "x".repeat(32769) }]) {
    const { deps } = setup({ result });
    assert.equal((await handleVoiceTranscription(request(), deps)).status, 502);
  }
});
Deno.test("network errors and timeouts are recoverable and sanitized", async () => {
  const failed = setup({ fetch: (async () => { throw new Error("private connection details"); }) as typeof fetch });
  assert.equal((await handleVoiceTranscription(request(), failed.deps)).status, 502);
  let aborted = false;
  const slow = setup({ env: { VOICE_TRANSCRIPTION_TIMEOUT_MS: "5" }, fetch: ((_url, init) => {
    const signal = (init as { signal?: AbortSignal | null } | undefined)?.signal;
    signal?.addEventListener("abort", () => { aborted = true; });
    return new Promise<Response>(() => {});
  }) as typeof fetch });
  assert.equal((await handleVoiceTranscription(request(), slow.deps)).status, 504);
  assert.equal(aborted, true);
});
Deno.test("timeout covers response body consumption as well as initial headers", async () => {
  const { deps } = setup({ env: { VOICE_TRANSCRIPTION_TIMEOUT_MS: "5" }, fetch: (async () => new Response(new ReadableStream({ start() {} }))) as typeof fetch });
  assert.equal((await handleVoiceTranscription(request(), deps)).status, 504);
});
Deno.test("never falls back to a generic OpenRouter key when the Pomodoist key is missing", async () => {
  for (const key of [undefined, "", "   "]) {
    const { deps, calls } = setup({ env: {
      POMODOIST_OPENROUTER_API_KEY: key,
      OPENROUTER_API_KEY: "unrelated-secret",
    } });
    const response = await handleVoiceTranscription(request(), deps);
    assert.equal(response.status, 503);
    assert.equal((await response.json()).code, "transcription_unavailable");
    assert.equal(calls.length, 0);
  }
});
