import assert from 'node:assert/strict';
import { copy, launcher } from './bot_ui.ts';
import { taskPage, type JsonMap, type State } from './commands.ts';
const test = Deno.test;
const id = '11111111-1111-4111-8111-111111111111';
const now = new Date('2026-09-07T12:00:00Z');
const task = { id, content: 'Task', status: 'open', projectId: 'inbox' };
function state(rows: JsonMap[]): State {
  return { tasks: new Map(rows.map(row => [String(row.id), row])), projects: new Map(), focusRuns: new Map(), focusIntervals: new Map(),
    entities: rows.map(row => ({ entityType: 'task', entityId: String(row.id), serverRevision: 4, data: row })) };
}
test('snapshot exposes read-only metadata without changing date filtering', () => {
  const s = state([{ ...task, deadlineJson: '{"type":"date","date":"2026-09-07"}', projectId: 'release' }]);
  s.projects.set('release', { name: 'Release' });
  const data = taskPage(s, now, { taskId: id, timeZone: 'Europe/Helsinki', view: 'today' });
  assert.equal(data.total, 0); // A deadline is not a scheduled date.
  assert.equal((data.task as JsonMap).deadlineJson, s.tasks.get(id)!.deadlineJson);
  assert.equal((data.task as JsonMap).projectName, 'Release'); assert.equal((data.task as JsonMap).timeZone, 'Europe/Helsinki');
});
test('active focus task is available even outside the current list page', () => {
  const s = state([{ ...task, projectId: 'another-project' }]);
  s.focusRuns.set('run', { id: 'run', taskId: id, status: 'active' });
  const data = taskPage(s, now, {}) as JsonMap;
  assert.equal((data.focusTask as JsonMap)?.id, id); assert.equal((data.focusTask as JsonMap)?.isFocused, true);
  s.projects.set('another-project', { isArchived: true }); assert.equal((taskPage(s, now, {}) as JsonMap).focusTask, null);
});

test('new bot locales translate every reply and use Brazilian Portuguese for variants', () => {
  for (const language of ['pt', 'pt-BR', 'pt-PT', 'ja-JP', 'ko-KR']) {
    const messages = copy(language);
    for (const key of Object.keys(copy('en')) as Array<keyof typeof messages>) assert.notEqual(messages[key], copy('en')[key]);
    assert.equal(launcher(messages, 'https://app.example/telegram/').reply_markup.inline_keyboard[0][0].text, messages.open);
  }
  assert.equal(copy('pt').open, 'Abrir Pomodoist');
  assert.equal(copy('xx'), copy('en'));
});
