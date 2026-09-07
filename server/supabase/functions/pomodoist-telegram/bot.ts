import { type JsonMap, object, stableUuid, TelegramError, validateCommand } from './commands.ts';
import { copy, launcher, type Screen } from './bot_ui.ts';
import type { TelegramStore } from './pomodoist_telegram.ts';
export type TelegramApi = (method: string, body: JsonMap) => Promise<JsonMap>;
export type BotDeps = {
  secret: string; botToken: string; webAppUrl: string; timeZone?: string;
  store: TelegramStore; call: TelegramApi; now?: () => Date;
};
export function isTelegramWebhookRequest(req: Request) {
  return new URL(req.url).pathname.endsWith('/webhook') || req.headers.has('X-Telegram-Bot-Api-Secret-Token');
}
class DeliveryError extends Error {
  constructor(readonly retryable: boolean, readonly cannotEdit = false) { super('telegram_delivery_failed'); }
}
export function createTelegramApi(botToken: string, fetcher: typeof fetch = fetch, apiBaseUrl = 'https://api.telegram.org'): TelegramApi {
  const base = new URL(apiBaseUrl);
  if (base.protocol !== 'https:' || base.hostname !== 'api.telegram.org' || base.pathname !== '/' || base.username || base.password || base.search || base.hash) {
    throw new Error('invalid_telegram_api_base_url');
  }
  return async (method, body) => {
    if (!['sendMessage', 'editMessageText', 'answerCallbackQuery'].includes(method)) throw new Error('unsupported_telegram_method');
    let response: Response;
    try {
      response = await fetcher(new URL(`/bot${botToken}/${method}`, base), { method: 'POST',
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
    const input = typeof message.text === 'string' ? message.text.trim() : '';
    const reply = object(message.reply_to_message);
    const oldPrompt = String(object(reply?.from)?.id) === botId &&
      object(reply?.from)?.is_bot === true && String(reply?.text ?? '').includes('#pomodoist ');
    if (callback || input.startsWith('/') || oldPrompt || !input) {
      await respond(launcher(t, miniAppUrl(deps.webAppUrl)));
    } else {
      const command = { type: 'task.create', content: input,
        id: await stableUuid(`telegram:${botId}:${userId}:update:${update.update_id}`) };
      validateCommand(command);
      const account = await deps.store.identity(userId) ?? await deps.store.bootstrap(userId);
      await deps.store.command(account, command, now);
      await respond(launcher(t, miniAppUrl(deps.webAppUrl), t.added));
    }
    return Response.json({ ok: true });
  } catch (error) {
    if (error instanceof DeliveryError && !error.retryable) return Response.json({ ok: true });
    if (error instanceof TelegramError && error.status < 500) {
      try { await respond(launcher(t, miniAppUrl(deps.webAppUrl), error.code === 'invalid_task_content' ? t.invalid : t.error), true); return Response.json({ ok: true }); }
      catch { /* Retry only with the same mutation receipt id. */ }
    }
    return Response.json({ ok: false, code: 'retry_later' }, { status: 503 });
  }
}
