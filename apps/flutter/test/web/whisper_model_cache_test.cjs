const assert = require('node:assert/strict');
const { createHash, webcrypto } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

test('reuses the legacy Tiny cache and resumes interrupted model downloads', async () => {
  const script = readFileSync(join(__dirname, '../../web/voice_recognition_worker.js'), 'utf8');
  const tiny = {
    cacheName: 'pomodoist-whisper-tiny-v1',
    modelOrigin: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/65176e2deb88badc814a94058666cadccc29b61c/',
  };
  const base = {cacheName: 'pomodoist-whisper-base-v1', modelOrigin: 'https://example.test/base/'};
  function fixture(name) {
    const bytes = Buffer.from(name);
    return {name, size: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex')};
  }
  tiny.models = ['tiny-encoder.int8.onnx', 'tiny-decoder.int8.onnx', 'tiny-tokens.txt'].map(fixture);
  base.models = ['base-encoder.int8.onnx', 'base-decoder.int8.onnx', 'base-tokens.txt'].map(fixture);
  const storage = new Map([[tiny.cacheName, new Map(tiny.models.map(file =>
    [tiny.modelOrigin + file.name, new Response(file.name)]))]]);
  const caches = {open: async name => {
    if (!storage.has(name)) storage.set(name, new Map());
    const cache = storage.get(name);
    return {
      match: async url => cache.get(url.href)?.clone(),
      put: async (url, response) => cache.set(url.href, response),
    };
  }};
  let interrupt = true;
  const requests = [];
  async function fetch(url) {
    const name = url.pathname.split('/').pop();
    requests.push(name);
    return new Response(interrupt && name === base.models[1].name ? 'corrupt' : name);
  }
  const self = {};
  runInNewContext(script, {self, caches, fetch, crypto: webcrypto, URL, Response, Uint8Array,
    AbortController, setTimeout, clearTimeout});
  async function run(model, operation) {
    let result;
    self.postMessage = message => { if (message.progress === undefined) result = message; };
    await self.onmessage({data: {...model, operation}});
    return result;
  }
  assert.equal((await run(tiny, 'check')).text, 'ready');
  assert.equal((await run(tiny, 'download')).text, 'ready');
  assert.equal((await run(base, 'check')).text, 'missing');
  assert.deepEqual(requests, []);
  assert.equal((await run(base, 'download')).code, 'voice_model_download_failed');
  assert.equal((await run(base, 'check')).text, 'missing');
  interrupt = false;
  requests.length = 0;
  assert.equal((await run(base, 'download')).text, 'ready');
  assert.deepEqual(requests, base.models.slice(1).map(file => file.name));
  assert.equal((await run(tiny, 'check')).text, 'ready');
});
