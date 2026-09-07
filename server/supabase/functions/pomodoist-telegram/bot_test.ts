import assert from 'node:assert/strict';
import { handleTelegramWebhook, createTelegramApi, isTelegramWebhookRequest, signPrompt } from './bot.ts';
import { actionData, readAction } from './bot_ui.ts';
import { TelegramError } from './commands.ts';
const test = Deno.test;
const secret = 's'.repeat(48), taskId = '11111111-1111-4111-8111-111111111111';
const now = new Date('2026-09-07T12:00:00Z');
function fixture() {
  const calls: { method: string; body: Record<string, any> }[] = [];
  const commands: Record<string, any>[] = [], order: string[] = [];
  const task = { id: taskId, content: '<b>Title & text</b>', description: null, status: 'open', day: '', revision: 4 };
  const snapshot = { account: { linked: false }, tasks: [task], task, total: 1, pages: 1, page: 0, view: 'inbox', focus: null, timeZone: 'UTC' };
  const account = { telegramUserId: '42', userId: 'user', clientId: 'client', linked: false };
  const store = { identity: async () => { order.push('identity'); return account; }, bootstrap: async () => account,
    snapshot: async (_a: unknown, _n: unknown, opts: any = {}) => ({ ...snapshot, ...opts }),
    command: async (_a: unknown, command: any) => { commands.push(command); return snapshot; },
    beginLink: async () => ({ url: 'https://app.example.com/telegram-account-link?token=opaque' }), completeLink: async () => ({ linked: true }) };
  const deps = { secret, botToken: '123:test', webAppUrl: 'https://app.example.com', timeZone: 'UTC', store, now: () => now,
    call: async (method: string, body: Record<string, any>) => { order.push(method); calls.push({ method, body }); return { message_id: 2 }; } };
  return { calls, commands, order, store, snapshot, deps };
}
function message(text: string, extra: any = {}) { return { update_id: 10, message: { message_id: 1, date: +now / 1000, chat: { id: 42, type: 'private' }, from: { id: 42, is_bot: false, language_code: 'ru' }, text, ...extra } }; }
function callback(data: string, extra: any = {}) { return { update_id: 11, callback_query: { id: 'click', from: { id: 42, language_code: 'ru' }, data,
  message: { message_id: 5, date: +now / 1000, chat: { id: 42, type: 'private' }, from: { id: 123, is_bot: true } }, ...extra } }; }
function req(update: unknown, token = secret) { return new Request('https://api.example.com/functions/v1/pomodoist-telegram/webhook', { method: 'POST', headers: { 'X-Telegram-Bot-Api-Secret-Token': token }, body: JSON.stringify(update) }); }
test('webhook detection survives runtimes that strip the path suffix', () => {
  assert.equal(isTelegramWebhookRequest(new Request('https://api.example.com/functions/v1/pomodoist-telegram', { headers: { 'X-Telegram-Bot-Api-Secret-Token': secret } })), true);
  assert.equal(isTelegramWebhookRequest(new Request('https://api.example.com/functions/v1/pomodoist-telegram')), false);
});
test('webhook requires its own secret before touching account storage', async () => {
  const f = fixture(); assert.equal((await handleTelegramWebhook(req(message('/start'), 'wrong'), f.deps)).status, 403); assert.equal(f.order.length, 0);
  assert.equal((await handleTelegramWebhook(req(message('/start')), { ...f.deps, secret: '' })).status, 503);
});
test('group messages and forged cross-chat callbacks never reach account data', async () => {
  const f = fixture(); await handleTelegramWebhook(req(message('secret task', { chat: { id: -1, type: 'group' } })), f.deps);
  await handleTelegramWebhook(req(callback('list:inbox:0', { from: { id: 43 } })), f.deps); assert.equal(f.order.length, 0);
});
test('callbacks are acknowledged before database work', async () => {
  const f = fixture(); await handleTelegramWebhook(req(callback('list:inbox:0')), f.deps); assert.equal(f.order[0], 'answerCallbackQuery');
});
test('ordinary private text creates a task without opening another app', async () => {
  const f = fixture(); assert.equal((await handleTelegramWebhook(req(message('Write tests')), f.deps)).status, 200);
  assert.equal(f.commands[0].type, 'task.create'); assert.equal(f.commands[0].content, 'Write tests');
});
test('redelivered messages and double-clicked buttons keep mutation ids stable', async () => {
  const f = fixture(); await handleTelegramWebhook(req(message('Write tests')), f.deps); await handleTelegramWebhook(req(message('Write tests')), f.deps);
  assert.equal(f.commands[0].id, f.commands[1].id);
  const data = actionData('done', taskId, 4, now);
  await handleTelegramWebhook(req(callback(data)), f.deps);
  await handleTelegramWebhook(req(callback(data, { id: 'different-click' })), f.deps);
  assert.equal(f.commands[2].id, f.commands[3].id); assert.equal(f.commands[2].expectedRevision, 4);
});
test('delete command asks for confirmation and only its confirmation mutates', async () => {
  const f = fixture(); await handleTelegramWebhook(req(message(`/delete ${taskId}`)), f.deps); assert.equal(f.commands.length, 0);
  const body = f.calls.find(c => c.method === 'sendMessage')!.body;
  const confirm = body.reply_markup.inline_keyboard.flat().find((b: any) => b.callback_data.startsWith('yes:'));
  await handleTelegramWebhook(req(callback(confirm.callback_data)), f.deps); assert.equal(f.commands[0].type, 'task.delete');
});
test('Today and Upcoming navigation remains in Telegram and is paginated', async () => {
  for (const view of ['today', 'upcoming', 'completed']) {
    const f = fixture(); await handleTelegramWebhook(req(callback(`list:${view}:2`)), f.deps);
    assert.ok(f.calls.find(c => c.method === 'editMessageText')); assert.equal(f.commands.length, 0);
  }
});
test('task text is sent as plain text, never Telegram HTML', async () => {
  const f = fixture(); await handleTelegramWebhook(req(message(`/task ${taskId}`)), f.deps);
  const body = f.calls.find(c => c.method === 'sendMessage')!.body;
  assert.ok(body.text.includes('<b>Title & text</b>')); assert.equal(body.parse_mode, undefined);
});
test('edit and note commands update only the requested field', async () => {
  const f = fixture(); await handleTelegramWebhook(req(message(`/edit ${taskId} New title`)), f.deps);
  assert.deepEqual(f.commands[0].patch, { content: 'New title' });
  await handleTelegramWebhook(req(message(`/note ${taskId} Some notes`)), f.deps); assert.deepEqual(f.commands[1].patch, { description: 'Some notes' });
});
test('schedule validates an all-day date and rejects nonexistent days', async () => {
  const f = fixture(); await handleTelegramWebhook(req(message(`/schedule ${taskId} 2026-09-08`)), f.deps);
  assert.deepEqual(JSON.parse(f.commands[0].patch.dueJson), { type: 'allDay', date: '2026-09-08' });
  await handleTelegramWebhook(req(message(`/schedule ${taskId} 2026-02-30`)), f.deps); assert.equal(f.commands.length, 1);
});
test('expired action controls never mutate', async () => {
  const f = fixture(); await handleTelegramWebhook(req(callback(actionData('done', taskId, 4, new Date(+now - 3600000)))), f.deps); assert.equal(f.commands.length, 0);
});
test('focus controls are bound to the specific run', async () => {
  const f = fixture(); await handleTelegramWebhook(req(callback(actionData('pause', taskId, 0, now))), f.deps);
  assert.equal(f.commands[0].type, 'focus.pause'); assert.equal(f.commands[0].runId, taskId);
});
test('account linking uses the existing authenticated link flow', async () => {
  const f = fixture(); await handleTelegramWebhook(req(callback('link')), f.deps);
  assert.ok(JSON.stringify(f.calls).includes('telegram-account-link?token=opaque')); assert.equal(f.commands.length, 0);
});
test('transient backend errors request webhook redelivery, without exposing internals', async () => {
  const f = fixture(); f.store.command = async () => { throw new Error('secret database password'); };
  const response = await handleTelegramWebhook(req(message('Write tests')), f.deps);
  assert.equal(response.status, 503); assert.equal((await response.text()).includes('password'), false);
});
test('permanent validation errors give a useful message and stop retries', async () => {
  const f = fixture(); f.store.command = async () => { throw new TelegramError('task_changed', 409); };
  assert.equal((await handleTelegramWebhook(req(message(`/done ${taskId}`)), f.deps)).status, 200);
  assert.ok(f.calls.find(c => c.method === 'sendMessage'));
});
test('rejects oversized streamed bodies even without content-length', async () => {
  const f = fixture(); const r = req({ text: 'a'.repeat(70000) }); assert.equal((await handleTelegramWebhook(r, f.deps)).status, 413); assert.equal(f.order.length, 0);
});
test('all task control data fits Telegram 64-byte limit and round trips', () => {
  for (const action of ['done', 'undo', 'edit', 'note', 'date', 'del', 'yes', 'go', 'pause', 'resume', 'stop', 'finish']) {
    const value = actionData(action, taskId, Number.MAX_SAFE_INTEGER, now); assert.ok(new TextEncoder().encode(value).length <= 64);
    assert.equal(readAction(value, now).id, taskId);
  }
});
test('signed edit replies cannot be forged or moved to another chat', async () => {
  const f = fixture(), issued = Math.floor(+now / 1000);
  const token = await signPrompt('edit', taskId, 4, issued, '42', secret);
  const source = { message_id: 9, date: issued, from: { id: 123, is_bot: true }, text: `Edit\n${token}` };
  await handleTelegramWebhook(req(message('Changed', { reply_to_message: source })), f.deps);
  assert.equal(f.commands[0].type, 'task.update'); assert.equal(f.commands[0].expectedRevision, 4);
  source.text += 'tampered'; await handleTelegramWebhook(req(message('Injected', { reply_to_message: source })), f.deps); assert.equal(f.commands.length, 1);
});
test('HTTP client enforces API ok field and never leaks the bot token', async () => {
  const call = createTelegramApi('123:SECRET', async () => new Response(JSON.stringify({ ok: false, error_code: 429, description: 'rate limit' }), { status: 200 }));
  await assert.rejects(call('sendMessage', { chat_id: 42, text: 'x' }), e => e instanceof Error && !e.message.includes('SECRET'));
});
