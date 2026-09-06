import { type JsonMap, object, snapshotOptions, type SnapshotOptions, TelegramError, validateCommand } from './commands.ts';
export { TelegramError } from './commands.ts';
export type TelegramIdentity = { telegramUserId: string; userId: string; guestUserId?: string; clientId: string; linked: boolean };
export type TelegramStore = {
  identity: (telegramUserId: string) => Promise<TelegramIdentity | null>;
  bootstrap: (telegramUserId: string) => Promise<TelegramIdentity>;
  snapshot: (identity: TelegramIdentity, now: Date, options?: SnapshotOptions) => Promise<unknown>;
  command: (identity: TelegramIdentity, command: JsonMap, now: Date, options?: SnapshotOptions) => Promise<unknown>;
  beginLink: (identity: TelegramIdentity, now: Date) => Promise<unknown>;
  completeLink: (token: string, authorization: string, now: Date) => Promise<unknown>;
};
export type PomodoistTelegramDeps = { botToken: string; allowedOrigin: string; store: TelegramStore; now?: () => Date };
export async function handlePomodoistTelegram(req: Request, deps: PomodoistTelegramDeps) {
  const origin = req.headers.get('Origin') ?? '';
  const response = (body: unknown, status: number) => Response.json(body, { status, headers: origin === deps.allowedOrigin ? cors(origin) : { Vary: 'Origin' } });
  if (origin !== deps.allowedOrigin) return response({ ok: false, code: 'origin_forbidden' }, 403);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors(origin) });
  if (req.method !== 'POST') return response({ ok: false, code: 'method_not_allowed' }, 405);
  if (Number(req.headers.get('Content-Length') ?? '0') > 16384) return response({ ok: false, code: 'body_too_large' }, 413);
  let body: JsonMap;
  try {
    const raw = await req.text(); if (new TextEncoder().encode(raw).length > 16384) throw new TelegramError('body_too_large', 413);
    const value = object(JSON.parse(raw)); if (!value) throw new TelegramError('invalid_body'); body = value;
  } catch (error) {
    const failure = error instanceof TelegramError ? error : new TelegramError('invalid_body');
    return response({ ok: false, code: failure.code }, failure.status);
  }
  const now = deps.now?.() ?? new Date();
  try {
    if (body.action === 'complete_link') {
      const token = requiredString(body.token, 'invalid_link_token', 400, 512);
      const authorization = requiredString(req.headers.get('Authorization'), 'authorization_required', 401, 8192);
      return response({ ok: true, data: await deps.store.completeLink(token, authorization, now) }, 200);
    }
    const initData = requiredString(req.headers.get('X-Telegram-Init-Data'), 'telegram_context_required', 401, 8192);
    const verified = await verifyTelegramInitData(initData, deps.botToken, now);
    const identity = await deps.store.identity(verified.userId) ?? await deps.store.bootstrap(verified.userId);
    let data: unknown;
    if (body.action === 'snapshot') data = await deps.store.snapshot(identity, now, snapshotOptions(body));
    else if (body.action === 'command') {
      const command = object(body.command); validateCommand(command); data = await deps.store.command(identity, command, now);
    } else if (body.action === 'begin_link') data = await deps.store.beginLink(identity, now);
    else throw new TelegramError('unsupported_action');
    return response({ ok: true, data }, 200);
  } catch (error) {
    // Infrastructure failures are retryable; a 400 used to discard the Mini App's
    // durable outbox entry even when the database was merely unavailable.
    const failure = error instanceof TelegramError ? error : new TelegramError('request_failed', 503);
    return response({ ok: false, code: failure.code }, failure.status);
  }
}
export async function verifyTelegramInitData(initData: string, botToken: string, now = new Date()) {
  if (!initData || initData.length > 8192 || !botToken) throw new TelegramError('invalid_init_data', 401);
  const params = new URLSearchParams(initData);
  if ([...params.keys()].some(key => params.getAll(key).length !== 1)) throw new TelegramError('invalid_init_data', 401);
  const hash = params.get('hash') ?? ''; params.delete('hash');
  if (!/^[a-f0-9]{64}$/i.test(hash)) throw new TelegramError('invalid_init_data', 401);
  const check = [...params.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([key, value]) => `${key}=${value}`).join('\n');
  const encode = (value: string) => new TextEncoder().encode(value);
  const secret = await hmac(encode('WebAppData'), encode(botToken));
  const expected = hex(await hmac(secret, encode(check)));
  if (!equal(expected, hash.toLowerCase())) throw new TelegramError('invalid_init_data', 401);
  const authDate = Number(params.get('auth_date')), seconds = Math.floor(+now / 1000);
  if (!Number.isInteger(authDate) || authDate > seconds + 30) throw new TelegramError('invalid_init_data', 401);
  if (seconds - authDate > 3600) throw new TelegramError('expired_init_data', 401);
  let user: JsonMap | null = null;
  try { user = object(JSON.parse(params.get('user') ?? '')); } catch { /* Rejected below. */ }
  const id = user?.id;
  if (!['string', 'number'].includes(typeof id) || !/^\d{1,20}$/.test(String(id)) || !Number.isSafeInteger(Number(id)) || Number(id) <= 0) throw new TelegramError('invalid_init_data', 401);
  return { userId: String(id), authDate };
}
async function hmac(key: BufferSource, value: BufferSource) {
  return new Uint8Array(await crypto.subtle.sign('HMAC', await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']), value));
}
function hex(value: Uint8Array) { return [...value].map(byte => byte.toString(16).padStart(2, '0')).join(''); }
function equal(left: string, right: string) {
  if (left.length !== right.length) return false;
  let mismatch = 0; for (let i = 0; i < left.length; i++) mismatch |= left.charCodeAt(i) ^ right.charCodeAt(i);
  return mismatch === 0;
}
function requiredString(value: unknown, code: string, status: number, max: number): string {
  if (typeof value !== 'string' || !value || value.length > max) throw new TelegramError(code, status);
  return value;
}
function cors(origin: string) {
  return { 'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info, x-telegram-init-data',
    'Access-Control-Allow-Methods': 'POST, OPTIONS', Vary: 'Origin' };
}
