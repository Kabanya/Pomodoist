import test from 'node:test';
import assert from 'node:assert/strict';
import { Store, synchronize } from '../src/sync.js';
import { Client } from '../src/client.js';

const session = (id = 'user-a') => ({ user: { id, email: `${id}@example.test` }, access_token: 'access', refresh_token: 'refresh', expires_at: Date.now() / 1000 + 3600 });
function storage() {
  let data = {};
  return { async get(key) { return { [key]: structuredClone(data[key]) }; },
    async set(value) { data = structuredClone({ ...data, ...value }); } };
}
async function setup() {
  const disk = storage(), store = new Store(disk, 'https://api.example.test');
  await store.init(); await store.acceptSession(session()); return { disk, store };
}
const pull = (changes = [], nextCursor = 0, hasMore = false) => ({ changes, nextCursor, hasMore });
const change = (id, serverRevision, extra = {}) => ({ entityType: 'task', entityId: id, serverRevision,
  data: { id, content: id, projectId: 'inbox', status: 'open', ...extra } });
const api = handler => ({ rpc: handler, broadcast: async () => {}, overview: async () => ({ profile: { pomodoistIsPro: true } }) });

test('outbox is durable before network and stable across worker restarts', async () => {
  const { disk, store } = await setup();
  await store.enqueue({ kind: 'create', content: 'Offline task' }, 'user-a');
  const ids = store.data.outbox.map(o => o.opId);
  await assert.rejects(synchronize(store, api(async () => { throw new Error('Offline'); })));
  const restarted = new Store(disk, 'https://api.example.test'); await restarted.init();
  assert.deepEqual(restarted.data.outbox.map(o => o.opId), ids);
  assert.equal(Object.values(restarted.snapshot().records).filter(r => r.content === 'Offline task').length, 1);
});
test('push ack never advances pull cursor past concurrent remote changes', async () => {
  const { store } = await setup(); await store.enqueue({ kind: 'create', content: 'Local' }, 'user-a');
  let since;
  await synchronize(store, api(async (name, body) => {
    if (name === 'push_changes') return { serverRevision: 100, applied: [] };
    since = body.p_since_revision; return pull([change('remote', 10)], 100);
  }));
  assert.equal(since, 0); assert.equal(store.data.cursor, 100); assert.equal(store.data.records['task:remote'].content, 'remote');
  assert.equal(store.data.outbox.length, 0);
});
test('pagination persists records and cursor together and resumes after a failed page', async () => {
  const { disk, store } = await setup();
  await assert.rejects(synchronize(store, api(async (_, body) => {
    if (body.p_since_revision === 0) return pull([change('first', 1)], 1, true);
    throw new Error('Second page failed');
  })));
  const resumed = new Store(disk, 'https://api.example.test'); await resumed.init();
  assert.equal(resumed.data.cursor, 1); assert.ok(resumed.data.records['task:first']);
  await synchronize(resumed, api(async (_, body) => {
    assert.equal(body.p_since_revision, 1); return pull([change('second', 2)], 2);
  }));
  assert.ok(resumed.data.records['task:second']);
});
test('server cursor reset rebuilds cache rather than resurrecting removed tasks', async () => {
  const { store } = await setup();
  await store.save({ cursor: 10, records: { 'task:old': { id: 'old' } } });
  let calls = 0;
  await synchronize(store, api(async (_, body) => {
    if (++calls === 1) { assert.equal(body.p_since_revision, 10); return pull([], 0); }
    assert.equal(body.p_since_revision, 0); return pull([change('new', 1)], 1);
  }));
  assert.equal(store.data.records['task:old'], undefined); assert.ok(store.data.records['task:new']);
});
test('tombstones remove tasks from visible cache, and pagination cannot spin', async () => {
  const { store } = await setup();
  await synchronize(store, api(async () => pull([{ ...change('gone', 1), deletedAt: new Date().toISOString() }], 1)));
  assert.equal(store.snapshot().records['task:gone'].isDeleted, true);
  await assert.rejects(synchronize(store, api(async () => pull([], 1, true))), /cursor/i);
});
test('logout/account switch clear credentials, cache and pending writes without cross-account replay', async () => {
  const { store } = await setup(); await store.enqueue({ kind: 'create', content: 'Private' }, 'user-a');
  await assert.rejects(store.acceptSession(session('user-b')), /unsynced/i);
  await assert.rejects(store.logout(false), /unsynced/i);
  await store.logout(true); await store.acceptSession(session('user-b'));
  assert.deepEqual(store.data.records, {}); assert.equal(store.data.outbox.length, 0);
  await assert.rejects(store.enqueue({ kind: 'create', content: 'Old view' }, 'user-a'), /account/i);
});
test('failed persistence does not mutate in-memory state or pretend a task was saved', async () => {
  const { store } = await setup(); const before = structuredClone(store.data);
  store.storage.set = async () => { throw new Error('Storage full'); };
  await assert.rejects(store.enqueue({ kind: 'create', content: 'Lost' }, 'user-a'));
  assert.deepEqual(store.data, before);
});
test('malformed push ack leaves pending operations intact', async () => {
  const { store } = await setup(); await store.enqueue({ kind: 'create', content: 'Keep' }, 'user-a');
  await assert.rejects(synchronize(store, api(async () => ({}))), /response/i);
  assert.equal(store.data.outbox.length, 2);
});
test('backend changes cannot reuse an old instance session or cache', async () => {
  const { disk, store } = await setup(); await store.enqueue({ kind: 'create', content: 'Private' }, 'user-a');
  const different = new Store(disk, 'https://other.example.test'); await different.init();
  assert.equal(different.data.session, null); assert.deepEqual(different.data.records, {});
});
const response = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const config = { apiUrl: 'https://api.example.test', anonKey: 'sb_publishable_test' };
test('simultaneous requests rotate the refresh token once and persist it before continuing', async () => {
  const { store } = await setup(); await store.save({ session: { ...session(), expires_at: 1 } });
  let refreshes = 0;
  const client = new Client(config, store, async (url, options) => {
    assert.equal(options.redirect, 'error'); assert.equal(options.credentials, 'omit');
    if (url.includes('grant_type=refresh_token')) { refreshes++; return response({ ...session(), refresh_token: 'rotated' }); }
    assert.equal(store.data.session.refresh_token, 'rotated'); return response({ profile: {} });
  });
  await Promise.all([client.overview(), client.overview()]); assert.equal(refreshes, 1);
});
test('401 retries once with a refreshed token, not an unbounded loop', async () => {
  const { store } = await setup(); let rpcs = 0, refreshes = 0;
  const client = new Client(config, store, async url => {
    if (url.includes('refresh_token')) { refreshes++; return response(session()); }
    rpcs++; return response({}, 401);
  });
  await assert.rejects(client.overview()); assert.equal(rpcs, 2); assert.equal(refreshes, 1);
});
test('expired session hides cached tasks but preserves same-owner unsynced changes for reauthentication', async () => {
  const { store } = await setup(); await store.enqueue({ kind: 'create', content: 'Private' }, 'user-a');
  await store.save({ session: { ...session(), expires_at: 1 } });
  const client = new Client(config, store, async () => response({ error: 'invalid_grant' }, 400));
  await assert.rejects(client.overview()); assert.equal(store.snapshot().user, null);
  assert.deepEqual(store.snapshot().records, {});
  await store.acceptSession(session()); assert.equal(store.data.outbox.length, 2);
});
test('auth errors never echo the raw server body or credentials', async () => {
  const { store } = await setup();
  const client = new Client(config, store, async () => response({ error_description: 'PASSWORD_SECRET' }, 400));
  await assert.rejects(client.password('a@example.test', 'PASSWORD_SECRET'), err => !err.message.includes('PASSWORD_SECRET'));
});
test('a committed push whose response was lost is retried with the same operation IDs', async () => {
  const { store } = await setup(); await store.enqueue({ kind: 'create', content: 'Exactly once' }, 'user-a');
  let first = true, original; const received = new Set(), applied = [];
  const client = api(async (name, body) => {
    if (name === 'pull_changes') return pull(applied, 2);
    const ids = body.p_operations.map(op => op.opId);
    if (!original) original = ids; else assert.deepEqual(ids, original);
    for (const op of body.p_operations) if (!received.has(op.opId)) {
      received.add(op.opId); applied.push({ entityType: op.entityType, entityId: op.entityId, data: op.payload });
    }
    if (first) { first = false; throw new Error('Response lost after commit'); }
    return { serverRevision: 2, applied };
  });
  await assert.rejects(synchronize(store, client));
  await synchronize(store, client);
  assert.equal(received.size, 2); assert.equal(store.data.outbox.length, 0);
  assert.equal(Object.keys(store.data.records).filter(key => key.startsWith('task:')).length, 1);
});
