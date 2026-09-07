import assert from 'node:assert/strict';
import { copy, navigation, taskScreen, listScreen, focusScreen, actionData, readAction } from './bot_ui.ts';
import { taskPage, type JsonMap, type State } from './commands.ts';
const test = Deno.test;
const id = '11111111-1111-4111-8111-111111111111';
const now = new Date('2026-09-07T12:00:00Z');
const task = { id, content: 'Ship <b>release</b> & tests', status: 'open', priority: 1, revision: 4,
  projectId: 'inbox', timeZone: 'Europe/Helsinki', dueJson: null };
const textOf = (value: unknown) => (value as { text: string }).text;
function state(rows: JsonMap[]): State {
  return { tasks: new Map(rows.map(row => [String(row.id), row])), projects: new Map(), focusRuns: new Map(), focusIntervals: new Map(),
    entities: rows.map(row => ({ entityType: 'task', entityId: String(row.id), serverRevision: 4, data: row })) };
}
test('Russian task actions match the app terminology', () => {
  const t = copy('ru-RU');
  assert.equal(t.inbox, 'Входящее'); assert.equal(t.done, 'Завершить');
  assert.equal(t.undo, 'Сделать открытой'); assert.equal(t.note, 'Комментарий'); assert.equal(t.stop, 'Стоп');
});
test('English task actions match the app terminology', () => {
  const t = copy('en'); assert.equal(t.done, 'Mark complete'); assert.equal(t.undo, 'Mark open');
  assert.equal(t.note, 'Comment'); assert.equal(t.finish, 'Complete interval');
});
test('navigation is compact with stable primary, secondary and add rows', () => {
  assert.deepEqual(navigation(copy('en')).map(row => row.map(b => b.callback_data)), [
    ['list:today:0', 'list:upcoming:0', 'list:inbox:0'], ['focus', 'list:completed:0', 'account'], ['new'],
  ]);
});
test('task card distinguishes floating schedule, deadline, priority and project', () => {
  const screen = taskScreen({ ...task, projectId: 'project', projectName: 'Release',
    dueJson: JSON.stringify({ type: 'allDay', date: '2026-09-07' }),
    deadlineJson: JSON.stringify({ type: 'date', date: '2026-09-09T00:00:00.000' }) }, copy('en'), now);
  assert.match(screen.text, /Schedule: Today · All-day/); assert.match(screen.text, /Deadline: 2026-09-09/);
  assert.match(screen.text, /Priority 1/); assert.match(screen.text, /Release/);
  assert.ok(screen.text.includes(task.content)); assert.equal((screen as JsonMap).parse_mode, undefined);
});
test('timed task shows local range and remains current until its end', () => {
  const dueJson = JSON.stringify({ type: 'timed', start: '2026-09-07T11:30:00Z', end: '2026-09-07T12:30:00Z' });
  const screen = taskScreen({ ...task, dueJson }, copy('en'), now);
  assert.match(screen.text, /14:30–15:30/); assert.match(screen.text, /Europe\/Helsinki/); assert.match(screen.text, /In progress/);
  assert.doesNotMatch(screen.text, /Overdue/);
  assert.match(taskScreen({ ...task, dueJson }, copy('en'), new Date('2026-09-07T12:30:00Z')).text, /Overdue/);
});
test('cross-midnight ranges show the ending date', () => {
  const screen = taskScreen({ ...task, timeZone: 'UTC', dueJson: JSON.stringify({ type: 'timed',
    start: '2026-09-07T23:30:00Z', end: '2026-09-08T01:00:00Z' }) }, copy('en'), now);
  assert.match(screen.text, /Today 23:30–Tomorrow 01:00/);
});
test('completed cards suppress overdue warnings and expose only reopen, not start focus', () => {
  const screen = taskScreen({ ...task, status: 'completed', dueJson: JSON.stringify({ type: 'allDay', date: '2026-09-01' }),
    deadlineJson: JSON.stringify({ type: 'date', date: '2026-09-01' }) }, copy('en'), now);
  assert.match(screen.text, /Completed/); assert.doesNotMatch(screen.text, /Overdue/);
  const data = screen.reply_markup.inline_keyboard.flat().map(b => b.callback_data ?? '');
  assert.ok(data.some(v => v.startsWith('undo:'))); assert.ok(!data.some(v => v.startsWith('go:')));
});
test('focus state takes precedence over schedule lateness', () => {
  const screen = taskScreen({ ...task, isFocused: true, dueJson: JSON.stringify({ type: 'timed',
    start: '2026-09-07T10:00:00Z', end: '2026-09-07T11:00:00Z' }) }, copy('en'), now);
  assert.match(screen.text, /In focus/); assert.doesNotMatch(screen.text, /Overdue/);
});
test('long Unicode content is bounded and entities use valid UTF-16 offsets', () => {
  const screen = taskScreen({ ...task, content: '🍅'.repeat(1000), description: '🧪'.repeat(4000) }, copy('ru'), now);
  assert.ok(screen.text.length <= 4096); assert.ok(screen.text.length > 1000);
  const entities = (screen as { entities?: { type: string; offset: number; length: number }[] }).entities;
  assert.ok(entities?.some(e => e.type === 'bold'));
  for (const e of entities!) {
    assert.ok(e.offset >= 0 && e.length > 0 && e.offset + e.length <= screen.text.length);
    assert.doesNotMatch(screen.text.slice(e.offset, e.offset + e.length), /^[\uDC00-\uDFFF]|[\uD800-\uDBFF]$/u);
  }
});
test('delete confirmation separates cancel from the destructive action', () => {
  const screen = taskScreen(task, copy('en'), now, true);
  const row = screen.reply_markup.inline_keyboard[0];
  assert.equal(row[0].text, 'Cancel'); assert.ok(row[0].callback_data?.startsWith('view:'));
  assert.equal(row[1].text, 'Delete'); assert.ok(row[1].callback_data?.startsWith('yes:'));
});
test('list previews show status and priority while buttons keep titles on one line', () => {
  const screen = listScreen({ view: 'today', page: 0, pages: 1, total: 1, timeZone: 'UTC', tasks: [
    { ...task, content: 'Release\n\nnotes', dueJson: JSON.stringify({ type: 'allDay', date: '2026-09-06' }) },
  ] }, copy('en'), now);
  assert.match(screen.text, /Release notes/); assert.match(screen.text, /P1/); assert.match(screen.text, /Overdue/);
  assert.ok(screen.reply_markup.inline_keyboard.flat().every(b => !b.text.includes('\n')));
});
test('empty views use different app-aligned copy', () => {
  const render = (view: string) => listScreen({ view, tasks: [], total: 0 }, copy('ru'), now).text;
  assert.match(render('inbox'), /Здесь нет задач/); assert.match(render('today'), /На этот день задач нет/);
  assert.match(render('upcoming'), /Нет задач с датой/);
});
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
test('Focus shows linked task, paused status, phase and accurate remaining time', () => {
  const screen = focusScreen({ focusTask: task, focus: { run: { id }, interval: { status: 'paused',
    startedAt: '2026-09-07T11:50:00Z', pausedAt: '2026-09-07T11:55:00Z', pausedTotalSeconds: 60, plannedSeconds: 1500 } } }, copy('en'), now);
  assert.match(screen.text, /21:00/); assert.match(screen.text, /Paused/); assert.match(screen.text, /Work/);
  assert.ok(screen.text.includes(task.content));
  assert.ok(!screen.reply_markup.inline_keyboard.flat().some(b => b.callback_data?.startsWith('finish:')));
});
test('idle Focus uses the same session naming as the app', () => {
  assert.match(textOf(focusScreen({}, copy('ru'), now)), /Нет активной сессии/);
});
test('priority controls preserve the existing revision and 64-byte limit', () => {
  for (const action of ['priority', 'pone', 'ptwo', 'pthree', 'pfour']) {
    const value = actionData(action, id, Number.MAX_SAFE_INTEGER, now);
    assert.ok(new TextEncoder().encode(value).length <= 64); assert.equal(readAction(value, now).action, action);
  }
});

import { handleTelegramWebhook } from './bot.ts';
import type { BotDeps } from './bot.ts';
function webhookFixture() {
  const calls: { method: string; body: JsonMap }[] = [], commands: JsonMap[] = [];
  const account = { telegramUserId: '42', userId: 'user', clientId: 'client', linked: false };
  const data = { tasks: [], total: 0, task, focus: null, account: { linked: false } };
  const deps: BotDeps = { secret: 's'.repeat(48), botToken: '123:test', webAppUrl: 'https://app.example.com', now: () => now,
    store: { identity: async () => account, bootstrap: async () => account,
      snapshot: async (_a, _n, options) => ({ ...data, ...options }),
      command: async (_a, command) => { commands.push(command); return data; },
      beginLink: async () => ({ url: 'https://app.example.com/telegram-account-link?token=opaque' }), completeLink: async () => ({ linked: true }) },
    call: async (method, body) => { calls.push({ method, body }); return { message_id: 2 }; } };
  async function send(text: string, callback = false, extra: JsonMap = {}) {
    const from = { id: 42, language_code: 'ru', is_bot: false };
    const message = { message_id: 5, from, chat: { id: 42, type: 'private' }, text, ...extra };
    const update = callback ? { update_id: 10, callback_query: { id: 'cb', data: text, from,
      message: { ...message, from: { id: 123, is_bot: true } } } } : { update_id: 11, message };
    return handleTelegramWebhook(new Request('https://app.example.com/webhook', { method: 'POST',
      headers: { 'X-Telegram-Bot-Api-Secret-Token': deps.secret }, body: JSON.stringify(update) }), deps);
  }
  const last = () => calls.filter(c => c.method !== 'answerCallbackQuery').at(-1)!.body as unknown as
    { text: string; entities: { type: string; offset: number; length: number }[]; reply_markup: { inline_keyboard: { text: string; callback_data: string }[][]; force_reply?: boolean } };
  return { calls, commands, deps, send, last };
}
test('priority picker is read-only, selection writes only priority with a stable receipt', async () => {
  const f = webhookFixture(); await f.send(actionData('priority', id, 4, now), true);
  assert.equal(f.commands.length, 0); assert.match(f.last().text, /Выберите приоритет/);
  const selection = f.last().reply_markup.inline_keyboard[0][1].callback_data;
  await f.send(selection, true); await f.send(selection, true);
  assert.equal(f.commands.length, 2); assert.deepEqual(f.commands[0].patch, { priority: 2 });
  assert.equal(f.commands[0].expectedRevision, 4); assert.equal(f.commands[0].id, f.commands[1].id);
  assert.equal(f.calls[0].method, 'answerCallbackQuery');
});
test('static screens share the same branded hierarchy and compact footer', async () => {
  for (const command of ['/start', '/help', '/account', '/add']) {
    const f = webhookFixture(); await f.send(command);
    assert.match(f.last().text, /^Pomodoist · /); assert.ok(f.last().entities.some(e => e.type === 'bold'));
    assert.deepEqual(f.last().reply_markup.inline_keyboard.slice(-3), navigation(copy('ru')));
  }
});
test('task errors use the same screen hierarchy without exposing internals', async () => {
  const f = webhookFixture(); await f.send('/task invalid-id');
  assert.match(f.last().text, /^Pomodoist · /); assert.ok(f.last().entities.length > 0); assert.equal(f.commands.length, 0);
});
test('deletion notice shifts all entity offsets without corrupting the list heading', async () => {
  const f = webhookFixture(); await f.send(actionData('yes', id, 4, now), true);
  const screen = f.last(), heading = screen.entities.find(e => e.type === 'bold')!;
  assert.match(screen.text, /^Задача удалена/);
  assert.match(screen.text.slice(heading.offset, heading.offset + heading.length), /^Pomodoist · /);
});
test('formatted edit prompts preserve authenticated reply tokens and literal titles', async () => {
  const f = webhookFixture(); await f.send(actionData('edit', id, 4, now), true);
  const prompt = f.last(); assert.equal(prompt.reply_markup.force_reply, true);
  assert.match(prompt.text, /^Pomodoist · /); assert.ok(prompt.text.includes(task.content));
  const metadata = prompt.entities.find(e => e.type === 'spoiler')!;
  assert.ok(metadata); assert.equal(prompt.text.slice(metadata.offset, metadata.offset + metadata.length), prompt.text.split('\n').at(-1));
  await f.send('Updated', false, { reply_to_message: { text: prompt.text, from: { id: 123, is_bot: true } } });
  assert.deepEqual(f.commands[0].patch, { content: 'Updated' }); assert.equal(f.commands[0].expectedRevision, 4);
});
test('floating dates and deadlines do not shift at a UTC day boundary', () => {
  const screen = taskScreen({ ...task, dueJson: JSON.stringify({ type: 'allDay', date: '2026-09-07' }),
    deadlineJson: JSON.stringify({ type: 'date', date: '2026-09-08T00:00:00.000' }) }, copy('en'), new Date('2026-09-07T22:30:00Z'));
  assert.match(screen.text, /Schedule: Yesterday · All-day/); assert.match(screen.text, /Deadline: Today/);
});
test('malformed optional metadata cannot break the card', () => {
  const screen = taskScreen({ ...task, dueJson: '{bad', deadlineJson: '[]', priority: 9, timeZone: 'invalid/zone' }, copy('fr'), now);
  assert.match(screen.text, /No date/); assert.match(screen.text, /Priority 4/); assert.doesNotMatch(screen.text, /Invalid Date|undefined|NaN/);
});
test('elapsed Focus exposes completion while zeroing the displayed clock', () => {
  const screen = focusScreen({ focus: { run: { id }, interval: { status: 'running', startedAt: '2026-09-07T11:00:00Z', plannedSeconds: 1500 } } }, copy('en'), now);
  assert.match(screen.text, /00:00/); assert.match(screen.text, /Ready/);
  assert.ok(screen.reply_markup.inline_keyboard.flat().some(b => b.callback_data?.startsWith('finish:')));
});
