import test from 'node:test';
import assert from 'node:assert/strict';
import { canonicalJson, captureMutation, runGuardedAction } from '../server/supabase/functions/pomodoist-mcp/openclaw_actions.ts';
const id = '4c338dd6-1a1b-4e1f-a1d3-cf9a8913b835';
const identity = { subject: id, sessionId: id, clientId: id };
const action = { requestId: id, name: 'create_task', arguments: { content: 'One task' } };
const op = { opId: id, entityType: 'task', entityId: 'task-1', operation: 'upsert', payload: { content: 'One task' }, clientUpdatedAt: '2026-09-07T01:00:00Z' };

test('canonical JSON is independent of object key order but preserves array order', () => {
  assert.equal(canonicalJson({ b: [1, 2], a: { z: true, a: null } }), '{"a":{"a":null,"z":true},"b":[1,2]}');
  assert.notEqual(canonicalJson([1, 2]), canonicalJson([2, 1]));
  assert.throws(() => canonicalJson({ value: NaN }));
});
test('legacy mutation is planned without sending any write or hint', async () => {
  const requests = [];
  const plan = await captureMutation('https://backend.example', async input => {
    requests.push(String(input)); return Response.json({ tasks: [] });
  }, async fetcher => {
    await fetcher('https://backend.example/rest/v1/rpc/read_pomodoist_mcp', { method: 'POST', body: '{}' });
    await fetcher('https://backend.example/rest/v1/rpc/push_pomodoist_mcp_changes', { method: 'POST', body: JSON.stringify({ p_operations: [op] }) });
    await fetcher('https://backend.example/rest/v1/rpc/send_pomodoist_mcp_sync_hint', { method: 'POST', body: '{}' });
    return { structuredContent: { ok: true, data: { id: 'task-1', server_revision: null } } };
  });
  assert.deepEqual(requests, ['https://backend.example/rest/v1/rpc/read_pomodoist_mcp']);
  assert.deepEqual(plan, { operations: [op], result: { id: 'task-1', server_revision: null } });
});
test('unrecognized writes fail closed', async () => {
  await assert.rejects(captureMutation('https://backend.example', () => { throw Error('Must not reach network'); }, async fetcher => {
    await fetcher('https://backend.example/rest/v1/rpc/other_write', { method: 'POST' });
  }), /Unexpected/);
});
test('legacy validation errors are preserved and never committed', async () => {
  await assert.rejects(captureMutation('https://backend.example', fetch, async () => ({
    isError: true, structuredContent: { ok: false, error: { code: 'not_found', message: 'Task not found.' } },
  })), error => error.code === 'not_found');
});
test('prepare precedes planning and commit carries the original revision and hash', async () => {
  const stages = [];
  const result = await runGuardedAction(identity, action, async args => {
    if (args.p_operations === undefined) { stages.push('prepare'); return { revision: '9007199254740993' }; }
    stages.push('commit');
    assert.equal(args.p_expected_revision, '9007199254740993');
    assert.match(args.p_arguments_hash, /^[a-f0-9]{64}$/);
    assert.deepEqual(args.p_operations, [op]);
    assert.equal(args.p_subject, id);
    return { id: 'task-1', server_revision: '9007199254740994' };
  }, async () => { stages.push('plan'); return { operations: [op], result: { id: 'task-1' } }; });
  assert.deepEqual(stages, ['prepare', 'plan', 'commit']);
  assert.equal(result.server_revision, '9007199254740994');
});
test('durable replay returns the committed result without invoking the planner', async () => {
  const saved = { id: 'original-id', server_revision: '42' };
  const result = await runGuardedAction(identity, action, async () => ({ revision: '55', result: saved }),
    async () => { throw Error('Duplicate plan'); });
  assert.deepEqual(result, saved);
});
test('failed planning does not issue commit', async () => {
  let calls = 0;
  await assert.rejects(runGuardedAction(identity, action, async () => { calls++; return { revision: '1' }; },
    async () => { throw Error('Task not found'); }), /Task not found/);
  assert.equal(calls, 1);
});
test('ambiguous commit failures are not automatically retried', async () => {
  let commits = 0;
  await assert.rejects(runGuardedAction(identity, action, async args => {
    if (!args.p_operations) return { revision: '1' };
    commits++; throw Error('Response lost after commit');
  }, async () => ({ operations: [op], result: { id: 'task-1' } })), /Response lost/);
  assert.equal(commits, 1);
});
