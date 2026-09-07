import assert from 'node:assert/strict';
import { handleTelegramWebhook, createTelegramApi, isTelegramWebhookRequest } from './bot.ts';
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
test('redelivered messages keep their mutation receipt, while confirmations only open Mini App', async () => {
  const f = fixture();
  for (let i = 0; i < 2; i++) await handleTelegramWebhook(req(message('Write tests')), f.deps);
  assert.equal(f.commands[0].id, f.commands[1].id);
  const body = f.calls.find(c => c.method === 'sendMessage')!.body;
  assert.deepEqual(body.reply_markup.inline_keyboard, [[{ text: 'Открыть Pomodoist', web_app: { url: 'https://app.example.com/telegram/' } }]]);
});
test('all old commands and callbacks redirect to Mini App without mutating or reading account data', async () => {
  for (const input of ['/start', '/help', '/add Task', '/today', '/upcoming', '/completed', '/account', '/focus', '/pause', '/resume', '/stop', '/finish', `/done ${taskId}`, `/delete ${taskId}`, `/edit ${taskId} New`, `/note ${taskId} Note`, `/schedule ${taskId} 2026-09-08`]) {
    const f = fixture(); await handleTelegramWebhook(req(message(input)), f.deps);
    assert.equal(f.commands.length, 0); assert.ok(!f.order.includes('identity'));
    assert.equal(f.calls[0].body.reply_markup.inline_keyboard[0][0].web_app.url, 'https://app.example.com/telegram/');
  }
  for (const input of ['list:today:0', 'link', 'account', 'new', `done:${taskId}`, `yes:${taskId}`, `pause:${taskId}`]) {
    const f = fixture(); await handleTelegramWebhook(req(callback(input)), f.deps);
    assert.equal(f.commands.length, 0); assert.equal(f.order[0], 'answerCallbackQuery');
    assert.ok(!f.order.includes('identity'));
    assert.equal(f.calls.at(-1)!.body.reply_markup.inline_keyboard[0][0].web_app.url, 'https://app.example.com/telegram/');
  }
});
test('replies to old bot edit prompts do not accidentally edit or create a task', async () => {
  const f = fixture();
  await handleTelegramWebhook(req(message('Changed', { reply_to_message: { from: { id: 123, is_bot: true }, text: `Edit\n#pomodoist edit ${taskId} 4 123 fake-signature` } })), f.deps);
  assert.equal(f.commands.length, 0);
  assert.equal(f.calls[0].body.reply_markup.inline_keyboard[0][0].web_app.url, 'https://app.example.com/telegram/');
});
test('task input stays literal, including HTML and multiline text', async () => {
  const f = fixture(); await handleTelegramWebhook(req(message('<b>Title & text</b>\nSecond line')), f.deps);
  assert.equal(f.commands[0].content, '<b>Title & text</b>\nSecond line');
  assert.equal(f.calls[0].body.parse_mode, undefined);
});
test('transient backend errors request webhook redelivery, without exposing internals', async () => {
  const f = fixture(); f.store.command = async () => { throw new Error('secret database password'); };
  const response = await handleTelegramWebhook(req(message('Write tests')), f.deps);
  assert.equal(response.status, 503); assert.equal((await response.text()).includes('password'), false);
});
test('permanent validation errors give a useful message and stop retries', async () => {
  const f = fixture(); f.store.command = async () => { throw new TelegramError('task_changed', 409); };
  assert.equal((await handleTelegramWebhook(req(message('Task')), f.deps)).status, 200);
  assert.ok(f.calls.find(c => c.method === 'sendMessage'));
});
test('rejects oversized streamed bodies even without content-length', async () => {
  const f = fixture(); const r = req({ text: 'a'.repeat(70000) }); assert.equal((await handleTelegramWebhook(r, f.deps)).status, 413); assert.equal(f.order.length, 0);
});
test('HTTP client enforces API ok field and never leaks the bot token', async () => {
  const call = createTelegramApi('123:SECRET', async () => new Response(JSON.stringify({ ok: false, error_code: 429, description: 'rate limit' }), { status: 200 }));
  await assert.rejects(call('sendMessage', { chat_id: 42, text: 'x' }), e => e instanceof Error && !e.message.includes('SECRET'));
});
test('HTTP client accepts the Telegram host on a staging port and rejects other hosts', async () => {
  let target = '';
  const call = createTelegramApi('123:SECRET', async input => {
    target = String(input); return new Response(JSON.stringify({ ok: true, result: {} }));
  }, 'https://api.telegram.org:14443');
  await call('sendMessage', { chat_id: 42, text: 'x' });
  assert.equal(target, 'https://api.telegram.org:14443/bot123:SECRET/sendMessage');
  assert.throws(() => createTelegramApi('123:SECRET', fetch, 'https://example.com'));
});
