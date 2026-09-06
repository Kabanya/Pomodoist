import assert from 'node:assert/strict';
import { validateCommand, taskOperations, taskPage, snapshotOptions, stableUuid } from './commands.ts';
const test = Deno.test;
const id = '11111111-1111-4111-8111-111111111111';
const child = '22222222-2222-4222-8222-222222222222';
const commandId = '33333333-3333-4333-8333-333333333333';
const now = new Date('2026-09-07T10:00:00Z');
function state(rows: Record<string, unknown>[] = []) {
  return { tasks: new Map(rows.map(row => [String(row.id), row])), projects: new Map(),
    focusRuns: new Map(), focusIntervals: new Map(), entities: rows.map(row => ({ entityType: 'task', entityId: String(row.id), serverRevision: 7, data: row })) };
}
const task = { id, content: 'Read', description: 'Keep me', status: 'open', projectId: 'inbox', updatedAt: '2026-09-06T00:00:00Z' };
function command(type: string, extra: Record<string, unknown> = {}) { return { type, id: commandId, taskId: id, ...extra }; }
test('update is a captured patch, not a stale full row', () => {
  const [op] = taskOperations(state([task]), command('task.update', { patch: { content: 'Edited' } }), now)!;
  assert.equal(op.payload.content, 'Edited'); assert.equal(op.payload.schemaVersion, 1);
  assert.equal('description' in op.payload, false); assert.equal(op.opId, commandId);
});
test('delete tombstones the entire subtree atomically with stable receipt ids', () => {
  const rows = [task, { ...task, id: child, parentId: id }];
  const a = taskOperations(state(rows), command('task.delete'), now)!;
  const b = taskOperations(state(rows), command('task.delete'), now)!;
  assert.deepEqual(a, b); assert.equal(a.length, 2); assert.ok(a.every(op => op.operation === 'delete'));
});
test('completion includes descendants and completion receipts without copying unrelated fields', () => {
  const ops = taskOperations(state([task, { ...task, id: child, parentId: id }]), command('task.complete'), now)!;
  assert.equal(ops.length, 4); assert.equal(ops.filter(op => op.entityType === 'task_completion').length, 2);
  assert.equal(ops[0].payload.status, 'completed'); assert.equal('content' in ops[0].payload, false);
});
test('already completed tasks are no-ops', () => assert.deepEqual(taskOperations(state([{ ...task, status: 'completed' }]), command('task.complete'), now), []));
test('cross-account and deleted task ids cannot be mutated', () => {
  assert.throws(() => taskOperations(state([]), command('task.update', { patch: { content: 'x' } }), now), /task_not_found/);
  assert.throws(() => taskOperations(state([{ ...task, isDeleted: true }]), command('task.delete'), now), /task_not_found/);
});
test('stale revisions cannot overwrite a newer edit', () => assert.throws(() => taskOperations(state([task]), command('task.update', { expectedRevision: 6, patch: { content: 'x' } }), now), /task_changed/));
test('rejects ownership, structure and unsupported patch fields', () => {
  for (const patch of [{ userId: 'other' }, { projectId: 'other' }, { content: '' }, { priority: 9 }, { content: 'x'.repeat(2001) }])
    assert.throws(() => validateCommand(command('task.update', { patch })));
});
test('validates real calendar dates and timed durations', () => {
  for (const due of [{ type: 'allDay', date: '2026-02-30' }, { type: 'timed', start: '2026-09-07T10:00:00Z', end: '2026-09-07T09:00:00Z' }])
    assert.throws(() => validateCommand(command('task.update', { patch: { dueJson: JSON.stringify(due) } })));
});
test('schedule edits update duration and preserve recurrence metadata', () => {
  const recurrence = { frequency: 'daily', interval: 1, seriesId: id };
  const ops = taskOperations(state([{ ...task, dueJson: JSON.stringify({ type: 'allDay', date: '2026-09-07', recurrence }) }]), command('task.update', { patch: { dueJson: JSON.stringify({ type: 'allDay', date: '2026-09-08' }) } }), now)!;
  assert.deepEqual(JSON.parse(String(ops[0].payload.dueJson)).recurrence, recurrence); assert.equal(ops[0].payload.durationSeconds, null);
});
test('recurring deletion is rejected instead of silently ending a series', () => assert.throws(() => taskOperations(state([{ ...task, dueJson: JSON.stringify({ type: 'allDay', date: '2026-09-07', recurrence: {} }) }]), command('task.delete'), now), /recurring_task_requires_app/));
test('rejects batches larger than the existing RPC limit without partial deletion', () => {
  const rows = [task, ...Array.from({ length: 50 }, (_, n) => ({ ...task, id: `child${n}`, parentId: id }))];
  assert.throws(() => taskOperations(state(rows), command('task.delete'), now), /task_batch_too_large/);
});
test('cannot delete a task associated with active Focus', () => {
  const s = state([task]); s.focusRuns.set('run', { id: 'run', taskId: id, status: 'active' });
  assert.throws(() => taskOperations(s, command('task.delete'), now), /task_has_active_focus/);
});
test('Today includes overdue and respects the requested IANA timezone', () => {
  const s = state([{ ...task, dueJson: JSON.stringify({ type: 'timed', start: '2026-09-07T23:30:00Z', end: '2026-09-08T00:00:00Z' }) }]);
  assert.equal(taskPage(s, new Date('2026-09-07T20:00:00Z'), { view: 'today', timeZone: 'Europe/Helsinki' }).total, 0);
  assert.equal(taskPage(s, new Date('2026-09-08T04:00:00Z'), { view: 'today', timeZone: 'Europe/Helsinki' }).total, 1);
});
test('task lists are paginated and hide archived projects', () => {
  const s = state(Array.from({ length: 15 }, (_, n) => ({ ...task, id: String(n) })));
  assert.equal(taskPage(s, now, { view: 'inbox', page: 1 }).tasks.length, 6);
  assert.equal(taskPage(s, now, { view: 'inbox', page: 99 }).page, 2);
  s.projects.set('inbox', { isArchived: true }); assert.equal(taskPage(s, now, {}).total, 0);
});
test('snapshot parameters fail closed on invalid zones and page numbers', () => {
  assert.throws(() => snapshotOptions({ timeZone: 'Not/AZone' }));
  assert.throws(() => snapshotOptions({ page: -1 }));
  assert.throws(() => snapshotOptions({ view: 'everything-secret' }));
});
test('stable action ids are valid deterministic UUIDs', async () => {
  const a = await stableUuid('telegram:42:100'); assert.equal(a, await stableUuid('telegram:42:100'));
  assert.notEqual(a, await stableUuid('telegram:43:100'));
  assert.match(a, /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

test('timed schedules reject normalized invalid calendar dates', () => {
  assert.throws(() => validateCommand({ type: 'task.update', id: commandId, taskId: id,
    patch: { dueJson: JSON.stringify({ type: 'timed', start: '2026-02-30T10:00:00Z', end: '2026-03-03T10:00:00Z' }) } }), /invalid_task_schedule/);
});
