import { APP_ID, cachedTypes, keyOf, optimisticRecords, taskOperations } from './core.js';
const STORAGE_KEY = 'pomodoist-extension-v1';
const fresh = instance => ({ version: 1, instance, deviceId: crypto.randomUUID(), owner: null,
  session: null, records: {}, cursor: 0, outbox: [], overview: null, overviewAt: 0, lastSyncedAt: 0, error: '' });

// All writes run through the service worker's serial queue. One storage item
// commits the outbox, cache and cursor together, including after worker restarts.
export class Store {
  constructor(storage, instance) { this.storage = storage; this.instance = instance; }
  async init() {
    const saved = (await this.storage.get(STORAGE_KEY))[STORAGE_KEY];
    this.data = saved?.version === 1 && saved.instance === this.instance ? saved : fresh(this.instance);
    if (this.data !== saved) await this.storage.set({ [STORAGE_KEY]: this.data });
  }
  async save(patch) {
    const next = { ...this.data, ...patch };
    await this.storage.set({ [STORAGE_KEY]: next });
    this.data = next;
  }
  async acceptSession(session) {
    if (!session?.user?.id || !session.access_token || !session.refresh_token || !Number.isFinite(session.expires_at)) {
      throw new Error('The server returned an invalid session.');
    }
    const owner = session.user.id;
    if (this.data.owner !== owner && this.data.outbox.length) throw new Error('Unsynced tasks belong to another account. Sign out explicitly to discard them first.');
    const state = this.data.owner === owner ? this.data : fresh(this.instance);
    await this.save({ ...state, session, owner, error: '' });
  }
  async logout(discardPending = false) {
    if (this.data.outbox.length && !discardPending) throw new Error('Unsynced changes remain. Sync first or confirm discarding them.');
    await this.save(fresh(this.instance));
  }
  snapshot() {
    const session = this.data.session;
    return { user: session ? { id: this.data.owner, email: session.user.email ?? '' } : null,
      records: session ? optimisticRecords(this.data.records, this.data.outbox) : {},
      pending: this.data.outbox.length, overview: session ? this.data.overview : null,
      overviewAt: this.data.overviewAt, lastSyncedAt: this.data.lastSyncedAt, error: this.data.error };
  }
  async enqueue(action, expectedOwner) {
    if (!this.data.session || expectedOwner !== this.data.owner) throw new Error('Account changed. Reopen the extension before editing.');
    const operations = taskOperations(this.snapshot().records, action);
    if (this.data.outbox.length + operations.length > 5000) throw new Error('Too many pending changes. Sync before adding more.');
    await this.save({ outbox: [...this.data.outbox, ...operations], error: '' });
  }
}
function apply(records, changes) {
  const next = { ...records };
  for (const entity of changes) {
    const type = entity.entityType ?? entity.entity_type;
    const id = entity.entityId ?? entity.entity_id;
    if (typeof type !== 'string' || typeof id !== 'string' || !id) throw new Error('Invalid sync response.');
    if (!cachedTypes.has(type)) continue;
    if (entity.deletedAt ?? entity.deleted_at) next[keyOf(type, id)] = { id, isDeleted: true };
    else {
      if (!entity.data || typeof entity.data !== 'object' || Array.isArray(entity.data)) throw new Error('Invalid sync response.');
      next[keyOf(type, id)] = { ...entity.data, id };
    }
  }
  return next;
}
export async function synchronize(store, client, changed = () => {}) {
  if (!store.data.session) return;
  try {
    let pushed = false;
    // Limits are per activation; subsequent syncs resume from the durable cursor.
    for (let batch = 0; store.data.outbox.length && batch < 50; batch++) {
      const operations = store.data.outbox.slice(0, 100);
      const result = await client.rpc('push_changes', { p_app_id: APP_ID,
        p_device_id: store.data.deviceId, p_operations: operations });
      if (!result || !Array.isArray(result.applied) || !Number.isSafeInteger(Number(result.serverRevision ?? result.server_revision))) {
        throw new Error('Invalid push response. Pending changes were kept.');
      }
      const acknowledged = new Set(operations.map(op => op.opId));
      await store.save({ records: apply(store.data.records, result.applied),
        outbox: store.data.outbox.filter(op => !acknowledged.has(op.opId)) });
      // Never use the push revision as the pull cursor: it skips other devices.
      pushed = true; changed();
    }
    let resets = 0;
    for (let page = 0; ; page++) {
      if (page >= 50) throw new Error('More history is available. Press Refresh to continue syncing.');
      const since = store.data.cursor;
      const result = await client.rpc('pull_changes', { p_app_id: APP_ID,
        p_device_id: store.data.deviceId, p_since_revision: since, p_limit: 500 });
      const cursor = Number(result?.nextCursor ?? result?.next_cursor);
      const hasMore = result?.hasMore ?? result?.has_more;
      if (!Number.isSafeInteger(cursor) || cursor < 0 || typeof hasMore !== 'boolean' || !Array.isArray(result?.changes)) {
        throw new Error('Invalid pull response. Cached changes were kept.');
      }
      if (cursor < since) {
        if (++resets > 1) throw new Error('Server cursor keeps resetting. Retry later.');
        await store.save({ records: {}, cursor: 0 });
        continue;
      }
      if (hasMore && cursor <= since) throw new Error('Server cursor did not advance. Retry later.');
      await store.save({ records: apply(store.data.records, result.changes), cursor });
      changed();
      if (!hasMore) break;
    }
    if (pushed) {
      try { await client.broadcast(); } catch { /* Durable sync succeeded; a hint is only an accelerator. */ }
    }
    if (Date.now() - store.data.overviewAt > 60000) {
      try { await store.save({ overview: await client.overview(), overviewAt: Date.now() }); }
      catch (error) {
        if (!store.data.session) throw error;
        // Keep the prior overview's timestamp; the popup labels stale status.
      }
    }
    await store.save({ error: '', lastSyncedAt: Date.now() });
    changed();
  } catch (error) {
    await store.save({ error: error.message || 'Sync failed. Retry when online.' });
    changed();
    throw error;
  }
}
