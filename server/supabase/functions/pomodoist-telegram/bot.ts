import { type JsonMap, object, snapshotOptions, stableUuid, TelegramError, uuidPattern, validDate, validateCommand } from './commands.ts';
import { copy, errorText, focusScreen, listScreen, messageScreen, navigation, priorityScreen, readAction, type Screen, taskScreen, withNotice } from './bot_ui.ts';
import { Message, shorten } from './bot_format.ts';
import type { TelegramStore } from './pomodoist_telegram.ts';
export type TelegramApi = (method: string, body: JsonMap) => Promise<JsonMap>;
export type BotDeps = {
  secret: string; botToken: string; webAppUrl: string; timeZone?: string;
  store: TelegramStore; call: TelegramApi; now?: () => Date;
};
class DeliveryError extends Error {
  constructor(readonly retryable: boolean, readonly cannotEdit = false) { super('telegram_delivery_failed'); }
}
export function createTelegramApi(botToken: string, fetcher: typeof fetch = fetch): TelegramApi {
  return async (method, body) => {
    if (!['sendMessage', 'editMessageText', 'answerCallbackQuery'].includes(method)) throw new Error('unsupported_telegram_method');
    let response: Response;
    try {
      response = await fetcher(`https://api.telegram.org/bot${botToken}/${method}`, { method: 'POST',
        headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
        signal: AbortSignal.timeout(method === 'answerCallbackQuery' ? 2000 : 10000), redirect: 'error' });
    } catch { throw new DeliveryError(true); }
    const data = object(await response.json().catch(() => null));
    if (!response.ok || data?.ok !== true) {
      const code = Number(data?.error_code ?? response.status);
      if (method === 'editMessageText' && code === 400 && String(data?.description).includes('message is not modified')) return {};
      throw new DeliveryError(code === 429 || code >= 500 || !data, method === 'editMessageText' && code === 400);
    }
    return object(data.result) ?? {};
  };
}
function equal(left: string, right: string) {
  if (left.length !== right.length) return false;
  let mismatch = 0; for (let i = 0; i < left.length; i++) mismatch |= left.charCodeAt(i) ^ right.charCodeAt(i);
  return mismatch === 0;
}
async function boundedJson(req: Request) {
  if (Number(req.headers.get('content-length') ?? 0) > 65536) throw new TelegramError('body_too_large', 413);
  const reader = req.body?.getReader(); if (!reader) throw new TelegramError('invalid_body');
  const chunks: Uint8Array[] = []; let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.byteLength; if (size > 65536) { void reader.cancel(); throw new TelegramError('body_too_large', 413); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const all = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { all.set(chunk, offset); offset += chunk.length; }
  try { const body = object(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(all))); if (body) return body; }
  catch { /* Rejected below without logging content or credentials. */ }
  throw new TelegramError('invalid_body');
}
function safeId(value: unknown) { return typeof value === 'number' && Number.isSafeInteger(value) && value > 0 ? String(value) : null; }
async function signature(text: string, secret: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const bytes = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(text)));
  return [...bytes.slice(0, 16)].map(n => n.toString(16).padStart(2, '0')).join('');
}
export async function signPrompt(kind: string, id: string, revision: number, issued: number, userId: string, secret: string) {
  const payload = `${kind} ${id} ${revision} ${issued}`;
  return `#pomodoist ${payload} ${await signature(`${userId}:${payload}`, secret)}`;
}
async function replyCommand(message: JsonMap, userId: string, botId: string, secret: string, now: Date): Promise<JsonMap | null> {
  const reply = object(message.reply_to_message), sender = object(reply?.from);
  if (!reply || String(sender?.id) !== botId || sender?.is_bot !== true || !String(reply.text ?? '').includes('#pomodoist ')) return null;
  const line = String(reply.text).split('\n').at(-1) ?? '';
  const match = /^#pomodoist (edit|note|date) ([0-9a-f-]{36}) (\d+) (\d+) ([0-9a-f]{32})$/.exec(line);
  if (!match || !uuidPattern.test(match[2]) || !Number.isSafeInteger(Number(match[3])) ||
      +now / 1000 - Number(match[4]) > 900 || Number(match[4]) > +now / 1000 + 30 ||
      !equal(line, await signPrompt(match[1], match[2], Number(match[3]), Number(match[4]), userId, secret))) throw new TelegramError('invalid_prompt', 409);
  return { type: 'task.update', taskId: match[2], expectedRevision: Number(match[3]),
    id: await stableUuid(`telegram-prompt:${botId}:${userId}:${line}`), patch: patchFor(match[1], String(message.text ?? '')) };
}
function patchFor(kind: string, input: string) {
  const value = input.trim();
  if (kind === 'edit') return { content: value };
  if (kind === 'note') return { description: value === 'clear' ? null : value };
  if (value !== 'clear' && !validDate(value)) throw new TelegramError('invalid_task_schedule');
  return { dueJson: value === 'clear' ? null : JSON.stringify({ type: 'allDay', date: value }) };
}
function miniAppUrl(base: string) {
  const url = new URL('/telegram/', base);
  if (url.protocol !== 'https:' || url.username || url.password) throw new TelegramError('invalid_web_app_url', 503);
  return url.href;
}
/** Authenticated private-chat webhook. Mutations use existing account/RPC receipts. */
export async function handleTelegramWebhook(req: Request, deps: BotDeps) {
  if (req.method !== 'POST') return Response.json({ ok: false }, { status: 405 });
  if (!/^[A-Za-z0-9_-]{32,256}$/.test(deps.secret) || !/^\d+:[A-Za-z0-9_-]+$/.test(deps.botToken)) return Response.json({ ok: false, code: 'webhook_not_configured' }, { status: 503 });
  if (!equal(req.headers.get('X-Telegram-Bot-Api-Secret-Token') ?? '', deps.secret)) return Response.json({ ok: false }, { status: 403 });
  let update: JsonMap;
  try { update = await boundedJson(req); }
  catch (e) { return Response.json({ ok: false }, { status: e instanceof TelegramError ? e.status : 400 }); }
  if (!Number.isSafeInteger(update.update_id) || Number(update.update_id) < 0) return Response.json({ ok: false }, { status: 400 });
  const callback = object(update.callback_query), message = object(callback?.message ?? update.message);
  const from = object(callback?.from ?? message?.from), chat = object(message?.chat);
  const userId = safeId(from?.id), chatId = safeId(chat?.id), botId = deps.botToken.split(':')[0];
  if (!message || !from || !userId || userId !== chatId || chat?.type !== 'private' || from.is_bot === true ||
      callback && (String(object(message.from)?.id) !== botId || object(message.from)?.is_bot !== true)) return Response.json({ ok: true });
  const now = deps.now?.() ?? new Date(), t = copy(from.language_code);
  if (callback) {
    try { await deps.call('answerCallbackQuery', { callback_query_id: callback.id }); }
    catch { /* Expired acknowledgements must not prevent idempotent mutations. */ }
  }
  const respond = async (screen: Screen, forceNew = false) => {
    const body = { chat_id: Number(chatId), ...screen, link_preview_options: { is_disabled: true } };
    if (callback && !forceNew) {
      try { await deps.call('editMessageText', { ...body, message_id: message.message_id }); return; }
      catch (error) { if (!(error instanceof DeliveryError) || !error.cannotEdit) throw error; }
    }
    await deps.call('sendMessage', body);
  };
  try {
    const account = await deps.store.identity(userId) ?? await deps.store.bootstrap(userId);
    const snapshot = async (options: JsonMap = {}) => object(await deps.store.snapshot(account, now, snapshotOptions({ timeZone: deps.timeZone ?? 'UTC', ...options }))) ?? {};
    const showList = async (view = 'inbox', page = 0, notice = '') => {
      const screen = listScreen(await snapshot({ view, page }), t, now);
      await respond(notice ? withNotice(screen, notice) : screen);
    };
    const showTask = async (id: string, confirm = false) => {
      const data = await snapshot({ taskId: id }); await respond(taskScreen(object(data.task), t, now, confirm));
    };
    const showAccount = async () => {
      const data = await snapshot(), linked = object(data.account)?.linked === true;
      await respond(messageScreen(t.account, linked ? t.linked : t.guest, [
        ...(!linked ? [[{ text: t.link, callback_data: 'link' }]] : []),
        [{ text: t.open, web_app: { url: miniAppUrl(deps.webAppUrl) } }], ...navigation(t)]));
    };
    const mutate = async (command: JsonMap, receipt?: string) => {
      command.id ??= await stableUuid(`telegram:${botId}:${userId}:${receipt ?? `update:${update.update_id}`}`);
      validateCommand(command);
      const data = object(await deps.store.command(account, command, now, { timeZone: deps.timeZone ?? 'UTC' })) ?? {};
      if (String(command.type).startsWith('focus.')) await respond(focusScreen(data, t, now));
      else if (command.type === 'task.delete') await showList('inbox', 0, t.removed);
      else if (object(data.task)) await respond(taskScreen(object(data.task), t, now));
      else await showList('inbox', 0, t.saved);
    };
    const prompt = async (kind: string, id: string) => {
      const data = await snapshot({ taskId: id }), task = object(data.task);
      if (!task) throw new TelegramError('task_not_found', 404);
      const token = await signPrompt(kind, id, Number(task.revision ?? 0), Math.floor(+now / 1000), userId, deps.secret);
      const explanation = kind === 'edit' ? t.editPrompt : kind === 'note' ? t.notePrompt : t.datePrompt;
      const title = kind === 'edit' ? t.edit : kind === 'note' ? t.note : t.date;
      const message = new Message().add(`Pomodoist · ${title}`, 'bold').add(`\n\n${explanation}`)
        .add(`\n\n${shorten(task.content, 500)}\n`).add(token, 'spoiler');
      await deps.call('sendMessage', { chat_id: Number(chatId), ...message,
        reply_markup: { force_reply: true, selective: true } });
    };
    if (callback) {
      const value = String(callback.data ?? '');
      if (new TextEncoder().encode(value).length > 64) throw new TelegramError('invalid_control');
      if (value.startsWith('list:')) {
        const match = /^list:(inbox|today|upcoming|completed):(\d{1,6})$/.exec(value);
        if (!match) throw new TelegramError('invalid_control'); await showList(match[1], Number(match[2]));
      } else if (value === 'focus') await respond(focusScreen(await snapshot(), t, now));
      else if (value === 'account') await showAccount();
      else if (value === 'new') await respond(messageScreen(t.add, t.newPrompt, navigation(t)), true);
      else if (value === 'link') {
        const link = object(await deps.store.beginLink(account, now));
        const url = new URL(String(link?.url));
        if (url.origin !== new URL(deps.webAppUrl).origin || url.protocol !== 'https:') throw new TelegramError('invalid_link_url', 503);
        await respond(messageScreen(t.account, t.guest, [[{ text: t.link, url: url.href }], ...navigation(t)]));
      } else {
        const action = readAction(value, now);
        if (action.action === 'view' || action.action === 'del') await showTask(action.id, action.action === 'del');
        else if (action.action === 'priority') {
          const data = await snapshot({ taskId: action.id });
          await respond(priorityScreen(object(data.task), t, now));
        } else if (['pone', 'ptwo', 'pthree', 'pfour'].includes(action.action)) {
          await mutate({ type: 'task.update', taskId: action.id, expectedRevision: action.revision,
            patch: { priority: ['pone', 'ptwo', 'pthree', 'pfour'].indexOf(action.action) + 1 } }, value);
        } else if (['edit', 'note', 'date'].includes(action.action)) await prompt(action.action, action.id);
        else if (['pause', 'resume', 'stop', 'finish'].includes(action.action)) await mutate({ type: `focus.${action.action === 'finish' ? 'complete' : action.action}`, runId: action.id }, value);
        else await mutate({ type: ({ done: 'task.complete', undo: 'task.uncomplete', yes: 'task.delete', go: 'focus.start' } as Record<string, string>)[action.action],
          taskId: action.id, expectedRevision: action.revision }, value);
      }
      return Response.json({ ok: true });
    }
    if (typeof message.text !== 'string' || !message.text.trim()) return Response.json({ ok: true });
    const input = message.text.trim();
    if (!input.startsWith('/')) {
      const reply = await replyCommand(message, userId, botId, deps.secret, now);
      await mutate(reply ?? { type: 'task.create', content: input });
      return Response.json({ ok: true });
    }
    const match = /^\/([a-z]+)(?:@[A-Za-z0-9_]+)?(?:\s+([\s\S]*))?$/.exec(input);
    const name = match?.[1] ?? '', argument = match?.[2]?.trim() ?? '';
    if (['start', 'help', 'cancel'].includes(name)) await respond(messageScreen(t.menu, t.help, navigation(t)));
    else if (['inbox', 'today', 'upcoming', 'completed'].includes(name)) await showList(name);
    else if (name === 'account') await showAccount();
    else if (name === 'focus') await respond(focusScreen(await snapshot(), t, now));
    else if (['pause', 'resume', 'stop', 'finish'].includes(name)) {
      const data = await snapshot(), run = object(object(data.focus)?.run);
      if (!run) throw new TelegramError('focus_changed', 409);
      await mutate({ type: `focus.${name === 'finish' ? 'complete' : name}`, runId: run.id });
    } else if (name === 'add') {
      if (!argument) await respond(messageScreen(t.add, t.newPrompt, navigation(t)));
      else await mutate({ type: 'task.create', content: argument });
    } else if (['task', 'delete', 'edit', 'note', 'schedule', 'done', 'undo'].includes(name)) {
      const [id, ...rest] = argument.split(/\s+/), value = rest.join(' ');
      if (!uuidPattern.test(id)) throw new TelegramError('invalid_task_id');
      if (name === 'task' || name === 'delete') await showTask(id, name === 'delete');
      else if (name === 'done' || name === 'undo') await mutate({ type: name === 'done' ? 'task.complete' : 'task.uncomplete', taskId: id });
      else if (!value) await prompt(name === 'schedule' ? 'date' : name, id);
      else await mutate({ type: 'task.update', taskId: id, patch: patchFor(name === 'schedule' ? 'date' : name, value) });
    } else await respond(messageScreen(t.menu, t.help, navigation(t)));
    return Response.json({ ok: true });
  } catch (error) {
    if (error instanceof DeliveryError && !error.retryable) return Response.json({ ok: true });
    if (error instanceof TelegramError && error.status < 500) {
      try { await respond(messageScreen(t.menu, errorText(error.code, t), navigation(t)), true); return Response.json({ ok: true }); }
      catch { /* Retry only with the same mutation receipt id. */ }
    }
    return Response.json({ ok: false, code: 'retry_later' }, { status: 503 });
  }
}
