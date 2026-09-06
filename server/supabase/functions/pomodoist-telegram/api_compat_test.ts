import assert from 'node:assert/strict';
import { handlePomodoistTelegram, verifyTelegramInitData } from './pomodoist_telegram.ts';
const now = new Date('2026-09-07T12:00:00Z'), token = '123:TEST';
async function signed(userId = 42, at = now) {
  const p = new URLSearchParams({ auth_date: String(+at / 1000), user: JSON.stringify({ id: userId }), query_id: 'test' });
  const bytes = (s: string) => new TextEncoder().encode(s);
  const hmac = async (key: BufferSource, data: BufferSource) => crypto.subtle.sign('HMAC', await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']), data);
  const secret = await hmac(bytes('WebAppData'), bytes(token));
  const hash = await hmac(secret, bytes([...p].sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${k}=${v}`).join('\n')));
  p.set('hash', [...new Uint8Array(hash)].map(n => n.toString(16).padStart(2, '0')).join('')); return p.toString();
}
function fixture() {
  const identities = new Map(); const calls: string[] = [];
  const store = { identity: async (id: string) => identities.get(id) ?? null,
    bootstrap: async (id: string) => { if (!identities.has(id)) identities.set(id, { telegramUserId: id, userId: `guest-${id}`, clientId: 'client', linked: false }); return identities.get(id); },
    snapshot: async (i: { userId: string }) => { calls.push(i.userId); return { inbox: [], focus: null, account: { linked: false } }; },
    command: async () => ({}), beginLink: async () => ({}), completeLink: async () => ({ linked: true }) };
  return { store, identities, calls, deps: { botToken: token, allowedOrigin: 'https://app.example.com', store, now: () => now } };
}
async function request(body: unknown, user = 42) { return new Request('https://api.example.com/functions/v1/pomodoist-telegram', { method: 'POST',
  headers: { Origin: 'https://app.example.com', 'X-Telegram-Init-Data': await signed(user) }, body: JSON.stringify(body) }); }
Deno.test('existing signed Mini App API still bootstraps and isolates users', async () => {
  const f = fixture();
  for (const id of [42, 42, 43]) assert.equal((await handlePomodoistTelegram(await request({ action: 'snapshot' }, id), f.deps)).status, 200);
  assert.equal(f.identities.size, 2); assert.deepEqual(f.calls, ['guest-42', 'guest-42', 'guest-43']);
});
Deno.test('Mini App initData signature, expiration and duplicate fields are checked', async () => {
  assert.equal((await verifyTelegramInitData(await signed(), token, now)).userId, '42');
  await assert.rejects(verifyTelegramInitData(await signed(), 'other', now), /invalid_init_data/);
  await assert.rejects(verifyTelegramInitData(await signed(42, new Date(+now - 3601000)), token, now), /expired_init_data/);
  await assert.rejects(verifyTelegramInitData(`${await signed()}&auth_date=1`, token, now), /invalid_init_data/);
});
Deno.test('Mini App cannot bypass origin checks by adding the bot webhook header', async () => {
  const f = fixture(), r = await request({ action: 'snapshot' }); r.headers.set('Origin', 'https://evil.example'); r.headers.set('X-Telegram-Bot-Api-Secret-Token', 'fake');
  assert.equal((await handlePomodoistTelegram(r, f.deps)).status, 403); assert.equal(f.identities.size, 0);
});
Deno.test('transient Mini App failures stay retryable to preserve the durable outbox', async () => {
  const f = fixture(); f.store.command = async () => { throw new Error('database temporarily unavailable'); };
  const response = await handlePomodoistTelegram(await request({ action: 'command', command: { type: 'task.create', id: '11111111-1111-4111-8111-111111111111', content: 'Task' } }), f.deps);
  assert.equal(response.status, 503); assert.equal((await response.json()).code, 'request_failed');
});
Deno.test('invalid edits are rejected before reaching the store', async () => {
  const f = fixture(); let called = false; f.store.command = async () => { called = true; return {}; };
  const response = await handlePomodoistTelegram(await request({ action: 'command', command: { type: 'task.update', id: '11111111-1111-4111-8111-111111111111', taskId: '11111111-1111-4111-8111-111111111111', patch: { userId: 'other' } } }), f.deps);
  assert.equal(response.status, 400); assert.equal(called, false);
});
Deno.test('existing authenticated account-link endpoint remains usable without initData', async () => {
  const f = fixture(); const response = await handlePomodoistTelegram(new Request('https://api.example.com/functions/v1/pomodoist-telegram', { method: 'POST',
    headers: { Origin: f.deps.allowedOrigin, Authorization: 'Bearer token' }, body: JSON.stringify({ action: 'complete_link', token: 'opaque' }) }), f.deps);
  assert.equal(response.status, 200);
});
