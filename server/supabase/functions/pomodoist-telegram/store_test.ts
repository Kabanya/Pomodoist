import assert from 'node:assert/strict';
import { createTelegramStore, type TelegramRuntime } from './store.ts';
const at = new Date('2026-09-07T12:00:00Z');
const taskId = '11111111-1111-4111-8111-111111111111';
const commandId = '22222222-2222-4222-8222-222222222222';
function fixture() {
  const mapping = { telegram_user_id: '42', user_id: 'account-42', client_id: 'client-42' };
  const queries: { table: string; filters: [string, unknown][] }[] = [];
  let rows = [{ entity_type: 'task', entity_id: taskId, server_revision: 1, deleted_at: null as null | string,
    data: { id: taskId, content: 'Original', userId: 'local-user', projectId: 'inbox', status: 'open' } as Record<string, unknown> }];
  const receipts = new Set<string>(), pushes: Record<string, any>[] = [];
  let hintFails = false, failNext = false, delegated = 0;
  const channel = { send: async () => { if (hintFails) throw new Error('hint failed'); return 'ok'; } };
  const admin = {
    from(table: string) {
      const q = { table, filters: [] as [string, unknown][] }; queries.push(q);
      const builder = { select: (_value: unknown) => builder,
        eq: (key: string, value: unknown) => { q.filters.push([key, value]); return builder; },
        is: (_key: string, _value: unknown) => builder, in: (_key: string, _value: unknown) => builder,
        gt: (_key: string, _value: unknown) => builder, order: (_value: unknown) => builder,
        limit: async (_value: number) => ({ data: rows.filter(row => !row.deleted_at), error: null }),
        maybeSingle: async () => ({ data: table === 'pomodoist_telegram_accounts' ? mapping :
          receipts.has(String(q.filters.find(([key]) => key === 'op_id')?.[1])) ? { op_id: commandId } : null, error: null }) };
      return builder;
    },
    rpc: async (name: string, args: Record<string, any>) => {
      assert.equal(name, 'push_pomodoist_telegram_changes'); pushes.push(args);
      if (failNext) { failNext = false; return { error: { message: 'temporary database failure' }, data: null }; }
      for (const op of args.p_operations) {
        receipts.add(op.opId);
        if (op.entityType !== 'task') continue;
        rows = rows.map(row => row.entity_id === op.entityId ? { ...row, server_revision: row.server_revision + 1,
          deleted_at: op.operation === 'delete' ? at.toISOString() : null, data: { ...row.data, ...op.payload } } : row);
      }
      return { error: null, data: {} };
    },
    channel: () => channel,
    removeChannel: async () => { if (hintFails) throw new Error('cleanup failed'); return 'ok'; },
  };
  const runtime = {
    pomodoistState: (entities: typeof rows) => ({ entities: entities.map(e => ({ entityType: e.entity_type, entityId: e.entity_id, serverRevision: e.server_revision, data: e.data })),
      tasks: new Map(entities.filter(e => e.entity_type === 'task').map(e => [e.entity_id, e.data])),
      projects: new Map(), labels: new Map(), focusPresets: new Map(), focusRuns: new Map(), focusIntervals: new Map(), maxRevision: 1 }),
    telegramSnapshot: () => ({ generatedAt: at.toISOString(), inbox: [], focus: null }),
    telegramCommandOps: () => { delegated++; return []; },
  } as unknown as TelegramRuntime;
  const store = createTelegramStore(admin as unknown as Parameters<typeof createTelegramStore>[0], 'https://app.example.com', runtime);
  const account = { telegramUserId: '42', userId: 'account-42', clientId: 'client-42', linked: true };
  return { store, account, queries, pushes, receipts, failHint: () => { hintFails = true; }, failPush: () => { failNext = true; }, delegated: () => delegated };
}
function unlinkFixture() {
  let mapping: Record<string, unknown> = { telegram_user_id: '42', user_id: 'account-42', guest_user_id: null, client_id: 'client-42', linked: true };
  let failRpc = false, creates = 0, deletes = 0;
  const rpcCalls: Record<string, unknown>[] = [];
  const users = new Map<string, Record<string, unknown>>();
  const admin = {
    auth: { admin: {
      createUser: async () => {
        creates++;
        const user = { id: 'guest-new-42', email: 'tg-new@telegram.invalid', app_metadata: { account_kind: 'telegram_guest' } };
        users.set(String(user.id), user);
        return { data: { user }, error: null };
      },
      getUserById: async (id: string) => ({ data: { user: users.get(id) ?? null }, error: null }),
      deleteUser: async (id: string) => { deletes++; users.delete(id); return { error: null }; },
    } },
    from(table: string) {
      const filters: [string, unknown][] = [];
      const builder = {
        select: () => builder,
        eq: (key: string, value: unknown) => { filters.push([key, value]); return builder; },
        is: () => builder,
        in: () => builder,
        gt: () => builder,
        order: () => builder,
        limit: async () => ({ data: [], error: null }),
        maybeSingle: async () => ({ data: table === 'pomodoist_telegram_accounts' ? mapping : null, error: null }),
      };
      return builder;
    },
    rpc: async (name: string, args: Record<string, unknown>) => {
      assert.equal(name, 'unlink_pomodoist_telegram');
      rpcCalls.push(args);
      if (failRpc) return { data: null, error: { message: 'temporary unlink failure' } };
      mapping = { ...mapping, user_id: 'guest-new-42', guest_user_id: 'guest-new-42', linked: false };
      return { data: mapping, error: null };
    },
    channel: () => ({ send: async () => 'ok' }),
    removeChannel: async () => 'ok',
  };
  const runtime = {
    pomodoistState: () => ({ entities: [], tasks: new Map(), projects: new Map(), labels: new Map(), focusPresets: new Map(), focusRuns: new Map(), focusIntervals: new Map(), maxRevision: 0 }),
    telegramSnapshot: () => ({ generatedAt: at.toISOString(), inbox: [], focus: null }),
    telegramCommandOps: () => [],
  } as unknown as TelegramRuntime;
  const store = createTelegramStore(admin as unknown as Parameters<typeof createTelegramStore>[0], 'https://app.example.com', runtime);
  const account = { telegramUserId: '42', userId: 'account-42', clientId: 'client-42', linked: true };
  return { store, account, rpcCalls, creates: () => creates, deletes: () => deletes, fail: () => { failRpc = true; } };
}
Deno.test('store keeps the complete edit inside the mapped account RPC and replays without a second write', async () => {
  const f = fixture(), command = { type: 'task.update', id: commandId, taskId, expectedRevision: 1, patch: { content: 'Edited' } };
  await f.store.command(f.account, command, at); await f.store.command(f.account, command, at);
  assert.equal(f.pushes.length, 1);
  assert.equal(f.pushes[0].p_expected_user_id, 'account-42');
  assert.equal(f.pushes[0].p_telegram_user_id, '42');
  assert.equal(f.pushes[0].p_operations[0].payload.content, 'Edited');
  assert.ok(f.queries.filter(q => q.table === 'sync_entities').every(q => q.filters.some(([k, v]) => k === 'user_id' && v === 'account-42')));
});
Deno.test('store keeps failed mutations retryable with the original operation id', async () => {
  const f = fixture(), command = { type: 'task.delete', id: commandId, taskId };
  f.failPush(); await assert.rejects(f.store.command(f.account, command, at), /temporary/);
  await f.store.command(f.account, command, at);
  assert.equal(f.pushes.length, 2); assert.deepEqual(f.pushes[0].p_operations, f.pushes[1].p_operations);
});
Deno.test('optional Realtime and channel cleanup failures do not turn committed edits into failures', async () => {
  const f = fixture(); f.failHint();
  await f.store.command(f.account, { type: 'task.update', id: commandId, taskId, patch: { content: 'Saved' } }, at);
  assert.ok(f.receipts.has(commandId));
});
Deno.test('store rejects stale edits without invoking push and delegates existing create logic', async () => {
  const f = fixture();
  await assert.rejects(f.store.command(f.account, { type: 'task.update', id: commandId, taskId, expectedRevision: 0, patch: { content: 'Old' } }, at), /task_changed/);
  assert.equal(f.pushes.length, 0);
  await f.store.command(f.account, { type: 'task.create', id: commandId, content: 'New' }, at);
  assert.equal(f.delegated(), 1);
});
Deno.test('mutation responses preserve the bot display time zone', async () => {
  const f = fixture();
  const result = await f.store.command(f.account, { type: 'task.update', id: commandId, taskId, patch: { content: 'Renamed' } }, at, { timeZone: 'Europe/Helsinki' });
  assert.equal((result as Record<string, unknown>).timeZone, 'Europe/Helsinki');
});
Deno.test('unlink creates one empty guest and repeated requests reuse it', async () => {
  const f = unlinkFixture();
  const first = await (f.store as any).unlinkAccount(f.account, at, { view: 'inbox', page: 0, timeZone: 'Europe/Moscow' });
  const current = await f.store.identity('42');
  const second = await (f.store as any).unlinkAccount(current, at, { view: 'inbox', page: 0, timeZone: 'Europe/Moscow' });
  assert.equal(f.creates(), 1);
  assert.equal(f.rpcCalls.length, 1);
  assert.equal(f.rpcCalls[0].p_expected_user_id, 'account-42');
  assert.equal(f.rpcCalls[0].p_guest_user_id, 'guest-new-42');
  assert.deepEqual((first as Record<string, unknown>).account, { linked: false });
  assert.deepEqual(second, first);
});
Deno.test('failed unlink deletes the unused guest and keeps the linked mapping', async () => {
  const f = unlinkFixture(); f.fail();
  await assert.rejects((f.store as any).unlinkAccount(f.account, at), /temporary unlink failure/);
  assert.equal(f.creates(), 1);
  assert.equal(f.deletes(), 1);
  assert.equal((await f.store.identity('42'))?.userId, 'account-42');
});
