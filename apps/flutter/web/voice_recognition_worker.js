/* global SherpaOnnx, OfflineRecognizer */
'use strict';

const runtime = 'assets/packages/sherpa_onnx_web/assets/';


async function validModel(buffer, model) {
  if (!buffer) return null;
  if (buffer.byteLength !== model.size) return null;
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', buffer));
  const hash = Array.from(digest, (byte) => byte.toString(16).padStart(2, '0')).join('');
  return hash === model.sha256 ? new Uint8Array(buffer) : null;
}

async function fetchModel(url, model, report) {
  const abort = new AbortController();
  let timer;
  function resetTimeout() {
    clearTimeout(timer);
    timer = setTimeout(() => abort.abort(), 30000);
  }
  try {
    resetTimeout();
    const response = await fetch(url, {credentials: 'omit', signal: abort.signal});
    if (!response.ok) throw new Error('Model download failed');
    const reader = response.body.getReader();
    const file = new Uint8Array(model.size);
    let offset = 0;
    while (true) {
      resetTimeout();
      const {value, done} = await reader.read();
      if (done) break;
      file.set(value, offset);
      offset += value.length;
      report(offset);
    }
    return offset === model.size ? validModel(file.buffer, model) : null;
  } finally {
    clearTimeout(timer);
  }
}

async function useModels(data, module) {
  const cache = await caches.open(data.cacheName);
  const total = data.models.reduce((sum, model) => sum + model.size, 0);
  let verified = 0;
  let percent = -1;
  function report(bytes) {
    const next = Math.floor(100 * (verified + bytes) / total);
    if (data.operation === 'download' && next !== percent) {
      percent = next;
      self.postMessage({progress: percent / 100});
    }
  }
  for (const model of data.models) {
    const url = new URL(model.name, data.modelOrigin);
    const cached = await cache.match(url);
    let bytes = await validModel(await cached?.arrayBuffer(), model);
    if (!bytes) {
      if (data.operation !== 'download') return false;
      bytes = await fetchModel(url, model, report);
      if (!bytes) throw new Error('Invalid speech model');
      await cache.put(url, new Response(bytes));
    }
    verified += model.size;
    report(0);
    if (module) module.FS.writeFile(`/${model.name}`, bytes);
  }
  return true;
}

self.onmessage = async ({ data }) => {
  if (data.operation === 'check' || data.operation === 'download') {
    try {
      self.postMessage({ text: await useModels(data) ? 'ready' : 'missing' });
    } catch (_) {
      self.postMessage(data.operation === 'check' ? {text: 'missing'} : {code: 'voice_model_download_failed'});
    }
    return;
  }
  let module;
  try {
    importScripts(`${runtime}sherpa-onnx-wasm-web.js`, `${runtime}sherpa-onnx-asr.js`);
    module = await SherpaOnnx({ locateFile: (name) => new URL(`${runtime}${name}`, self.location.href).href });
  } catch (_) {
    self.postMessage({ code: 'speech_unavailable' });
    return;
  }
  try {
    if (!await useModels(data, module)) throw new Error('Model unavailable');
  } catch (_) {
    self.postMessage({ code: 'voice_model_download_failed' });
    return;
  }
  let recognizer;
  try {
    const [encoder, decoder, tokens] = data.models.map((model) => `/${model.name}`);
    recognizer = new OfflineRecognizer({
      modelConfig: {
        whisper: { encoder, decoder, language: data.language, task: 'transcribe', tailPaddings: -1 },
        tokens,
        numThreads: 1,
      },
    }, module);
    if (!recognizer.handle) throw new Error('Cannot initialize speech recognition');
    const text = [];
    for (const samples of data.segments) {
      const stream = recognizer.createStream();
      try {
        stream.acceptWaveform(data.rate, samples);
        recognizer.decode(stream);
        const transcript = recognizer.getResult(stream).text?.trim();
        if (transcript) text.push(transcript);
      } finally {
        stream.free();
      }
    }
    self.postMessage({ text: text.join(' ') });
  } catch (_) {
    self.postMessage({ code: 'speech_recognition_failed' });
  } finally {
    recognizer?.free();
  }
};
