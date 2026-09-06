import test from 'node:test';
import assert from 'node:assert/strict';
import { tasksFor, schedule, scheduleFields, taskOperations, tabDraft, callbackValue, recordsOf } from '../src/core.js';

const now = new Date(2026, 8, 7, 12).getTime();
const task = (id, dueJson = null, extra = {}) => ({ id, userId: 'local-user', content: id,
  projectId: 'inbox', status: 'open', dueJson, createdAt: now, updatedAt: now, orderKey: id, ...extra });
const day = date => JSON.stringify({ type: 'allDay', date });
const records = rows => Object.fromEntries(rows.map(t => [`task:${t.id}`, t]));
let seq = 0;
const uuid = () => `id-${++seq}`;

test('Today includes overdue all-day tasks without shifting calendar dates', () => {
  const r = records([task('old', day('2026-09-06')), task('today', day('2026-09-07')),
    task('future', day('2026-09-08')), task('none')]);
  assert.deepEqual(tasksFor(r, 'today', now).map(t => t.id), ['old', 'today']);
  assert.deepEqual(tasksFor(r, 'upcoming', now).map(t => t.id), ['future']);
});
test('completed/deleted tasks and archived projects are excluded', () => {
  const r = records([task('a', null, { status: 'completed' }), task('b', null, { isDeleted: true }),
    task('c', day('2026-09-07'), { projectId: 'archived' }), task('d')]);
  r['project:archived'] = { id: 'archived', isArchived: true };
  assert.deepEqual(tasksFor(r, 'inbox', now).map(t => t.id), ['d']);
  assert.deepEqual(tasksFor(r, 'completed', now).map(t => t.id), ['a']);
});
test('timed schedules are filtered by local start day', () => {
  const start = new Date(2026, 8, 7, 23, 30);
  const due = JSON.stringify({ type: 'timed', start: start.toISOString(), end: new Date(+start + 3600000).toISOString() });
  assert.equal(tasksFor(records([task('timed', due)]), 'today', now).length, 1);
});
test('date-only reschedule preserves local time, duration, timezone and recurrence', () => {
  const old = { type: 'timed', start: new Date(2026, 8, 7, 9, 15).toISOString(),
    end: new Date(2026, 8, 7, 10, 45).toISOString(), timeZone: 'Europe/Amsterdam',
    recurrence: { unit: 'week', interval: 1, seriesId: 'series' } };
  const next = schedule('2026-09-09', undefined, undefined, JSON.stringify(old));
  const s = JSON.parse(next);
  assert.equal(new Date(s.start).getDate(), 9);
  assert.equal(new Date(s.start).getHours(), 9);
  assert.equal(new Date(s.start).getMinutes(), 15);
  assert.equal(Date.parse(s.end) - Date.parse(s.start), 90 * 60000);
  assert.deepEqual(s.recurrence, old.recurrence);
  assert.equal(s.timeZone, old.timeZone);
});
test('all-day, unschedule and invalid dates are explicit', () => {
  assert.deepEqual(JSON.parse(schedule('2026-09-08', '', 30, null)), { type: 'allDay', date: '2026-09-08' });
  assert.equal(schedule('', '', 30, null), null);
  assert.throws(() => schedule('2026-02-30', '', 30, null));
  assert.throws(() => schedule('2026-09-08', '24:00', 30, null));
  assert.throws(() => schedule('2026-09-08', '09:00', 0, null));
});
test('schedule editor round-trips the existing timed schedule', () => {
  const due = schedule('2026-09-08', '09:20', 75, null);
  const f = scheduleFields(due);
  assert.equal(f.date, '2026-09-08'); assert.equal(f.time, '09:20'); assert.equal(f.minutes, 75);
});
test('rename emits only changed fields, not stale scheduling/project/status data', () => {
  const r = records([task('a', day('2026-09-07'))]);
  const [op] = taskOperations(r, { kind: 'edit', id: 'a', patch: { content: ' Renamed ' } }, now, uuid);
  assert.deepEqual(op.payload, { schemaVersion: 1, commandType: 'task.update', id: 'a', content: 'Renamed', updatedAt: now });
  assert.equal(op.clientUpdatedAt, new Date(now).toISOString());
  assert.throws(() => taskOperations(r, { kind: 'edit', id: 'a', patch: { userId: 'other' } }, now, uuid));
});
test('create and schedule use the same schema as the Flutter sync client', () => {
  const ops = taskOperations({}, { kind: 'create', content: 'Test', dueJson: day('2026-09-09') }, now, uuid);
  const op = ops.find(o => o.entityType === 'task');
  assert.equal(op.payload.projectId, 'inbox'); assert.equal(op.payload.status, 'open');
  assert.equal(op.payload.priority, 4); assert.equal(op.payload.dueJson, day('2026-09-09'));
  assert.ok(ops.some(o => o.entityType === 'task_kanban_status'));
});
test('completion includes descendants, history and Done assignment without erasing due', () => {
  const r = records([task('root'), task('child', null, { parentId: 'root' }),
    task('already', null, { parentId: 'root', status: 'completed' }), task('other')]);
  const ops = taskOperations(r, { kind: 'complete', id: 'root' }, now, uuid);
  assert.deepEqual(ops.filter(o => o.entityType === 'task').map(o => o.entityId), ['root', 'child']);
  assert.equal(ops.filter(o => o.entityType === 'task_completion').length, 2);
  assert.equal(ops.filter(o => o.entityType === 'task_kanban_status').length, 2);
  assert.ok(ops.filter(o => o.entityType === 'task').every(o => !Object.hasOwn(o.payload, 'dueJson')));
});
test('restoring completion recovers previous workflow status from completion snapshot', () => {
  const r = records([task('a', null, { status: 'completed' })]);
  r['label:work'] = { id: 'work', kind: 'kanbanStatus', systemKey: 'inProgress' };
  r['task_completion:c'] = { id: 'c', taskId: 'a', completedAt: now,
    snapshotJson: JSON.stringify({ version: 1, kanban: { previousStatusLabelId: 'work' } }) };
  const ops = taskOperations(r, { kind: 'uncomplete', id: 'a' }, now, uuid);
  assert.equal(ops.find(o => o.entityType === 'task_kanban_status').payload.labelId, 'work');
  assert.equal(ops.find(o => o.entityType === 'task').payload.completedAt, null);
});
test('unknown/deleted task cannot be resurrected by edit or completion', () => {
  assert.throws(() => taskOperations({}, { kind: 'edit', id: 'missing', patch: { content: 'x' } }, now, uuid));
  assert.throws(() => taskOperations(records([task('a', null, { isDeleted: true })]), { kind: 'complete', id: 'a' }, now, uuid));
});
test('tab import rejects privileged URLs and credentials; title remains plain text', () => {
  assert.deepEqual(tabDraft({ title: '<img src=x>', url: 'https://example.com/a' }), { content: '<img src=x>', description: 'https://example.com/a' });
  for (const url of ['chrome://settings', 'file:///etc/passwd', 'javascript:alert(1)', 'https://u:p@example.com/']) {
    assert.throws(() => tabDraft({ title: 'x', url }));
  }
});
test('identity callbacks validate exact origin/path/state and reject duplicates', () => {
  const base = 'https://' + 'a'.repeat(32) + '.chromiumapp.org/auth-callback';
  assert.equal(callbackValue(`${base}?state=nonce&code=abc`, base, 'nonce', 'code'), 'abc');
  for (const url of [`${base}?state=wrong&code=abc`, `${base}?state=nonce&code=a&code=b`,
    `${base}/evil?state=nonce&code=abc`, `https://evil.test/auth-callback?state=nonce&code=abc`, `${base}?state=nonce&code=abc#access_token=bad`]) {
    assert.throws(() => callbackValue(url, base, 'nonce', 'code'));
  }
});
test('recordsOf excludes tombstones', () => {
  assert.equal(recordsOf(records([task('a'), task('b', null, { isDeleted: true })]), 'task').length, 1);
});
test('removing a repeating schedule requires the full app instead of silently dropping the rule', () => {
  assert.throws(() => schedule('', '', 30, JSON.stringify({ type: 'allDay', date: '2026-09-07', recurrence: { unit: 'day' } })), /repeating/i);
});
test('an oversized page URL is rejected, not truncated into another link', () => {
  assert.throws(() => tabDraft({ title: 'Page', url: 'https://example.test/?q=' + 'a'.repeat(8200) }), /long/i);
});
