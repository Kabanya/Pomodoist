import test from 'node:test';
import assert from 'node:assert/strict';
import { Realtime } from '../src/realtime.js';
import { pkce } from '../src/client.js';
import { parseChallenge } from '../../web/auth/extension-challenge.js';
const tick = () => new Promise(resolve => setImmediate(resolve));
class Socket {
  static instances = [];
  constructor(url) { this.url = url; this.readyState = 1; this.sent = []; Socket.instances.push(this); }
  send(text) { this.sent.push(JSON.parse(text)); }
  close() { this.readyState = 3; }
  message(value) { this.onmessage?.({ data: JSON.stringify(value) }); }
}
const context = { apiUrl: 'https://api.example.test', anonKey: 'public', accessToken: 'private-token', userId: 'a', deviceId: 'device' };
test('Realtime joins the same private account channel, pulls on join/hints and stops on close', async () => {
  let pulls = 0, live = false;
  const rt = new Realtime(async () => context, () => pulls++, value => { live = value; }, Socket);
  rt.start(); await tick(); const socket = Socket.instances.at(-1); socket.onopen();
  const join = socket.sent[0];
  assert.equal(join.topic, 'realtime:sync:a:pomodoist'); assert.equal(join.payload.config.private, true);
  assert.equal(join.payload.access_token, 'private-token'); assert.ok(!socket.url.includes('private-token'));
  socket.message({ topic: join.topic, event: 'phx_reply', ref: join.ref, payload: { status: 'ok' } });
  assert.equal(live, true); assert.equal(pulls, 1);
  socket.message({ topic: join.topic, event: 'broadcast', payload: { event: 'changed', payload: { appId: 'pomodoist', deviceId: 'other' } } });
  assert.equal(pulls, 2);
  socket.message({ topic: join.topic, event: 'broadcast', payload: { event: 'changed', payload: { appId: 'pomodoist', deviceId: 'device' } } });
  assert.equal(pulls, 2); rt.stop(); assert.equal(socket.readyState, 3); assert.equal(live, false);
});
test('join failures are not displayed as live and schedule a bounded reconnect', async () => {
  let live = false;
  const rt = new Realtime(async () => context, () => {}, value => { live = value; }, Socket);
  rt.start(); await tick(); const socket = Socket.instances.at(-1); socket.onopen(); const join = socket.sent[0];
  socket.message({ topic: join.topic, event: 'phx_reply', ref: join.ref, payload: { status: 'error' } });
  assert.equal(live, false); assert.equal(socket.readyState, 3); assert.ok(rt.retry); rt.stop();
});
test('closing during async token retrieval cannot open an orphan socket', async () => {
  let resolve; const promise = new Promise(r => { resolve = r; });
  const count = Socket.instances.length;
  const rt = new Realtime(() => promise, () => {}, () => {}, Socket); rt.start(); rt.stop(); resolve(context); await tick();
  assert.equal(Socket.instances.length, count);
});
test('PKCE is random and uses the SHA-256 challenge, never a reusable secret', async () => {
  const a = await pkce(), b = await pkce();
  assert.notEqual(a.verifier, b.verifier); assert.equal(a.verifier.length, 43);
  assert.equal(a.challenge, Buffer.from(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(a.verifier))).toString('base64url'));
});
test('hosted CAPTCHA accepts only a nonce-bound exact Chrome identity callback', () => {
  const callback = 'https://' + 'a'.repeat(32) + '.chromiumapp.org/captcha-callback';
  const href = 'https://tasks.example.test/auth/extension-challenge.html?returnTo=' + encodeURIComponent(callback) + '#state=' + 'n'.repeat(43);
  assert.equal(parseChallenge(href).target.href, callback);
  for (const target of ['https://evil.test/captcha-callback', callback.replace('chromiumapp.org', 'chromiumapp.org.evil.test'),
    callback + '?x=1', callback.replace('https:', 'http:'), callback.replace('/captcha-callback', '/elsewhere')]) {
    assert.throws(() => parseChallenge('https://tasks.example.test/?returnTo=' + encodeURIComponent(target) + '#state=' + 'n'.repeat(43)));
  }
  assert.throws(() => parseChallenge(href + '&state=duplicate'));
});
